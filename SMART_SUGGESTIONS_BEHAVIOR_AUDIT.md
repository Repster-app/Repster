# Smart Suggestions & fatigue — behaviour audit and decision record

**Opened:** 2026-08-26 · **Branch:** NewMain · **Status:** audit complete, fixes not started

Covers a user-POV audit of the Smart Suggestions / fatigue engine, the empirical data behind it,
and every decision taken in review. Structured for comparison against other workstreams.

- **Harness:** [RepsterTests/SmartSuggestionBehaviorScenarioTests.swift](RepsterTests/SmartSuggestionBehaviorScenarioTests.swift) — 22 scenarios, prints the numbers the card would show
- **Engine:** `SuggestionEngine` in [LoadPrescriptionServiceProtocol.swift:583](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:583)
- **Full suite after this work:** 538 tests, 4 skipped, 0 failures

Re-run:

    xcodebuild test -scheme Repster -destination 'id=<sim>' \
      -only-testing:RepsterTests/SmartSuggestionBehaviorScenarioTests

---

## 1. Method and why

The formulas already had unit coverage. Nothing checked whether the resulting *numbers are
believable to a lifter*. This audit drives the real engine through whole sessions at production
defaults (rest 150 s, increment 2.5 kg, fatigue on, freshness off, base rate 0.03, tau 180 s,
`.observed` capability policy, Epley) and reads the output as a user would.

Findings were then checked against real training data — see §3.

---

## 2. Findings

### 2.1 CONFIRMED — Sets at RIR >= 3 are discarded, and the weight still drops

Same set logged at 75 kg x 8, varying only the reported RIR. What set 2 prices:

| Reported RIR | Set 2 | Session fatigue |
|---|---|---|
| 0 | 67.5 kg | 4.3% |
| 1 | 70.0 kg | 3.9% |
| 2 | 72.5 kg | 3.4% |
| 3 / 4 / 5 | **72.5 kg (identical)** | 3.0% |

RIR 3, 4 and 5 are one dead value. A lifter reporting "five left in the tank" gets a *lower*
weight than they just lifted.

RIR does two jobs. **Fatigue cost** always uses it, at every value. **Capability estimate** —
backing out "what could this person do for one rep right now" — is gated at
[`actualRIR < 3`](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:994).
The in-code reasoning is legitimate (RIR self-report is unreliable far from failure; e1RM formulas
degrade past ~10 reps to failure). But the fatigue subtraction still charges the set while the
capability credit refuses it — so telling the app a set was easy can only move the number down.

This is the engine-level cause of the recorded 32.5-vs-45 kg undershoot. Fixing the RIR chip
censoring at "5+" would not change any number in that table.

**This is also the root of "the model has no upward gear" (§2.6).**

### 2.2 DOWNGRADED — Rep-range weight bounce is a presentation issue, not a bug

Originally logged as a correctness defect: rep-range sessions prescribe non-monotonic weights,
e.g. the 5-8 range going 77.5 -> 75 -> 72.5 -> **77.5**.

**That framing was wrong.** Reps and weight trade off. Checking the actual demand (implied e1RM of
each prescription at target RIR) shows it decreasing monotonically in all three ranges tested:

| Set | Prescribed | Implied e1RM (real demand) |
|---|---|---|
| 3 | 72.5 kg x 8 | 96.67 |
| 4 | 77.5 kg x 5 | **95.58** — weight up, demand down |

Every instance where the bar weight rises, the rep target falls further, so the set is *easier*.
The engine is internally consistent.

What remains is presentational: bar weight is the most salient number on the card, and it rising
mid-session reads as broken even when the prescription got lighter. The rep target also wanders
inside the range (7, 7, 8, 5, 5, 5) with no visible logic.

**Parked** — see §4.

### 2.3 CONFIRMED but LOW PRIORITY — No memory past about set 3

Twelve sets of 8 @ RIR 2 at defaults:

    set  1   2    3    4    5    6    7 ... 12
    kg  75  72.5 72.5 70   70   70   70    70
    fat  0%  3.4% 4.9% 5.6% 5.9% 6.0% 6.1%  6.1%

Fatigue saturates at 6.1% by set 4 and never moves. Decay between sets (e^(-150/180) = 0.435)
cancels accumulation almost immediately.

`maxFatigue = 0.25` is effectively unreachable:

| Configuration | Peak over 12 sets | Hits ceiling |
|---|---|---|
| Defaults (0.03, 150 s, 8 @ RIR 2) | 6.1% | no |
| Max **learnable** rate 0.08, 150 s | 16.3% | no |
| 0.08, 60 s rest, 12 @ RIR 0 | 25.0% | yes |
| 0.08, 45 s rest, 20 @ RIR 0 | 25.0% | yes |

