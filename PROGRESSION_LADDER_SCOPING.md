# Progression & the rep ladder — source of truth

**Date:** 2026-09-21 · **Branch:** NewMain · **Status:** scoped, nothing built
**Feature area:** Smart Suggestions
**This is the one-stop doc.** It consolidates the progression/ladder material that was spread across
four documents, plus findings from the 2026-09-21 code review that were in none of them. The older
docs stay for their history; §11 says what each still owns.

**Standing caveat.** Numbers marked *(n=1)* come from `real-history.repsterbackup` — one lifter.
Repster has 200+ users. Structural claims (what the code does) hold for everyone; behavioural ones
marked *(n=1)* are hypotheses about the population.

---

## 0. Read this first

- **The plateau is a feedback loop, not a missing feature.** The card asks for 8 reps, the lifter does
  8, capacity doesn't move, the card asks for 8 again. Capacity *does* follow performance upward — the
  app just never goes first. §1.
- **A rep range here is not a ladder.** 8–12 is a set of equal-difficulty (weight × reps) pairs for
  today, and the winner is picked by plate-grid rounding. Nothing remembers where you were last time.
  §2.
- **There is a live defect worth fixing regardless of any of this.** The baseline is the *max* of your
  last 3 workouts, so one high-rep set makes the app ask for your heaviest weight ever on a bad day.
  §9.1.
- **The ladder is cheaper than the existing estimate says** — position is derivable from history, not
  persisted. §8.
- **Cheapest thing that moves progression at all: ~15 lines.** §4, option C2.
- **The decision everything hangs on:** should the app ever ask for more than you have proven? §6, D1.

---

## 1. What happens today

A rep target is either a **range** or a **single number**. The single-number path prices:

```
weight = capacity × intensityFactor(targetReps + targetRIR)
```

which is the algebraic inverse of the formula that derived that capacity — so it hands back the weight
you last lifted. Progression logic exists **only** on the range path
(`firstSetProgressionAboveRecentPeak`, unreachable unless `lowerBound < upperBound`).

**How many sets take each path *(n=1)*:**

| Path | Share |
|---|---|
| Range — progression possible | **0.37%** |
| Single number — no progression term | **99.63%** |
| …of which no target at all, so the profile default of 8 | 96% |

A range only ever arrives from a template or a manually-set min≠max. The profile default is a single
number, so ad-hoc sets — the normal way to log — never reach the progression path.

### The correction that matters

**"Fixed targets can never progress" is wrong**, and two older docs say it. Capacity is the **peak of
your last 3 workouts**, computed from what you actually logged (reps *and* RIR). Do more reps than
asked and capacity rises, and the next prescription rises with it.

So the app follows you up. It just never leads. The loop:

> card says 60 kg × 8 → you do exactly 8 → capacity unchanged → card says 60 kg × 8

The card's own number suppresses the performance that would move it. At RIR 0 this is especially odd:
if you are going to failure, the rep count is a *prediction of where failure lands*, not an
instruction.

---

## 2. What a range is here — and what it is not

**Not a ladder.** The intuitive reading of "8–12" is double progression: failure at 9, so aim for 10,
hold the weight, add load once you clear 12. The engine does nothing of the kind.

From `repRangeCandidates` ([:983](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:983))
and `bestClosestMatchCandidate` ([:1062](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:1062)):
for 8–12 at RIR 2 the engine builds five candidates — 8, 9, 10, 11, 12 — and prices each at the weight
that produces *the same* effective e1RM. All five are equally hard by the model. They differ only in
how much plate-grid rounding error they carry, and the smallest error wins.

Two consequences:

- **The rep count is chosen by grid rounding, not training logic.** This is the real reason golden
  master F1 bounces 7, 8, 6, 7. Across a wide range it is pure noise — at 1–30, consecutive sets can
  read 4 reps then 23.
- **Nothing remembers your position.** There is no stored rep position, so "failure at 9 → 10 next
  time" cannot happen. The only progression rule in the range path is `bestProgressedCandidate`
  ([:1076](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:1076)), it fires on
  **set 1 only**, and it picks the candidate beating the recent peak by the *smallest* margin
  (~+0.5%, and it will drop bar weight to buy it).

The range buys a cleaner landing on the weight grid and a set-1 nudge. It does not buy a ladder.

---

## 3. What the ladder would do

Hold the weight, add reps across sessions; when the top set reaches the top of the range, add one
increment and reset to the bottom. This is the coaching norm past the beginner phase — linear
progression at a fixed rep count works roughly 6–12 months and then stops, which is why the field
moved to rep ranges. (Sources: Legion, Hevy Coach, FitBudd, autoregulation meta-analysis PMC8762534.)

