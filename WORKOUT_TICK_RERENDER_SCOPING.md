# Menus Refreshing During a Workout — Scoping

**Written:** 2026-11-01 · **Reviewed and built:** 2026-11-02 · **Status:** BUILT, device pass outstanding (§9) · **Target:** 1.6 · **Size:** small: 3 app files + 1 test file, no schema change, no visible UI change

**Decision:** D1 in §6 settled on B. What was verified is in §10.

## 1. The report

Selecting a muscle in New Exercise during a workout shows a constant refresh. Confirmed by the user to happen only in a workout. The unanswered questionnaire is not involved.

This is not the bug fixed by renaming the `@AppStorage` key in 881af48. It is also not a regression: 1.5 measures the same.

## 2. What happens today

The app has two timers, the workout clock and the rest timer, both in `ActiveWorkoutViewModel`.

1. `ActiveWorkoutView.body` reads both values directly: the clock at [ActiveWorkoutView.swift:447](Repster/Features/Workout/Views/ActiveWorkoutView.swift:447) and the rest timer at [:338](Repster/Features/Workout/Views/ActiveWorkoutView.swift:338), [:345](Repster/Features/Workout/Views/ActiveWorkoutView.swift:345) and [:375](Repster/Features/Workout/Views/ActiveWorkoutView.swift:375). So it re-runs on every tick.
2. Each re-run updates the sheets it presents ([:189](Repster/Features/Workout/Views/ActiveWorkoutView.swift:189), [:234](Repster/Features/Workout/Views/ActiveWorkoutView.swift:234)).
3. Inside those sheets, `ExerciseListView` and `CreateEditExerciseSheet` re-render, the muscle `Menu` is rebuilt, and UIKit replaces every row.

Reaches: the New Exercise form via **+ Exercise → Add New**, and the same form via **gear → More Exercise Settings**. The Increment picker on the gear sheet sits on the same path (not measured separately). The sort menu in the exercise list is not affected (measured). The summary sheet, History and PRs have no menus, though the summary sheet does tick and its Time tile relies on that (§3). The Charts sub-tab does (`ChartDropdown`), but it is not a sheet and takes no closures, so the tick probably does not reach it. That is not measured; fix B stops the screen ticking either way.

### Measured

Menu refreshes with the Primary Muscle menu held open (iPhone 17 Pro simulator, iOS 26.3, Debug):

| Build | Clock only (~10 s) | Rest running (~10 s) | After rest (~6 s) |
|---|---|---|---|
| 1.5 | 10 | 22 | 7 |
| Current | 11 | 21 | 7 |
| No workout, questionnaire unanswered | 0 in 16 s | n/a | n/a |
| **Fix B (recommended)** | **0** | **1** (bar appears) | **1** (rest ends) |
| Fix A | 0 | 0 | 0 |
| Fix C | 10 | 21 | 7 |

The gear route measures the same for current, A and B.

## 3. The fix (shape B)

The workout screen knows **whether** the rest bar shows, never the seconds. Only the clock, the bar's contents and the summary sheet read the ticking values.

**`ActiveWorkoutViewModel.swift`**

- Add `RestTimerPresence` (`idle`, `counting`, `finished`) and `RestTimerState.presence` beside [`RestTimerState`](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:45).
- Give [`restTimer`](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:173) a `didSet` that updates a new `private(set) var restTimerPresence` only when it changes. Same pattern as `selectedExerciseIndex` at [:136](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:136). Every write passes through it, so the two cannot drift.

**`ActiveWorkoutView.swift`**

- `shouldShowRestTimer(for:)` takes `RestTimerPresence`.
- `shouldShowSupersetPrompt` drops `restTimerState`. The function never uses it, but reading it to pass it in keeps the screen ticking.
- `isRestTimerVisible` reads `restTimerPresence`.
- The `RestTimerView(...)` block moves unchanged into a small `WorkoutRestBand` child; `ElapsedTimerView(...)` likewise into `WorkoutClock`.

