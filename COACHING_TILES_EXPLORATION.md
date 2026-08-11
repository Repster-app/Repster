# Coaching tiles — exploration

**Status: parked 2026-08-11.** Nothing here is built or agreed. Split out of the insights
chart work so that could stay focused; this is the record of what was explored and what
still has to be decided.

Mockups: `html prototype/prototype-coaching-tiles.html`
Related: `TRAINING_INSIGHTS_V2_DESIGN.md` (§2 locked decisions, §5 findings catalog,
§7.1 chart spec, §12 out of scope)

---

## The framing question

Most of what already ships is coaching-adjacent. `deloadReadiness`, `muscleBalance` and
`restSweetSpot` all imply an action without naming one. So the line that would define a
coaching tile is **whether it names the next step**.

That makes this a grouping and copy-register decision first, and an engine decision second.
A large part of the category could ship as a re-frame of existing findings plus two or three
new rules.

Note that §"The organising idea" already assigns findings the *prescribing* role — only the
status layer is restricted to describing. **A coaching category is not a departure from the
locked design.** The collisions are narrower than that, and listed below.

---

## Two independent gates

**Coverage.** The two model-transparency tiles read `FatigueObservation`, which only exists
where Smart Suggestions produced a prediction. Blank for anyone not using the wand — the
same caveat §5.1 records for `deloadReadiness`. Neither can be a Tier 1 card.

**Stance.** Four coaching tiles are marked "stance needed" below: the *finding* is safe, but
the *recommendation* is an opinion the app has never yet asserted. Stating that chest gets
its 16 sets in one day is a fact about the user's data. Saying spread is better is a claim
about training. Nothing in Insights currently makes claims of the second kind, and that is
the decision underneath the whole category.

---

## The tiles

| Tile | Domain | Data | Cost |
|---|---|---|---|
| Model check | suggested vs actual | `FatigueObservation.prescribedWeight` / `actualWeight` / `normalizedError` | **mostly built** — see below |
| Fatigue cost | per-exercise fatigue rank | `appliedFatigueRate(for:)` → `AppliedFatigueRateInfo` | free, one trap |
| Today (A/B) | what to train | workout dates + `primaryMuscle` | free |
| Stalled | load progression | per-session weight + `e1RM` on `WorkoutSet` | free |
| Session order | session structure | `orderInWorkout` + within-session `e1RM` decay | free, **ungated** |
| Frequency | scheduling | workout dates + `primaryMuscle` | free, stance needed |
| On pace | goals | `StatsService.computeE1RMTrendSlope` | free, hedging needed |
| Rep mix | stimulus variety | `reps` on every set | free, stance needed |
| Balance | push : pull | needs a movement-pattern mapping | stance + taxonomy |

### Worth knowing per tile

**Model check** is closer to built than it looks. `FatigueLearningService.diagnosticsExercises()`
and `recentSessionSummaries()` already roll this up, and `FatigueLearningAdminView` renders a
version today. The work is user-facing language, not computation. Framing risk: a table saying
the model was wrong invites "so why trust it" — it has to read as *the model learns from this*,
which it does.

**Fatigue cost** has one trap. `appliedFatigueRateInfo(for:profile:)` returns a *default* rate
when nothing has been learned. Ranking defaults would show the user the model's priors dressed
up as a fact about their training. Gate on `source` and `hasAuditHistory`; show learned rows only.

**Session order** is the one to build first if this category proceeds. `orderInWorkout` gives
position and within-session `e1RM` decay gives cost — and computing decay directly from
`WorkoutSet` rather than from `appliedFatigueRate` **sidesteps the Smart Suggestions gate
entirely**, so unlike the two above it works for every user. "You squat fourth and it costs you
most" is concrete, actionable, and needs no new model.

**Stalled** is the most coach-like thing the data supports, with a catch: a flat run is only a
plateau if reps are rising underneath it. An intentional maintenance block looks identical, so
reps-rising has to be a firing condition rather than a nicety.

**On pace** is nearly free but the riskiest to get wrong. A dashed line is a promise, and linear
extrapolation of strength is wrong over any real horizon. Short window and a visible hedge, or
it becomes the most disappointing card in the app.

---

## Decisions to settle before building

1. **Stance.** Does the app assert training opinions ("spread is better", "vary your rep
   ranges", "keep push and pull even"), or only state the user's own patterns? Four tiles
   depend on this and it applies to the category as a whole.
2. **Name.** §2 locks "Suggestions" — Smart Suggestions owns it, including a Settings screen
   and the workout-screen wand. A second feature prescribing weights would read as the same
   thing said twice. A coaching category needs a distinct name and a clear boundary against it.
3. **Deep links.** §12 defers actions from findings into editors. "Load this session" and
   "Start a legs session" are out of scope as currently written, and a coach tile that can't
   act is half a feature. Revisit that deferral or design around it.
4. **Contract.** §6 curation keeps findings occasional and allowed to say nothing. A coach tile
   users expect *daily* is a different promise. Decide whether coaching lives in the gated feed
   or as an always-on surface like the status card.
