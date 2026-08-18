# Unperformed Sets & Exercise Removal — Scoping

**Date:** 2026-08-17
**Status:** scoping, nothing implemented.
**Reported:** a Copy Previous workout was finished with two exercises never started. Both appear
in history as if they were logged. In Edit Workout the exercise could not be deleted, so the sets
were deleted one by one — which left the exercise on screen with no sets. On Save it disappeared
from history, which was the desired outcome.

Two separate problems arrived in one report:

1. **A defect.** `completed` is not enforced on the history read path, and three write paths treat
   an unperformed row as if it counted. §1–§4.
2. **A UX gap.** Removing an exercise already exists and works; it is reachable only by long-press
   on a tab chip. §5.

They are independent fixes. Sequencing is §7 and the order matters — one of the fixes makes the
other one free.

---

## 1. Where these rows come from

**Copy Previous is the only producer of a row that looks logged but wasn't.**

```swift
// ContentView.swift:648-667 — performCopy
_ = try await services.setService.create(
    …, weight: sourceSet.weight, reps: sourceSet.reps, …
)
```

The new row carries last session's actual numbers in `weight`/`reps`, and
`SetRepository.create` stamps `completed: false` ([SetRepository.swift:59](Repster/Core/Repositories/SetRepository.swift:59)).
That combination — real numbers, never ticked — is what `WorkoutSet.hasData` reads as data
([WorkoutSet.swift:109-114](Repster/Data/Models/WorkoutSet.swift:109)).

The other two start paths do not produce it:

| Start path | Row created with | `hasData` |
|---|---|---|
| Copy Previous ([ContentView.swift:653](Repster/App/ContentView.swift:653)) | `weight`, `reps`, `rir` from source | **true** |
| Browse → start ([ContentView.swift:532](Repster/App/ContentView.swift:532)) | `weight: nil, reps: nil` | false |
| Template ([TemplateService.swift:285](Repster/Core/Services/TemplateService.swift:285)) | `targetRepMin/Max`, `targetRIR` only | false |

`SetService.create` deliberately does **not** feed these rows into PRs or stats — that was fixed
already, and the comment says exactly why ([SetService.swift:73-84](Repster/Core/Services/SetService.swift:73)).
It does persist `effectiveWeight`, and deliberately leaves `e1RM` unwritten
([SetService.swift:91-106](Repster/Core/Services/SetService.swift:91)). Hold on to both facts —
they decide the blast radius in §3.

**Finishing does nothing about them.** `WorkoutService.finishWorkout` flips status, stamps
duration, saves title/notes/RPE ([WorkoutService.swift:60-99](Repster/Core/Services/WorkoutService.swift:60)).
The unticked rows survive into history verbatim.

---

## 2. The invariant that was asserted but never enforced

`ChartDataService` states the rule, correctly, and names this exact scenario:

```swift
// ChartDataService.swift:56-59
/// `completed` matters as much as `hasData`: a row can carry weight and reps without
/// having been performed. Copy Previous creates exactly that, and an uncompleted row
/// plotted as a data point claims a session that never happened. Stats, PRs and the
/// History tab all draw the line at completion — charts do too.
```

The last sentence is not true. Charts were fixed on the belief that everything else already had
the rule. Here is who actually enforces what:

### Read paths

| Surface | Filter used | |
|---|---|---|
| Charts ([ChartDataService.swift:64](Repster/Core/Services/ChartDataService.swift:64)) | `completed && hasData` | ✅ |
| Insights ([InsightsService.swift:570](Repster/Core/Services/InsightsService.swift:570), [:607](Repster/Core/Services/InsightsService.swift:607)) | predicate `completed == true` | ✅ |
| Home recent-workout card ([HomeViewModel.swift:365](Repster/Features/Home/ViewModels/HomeViewModel.swift:365)) | `hasData` only | ❌ set count + volume |
| History detail stats strip ([WorkoutDetailFromHomeView.swift:215](Repster/Features/Home/Views/WorkoutDetailFromHomeView.swift:215)) | `hasData` only | ❌ set count + volume |
| Calendar detail ([CalendarViewModel.swift:218](Repster/Features/Calendar/ViewModels/CalendarViewModel.swift:218)) | `hasData` only | ❌ same |
| Exercise card rows ([CalendarExerciseCard.swift:15](Repster/Features/Calendar/Views/Components/CalendarExerciseCard.swift:15)) | `hasData` only | ❌ renders the rows |
| Exercise **cards** ([WorkoutDetailFromHomeView.swift:198-213](Repster/Features/Home/Views/WorkoutDetailFromHomeView.swift:198)) | none — grouped from all sets | ❌ card appears even with zero rows |
| Finish summary "N logged" ([WorkoutSummarySheet.swift:450](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:450)) | none — every exercise listed | ❌ counts untouched exercises |
| Finish summary set counts ([ActiveWorkoutViewModel.swift:1961](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1961)) | `completed` | ✅ |

