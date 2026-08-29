# Smart Suggestions — what's still open

**Date:** 2026-08-27 · **Branch:** NewMain
**Scope:** only what is **not** decided and **not** built. Everything shipped in the epoch-2 release
is deliberately excluded — see [SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md](SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md)
for that. Written to be picked up cold, and to be bundled with another feature.

**Standing caveat.** Several numbers below come from `real-history.repsterbackup`, which is **one
lifter's training**. Repster has 200+ users. Anything marked *(n=1)* is a hypothesis about the
population, not a finding. Structural claims — what the code does — hold for everyone.

---

## 1. The plateau, and progression

### What happens today

A rep target is either a **range** or a **single number**. The single-number path prices:

```
weight = capacity x intensityFactor(targetReps + targetRIR)
```

which is the algebraic inverse of the formula that derived that capacity, so it hands back the
weight you last lifted. Progression logic exists **only** on the range path
(`firstSetProgressionAboveRecentPeak`, unreachable unless `lowerBound < upperBound`).

**How many sets take each path *(n=1)*:**

| | |
|---|---|
| Range path — progression possible | **0.37%** |
| Single-number path — no progression | **99.63%** |
| …of which, no target at all → profile default of 8 | 96% |

A range only ever arrives from a template or a manually-set min≠max. The profile default is a single
number, so ad-hoc sets — the normal way to log — can never progress.

### The correction that matters

**"Fixed targets can never progress" is wrong.** Capacity is the **peak of your last 3 workouts**,
computed from what you actually logged (reps + RIR). Do more reps and capacity rises and the next
prescription rises with it. The app follows you up; it just never goes first.

So the plateau is a **feedback loop**, not a dead end:

> card says 60 kg x 8 → you do exactly 8 → capacity unchanged → card says 60 kg x 8

The card's own number is what suppresses the performance that would move it. At RIR 0 this is
especially odd: if you are going to failure, the rep count is a *prediction of where failure lands*,
not an instruction.

### The hypothesis: double progression

Hold the weight, add reps across sessions, and when the top set reaches the top of the range, add one
increment and reset to the bottom.

This is the coaching norm past the beginner phase. Linear progression — adding weight at a fixed rep
count — works roughly 6–12 months and then stops, which is why the field moved to rep ranges. Sources
in the session that produced this doc: Legion, Hevy Coach, FitBudd, and the autoregulation
meta-analysis at PMC8762534.

**Worked example** — 1.25 kg increment, range 8–12 @ RIR 0, three sets, same performances run both
ways:

| Ses | Ladder weight | Top set | Peak e1RM | Ladder does | Today's engine would say |
|---|---|---|---|---|---|
| 1 | 60.00 | 8 | 76.00 | hold | 60.00 |
| 2 | 60.00 | 9 | 78.00 | hold | 60.00 |
| 3 | 60.00 | 11 | 82.00 | hold | **61.25** |
| 4 | 60.00 | 9 *(bad day)* | 78.00 | hold | **65.00** |
| 5 | 60.00 | **12** | 84.00 | **+1 increment** | 65.00 |
| 6 | 61.25 | 8 | 77.58 | hold | **66.25** |

### Open decisions

1. **Does the app ever ask for more than you have proven?** Everything else follows from this. If no,
   the current behaviour is correct and only the copy needs fixing. If yes, you need a mechanism.
2. **Does the ladder govern every working set, or only the top set?** It has to be every set — see
   §2.1. That is the largest structural consequence.
3. **What is the fatigue model for on ladder-governed sets?** If the weight is held, fatigue can no
   longer adjust it. Go quiet, or switch to predicting reps?
4. **What counts as "cleared"?** Reps alone, or reps at target RIR — see §3.2, this is the decision
   that determines whether the feature works for users who do not log RIR.
5. **Beginners.** Double progression is the intermediate answer. A beginner can add weight most
   sessions and a five-week ladder holds them back. Adaptive range width, or a separate path?

---

## 2. Live defects, not yet fixed

### 2.1 The ladder and the model fight over sets 2+

Modelled with the real engine formulas: with the ladder holding **set 1** at 60 kg, sets 2 and 3
priced at **62.50 and 63.75** — because the good first set raised session capability and the model
priced the rest off it. Weight climbing while the lifter tires.

So a ladder cannot govern set 1 alone. This is a design constraint, not a bug, but it is the reason
the feature is bigger than "change the default".

### 2.2 The baseline over-reacts to one good session · **undocumented until now**

`recentWorkoutPeakWindow = 3`, and the baseline is the **max** capacity across those workouts. Epley
converts high-rep sets into large e1RM values. Together:

- One 12-rep set at RIR 0 raises the baseline sharply
- It stays the baseline for **three workouts**
- On a bad day inside that window the app asks for the heaviest weight yet

In the worked example above, session 4 is a genuinely poor session and today's engine prescribes
**65 kg** — up from 60 — because session 3's peak is still in the window.

This is live now, independent of any progression work, and it is in none of the other docs.

### 2.3 First exposure to a new exercise is improved by nothing

The largest observed error was a first session (32.5 kg suggested against ~45 kg real capacity). The
floor cannot fire on set 1 — no completed sets — and the baseline needs history. Nothing shipped or
planned touches it. The idea on the table is a **probe mode** that steps up 15–25% per set while the
baseline rests on a single session.

