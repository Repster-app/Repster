# Insights feature — design document

Status: design draft (2026-06-10). Not yet scheduled; candidate for post-June roadmap.

## Summary

A findings feed, not a stats wall. An `Insights` page surfaces a small number of
high-confidence, personally-derived training findings ("your reported RIR 2 is
usually RIR 4 on bench"), each backed by a small chart and, where possible, a
one-tap action. Entry via a new home-screen section card with an unread badge.

Guiding principle: **one true insight beats twelve noisy ones.** Every insight
must pass a statistical gate before it is allowed to appear; an empty feed is a
valid output.

## Entry point

- New `HomeSectionId.insights` case in `Repster/Features/Home/Models/HomeSectionConfig.swift`.
  The existing `sanitized()` migration auto-inserts it for current users; the
  customize sheet gives hide/reorder for free.
- Teaser card: icon + "Insights" + badge ("2 new") + headline of the top-ranked
  finding + chevron. Tap navigates to the Insights page.
- Badge = count of `InsightRecord` rows in state `new` not yet seen. Mark seen
  when the Insights page appears.

## Data feasibility (verified against the codebase)

Computable today with no new logging:

| Signal | Source |
|---|---|
| Per-set weight/reps/RIR/e1RM, incl. left/right | `WorkoutSet` |
| Set order in workout and exercise | `WorkoutSet.orderInWorkout` / `.orderInExercise` |
| PR status per set | `WorkoutSet.cachedPRStatusRaw` |
| Targets vs. actuals | `targetWeight`, `targetRepMin/Max`, `targetRIR` |
| e1RM trend slope per exercise | `ExerciseStats.estimated1RMTrendSlope` |
| Prediction error per set (suggestion users) | `FatigueObservation.normalizedError` |
| Learned fatigue/recovery per exercise | `Exercise.fatigueRate`, `.recoveryConstant` |
| Muscle mapping | `Exercise.primaryMuscle`, `.secondaryMuscles` |
| Bodyweight | `BodyweightEntry` |

Known caveats:

1. **`WorkoutSet.startedAt` is never populated** (only `completedAt` is set, in
   `ActiveWorkoutViewModel`). Set duration is unmeasurable; rest must be
   approximated as the gap between consecutive `completedAt` values.
2. **`restDurationSeconds` is a biased sample** — only captured when the rest
   timer runs to zero (`captureRestDurationOnLastCompletedSet`), so short rests
   are systematically missing.
3. **`FatigueObservation` is pruned to the last 30 sessions per exercise**
   (`FatigueLearningService.maxRetainedSessions`). Fine for recent-state
   metrics; rules out lifetime calibration history. Suggestion-dependent
   insights only exist for users with smart suggestions enabled.

Pre-work (small, ship ASAP so data accrues for live users):

- [ ] Populate `WorkoutSet.startedAt` during active workouts.
- [ ] Capture rest duration on early timer dismissal, not only on completion
      (or formalize the completedAt-gap derivation).

## Insight catalog

Tiered by data appetite; the tier is the unlock order a new user experiences.
Launch set marked with ★.

### Tier 1 — first 1–2 weeks of data

| Insight | Gate | Primary action |
|---|---|---|
| ★ Muscle balance | A muscle group gets <⅓ the hard sets (RIR ≤ 3) of comparable groups over 2 weeks | Suggest an exercise |
| ★ Target adherence | Rep-range hit rate notably high/low over ≥10 sets | Adjust template targets |
| Consistency pattern | Session frequency deviates from the user's own baseline | Schedule a planned workout |

### Tier 2 — after 3–6 weeks

| Insight | Gate | Primary action |
|---|---|---|
| ★ Rest sweet spot | ≥15 rests with spread; effect ≥1 rep | One-tap rest-timer update |
| ★ RIR calibration | ≥10 observed sets with consistent bias | Offer to adjust suggestion aggressiveness |
| ★ PR rhythm / drought | >~1.5× the user's typical PR interval | Suggest rep-range change or deload |
| Progress velocity | e1RM slope stands out (up or down) | Share card |
| Relative strength milestone | e1RM/bodyweight crosses round threshold | Share card |
| Strength retention on a cut | Bodyweight down ≥3 weeks, e1RM held | Share card |
| L/R asymmetry | Gap ≥8% across ≥8 unilateral sessions, or growing | Extra sets on weaker side |

### Tier 3 — after 2–3 months

| Insight | Gate | Primary action |
|---|---|---|
| Order interference | Exercise in ≥2 slots, ≥5 sessions each, effect ≥4% | Reorder template |
| Recovery half-life | Varied spacing shows clear per-muscle optimum | Adjust program spacing |
| Session decay point | Output vs. prediction drops past consistent minute mark | Front-load priority lifts |
| Fatigue resistance profile | `fatigueLearningSessionCount` sufficient | Per-exercise set-count suggestion |
| Overreaching alarm | `normalizedError` trending positive across exercises ~1 week | Deload suggestion |
| Bang-for-buck ranking | ≥8 weeks of data; quarterly cadence | Suggest swapping low-yield exercises |
| Time-of-day effect | Consistent ≥3% morning/evening gap | None (trivia, low rank) |

Statistical honesty note: order-effect and recovery findings are observational.
They only fire for users whose data actually varies (different slots, different
spacing) — the confidence gate enforces this, so users with constant habits
simply never see those cards.

## Selection pipeline

Runs at workout finish on a background task (same hook `FatigueLearningService`
uses). Stages:

1. **Generate** — every rule runs, emits zero or more candidate findings.
   Each finding carries: confidence, effect size, actionability, novelty.
2. **Gate** — data sufficiency + statistical confidence + minimum effect size.
   Below any threshold → silent. Never show "insufficient data".
3. **Score** — `effectSize × actionability × novelty`, multiplied by per-category
   persona weights. Worsening findings (growing asymmetry, drought) get an
   urgency bump.
4. **Curate** — max 1 card per category, hard cap ~3, per-instance cooldowns.
5. **Feed** — 0–3 cards persisted as `InsightRecord`s. Zero is allowed; the
   empty state says when the next analysis runs.

### Insight lifecycle

Identity = (ruleId, subjectId — exercise or muscle group). State machine on
`InsightRecord`:

- `detected → shown` — appears in feed, badge increments.
- `shown → resolved` — metric improved after user saw it → show a resolution
  card ("longer squat rests are worth +1.5 reps"). Best retention mechanic.
- `shown → cooldown` — no change → suppressed ~3 weeks, then may resurface.
- `cooldown → regressed` — materially worse → cooldown breaks, urgency bump.

### Relevance without a stated goal

Onboarding does not capture training goals. Two composable mechanisms:

- **Inferred persona** — median working rep range (strength vs. hypertrophy vs.
  endurance), bodyweight trend direction (cutting → retention insights up),
  program usage (structure-oriented → adherence insights up), unilateral volume
  (symmetry-conscious). These set per-category weight multipliers.
- **Direct feedback** — dismiss downweights a category; tap-through/share
  upweights. A few float multipliers persisted per profile. An optional future
  onboarding question would just initialize the same weights.

### Cold start

Locked cards with progress bars ("3 more bench sessions until your rest
analysis unlocks") turn the statistical gates into an engagement loop instead
of an empty feature.

## Interactions

Per card:
1. Tap → detail: full chart, supporting numbers, "how this was computed"
   disclosure (e.g. "23 sets over 6 weeks"). Methodology line builds trust.
2. Primary action button — deep-links into existing editors (rest time,
   template reorder, targets, planned workout). Ship insights whose actions
   reuse existing screens first; the deep links are the main engineering cost.
3. Snooze (swipe/button) → cooldown. Overflow: "don't show this type again"
   → category weight.
4. Share → renders as share card (same component family as the roadmap share
   card feature).

Per page: New / Earlier / Locked sections; empty state with next-analysis hint;
mark-as-seen on appear.

System: background pipeline at workout finish; push notifications reserved for
urgent regressions only (later phase, sparing).

## Architecture

- New feature folder `Repster/Features/Insights/` (Views, ViewModels, Models)
  following existing feature conventions.
- New `InsightsEngine` service in `Core/Services`: owns the rule registry and
  pipeline; each rule is a small type conforming to an `InsightRule` protocol
  (`evaluate(context:) -> [CandidateFinding]`).
- New SwiftData model `InsightRecord`: ruleId, subjectId, state, score,
  payload (headline + chart data), firstDetected, lastShown, lastValue.
- Precedent: `ExerciseStats` already demonstrates the cached-aggregate pattern;
  the engine recomputes at session end, UI reads persisted records instantly.
- All on-device; data volume (~4k sets/user/year) makes every rule a trivial
  in-memory aggregation. No ML, no server.

## Phasing

1. **Phase 0** — logging fixes (`startedAt`, rest-on-dismissal). Deferred by
   decision (2026-06-11): no changes to workout-logging code for now. The rest
   rule runs on timer-completed rests only until this lands.
2. **Phase 1** — engine + `InsightRecord` + Insights page + home entry card +
   launch rules. Snooze + detail. **Shipped to NewMain 2026-06-11** (5 rules:
   rest sweet spot, target adherence, muscle balance, PR rhythm, RIR
   calibration; action deep links deferred to Phase 2).
3. **Phase 2** — share rendering (align with share card feature), locked-card
   progress, persona weights, more rules.
4. **Phase 3** — Tier 3 rules, resolution cards, notifications for regressions.
