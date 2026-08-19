# Rest Timer Alarm — Scoping

**Date:** 2026-08-18
**Branch:** NewMain (`42076bc` + uncommitted)
**Status:** **D1–D6 implemented 2026-08-18** — see §15. **D7 (instrumentation) deliberately not
done**: it turns on a §13.4 privacy decision that is still unanswered. D3 needs provisioning work
that is not mine to do — §15.3.
Suite **504, 0 failures, 4 skipped** (22 added here; the total also absorbed an 11-test net
change from in-flight `BaselineMeterView` work that earlier runs were compiling stale — §15.5).
**Trigger:** audit request, not a user report. No crash, no data loss — the failure mode is
*silence*, which is why it has almost certainly been happening in production without a support
ticket. A missed rest alarm looks like the user's own fault.

The state machine, pause/resume, background recalculation and analytics triggers are correct and
are not the subject of this document (§9 lists what was checked and passed). What follows is about
the alarm — whether the user is actually told.

---

## 0. Conclusions — read this first

1. **Three independent situations end in no alert at all**, and one more is silenced by a setting
   most lifters have on. The alarm is only reliable when the workout screen is on top *and* the app
   is foreground. §1.
2. **The root cause is ownership.** The alarm lives on a view-scoped `@State` ViewModel, so closing
   the workout cover kills it. §2.
3. **The local notification cannot cover for it**, because no `UNUserNotificationCenterDelegate`
   is ever set and iOS's default is to suppress foreground notifications. §3.
4. **Notification permission is requested at the worst possible moment**, the answer is discarded,
   and it is never checked again — while one code path explicitly assumes it was granted. §4.
5. **`.active` interruption level means any Focus mode silences the alarm.** Focus during a workout
   is the normal case, not an edge case. §5.
6. **The Live Activity never announces that rest is over.** It freezes on a spent countdown and
   the "REST COMPLETE" treatment it already ships is unreachable from the background. Fixable
   entirely in the widget, no push server. §6.
7. **Two teardown paths can fire "Rest period is over" for a workout that no longer exists.** §7.
8. **The suite covers none of this** — two unit tests on a string helper, nothing on the finish
   transition, the notification, or the alarm. §10.

The fixes are small and mostly independent. §11 sequences them; §13 is what I need from you.

---

## 1. The four channels and when each actually works

| # | Channel | Implemented | Requires |
|---|---|---|---|
| A | In-app `fireTimerAlert()` — `AudioServicesPlaySystemSound` + `UINotificationFeedbackGenerator` ([ActiveWorkoutViewModel.swift:1444](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1444)) | ✅ | ViewModel alive **and** app foreground |
| B | Local notification, `UNTimeIntervalNotificationTrigger` ([:1462](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1462)) | ✅ | permission granted, app **not** foreground, no Focus |
| C | Live Activity visual (Lock Screen / Dynamic Island) | ✅ | a push while the app executes |
| D | Live Activity `alertConfiguration` (haptic + banner + Watch) | ❌ | see §6.3 — needs the app to be executing |

Run every realistic scenario through that:

| | Scenario | A | B | C | Outcome |
|---|---|---|---|---|---|
| S1 | Workout screen up, app foreground | ✅ | suppressed by iOS | n/a | **works** |
| S2 | App backgrounded or phone locked | dead | ✅ | shows 0:00 → §6.2 | **works** (sound only) |
| S3 | **App foreground, workout cover dismissed** (Home/History/Settings tab) | dead — §2 | suppressed — §3 | stale | **SILENT** |
| S4 | **Notification permission denied** | dead when backgrounded | never fires | stale | **SILENT** |
| S5 | **Any Focus mode on, app backgrounded** | dead | delivered quietly — §5 | stale | **effectively SILENT** |
| S6 | App force-quit mid-rest | dead | ✅ (OS-scheduled, survives) | activity ends at relaunch | **works** |
| S7 | Timer ends backgrounded, user glances at Lock Screen | dead | fired already | frozen **0:00** — §6.2 | **no completion signal** |

S3, S4 and S5 are not exotic. **S3 is the back button** — see §2. S4 is anyone who dismissed a
permission prompt that appeared before they had seen the app. S5 is anyone who turns on a Focus
mode to train.

---

## 2. Why the in-app alert dies — S3

`ActiveWorkoutView` is presented as a `fullScreenCover` ([ContentView.swift:224](Repster/App/ContentView.swift:224))
and constructs the ViewModel as its own `@State`:

