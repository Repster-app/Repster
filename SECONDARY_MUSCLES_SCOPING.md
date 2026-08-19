# Muscle Group Coverage — Scoping

**Status:** scoping only, nothing built
**Date:** 2026-08-16
**Supersedes:** the insights-attribution framing in this doc's first draft

## The feature, stated properly

Users want to **keep track of which muscles they're training** — while planning a routine, right after finishing a workout, and over time. Secondary muscles are the plumbing that makes that tracking accurate. They are not the feature.

The first draft of this doc scoped secondary muscles as an insights-weighting problem, because the insights panel is the only place muscle data is currently consumed. That framing produced a long debate about credit constants and led away from what users are actually asking for. Corrected here.

### Evidence

From [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md):

- A **live routine overview while editing**, showing muscles worked (primary + secondary), updating as exercises are added. Their framing is the important part: *this information only appears after logging, but it's needed while planning.*
- Hevy **removed** its muscle-distribution visual and users ask for it back by name — listed as one of two regressions worth noting.
- "Volume per muscle group, not just set count."
- Primary/secondary counted as 1.0 / 0.5 sets against a weekly target.
- Separate front/side/rear delt tracking (finer taxonomy — see Decision 1).

---

## The three surfaces

| When | Surface | Today |
|---|---|---|
| **Planning** a routine | `CreateEditTemplateView` | **Nothing.** No muscle overview while editing |
| **Finishing** a workout | `WorkoutSummarySheet` | **Nothing.** No muscle display at all |
| **Over time** | Insights muscle panel, Charts breakdown | Exists, primary-only |

Two of the three don't exist. The one that does is the one I over-scoped last time.

Already correct and worth not breaking: template *cards* show muscle tags ([TemplateService.swift:97](Repster/Core/Services/TemplateService.swift:97)), and both the muscle panel and chart breakdown already sort by size rather than alphabetically — which is a specific complaint in the Hevy thread.

### The key consequence

**The two missing surfaces need no arithmetic.** A routine overview answers "does this hit chest?" — a coverage question. Primary shown solid, secondary shown muted. There is no weighting, no baseline, no credit constant, nothing to tune.

That confines the entire 0.5-credit question to the one panel that already exists. It is not a blocker for the feature.

---

## Decision 1 — the taxonomy mismatch (blocking, do this first)

This is the real work, and it's unchanged from the first draft. Primary and secondary are drawn from **different vocabularies**.

`ExerciseMuscleGroupCatalog.supportedEntries` ([ExerciseMuscleGroupCatalog.swift:9](Repster/Features/Exercise/Models/ExerciseMuscleGroupCatalog.swift:9)) has 10 canonical values:

> abs, back, biceps, cardio, chest, forearms, full body, legs, shoulders, triceps

The seed data's secondary tags use a finer-grained leg vocabulary that isn't in it: **glutes (17), quads (11), hamstrings (10), calves (4)** — 42 of 96 tags off-catalog. `normalizedValue` passes unknown values through unchanged ([ExerciseMuscleGroupCatalog.swift:36](Repster/Features/Exercise/Models/ExerciseMuscleGroupCatalog.swift:36)), so today they'd surface raw.

**Recommendation: roll up to the existing taxonomy.** Add `glutes | quads | hamstrings | calves → legs` to `normalizedValue`. Zero migration, zero UI churn.

Measured yield: **59 of 96 tags survive** rollup + dedupe; **41 of 69 exercises gain at least one secondary group**. The 37 that collapse were leg sub-muscles under a `legs` primary, which was never new information. What survives is what users notice:

| Exercise | Primary | Gains |
|---|---|---|
| Conventional Deadlift | back | abs, legs |
| Barbell Bench Press | chest | shoulders, triceps |
| Barbell Overhead Press | shoulders | abs, triceps |
| Close Grip Bench Press | triceps | chest, shoulders |
| Barbell Row | back | abs, biceps |

