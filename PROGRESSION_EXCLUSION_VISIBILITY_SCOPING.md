# Progression Exclusion Visibility — Scoping

A workout can be marked "don't count toward PRs & future suggestions". The flag works
correctly. Nothing in the app ever says it is on.

This document scopes making it visible. It does **not** propose changing what the flag does.

Origin: 2026-08-29. A 55 kg × 8 on Incline Smith Barbell Press never became the 8-rep PR, and
55 kg × 6 from two months later showed as the standing record instead. Recomputing PRs changed
nothing, because the recompute was right — the session it came from is flagged. Diagnosis and
the two regression tests that now cover the retroactive path are in `SetServiceTests.swift`
(`testUnexcludingFinishedWorkoutRestoresItsPRsAndDemotesTheLowerRepSet` and its inverse).

---

## What we're deciding

1. What an excluded session looks like on each surface that renders it.
2. Whether "excluded" gets one visual language or several.
3. Whether the indicator is also the way to undo it.
4. Whether to tell people *during* the workout, not only afterwards.
5. What we deliberately leave inconsistent, and say so in copy.

---

## 1. The finding that shapes the copy: the flag already means two different things

The exclusion is honoured by some services and ignored by others. This is not a bug — it is an
unstated product decision — but it constrains every word we write.

**Honours the flag:**

| Service | Where |
|---|---|
| `PRService` | `isEligible` (`:718`), `excludedWorkoutIds` (`:776`) — sets earn no records or badges |
| `LoadPrescriptionService` | `excludedWorkoutIds` (`:374`) — sets never inform a future suggestion |
| `InsightsService` | `:117` |
| `InsightRules` | `:29` |

**Ignores the flag entirely:**

| Service | Consequence |
|---|---|
| `ChartDataService` | The set is plotted on the exercise's Charts tab like any other |
| `StatsService` | The set counts in total volume, set counts, workout counts, streaks |
| `ExportService` | Exports carry the flag but no consumer acts on it |

So an excluded 55 kg × 8 **is** on your strength chart, **is** in your volume total, and is
**not** in your PRs. That is defensible — the toggle says "PRs & suggestions", and erasing a
session from your volume history because it happened in a hotel gym would be wrong. But it means
we can never label these sessions "not counted" flat. Every string must name the scope.

> **Copy rule for the whole feature:** always "PRs" or "PRs & suggestions", never bare "excluded",
> "ignored", or "doesn't count".

---

## 2. Where it is invisible today

Complete inventory. Every row is a place a user can be looking straight at an excluded session.

| Surface | File | Shows the flag? |
|---|---|---|
| Exercise → History tab | `ExerciseHistoryView.swift:35` | No — session card is a date header and rows, nothing else |
| Exercise → PRs tab | `ExercisePRsView.swift` | No — rows are simply absent, no explanation |
| Exercise → Charts tab | `ChartDataService` | N/A — includes the sets (see §1) |
| In-workout History sub-tab | `ActiveWorkoutViewModel.swift:1654` | No — same view, second construction site |
| In-workout PRs sub-tab | same | No |
| **The active workout itself** | `ActiveWorkoutViewModel.swift:2127` | **No** — flag is read *only* to tag an analytics event |
| Workout detail (Home) | `WorkoutDetailFromHomeView.swift` | No |
| Workout detail (Calendar) | `CalendarWorkoutDetailView.swift` | No |
| Calendar day cell | `CalendarDayCell.swift` | No |
| Home → Recent PRs | `RecentPRsView.swift` | Consistent by construction — reads `PerformanceRecord`, which excluded sets never create |
| Edit Workout → … → Progression | `WorkoutExclusionSheet.swift:34` | **Yes — the only place in the app** |

The active-workout row is the one that stands out. You can train for ninety minutes in a session
that will not count, and the app knows, and says nothing until you go looking months later.

---

## 3. The enabling change: two snapshot types

Almost all of the work above is blocked on the same small thing, and once it is done each surface
is a rendering decision rather than a data-fetching one.

Views render from `Sendable` snapshots, never live SwiftData models. Neither snapshot carries the
flag:

- **`WorkoutSnapshot`** (`ChartSetData.swift:250`) — has `status`, `duration`, `displayTitle`;
  no exclusion fields. Feeds both workout-detail screens and the template-save flow.
- **`WorkoutHistoryGroup`** (`ExerciseModels.swift:17`) — `id`, `date`, `sets`. Built in two
  places (`ExerciseDetailViewModel.swift:62` and `ActiveWorkoutViewModel.swift:1654`), both by
  grouping `ChartSetData` by `workoutId`. Neither fetches the `Workout` row at all.

**Change:**

```
WorkoutSnapshot        += excludesEntireWorkoutFromProgressionHistory: Bool
                       += excludedExerciseIdsForProgressionHistory: Set<UUID>

WorkoutHistoryGroup    += isExcludedFromProgression: Bool   // resolved for THIS exercise
```

`WorkoutSnapshot` is one `init(from:)` — everything downstream inherits it free.

`WorkoutHistoryGroup` needs the exclusion resolved per-exercise, because the flag has a
whole-workout form and a per-exercise form (`Workout.excludesFromProgressionHistory(exerciseId:)`,
`Workout.swift:56`). Both history loaders need one extra lookup keyed on the workout ids they
already have. `WorkoutRepository.fetch(byIds:)` exists and `PRService` already uses exactly this
shape — mirror `PRService.excludedWorkoutIds(for:workoutIds:)` (`:776`) as a snapshot-returning
service method rather than inventing a second pattern.

---

## 4. Decisions

### D1 — One visual language: a muted pill reading "Not counted toward PRs"

Not a warning colour, not an alert. These sessions are usually excluded on purpose; the tone is
"noted", not "problem". Use `Color.textTertiary` on `Color.bgInput`, matching existing metadata
chips rather than the gold PR badge or the RIR pill.

One string, one component, every surface. A user who learns it on the workout screen recognises
it in exercise history.

### D2 — History session card: pill on the date header, rows untouched

`ExerciseHistoryView.workoutSessionCard` (`:35`) already renders a date header with space to its
right. Put the pill there.

Do **not** dim or strike the set rows. They are still a truthful record of what was lifted, they
are still on the chart and in the volume total, and dimming five rows to communicate one fact
about the session is both louder and less precise than one pill.

### D3 — PRs tab: a hint card, but only when this exercise is actually affected

`ExercisePRsView` already has the pattern — `perSideHint` (`:44`) is a card above the table in
exactly the right style. Reuse it verbatim.

Show it only when the exercise has at least one excluded session containing PR-eligible sets.
A permanent notice on every exercise is noise, and noise is what let this hide for five months.

Copy: *"2 sessions aren't counted toward PRs."*

### D4 — Tell people during the workout

The highest-value item and the cheapest. If the session will not count, say so while it is
happening, not in an analytics event.

Same pill, in the active workout header near the timer. `ActiveWorkoutViewModel` already holds
the workout; this needs no plumbing from §3 at all and could ship on its own.

This is also the only fix that prevents the problem rather than explaining it afterwards. The
toggle that sets the flag sits one tap from Start (`StartWorkoutSheet.swift:138`) and resets to
on each time the sheet opens, so a stray tap costs a session with no feedback whatsoever.

### D5 — Workout detail: banner, and make it the way back

Both detail screens get a tappable banner opening the Progression sheet for that workout.

Today the only route is Home/Calendar → workout → **Edit** → an unlabelled **…**
(`EditWorkoutView.swift:126`) → Progression. Five taps behind an ellipsis inside an editing
screen. The banner collapses that to one, and the sheet, the service call and the PR rebuild all
already exist and are now covered by tests — `WorkoutService.updateProgressionHistoryExclusions`
rebuilds PRs per exercise on the way out.

### D6 — Make the history pill open the same sheet

From Exercise → History there is currently no route to the workout at all. Rather than build
exercise-history → workout-detail navigation, present `WorkoutProgressionSheet` directly from the
pill: it needs a `Workout` and an exercise list, both cheap to fetch by id.

Keep `showsExerciseOverrides: false`, as the historic path does today — whole-workout only.