**Worked example** — 1.25 kg increment, 8–12 @ RIR 0, three sets, identical performances run both ways:

| Ses | Ladder weight | Top set | Peak e1RM | Ladder does | Today's engine says |
|---|---|---|---|---|---|
| 1 | 60.00 | 8 | 76.00 | hold | 60.00 |
| 2 | 60.00 | 9 | 78.00 | hold | 60.00 |
| 3 | 60.00 | 11 | 82.00 | hold | **61.25** |
| 4 | 60.00 | 9 *(bad day)* | 78.00 | hold | **65.00** |
| 5 | 60.00 | **12** | 84.00 | **+1 increment** | 65.00 |
| 6 | 61.25 | 8 | 77.58 | hold | **66.25** |

**Read session 4 twice.** It is a genuinely poor session and today's engine prescribes 65 kg — up from
60 — because session 3's peak is still inside the 3-workout window. And by session 6 today's engine is
asking 66.25 where the ladder asks 61.25.

So the honest framing is **not** "the ladder adds progression where there is none." It is: **today's
progression is jumpy and over-reactive; the ladder is slower, steadier and predictable.** That is a
product argument, not a bug fix — which is why D1 in §6 is the question everything else hangs on.

---

## 4. The options, cheapest first

### C1 — Turn on the freshness bonus · ~1 line + tests

`readinessState` ([:1296](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:1296))
already multiplies first-set capability by `1 + freshnessPercent` (default 3%). It is wired, tested,
in the cache key, and already drives the right copy — `hasProgressionBump`
([WeightSuggestionData.swift:888](Repster/Features/Workout/Models/WeightSuggestionData.swift:888))
includes `freshnessApplied`, so the card already says *"Nudging up from your last workout's peak."*

It is `?? false` ([LoadPrescriptionService.swift:92](Repster/Core/Services/LoadPrescriptionService.swift:92))
and **has no Settings UI anywhere** — the only hit in `Repster/Features` is the admin diagnostics
label. A finished progression feature with no switch.

- **Gets you:** ~3%/session on the first set, compounding while you succeed, on both paths.
- **Costs:** a default flip, golden-master regeneration, a few tests. Half a day.
- **Weakness:** rounds away on light lifts. 3% of 60 kg is 1.8 → clears a 2.5 kg step. 3% of 40 kg is
  1.2 → rounds straight back to 40. Invisible for anyone training lighter.
- **Weakness:** it nudges because you are *fresh*, not because you *earned it* — it escalates whether
  or not you succeeded last session.
- **Do not ship it without a Settings toggle.** A silent compounding multiplier with no off switch
  will generate "why does it keep asking for more" reports.

### C2 — Extend the existing progression policy to the fixed path · ~15 lines

The fixed path ([:876](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:876)) is
the mirror. Everything needed is already in scope: `input.baseE1RM`, `isFirstSet`, `input.baseSource`,
`settings.weightIncrement`.

> If this is set 1 off recent performance and the prescribed weight does not imply an e1RM above the
> recent peak, add one increment and flag `.firstSetProgressionAboveRecentPeak`.

Same gate and same policy case the range path already uses. No new enum case, no new input, no new
copy, no service lookup.

- **Gets you:** guaranteed one-increment movement, no rounding-away problem, conditional on having
  matched your peak.
- **Costs:** ~15 lines in one file, plus tests and a golden-master diff (F3–F7 and others all use set 1
  off `.recentPerformance`, so expect 20–40 changed fixture lines).
- **Weakness:** still escalates against the 3-workout peak, so §9.1 still bites.

### L1 — Ladder on a fixed target only · ~400–570 lines, 5–7 files

Last session's top set met the target at or under target RIR → prescribe +1 increment. No ranges, no
stored position. This is what [SUGGESTION_PROGRESSION_DESIGN.md](SUGGESTION_PROGRESSION_DESIGN.md)
recommends starting with.

### L2 — Derived ladder over ranges · ~750–1050 lines, 6–8 files

The real 8→12→+weight→8 behaviour, position read from last session's actual top set. Needs D2–D6.
**Supersedes** the range path's three defects (§9.4) rather than inheriting them, because it sets a
single rep target and pricing takes the fixed path.

### L3 — True ladder with persisted position · ~1200–1800 lines, 12–18 files

Holds its plan when the lifter ignores it. Needs stored position, migration, backup round-trip,
`resetAllAppData` semantics, and a decision on per-exercise vs per-template scoping. This is the tier
[DEFAULT_REP_RANGE_TECHNICAL_SCOPE.md](DEFAULT_REP_RANGE_TECHNICAL_SCOPE.md) §15 estimates at 2–3 weeks.

