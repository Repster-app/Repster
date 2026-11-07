# Training Data Sharing — Design

**Status:** Built 2026-10-22 for 1.6 (`4fef2c0`). Smart Suggestion data added 2026-11-06
(schema 2, see [below](#smart-suggestion-data-schema-2)). Sending has run on TestFlight builds.
The manual history upload had not run on a phone as of 2026-11-04.
**Code:** `Repster/Core/Services/TrainingDataSharingService.swift`. Tests are in
`RepsterTests/TrainingDataSharingTests.swift`.

## Why

There are three goals: analyse what people actually lift, grow the built-in exercise
library from what people add, and later publish percentile rankings. All three need
set-level data, which Repster never collected before. Product analytics events are bucketed
on purpose (`set_count_bucket: "4-6"`), and that stays true.

## Decisions (user, 2026-10-22)

| Question | Decision |
|---|---|
| Where it goes | PostHog events, in the same project as analytics. No separate database. |
| Where it's offered | Settings only: Data & Backups → Share Training Data |
| Default | **On for everyone, with no automatic history upload** |

"No automatic history upload" works like this:

- **Default-on window.** The first launch of 1.6 stores `shareTrainingDataSince = now`.
  Only workouts dated after that are shared automatically, including their edits and
  deletes.
- **Manual switch-on.** If the user turns the toggle on themselves (always from off),
  the window moves to `.distantPast` and `shareHistory()` sends every completed workout
  and every custom exercise. Doing it by hand counts as the consent for history logged
  under the old policy.
- **CSV imports.** Imported *workouts* are never sent automatically, because they're
  history from before Repster. The *exercises* an import had to create are sent with
  `source: csv_import`. Their names show how Strong, Hevy and FitNotes label the same
  lifts.

## Gating

```
isSharingActive = Share Anonymous Analytics && Share Training Data
```

Turning analytics off turns this off too, and the Settings toggle shows off and disabled
while analytics is off. DEBUG builds use `NoopAnalyticsService`, so they send nothing
unless `-analyticsDebugCaptureEnabled YES` is set.

## Events

All events carry `schema_version`, which is now 2. Version 2 (2026-11-06) added `e1rm_formula` and
each set's `suggestion`. Only TestFlight builds ever sent version 1. Keys are snake_case and dates
are ISO 8601.

| Event | When | Properties |
|---|---|---|
| `training workouts shared` | finish; edit (only if shared content changed); progression-exclusion change; history share in chunks of 20 | `reason` (`finished`/`edited`/`history`), `workout_count`, `e1rm_formula`, `workouts[]` |
| `training workout deleted` | a shared, completed workout is deleted | `workout_id` |
| `training exercises created` | form create, CSV import, history share, in chunks of 50 | `source` (`manual`/`csv_import`/`history`), `exercise_count`, `exercises[]` |
| `training data sharing toggled` | Settings toggle (a normal analytics event) | `enabled` |

`workouts[]` item:
- `workout_id`, `date`, `duration_seconds`, `perceived_effort`, `from_program`,
  `excluded_from_progression`
- `exercises[]`: `exercise_id`, `name`, `built_in`, `equipment`, `tracking_type`,
  `primary_muscle`, `movement_pattern`, `unilateral`, `excluded_from_progression`, `sets[]`
- `sets[]`: `order`, `type`, `completed`, `weight_kg`, `reps`, `left_reps`, `right_reps`,
  `side`, `rir`, `left_rir`, `right_rir`, `rpe`, `duration_seconds`, `distance_meters`,
  `rest_seconds`, `superset_group` (1…n per workout), `excluded_from_prs`,
  `target_weight_kg`, `target_rep_min`, `target_rep_max`, `target_rir`, `suggestion`
  (ticked sets only, see below)

**Never sent** (a test asserts the free-text ones):
- Notes and workout titles.
- `effective_weight` and the stored `e1RM`. Both fold bodyweight in on bodyweight
  exercises, so you could work backwards to the user's bodyweight. Stored e1RM also
  depends on which formula each user picked, so recompute it from `weight_kg` and `reps`.
- Smart Suggestions' figures on an exercise that adds bodyweight, for the same reason.

**Unticked sets are sent with `completed: false`, not dropped.** Copy Previous rows that
were never ticked carry real weight and reps (`UNPERFORMED_SETS_SCOPING.md`). Filter on
`completed` in every query.

## Smart Suggestion data (schema 2)

Added 2026-11-06 so Smart Suggestions can be calibrated across users instead of one phone at a
time. Nothing new is tracked: every ticked set already gets a `FatigueLearningSetAudit` row at
the tick, and the payload copies it.

`e1rm_formula` is on the event: `epley`, `brzycki` or `lombardi`, resolved the way the engine
does it (Epley when unset). Every e1RM figure in the event was computed with it. It's read at
send time, so a history share labels old workouts with today's formula.

`suggestion` is on each ticked set that has a row:

| Field | Audit field | Meaning |
|---|---|---|
| `status` | `status` | `used`, `baselineFirstWorkingSet`, `suggestionUnavailable`, `missingRIR`, `weightDeviationOver20Percent`, `invalidPerformance`, `warmupNotTracked`, `nonCapacitySetType` |
| `unavailable_reason` | `suggestionUnavailableReason` | Why there was no suggestion: `noStrengthData`, `featureDisabled`, `bodyweightHistoryOnly` and so on. Missing on `suggestionUnavailable` when no suggestion had loaded for that set, after a fast tick for example |
| `suggested_weight_kg` | `prescribedWeight` | The suggestion as it stood at the tick |
| `e1rm_predicted_kg` | `predictedEffectiveE1RM` | The capacity the model expected for this set, after fatigue |
| `e1rm_base_kg` | `baseE1RM` | The baseline it started from: the peak of the last 3 workouts in the recency window, or else the most recent workout |
| `model_epoch` | `modelEpoch` | 1 = before 1.5 (stored as nil), 2 = current |
| `captured_at` | `createdAt` | When the prediction was recorded |

**What keeps it within the policy:**
- **Bodyweight.** The engine works in effective weight, so on an exercise with
  `bodyweightFactor > 0` every figure has bodyweight folded in. Those sets send only
  `status`, `unavailable_reason`, `model_epoch` and `captured_at`. The same happens when the
  row's stored weight differs from the set's weight, which catches a factor changed after the
  tick.
- **Ticked sets only.** Un-ticking deletes the row, so a row left on an unticked set is stale
  and isn't sent.

**Reading it:**
- **Take suggestions from the `finished` event, not the latest one.** Editing a set in history
  deletes its row, and nothing writes it again, so an `edited` event can lack a suggestion that
  was there at finish. Weights and reps still come from the latest event.
- **Drop re-ticked sets.** A set ticked again after a later set was predicted with that later
  set already done, so it isn't a forecast. Simplest filter: drop a set whose `captured_at` is
  later than that of a set with a higher `order` in the same exercise. Un-ticks are common: 85
  of 143 public 1.5 workouts had at least one.
- **Accuracy needs RIR.** With `rir`, actual capacity is `formula(weight_kg, reps + rir)` (the
  phone rounds `rir` down to a whole number), and the error is `(predicted − actual) / base`.
  That's the phone's own `normalizedError`, and negative means the lifter was stronger than
  predicted. Without RIR, `formula(weight_kg, reps)` is only a lower bound. In public 1.5, 54 of
  143 workouts had any RIR.
- **`suggested_weight_kg` doesn't measure adherence.** Typing reps re-prices the suggestion to
  those reps before the tick, so it's usually the price of what was logged. Nothing records
  what the lifter saw first.
- **Calibrate on epoch 2 only.** Epoch 1 rows came from a reps-only baseline.
- **Not sent, and not stored on the phone either:** the rep and RIR target the suggestion
  aimed at, the fatigue rate it applied and where that came from, and the rest it assumed.
  Capturing them needs new stored fields, so that's a 1.7 question.

## Querying (HogQL)

The queries below are untested starting points. They need checking against real events once some exist.

Events are never edited, so the **latest event per `workout_id` wins**, and a tombstone
removes a workout. Leave out installs that switched sharing off. You may also want to
exclude the TestFlight account `39de1ef1`.

```sql
-- One row per current workout
WITH shared AS (
  SELECT distinct_id, timestamp,
         arrayJoin(JSONExtractArrayRaw(properties, 'workouts')) AS w
  FROM events WHERE event = 'training workouts shared'
),
latest AS (
  SELECT JSONExtractString(w, 'workout_id') AS workout_id,
         argMax(w, timestamp) AS workout, argMax(distinct_id, timestamp) AS person
  FROM shared GROUP BY workout_id
)
SELECT * FROM latest
WHERE workout_id NOT IN (
  SELECT properties.workout_id FROM events WHERE event = 'training workout deleted'
)
```

Sets follow from a second `arrayJoin` over `exercises`, then over `sets`.

**Seed-library candidates:** custom names created by at least 3 installs.

```sql
SELECT lower(trim(JSONExtractString(e, 'name'))) AS name,
       count(DISTINCT distinct_id) AS installs
FROM (SELECT distinct_id, arrayJoin(JSONExtractArrayRaw(properties, 'exercises')) AS e
      FROM events WHERE event = 'training exercises created')
WHERE JSONExtractBool(e, 'built_in') = 0
GROUP BY name HAVING installs >= 3 ORDER BY installs DESC
```

## Volume

- **Per workout:** one event per finished workout, roughly as many events as
  `workout completed`.
- **History share:** the largest real history (579 workouts) becomes 29 events. Chunking
  keeps a history share well inside the posthog-ios queue (1,000 events, oldest evicted
  first).

## Open

1. **Already-shared data after switching off.** Sharing stops immediately, and the toggle
   event marks the moment. The policy makes no promise about deleting what was already
   sent. PostHog can delete a person with all their events, but not one event type. Decide
   whether to commit to deleting it, and how.
2. **App Store label.** `Fitness` is already declared (Analytics, not linked). Decide
   whether custom exercise names also need `Other User Content`
   (`privacy-review-checklist.md`).
3. **Template import** creates exercises too (`TemplateService.makeExercise`) and isn't
   reported. It's rare, so it's left out for now.
4. **Legal read.** Default-on sharing of training logs is a judgement call for EU users.
   Treat it as a decision to revisit, not a settled one.
5. **Deploy order.** `docs/privacy.html` goes live when `NewMain` is pushed, and it has to
   be live before a 1.6 build reaches users.
