# Share from history — scoping

**Status:** scoped and **built 2026-09-11**, uncommitted. Target: 1.6. All five §9
decisions went with the recommendation. The device pass (§7) is outstanding.
**Origin:** a user asked why the workout share card can only be shared from the summary
sheet, and not after leaving it.
**Already decided:** PR handling is **option A**: PR highlights appear only while the PR
still stands. This is option 2 in [SHARE_CARD_FEATURE_DESIGN.md §C5](SHARE_CARD_FEATURE_DESIGN.md).
No schema change and no persisted "was a PR when logged" flag.

Open decisions are collected in §9. Everything else here is a default the build follows
unless told otherwise.

---

## 1. What exists today

**The card can only be built inside the summary sheet.** `shareCardData(summary:)`,
`muscleSlices()` and `traceBars()` are private to
[WorkoutSummarySheet.swift:1099](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:1099)
and read `ActiveWorkoutViewModel.exercises` / `setsByExercise`. Finishing the workout clears
both, so nothing can build a card once the sheet is gone.

**The preview sheet is already reusable.** `WorkoutSharePreviewSheet(data:entryPoint:prsHit:accessTier:analyticsService:)`
([WorkoutShareCard.swift:941](Repster/Features/Workout/Views/WorkoutShareCard.swift:941))
takes a plain `WorkoutShareCardData` value (which is `Equatable`) and needs nothing from the
active workout. The styles, privacy toggles, Save Image, `UIActivityViewController` and all four
analytics events come along unchanged.

**`ShareCardEntryPoint` has one case:** `.summary`
([AnalyticsServiceProtocol.swift:888](Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift:888)).

**Where saved workouts are shown:**

| Surface | Reached from | Existing "…" menu |
|---|---|---|
| `CalendarWorkoutDetailView` in the Calendar day pane ([CalendarView.swift:316](Repster/Features/Calendar/Views/CalendarView.swift:316)) | Calendar tab | Per-workout header row, [CalendarWorkoutDetailView.swift:177](Repster/Features/Calendar/Views/CalendarWorkoutDetailView.swift:177) |
| `WorkoutDetailFromHomeView` | Home Recent card ([HomeView.swift:102](Repster/Features/Home/Views/HomeView.swift:102)), Workouts tab ([WorkoutsTabView.swift:113](Repster/Features/Charts/Views/WorkoutsTabView.swift:113)), Exercises tab ([ExercisesTabView.swift:161](Repster/Features/Charts/Views/ExercisesTabView.swift:161)) | Toolbar, [WorkoutDetailFromHomeView.swift:72](Repster/Features/Home/Views/WorkoutDetailFromHomeView.swift:72) |

`WorkoutDetailFromHomeView` renders the workout through `CalendarWorkoutDetailView`, but passes
`nil` for every header callback. The header row, and its menu, are therefore hidden there
([CalendarWorkoutDetailView.swift:64](Repster/Features/Calendar/Views/CalendarWorkoutDetailView.swift:64)).
Two entry points cover all four routes, and they never appear on the same screen.

**Both surfaces already hold everything the card needs,** as snapshots in `WorkoutDetail`:
- `WorkoutSnapshot`: `displayTitle`, `date`, `duration`, `status`
- `ExerciseGroup.exercise` (`ChartExerciseData`, including `primaryMuscle`)
- `ExerciseGroup.sets` (`ChartSetData`: `weight`, `effectiveWeight`, `reps`, `prReps`,
  `completed`, `setType`, `orderInWorkout`, `prStatus`)

No new fetches are needed. Because these are value snapshots rather than live SwiftData
models, the model-lifetime crash class does not apply.

---

## 2. The two paths disagree today, so the card has to pick one rule

The summary and the history screens compute "what happened in this workout" differently. A
card built by copying either side would disagree with the other for the same workout.

| Card input | Summary sheet today | History screen today | **Builder rule** |
|---|---|---|---|
| Which sets count | `completed` in `computeSummary`, but `completedAt != nil` in `muscleSlices`/`traceBars` | `hasData` ([CalendarViewModel.swift:291](Repster/Features/Calendar/ViewModels/CalendarViewModel.swift:291), [WorkoutDetailFromHomeView.swift:234](Repster/Features/Home/Views/WorkoutDetailFromHomeView.swift:234)) | **`completed`** |
| Set count | Completed sets, warm-ups included | `hasData` count | Completed, warm-ups included (unchanged) |
| Volume / primary metric | `summarize(completed)` | `summarize(hasData)` | `summarize(completed)` |
| Lifts listed and "N lifts" | Every exercise in the session, **including ones with no completed set**, which show as "0 sets" rows and inflate the count | Exercises with any set row | Exercises with at least one completed set |
| PR | Any set with `.current`, **ticked or not** | n/a | A **completed** set with `.current` |
| Title | Edited title, else `displayTitle` | `displayTitle` (which is the saved, edited title) | `displayTitle` |
| Duration | Live clock at the moment of the tap | `workout.duration`, saved at finish from the same clock | Passed in. `nil` allowed (§3.5) |
| Date label | "Sat, Aug 30" | n/a | Same, plus the year when it isn't the current one (§3.5) |
| Units | `viewModel.unitPreference` | `services.unitPreference` | Passed in |