### C3 — Change what the card asks for · days, commits you to nothing

The loop in §1 exists because the card names one number. Show a bounded invitation instead — "8–12
reps", or last session's reps to beat — and the existing engine raises the weight on its own when
performance improves. Reversible, and it generates the data that would settle D1.

**Tension to resolve:** [DEFAULT_REP_RANGE_SCOPING.md](DEFAULT_REP_RANGE_SCOPING.md) decision 5 decided
**not** to surface the default on set rows ("we don't do that today and we shouldn't start"). That
decision removes precisely this mechanism. Both positions are defensible; they cannot both hold.

An unbounded "8+" is the wrong version: Epley degrades past ~10 reps, so it invites sets that inflate
the capacity estimate.

---

## 5. What the user would see

Today the strip reads **"Set 1 · 60 kg for 8 reps"** under *"Based on your recent performance for this
rep target"* — and says 60 kg indefinitely. With a ladder it becomes an instruction that cites you:

| Session | Card | Line underneath |
|---|---|---|
| 1 | Set 1 · 60 kg for 8 reps | Based on your recent performance |
| 2 | Set 1 · **60 kg for 9 reps** | You hit 8 at RIR 0 last time — one more rep, same weight |
| 5 | Set 1 · 60 kg for 12 reps | Top of your range — clear this and the weight goes up |
| 6 | Set 1 · **62.5 kg for 8 reps** | You cleared 12 — adding 2.5 kg, back to 8 |

The "Why this weight" sheet gets much more legible: step 1 becomes "Last session: 60 kg × 8 @ RIR 0 —
cleared", step 2 "8 → 9 reps", with no e1RM needed to follow it. The **PUSH IT** row is unchanged.

Rough edges a user would actually hit:

- **New exercise** → no position, falls back to today's predictor. First session looks unchanged.
- **You ignore it** (card says 60 × 9, you do 65 × 5). A derived ladder follows what you did, so one
  heavy day resets your position. That is D5, and the likeliest source of complaints.
- **Stranded.** Miss the bottom twice and without a deload rule you are told to do something you
  cannot. D4 is not optional in practice.
- **Blank RIR** → cannot tell a grind from an easy 8. See §7.

---

## 6. Decisions

