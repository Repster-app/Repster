# Training Data Sharing — Design

**Status:** Built 2026-10-22 for 1.6 (uncommitted). Not device-tested.
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

All events carry `schema_version: 1`. Keys are snake_case and dates are ISO 8601.

| Event | When | Properties |
|---|---|---|
| `training workouts shared` | finish; edit (only if shared content changed); progression-exclusion change; history share in chunks of 20 | `reason` (`finished`/`edited`/`history`), `workout_count`, `workouts[]` |
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
  `target_weight_kg`, `target_rep_min`, `target_rep_max`, `target_rir`

**Never sent** (a test asserts the free-text ones):
- Notes and workout titles.
- `effective_weight` and the stored `e1RM`. Both fold bodyweight in on bodyweight
  exercises, so you could work backwards to the user's bodyweight. Stored e1RM also
  depends on which formula each user picked, so recompute it from `weight_kg` and `reps`.

**Unticked sets are sent with `completed: false`, not dropped.** Copy Previous rows that
were never ticked carry real weight and reps (`UNPERFORMED_SETS_SCOPING.md`). Filter on
`completed` in every query.

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