Worth weighing against the progression work: activation is the stated growth bottleneck, and a new
user's first exercise is by definition a first exposure.

### 2.4 Light loads get a coarser staircase

Same modelled fatigue produces a −3.3% step at 100 kg and **−8.3%** at 42.5 kg, purely from rounding.
`Exercise.weightIncrement` already exists, so a smarter per-exercise default is small. Aimed squarely
at newer users.

### 2.5 The range path's three defects

Only matter if ranges become the default — at which point they go from invisible to universal:

- The rep target wanders inside a session (7, 7, 8, 5, 5, 5) with no visible logic
- `bestProgressedCandidate` takes the **`.min`** delta above baseline — the smallest increase that
  clears an epsilon, and it will lower bar weight to buy it
- Progression is gated on `isFirstSet`, so sets 2+ get none

A ladder would **supersede** these rather than inherit them: it sets a single rep target, so pricing
takes the fixed path and the candidate search is bypassed.

---

## 3. What we would need to know

The progression design hinges on facts about the user base that nobody has.

### 3.1 Unmeasured, and not answerable today

| Question | Why it decides something | Status |
|---|---|---|
| Do users hold weight across sets, or let it drop? | The engine prescribes a **descending** pattern. If most users hold, it is arguing with them | **No event exists.** *(n=1: 41% hold, 31% ascend, 12% descend)* |
| What increments do users train on? | One increment is ~2% on a 1.25 kg bar and **>8%** on a 5 kg stack. A fixed 8–12 range gives one user five gentle rungs and the other a wall | Not measured |
| Beginner / intermediate mix | Decides whether linear or double progression is the right default | Not measured |

### 3.2 Partly answerable now

- **RIR fill rate** — `rir_entered`, `average_rir_bucket` already ship. *(n=1: 78.6% app-era, 21.4%
  blank, and 100% of imported history has none.)* This is the one that changes the design: if
  "cleared" requires a target RIR, every non-logging user is frozen out. **Judging clearing on reps
  alone removes the dependency** and still works for RIR loggers.
- **Set counts** — `set_count_bucket` ships. *(n=1: 3% one set, 18% two, 47% three.)* A one-set user
  and a five-set user progress on the same top-set rule, which is probably correct but untested.
- **Suggestion adherence** — built in the epoch-2 release, not yet released. Whether users follow,
  go heavier, or go lighter. **Wants shipping a release ahead of any engine change**, or there is no
  before-picture.

---

## 4. The default rep target

Today: one global number, default **8**, clamped 1–30. `Exercise` carries **no** rep-target fields, so
per-exercise targets are new schema.

Three shapes, none chosen:

1. **Keep a single number.** Progression stays impossible without a ladder.
2. **Make the default a range** (8 → 8–12). Double progression works for everyone with no
   configuration. Moves ~99% of sets onto the range path, so §2.5 must be fixed first — unless a
   ladder supersedes it.
3. **Per-exercise, inferred from history.** 8 reps suits squats and curls differently. The app already
   infers something similar for the rep input field. Composes with (2): the range can be seeded rather
   than configured across a whole library.

**Removing the default entirely does not work.** With no resolvable target the card renders
`missingTarget` and Smart Suggestions goes dark — worst possible friction for a new user.

---

## 5. Loose ends

Small, individually cheap, none blocking.

- **The "5+" chip is undisclosed.** It stores exactly 5 whether the lifter had 5 reps left or 13. The
  decision was accept it, cap the credit, *and say so*. The first two shipped; nothing anywhere
  explains it. Fix is a line of copy, or more chips.
- **v1 learning data erodes.** Observations are pruned to 30 sessions per exercise and the pruning is
  **epoch-blind**, so pre-1.5 rows age out as new sessions land. Audits are not pruned, so the
  coaching record survives — but a future rate seeder's corpus is on a clock. Fix: prune within epoch.
- **The rate seeder.** On upgrade, derive each exercise's starting fatigue rate from history instead
  of relearning from the default. Deferred: *(n=1)* only 5.4% of exercise-sessions have ≥2 sets
  carrying RIR, so the usable corpus is thin, and it needs a fitting method the current
  sign-following learner does not have.
- **Cross-exercise fatigue.** Decided out of the epoch-2 release, but the accumulator was not
  structurally kept open, so adding it later is still a change to the same path.
- **Audit table growth is unmeasured.** It is the coaching substrate and has no routine pruning.
  Worth sizing before building on it.
- **Upgrade during an in-progress workout.** Nobody has checked what the startup rate reset does to a
  session that is partly logged.

---

## 6. If this gets bundled

The cheapest thing that moves the plateau, and it commits you to none of the above:

**Change what the card asks for.** It says "8 reps", so the lifter does 8, so capacity never moves.
Showing a bounded invitation instead — "8–12 reps", or last session's reps to beat — breaks the loop
using machinery that already exists, because the engine already raises the weight when performance
improves. Days of work, reversible, and it generates the data that would settle §1.

An unbounded "8+" is the wrong version: Epley degrades past ~10 reps, so it invites sets that inflate
the capacity estimate.