**`WorkoutSummarySheet.swift`**

- [`displaySummary`](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:224) reads `viewModel.elapsedTime`, after its frozen-summary early return. The Time tile comes from `computeSummary()`, which reads `Date()` ([ActiveWorkoutViewModel.swift:2418](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:2418)), and nothing the sheet observes ticks. It stays current today only because the presenter re-runs it. Without this line, Time freezes while Save still stores the real clock. A stops the same re-run, so it needs this too (not measured with A).

**Not touched:** `bottomAccessoryArea`'s structure, `bottomAccessoryAnimationKey`'s meaning, `SetEntryKeyboardOverlay`, and the `@StateObject` manager, so the per-digit repaint stays as it is.

**What users notice:** menus in those sheets stay still. If a menu happens to be open, it refreshes once each time the bar changes: at most three times per rest (the bar appears, rest runs out and it shows "Rest complete", it is dismissed). Nothing else changes.

Also measured: the list rows behind the form stop re-rendering (100 in 10 s → 0 on the clock).

Re-rendering of the real views on the clock, in 6 s, hosted from a test in a scratch copy:

| View | Today | B | B + summary line |
|---|---|---|---|
| `ActiveWorkoutView` | 6 | 0 | 0 |
| `ExerciseListView` | 6 | 0 | 0 |
| `WorkoutSummarySheet` | 6 | 0 | 6 |

## 4. What could break, checked

The risk is something that only looks right because the screen repaints every second. This codebase has been caught that way before: on 2026-09-04, removing a full-screen repaint left lazy set rows undrawn.

| Suspect | Finding |
|---|---|
| Wall-clock reads in workout views | One that matters: the summary's Time tile, through `computeSummary()`. Fixed in §3. The explainer's "x days ago" label also reads `Date()`, but it is a past set's age and harmless if it lags |
| View model state hidden from observation | None: no `@ObservationIgnored` |
| View-facing values derived from the timers | Only `computeSummary().duration`, above. `willAlertRestTimerInApp` is read by the alarm coordinator, not a view |
| Keypad visibility | Safe: `trackedField` only moves between fields; show and hide go through published `context` |
| Set table | Never ticked: `SetTableView.body` does not re-run per tick today |
| Unobserved reads in views the tick re-runs | None beyond the `Date()` reads above |
| Views only ever seen under the tick | The summary sheet, above. The gear sheet and suggestion module use only their inputs and `@State`, so the tick refreshes nothing in them. The exercise list and create form also run outside a workout, where nothing ticks |
| Rest alarm prompt "Asking…", read in a `.sheet` closure | Measured: updates within 7 ms with the tick gone |
| Clock and rest bar still updating | Measured: both re-render about once a second; pause stops the bar; workout pause stops both |
| Every rest state | Measured with a menu open: ticked set, running, +15, paused, resumed, workout paused, runs out, finished, dismissed. Screen re-renders only on real changes (0 to 2 per state) |
| Rest bar leaving | Measured in a small test app built around the real `RestTimerView`: its body re-runs with the new state as it leaves, but the bar slides out the same as today, keypad open or closed, on iOS 26.3 and 18.6. Sampled 15 to 25 frames a second, not the real screen, so §9 checks it by eye |

**Still to check:** the keypad with real key presses, in the device pass (§9). §10 has what the simulated walk covered.

## 5. Alternatives

- **A: move the whole bottom accessory into a child view.** Fully quiet, no view model change, about 75 lines moved in one file. But it moves the keypad's container, and that area has regressed repeatedly (`LazyVGrid` holes, doubled animation in `c11fc94`, `GeometryReader` drift). Not worth it to avoid a few refreshes per rest.
- **C: give the sheets host views with stable inputs.** Tried and **does not work**: `ExerciseListView` stops being recreated but its `body` still re-runs every tick. Likely `@Environment(\.dismiss)` changing as the presenter re-runs; that link is inference, not measured.
- **Do nothing.** It has existed since at least 1.5 and is cosmetic, but it runs for the whole workout whenever one of these menus is open.

