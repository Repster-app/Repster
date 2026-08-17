# Set Types — Scoping

**Status:** scoping only, nothing built
**Date:** 2026-08-16

## The problem, stated properly

`SetType` ([SetType.swift](Repster/Data/Enums/SetType.swift)) has 13 cases. Twelve of them are labels the user cannot see attached to features that were never built. The thirteenth — warm-up — is the only one carrying its weight.

There are **two separate problems** here and they should not be solved together:

1. **Labels without features.** Tagging a set "Drop Set" changes nothing about how you log it.
2. **An invisible coupling to the suggestion engine.** Each type silently scales session fatigue, which moves prescribed weight. Nobody can see this, and the model cannot learn its way out of it.

Problem 2 is a live correctness issue in the app's headline feature. Problem 1 is a product gap. Fixing 2 is small and should not wait for a decision on 1.

---

## What's actually true today

Three tiers of behavior hide behind thirteen labels:

| Tier | Types | Behavior |
|---|---|---|
| **Real** | `warmup` | W1/W2 badge, 50% dimmed row, own rest-timer default, inserted above working sets, excluded from volume (unless `includeWarmupsInVolume`), PRs, charts, e1RM baselines, fatigue learning |
| **Real** | `partial` | Excluded from volume, PRs, charts, load prescription — no user override anywhere |
| **Cosmetic** | the other 11 | Identical to `working` everywhere except one fatigue constant. No badge, no color, no label, no distinct logging, no export column |

**Creation paths.** The app only creates `working` and `warmup` (`+ Add Set` / `+ Add Warmup`). The other 11 arrive via:

- long-press → Edit Set Type ([SetRowView.swift:259](Repster/Features/Workout/Views/SetRowView.swift:259)) — the only in-app route, and it lists all 13 with no grouping
- Strong CSV import → `dropset`, `failure` ([ImportService.swift:991](Repster/Core/Services/ImportService.swift:991))
- Hevy CSV import → `dropset`, `failure` ([ImportService.swift:1345](Repster/Core/Services/ImportService.swift:1345))
- AI-generated templates, which are handed all 13 raw values ([TemplateListSheet.swift:980](Repster/Features/Templates/Views/TemplateListSheet.swift:980))

So there is live user data with these types, mostly from importers. Not a clean slate.

### Evidence this matters

From [COMPETITIVE_FEATURE_ANALYSIS.md:104](COMPETITIVE_FEATURE_ANALYSIS.md:104), advanced set types are the **single largest competitor gap** (~16 distinct requests): myoreps and myorep matching, auto-calculated drop sets, partials/half-reps, a "Deload" label distinct from Normal and Warm-up, EMOM, time under tension.

The answer is therefore not "delete the enum." It's that the enum shipped ahead of the feature.

---

## Decision 1 — decouple set type from fatigue (blocking, small, do first)

`SuggestionEngine.setTypeMultiplier` ([LoadPrescriptionServiceProtocol.swift:608](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:608)) assigns each type a fatigue coefficient from 0.5 to 1.5. These constants appear in **no design doc and no commit message**. They are undocumented magic numbers.

**What they do.** Per-set fatigue is `learnedRate × typeMult × effortScale × repScale`, and the result discounts effective e1RM. At the default rate (0.03), 8 reps @ RIR 2, default rest 150s against a 180s recovery constant (43% carryover):

| | Per-set discount | By set 4–5 (steady state) |
|---|---|---|
| Working (1.0×) | 3.5% | ~6.1% |
| Failure / AMRAP (1.5×) | 5.2% | ~9.2% |
| Back-off (0.7×) | 2.4% | ~4.3% |

On set 2 the Working↔Failure gap is ~0.75% of e1RM — under a kilo on a 100 kg e1RM, gone in rounding. **By set 4–5 it's ~3 percentage points**, which is a real plate. At the top of the learned-rate range (0.08) the gap widens to ~8 points and the 0.25 fatigue cap starts binding. So: invisible early, quietly material late.

**The structural flaw, which is worse than the calibration.** [`FatigueObservation`](Repster/Data/Models/FatigueObservation.swift) does not record `setType`. The learner reduces a session to one median error and nudges a single per-exercise rate by ±0.002, then also updates the global profile rate ([FatigueLearningService.swift:600](Repster/Core/Services/FatigueLearningService.swift:600)).