**Why `completed` and not `hasData`** (decision D3). The whole difference between the two
is the unperformed-sets defect: Copy Previous rows that were never ticked
([UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md), still open). With `hasData`,
the card would publish sets the user never did, and a card shared from history would
disagree with the one shared from the summary.

Every write path was checked, so `completed` does not blank out any legitimate workout:
- Live logging: sets start `false` and are ticked to `true`
  ([SetRepository.swift:61](Repster/Core/Repositories/SetRepository.swift:61)).
- Edit Workout: sets `completed = true` on every set it saves
  ([EditWorkoutViewModel.swift:131](Repster/Features/Workout/ViewModels/EditWorkoutViewModel.swift:131)).
- CSV import: writes `true` ([ImportService.swift:182](Repster/Core/Services/ImportService.swift:182)).
- Backup restore: keeps the stored value
  ([ExportService.swift:637](Repster/Core/Services/ExportService.swift:637) / `:681`).
- The only `false` writers are the live-logging default and template rows
  ([TemplateService.swift:306](Repster/Core/Services/TemplateService.swift:306)), which are not
  logged sets.

The cost: on a workout with ghost rows, the card shows fewer sets than the stats strip above
it. That is the existing defect becoming visible. The fix belongs to the unperformed-sets
work, not here.

**Two small changes to the summary card follow from this.** Both are fixes, listed here so
they aren't surprises:
1. Exercises with no completed set stop appearing as "0 sets" rows, and stop counting toward
   "N lifts".
2. The PR headline ignores unticked rows.

A third fix turned up during the build: **the trace card's PR diamond had never been drawn.**
The summary read `WorkoutSet.cachedPRStatus`, a legacy field the model's own comment says
app logic must not use. The initialiser always sets it to `nil`, and nothing else writes it.
The builder reads `prStatus` through the snapshot, so a standing record's bar now gets its
diamond. It also stops the summary reading an optional-enum SwiftData attribute the model
warns against.

The summary's `prsHit`, used by `workout completed` and by the `prs_hit` on share events from
the summary, is still computed by `computeSummary` and is **not changed**.

**Duration.** The summary's value is the live clock when Share is tapped. The saved value is
taken from the same clock at Save & Close. The two can differ by however long the user sits on
the summary sheet. Whether the clock stops when the summary opens was not checked; the saved
value is the authoritative one either way.

---

## 3. Design

### 3.1 One builder, used by both paths

A new `WorkoutShareCardBuilder`: pure, no services. Its input:
- title, date, `duration: TimeInterval?`
- exercises in workout order, each as `(exercise: ChartExerciseData, sets: [ChartSetData])`
- unit preference
- context (summary vs history, for the PR label in §3.2)
- `now`, for the year rule

Its output is a `WorkoutShareCardData`.

The bodies of `shareCardData`, `muscleSlices` and `traceBars` move into it, switched from
`WorkoutSet` to `ChartSetData`.
- **Summary** calls it with `viewModel.exercises` and `setsByExercise`, mapped through
  `ChartSetData(from:)`. `computeSummary` already does exactly this mapping.
- **History** calls it with `detail.exerciseGroups`.

**Why one builder rather than a second copy.** `ExerciseGroup.build` exists because two copies
of the grouping code had already drifted (see the comment at
[CalendarViewModel.swift:21](Repster/Features/Calendar/ViewModels/CalendarViewModel.swift:21)).
Two copies of the card maths would drift the same way, and here the drift would show up as
two different cards for the same workout.

**Order.** The summary passes exercises in tab-strip order. `ExerciseGroup.build` orders by
the lowest `orderInWorkout`, which its own comment documents as the tab strip's rule. So the
PR headline ("first exercise with a PR") and ties among the top lifts resolve the same way on
both paths. Test 8 pins this.

### 3.2 PR handling (option A)

The builder treats only `.current` as a PR, which is already the trace-bar rule.
`.previous`, `.matched` and `.dominated` are not PRs. When a PR has since been beaten, the card
leads with the workout title (the designed no-PR state) and draws no gold bars. The card has no
PR count, so nothing false is printed.