```swift
// ActiveWorkoutView.swift:74
_viewModel = State(initialValue: ActiveWorkoutViewModel(…))
```

Dismissing the cover releases the view, which releases the ViewModel, which deallocates
`timerSubscription` (`AnyCancellable`) and cancels the `Timer.publish`. `timerTick()` never reaches
zero, so `fireTimerAlert()` is never called.

### 2.1 It is the back button, not a corner case

The affordance that triggers this is the top-left chevron in the workout header:

```swift
// ActiveWorkoutView.swift:368-371
// Back / dismiss button
Button {
    dismiss()
}
```

No confirmation, no teardown, and the workout deliberately stays active — ContentView has a full
resume path with its own analytics event ([:305-306](Repster/App/ContentView.swift:305)). So S3 is
reached by the most-tapped control in iOS, doing exactly what it is designed to do.

`ActiveWorkoutView` has **no `onDisappear` at all**, so nothing observes the departure. The only
other `dismiss()` is the post-finish one at [:169](Repster/Features/Workout/Views/ActiveWorkoutView.swift:169).

### 2.2 The state survives; only the alert is lost

This is a supported flow, not an accident — the persistence layer exists precisely for it:

```swift
// ActiveWorkoutViewModel.swift:382
// 8. Restore persisted workout clock and rest timer state (survives view dismissal).
```

`restoreRestTimerState` correctly recomputes from `restTimerStartDate` on return and lands on
`.finished` if the timer expired ([:1372-1381](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1372)).
So the *state* survives the round trip perfectly — come back after the timer expired and the band
correctly reads "Rest complete". Only the alert in between is lost.

---

## 3. Why the notification can't cover for it — S3

`grep -rn "UNUserNotificationCenterDelegate\|willPresent" Repster/` returns nothing. No delegate is
set anywhere. iOS's default when no delegate implements
`userNotificationCenter(_:willPresent:withCompletionHandler:)` is to **not** present a notification
that arrives while the app is foreground — it is filed silently into Notification Center with no
banner, no sound, no haptic.

So in S3 the notification *is* delivered, correctly, on time — and the user is told nothing. They
find it later by pulling down Notification Center, which is not an alarm.

This is a single missing object. It is also the highest-leverage fix in the document.

---

## 4. Permission is requested badly and never verified — S4

### 4.1 What happens today

```swift
// RepsterApp.swift:73
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
```

- It runs inside `App.init()`, so the system prompt appears at **cold start, before onboarding
  renders**. The user is asked to allow notifications by an app they have not seen a screen of.
- The result is discarded — `{ _, _ in }`.
- Nothing anywhere calls `getNotificationSettings`. `center.add(request)` then fails silently on
  every rest timer, forever.
- There is no Settings surface saying the alarm can't reach them, and no way to re-prompt (iOS only
  shows the system prompt once; recovery is a deep link to Settings).

### 4.2 The compounding bug

[ActiveWorkoutViewModel.swift:1233-1236](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1233):

```swift
// Don't fire the in-app alert here — the background notification
// already alerted the user while the app was suspended.
cancelRestTimerNotification()
```

The reasoning is right *when the notification fired*. For a denied user it did not, so this
suppression converts "no background alert" into "no alert at all, ever, on the background path."
The one place that could still rescue them is the place that deliberately stays quiet.

### 4.3 The app already knows how to do this properly

HealthKit is the precedent and it is a good one — pre-permission UI, a skippable onboarding step,
a Settings row with live status, a recovery message naming the exact Settings path, and analytics
on both halves of the funnel:

| | Apple Health | Notifications |
|---|---|---|
| Pre-permission explanation | [AppleHealthConnectionModel](Repster/Features/Health/AppleHealthConnectionModel.swift), onboarding step ([OnboardingStep.swift:16](Repster/Features/Onboarding/OnboardingStep.swift:16)) | none |
| Result captured | `HealthKitAuthorizationResult` ([HealthKitServiceProtocol.swift:9](Repster/Core/Services/Protocols/HealthKitServiceProtocol.swift:9)) | discarded |
| Status readable synchronously | `isAvailable` / `isAuthorized` | not read |
| Settings row with state | [SettingsView.swift:329-331](Repster/Features/Settings/Views/SettingsView.swift:329) | none |
| Recovery copy | names Health → Sharing → Apps → Repster | none |
| Analytics | `appleHealthPromptShown` / `…Answered` | none |

