# Paywall Bridge Sheet — Scoping

**Date:** 2026-09-29
**Status:** Built 2026-09-29, uncommitted. The suite result and device pass are recorded in §11.
**Target release:** 1.6
**Feature area:** Monetization / free tier
**Chosen option:** A (bridge sheet) on its own. B (a separate Home card state for "no free workouts left") and C
(a heads-up before the last free workout) were sketched on 2026-09-29 and set aside. See §9.

## 1. Summary

When a free user has used all 10 free workouts, starting a workout opens the RevenueCat paywall
with no explanation. This change puts a short sheet in front of the paywall. The sheet says the free
workouts are used up, shows what the user has logged, and says their log stays open. It offers
**See plans** (which opens the paywall) or **Not now**.

Every way to start a workout already passes through one gate, `ensureWorkoutCreationAccess`, so
changing that one function covers all entry points.

**Scale:** a PostHog analysis of 2026-08-10 to 09-18 found that 2 of the 22 users who started the
10-workout quota reached 0 remaining. [posthog-funnel-audit-2026-09-19.md](marketing/metrics/posthog-funnel-audit-2026-09-19.md)
also notes that no 1.5 free user was seen below 6 remaining. The goal is to treat the users most
likely to buy decently. This change won't show up as a measurable move in the numbers.

## 2. What happens today

| Step | What the user sees | Code |
|---|---|---|
| Finishes workout 10 | Nothing about the quota | `recordCompletedWorkoutIfNeeded`, `MonetizationService.swift:415` |
| Back on Home | The Start card's blue subtext changes from "N free workouts left" to "Unlock Repster to start a new workout" | `workoutAccessMessage`, `ContentView.swift:496` |
| Taps the card | The Start sheet opens with the same subtext line and all three options, which still look available | `StartWorkoutSheet.swift:32` |
| Taps any option | The Start sheet closes and the RevenueCat paywall opens | `ensureWorkoutCreationAccess`, `ContentView.swift:517` → `showPaywall = true` |

Entry points that reach the gate, all in `ContentView.swift`:

| Entry | Caller | Closes first |
|---|---|---|
| Empty Workout | `startEmptyWorkout` (:531) | Start sheet (it closes itself) |
| Copy Previous | `beginCopyPreviousFlow` (:550) | Start sheet |
| Use Template | `beginTemplateFlow` (:569) | Start sheet |
| Starting a workout from inside the template flow | `TemplateFlowView.beforeStartWorkout` (:449) | Template flow (`dismissBeforePaywall`) |
| Exercise list, browse mode | `startWorkoutWithExercises` (:583) | Exercise list (`dismissBeforePaywall`) |

The Settings row "Unlock Repster" opens the paywall directly (`SettingsView.swift:526`). That's the
right behaviour, because the user asked for it, so it stays as it is.

Only starting a new workout is gated. `requiresPaywall` and `canStartNewWorkout` have no other
callers. History, Charts, Insights, Export, templates and resuming an active workout all keep working
at 0 remaining. That is what makes the sheet's "stays open" line true.

## 3. The change

```
tap any start option at 0 remaining
  → ensureWorkoutCreationAccess: showFreeLimitSheet = true   (was: showPaywall = true)
      → See plans  → set pendingPaywall, close the sheet → onDismiss → showPaywall = true
      → Not now    → close the sheet, back where they were
      → swipe down → same as Not now
```

- **Show it every time**, not once. The sheet is the explanation, and it adds one tap. A user who
  already knows can use See plans. The Settings row stays a direct path to the paywall.
- **Open the paywall after the sheet has closed**, from its `onDismiss`, using a pending flag. That's the
  same pattern `pendingTemplateFlow` uses (`ContentView.swift:399`). Opening a sheet from inside a sheet,
  or while one is closing, is what the comment at `ContentView.swift:395` warns about.
- **The sheet opens with the same timing the paywall has today:** right after the Start sheet,
  template flow or exercise list closes. The paywall appears reliably at that point today, so the
  sheet should too. Check it on a device anyway (§7).
