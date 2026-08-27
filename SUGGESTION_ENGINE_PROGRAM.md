# Smart Suggestions — one program of work

**Date:** 2026-08-26 · **Branch:** NewMain · **Status:** synthesis, no code changes

Four documents written in four sessions describe what is actually **one body of work on one
engine**. This doc maps them onto each other, resolves the places where they contradict, names
the root causes none of them owns, and proposes a single sequence.

| Doc | Written | Axis it covers | Status |
|---|---|---|---|
| [SMART_SUGGESTIONS_BEHAVIOR_AUDIT.md](SMART_SUGGESTIONS_BEHAVIOR_AUDIT.md) | 08-26 | **Within-session**: fatigue, capability updates | audit done, fixes not started |
| [SUGGESTION_PROGRESSION_DESIGN.md](SUGGESTION_PROGRESSION_DESIGN.md) | 08-26 | **Across-session**: does the number ever go up | P1 shipped, P2 open |
| [DROP_SETS_SCOPING.md](DROP_SETS_SCOPING.md) | 08-26 | **Per-set-type**: what a tagged set is worth | scoping only |
| [SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md) | 08-16 | Survey of all 13 types | superseded in part |
| [SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md) | 08-17 | A guardrail over the whole thing | parked |

The floor doc is included because all four reference it and two of them make decisions about it.

---

## 0. Start here

Everything below this section is reference. This part is the whole argument.

### What is actually broken

1. **The app throws away your easy sets.** A set at RIR 3+ can't raise its estimate of what you
   can lift, but still charges you fatigue for it. Telling the app a set was easy can only move
   the number down.
2. **The number can never go up between sessions.** At a fixed rep target the app hands back your
   last performance forever — and if you train above RIR 0, it hands back slightly *less* each
   time.
3. **One weird set poisons the rest of the exercise.** A drop set (or any light set) replaces the
   app's estimate of your capacity outright instead of nudging it.

They're the same engine, three stages apart. That's it.

### How big is it really

| | Code size | What's hard about it |
|---|---|---|
| Fix 1 — credit easy sets | **S** — one guard, one blend | Deciding *how much* credit: damped, or a ceiling |
| Fix 2 — make it progress | **M–L** | Not the code. Deciding whether the app prescribes or predicts |
| Fix 3 — drop sets don't crater it | **S** — one predicate | Nothing. Ship it |
| Plumbing before any of them | **S** | Nothing. Two fields, two names, one enum case |
| Drop sets visible in history | **M** | Independent of all the above |

Only **Fix 2** is a real project. Everything else is a handful of small edits to two functions.

### The one thing that makes it feel bigger than it is

All these changes touch the same learned fatigue rates (34 sessions, 41 exercises). Ship them one
at a time and you invalidate that calibration four separate times and can't tell which change
caused what. Ship them as **one release**, and the cost is paid once. That is the only reason
this has to be a program instead of four tickets.

### If you do one thing

Wave 0 plumbing, then Fix 1 + Fix 3 together in one release. That's a few days of small edits,
it fixes the complaint you actually hit in the gym, and it doesn't commit you to any answer on
Fix 2.

---

---

## 1. The one system underneath

`SuggestionEngine.evaluate` answers "what weight for this set" in four stages. Each document
owns a different stage's defects, which is why they read as unrelated.

| Stage | What it does | Code | Defects, and who found them |
|---|---|---|---|
| **1. Baseline** | What could you lift, historically | `peakAcrossRecentWorkouts` ([LoadPrescriptionService.swift:318](Repster/Core/Services/LoadPrescriptionService.swift:318)) over stored `set.e1RM` | **§R1 below — nobody owns it.** Floor doc names it in one line |
| **2. Session capability** | What can you lift right now, updated per completed set | `normalizedObservedCapability` ([:983](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:983)), `.observed` blend ([:269](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:269)) | AUDIT §2.1, §2.6 · DROP_SETS 4a, 4b |
| **3. Fatigue discount** | What this session has cost you | `computeSetFatigue` ([:638](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:638)), `setTypeMultiplier` ([:616](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:616)) | AUDIT §2.3, §2.4, §2.5 · DROP_SETS 4c, 4d · SET_TYPES P1 |
| **4. Prescription** | Turn capability into a weight and a rep count | range/fixed branch ([:740-767](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:740)) | PROGRESSION P1, P2, O3, O4 |