**Copy** (decision D2). "NEW PR" reads wrong on a card from March. Proposed: a `prLabel` on
the card data, "NEW PR" from the summary and "PERSONAL BEST" from history. The hide-weights
subline "Best set I've logged" is true either way and stays.

### 3.3 Where the button goes (decision D1)

**Recommended: a visible share icon (`square.and.arrow.up`) next to the "…", in both
places.** The report is that people couldn't find sharing. A menu item would put it in the
same hidden kind of place.

- **`WorkoutDetailFromHomeView`:** a second `ToolbarItem`, to the left of the menu.
- **`CalendarWorkoutDetailView`:** a new optional `onShare: ((WorkoutSnapshot) -> Void)?`, drawn
  as a 32×32 icon to the left of the "…" in `workoutHeader`. The header-visibility condition
  at `:64` gains `onShare`. It's per workout, so on a day with two sessions each header shares
  its own. Home keeps passing `nil`, so there's no duplicate button.

**The icon is hidden when:**
- `workout.status != .completed`. Calendar's fetch has no status filter
  ([WorkoutRepository.swift:57](Repster/Core/Repositories/WorkoutRepository.swift:57)), so
  today's in-progress workout does appear there.
- The workout has no completed sets, because the card would be empty.

This check is a static `canShare(_ detail: WorkoutDetail) -> Bool`, so it can be tested.

### 3.4 Presentation: one modifier, not two copies

A `.shareWorkoutCard(detail:entryPoint:)` view modifier, living next to the builder:
- It resolves the access tier when the host screen appears, using
  `accessControlService.currentAccessSnapshot()`. This is the read-only call the summary uses
  ([WorkoutSummarySheet.swift:181](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:181)).
  It must never be `recordCompletedWorkoutIfNeeded()`, which would use up a free workout.
- It builds the card data at tap time and presents `WorkoutSharePreviewSheet`.

Both surfaces use it. The design doc already records the cost of copy-pasting instead: the
`ActivityShareSheet` wrapper ended up duplicated verbatim in two files (§B1).

**Freshness.** The card is built at tap time from the screen's current `WorkoutDetail`. Both
screens reload after Edit Workout
([WorkoutDetailFromHomeView.swift:158](Repster/Features/Home/Views/WorkoutDetailFromHomeView.swift:158),
[CalendarView.swift:174](Repster/Features/Calendar/Views/CalendarView.swift:174)), so an edited
workout shares as edited.

### 3.5 Card data changes

- **`durationLabel` becomes optional.** `WorkoutSnapshot.duration` is `Int?`, and an imported
  workout can arrive without one: [ImportService.swift:117](Repster/Core/Services/ImportService.swift:117)
  passes through whatever the file had. The meta rows drop it, and the TIME stat cell shows "—".
  Summary cards always have a duration, so they're unaffected.
- **The date gains a year when it isn't the current one:** "Sat, Aug 30, 2025". The date label
  also feeds the saved image's file name (`writePNG`), which is fine.
- **`prLabel`,** per §3.2.

### 3.6 Analytics

- **Entry points** (decision D4). Add `calendar` and `workout_detail`, rather than the single
  `history` value the design doc reserved. Placement is the thing this change is least sure
  of, a split answers that directly, and grouping two values in PostHog is trivial. Nothing
  has ever shipped with `history`, so there's no compatibility cost.
- **New property `days_since_workout`** (raw Int, decision D5) on `share card opened` and
  `share card shared`, for non-summary entry points only. It separates two different cases:
  people who closed the summary and immediately wanted the card (0 days), and people sharing
  an old session. The first points at making the summary button more prominent; the second
  points at more history surfaces.
- **`prs_hit` from history means "PRs still standing".** That's a different meaning from the
  summary's, and the guide should say so.
- **Dashboard 2, item 10** (the `workout completed` → `opened` → `shared` funnel) must filter
  to `entry_point = summary`. Otherwise same-day history opens inflate the open rate that the
  phase-2 gate is read against.
- The instrumentation rules are reused as they are: `opened` fires once per presentation,
  `dismissed` fires only when nothing was shared, and a Photos save counts as a share.

---

## 4. Files

