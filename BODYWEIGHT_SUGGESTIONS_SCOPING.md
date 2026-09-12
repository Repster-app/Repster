# Bodyweight exercises & Smart Suggestions — scoping

**Date:** 2026-09-10 · **Branch:** NewMain · **Status:** scoped, nothing built · **Target:** 1.6 (1.5 scope is locked)

Field report, 2026-09-10 (the developer's own account): a custom exercise with **Equipment =
Bodyweight**, a bodyweight entry logged on **3 September**, workout on **9 September** — and the
wand had nothing to offer. The exercise's Advanced settings show **Bodyweight Factor 0**.

The short version: this is not one bug, and it is not the user's fault. Pricing a bodyweight set
passes through **three independent gates**, a normal user fails at least one, and the app's UI
tells them everything is fine. Behind the gates are a units defect and a modelling mismatch, and
every fix touches stored data that eight other surfaces read.

---

## 1. How a bodyweight set is priced today

```
weight text ─► parseDisplayedWeight ─► SetService.computeEffectiveWeight ─► e1RM (only if > 0) ─► suggestion baseline
```

`effectiveWeight = weight + closestBodyweight × bodyweightFactor`, computed once at save time
([SetService.swift:590](Repster/Core/Services/SetService.swift:590)) and persisted. Everything
downstream reads the stored value.

### The three gates

| # | Gate | Code | What fails it |
|---|---|---|---|
| G1 | The weight field is not blank | [SetService.swift:595](Repster/Core/Services/SetService.swift:595) `guard let weight else { return nil }` | **Leaving it blank — the natural thing to do on a push-up.** `parseDecimal("")` is nil ([UnitConversion.swift:48](Repster/Core/Extensions/UnitConversion.swift:48)), and this guard runs *before* the factor is consulted |
| G2 | `bodyweightFactor > 0` | [SetService.swift:601](Repster/Core/Services/SetService.swift:601) | Custom exercises default to `0.0` ([CreateEditExerciseViewModel.swift:33](Repster/Features/Exercise/ViewModels/CreateEditExerciseViewModel.swift:33)). Picking Bodyweight as equipment does not set it. CSV import creates exercises as `.other` with factor 0 ([ImportService.swift:139](Repster/Core/Services/ImportService.swift:139)) |
| G3 | A `BodyweightEntry` exists when the set is **saved** | [SetService.swift:611](Repster/Core/Services/SetService.swift:611) | The onboarding bodyweight step only exists since `2066de7` (2026-08-17) and is optional. Upgraders never see it — `hasCompletedOnboarding` is a one-shot flag ([RepsterApp.swift:12](Repster/App/RepsterApp.swift:12)). HealthKit is write-only, `read: []` ([HealthKitService.swift:116](Repster/Core/Services/HealthKitService.swift:116)) |

Pass all three and you get `effectiveWeight > 0`, which is the only way to get an `e1RM`
([SetService.swift:159](Repster/Core/Services/SetService.swift:159)), which is the only way to
get a suggestion baseline ([LoadPrescriptionService.swift:313](Repster/Core/Services/LoadPrescriptionService.swift:313)).
Fail any one and the set is stored with no e1RM, permanently.

**The field report fails G2 for certain, and probably G1 as well.** G3 passed: the entry predated the
workout, and `fetchClosest` looks both before and after the set date
([BodyweightEntryRepository.swift:40](Repster/Core/Repositories/BodyweightEntryRepository.swift:40)).

### Equipment = Bodyweight is a label and nothing else

Exhaustive search: the `.bodyweight` equipment case is referenced in exactly two places — the seed
JSON mapping ([SeedExerciseDTO+Mapping.swift:54](Repster/Core/Seeding/SeedExerciseDTO+Mapping.swift:54))
and `isBodyweightStyle` ([Exercise.swift:76](Repster/Data/Models/Exercise.swift:76)), which is
`equipmentType == .bodyweight || bodyweightFactor > 0` — an **OR**. Its only consumer is
`weightLabel`, which prints `"BW"` instead of `"0 kg"`
([WorkoutSetPerformanceFormatter.swift:413](Repster/Core/Formatting/WorkoutSetPerformanceFormatter.swift:413)).

So the display asks the OR and every calculation asks `factor > 0` alone. The row says "BW × 8"
— the app confirming it understood — while `effectiveWeight`, `e1RM`, PRs, stats, charts and the
suggestion baseline treat the set as a 0 kg barbell.

### Seeded exercises don't rescue anyone

Only five seeded exercises carry a factor: Pull-up and Chin-up 0.65, Dip 0.8, Push-up 0.64, Inverted Row 0.5
([seed_exercises.json](Repster/Resources/seed_exercises.json)). And `SeedService` runs **once**,
only when the Exercise table is empty
([SeedService.swift:15](Repster/Core/Services/SeedService.swift:15)). Any change to seed data
never reaches an existing install.

### What one real history shows *(n=1 — mechanisms only, not population sizing)*

From `RepsterTests/Fixtures/Local/real-history.repsterbackup` (exported 2026-08-13; 171 exercises,
11,785 sets):

| Exercise | Equipment | Factor | Completed sets | Weight field | Sets with e1RM |
|---|---|---|---|---|---|
| Incline Push-up | Bodyweight | 0 | 6 | **all blank** | 0 |
| Decline | Bodyweight | 0 | 9 | 3 blank, 6 with a weight | 6 |
| Burbee | Bodyweight | 0 | 1 | blank | 0 |
| Assisted Pull Up | Other | 0 | 18 | **assistance logged as positive weight** | 18 |

- Every exercise marked Bodyweight has factor 0. None were seeded ones.
- Blank is what a lifter types on a bodyweight move. G1 is not an edge case.
- Assistance is being logged as load, so the engine reads *more help* as *more strength* (§5 C7).
- The archive carries no bodyweight entries — a known gap ([RELEASE_1_6_CONSIDERATIONS.md §1.1](RELEASE_1_6_CONSIDERATIONS.md)).

---

## 2. What a user sees today

The wand shows **"Not enough history"** (`.noStrengthData`), which is false — they have plenty.
If they once logged a weighted variant it shows `.bodyweightHistoryOnly` instead
([LoadPrescriptionService.swift:267](Repster/Core/Services/LoadPrescriptionService.swift:267)).
Nothing they can do in the app clears either one.

For the users who **do** pass all three gates (seeded exercise + a typed weight + a bodyweight entry), the
app already contradicts itself about the same set:

| Surface | Reads | A pull-up at BW, 80 kg lifter |
|---|---|---|
| Set row / performance label | `set.weight` ([Formatter:23](Repster/Core/Formatting/WorkoutSetPerformanceFormatter.swift:23)) | `BW × 8` |
| History grid weight cell | `effectiveWeight ?? weight` ([Formatter:117](Repster/Core/Formatting/WorkoutSetPerformanceFormatter.swift:117)) | `52 kg` |
| Suggestion done strip | `effectiveWeight` ([WeightSuggestionData.swift:395](Repster/Features/Workout/Models/WeightSuggestionData.swift:395)) | `52 kg` |
| Suggestion chip and card | `prescribedWeight` | `~55 kg` (§3) |
| Share card muscle slices | `set.weight`, falls back to **raw reps** ([WorkoutSummarySheet.swift:1146](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:1146)) | `8` summed alongside bench's `800` |

Volume already has three definitions: `effectiveWeight × reps` (stats, charts, Insights, workout
summary); `weight × reps`, or reps alone when weight is 0 (share card); and zero by design for
bodyweight (the Insights comment at [InsightsService.swift:552](Repster/Core/Services/InsightsService.swift:552)).

---

## 3. The units defect · **believed, not yet observed**

For users who pass all three gates, the suggestion is in the wrong space.

- Every engine input is effective weight: the baseline ([LoadPrescriptionService.swift:368](Repster/Core/Services/LoadPrescriptionService.swift:368))
  and the in-session sets ([WeightSuggestionData.swift:338](Repster/Features/Workout/Models/WeightSuggestionData.swift:338)).
- So `prescribedWeight = round(e1RM × intensity)` comes out as effective weight.
- It reaches the chip unchanged ([WeightSuggestionData.swift:819](Repster/Features/Workout/Models/WeightSuggestionData.swift:819) →
  [SetTableView.swift:1767](Repster/Features/Workout/Views/SetTableView.swift:1767)), and tapping
  writes it into the weight field ([SetTableView.swift:2019](Repster/Features/Workout/Views/SetTableView.swift:2019)),
  which holds **added** weight.
- No consumer of `suggestedWeight` subtracts a bodyweight component (every consumer checked:
  chip, card, explainer, both snapshots).

**Consequence:** the chip reads "55 kg" where the answer is "+2.5 kg". Tap it and the set stores
`55 + 52 = 107 kg` effective. The baseline is the **peak of the last three workouts**
([LoadPrescriptionService.swift:34](Repster/Core/Services/LoadPrescriptionService.swift:34)), so
one poisoned session inflates the next three.

**Who hits it today:** seeded Pull-up, Chin-up and Push-up users who type a 0, and **every weighted-dip or
weighted pull-up user** who types their added load and has a bodyweight on file. +10 kg on a dip at 80 kg
bodyweight is 74 kg effective; the chip suggests about 75.

**Status:** derived from the code, not yet reproduced. §7 step 0 pins it with a test before anything
is built on the assumption.

### What is consistent today and must stay that way

The learning and measurement paths are currently correct **because** they are entirely in
effective space:

| Path | Compares | Code |
|---|---|---|
| Fatigue-learning deviation | `PredictionSnapshot.prescribedWeight` vs actual effective weight | [FatigueLearningService.swift:214](Repster/Core/Services/FatigueLearningService.swift:214), snapshot at [ActiveWorkoutViewModel.swift:464](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:464) |
| Adherence analytics (`suggestion_followed_share`) | audit prescribed vs audit actual | [FatigueLearningService.swift:383](Repster/Core/Services/FatigueLearningService.swift:383) |
| Suggestion floor | completed session sets, effective | [LoadPrescriptionServiceProtocol.swift:1241](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:1241) |
| Done-strip "vs sug" | effective vs effective | [WeightSuggestionData.swift:395](Repster/Features/Workout/Models/WeightSuggestionData.swift:395) |

**The trap:** converting `SetSuggestion.suggestedWeight` to added weight at the source would flow
into `PredictionSnapshot`. Deviation becomes `|effective − added| / added`, which exceeds 20% on
every bodyweight set, so learning **silently stops** (`weightDeviationOver20Percent`), and adherence
reads as 100% "heavier". The conversion belongs at the display/apply boundary, and the snapshot
has to stay effective.

### The grid is anchored at zero

`roundToIncrement` snaps to multiples of the increment from 0
([LoadPrescriptionServiceProtocol.swift:1345](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:1345)).
With a bodyweight component of 52.0 kg, effective prescriptions land on 52.5 and 55 — that is
**+0.5 kg** and **+3 kg** added, neither loadable. Subtracting at display time can't fix this.
The engine needs the bodyweight component as an input (a load offset) and has to round
`offset + round(raw − offset)` at all four sites: the prescription (`:881`), the push option (`:965`),
the range candidates (`:996`) and the floor's "next grid value" (`:1269`).

**Below zero:** when readiness × intensity falls under the bodyweight component, the added weight
goes negative, meaning "less than your bodyweight". The keypad can't express that: it clamps to ≥ 0
([SetTableView.swift:2046](Repster/Features/Workout/Views/SetTableView.swift:2046)) and rejects "-"
in the weight field (`:2058`). That boundary is exactly where the rep axis (§4) is needed.

---

## 4. The wrong axis

On a bodyweight movement the load is fixed and **reps are the free variable**. The engine only
ever solves for weight at a given rep target. The default target is 8 @ RIR 2
([HealthProfile.swift:105](Repster/Data/Models/HealthProfile.swift:105)), so even a perfectly
priced push-up gets told a weight.

### Scale invariance makes the rep solve cheap

All three formulas have the form `weight × g(reps)` ([E1RMFormula.swift:30](Repster/Data/Enums/E1RMFormula.swift:30)).
At constant load:

```
w · g(r' + RIR) = w · g(r_best) · readiness   ⇒   g(r' + RIR) = g(r_best) · readiness
```

The load cancels. **A rep prescription for a pure-bodyweight set needs no bodyweight, no factor
and no stored e1RM** — so it works for users failing G1, G2 and G3 alike. Bodyweight only matters when
bodyweight and weighted sets are mixed in one history, because added load changes the ratio.

### What carries over and what doesn't

| Engine part | Weight-free? | Note |
|---|---|---|
| Fatigue accumulation and decay | Yes | `repScale` uses reps only ([:761](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:761)); τ decay is time-only |
| Calibration adjustment | Yes | Multiplicative on readiness |
| Capability gate (RIR rules) | Yes | Same R1 evidence rules apply |
| Baseline | **No** | Built from stored `e1RM > 0` ([:313](Repster/Core/Services/LoadPrescriptionService.swift:313)); these sets have none. Needs a rep-space baseline read from reps and RIR |
| Suggestion floor | **No** | Weight-based; needs a rep analogue ("did N @ RIR r at this load") |
| Push option | **No** | Adds load; in rep mode it's "top of range to failure" |
| Range candidates | Partly | Iterate reps instead of pricing them — same shape as [`repRangeCandidates`](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:983) |
| Increment rounding | N/A | Reps are integers |

### The high-rep problem

Bodyweight work lives at 10–40 reps, where e1RM formulas are at their weakest:

- **Brzycki is undefined at 37 reps and negative beyond** — `36 / (37 − r)`. A 40-rep push-up set
  under Brzycki produces a negative e1RM.
- Target reps are normalised to 1…30 ([WeightSuggestionData.swift:653](Repster/Features/Workout/Models/WeightSuggestionData.swift:653)).
- Epley doubles the load at 30 reps. Predictions at those counts are extrapolation.

The engine header already cites a rep drop-off model (Nuzzo/SBS), which is natively rep-space.
It's worth checking whether that literature fits better than an e1RM inversion here. That's decision D6.

### Duration is a third axis

Plank and Dead Hang are excluded outright ([WeightSuggestionData.swift:367](Repster/Features/Workout/Models/WeightSuggestionData.swift:367)).
Same inversion, with seconds. **Out of scope** — named so the rep-axis abstraction doesn't come out
as a weight-vs-reps binary.

---

## 5. Candidate changes and what each one moves

### C1 · Couple equipment to factor · **size XS**

Choosing Bodyweight prefills a factor. The field gets help text and is surfaced beside the
equipment picker rather than buried in Advanced ([CreateEditExerciseSheet.swift:157](Repster/Features/Exercise/Views/CreateEditExerciseSheet.swift:157)).

- **Only affects exercises created or edited afterwards.** Existing custom exercises stay at 0.
- Editing the factor on an exercise with history rebuilds PRs and stats but **not** `effectiveWeight`
  ([ExerciseService.swift:229](Repster/Core/Services/ExerciseService.swift:229): "never
  recalculates retroactively"). The e1RM and volume charts **step** at the edit date — the same
  symptom §3.1 of the 1.6 doc describes for `bilateralLoadFactor`.
- **Which default?** Movement-specific values are right for pulls, dips and push-ups, and nonsense for core
  work (crunch, leg raise). A generic 0.65 on a crunch invents an e1RM.
- **Not enough on its own:** G1 still kills blank-weight sets. And a user who does type a weight
  walks straight into §3.
- Template import already carries the factor ([TemplateService.swift:570](Repster/Core/Services/TemplateService.swift:570)).

### C2 · Treat a blank weight as 0 on bodyweight-style exercises · **size XS code, M consequences**

In `computeEffectiveWeight`, nil weight plus a positive factor prices as 0 kg added.

- **PR storm.** Every bodyweight rep count already has a `PerformanceRecord` at **0 kg** (the first set
  created it). The first post-change set at each rep count beats it by grams
  ([PRService.swift:105](Repster/Core/Services/PRService.swift:105)), so each one badges as a PR.
  Follows from the code path; not observed.
- **Mixed history display.** Grid cells flip from "BW" to "52 kg" for new sets only, while older
  rows in the same list still read "BW".
- **Insights muscle volume.** Back and chest volume in the current window rises against a baseline
  that has none. This is the TrainingStatus volume panel only; the volume-ramp insight counts
  **sets**, not volume ([InsightRules+Progress.swift:351](Repster/Core/Services/InsightRules+Progress.swift:351)),
  so it doesn't misfire.
- **e1RM charts** gain bodyweight exercises from the change date, with nothing before it (charts filter
  `e1RM > 0`, [ChartDataService.swift:394](Repster/Core/Services/ChartDataService.swift:394)).
- **Fatigue learning** starts using bodyweight sets (currently `invalidPerformance` on `actualWeight ≤ 0`). Correct, but new.
- **Suggestions appear**, and every one hits §3. **C2 must not ship before C3.**
- The share card is unaffected (it reads `set.weight`).

### C3 · Fix the units at the suggestion boundary · **size S — a live defect**

Pass the bodyweight component into the engine as a load offset. Round in added space. Show and
apply added weight. **Keep `PredictionSnapshot` in effective space.**

Surfaces that must change together, or the module contradicts itself:

- chip label and apply ([SetTableView.swift:1767](Repster/Features/Workout/Views/SetTableView.swift:1767), `:2019`)
- card ([WeightSuggestionCardView.swift:125](Repster/Features/Workout/Views/Components/WeightSuggestionCardView.swift:125), `:145`, `:177`)
- explainer, including its "rounded to your steps" and "capacity" copy ([SuggestionExplainerSheet.swift:87](Repster/Features/Workout/Views/Components/SuggestionExplainerSheet.swift:87), `:155`, `:345`)
- push option, floor, range candidates (the offset grid)
- the done strip — both sides converted, or both left effective

Must **not** change: `PredictionSnapshot.prescribedWeight`, the fatigue-learning deviation, adherence.

- A negative added weight needs an interim answer until C4 lands: show "BW" plus the rep count the
  model implies.
- The engine golden master ([SuggestionEngineGoldenMaster.txt](RepsterTests/Fixtures/SuggestionEngineGoldenMaster.txt))
  is unchanged with offset 0; add bodyweight cases.
- **lbs users:** the offset grid is anchored in display units.
- **Which bodyweight?** The same entry `SetService` would use for a set saved now (closest to
  today). Historical e1RMs were priced at their own dates, so if bodyweight moved, capacity moved with it.

### C4 · Rep-axis suggestions · **size M–L — the feature**

- **Decision shape:** `SuggestionDecision.prescribedWeight: Double` becomes an enum
  (`.load / .reps / .duration`) or gets a sibling field. Consumers to follow: `SetSuggestion.suggestedWeight`,
  chip, card, explainer, done strip, both snapshots, adherence (weight-only — rep-mode sets would drop out of
  `comparableSets`, so analytics needs a mode property), the fatigue-learning deviation filter
  (weight-based; needs a rep analogue or an explicit exclusion), the golden master, and
  `SmartSuggestionBehaviorScenarioTests`.
- **UI:** the wand moves to the reps field, which currently hosts `repRangeButton`.
- **Baseline:** best `(reps + RIR)` at bodyweight over the last three workouts, under the same R1 RIR rules.
- **Mixed histories:** without a bodyweight component, bodyweight and weighted sets live in incomparable spaces.
  Build the rep baseline from bodyweight sets only, and the load baseline from weighted sets only when an
  offset exists.
- **Mode switch:** compute the added weight first. At or below 0 → rep mode. If the solved reps exceed
  the top of the range → load mode. That is **double progression** — the same hypothesis as
  [SUGGESTION_OPEN_QUESTIONS.md §1](SUGGESTION_OPEN_QUESTIONS.md). **Decide the two together**;
  they're the same mechanism.
- `.bodyweightHistoryOnly` stops being a dead end; it becomes rep mode.
- Needs D6 (the high-rep model) settled first.

### C5 · Backfill · **size M — this is [RELEASE_1_6_CONSIDERATIONS.md §3.1](RELEASE_1_6_CONSIDERATIONS.md)**

Recompute `effectiveWeight` and `e1RM` for **null-case** sets, then rebuild PRs and stats.

- **The case for touching history at all:** the write-time snapshot is right for a set priced
  *with* a bodyweight — it shouldn't be re-priced when you weigh more. A set priced *without* one
  stored a null, not a historical fact.
- **Detection:** on an exercise with a positive factor, a set whose `effectiveWeight == weight`, or which is nil
  under C2, was priced without a bodyweight component.
- **"Never retroactive" is already untrue per set:** `SetService.edit` re-prices with the
  **current** log on any edit ([SetService.swift:248](Repster/Core/Services/SetService.swift:248)).
  Fix the reps on a three-month-old pull-up and it is silently re-priced. So there is precedent, and
  there is an existing inconsistency to decide on.
- **What visibly moves:** PR badges reshuffle across history; e1RM and volume charts gain history; history
  cells flip from "BW" to kg; Insights volume baselines jump (uniformly, so comparisons hold).
  Fatigue audits stay as written — they're records.
- **Restore reverts it:** the archive carries `effectiveWeight` but no bodyweight entries (1.6 §1.1). A
  pre-backfill backup restores pre-backfill values. So the backfill must be idempotent,
  re-runnable, and a no-op without entries.
- **Import disagrees with save:** it prices every row with the single entry closest to *now*
  ([ImportService.swift:279](Repster/Core/Services/ImportService.swift:279)); `SetService` uses the
  set's own date. A backfill should use the set's date.
- **Crash surface:** a bulk write across all sets. It must run inside the repository actor, never on
  main, and never during an active workout — the SwiftData model-lifetime history is why.
  Extend `PipelinePerformanceTests`.
- **Opt-in vs automatic:** 1.6 §3.1's recommendation on file is an explicit, opt-in, one-time
  action — and one answer covering `bilateralLoadFactor` and the machine offset too. The null case
  argues for automatic; the PR reshuffle argues for opt-in. That's D3.

### C6 · A reliable bodyweight source · **size S**

- **Read body mass from HealthKit.** It adds a read type and a permission prompt, and changes the
  privacy policy (served from `NewMain:/docs` — pushing NewMain is the deploy) and the App Store
  privacy label. App Review surface.
- **Ask just in time:** prompt on the first bodyweight exercise logged with no entry. That targets the
  activation window, which is where growth is bottlenecked.
- Reaches upgraders, who never saw the onboarding step.

### C7 · Assistance · **decide now, build later**

The real history has an Assisted Pull Up logged as positive weight. The engine progresses assistance
**upward** (easier). PRs reward more help. Volume counts the assist as load.

- **Options:** an `assisted` flag with `effective = offset − assist` (needs a bodyweight component), or
  negative factor semantics (collides with every `factor > 0` gate).
- **Settle the sign convention before C3 and C4**, since the offset maths is where it lands.

---

## 6. Measurement — the size of this can't be read today

- `exerciseCreated` carries no `equipmentType` ([RELEASE_1_6_CONSIDERATIONS.md §2.1](RELEASE_1_6_CONSIDERATIONS.md)).
- No event carries the suggestion unavailable reason, or whether a bodyweight entry exists.
- The only signal is the onboarding step `units_bodyweight` — since 2026-08-17 only, and it records
  that the screen was seen, not that a value was entered.

**Add before building:** `equipmentType` on `exerciseCreated`; a bucketed unavailable reason on the
workout-completed event; a suggestion-mode property once C4 exists. Without them there's no way to
tell whether any of this helped. **Don't size it from the developer's own history** — 200+ users
train differently.

---

## 7. Recommended order

| Step | What | Why this position |
|---|---|---|
| 0 | **Tests that pin today's behaviour** — the units defect (exercise factor 0.65, entry 80 kg, three workouts at 0 × 8 @ RIR 2, evaluate, assert prescribed ≈ effective) and the blank-weight gate | §3 is believed, not seen. Nothing gets built on it until it's reproduced |
| 1 | Measurement (§6) | Needs a release of data before it can say anything |
| 2 | **C3** units fix + the **C7** sign decision | A live defect for weighted-dip and pull-up users; also the precondition for C1 and C2 |
| 3 | **C4** rep axis, designed jointly with double progression | Makes the wand work for users failing G1–G3 **without touching stored data** — no PR storm, no chart step, no backfill |
| 4 | **C1 + C2 + C5** as one unit, under 1.6 §3.1 | They're the data-semantics change; shipping any of them alone creates mixed displays and PR storms |
| 5 | C6 HealthKit read | Independent; carries privacy-policy work |

The fork between steps 3 and 4 is the real choice. **Reps first** fixes the experience for the most
users and leaves history alone. **Load first** fixes what the data means and leaves the wand dead
for everyone who logs bodyweight sets blank. Reps first is recommended.

---

## 8. Open decisions

| # | Decision | Blocks |
|---|---|---|
| D1 | Does Equipment = Bodyweight **imply** a factor, or stay a label? | C1 |
| D2 | Is a blank weight on a bodyweight exercise 0 or nil? | C2 |
| D3 | Backfill: automatic for the null case, or opt-in as 1.6 §3.1 recommends? And should `edit()` keep re-pricing? | C5 |
| D4 | Assistance sign convention | C3, C4 |
| D5 | `SuggestionDecision`: enum or sibling field | C4 |
| D6 | High-rep model: cap reps, restrict the formula, or a rep drop-off model | C4 |
| D7 | Label: `BW+10 kg` or `90 kg` ([1.6 §1.3](RELEASE_1_6_CONSIDERATIONS.md)) — the suggestion display follows whichever wins | C3 |
| D8 | Bodyweight PR semantics: effective weight (gaining weight is a PR) or reps at bodyweight | C2, C5 |

---

## 9. Workaround for the field report

On the exercise: set **Bodyweight Factor** to the right value (0.65 pull-up or chin-up, 0.8 dip, 0.64
push-up, 0.5 inverted row), **and type `0` in the weight field** on every set — a blank field skips the
factor entirely (G1). Past sets stay unpriced. Expect the first set at each rep count to badge as a PR (C2).
**Don't tap the suggestion** until §3 is fixed.

---

## 10. Verified vs believed

| Claim | Evidence |
|---|---|
| The three gates and their order | Code, read end to end |
| Blank weight is stored as nil in practice | Code, plus the real history (6/6 Incline Push-up sets) |
| Equipment Bodyweight affects only the label | Exhaustive search of `.bodyweight` and `isBodyweightStyle` |
| Seed data never reaches existing installs | Code (`SeedService` gate) |
| Rebuild never recomputes `effectiveWeight` | Code, plus the comment at `ExerciseService.swift:229` |
| `edit()` re-prices with the current log | Code |
| **Units defect** | **Derived from code, not reproduced** — step 0 |
| **PR storm under C2** | **Derived from the PRService path, not observed** |
| Volume ramp is unaffected | Code (counts sets) |
| How many users are affected | **Unknown** — §6 |

## Related documents

- [RELEASE_1_6_CONSIDERATIONS.md](RELEASE_1_6_CONSIDERATIONS.md) — §1.1 archive, §1.3 label, §2.1 analytics, §2.2 bilateral, §3.1 backfill policy
- [SUGGESTION_OPEN_QUESTIONS.md](SUGGESTION_OPEN_QUESTIONS.md) §1 — double progression, the same mechanism as C4's mode switch
- [SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md](SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md) G11 — unilateral and bodyweight in PR2
- [SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md) — the floor C3 must re-grid and C4 must re-express
- [ONBOARDING_REDESIGN_SCOPING.md](ONBOARDING_REDESIGN_SCOPING.md) — where the bodyweight step came from