Notifications carry a *harder* dependency than HealthKit — HealthKit failing loses a mirrored
workout, notifications failing breaks a core in-workout feature — and get none of the same care.

---

## 5. Focus modes silence it — S5

[ActiveWorkoutViewModel.swift:1466-1474](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1466)
never sets `content.interruptionLevel`, so it defaults to `.active`. Under any Focus mode, an
`.active` notification from a non-allowed app is delivered quietly — no sound, no banner.

`.timeSensitive` is the level designed for exactly this ("a timer you set has ended") and breaks
through Focus unless the user specifically turns Time Sensitive off for Repster. It requires the
`com.apple.developer.usernotifications.time-sensitive` entitlement, which is **not** present —
[Repster.entitlements](Repster/Repster.entitlements) carries only the two HealthKit keys.

Adding it means an entitlement change and a provisioning profile regeneration. It is not a code-only
fix, and it needs to be in place before the build that depends on it goes to TestFlight.

---

## 6. The Live Activity — S7

### 6.1 What it should be

The Lock Screen is where a resting lifter is actually looking. It is also the only channel that
works with notifications denied. Today it is the weakest of the three.

### 6.2 The expired timer is never announced

> **Corrected.** This section first claimed the Lock Screen falls through to **"Ready for next
> set"**. That is reachable but not what usually happens, and the claim contradicted my own
> reasoning in D4. Both outcomes are wrong in the same way and the fix is unchanged, but the
> severity is lower than first stated — see the end of this section.

`isRestTimerFinished` is only ever set from `timerTick()`, which requires the app to be executing.
While the app is suspended no push happens, so the widget still holds `isRestTimerRunning == true`
with a `restTimerEndDate` now in the past. Meanwhile:

```swift
// WorkoutLiveActivityLiveActivity.swift:388-395
guard state.isRestTimerRunning, let endDate = state.restTimerEndDate else { return nil }
let now = Date.now
guard endDate > now else { return nil }
```

`restCountdownRange` returns `nil` once the end date passes, and the lock-screen chain
([:139-225](WorkoutLiveActivity/WorkoutLiveActivityLiveActivity.swift:139)) is:

```
if isWorkoutPaused … else if isRestTimerPaused … else if let countdown = restCountdownRange …
else if isRestTimerFinished … else { "Ready for next set" }
```

**But that guard only re-runs if the view body is re-evaluated**, and nothing triggers one:
a new push is impossible while suspended, and `staleDate` is `nil`
([LiveActivityManager.swift:184](Repster/Features/Workout/Models/LiveActivityManager.swift:184)),
so the system has been given no date at which to reload. `Text(timerInterval:countsDown:)` is
animated by the system without re-rendering, so it simply counts to **0:00 and stops there**.

So the realistic outcome is a **frozen spent countdown reading "0:00 remaining"**. The
"Ready for next set" branch is reachable — a system-initiated reload (Lock Screen wake, Dynamic
Island expansion) re-evaluates the body and drops it there — but it is not deterministic, and I
should not have stated it as the symptom.

**What this changes:** a spent 0:00 does read as "rest is over", so this is *not* actively
misleading the way "Ready for next set" would be. The real defect is narrower — **the
"REST COMPLETE" treatment that already exists at
[:194-213](WorkoutLiveActivity/WorkoutLiveActivityLiveActivity.swift:194) is unreachable from the
background**, so the Lock Screen never gives a positive go signal, and the Dynamic Island chain
([:268-296](WorkoutLiveActivity/WorkoutLiveActivityLiveActivity.swift:268)) has the same gap.

That lowers D4's priority (§12) but not its cost — and `restTimerEndDate` is already in
`ContentState` ([WorkoutActivityAttributes.swift:60](Repster/Features/Workout/Models/WorkoutActivityAttributes.swift:60)),
so the widget still has everything it needs. Setting `staleDate` to the end date is what supplies
the missing re-render; that is the whole mechanism, and §6.3 and D4 already described it correctly.

### 6.3 `alertConfiguration` — recommend **not** doing this

The obvious-looking fix is to pass an `AlertConfiguration` on the finishing update so the Lock
Screen buzzes. It is close to worthless here: `activity.update(...)` only runs when the app is
executing, which is precisely the case where channel A already alerts. Updating a Live Activity
from a suspended app needs ActivityKit **push** tokens and a server to push from, and Repster has
no backend.