Real data settles this: **100% of app-era exercise-sessions are <= 4 sets** (§3). Saturation sits
at the edge of the data. Not worth fixing.

### 2.4 CONFIRMED — Set-type multipliers never reach the user

Same set at 75 kg x 8 @ RIR 1, varying only the type:

| Type | Internal fatigue | Set 2 suggestion |
|---|---|---|
| backoff | 2.7% | **70.0 kg** |
| working | 3.9% | **70.0 kg** |
| dropset | 5.5% | **70.0 kg** |
| amrap | 5.8% | **70.0 kg** |
| failure | 5.8% | **70.0 kg** |

A 3.1-point spread collapses to one number after 2.5 kg rounding.

**Additional insight (from review):** the multipliers partly *double-count* RIR. Per-set fatigue is
`baseRate x typeMultiplier x effortScale(RIR) x repScale(reps)`. For an AMRAP to failure at 15
reps, the RIR-0 term (1.45x) and rep term (1.5x) already encode "brutal" — the type multiplier
(1.5x) says it a third time. Same set scores 0.065 as `working`, 0.098 as `amrap`, purely from the
label.

The exception is **dropset / rest-pause / myo / cluster**: these are several mini-sets logged as
one row, so reps and RIR structurally understate the work. There the multiplier carries information
nothing else has.

### 2.5 CONFIRMED — `missingRIRDefault = 1.0` treats unlabelled sets as near-failure

A completed set with no RIR is modelled as *harder* than one explicitly marked RIR 2
(effort scale 1.30 vs 1.15). Measured over 4 completed sets:

| History | Set 5 says |
|---|---|
| no RIR logged (today) | **70.0 kg** |
| same sets at RIR 2 | **72.5 kg** |

Worth one increment. Compounding: no RIR also means capability never updates (§2.1) and the
learning-loop audits are skipped — so those users get the conservative half of the model and none
of the corrective half.

### 2.6 CONFIRMED — The model has no upward gear within a session

`fatigueDiscount` is capped at 1.0 and purely subtractive; the freshness bonus only touches set 1
and is off by default. The **only** route to a higher mid-session suggestion is a completed set
raising `sessionCapabilityE1RM` — which §2.1 gates at RIR < 3.

Consequence: a lifter training with genuine reps in reserve can never make the app go up. Verified —
85 kg x 8 @ RIR 1 against a 75 suggestion lifts the baseline to 106 and prices set 2 at 80; the same
set at RIR 3-5 leaves it at 97.0, below the 100 starting point.

Largely resolved by fixing §2.1.

### 2.7 NOTED — Light loads see a coarser staircase

| | Set 1 | Set 2 | Step |
|---|---|---|---|
| 100 kg e1RM, 4x8 | 75.0 | 72.5 | -3.3% |
| 42.5 kg e1RM beginner, 3x10 | 30.0 | 27.5 | **-8.3%** |

Same modelled fatigue, 2.5x the felt drop, purely from rounding. At a 5 kg increment the whole
four-set curve becomes one step; at 1 kg it reads smoothly.

### 2.8 What holds up well

- **Rest sensitivity** is directionally right (60 s reaches -6.7% by set 3; 420 s holds -3.3%).
- **Warm-ups are genuinely free** — byte-identical prescriptions with and without them.
- **Fatigue toggle off** produces a clean flat control line.
- **Rep-count scaling** behaves: 4x20 fades -8.7%, 4x3 fades -2.9%.
- **Within-session adaptation works** whenever RIR < 3, both directions.
- **The headline case is defensible**: -6.7% across 4 sets of 8, consistent with the
  Willardson/SBS literature the engine header cites.
- **The learning loop works and grades the model as calibrated** — see §3.

---

## 3. Empirical grounding

Source: `RepsterTests/Fixtures/Local/real-history.repsterbackup` — real training data, 11,630
completed working sets, 579 workouts, back to 2021. Gitignored; exported 2026-08-13.

**Caveat that bit twice during this audit:** whole-history numbers are misleading because
pre-2026-03 rows are imported from another app with no RIR and no rest data. Always split by era.

| Measure | Whole history | App era (2026-03+) |
|---|---|---|
| RIR fill rate | 3.9% | **78.6%**, recently ~90% |
| Rest capture | 2.0% | **~50%**, median 180 s |
| Sets per exercise per workout | 85.5% <= 4 | **96.3% <= 3, 100% <= 4** |

Other findings:

- **67.3% of filled RIR values are RIR 0.** Users treat RIR as a went-to-failure flag, not a graded
  0-5 scale. Only **6.4%** are >= 3 — so §2.1 is a narrow but high-salience trust event, not a
  statistical accuracy problem.
- **The learning loop is alive and says the model is calibrated:** 34 qualifying global sessions,
  learned rate 0.032 vs 0.03 default, cumulative error **-0.0028** (~zero). 41/171 exercises carry
  local rates spanning 0.028-0.044.
