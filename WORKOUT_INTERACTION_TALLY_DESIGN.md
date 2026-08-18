# Workout Interaction Tally — Design

**Status:** implemented 2026-08-17 on `NewMain`.

Counts what someone actually *did* during a workout — opened History, skipped a
rest, un-ticked a set — accumulates it locally, and ships the totals as
properties on the workout's terminal event. Answers "what does a session look
like from the inside", which no event in the project currently does.

## The shape: a tally, not a tap stream

The obvious implementation is one event per interaction. It is the wrong one.

**Volume.** A twenty-set workout is 150–300 interactions. `LifecycleEventFilter`
exists in `AnalyticsService.swift` because `Application Opened`/`Backgrounded`
reached 76% of ingested events on 1.1 and buried everything else; a tap stream
would be worse than that by an order of magnitude, and every real event would be
harder to find in Data Management.

**Analysis.** As properties on `workout completed`, "what fraction of workouts
involve checking history" is one insight with a breakdown, and it crosses with
retention, access tier and attribution for free — because those already sit on
the same event. As separate events it is a funnel needing session stitching.

The cost of the tally shape is stated under *Limits* below. It is real, and
session replay already covers it.

## Decisions

### D1 — Storage is one UserDefaults key holding `[String: Int]`

`WorkoutInteractionTally`, key `analyticsActiveWorkoutInteractions`.

Not in-memory on `ActiveWorkoutViewModel`, because two of the three terminal
events fire from outside it and after it is gone:

- `workout abandoned` is emitted by `ContentView.reportAbandonedWorkoutIfNeeded()`
  on a **later app launch**, reading `ActiveWorkoutSessionMarker` from UserDefaults.
- `workout discarded` also fires from `ContentView.discardActiveAndCopy()`, which
  never constructs the active-workout ViewModel at all.

Not thirteen discrete keys: one read-modify-write per increment instead of
thirteen key constants, one `removeObject` to reset, and adding a counter later
needs no key bookkeeping. `[String: Int]` is plist-native, so no encoding step.

This is the same trade `ActiveWorkoutSessionMarker` already makes for `setCount`,
for the same reason.

### D2 — `ActiveWorkoutSessionMarker` owns the lifecycle

`markStarted` resets the tally; `clear` clears it. No new lockstep to maintain:
the marker is already the single lifecycle owner for in-flight analytics
bookkeeping, and `WorkoutStartContextStore.remember`/`clear` already drive it.
A third independent store would be a third thing that can disagree about whether
a workout is in flight.

### D3 — `WorkoutInteraction` raw values *are* the property names

One closed enum for counter identity, whose raw values match a corresponding
`AnalyticsPropertyKey` case exactly. `WorkoutInteractionTally.properties(from:)`
maps between them by raw value, and
`testEveryWorkoutInteractionHasAnAnalyticsPropertyKey` fails the build if the two
vocabularies ever drift. The alternative — a `switch` mapping one enum to the
other — is thirteen lines that can silently be wrong.

### D4 — Increments go through the analytics service, never the store directly

`AnalyticsServiceProtocol.recordWorkoutInteraction(_:)`, guarded on
`isCollectionEnabled`. Three consequences, all wanted:

- An opted-out user accumulates **nothing at all**, rather than accumulating
  locally and having it dropped at send time.
- DEBUG builds get `NoopAnalyticsService` (`isCollectionEnabled == false`), so
  simulator runs don't accumulate either — consistent with every other event, and
  with the `-analyticsDebugCaptureEnabled YES` escape hatch.
- Call sites stay one-liners, and the existing test doubles work unchanged.

### D5 — Raw `Int`s, every counter present on every event, zeros included

Not `AnalyticsBuckets.count`. These are "how many times" values where the mean is
the interesting statistic, and PostHog can bucket a numeric property at query
time — it cannot unbucket `"4-6"`. `prsHit` is the existing raw-int precedent.

Zeros must be sent explicitly. If a counter is omitted when unused, PostHog
averages it over only the workouts that used it, and "History opens per workout"
silently becomes "History opens per workout that opened History" — a number that
can only ever look healthy. `snapshot()` therefore returns all thirteen cases,
filling absent ones with `0`.

### D6 — The `interactions:` parameter is required, not defaulted

All three terminal helpers take it with no default value, so the compiler refuses
a call site that forgets the tally. A defaulted `[:]` would have kept the two
existing tests compiling untouched and left a silent hole for the next caller;
per D5 a missing counter corrupts the average rather than just narrowing it.

### D7 — Exercise switches count user taps only