### D7 — Leave Charts and Stats alone, and say why in the sheet

Do not make `ChartDataService` and `StatsService` honour the flag. Volume you actually moved is
volume you actually moved.

But the Progression sheet should state the boundary, because right now nothing does. Extend the
footer in `WorkoutExclusionSheet.swift`:

> *"Excluded sessions still appear in your history, charts and volume totals — they just don't
> set PRs or feed future suggestions."*

### D8 — Nothing on the calendar day cell

Considered and rejected. The cell is a date and a dot; a second indicator at that size is
unreadable and the detail view is one tap away.

---

## 5. Build checklist

Ordered so each step ships on its own.

**Phase 1 — no plumbing required**
- [ ] `ProgressionExclusionPill` component (D1)
- [ ] Active workout header pill (D4)
- [ ] Progression sheet footer copy (D7)

**Phase 2 — snapshot plumbing**
- [ ] `WorkoutSnapshot` += two exclusion fields (§3)
- [ ] Snapshot-returning excluded-workout-ids lookup, mirroring `PRService:776`
- [ ] `WorkoutHistoryGroup` += `isExcludedFromProgression`, both construction sites
- [ ] History session-card pill (D2)
- [ ] Workout-detail banners, Home + Calendar (D5)

**Phase 3 — entry points and the PRs tab**
- [ ] Banner and pill open `WorkoutProgressionSheet` (D5, D6)
- [ ] Excluded-session count on `loadPRs()` (`ExerciseDetailViewModel.swift:77`)
- [ ] PRs tab hint card (D3)

---

## 6. Test plan

The retroactive rebuild path is now covered. What this feature adds is *display* correctness, and
the trap is the per-exercise form of the flag.

- [ ] `WorkoutHistoryGroup.isExcludedFromProgression` is true for a whole-workout exclusion
- [ ] …and true for an exercise-scoped exclusion **naming this exercise**
- [ ] …and **false** for an exercise-scoped exclusion naming a *different* exercise in the same
      workout. This is the one that will break: it is the case where the workout is flagged and
      this exercise is not, and a naive `workout.excludeFromProgressionHistory` read gets it wrong
- [ ] Both history construction sites agree — same workout, same exercise, same answer from
      `ExerciseDetailViewModel` and `ActiveWorkoutViewModel`
- [ ] `WorkoutSnapshot` round-trips both fields
- [ ] PRs-tab hint count is zero when no excluded session has eligible sets for that exercise
      (a session excluded but containing only warmups for this exercise must not trigger it)
- [ ] Golden-master pass — `ScreenDataGoldenMasterTests` covers these screens and will move

Worth running `RealDataDifferentialTests` across this: the local fixture contains four excluded
workouts, so the diff is non-empty by construction and the baseline will need rewriting
deliberately rather than by accident.

---

## 7. Out of scope

- Changing what the flag excludes (§1, D7)
- Per-exercise retroactive editing — historic edits stay whole-workout
- Backfill or migration — no stored data changes
- Any change to `PRFrontier` or the rebuild pipeline
- Un-excluding the four flagged sessions in the local history; that is a data fix, not a feature

---

## 8. Open questions

1. **Does the PRs-tab hint say what it costs you?** "2 sessions aren't counted" is honest but
   inert. "…including 55 kg × 8, which would be your 8-rep PR" is what a user actually wants, and
   it is computable — run the frontier twice, once honouring the flag and once not, and diff. It
   is the single highest-value string in the feature and also the only place needing genuinely
   new logic. Phase 4, or cut?

2. **Should excluding a *finished* workout warn about what it will remove?** Turning the flag on
   retroactively silently deletes PR records. The sheet could say "this will remove 3 PRs" before
   saving. Same diff computation as (1).

3. **Is the Start-sheet toggle in the right place at all?** Four sessions in 579 are flagged and
   all four read as ordinary training days, which is weak evidence for accidental taps. If D4
   lands and sessions still get flagged by mistake, the toggle probably wants to move behind a
   confirmation or out of the primary start path.

4. **Anything for widgets or the Live Activity?** Not audited here.