Include it if it's free once §6.2 is in hand, but do not count it as covering S2/S4/S5.

---

## 7. Stale notifications outlive their workout

`restTimerNotificationId` is `private static` on the ViewModel
([:1460](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1460)), so nothing outside
that type can cancel a pending alarm. Two paths tear a workout down from outside it:

| Path | Clears the 6 UserDefaults keys | Cancels the notification |
|---|---|---|
| `ContentView.discardActiveAndCopy()` ([:582](Repster/App/ContentView.swift:582)) | ❌ | ❌ |
| `SettingsService.clearStoredAppState()` ([:224-235](Repster/Core/Services/SettingsService.swift:224)) | ✅ all six | ❌ |

Discard mid-rest and minutes later the phone says *"Rest period is over — time for your next set!"*
for a workout that was thrown away. `clearStoredAppState` is the more embarrassing of the two — it
was clearly written with the rest timer in mind and got five of six things right.

---

## 8. Lower severity

**L1 — "Vibration" plays a sound in the background.** [:1471](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1471)
attaches `.default` for `"vibration"`, and the helper documents why: a soundless notification
produces no haptic either, so the choice is sound-or-nothing. It is the right trade —
`.default` respects the ringer switch, so on silent it genuinely is vibration only — but with the
ringer on, the setting does not do what its label says. Wants a footer line in Settings, not a code
change.

**L2 — `subtractTime` desyncs the two clocks.** [:1128-1150](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1128)
clamps `newRemaining` and `newTotal` to 1 independently without touching `timerStartDate`. Subtract
15s at 0:05 → the band reads 0:01 while `recalculateTimerAfterBackground` computes `total - elapsed`
= −10 and finishes at once. Both paths end finished, so it is cosmetic, but the displayed value and
the authoritative value disagree, and the notification is scheduled from the displayed one.

**L3 — four sources disagree on the default `restTimerAlert`.**

| Source | Says |
|---|---|
| `HealthProfile` doc comment ([:18](Repster/Data/Models/HealthProfile.swift:18)) | `"both"` |
| `HealthProfile` memberwise init ([:81](Repster/Data/Models/HealthProfile.swift:81)) | `"vibration"` |
| ViewModel ([:378](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:378)) | `"both"` |
| Settings picker ([SettingsView.swift:771](Repster/Features/Settings/Views/SettingsView.swift:771)) | `"both"` |
| Settings summary row ([SettingsViewModel.swift:120](Repster/Features/Settings/ViewModels/SettingsViewModel.swift:120)) | `"vibration"` |

The model's own doc comment contradicts the initialiser three lines below it.

**And the `nil` case is real, not theoretical.** `restTimerAlert` is an optional attribute added in
`045b10b`, after the initial commit — so every profile created before that release holds `nil`
today. `HealthProfileRepository.fetchOrCreate()` ([:43-48](Repster/Core/Repositories/HealthProfileRepository.swift:43))
doesn't pass the argument, so *fresh* profiles take `"vibration"` and are self-consistent; migrated
ones see a Settings row reading **"Vibration"** that opens a picker showing **"Both"**, with actual
behaviour "Both". One constant, five readers.

---

## 9. What was checked and is correct

Worth recording so it isn't re-audited:

- **No double-alert is possible.** `fireTimerAlert()` cancels the pending request
  ([:1454](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1454)), and a
  notification that beats the tick is suppressed in the foreground anyway.
- **`addTime` is correct.** It deliberately leaves `timerStartDate` alone, so `total` growing by 15
  makes the background recalculation agree with the display. (Contrast L2.)
- **The notification is replaced, not duplicated** — `removePendingNotificationRequests` before
  every `add`, same identifier ([:1467](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1467)).
- **Pause/resume is right** in all four transitions, including workout-pause vs. manual-pause
  provenance, and cancels/reschedules the notification correctly.
- **Restore-from-persistence is right**, including the `.workout`-paused-but-workout-now-running
  case ([:1355](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1355)).
- **The analytics triggers are accurate.** `restTimerSkips` fires only on hand-dismissal at
  [ActiveWorkoutView.swift:328](Repster/Features/Workout/Views/ActiveWorkoutView.swift:328) rather
  than inside `dismissTimer()`, which is also the internal cleanup path for finish/discard/set
  completion — the comment there and at
  [AnalyticsServiceProtocol.swift:246](Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift:246)
  both call this out. `restTimerAdjusts` covers all three adjust affordances. Nothing is
  double-counted and nothing is missed.
