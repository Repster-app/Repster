# Smart Suggestions — implementation plan

**Date:** 2026-08-27 · **Branch:** NewMain · **Status:** PF1, PR1, PR2, PR3 built and green (568 tests, 0 failures)

| Step | State |
|---|---|
| PF1 golden master | **done** — `RepsterTests/Fixtures/SuggestionEngineGoldenMaster.txt`, 37 scenarios / 110 prescriptions |
| PR1 predicates | **done** — golden master unchanged, so provably behaviour-neutral |
| PR2 input enrichment | **done** — golden master unchanged |
| PR3 baseline reads RIR | **done** — mutation-checked: reverting the fix fails 3 tests at exactly 57.5 kg |
| PR4-PR8 | not started |
| PF2 target-RIR coverage | still outstanding, still the only measurement on the critical path |
| PF3 adherence metric | still outstanding, still wants to ship a release early |
**Companion to:** [SUGGESTION_ENGINE_PROGRAM.md](SUGGESTION_ENGINE_PROGRAM.md) (the why)

This is the build order. Section 3 is the part to read before starting — it lists what none of
the four source docs considered, including two items that change the design.

---

## 1. Pre-flight — do these before writing engine code

**PF1 · Freeze a golden master.** `SmartSuggestionBehaviorScenarioTests` prints its numbers but
stores nothing. Dump all 22 scenarios to a committed fixture first, so every later PR produces a
reviewable diff instead of an eyeballed one. Without this you cannot tell an intended change from
a regression, and five PRs in a row change these numbers.

**PF2 · Measure target-RIR coverage.** The missing-RIR fix (PR5) depends on knowing what RIR a set
was prescribed at. Query `real-history.repsterbackup` for what fraction of completed app-era sets
can resolve a target. If it's low, PR5's value drops sharply — see **G1**, which already changes the
design. *This is the only measurement still on the critical path; the constants backtest was
removed by decision 1.*

**PF3 · Ship the adherence metric in the *current* release, not this one.** There is no way today to
tell whether suggestions are good — see **G2**. It has to land at least one release *ahead* of the
engine changes or there is no before-picture to compare against. This is the single highest-value
item in the document and it is not engine work.

---

## 2. Build order

Numbers are relative sizes, not estimates. PRs 3–7 **ship as one release** (see §2.9).

### PR1 · Name the conventions · no behaviour change

Add to [SetType.swift](Repster/Data/Enums/SetType.swift):

| Predicate | Means | Members |
|---|---|---|
| `countsAsPerformedWork` | The denylist, named | all except `warmup`, `partial` |
| `isStraightWorkingSet` | An ordinary set | `working` |
| `isCapacityPointEstimate` | "This tells me what you can lift" | `working`, `amrap`, `failure` |
| `isCapacityLowerBound` | "This tells me what you can *at least* lift" | `working`, `backoff` |
| `userSelectable` | Offerable in the picker | `warmup`, `working`, `dropset` |

Swap the engine's inline checks to these names. **Do not** touch the ten `== .working` consumer
sites yet — that's PR9, and it is user-visible.

*Acceptance:* 22 scenarios byte-identical to PF1.

### PR2 · Enrich the engine's inputs · no behaviour change

- `SessionSetContext` ([:10](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:10))
  gains `targetRIR: Double?` and `prescribedWeight: Double?`.
- **Source `targetRIR` from `resolveTarget`, not from `WorkoutSet.targetRIR`** — see **G1**. This
  means calling `resolveTarget` for completed sets in `resolveWorkingSets`
  ([:350](Repster/Features/Workout/Models/WeightSuggestionData.swift:350)), where completed sets
  currently `continue` past it.
- `FatigueObservation` gains `setType`.

Fields are carried but unread. *Acceptance:* 22 scenarios byte-identical.

### PR3 · Baseline reads RIR (R1)