| # | Decision | Notes |
|---|---|---|
| **D1** | **Should the app ever ask for more than you have proven?** | Everything follows. If no, today's behaviour is correct and only copy needs fixing. If yes, you need a mechanism. §3 reframes this: it is a choice between jumpy-and-aggressive and slow-and-steady, not between progression and none. |
| D2 | Does the ladder govern every working set, or only the top set? | **It has to be every set** — see §9.2. Largest structural consequence, and the reason this is bigger than "change the default". |
| D3 | What is the fatigue model for on ladder-governed sets? | If weight is held, fatigue can no longer adjust it. Go quiet, or switch to predicting reps? |
| D4 | Failure / deload rule | Miss the bottom twice → drop the weight? Without it, one bad week strands the lifter. |
| D5 | What if the lifter does not follow it? | Follow actual performance (forgiving, collapses toward "last session + 1 rep") or hold the plan (needs L3's persisted state)? **This single decision is the L2/L3 boundary.** |
| D6 | Reps alone, or reps at target RIR, counts as "cleared"? | §7 — determines whether the feature works for users who do not log RIR. Recommend **reps alone**. |
| D7 | Beginners | Double progression is the intermediate answer; a beginner can add weight most sessions and a five-week ladder holds them back. Adaptive range width, or a separate path? |
| D8 | Opt-in toggle, or default-on? | A toggle costs ~+80–120 lines and 5 extra files — roughly the ladder logic again — because it pulls in `HealthProfile`, the snapshot mirror, `SettingsService`, the view, and **five** test-stub conformers. Default-on is the big lever on blast radius. |
| D9 | Ship C1/C2 first, or go straight to a ladder? | C2 is ~15 lines and needs none of D2–D7. |

---

## 7. What is measurable, and what is not

### Answerable now

- **RIR fill rate** — `rir_entered` and `average_rir_bucket` already ship. *(n=1: 78.6% filled,
  21.4% blank, and 100% of imported history has none.)* **This is the one that changes the design:** if
  "cleared" requires target RIR, every non-logging user is frozen out. Judging on **reps alone** removes
  the dependency and still works for RIR loggers. → D6.
- **Set counts** — `set_count_bucket` ships. *(n=1: 3% one set, 18% two, 47% three.)* A one-set and a
  five-set user progress on the same top-set rule; probably right, untested.
- **Suggestion adherence** — built in the epoch-2 release, not yet released. Whether users follow, go
  heavier, or go lighter. **Wants shipping a release ahead of any engine change**, or there is no
  before-picture.

### Not answerable today

| Question | Why it decides something |
|---|---|
| Do users hold weight across sets, or let it drop? | The engine prescribes a **descending** pattern. If most users hold, it is arguing with them. No event exists. *(n=1: 41% hold, 31% ascend, 12% descend)* |
| What increments do users train on? | One increment is ~2% on a 1.25 kg bar and **>8%** on a 5 kg stack. A fixed 8–12 gives one user five gentle rungs and the other a wall. |
| Beginner / intermediate mix | Decides whether linear or double progression is the right default. → D7 |

---

## 8. Sizing and blast radius

### Calibration

The nearest shipped analogue is `45a45de` ("Credit reps in reserve as a floor") — new override in
`evaluate`, new selection-policy case, new explanation branch, golden master regenerated:

```
LoadPrescriptionServiceProtocol.swift       +157
SmartSuggestionBehaviorScenarioTests.swift  +358
WeightSuggestionData.swift                   +18
SuggestionEngineGoldenMaster.txt              30 changed
ActiveWorkoutViewModelSuggestionRefreshTests  +3
                        563 insertions, 6 files
```

Production was ~175 lines; **tests were 2×**. That ratio is the shape of any change in this engine.

### Position is derivable, not persisted

[SUGGESTION_ENGINE_PROGRAM.md](SUGGESTION_ENGINE_PROGRAM.md) claims O4 "is the only item in the whole
program needing genuinely new *persisted* state (ladder position)". **That is true only of L3.** For
L1 and L2 the engine already receives everything needed:

- `SuggestionEngineInput.baseSourceTopSet`
  ([:368](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:368)) is a
  `HistoricalSetSnapshot` carrying **weight, reps, RIR and date** — and its own comment says it is
  currently unused in the UI.
- `peakAcrossRecentWorkouts(_:limit:formula:)`
  ([LoadPrescriptionService.swift:319](Repster/Core/Services/LoadPrescriptionService.swift:319)) already
  computes "top set of the last N workouts". It is called with `limit: 3`; `limit: 1` gives last session.

That claim is load-bearing for prioritisation, and it is what makes the ladder look expensive.

### Why the call sites don't break

`BaseE1RMEstimate` and `SuggestionEngineInput` both have explicit inits with defaults from the third
parameter on, and `SuggestionSettingsSnapshot` already carries `var capacityGuardsEnabled: Bool = true`
as precedent. New fields are free across all 27 `SuggestionEngineInput` construction sites — 26 of
which are tests. `SuggestionSelectionPolicy` has 30 references but only one exhaustive switch (its own
`label`).

### The golden master

Both `evaluate` helpers ([:89](RepsterTests/SmartSuggestionBehaviorScenarioTests.swift:89),
[:581](RepsterTests/SmartSuggestionBehaviorScenarioTests.swift:581)) build inputs **without**
`baseSourceTopSet`, so it is nil in all 151 fixture lines. A ladder gated on "we have last session's
top set" therefore **fires in zero existing scenarios** and the fixture stays byte-identical unless
scenarios are added deliberately. C2 is the opposite — it fires on set 1 off `.recentPerformance`,
which most scenarios use.

### The fatigue learner survives

`normalizedError` compares predicted vs actual **e1RM**
([FatigueLearningService.swift:214](Repster/Core/Services/FatigueLearningService.swift:214)), not
prescribed weight. Prescribed weight is only a ±20% gate that discards wild deviations. A ladder shifts
what that gate measures against but does not poison the learned rates.

### Collision

`evaluate` is the insertion point the remaining floor and drop-set work also wants — the collision map
in [SUGGESTION_ENGINE_PROGRAM.md](SUGGESTION_ENGINE_PROGRAM.md) §4 names it. Also unresolved: **floor
vs ladder precedence.** Both override the model's weight and can disagree — the ladder says "+1
increment from last session", the floor says "above a completed set with reps to spare".

---

## 9. Adjacent defects that interact

### 9.1 The baseline over-reacts to one good session · live now

`recentWorkoutPeakWindow = 3` ([:34](Repster/Core/Services/LoadPrescriptionService.swift:34)) and the
baseline is the **max** across those workouts. Epley turns high-rep sets into large e1RM values, so:
one 12-rep set at RIR 0 raises the baseline sharply, it stays the baseline for three workouts, and on a
bad day inside that window the app asks for the heaviest weight yet. Session 4 of §3 is exactly this.

**This is live today, independent of any progression work.** Both C1 and C2 escalate against this same
stale peak, so neither fixes it. A ladder reading last session's actual top set self-corrects faster.

### 9.2 A ladder cannot govern set 1 alone

Modelled with the real formulas: with the ladder holding set 1 at 60 kg, sets 2 and 3 priced at
**62.50 and 63.75** — the good first set raised session capability and the model priced the rest off
it. Weight climbing while the lifter tires. → D2.

### 9.3 First exposure to a new exercise is improved by nothing

The largest observed error was a first session (32.5 kg suggested against ~45 kg real capacity). The
floor cannot fire on set 1 and the baseline needs history. Nothing shipped or planned touches it; the
idea on the table is a **probe mode** stepping 15–25% per set. Worth weighing against the ladder:
activation is the stated growth bottleneck, and a new user's first exercise is by definition a first
exposure.

### 9.4 The range path's three defects

Only matter if ranges become the default — at which point they go from invisible to universal. The rep
target wanders inside a session; `bestProgressedCandidate` takes the `.min` delta and will lower bar
weight to buy it; progression is gated on `isFirstSet`. **L2 supersedes all three.**

### 9.5 Light loads get a coarser staircase

Same modelled fatigue gives a −3.3% step at 100 kg and **−8.3%** at 42.5 kg, purely from rounding.
`Exercise.weightIncrement` already exists, so a smarter per-exercise default is small. Same root cause
as C1's rounding weakness.

### 9.6 The push option regresses under a default range

With RIR 2 and a range of 8–12, `pushOption`
([:954](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:954)) takes the top of
the range at RIR 0 and suppresses itself when that would be lighter than prescribed. At 100 kg
effective e1RM on a 2.5 kg grid: chosen 8 → **no push at all**; chosen 10 → same weight (handled
gracefully, reads "× 12 reps · same bar, all out"); chosen 11–12 → heavier as intended. Today every
fixed-target set has a heavier push. A ladder makes this moot by fixing the rep target.

---

## 10. Tests

Whatever ships:

- `SmartSuggestionBehaviorScenarioTests` — cleared / not-cleared / no-history / blank-RIR / lifter
  deviated / at-top-of-range. Expect this file to carry most of the diff.
- `SuggestionEngineGoldenMasterTests` and `RepsterTests/Fixtures/SuggestionEngineGoldenMaster.txt` —
  regenerate deliberately and diff row by row. Unchanged for L1/L2 unless scenarios are added; 20–40
  lines for C2.
- `ActiveWorkoutViewModelSuggestionRefreshTests` — one end-to-end refresh.
- `WorkoutJourneyTests` — has 6 `estimateBaseE1RM` call sites; one is worth extending for the real-store
  path.
- Run the suite **once**, into a log.

---

## 11. Where the older docs stand

All four keep their history. What each still uniquely owns:

| Doc | Still the source for |
|---|---|
[SUGGESTION_OPEN_QUESTIONS.md](SUGGESTION_OPEN_QUESTIONS.md) | §4 default-rep-target shapes; §5 loose ends (the "5+" chip disclosure, v1 learning-data erosion, the rate seeder, cross-exercise fatigue, audit-table growth, upgrade mid-workout) |
[SUGGESTION_PROGRESSION_DESIGN.md](SUGGESTION_PROGRESSION_DESIGN.md) | P1's fix history; O1–O3 and why they were dropped |
[DEFAULT_REP_RANGE_TECHNICAL_SCOPE.md](DEFAULT_REP_RANGE_TECHNICAL_SCOPE.md) | Strategy 2 (stable adaptive range); §11 materializing guidance onto completed sets; §12 import/export compatibility |
[DEFAULT_REP_RANGE_SCOPING.md](DEFAULT_REP_RANGE_SCOPING.md) | The 8 → 8–12 default change as its own shippable piece, with decisions 1–10 |
[SMART_SUGGESTIONS_BEHAVIOR_AUDIT.md](SMART_SUGGESTIONS_BEHAVIOR_AUDIT.md) | §2.2 within-session bounce as a presentation question; §3 the learned-state constraint |

**Two corrections this doc makes to them:**

1. "A fixed rep target can never progress" (PROGRESSION P2) is **wrong** — see §1. That doc already
   carries a banner saying so; its P2 body text still reads the old way, and two other docs repeat it.
2. "O4 is the only item needing genuinely new persisted state" (PROGRAM §C) is **true only of L3** —
   see §8.