- **The alert mode can't go stale mid-workout.** It is read once in `loadActiveWorkout()`, but
  Settings is only reachable by dismissing the cover, which rebuilds the ViewModel.

---

## 10. Decisions

### D1 — Set a notification delegate, and gate foreground presentation on whether the in-app handler is live

Fixes **S3**. The cheapest and highest-value change in the document.

A delegate that unconditionally presents would drop a banner over the workout screen after every
single set — lifters would hate it, and channel A already handles that case. So the rule is:

> Present the notification in the foreground **unless** the active workout screen is on top and
> will alert in-app.

Shape: a small app-scoped `RestTimerAlarmCoordinator` (`@MainActor`, one `Bool`), set true from
`ActiveWorkoutView.task` and false from `.onDisappear`; the delegate returns
`[]` when it's true and `[.banner, .sound, .list]` when it's false. The flag is only ever consulted
in the foreground, so backgrounding — which doesn't fire `.onDisappear` — is irrelevant.

The delegate object also wants `didReceive` so tapping the notification re-presents the workout
cover. That is a genuine improvement and near-free once the object exists, but call it optional.

**Rejected alternative:** hoisting the whole rest timer into an app-scoped observable so the tick
survives cover dismissal. It fixes S3 too, but it is a much larger change to a state machine that
is currently correct, and it does nothing for S4 or S5. Not worth the blast radius.

### D2 — Request permission contextually, keep the answer, and stop assuming it

Fixes **S4**. Four parts:

1. **Move the request out of `App.init()`.** Ask the first time a rest timer actually starts —
   the one moment the user has just seen a countdown appear and the reason is self-evident.
   Follow `AppleHealthConnectionModel`: our own explanation first, the system prompt only on an
   explicit tap, so a "not now" leaves iOS's one-shot prompt unspent.
2. **Store the result** and re-read `getNotificationSettings` on foreground.
3. **Make §4.2 conditional.** `recalculateTimerAfterBackground` should fire the in-app alert on
   return *when we know nothing else did* — i.e. when authorization is not granted. Late is
   dramatically better than never.
4. **Surface it in Settings.** A status line under Timer Alert when denied, with the Settings deep
   link, matching the Apple Health row's shape.

**Open question for you (§13.2):** whether to add an onboarding step. My read is no — onboarding is
already four screens and rest alarms mean nothing to someone who has not logged a set. Contextual
at first timer is both better-converting and better-mannered.

### D3 — `.timeSensitive` + the entitlement

Fixes **S5**. `content.interruptionLevel = .timeSensitive` plus
`com.apple.developer.usernotifications.time-sensitive` in
[Repster.entitlements](Repster/Repster.entitlements). Needs the App ID capability enabled and
profiles regenerated — same operational shape as the outstanding HealthKit App ID work, and worth
doing in the same sitting.

### D4 — Make the widget announce the expired timer

Fixes **S7**. Per the correction in §6.2 this is "the Lock Screen never says rest is done" rather
than "the Lock Screen lies", so it is a polish fix on the most-looked-at surface, not a defect fix.
Two edits:

1. `LiveActivityManager.updateActivity` passes `staleDate: restTimerEndDate` instead of `nil`
   when a timer is running ([:184](Repster/Features/Workout/Models/LiveActivityManager.swift:184)).
   Needs `restTimerEndDate` threaded to that call site — it is already a parameter.
2. Both rest sections branch on the expired case before falling through to "Ready for next set",
   using `context.isStale` (or the now-safe `endDate <= .now`) while `isRestTimerRunning` is true,
   and render the existing "REST COMPLETE" treatment.

No push server, no new state, no app-side execution required. Skip `alertConfiguration` per §6.3.

### D5 — Make notification cancellation reachable from outside the ViewModel

Fixes §7. Lift the identifier and a `cancel()` onto a small shared type — the same object D1
introduces is the natural home — and call it from `discardActiveAndCopy()` and
`clearStoredAppState()`. While there, have `discardActiveAndCopy()` clear the six rest-timer
defaults, which it also skips today.

### D6 — The three small ones