`peakAcrossRecentWorkouts` ([:318](Repster/Core/Services/LoadPrescriptionService.swift:318))
recomputes e1RM as `formula.calculate(weight: effectiveWeight, reps: prReps + performanceRIR)`
instead of reading the stored `set.e1RM`. **Stored `e1RM` is never written** — charts, PRs and
history don't move.

Keep `(set.e1RM ?? 0) > 0` in `isEligibleForCapacity` as an eligibility gate; only the *value*
changes.

*Tests:* log 60 × 8 @ RIR 2 through `SetService`, ask for a fixed target of 8 @ RIR 2, assert ≥ 60
(predicted to fail at 57.5 today). Plus a no-RIR regression asserting today's behaviour is
unchanged.

### PR4 · Capability crediting (Fix 1 + Fix 3)

**Design decided 2026-08-27: credit RIR ≥ 3 sets as a lower bound, not as a damped point estimate.**
The audit listed both. The damped version needs a tuning constant and can overshoot; the lower-bound
version needs no constant and structurally cannot suggest more than one increment above a weight the
lifter actually completed with reps to spare. Both land on 37.5 kg for the reported case.

This un-parks [SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md) — it is
not a competing idea, it is the constant-free implementation of Fix 1. Build it as specified there
(D1–D9, 13 test cases), with two amendments:

- Use PR1's `isCapacityLowerBound` predicate rather than D5's inline type list.
- D5 excludes `.amrap` / `.failure` on the grounds that their RIR is definitionally 0 so the surplus
  never clears — still true, keep them out of the *floor*, but they remain `isCapacityPointEstimate`
  members and must keep feeding the point estimate.

In `normalizedObservedCapability` ([:983](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:983)):

- Gate on `isCapacityPointEstimate` instead of `!= .warmup && != .partial`.
- Keep the `actualRIR < 3` gate for the point estimate — the floor now covers that blind spot, which
  is what D2 argues.
- **Do not narrow `isCapabilityTrackingSetType`** ([:1042](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:1042)) — it also arms the freshness bonus.
- Clamp per-set *downward* capability movement (DROP_SETS 4b). **No upward clamp is needed** — the
  lower-bound design cannot run away, which is why **G4** is now closed.

*Tests:* the floor doc's 13 cases; re-derive the §2.1 RIR table; drop-set-craters-capability;
freshness bonus not re-armed after a drop set; downward clamp bound.

**One constant to decide**, and it is the benign one: the downward clamp percentage. Anchor on the
learner's existing 20% weight-deviation guard
([FatigueLearningService.swift:203](Repster/Core/Services/FatigueLearningService.swift:203)). Failure
mode is capability drifting down more slowly than it should — no failed reps. Write it next to the
existing constants at [:586](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:586)
with a comment saying why, since undocumented magic numbers there are what SET_TYPES complained about.

### PR5 · Missing-RIR fallback (Fix 1b)

Replace `missingRIRDefault = 1.0` with the resolved target RIR from PR2; keep the constant only for
sets with no resolvable target at all.

### PR6 · Learning exclusions (Fix 3c)

Add a `nonCapacitySetType` case to `FatigueLearningAuditStatus`
([SetType.swift:38](Repster/Data/Enums/SetType.swift:38)) with title and detail; exclude those sets
in `FatigueLearningService`. Check the archive decoder tolerates an unknown status raw value on
downgrade — see **G8**.

### PR7 · One-time recalibration on upgrade

`resetAllLearning()` already exists and is thorough
([FatigueLearningService.swift:378](Repster/Core/Services/FatigueLearningService.swift:378)) — it
clears per-exercise rates, observations, audits and the global profile rate. **Its only caller is
the hidden admin screen** ([FatigueLearningAdminView.swift:44](Repster/Features/Settings/Views/FatigueLearningAdminView.swift:44)).

Add a versioned run-once launch hook that calls it, records that it ran, and is idempotent. It must
fire **after** the new engine code is active, never before.

### PR8 · Re-baseline and release notes

Regenerate the PF1 fixture, review the diff deliberately, add the WhatsNew line — see **G9**.

### 2.9 Why 3–7 are one release