- **Suppress the review prompt when the sheet is shown**, the same way the paywall does
  (`reviewPrompt.suppressForThisSession()`, `ContentView.swift:285`).
- **After a purchase, nothing changes.** The paywall's `onDismiss` refreshes access. The user taps
  Start again, as they do today. Resuming the original tap automatically is out of scope (§9).

## 4. Sheet content and copy

```
        ✓
You've used your 10 free workouts

   [ 42 workouts ]  [ 610 sets ]        ← recap, §5

Your history, charts and insights stay open.
Unlock Repster to keep logging new workouts.

        [ See plans ]
           Not now
```

- **Title:** "You've used your {limit} free workouts". Take `{limit}` from
  `accessSnapshot.freeWorkoutLimit`, not a literal. The limit has already changed once (5 → 10).
- **Body:** two short sentences. The first reassures, the second states the one thing that's locked.
  The second one mirrors the existing "Unlock Repster" wording in Settings and on the card.
- **No benefit bullets.** The paywall shows the benefits right after this sheet. Any benefit line
  added here has to match the three canonical welcome bullets (value-prop rule), so the simplest
  choice is none.
- **Buttons:** "See plans" is the one accent button and "Not now" is plain text. The Health prompt
  uses the same "Not now" wording.
- **Height:** fit the sheet to its content with the shared `PromptSheetHeight.swift` helpers
  (`measuringHeight()` + `promptDetentHeight`), like `AppleHealthPromptView`. Don't use a fixed
  `.medium`, which is what clipped the rest-alarm prompt.
- **Icon:** a green checkmark (`Color.success`), not a lock. The user finished something, so it
  shouldn't look like they hit an error.

## 5. Recap numbers

**Show workouts and sets. Leave PRs out.**

- **Source:** `chartDataService.fetchBreakdownSummary(timeRange: .all)` → `totalWorkouts`,
  `totalSets`. Home's monthly stats already use this call (`HomeViewModel.swift:281`), so the numbers
  match what Charts shows.
- **Why not PRs:** the obvious source, `fetchRecentPRs`, returns one standing record per
  exercise. For someone 10 workouts in, almost every exercise they've done holds a first-time rep
  max. The count would just be "exercises tried" relabelled as PRs, which is inflated and means
  nothing.
- **Why not the quota count:** the quota counter isn't the size of their history. Workouts
  logged before the empty-workout guard (6611cd8) counted as empty sessions, and imported workouts
  don't count at all. The history count is honest. It can be far above 10 for someone who imported
  from FitNotes, and that's fine.
- **Loading:** fetch in the gate, *before* the sheet opens (`ContentView.loadFreeLimitRecap`). This
  replaces the earlier plan of fetching in the sheet's `.task`: a row that arrives late makes the
  fitted sheet visibly grow. The query is local and runs while the previous sheet is still closing.
  The row is hidden if `totalWorkouts == 0` or the fetch fails. Never show a zero or a spinner. The
  sheet has to work without the recap.
- **Formatting:** group thousands (`610`, `4,210`) with the app's existing number formatting. Use
  singular labels at 1.

## 6. Analytics

Two new events. Names follow the existing lowercase-with-spaces style:

| Event | Properties | Fires |
|---|---|---|
| `free limit sheet shown` | `free_workout_limit` (Int) | Once per presentation |
| `free limit sheet closed` | `result`: `see_plans` \| `not_now` \| `swiped` | On close |

- **`result` reuses the existing property key** that `apple health prompt answered` uses, rather
  than adding an `action` key.
- **`shown` is an event only, with no screen view.** That keeps the sheet from inflating the Paywall
  screen count.
- **Fire `shown` once per presentation with a one-shot guard**, as the share card does
  (`shareCardOpened`). Don't use a bare `.onAppear`: `paywall shown` does that and was measured
  double-firing on 2026-09-03.
- **Paywall events are unchanged.** The workout gate still reports `PaywallSource.paywall`, whose
  documented meaning ("the gate hit when starting a workout with no free workouts left") stays
  correct. The funnel becomes sheet shown → see plans → paywall shown → purchase.