L1: one footer line under the Timer Alert picker. L2: adjust `timerStartDate` alongside the clamp,
or clamp against `timerTotalDuration - elapsed` so both clocks agree. L3: one
`static let defaultRestTimerAlert` read by all three sites — and decide whether the true default is
`"vibration"` (what `HealthProfile` says) or `"both"` (what the ViewModel does). I would make it
`"vibration"` and match the model.

### D7 — Instrument it, or this stays invisible

We cannot currently tell from PostHog how often S3–S5 happen, and the whole point of §0 is that
users will not report it. Minimal, and consistent with the one-toggle privacy posture:

- Notification authorization status as a property on the workout-terminal events, alongside the
  existing `WorkoutInteractionTally` properties.
- A `rest_timer_alarms_missed` counter in the tally — incremented when a rest timer reaches zero
  with no channel available to announce it.

That is two properties on events that already fire, no new event, no new collection surface. It
also gives a before/after on whether these fixes moved anything.

---

## 11. Test plan

**Unit / ViewModel** (`ActiveWorkoutViewModelSuggestionRefreshTests`, XCTest, `@MainActor`, stub
services — the existing `testPausingWorkoutFreezesAndResumesRestTimer` at
[:618](RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift:618) is the shape):

- Timer reaching zero transitions to `.finished`, captures `restDurationSeconds` on the last
  completed set, and clears all six defaults. **No coverage today.**
- `recalculateTimerAfterBackground` with authorization denied **does** fire the in-app alert; with
  authorization granted it does not. (D2.3 — inject the status.)
- `subtractTime` leaves the displayed remaining and `timerTotalDuration - elapsed` in agreement (D6/L2).
- Notification scheduling is skipped for `"off"` and requested for the other three modes — extend
  the two existing `restTimerBackgroundNotificationUsesSystemSound` tests
  ([:273-283](RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift:273)) with a
  scheduling spy rather than testing the string helper alone.

**Coordinator (D1):** presentation options are empty while the workout screen is registered and
`[.banner, .sound, .list]` when it is not; registration is balanced across present/dismiss cycles.

**Teardown (D5):** discard-with-timer-running and `clearStoredAppState` each cancel the pending
request and leave no rest-timer defaults.

**Widget (D4):** `restCountdownRange` returns nil past the end date (already true), and a
`ContentState` with `isRestTimerRunning == true` and an expired `restTimerEndDate` selects the
finished branch, not the ready branch. Both chains.

**Manual on device** — the parts no test reaches, and the reason S3–S5 shipped:

| | Steps | Expect |
|---|---|---|
| S3 | Start a set, close the workout cover, sit on Home | banner + sound at zero |
| S4 | Deny notifications, background the app over a rest, return | alert on return |
| S5 | Enable a Focus mode, background over a rest | breaks through |
| S7 | Background over a rest, look at the Lock Screen after zero | "REST COMPLETE" |
| §7 | Discard the workout mid-rest, wait past the original end | nothing fires |
| L1 | Alert = Vibration, ringer on, background over a rest | note what it does |

Run the suite once into a log, as usual — concurrent `xcodebuild` runs invent failures.

---

## 12. Sequencing

| Phase | Work | Size | Notes |
|---|---|---|---|
| 0 | **D1** — delegate + coordinator | S | Fixes S3 alone. Standalone; ship first. |
| 1 | **D5** — cancellation reachable from outside | XS | Wants D1's object; do it in the same PR. |
| 2 | **D2** — contextual permission, status kept, §4.2 conditional | M | The largest, and the only one with UI. |
| 3 | **D3** — `.timeSensitive` + entitlement | XS code / M ops | Entitlement must land before the build ships. |
| 4 | **D4** — widget expired rendering | S | Independent. Demoted after the §6.2 correction — polish, not a defect. |
| 5 | **D6** + **D7** — small fixes, instrumentation | S | D7 last, so it measures the fixed build. |

Phases 0–1 together are one small PR and remove the most common silent case. Phase 4 is independent
and could go first if you would rather ship something with a visible result — though after the §6.2
correction it buys less than it first appeared.

---

## 13. Decisions I need from you

1. **D1's rule** — suppress the banner while the workout screen is up, or always present it? I
   recommend suppress; always-present is one line simpler but banners every set.
2. **D2 placement** — contextual at first rest timer (my recommendation), or a fifth onboarding
   step? Not both.