Each of PR3–PR7 independently invalidates the same 34 sessions of global learning and 41
per-exercise rates. Shipped separately you pay the recalibration four times and can never attribute
a regression to a change. One release, one reset, one before/after comparison.

### Then, independently

- **PR9–PR11 · Drop sets visible.** Picker to three types; shared badge/numbering helper across the
  three renderers; audit the ten `== .working` sites per DROP_SETS Decision 3. Fixes two latent
  history-numbering bugs on the way.
- **PR12 · Flatten `setTypeMultiplier`.** Last, with PR2's instrumentation in hand.
- **Deferred · Progression (Fix 2).** Needs the predictor-vs-prescriber decision first.

---

## 3. What we hadn't considered

Ordered by how much they change the plan.

### G1 · The missing-RIR fix would have been a no-op for most users · **changes the design**

The audit proposes falling back to "the target RIR that set was prescribed at" and calls it *"one
field to thread through."* The field is the easy part; the **source** is the trap.

`WorkoutSet.targetRIR` is written **only by `TemplateService`**. Ad-hoc sets — `+ Add Set`, the
whole non-template flow — leave it nil forever. Sourced that way, PR5 would silently degrade to the
old constant for every user who doesn't run templates, and look like it worked.

The fix: `resolveTarget` ([:382](Repster/Features/Workout/Models/WeightSuggestionData.swift:382))
already has a full fallback chain ending at a profile-level default, and it is currently called for
pending sets only. Call it for completed sets too and every user gets a real target. **PR2 is
written this way.**

### G2 · Nothing measures whether any of this worked · **do this first, in the previous release**

The only suggestion analytics is `suggestion_refreshes` — a tally
([AnalyticsServiceProtocol.swift:226](Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift:226)).
Nothing records whether the lifter **accepted** the suggested weight, went heavier, or went lighter.
That ratio is the whole quality signal for this feature.

The data already exists locally — the audit trail flags `weightDeviationOver20Percent` — it is just
never aggregated or reported. Add a per-workout adherence property (accepted / heavier / lighter,
bucketed) and ship it **one release ahead**, or the engine release has no baseline to be compared
against and you will be arguing from vibes again in a month.

### G3 · Set 1 of a new exercise is untouched by the entire program · **name it, then park it**

The largest observed error — 32.5 vs 45 kg — was a *first session on a new exercise*. Trace it:
PR3 needs history, PR4 needs a completed set, and the floor guardrail *"cannot fire on set 1"* by
its own admission. **Nothing in this plan improves the first suggestion on a brand-new exercise.**

That is the probe-mode idea buried in the floor doc's Limits section, and it is in no wave. Given
your growth memory says post-install activation is the bottleneck, and a new user's first exercise
is by definition a first exposure, this may deserve to outrank Fix 2.

### G4 · Fix 1 is the first change that can make the app ask for too much · **CLOSED by decision 1**

Every existing failure mode is "too light". Fix 1 inverts that: it moves the number **up**, driven
by the least trustworthy input in the system — self-reported RIR, which the audit notes is treated
as a went-to-failure flag by 67% of entries.

DROP_SETS 4b clamps downward moves; nothing clamped upward. This is why PR4 uses the lower-bound
design rather than a damped point estimate: a floor one increment above a weight you actually
completed **cannot** overshoot, so no upward clamp is needed. Recorded because it is the reason for
that choice — "suggests more than you can lift" is a materially worse experience than "suggests a
bit light". One is a disappointment, the other is a failed rep.

### G5 · The "5+" chip · **DECIDED: accept and cap** (decision 4)

Today the chip ceiling is harmless: `SetTableView` stores `value: 5` for the "5+" label
([:1271](Repster/Features/Workout/Views/SetTableView.swift:1271)), and RIR ≥ 3 is discarded anyway,
so the truncation changes nothing. After PR4 that truncation feeds the capability estimate directly.
Someone with 13 reps in reserve gets credited with 5.