- **Expect `paywall shown` to drop** for the workout gate once this ships, because users who tap
  Not now never reach the paywall. Note this on the PostHog paywall dashboard so the drop isn't
  read as a regression.

## 7. Testing

- **The view takes plain values** (limit, optional recap, two closures) and no services. That keeps it
  previewable and testable without the `AccessControlServiceProtocol` mock, which doesn't exist yet
  (see Known test failures).
- **Previews:** the default state, no recap, an importer with large numbers, and the largest
  Dynamic Type size (checks the fitted height and that the ScrollView takes over).
- **Unit tests:** recap formatting and hiding the row (zero, failed fetch, singular labels). The gate
  routing in `ContentView` has no test harness, which is also true today.
- **QA shortcut, optional and small:** the quota lives in the Keychain, so reaching the wall on a
  simulator means logging 10 workouts with at least one set each. A DEBUG-only launch argument that
  seeds `saveConsumedWorkoutCount(10)` would make this a one-step check. If it's built, it must be
  `#if DEBUG`.
- **Device pass (tap steps):** from 0 remaining, try each of the five entry points in §2 and
  confirm the sheet appears every time. Then check that See plans opens the paywall, that Not now
  and swipe-down return to where the user was, and that a purchase followed by tapping Start again
  starts a workout.

## 8. Size

- **New:** `FreeLimitSheet.swift` (view, about 120 lines) and one test file for the recap.
- **Changed:** `ContentView.swift` (two `@State`s, one `.sheet`, one line in the gate, about 30 lines),
  and `AnalyticsServiceProtocol.swift` plus `AnalyticsService.swift` (two events).
- **Nothing else:** no model, migration, RevenueCat or dashboard-config changes.

## 9. Out of scope

- **B:** a Home card state for "no free workouts left" that skips the Start sheet. Without it, the
  path is still card → Start sheet (three options that look available) → free-limit sheet. That's one
  more tap than ideal, but the user now gets an explanation.
- **C:** the "This is your last free workout" line at 1 remaining, and a one-time card on Home after
  workout 10.
- **Resuming the original tap after a purchase.** For example, going straight into the Empty
  Workout they tapped.
- **The `paywall shown` double-fire on `.onAppear`.** It's a separate instrumentation fix and hasn't
  been re-verified since 2026-09-03.
- **An entry-point property on the new events.** It's too little volume to split.

## 10. Decisions

1. **Button label:** "See plans", accepted 2026-09-29. It says what happens next, and the body
   already says "Unlock Repster".
2. **DEBUG quota launch argument:** built. Add `-RepsterFreeWorkoutsUsed 10` to the scheme's launch
   arguments to reach the sheet, or `0` to reset. The value is written to the Keychain, so it outlives
   the launch. `KeychainWorkoutQuotaStore.applyDebugLaunchOverride`, called from `RepsterApp.init`,
   only exists in DEBUG builds.

## 11. What was built

| File | Change |
|---|---|
| `Repster/Features/Home/Views/FreeLimitSheet.swift` | New: `FreeLimitRecap` and the sheet, with four previews |
| `Repster/App/ContentView.swift` | The gate raises the sheet, not the paywall. New `loadFreeLimitRecap`. The sheet's `onDismiss` opens the paywall on See plans. The label `dismissBeforePaywall` is renamed `dismissBeforeFreeLimitSheet` |
| `Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift` | Two events, the `FreeLimitSheetResult` enum, and the `free_workout_limit` key |
| `Repster/Core/Services/MonetizationService.swift`, `Repster/App/RepsterApp.swift` | The DEBUG launch override |
| `RepsterTests/FreeLimitSheetTests.swift` | New: recap rules (5 tests) |
| `RepsterTests/AnalyticsServiceTests.swift` | Three event tests |

**Suite:** 936 executed, 14 skipped, 0 failures on the iPhone 16 Pro simulator (2026-09-29). All 8 new tests passed, and the runner didn't crash.

**Device pass: outstanding.** Use the tap steps in §7.