Note the last two rows disagree **with each other on the same sheet**: the header counts every
exercise, the per-exercise line counts only completed sets. An untouched exercise is listed as
"0 sets" and still adds one to "N logged".

Note also the "card appears" row: that one is not Copy Previous-specific. Skip an exercise in a
*template* workout and its card still shows in history, just empty. The set-count and volume
damage is Copy Previous only; the phantom exercise card is universal.

### Write paths

| Path | Rule | |
|---|---|---|
| `SetService.create` ([:73](Repster/Core/Services/SetService.swift:73)) | adds no contribution | ✅ |
| `SetService.edit` ([:326-342](Repster/Core/Services/SetService.swift:326)) | `hasData` only | ❌ |
| `SetService.delete` ([:459-471](Repster/Core/Services/SetService.swift:459)) | `hasData` only | ❌ |
| `StatsService.shouldCountForStats` ([:179-188](Repster/Core/Services/StatsService.swift:179)) | `hasData` only | ❌ |
| `StatsService` workout membership ([:197-198](Repster/Core/Services/StatsService.swift:197)) | `completed` + above | ✅ |
| `StatsService.rebuild` → `fetchAggregateStats` ([SetRepository.swift:490](Repster/Core/Repositories/SetRepository.swift:490)) | `hasData` only | ❌ |
| `StatsService.rebuild` → `fetchWorkoutCount` ([SetRepository.swift:522](Repster/Core/Repositories/SetRepository.swift:522)) | `completed && hasData` | ✅ |
| `PRService.isEligible` ([:737-745](Repster/Core/Services/PRService.swift:737)) | `hasData` only | ❌ |
| `PRService.rebuild` → `fetchBestEligibleSet` ([SetRepository.swift:442](Repster/Core/Repositories/SetRepository.swift:442)) | `hasData` only | ❌ |

A single rebuild is internally inconsistent with itself: ghost rows inflate `totalSets` and
`totalVolume` but not `totalWorkouts`.

---

## 3. What it actually costs

### C1 — History overstates what happened *(the report)*

Two untouched exercises show as cards with full sets; their volume is in the session total; the
set count includes them. The finish sheet said one thing, history says another.

### C2 — Deleting a ghost row subtracts stats that were never added *(what the user did next)*

`SetService.delete` captures `hasData` and emits `.delete`
([SetService.swift:432,459-471](Repster/Core/Services/SetService.swift:432)); `handleDelete` sees
`wasCounted == true` and decrements ([StatsService.swift:363-380](Repster/Core/Services/StatsService.swift:363)).
The contribution was never there. So the workaround — delete every set of the exercise — silently
shrank that exercise's lifetime `totalSets`, `totalReps` and `totalVolume`, and can trigger a
`maxWeight` recompute. `max(0, …)` clamps the floor; it does not prevent the drift.

**This is already in the reporter's data.** A rebuild (§C3, once the eligibility rule is fixed)
repairs it.

### C3 — Any rebuild promotes ghosts into PRs and stats

`PRService.rebuild` walks every set for the exercise and asks `fetchBestEligibleSet`, which never
checks `completed` ([PRService.swift:499-513](Repster/Core/Services/PRService.swift:499)). A copied
row is persisted *with* `effectiveWeight`, so it is a valid winner — a weight never lifted can take
the rep-max record. `e1RM` is left nil at create, so charts and the prescription baseline stay
clean; the PR badge and `ExerciseStats` do not.

Rebuild triggers are routine, not admin-only:

- delete any workout containing the exercise ([WorkoutService.swift:257-259](Repster/Core/Services/WorkoutService.swift:257))
- toggle progression exclusion on a workout ([WorkoutService.swift:223-225](Repster/Core/Services/WorkoutService.swift:223))
- Settings → Rebuild Stats