3. **D3** — are you willing to touch the App ID and regenerate profiles for the time-sensitive
   entitlement? Without it, S5 stays broken and there is no code-only substitute.
4. **D7** — is notification-authorization-status acceptable as an event property under the current
   privacy posture, or do you want the alarm left uninstrumented?
5. **D6/L3** — is the intended default `"vibration"` or `"both"`?

---

## 14. Out of scope

- **Custom alarm sounds.** A bundled `UNNotificationSound` per alert mode is a real product
  improvement and is a separate piece of work.
- **Playing through the silent switch.** No `AVAudioSession` category is configured anywhere in the
  app, so `AudioServicesPlaySystemSound` respects the ringer switch. Some competitors configure
  `.playback` to alarm through silent. That is a deliberate product decision with real downsides
  (it interacts with the user's music) and should not ride along on a correctness fix.
- **Apple Watch.** No watch target exists.
- **ActivityKit push updates.** Needs a backend — see §6.3.
- **The rest timer state machine, pause semantics, persistence and analytics.** Audited, correct,
  §9. Do not refactor them while fixing the alarm.

---

## 15. What shipped (2026-08-18)

### 15.1 Phases 0–1 — D1 + D5

New file `Repster/Core/Services/RestTimerAlarmCoordinator.swift`; six files touched; 192 insertions.
Suite 471 → 477, 0 failures. No new compiler warnings.

**One deviation from D1, deliberately.** The scope proposed tracking *view visibility* — a flag set
from `ActiveWorkoutView.task` and cleared from `.onDisappear`. That was built instead as a **weak
reference to the ViewModel**, which conforms to a new `RestTimerForegroundAlerting`:

```swift
var willAlertRestTimerInApp: Bool {
    if case .running = restTimer { return true }
    return false
}
```

Better on three counts, and worth recording because the reasoning generalises:

1. **It answers the real question.** The coordinator needs to know "will anything else alert?",
   which is exactly "is there a live ViewModel with a running tick" — not "is a view on screen".
2. **Deallocation clears it for free.** No teardown call to forget. The back-button case, which is
   the entire bug, is handled by the weak reference nilling itself.
3. **It is immune to view-lifecycle quirks.** An `onAppear`/`onDisappear` pair is fragile when the
   screen presents its own sheets and covers — the finish sheet and the exercise picker both do.

`resignForegroundAlerter` is identity-checked so a ViewModel tearing down *after* its replacement
registered cannot clear the newer one, which SwiftUI can do across a cover transition.

**Also confirmed while implementing, and worth not re-checking:** `finishWorkout` and
`discardWorkout` both *do* cancel the alarm correctly, via `clearScreenState()` → `dismissTimer()`
([ActiveWorkoutViewModel.swift:2150](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:2150)).
Only the two teardown paths that run *outside* the ViewModel leaked, exactly as §7 said.

**Not done, deliberately:** the `didReceive` tap-to-reopen handler mentioned under D1. It needs a
route from the coordinator back to `ContentView.showActiveWorkout`, which is new coupling that
belongs with the D2 permission work rather than bolted onto this change.

**Still unverified on device.** Everything above is unit-tested logic; the delegate actually being
consulted by iOS is not something the suite can prove. §11's manual matrix still stands, and rows
S3 and §7 are the two this change is claimed to fix.

### 15.2 D2, D3, D4, D6

**D2 — permission.** `RestTimerAlarmCoordinator` now owns a three-valued
`RestTimerAlarmAuthorization`, cached in `RestTimerAlarmPreferences` so view bodies and the alert
path can read it synchronously — the same UserDefaults-backed trick `HealthKitPreferences` uses.

- The request is **gone from `RepsterApp.init()`**; launch only refreshes the known status.
- `RestAlarmPromptView` is Repster's own explainer, raised by the *first* rest timer and gated on
  `notDetermined` as well as a one-shot flag. "Not now" never touches iOS, so the system prompt
  stays unspent and Settings can still turn it on.
- **§4.2 is now conditional.** `recalculateTimerAfterBackground` stays quiet only when
  `canAlertFromBackground` is true; otherwise it fires the in-app alert, because nothing else did.
- Granting mid-rest re-schedules the alarm already running, which would otherwise have been
  skipped at start for want of permission.
- Settings → Workout Preferences shows a tappable warning row when the alarm cannot reach the user.

`provisional` authorization maps to `.denied`. It delivers silently to Notification Centre, and for
"will the user be told rest is over", silent delivery is not reaching them.

**D3 — code only.** `content.interruptionLevel = .timeSensitive` is set. It is **inert** until the
entitlement lands (§15.3) — iOS silently downgrades to `.active`, today's behaviour — so this was
safe to ship ahead of the provisioning work.

**D4 — widget.** The five-way branch moved onto `ContentState.restDisplay(at:)`, shared by the Lock
Screen, the Dynamic Island and the compact trailing view, which previously maintained three
hand-written ladders and all carried the same gap. `staleDate` is now the rest end date rather than
`nil` — that is what makes WidgetKit re-render at the moment rest ends, and without it nothing
re-evaluated at all. The compact trailing view was also falling through to set progress, which is
indistinguishable from having no timer.

**D6.** `HealthProfile.defaultAlertMode` is the single nil-fallback, read by all three readers.
**Chosen as `"both"`, not `"vibration"`** — that is what the ViewModel and picker already did, so
no migrated user's alarm changes behaviour. The `init` default stays `"vibration"` for *new*
profiles; the two defaults are genuinely different things and are now documented as such. §13.5 is
therefore answered only in the safe direction — whether new profiles *should* default to `"both"`
is still open. L2's clamp now derives the new total from elapsed + remaining so the band and the
start-date maths agree. L1's caveat is a Settings footer line.

### 15.3 Not done, and why

- **The `.timeSensitive` entitlement.** Needs `com.apple.developer.usernotifications.time-sensitive`
  enabled on the App ID and profiles regenerated — an Apple Developer portal action. Adding the key
  to [Repster.entitlements](Repster/Repster.entitlements) *before* the capability exists breaks
  device signing, so it was deliberately left out. **S5 stays broken until this is done.**
- **D7 — instrumentation.** Recording notification-authorization status as an event property is the
  unanswered §13.4 privacy question. Not a call to make silently.
- **`didReceive` tap-to-reopen.** Still deferred; it needs a route back to
  `ContentView.showActiveWorkout`.
- **Device verification of D2/D3/D4.** §11's manual matrix still stands. Rows S4, S5 and S7 have
  never been run against the fixed build.

### 15.4 The double-alert race — reported and fixed same day

**Reported:** one observed instance of a banner *and* the in-app alert firing together, not
reproducible by hand. Real, and introduced by D1 — before the delegate existed nothing could ever
present in the foreground, so a double was impossible.

`timerTick()` does this, in this order:

```swift
restTimer = .finished          // ← state flips first
…
clearPersistedRestTimerState() // → cancelRestTimerNotification()
fireTimerAlert()               // ← in-app alert
```

`cancelRestTimerNotification()` removes *pending* requests. Once iOS has committed to delivering,
it is too late — so `willPresent` runs with the state already `.finished`,
`willAlertRestTimerInApp` truthfully answers **false**, and the banner is presented on top of an
alert that fired microseconds earlier.

The predicate asked *"will anything alert?"* — future tense. The race window is exactly the moment
something **just did**. Both channels are scheduled for the same instant, so this was always going
to land occasionally; whether the cancel beats the delivery is a coin toss weighted by how busy the
main thread is, which is why it appears once and then refuses to reproduce.

**Fix.** The coordinator records `lastInAppAlertAt` when `fireTimerAlert()` runs — *before* it
plays, since the notification can arrive mid-method — and suppresses anything landing within a
five-second grace. Past tense is checked before future tense.

It lives on the coordinator rather than the ViewModel on purpose: that also covers a ViewModel
alerting while a *newer* one holds the registration, which SwiftUI can briefly produce across a
cover transition, and which the weak reference alone does not solve.

Four regression tests pin it, including one asserting the back-button case still presents — the
grace window must not re-break what D1 fixed. `resetInAppAlertMarker()` exists purely as a test
seam, because the coordinator is a process-wide singleton whose marker would otherwise leak
suppression into whichever test ran next.

### 15.5 A note on the suite counts

The 471 baseline recorded at the start of this work was compiling **zero** Swift files — fully
cached — and was therefore running stale test objects that predate the in-flight
`BaselineMeterView` changes in the working tree. Ten "tick"-era geometry tests were still being
executed from a stale object while the file on disk had already replaced them with twenty-one
"bar/track" ones.

Nothing was failing and nothing was lost, but **local incremental runs here can silently execute
stale tests**. Worth a clean build before trusting a count.