Under the lower-bound design the truncation is bounded and conservative: a "5+" set floors the
suggestion at one increment above what they lifted, which is right even if their true reserve was
13. Accept it this release, extend the chip later, never inflate — inflating is the only option that
can overshoot.

### G6 · "Session fatigue" is actually per-exercise fatigue · **nobody has asked whether that's right**

`currentSets` is scoped to the current exercise
([ActiveWorkoutViewModel.swift:276](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:276)),
so `completedSessionSets` never contains a set from any other exercise. Squat 5×5, move to leg
press, and the model starts from **zero fatigue**.

Every one of the four docs calls this "session fatigue." The audit's §2.3 finding is really "no
memory past set 3 *of one exercise*", which makes its "100% of app-era exercise-sessions are ≤ 4
sets" defence weaker than it reads — and makes `maxFatigue = 0.25` even more unreachable than
measured. Whether fatigue should cross exercises is a real modelling question that has never been
put.

### G7 · No kill switch · **DECIDED: yes** (decision 5)

`prescriptionEnabled` / `fatigueEnabled` / `freshnessEnabled` are user settings, but PR4's new
behaviour would ship as unconditional code. If it over-credits in the wild there is no lever short
of an App Store release. Put PR4 behind a profile flag defaulted on.

### G8 · Archive round-trip for the new audit status

PR6 adds a `FatigueLearningAuditStatus` case. The enum is `Codable` and reaches the JSON archive.
Confirm an older build decoding a newer archive degrades gracefully rather than failing the whole
restore.

### G9 · Everyone's numbers change on the same day, silently

Suggestions shift and the learned calibration resets for every user at once. `WhatsNewSheet` exists
and should carry a line — including the honest part: *suggestions may look different for a week
while it re-learns.* Also check what PR7's reset does to a workout that is **in progress** across
the upgrade.

### G10 · Light loads still get a coarse staircase · **cheap, unassigned, and aimed at new users**

Audit §2.7: a beginner on a 2.5 kg increment feels −8.3% between sets where a 100 kg lifter feels
−3.3%. `Exercise.weightIncrement` already exists
([Exercise.swift:92](Repster/Data/Models/Exercise.swift:92)) — so a smarter per-exercise default for
light loads is a small change that lands squarely on the population your growth notes say is the
bottleneck. It is in no wave.

### G11 · Unilateral and bodyweight sets need care in PR2

`prReps` is `max(L, R)` and `performanceRIR` is the harder side, both per-side; `SessionSetContext.weight`
is `effectiveWeight`. Threading a resolved target RIR into that context means matching normalized
space, not display space — the same trap the floor doc flagged as `target.reps` vs
`target.displayReps`. Add a unilateral case to PR2's tests.

---

## 4. Coaching module — what this plan does to it

Checked against [COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md), whose top tile
("Model check": suggested vs actual) is exactly the performance-vs-expected question.

### The record already exists, and is already backed up

`FatigueLearningSetAudit` ([FatigueObservation.swift:91](Repster/Data/Models/FatigueObservation.swift:91))
stores, per set: `predictedEffectiveE1RM`, `baseE1RM`, `prescribedWeight`, `actualWeight`,
`actualReps`, `actualRIR`, `deviationFraction`, `normalizedError`, `setType`, `visibleSetNumber`,
and a typed `status` explaining why a set wasn't used. It covers **every** set, not just the ones
that fed learning — which makes it a better coaching substrate than `FatigueObservation`, the
narrower learning-only row.

Both tables are written into the JSON archive
([ExportService.swift:82-101](Repster/Core/Services/ExportService.swift:82)), so this history
survives device changes and restores.

### C1 · PR7 would delete all of it · **decide before building PR7**

`resetAllLearning()` prunes observations to zero **and** calls `auditRepo.deleteAll()`
([FatigueLearningService.swift:378](Repster/Core/Services/FatigueLearningService.swift:378)). Ship
the one-time recalibration as written and every user's performance-vs-expected history is wiped on
upgrade day — the exact data the Model check tile is built on.