### C4 — Completing a ghost row from Edit Workout under-counts

In `EditWorkoutViewModel`, `uncountedSetIds` holds only rows added or uncompleted *in that session*
([EditWorkoutViewModel.swift:39](Repster/Features/Workout/ViewModels/EditWorkoutViewModel.swift:39)).
A ghost row loaded from history is not in it, so ticking it goes through `edit()` → `handleEdit`'s
delta branch ([StatsService.swift:307-318](Repster/Core/Services/StatsService.swift:307)):
`totalSets` never increments, volume only diffs. Retroactively logging what you actually did
records less than it should.

---

## 4. Decisions

### D1 — Enforce `completed && hasData` everywhere, as one rule

Not eight local filter fixes. One shared predicate, used by every read surface in the §2 table and
by `shouldCountForStats`, `fetchAggregateStats`, `fetchBestEligibleSet` and `PRService.isEligible`.
`ChartDataService.chartEligibleSets` is the shape to promote — it already carries the rationale
comment.

This alone fixes C1 and C3, and stops C2/C4 for future rows.

### D2 — Delete never-completed rows at finish

Recommended, and **after D1**, which is what makes it cheap: once no derived value ever counted an
unticked row, deleting one needs no PR rebuild, no stats event, no exercise-level recompute. It is
a bulk row delete.

Shape: `SetRepository.deleteUncompletedSets(for workoutId:)`, called from
`WorkoutService.finishWorkout` before the status flip. Not through `SetService.delete` — that emits
the decrement in C2.

Why delete rather than only filter:

- A row that is invisible in history but still editable, still rebuild-eligible, still delta-eligible
  is a trap that has already bitten twice (C2, C4). The row has no meaning once the session is over —
  it is a plan artifact, and the app has no planned-vs-performed concept to hold it. (`PlannedWorkout`
  and `PlannedSet` exist in the schema and are referenced by nothing but container setup and the
  wipe-all path. Do not revive them for this.)
- It makes the editor behave the way the reporter already expected: an exercise with nothing logged
  is not in the workout.

### D3 — Unticked rows go regardless of their siblings

Four planned sets, two performed → a two-set exercise. Keeping the untouched two because the
exercise *was* trained is the same defect at smaller scale.

### D4 — Say so on the finish sheet; do not delete silently

Rows are visible on screen right up to the tap. Deleting them without a word is how you get "the app
lost my workout" mail. On `WorkoutSummarySheet`, above Save & Close, when anything is unticked:

> **Not logged** — Cable Fly, Face Pull (untouched), plus 2 unticked sets in Bench Press.
> These won't be saved.

And fix "N logged" ([WorkoutSummarySheet.swift:450](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:450))
to count exercises with ≥1 completed set.

Open: whether a fully-untouched *exercise* should additionally require a confirmation tap, or
whether the notice is enough. My read: notice only. A confirm dialog on every finish trains people
to dismiss it, and Copy Previous users skip an exercise often.

### D5 — One-shot migration for shipped data

Precedent exists and this is the same shape:
[GhostSetRepsBackfillMigration](Repster/Core/Services/GhostSetRepsBackfillMigration.swift),
[ExerciseWorkoutCountBackfillMigration](Repster/Core/Services/ExerciseWorkoutCountBackfillMigration.swift),
`UserDefaults`-guarded, runs once.

- Delete `completed == false` rows belonging to workouts with `status == .completed`.
- **Filter on workout status** — an in-progress copied session must survive, or the migration guts
  a workout mid-gym.
- Then `statsService.rebuild` + `prService.rebuild` for affected exercises. This repairs C2's
  under-count as a side effect.
- **Must run after D1 ships.** A rebuild against today's eligibility rules re-poisons stats with
  the very rows the migration is removing.

Alternative if you would rather not delete user rows: skip the migration and let D1's filters hide
them. Cheaper, and history reads correctly — but C2 and C4 stay live for every existing ghost row
forever. I would rather clear them.

### D6 — Copied rows as targets instead of actuals: a complement, not a substitute

Copying into `targetWeight`/`targetRepMin` instead of `weight`/`reps` is the semantically correct
model — an unperformed row would carry no data at all.