Consequence: if a multiplier is wrong, the prediction error it causes gets **absorbed into that exercise's learned fatigue rate** and applied to every set of that exercise regardless of type — and can drag the global rate with it. The multipliers can never be validated or corrected by data, only laundered into a parameter that is supposed to mean something else.

**Recommendation.** Flatten to the three tiers that have a defensible basis:

```
warmup  → 0.0   (a warm-up genuinely shouldn't accrue working fatigue)
partial → 0.5   (matches the existing exclusion logic)
all others → 1.0
```

and add `setType` to `FatigueObservation` so per-type multipliers can be *learned* later instead of asserted. Keeping unvalidated constants that corrupt the learned rate is the worst of the three options; deleting them outright without instrumenting loses the chance to ever do this properly.

**Blast radius:** two assertions ([`testAMRAPMultiplierIsHigherThanWorking`, `testBackoffMultiplierIsLowerThanWorking`](RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift:5381)), one row in the admin diagnostics drawer ([WeightSuggestionCardView.swift:376](Repster/Features/Workout/Views/Components/WeightSuggestionCardView.swift:376)), one SwiftData field addition. Nothing user-facing changes, because nothing user-facing exposed it.

---

## Decision 2 — the enum conflates two different things (blocking, shapes everything after)

This is the central claim of the doc. The 13 cases mix two categories that need completely different solutions:

**A. Execution structure** — one "set" composed of several efforts, needing multiple weight/rep entries under one set number:

> `dropset`, `restpause`, `cluster`, `myo`

**B. Effort annotation** — one ordinary set with a label describing how it was taken:

> `amrap`, `failure`, `backoff`, `tempo`, `isometric`, `eccentric`, `partial`

Group B needs **no data model change at all** — a visible badge and correct stats treatment is the whole feature. Group A needs sub-set rows, which is a genuine schema and set-table change.

Treating these as one enum is why 13 types shipped with 0 features: the cheap half was blocked behind the expensive half.

**Recommendation:** ship Group B as visible annotations first. It's most of the list, it's cheap, and it makes the types mean something immediately.

---

## Decision 3 — where a visible type indicator goes (blocking for Group B)

There is **no room for a new column.** The row is already `36pt badge | flexible inputs | 42pt RIR | 44pt PR badge | 40pt checkbox` ([SetRowView.swift:210](Repster/Features/Workout/Views/SetRowView.swift:210)) — 162pt of fixed columns before the inputs get anything.

Options, in order of my preference:

1. **Reuse the 36pt badge column.** Warm-up already does exactly this (`W1`, `W2`). Extend the pattern: `D1` drop set, `F` failure, `A` AMRAP, `B` back-off. Zero layout change, consistent with what exists, and readable at a glance. Limitation: 1–2 characters, so the type must be inferable from a letter.
2. **Row accent** — a 2pt colored leading edge plus the type name in the row's note line. More expressive, but competes with the note indicator and the editing-state border.
3. **Only in the expanded/edit state.** Cheapest, but fails the actual complaint: you still can't scan a finished workout and see which set was the drop set.

Option 1 also needs a rule for numbering — today working sets renumber from 1 while warm-ups count separately ([SetTableView.swift:139](Repster/Features/Workout/Views/SetTableView.swift:139)). Annotated sets should keep their working-set number (a failure set is still working set 3), so the letter is a *suffix*, not a replacement: `3F`.

---

## Decision 4 — which types survive, and migration

Trimming the enum is not free. Raw values are persisted in SwiftData, written into the JSON archive ([ExportService.swift:489](Repster/Core/Services/ExportService.swift:489)), and produced by both importers. Removing a case requires a mapping for existing rows, or old archives fail to decode.

| Type | Verdict | Note |
|---|---|---|
| `warmup`, `working` | Keep | The only two the app creates |
| `partial` | Keep | Real exclusion behavior; but see open question 2 |
| `dropset`, `failure` | Keep | Both importers emit these — cannot be dropped without a migration |
| `amrap`, `backoff` | Keep | Cheap Group B annotations, commonly requested |
| `myo`, `restpause`, `cluster` | Keep, unbuilt | Group A. Explicitly requested in the competitor analysis |
| `tempo`, `isometric`, `eccentric` | **Candidates to cut** | No import path, no request evidence, no plan to build |
| — | **Candidate to add** | `deload` — named directly in the competitor analysis, distinct from back-off |