## 6. Decisions

- **D1: shape. Settled on B** (2026-11-02): keypad untouched, one refresh each time the bar changes. A: no refresh at all, but moves the keypad's container. The summary line in §3 is needed either way.

## 7. Tests

- Update call sites in [ActiveWorkoutViewModelSuggestionRefreshTests.swift](RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift): 7 `shouldShowRestTimer`, 5 `shouldShowSupersetPrompt`. That file has uncommitted work, so keep these as separate hunks. Write the 7 as `RestTimerState.running(...).presence` rather than `.counting`, or the 4 running and paused tests become two duplicate pairs.
- New: `presence` mapping for all four states.
- New: `restTimerPresence` follows `restTimer` through running, paused, finished and idle. Nothing else would catch this: if it stopped updating, the rest bar would never appear and every other test would still pass.
- New: `restTimerPresence` stays quiet across a remaining-time change, using `withObservationTracking` and `addTime`. This guards "never on a tick".
- Run the full suite once into a log.

## 8. Out of scope

- A source-scanning test that stops `ActiveWorkoutView` reading the timers again.
- Removing the per-second `UserDefaults` save in `timerTick`. Safe, but unrelated to this fix.
- The dotted `healthkit.*` keys.
- `dotImage` redrawing its 19 images on each rebuild, which stops mattering once rebuilds stop.

## 9. Device check (tap steps)

1. Start a workout and tick a set. Clock and rest bar count; try −15, +15, pause, and tapping the countdown to set a time. Dismiss with the X, keypad closed and open: the bar slides away both times.
2. **+ Exercise → Add New → Primary Muscle**: hold the menu open for 10 seconds. It stays still. Repeat with Equipment.
3. **Gear → More Exercise Settings → Primary Muscle**: same. Then the Increment dropdown on the gear sheet.
4. During rest, tap a weight field: keypad opens with no jump, rest bar stays above it. Type, close. Let rest run out with the keypad open: "Rest complete" waits until it closes.
5. In a superset, finish a round: the prompt stacks above the rest bar and hides under the keypad.
6. On a fresh install, the first rest shows the alarm prompt and "Asking…" appears on Enable.
7. On the workout's Charts tab, open a dropdown during rest and hold it for 10 seconds. It stays still.
8. Tap **End** and leave the summary open past the next minute: Time moves on by itself.

## 10. Built (2026-11-02)

As §3 and §7, with one addition: the two superset tests that passed a timer to `shouldShowSupersetPrompt` now check the timer and the prompt together, because that function no longer takes a timer.

**Full suite**, iOS 26.3, from the real checkout: 1,024 tests, 14 skipped, 0 failed, confirmed from the result bundle. That is 1,021 plus the 3 new tests.

**Real screen**, finished code, hosted from a test in a scratch copy, with rest running:

| View | Re-renders in 6 s |
|---|---|
| `ActiveWorkoutView` | 0 |
| `ExerciseListView`, sheet open | 0 |
| `ElapsedTimerView` | 6 |
| `RestTimerView` | 6 |
| `WorkoutSummarySheet`, sheet open | 6, with Time moving on each time |

**Keypad walk** on the same rig: it opens with the rest bar still showing. Rest running out hides the bar, "Rest complete" appears once the keypad closes, and dismissing clears it. Three digits re-render the screen 3 times, so the per-digit repaint is unchanged. Digits were simulated with `refresh()`, not real key presses, and this checks state, not how it looks.

**New tests, broken on purpose:** with `restTimerPresence` stuck on `.idle`, 3 tests fail. With the change guard removed, none fail, because an equal write does not notify on this toolchain. The guard stays so the code does not depend on that. The stays-quiet test would still catch `presence` starting to change with the seconds.

**Still open:** the device pass in §9.