**It fixes more than it first appears.** Every broken filter in §2 guards `hasData` *first*, so
making it false short-circuits all of them without touching a line of that code:

| | Effect |
|---|---|
| C1 counts + volume | fixed — ghost rows stop being data, so set counts and session volume are right |
| C2 delete decrement | fixed — `wasCounted` is false, nothing to subtract |
| C3 rebuild → ghost PRs and stats | fixed — `isEligible` and `fetchBestEligibleSet` reject on `hasData` |
| C4 tick-in-editor under-count | fixed, and correctly: `handleEdit` takes the `!oldCounted && newCounted` branch and adds the full contribution |

**What it does not fix:**

- **The phantom exercise card — the reported symptom.** `exerciseGroups` is grouped from *all* sets
  with no data check, and `exerciseCount` counts every exercise with any row
  ([WorkoutDetailFromHomeView.swift:198-213,225](Repster/Features/Home/Views/WorkoutDetailFromHomeView.swift:198)).
  The untouched exercise still appears in history, now as an empty card, still +1 to the exercise
  count. Exactly what a skipped template exercise does today.
- **"N logged" on the finish sheet** ([WorkoutSummarySheet.swift:450](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:450)) — no data check at all.
- **The re-arming problem.** `completed` still isn't part of the rule anywhere. The next feature
  that writes a real number onto an unticked row reopens the entire class.
- **Existing data.** Shipped ghost rows keep their real `weight`/`reps`, so C2/C3/C4 stay live for
  them and D5's migration is needed either way.

**And it is not a config change.** `targetWeight` is rendered nowhere in the app — the weight field's
placeholder is a hardcoded `"0"` ([SetRowView.swift:402](Repster/Features/Workout/Views/SetRowView.swift:402)),
while rep targets do render via `preferredTargetRepBounds` ([SetRowView.swift:766](Repster/Features/Workout/Views/SetRowView.swift:766)).
Ship it as-is and last session's weight becomes invisible, which guts the feature. Real cost:

1. Render `targetWeight` as the weight placeholder.
2. Extend tap-to-accept to weight, and to rep *ranges* —
   `attemptAutoFillRepsFromTarget` handles reps only, single-value targets only
   ([SetTableView.swift:603-619](Repster/Features/Workout/Views/SetTableView.swift:603)).
3. Accept that copied reps now feed the prescription request and `InsightRules`
   ([InsightRules.swift:137](Repster/Core/Services/InsightRules.swift:137)) as explicit targets.
   Defensible — arguably an improvement — but it is a Smart Suggestions behaviour change, not inert.

**Verdict:** worth doing as a modelling improvement, after D1 — not instead of it. D1 is smaller,
closes the symptom that was actually reported, and holds the line for every future prefill.

---

## 5. Exercise removal in Edit Workout

**The action exists and works.** `EditWorkoutViewModel.removeExercise(at:)` deletes every set and
drops the exercise ([EditWorkoutViewModel.swift:359-386](Repster/Features/Workout/ViewModels/EditWorkoutViewModel.swift:359)).
It is reachable from exactly one place: long-press an exercise chip in the tab strip → context menu
→ Delete Exercise → confirm ([ExerciseTabStripView.swift:55-89](Repster/Features/Workout/Views/ExerciseTabStripView.swift:55)).

Why it wasn't found:

- **No affordance.** The chip is a 36pt tab that reads as navigation. Nothing indicates it holds a
  menu. Delete Set has the same problem ([SetRowView.swift:256-286](Repster/Features/Workout/Views/SetRowView.swift:256))
  but was found — a full-width row invites a long-press in a way a nav chip does not.
- **The obvious button is taken.** `ellipsis.circle` in the Edit header opens the *progression
  exclusion* sheet ([EditWorkoutView.swift:125-132](Repster/Features/Workout/Views/EditWorkoutView.swift:125)).
  That is the control anyone looks at first, and it does something unrelated.
- **The workaround looked like it failed.** Deleting the last set leaves the exercise key in
  `setsByExercise`, so the chip stays with an empty table until reload. The screen said the delete
  didn't work; the store disagreed.