Two cross-cutting layers sit on top: the **explanation copy** (`contextualUserSummary`,
`SuggestionSelectionPolicy`) and the **learning loop**, which grades stages 2–3 and writes back
into stage 3.

### The thesis worth extracting

PROGRESSION states it and then buries it: the app has a **prediction** engine and the lifter is
asking for a **prescription**.

Stages 1–3 are all prediction. Three of the four documents are making the predictor more accurate.
Only PROGRESSION P2/O4 addresses the fact that a perfectly accurate predictor still never tells
you to lift more than you already have. **That is the difference between "the audit's fixes" and
"the feature the user was complaining about."** Both are worth doing; they are not substitutes,
and it is worth being clear which one you are buying when you pick up a phase.

---

## 2. Contradictions between the docs

### C1 — The drop-set fatigue multiplier: keep it or flatten it? · **RESOLVED: flatten**

Direct conflict, on the one type about to become selectable:

- **AUDIT §2.4** finds the multipliers double-count RIR and never survive rounding — but carves out
  an exception: *"dropset / rest-pause / myo / cluster: these are several mini-sets logged as one
  row, so reps and RIR structurally understate the work. There the multiplier carries information
  nothing else has."* Decision 5 keeps them intact.
- **DROP_SETS 4d** and **SET_TYPES Phase 1** both say flatten `setTypeMultiplier`.

**The audit's premise is factually wrong for `dropset` in this codebase.** No path ever puts several
efforts in one `dropset` row:

- Strong import tags an individual row `D` ([ImportService.swift:1001](Repster/Core/Services/ImportService.swift:1001))
- Hevy import tags an individual row `dropset` ([ImportService.swift:1359](Repster/Core/Services/ImportService.swift:1359))
- DROP_SETS Decision 2 chooses **one row per drop** for manual logging

So reps and RIR describe exactly one effort, and the 1.4× is asserting something the other terms
already price. The exception survives only for `myo`/`restpause`/`cluster` — which have no logging
flow at all, so there is no data for the multiplier to be right or wrong about.

**Action:** flatten as DROP_SETS 4d says; narrow the AUDIT §2.4 exception clause to
`myo`/`restpause`/`cluster` so the next reader doesn't re-litigate it.

### C2 — Three docs, three predicates, one guard · **needs one decision**

`normalizedObservedCapability` today ([:983](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:983))
gates on `!= .warmup && != .partial && rir < 3`. Three documents independently want to edit it:

| Doc | Wants |
|---|---|
| AUDIT §2.1 (Decision 1: **Fix**) | Relax the RIR gate — RIR ≥ 3 sets should credit capability, damped or as a ceiling |
| DROP_SETS 4a | Narrow the *type* filter to an allowlist: `working`, `amrap`, `failure` |
| FLOOR D5 | A **third** predicate for the floor: `working`, `backoff` |

Not strictly contradictory, but they disagree about `backoff`: DROP_SETS rejects it as capacity
evidence ("submaximal by definition"), FLOOR accepts it as floor evidence. Both are right, because
they are answering different questions — a back-off set at RIR 5 is a valid **lower bound** and a
bad **point estimate** — and that distinction is written down nowhere.

**Action:** name it, exactly as DROP_SETS Decision 3 already does for `countsAsPerformedWork` /
`isStraightWorkingSet`. Two predicates: `isCapacityPointEstimate` (stage 2 input) and
`isCapacityLowerBound` (floor input). The cure was invented in one doc without noticing it applies
in two more places.

### C3 — What caused the 32.5 kg Leg Extension undershoot? · **RESOLVED: the audit is right**

The same incident is attributed three different ways:

| Source | Primary cause |
|---|---|
| FLOOR doc | Three contributing defects; all three fixed still only reaches 37.5 → hence a floor |
| PROGRESSION O2 | *"the RIR chip topping out at 5+ … a floor would paper over that"* |
| AUDIT §2.1 | *"the engine-level cause … Fixing the RIR chip censoring at '5+' would not change any number in that table"* |
| Memory index | Records the PROGRESSION/chip attribution |