The alternative — promoting glutes/quads/hamstrings/calves to first-class groups — changes the **primary** taxonomy too: migration, seed re-tag, new pills, new colors, a visible shift in existing baselines. The Hevy thread's front/side/rear delt request is the same idea one level deeper. Real demand, but a separate project. Ship the rollup first.

`MuscleGroupColors` already handles glutes, hamstrings, and quads ([MuscleGroupColors.swift:31](Repster/Core/Extensions/MuscleGroupColors.swift:31)). Only **calves** needs a case added.

---

## Decision 2 — dedupe rules (blocking, and small)

Coverage display needs exactly one shared helper. `MuscleAttribution` takes an exercise and returns its groups, primary flagged:

1. Normalize primary and every secondary through the rollup
2. Drop any secondary equal to the primary — otherwise `legs` + `["quads","glutes"]` lists legs three times
3. Dedupe the remainder
4. Drop `cardio` and `full body` where the consuming surface excludes them ([InsightsService.swift:409](Repster/Core/Services/InsightsService.swift:409))

**Every surface below calls this one function.** Do not let normalization logic fan out into five call sites.

---

## Decision 3 — credit weighting (deferred, applies to one panel only)

Only the insights muscle panel does arithmetic on muscles, so this only matters there. Recommendation stands at a flat **0.5**, with two notes:

- **A single constant is defensible** because each `MuscleVolumeRow` compares a muscle to *its own baseline*, computed under the same rule. The constant appears on both sides and largely cancels — 0.5 vs 0.7 changes the number printed, not whether the row reads as up, down, or absent. (Holds for a stable split; less so for someone alternating push and leg weeks.)
- **Keep `MuscleBalanceInsightRule` on primary-only.** It compares groups *against each other*, which is exactly where a flat credit distorts — inflating frequently-secondary groups (triceps, shoulders, abs). Leaving it alone also means its `>= 4 sets` and median thresholds keep working untouched.

If more fidelity is ever wanted, the seed arrays are **already ordered by involvement** — `Sumo Deadlift → glutes, hamstrings, quads` is correctly flipped against conventional. So rank-decay (0.5 / 0.35 / 0.25) costs an index lookup and no new data authoring. Not v1.

**Rejected: per-exercise credit values.** 96 tags to author by hand, UI on every custom exercise, and an AI generator emitting numbers it will get wrong — for precision that mostly cancels out.

### Two traps when the panel is wired

1. **The global total must not inflate.** At [InsightsService.swift:461](Repster/Core/Services/InsightsService.swift:461), `currentTotal += 1` sits in the same iteration as the per-group increment. One set fanning to three muscles must still increment the total once, or the status card breaks.
2. **`currentSets` is `Int`** on both `MuscleVolumeRow` and `TrainingStatus` ([InsightsServiceProtocol.swift:158](Repster/Core/Services/Protocols/InsightsServiceProtocol.swift:158)). Half-credit is fractional. Change to `Double` and format to one decimal — baselines are already `Double`.

---

## Decision 4 — the toggle

Smaller than the first draft made it. Coverage display needs no setting — showing which muscles an exercise works is just information.

A setting is only warranted for the **insights panel weighting**, since that changes numbers users have seen before. If wanted: `countSecondaryMuscles: Bool?` on `HealthProfile`, matching the existing optional-`Bool` pattern used by every `prescription*` flag, default on. Otherwise skip it — a setting nobody changes is a setting worth not building.

Worth deferring until the panel work in Phase 3.

---

## Work breakdown

### Phase 1 — foundation + input

- Rollup rules in `ExerciseMuscleGroupCatalog.normalizedValue`
- `MuscleAttribution` helper (Decision 2)
- `calves` color case
- **Secondary muscle picker in the exercise editor.** The "Muscles" section is primary-only ([CreateEditExerciseSheet.swift:112](Repster/Features/Exercise/Views/CreateEditExerciseSheet.swift:112)), but the view model already reads and writes the field ([:105](Repster/Features/Exercise/ViewModels/CreateEditExerciseViewModel.swift:105), [:157](Repster/Features/Exercise/ViewModels/CreateEditExerciseViewModel.swift:157)) — this is purely a multi-select control, no plumbing
- **Display on `ExerciseDetailView`** next to the primary badge ([ExerciseDetailView.swift:126](Repster/Features/Exercise/Views/ExerciseDetailView.swift:126))