**Recommendation: a calibration epoch, not a delete.** Stamp rows with a model version, reset the
*learned rates* only, and keep the history with its epoch marked. Learning reads the current epoch;
coaching reads across all of them. Cheap now, impossible to retrofit — deleted rows don't come back.

### C2 · Retention favours audits over observations

Observations are pruned to the last **30 sessions per exercise**
([FatigueLearningService.swift:126](Repster/Core/Services/FatigueLearningService.swift:126)).
Adequate for learning, thin for trend coaching. Audits have no routine pruning — better for
coaching, but nobody has checked how large that table grows. Worth measuring against
`real-history.repsterbackup` before building on it.

### C3 · "Fatigue across different things" is the one thing the data can't answer today

There is no cross-exercise fatigue: `currentSets` is exercise-scoped, so the model resets to zero
at every exercise change (**G6**).

| Question | Answerable today? |
|---|---|
| How does fatigue behave *within* an exercise | Yes — learned `Exercise.fatigueRate`, decay curves |
| Which exercise costs you most | Yes — the "Fatigue cost" tile, gated on learned-not-default |
| What position in the session costs you | **Yes, and for every user** — the "Session order" tile computes decay from `orderInWorkout` + `e1RM` directly, bypassing the Smart Suggestions gate |
| Systemic / whole-session fatigue | **No.** The model never accumulates across exercises |

Your own coaching doc already picks Session order as the one to build first, for exactly the right
reason: it needs no engine change and works for users who never touch the wand. That covers most of
what "fatigue across different things" means in practice.

Genuine systemic fatigue is an engine change. **If coaching wants it, decide now** — PR4 is
rewriting the capability path anyway, and retrofitting accumulation across exercises afterwards
means touching it twice.

### C4 · The coverage gate compounds

Both tables only exist where Smart Suggestions produced a prediction — the gate COACHING_TILES
already names as the reason Model check can't be Tier 1. Note the compounding the audit adds: a set
with no RIR is also skipped for audit, so **the users with the least data get the least coaching**.
PR5 does not fix this; only prompting for RIR would.

---

## 5. Decisions — settled 2026-08-27

| # | Decision | Call |
|---|---|---|
| 1 | How to credit RIR ≥ 3 sets | **Lower bound, not damped credit.** No tuning constant; cannot overshoot. Un-parks the floor guardrail as PR4's implementation |
| 2 | Upward clamp | **Not needed.** The lower-bound design can't run away — **G4** closed |
| 3 | Downward clamp % | **Anchor on the existing 20% deviation guard.** The one remaining constant, benign failure mode |
| 4 | What "5+" means | **Accept the truncation, cap the credit, say so.** Extend the chip later; never inflate |
| 5 | Kill switch | **Yes.** One `Bool` on `HealthProfile`, defaulted on, one admin-drawer row. PostHog flags are the remote option if wanted — needs setting up outside this repo |
| 6 | Systemic (cross-exercise) fatigue | **Out of this release, but don't wall it off.** When PR4 opens the capability path, structure the accumulator so cross-exercise carry-over is later a change, not a rewrite (**C3**, **G6**) |
| 7 | Calibration epoch (**C1**) | **Keep the history.** Stamp rows with a model version and reset the rates only. Blocks PR7; the one irreversible item |

### Why the damping factor is no longer on this list

Decision 1 removes it. Once the floor is live, the adherence metric (**G2**) reports whether lifters
routinely go *heavier* than the floor — which is direct field evidence of how much reserve they
actually had, from real users, rather than a backtest against the 6.4% of RIR values that are ≥ 3.
If that evidence later justifies a damped point estimate on top of the floor, it will come with a
number attached instead of a guess. **Revisit after one release of adherence data.**

### Still open, but scheduling rather than blocking

- **G3** — first exposure to a new exercise is improved by nothing in this plan. Weigh against Fix 2.
- **G10** — the light-load rounding staircase, aimed squarely at new users.
- **C2** — measure how large the audit table grows before building coaching on it.