- **But it is calibrated on a biased sample.** It only grades itself on sets with RIR, 67% of which
  are RIR 0. So "0.032 is right" really means "0.032 best predicts sets taken to failure", applied
  to RIR-2 work where fatigue behaves differently. The model likely shaves slightly too much for
  reps-in-reserve training. Same direction as everything else here: it leans conservative.
- **Audit statuses (556 rows):** used 34.7%, baselineFirstWorkingSet 30.6%, warmupNotTracked 21.9%,
  missingRIR 5.0%, suggestionUnavailable 4.3%, weightDeviationOver20Percent 3.1%.

### Generalisability

This is n=1. The **structural** findings (§2.1-2.7) are properties of the engine and hold for every
user. The **frequency** claims are one person's data and should be checked before they drive
priority. PostHog can answer this: `workout completed` already carries `rir_entered`,
`average_rir_bucket`, `set_count_bucket` and `exercise_count_bucket`
([POSTHOG_ANALYTICS_GUIDE.md:98](POSTHOG_ANALYTICS_GUIDE.md:98)) — workout-level rather than
set-level, but enough to decide.

### Constraint on any tuning

The learned rates are calibrated **around the current constants**. Changing `missingRIRDefault`,
the set-type multipliers or `maxFatigue` silently invalidates 34 sessions of global learning and 41
per-exercise rates. Pair any such change with a learning reset or an explicit re-convergence plan.

---

## 4. Decisions taken in review

| # | Item | Decision |
|---|---|---|
| 1 | **RIR >= 3 discarded** (§2.1) | **Fix.** Agreed this has to be improved. Approach undecided — see §5. |
| 2 | **Rep-range weight bounce** (§2.2) | **Parked.** Objection raised in review was correct: lower reps at higher weight is an easier set, and the demand does fall monotonically. Not a bug. Revisit only as presentation. |
| 3 | **No memory past set 3** (§2.3) | **Won't fix.** 100% of app-era sessions are <= 4 sets. Document as a deliberate limitation. |
| 4 | **`missingRIRDefault`** (§2.5) | **Fix**, built as a general solution, not tuned to one user's data. Design changed during review — see §5. |
| 5 | **Set-type multipliers** (§2.4) | **Ship 3 types** — normal, warmup, dropset. Keep the enum, multipliers and backup/restore fully intact so the others can return later; gate the picker UI only. |
| 6 | **`maxFatigue = 0.25`** | **Leave as-is.** A safety rail that never fires costs nothing. |
| 7 | **Biased calibration sample** (§3) | **No action.** Caveat to remember, not a task. |
| 8 | **Rest-assumption bias** | **Dropped.** Not a real finding — see §6. |

---

## 5. Open questions for the fixes that are going ahead

**§2.1 — how should RIR >= 3 sets be credited?** Options discussed, none chosen:
- let them raise capability at a damped weight (e.g. 30% influence)
- let them raise a ceiling without moving the point estimate
- keep discarding, but disclose it in the UI (moot if either of the above ships)

**§2.5 — what should an unlabelled set assume?** The review landed on a better shape than a
constant: **fall back to the target RIR that set was prescribed at.** If the app said "8 reps @
RIR 2" and the lifter ticked it complete without filling the chip, assuming they landed near RIR 2
beats any global number. Adapts to whatever the user programs, works on day one, nothing to tune.
Constant only as a last resort when there is no target either.
*Implementation note:* `SessionSetContext` does not currently carry the target RIR — one field to
thread through. Contained change.

**§4 item 5 — set-type gating.** The one risk to verify: sets already logged as `amrap` / `backoff`
/ etc. must still render correctly in history and workout detail once the type is no longer
offerable. Nothing is deleted, so this is a display concern, not a migration.

---

## 6. Corrections made during this audit

Recorded because they matter for judging confidence in the rest.

1. **Rep-range bounce called a correctness bug (§2.2).** Wrong. The demand falls monotonically;
   only the bar weight rises. Caught in review, verified afterwards.
2. **RIR fill rate quoted as 3.9%.** That is whole-history. App-era is 78.6%. This inverted the
   priority of §2.5 — it was briefly presented as governing 96% of sets when it governs ~21%.
3. **Rest capture quoted as 2.0%, framed as a stacking conservative bias.** Also whole-history;
   app-era is ~50% with a 180 s median. And the bias does not exist regardless: 150 s and 180 s
   produce *identical* prescriptions (the difference is sub-rounding). Finding withdrawn.
4. **Initial priority ranking was by mechanism, not frequency.** Real data reordered it.

The common thread in 2 and 3: this dataset contains years of imported history with no RIR and no
rest data. **Always split by era before quoting a rate from it.**