| File | Change |
|---|---|
| `Repster/Features/Workout/Views/WorkoutShareCardBuilder.swift` | **New.** Builder, `canShare`, `.shareWorkoutCard` modifier. Hand-register in `project.pbxproj` (explicit refs; `WorkoutShareCard.swift` is `BC9001`/`AC9001`, so pick unused neighbours) |
| `WorkoutSummarySheet.swift` | Call the builder; delete `shareCardData`/`muscleSlices`/`traceBars` |
| `WorkoutShareCard.swift` | Optional `durationLabel` (4 read sites: `:273`, `:311`, `:352`, `:456`), `prLabel` at `:397` |
| `AnalyticsServiceProtocol.swift`, `AnalyticsService.swift` | Entry-point cases, `days_since_workout` |
| `WorkoutDetailFromHomeView.swift` | Toolbar icon + modifier |
| `CalendarWorkoutDetailView.swift` | `onShare` callback + header icon |
| `CalendarView.swift` | Pass `onShare`, attach modifier |
| `RepsterTests/WorkoutShareCardTests.swift`, `RepsterTests/AnalyticsServiceTests.swift` | §5 |
| `POSTHOG_ANALYTICS_GUIDE.md` | Entry-point values, `days_since_workout`, funnel filter |
| `SHARE_CARD_FEATURE_DESIGN.md` §B2 / §E, `RELEASE_1_6_CONSIDERATIONS.md`, `CHANGELOG.md` | Record it |

`AnalyticsServiceProtocol.swift` and `POSTHOG_ANALYTICS_GUIDE.md` already carry uncommitted
edits from other work. This change stacks on top of them.

---

## 5. Tests

**Builder** (in `WorkoutShareCardTests.swift`):
1. **Golden parity.** A fixture session run through the builder equals the
   `WorkoutShareCardData` today's summary code produces. This test is written and green
   **before** the summary is switched over, which proves the refactor changes nothing except
   the two §2 fixes. Those fixes get their own tests.
2. An unticked row that has data is excluded from sets, volume, lifts, muscles and trace.
3. An exercise with no completed sets is neither listed nor counted.
4. `.current` produces the headline and a gold bar. `.previous` / `.matched` / `.dominated`
   produce neither.
5. A `nil` duration gives a `nil` label.
6. The year appears only for other years (inject `now`).
7. Warm-ups are excluded from muscles and trace but counted in sets. This pins today's
   behaviour.
8. The same sets, supplied in summary order and in `ExerciseGroup.build` order, produce equal
   card data.

**Visibility:** `canShare` is false for an in-progress workout and for a workout with zero
completed sets.

**Analytics** (in `AnalyticsServiceTests.swift`): the new raw values are sent;
`days_since_workout` is present for history entry points and absent for the summary.

Run the suite once, into a single log.

---

## 6. Build order and estimate

| # | Step | Estimate |
|---|---|---|
| 1 | Builder + tests 1–8, golden test first | ~3 h |
| 2 | Summary switched to the builder, old functions deleted, full suite | ~0.5 h |
| 3 | Card data changes (optional duration, year, `prLabel`) | ~0.5 h |
| 4 | Analytics + tests | ~1 h |
| 5 | Modifier + both surfaces | ~2 h |
| 6 | Docs | ~0.5 h |

**About one day, plus a device pass.**

---

## 7. Device pass (tap steps)

1. Finish a workout and share it from the summary, then Save. Open the same workout from the
   Home Recent card and tap the share icon. The card should match the summary one.
2. Calendar, on a day with two workouts: each header shares its own workout.
3. A workout whose PR has since been beaten shows no gold headline. A workout whose PR still
   stands reads "PERSONAL BEST".
4. A workout from last year shows the year in its date.
5. Today's in-progress workout in Calendar has no share icon.
6. An imported workout with no duration shows "—" for TIME.
7. Edit a past workout (add a set), then share: the new set is counted.
8. Hide weights, Save Image, and share to Messages. Same behaviour as from the summary.
9. PostHog live events show `entry_point` = `calendar` / `workout_detail` and
   `days_since_workout`.

---

## 8. Out of scope

- Persisting "was a PR when logged" (option B). This could be revisited if people complain
  about missing PR headlines on old workouts.
- The exercise-history screen, the Home Recent PRs card, and an Insights card variant (the
  design doc's phase 3).
- Fixing the ghost rows themselves ([UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md)).
- Changing how prominent the summary's Share button is. `days_since_workout` is there to
  inform that decision later.

---

## 9. Decisions needed before building

| # | Question | Recommended | Alternative |
|---|---|---|---|
| D1 | Where does Share go? | Visible icon next to "…" on both screens | Item inside the "…" menu |
| D2 | PR label on history cards | "PERSONAL BEST" | Keep "NEW PR" everywhere |
| D3 | Which sets count | `completed` (matches the summary card) | `hasData` (matches the screen, includes ghost rows) |
| D4 | Entry-point values | `calendar` + `workout_detail` | Single `history` |
| D5 | Send `days_since_workout`? | Yes | No |