**The audit's evidence settles it.** RIR 3, 4 and 5 produce a byte-identical suggestion because
`actualRIR < 3` discards all three equally. The chip's ceiling can only change the *magnitude* of
the estimate once the gate is open; with the gate shut it changes nothing. The gate is primary;
the chip ceiling is a real but strictly secondary issue that **only becomes live after §2.1 ships**.

Two consequences:

1. PROGRESSION O2's *conclusion* (deprioritize the floor) survives, but its *reasoning* does not.
   Re-park it on the audit's grounds instead: the case is a stage-2 discard, and stage 2 is being
   fixed.
2. The memory index entry for this undershoot records the disproven attribution and should be
   corrected, or it will keep steering future sessions at the chip.

### C4 — Rep ranges: parked as presentation, or rebuilt as a ladder? · **sequence, don't decide twice**

- **AUDIT Decision 2** parks the within-session rep-range bounce: *"Not a bug. Revisit only as
  presentation."*
- **PROGRESSION O4** proposes double progression, which makes the range a *position you occupy
  across sessions*. The ladder would fix the rep target for the session and leave the fatigue model
  to price the weight — dissolving the within-session wander as a side effect.

PROGRESSION spots this (D5, and its Related-documents note that *"a stickiness rule for §2 and a
ladder for O4 should be designed together"*). The audit doesn't link back.

**Action:** do not build a presentation fix for §2.2 before O4 is decided. If O4 ships, §2.2 is
moot. If O4 is rejected, §2.2 becomes live again.

### C5 — Four changes each invalidate the same learned state; one doc knows

AUDIT §3 carries the sharpest operational constraint in the whole set:

> The learned rates are calibrated **around the current constants**. Changing `missingRIRDefault`,
> the set-type multipliers or `maxFatigue` silently invalidates 34 sessions of global learning and
> 41 per-exercise rates.

Now count the planned changes that trip it:

| Change | Doc | Trips it | Mentioned there? |
|---|---|---|---|
| Target-RIR fallback replaces `missingRIRDefault` | AUDIT §2.5 | yes | yes |
| Flatten `setTypeMultiplier` | DROP_SETS 4d / SET_TYPES P1 | yes | **no** |
| Exclude non-capacity types from learning | DROP_SETS 4c | yes — changes which observations feed the learner | **no** |
| Credit RIR ≥ 3 sets to capability | AUDIT §2.1 | yes — changes predictions, and prediction error is what the learner grades | **no**, not even in the audit's own constraint list |

**Four independent invalidations of the same 34 sessions + 41 rates.** Shipped separately, you burn
the calibration four times and can never attribute a regression.

**Action:** batch every constant- or input-changing edit into **one release with one re-convergence
plan**. This is the single strongest argument for treating these docs as one program.

---

## 3. Root causes no document owns

### R1 — There are two e1RM conventions, and they disagree about RIR

Every **engine** site computes e1RM on `reps + RIR`. Every **storage / stats** site computes it on
`reps` alone.

| Convention | Sites | 60 kg × 8 @ RIR 2 |
|---|---|---|
| `reps + rir` (engine) | [Protocol:815](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:815), [:1000](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:1000), [WeightSuggestionData:959](Repster/Features/Workout/Models/WeightSuggestionData.swift:959), [FatigueLearningService:210](Repster/Core/Services/FatigueLearningService.swift:210) | **80.0** |
| `reps` only (stored) | [SetService:161](Repster/Core/Services/SetService.swift:161), [:261](Repster/Core/Services/SetService.swift:261), [ImportService:158](Repster/Core/Services/ImportService.swift:158), [StatsService:179](Repster/Core/Services/StatsService.swift:179) | **76.0** |

`baseE1RM` — the cross-session baseline that seeds set 1 of every session — is the peak of the
**stored** value ([LoadPrescriptionService:318](Repster/Core/Services/LoadPrescriptionService.swift:318)).
So the app systematically understates the capacity of anyone who trains with reps in reserve, and
the same set is worth two different numbers depending on which side of the wall reads it.

This is the same disease DROP_SETS Decision 3 diagnosed for "what counts as a real set" — a
convention duplicated across call sites with nobody named as owner — found a second time and not
yet noticed.

**Why it matters to each doc:**

**It makes PROGRESSION P2 worse than the doc claims.** P2 says a fixed rep target is *"a mirror …
returns 60.0 kg exactly, every session, indefinitely."* That holds **only at RIR 0**. At a fixed
target of 8 reps @ RIR 2:

```
you do        60 × 8 @ RIR 2
stored e1RM   60 × (1 + 8/30)              = 76.0     ← RIR dropped
next session  76.0 / (1 + 10/30)           = 57.0 → 57.5 kg
then          57.5 × (1+8/30) = 72.8 → 54.6 → 55.0 kg
```

Not a plateau — a **ratchet down of roughly 4% per session**, on the first suggestion of every
session, for anyone programming above RIR 0. The field report that opened PROGRESSION was at RIR 0,
which is the *best* case. (67.3% of this user's logged RIR values are 0 — §3 of the audit — which is
exactly why this has stayed hidden.)

*Confidence:* derived by reading the two code paths and the Epley round trip, not observed
end-to-end. One test confirms or kills it — see §5.

**It is invisible to the audit's harness.** `SmartSuggestionBehaviorScenarioTests` injects
`baseE1RM: 100` straight into `SuggestionEngine.evaluate`
([:90](RepsterTests/SmartSuggestionBehaviorScenarioTests.swift:90)) rather than deriving it from
logged sets through `SetService`. The 22 scenarios are structurally incapable of seeing a
storage↔engine convention split. That is a gap in the harness, not just in the docs.

**It is the floor doc's defect #1**, named in one line and then parked along with the rest of that
doc.

**It does *not* break the cross-session drop-set case**, and it's worth saying why:
`peakAcrossRecentWorkouts` takes a **max**, so a low drop-set e1RM is harmless there. The
within-session path craters (DROP_SETS 4a) precisely because `.observed` **replaces outright**
instead of taking a max. Max vs. replace is the whole difference — a useful one-line summary of why
4a is a real bug and the cross-session equivalent isn't.

### R2 — `SessionSetContext` is the shared bottleneck

Three docs want to reach data that isn't in it ([:10](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:10)):

| Doc | Needs | Consequence today |
|---|---|---|
| AUDIT §5 | target RIR | the principled missing-RIR fix is blocked; falls back to a constant |
| DROP_SETS 4b | prescribed weight | can't mirror the learner's 20% deviation guard; settles for a cheaper clamp |
| FLOOR | nothing — it's a pure function of what's there | correct as written |

Thread `targetRIR` and `prescribedWeight` **once** and two docs get their first-choice design
instead of their fallback. Independently, each looks like a cost not worth paying; together it's
one small change.

PROGRESSION O4 is the only item in the whole program needing genuinely new *persisted* state
(ladder position) — worth isolating for exactly that reason.

### R3 — One "why this number" surface, three independent extensions

`SuggestionSelectionPolicy` has two cases ([:564](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:564)).
FLOOR D7 wants a `floorApplied` flag or a third case; PROGRESSION O4 wants a third case for the
ladder; AUDIT §2.2's parked presentation fix lands in the same copy layer that P1 just changed.
Decide the shape of that surface once rather than three times.

---

## 4. Collision map

Functions more than one document wants to edit. This is the concrete reason these can't be
independent sessions.

| Site | Docs | Risk |
|---|---|---|
| `normalizedObservedCapability` [:983](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:983) | AUDIT §2.1, DROP_SETS 4a | Two different rewrites of the same guard |
| `.observed` blend [:269](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:269) | AUDIT §2.1 (damped credit), DROP_SETS 4b (asymmetric clamp) | Both change how one set moves capability |
| `setTypeMultiplier` [:616](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:616) | AUDIT D5 (keep), DROP_SETS 4d + SET_TYPES P1 (flatten) | **C1** |
| `FatigueObservation` setType field | DROP_SETS 4c, SET_TYPES P1 | Same change written twice |
| `evaluate` [:753-787](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:753) | FLOOR (insert clamp), PROGRESSION O4 (new branch) | Same insertion point |
| `SessionSetContext` | AUDIT §5, DROP_SETS 4b | **R2** |
| `SmartSuggestionBehaviorScenarioTests` (22 scenarios) | every stage-2/3 change | The tables are a golden master and **will** move. Only the audit knows they exist |

---

## 5. Proposed sequence

### Wave 0 — Foundations · no user-visible change

Everything here is mechanical, unblocks the rest, and can land in any order.

- [ ] Name the conventions. `countsAsPerformedWork` / `isStraightWorkingSet` (DROP_SETS D3),
      `isCapacityPointEstimate` / `isCapacityLowerBound` (C2), and one e1RM helper that forces every
      call site to state whether it includes RIR (R1).
- [ ] Thread `targetRIR` + `prescribedWeight` onto `SessionSetContext` (R2).
- [ ] Add `setType` to `FatigueObservation` (DROP_SETS 4c / SET_TYPES P1) — **instrumentation lands
      before any constant changes**, which is the one point both those docs already agree on.
- [ ] Extend the scenario harness to derive `baseE1RM` from logged sets for at least one scenario,
      so R1 becomes visible to tests.
- [ ] **The R1 confirming test:** log 60 × 8 @ RIR 2 through `SetService`, then ask for a suggestion
      at a fixed target of 8 @ RIR 2. Assert ≥ 60. Predicted to fail at 57.5.

### Wave 1 — The capability stage · one release, one recalibration

All four trip C5. Ship together or burn the calibration repeatedly.

- [ ] AUDIT §2.1 — credit RIR ≥ 3 sets (damped, or as a ceiling)
- [ ] DROP_SETS 4a — capacity allowlist, using the Wave 0 predicate
- [ ] DROP_SETS 4b — asymmetric downward clamp (now able to be the real deviation guard, per R2)
- [ ] AUDIT §2.5 — target-RIR fallback
- [ ] **Decide R1** — align stored e1RM with the engine convention, or keep stored e1RM as a display
      value and derive baselines with RIR. *The largest unowned decision in the program, but it has
      a cheap answer:* `WorkoutSet.rir` is already persisted
      ([:27](Repster/Data/Models/WorkoutSet.swift:27)), so the baseline read path can recompute with
      RIR without rewriting a single stored row. No migration, no mixed-convention data. Rewriting
      stored `e1RM` instead would need a backfill and would move every chart and PR — don't.
- [ ] One learning reset / re-convergence plan covering the whole wave
- [ ] Re-baseline the 22 scenarios and record the deltas

Reassess the floor **after** this wave, not before. Its motivating case is a stage-2 discard and
stage 2 is what this wave fixes.

### Wave 2 — Decide prediction vs. prescription (PROGRESSION O4, D1–D6)

A product decision, not a calculation. PROGRESSION's own recommendation — start with the degenerate
fixed-target case — is right, and R1 makes it more urgent: at RIR > 0 a fixed target doesn't
plateau, it decays. AUDIT Decision 2 stays parked until this is answered (C4).

### Wave 3 — Drop sets, user-visible (DROP_SETS Phases 2–3)

Independent of Waves 1–2 in content, gated on Wave 1 in time — which is DROP_SETS' own sequencing
note. Carries the two latent history-numbering bugs, which are worth fixing regardless.

### Wave 4 — Flatten the multipliers (DROP_SETS 4d)

Last, with Wave 0's instrumentation in hand — which was always the argument for its position.
Resolve C1 in favour of flatten and amend the AUDIT §2.4 exception.

---

## 6. Decisions that need you

1. **R1 — which e1RM convention wins?** Blocks Wave 1 and quietly governs every cross-session
   number in the app.
2. **O4 — predictor or prescriber?** And PROGRESSION D6: setting, or a default?
3. **DROP_SETS open questions 1–3** — drop sets and PRs, volume, rest timer.
4. **DROP_SETS open question 4** — should `failure` / `amrap` become selectable? Note the
   interaction: 4a treats them as the *best* capacity evidence, so making them selectable increases
   the value of 4a rather than just adding picker rows.

## 7. Housekeeping

- **Three of these four docs are untracked in git** (`DROP_SETS_SCOPING.md`,
  `SMART_SUGGESTIONS_BEHAVIOR_AUDIT.md`, `SUGGESTION_PROGRESSION_DESIGN.md`); `SET_TYPES_SCOPING.md`
  is modified and uncommitted. One `git clean` from gone.
- The memory index entry for the Smart Suggestions undershoot records the attribution the audit
  disproves (C3).
- PROGRESSION cites `WeightSuggestionDataRowStateTests` as though it were a file; the class lives at
  [ActiveWorkoutViewModelSuggestionRefreshTests.swift:2083](RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift:2083).