`selectedExerciseIndex` is written programmatically from nine places (restore on
load, jump-to-newly-added, clamp after removal, reorder, reset on finish and
discard). Its `didSet` and `ActiveWorkoutView.onChange` therefore both see far
more than user intent — including a spurious +1 on any workout restored to a
non-zero exercise.

So `SetTableDataSource` gains `recordExerciseTabSelected()` with a default no-op,
called from the tab's `onTapGesture`. `ActiveWorkoutViewModel` implements it;
`EditWorkoutViewModel` keeps the no-op, so the shared tab strip does not
instrument the edit-historic-workout screen. This follows the existing optional-
behaviour pattern in that protocol (`suggestionState`, `persistTargetRepOverride`).

### D8 — Rest-timer skips are counted in the view, not in `dismissTimer()`

`dismissTimer()` is also the internal cleanup path, called by `finishWorkout`,
`discardWorkout` and the set-completion flow. Counting inside it would add a
phantom skip to the end of every single workout. The count belongs on
`RestTimerView`'s `onDismiss`, which is only ever a user tap.

## The counters

| Property | Fires on |
|---|---|
| `history_views` | Sub-tab → History |
| `pr_views` | Sub-tab → PRs |
| `chart_views` | Sub-tab → Charts |
| `suggestion_refreshes` | Weight-suggestion refresh tap |
| `exercise_picker_opens` | `+` in the header, or the empty-state button |
| `exercise_switches` | Exercise tab tap (D7) |
| `exercise_settings_opens` | Gear icon beside the sub-tab bar |
| `sets_uncompleted` | `uncompleteSet` |
| `sets_deleted` | `deleteSet` |
| `sets_added` | `addSet` + `addWarmupSet` |
| `rest_timer_skips` | Rest timer dismissed by hand (D8) |
| `rest_timer_adjusts` | ±time or set-duration on the rest timer |
| `workout_pauses` | Clock tapped to pause (not to resume) |

The first four are the ones the app's whole premise rests on: they measure
whether people consult their own training data while training.
`sets_uncompleted` is the best confusion proxy available from taps — un-ticking a
set is a correction, and a high count points at tap targets or entry flow.

`workout completed` goes from 17 properties to 30. No practical PostHog limit is
near.

### Deliberately not counted

**Set edits after completion.** The only available hook, `markSetDirty`, fires
per keystroke and only for the current exercise, so it would measure typing
speed, not correcting. `sets_uncompleted` and `sets_deleted` already carry the
correction signal.

**Anything that is looked at without being tapped.** The weight-suggestion module
and the E1RM card are already on screen in the Sets scroll view. There is no
interaction to count, so "did they read the suggestion" is not measurable this
way at all — only `suggestion_refreshes`, which is a much narrower question.

## Limits

**No ordering, no timing.** `history_views: 3` cannot distinguish planning before
the first set from diagnosing after a failed one. Those are opposite behaviours
with opposite product conclusions.

The intended workflow is that the tally gives the *rates* and says where to look,
and masked session replay — already enabled — gives the narrative for a specific
cohort. Concretely: filter to workouts with `sets_uncompleted >= 3`, then watch
ten of those recordings.

## Files

| File | Change |
|---|---|
| `Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift` | `WorkoutInteraction`, `WorkoutInteractionTally`, 13 property keys, `recordWorkoutInteraction`, `interactions:` on 3 helpers, marker lifecycle |
| `Repster/Features/Workout/Protocols/SetTableDataSource.swift` | `recordExerciseTabSelected()` + default no-op (D7) |
| `Repster/Features/Workout/Views/ExerciseTabStripView.swift` | Call it from the tap |
| `Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` | 6 increments, tally on finish/discard |
| `Repster/Features/Workout/Views/ActiveWorkoutView.swift` | 7 increments |
| `Repster/App/ContentView.swift` | Tally on abandoned + copy-discard |
| `RepsterTests/AnalyticsServiceTests.swift` | 6 tests |
| `docs/privacy.html` | Disclosure clause |
| `POSTHOG_ANALYTICS_GUIDE.md` | §2 event reference, §3 dashboard |

## Privacy

No new *kind* of data: thirteen integers about which controls were used, no
exercise names, weights, reps or notes. It sits inside the existing
`Other Usage Data` declaration in `PrivacyInfo.xcprivacy` and does not touch the
`interaction autocapture` claim at privacy.html:67 — this is explicit first-party
counting of named controls, not PostHog autocapture, which stays off.

`privacy.html:43` enumerates what is collected specifically enough ("which
screens are opened… coarse ranges for things like workout duration and set
counts") that it needs one added clause to stay accurate. Done as part of this
change. `privacy-review-checklist.md` needs no answer changed.