Cutting three cases saves little and costs a migration. **Recommendation: keep all 13, add `deload` if Group B ships**, and instead fix the real problem with the list — the context menu presents 13 undifferentiated options. Group it: Warm-up / Working at top, then "Effort" and "Structure" sections.

---

## What each Group A type would actually need (deferred, sized only)

| Type | Needs | Size |
|---|---|---|
| **Drop set** | Sub-rows sharing one set number, auto weight-drop % (configurable, default ~20%), no rest timer between drops, volume summed across drops | L — schema + set table |
| **Rest-pause** | Same sub-row structure + intra-set rest. **`WorkoutSet.pauseDuration` already exists, is exported, and is written by nothing** — a dead field that looks purpose-built for this | M — reuses existing field |
| **Cluster** | Sub-rows + fixed intra-set rest, near-identical to rest-pause | S once rest-pause exists |
| **Myo-rep** | Activation set + mini-sets, plus "matching" (stop when reps fall below target) | L — needs its own logging flow |

All four share the same primitive: **a set that contains sub-sets.** Build that once and three of the four are configuration. That primitive is the real Group A decision, and it interacts with `supersetGroupId` (already on `WorkoutSet` and populated from templates) — worth checking whether one grouping mechanism can serve both before designing a second.

---

## Work breakdown

### Phase 1 — stop the bleeding (small, no user-visible change)
- Flatten `setTypeMultiplier` to warmup 0.0 / partial 0.5 / all else 1.0
- Add `setType` to `FatigueObservation`; keep writing the existing audit trail
- Update the two multiplier-ordering tests
- Leave the diagnostics drawer row in place — it now reads 1.0× for everything, which is the truth

### Phase 2 — make the labels mean something (Group B, the actual win)
- Badge suffix in the existing 36pt column (Decision 3, option 1)
- Grouped context menu
- Confirm stats treatment per annotation type — currently all of Group B counts fully toward volume and PRs; that's probably right for AMRAP and failure, questionable for back-off
- Add `deload` if it survives Decision 4

### Phase 3 — the sub-set primitive (Group A)
- Design the sub-set data model once, against both `supersetGroupId` and `pauseDuration`
- Drop set first (both importers already produce it, so there's real data to display correctly)
- Rest-pause and cluster follow as configuration
- Myo-rep last — it needs its own logging flow

### Leave alone
- Warm-up behavior in every consumer. It's correct and well-covered.
- Partial exclusions from volume/PR/charts/prescription.
- The learning pipeline's structure — Phase 1 adds a field, it doesn't change the algorithm.
- Superset plumbing, until Phase 3 evaluates it.

---

## Open questions

1. **Should annotated sets count toward PRs?** A set taken to failure producing a PR is legitimate. An AMRAP is arguably the *best* PR evidence. Back-off is not. Today they all count identically. Needs a per-type answer before Phase 2 ships badges that imply the app knows the difference.
2. **Is `partial`'s blanket exclusion right?** It's excluded from volume with no override, while warm-ups get a setting. Partials are a real training tool; a user logging lengthened partials sees zero volume credit and no way to change that.
3. **What happens to the 11 types' existing data on flatten?** Nothing breaks — the label persists, only the coefficient changes. But users who imported from Strong/Hevy will see suggestions shift slightly on exercises where they have `dropset`/`failure` sets. Small, but it's a real behavior change in shipped software and worth a line in release notes.
4. **Does the AI template generator need a narrower vocabulary?** It's currently handed all 13 raw values and can emit types the app can't meaningfully log.

## Sequencing note

Phase 1 is independent and should go in regardless of what's decided about Phases 2 and 3 — it removes an unauditable effect from the suggestion engine and starts collecting the data needed to do per-type fatigue properly later. Phase 2 is the one users would actually notice. Phase 3 is a real feature project and shouldn't be started until the sub-set primitive is designed on its own.