- **A hard gate.** Delete is hidden entirely at `exercises.count > 1`
  ([ExerciseTabStripView.swift:83](Repster/Features/Workout/Views/ExerciseTabStripView.swift:83)).
  Not the reporter's case, but it means a one-exercise workout can never have that exercise removed —
  and `EditWorkoutView` already has an empty state built for exactly that
  ([EditWorkoutView.swift:197-228](Repster/Features/Workout/Views/EditWorkoutView.swift:197)).

### Fixes, cheapest first

1. **Add Delete Exercise to the header menu** (S). Turn the header `ellipsis.circle` into a real
   menu: Delete Exercise (current), Exclude from Progression…. Keep the context menu. Same
   confirmation alert, same call.
2. **Drop the `count > 1` gate** (XS). Both screens have an empty state.
3. **Drop the exercise when its last set is deleted** (S). In `deleteSet`, if the exercise's array
   is now empty, remove it from `exercises` and `setsByExercise` and clamp the selection — matching
   what a reload shows. Alternatively keep the chip and show "No sets — this exercise will be
   removed", which is gentler but adds a state.
4. **A real exercise-management sheet** (M–L). One list with reorder, replace and delete. This
   overlaps [EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md) §7,
   which wants the same sheet to fix Move Left being O(n) taps. **Do not build it twice** — if that
   work is going ahead, fold delete into it and ship only 1–3 here as the interim.

Both screens share `ExerciseTabStripView` and `SetTableDataSource`, so 1–3 land on the active
workout at the same time. That is fine and desirable — the same "how do I get rid of this" applies
mid-session.

---

## 6. Test plan

**Journey tests** (real stack, `WorkoutJourneyTests` — nothing there covers copy-previous today):

- Copy a workout, complete one exercise, finish → history shows one exercise, one set count, volume
  from the completed sets only.
- Copy, complete 2 of 4 sets in one exercise, finish → exercise survives with 2 sets.
- Copy, complete nothing, finish → workout has no exercises; `ExerciseStats` for the copied
  exercises are unchanged from before the copy.
- Ghost row + rebuild: copy, finish, delete an unrelated workout for the same exercise (triggers
  rebuild) → no PR awarded to the copied row, `totalSets` unchanged. **Fails today.**
- Delete an existing ghost row via Edit Workout → `ExerciseStats` unchanged. **Fails today** (C2).
- Tick a ghost row in Edit Workout → `totalSets` +1, full volume added. **Fails today** (C4).

**Service/ViewModel tests:**

- `shouldCountForStats` / `isEligible` / `fetchAggregateStats` / `fetchBestEligibleSet` each reject
  `completed == false` with data present.
- `finishWorkout` removes unticked rows and leaves ticked ones (including the half-done exercise).
- Migration: completed workout's ghosts deleted; in-progress workout's rows untouched; runs once.

**Manual:** finish-sheet notice copy with 0 / 1 / several untouched exercises; the "N logged" count.

---

## 7. Sequencing

| Phase | Work | Size |
|---|---|---|
| 0 | D1 — one eligibility rule, all read + write paths, tests | M |
| 1 | D2 + D4 — delete at finish, finish-sheet notice, fix "N logged" | S |
| 2 | D5 — migration + rebuild | S–M |
| 3 | §5.1–5.3 — exercise delete discoverability | S |

Phase 0 before 1 (makes the delete a plain row delete). Phase 0 before 2 (or the rebuild re-poisons).
Phase 3 is independent — ship it whenever, or fold it into the replace/reorder work.

---

## 8. Out of scope

- Reorder and replace — [EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md).
- Planned-vs-performed as a first-class concept. The dead `PlannedWorkout`/`PlannedSet` models are
  not an invitation.
- Superset grouping behaviour when rows are removed at finish — `supersetGroupId` is copied but
  unused by the flows above; check before shipping D2 if supersets have landed by then.
- Export: rows go out carrying their real `completed` flag
  ([ExportService.swift:502](Repster/Core/Services/ExportService.swift:502)), so an export makes no
  false claim. After D2 there is nothing to export anyway.

---

## 9. Decisions I need from you

1. **D2** — delete unperformed rows at finish, or keep them and rely on filters alone?
2. **D4** — notice only, or a confirmation tap when a whole exercise is untouched?
3. **D5** — run the migration on existing histories, or leave old ghosts hidden-but-present?
4. **§5.4** — is the exercise-management sheet happening? If yes, I will ship only 5.1–5.3 as
   interim and not design the sheet twice.