Users can now see and edit secondary muscles. Nothing recalculates.

### Phase 2 — the two missing surfaces (the actual feature)

**Routine planning overview.** A summary in `CreateEditTemplateView` showing muscles covered by the exercises added so far — primary solid, secondary muted, updating live. `CreateEditTemplateViewModel` already carries `primaryMuscle` per exercise row ([:15](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:15)), so it needs secondary alongside it and a coverage strip in the view.

Worth considering here: which catalog groups get **nothing**, since "this routine hits no back" is the planning question users are really asking. That's the differentiator over a post-hoc panel.

**Post-workout muscle summary.** `WorkoutSummarySheet` shows no muscle data. A compact "worked today" strip using the same helper closes the loop at the moment users care most.

Neither needs the credit constant. Both are coverage, not arithmetic.

### Phase 3 — the existing trend surfaces

- Muscle volume panel + status loop, per Decision 3 and its two traps
- `MuscleBalanceInsightRule` stays primary-only
- Chart category filter honors secondary ([ChartDataService.swift:191](Repster/Core/Services/ChartDataService.swift:191))
- Exercise list filter matches secondary, sorted below primary matches ([ExerciseListViewModel.swift:121](Repster/Features/Exercise/ViewModels/ExerciseListViewModel.swift:121))
- `HealthProfile` toggle, if still wanted

### Leave alone

- **Charts donut** — one set fanning into several slices means the pie no longer sums to the total
- **Home / Calendar workout dots** ([HomeViewModel.swift:351](Repster/Features/Home/ViewModels/HomeViewModel.swift:351)) — include secondary and every workout shows the same three dots
- **Fatigue / e1RM model** — `FatigueLearningService` is per-exercise with no muscle concept. Untouched by any of this
- **Templates, export, AI generator** — already carry the field end to end; no archive version bump. The AI prompt should name the vocabulary, or it'll keep emitting off-catalog values

---

## What makes this cheap

There is **no persisted per-muscle aggregate anywhere**. `WorkoutSet`, `ExerciseStats`, and `InsightRecord` store no muscle attribution; `TrainingStatus` and every chart recompute live from sets on each read ([InsightsService.swift:422](Repster/Core/Services/InsightsService.swift:422)).

No migration. No stats rebuild. Numbers change on update.

---

## Open questions

1. **Does the routine overview show coverage or volume?** Coverage ("hits chest, shoulders, triceps") is simpler, needs no weighting, and matches the request. Volume-per-muscle-in-this-routine is the richer version and drags the credit constant into Phase 2. Recommend coverage.
2. **Is 0.5 right?** Phase 3 only. Not blocking.
3. **Re-tag the seed set?** Nobody has audited those 96 tags since they were written. Worth a pass before they drive visible numbers — but Phase 1 and 2 surface the tags as-is, which is itself a cheap way to find the wrong ones.
4. **Fine-grained taxonomy** (front/side/rear delts, glutes vs quads). Real demand in the thread. Separate project.

---

## Sequencing note

[COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md) ranks this **4th**, behind `bilateralLoadFactor` wiring, `Exercise.notes`, and custom-exercise analytics. That ranking holds — those three are smaller with larger matching demand, and items 1–3 there are independent enough to ship together.

Phase 1 here is small enough to ride along with them if convenient. Phase 2 is where this earns its place.

**Release target:** not 1.4. Slotted in [RELEASE_1_5_PLAN.md](RELEASE_1_5_PLAN.md)
— Phase 1 rides 1.5 if convenient, Phase 2 is proposed as the 1.6 headline, and
Phase 3 (the credit weighting) is deferred with no date.
