# Repster PostHog Guide

What every event means, which five dashboards to build, and the exact prompts to
paste into PostHog's AI (Max) to build them.

Project host: `https://eu.i.posthog.com` (EU cloud — the UI lives at
`https://eu.posthog.com`, not `app.posthog.com`).

Source of truth for everything below:
[AnalyticsServiceProtocol.swift](Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift).
If an event isn't in that file, Repster doesn't send it.

---

## 1. Three things that will confuse you before anything else

**Screens are not events.** `analyticsService.screen(.home)` sends PostHog's
built-in `$screen` event with a `$screen_name` property (`"Home"`, `"Charts"`,
`"Insights"`, …). There is no event called "Home". To chart screen traffic, pick
the `$screen` event and break down by `$screen_name`.

**Every count is a bucketed string, not a number.** `set_count_bucket` is
`"4-6"`, not `5`. You cannot average it — you can only count events per bucket or
break down by it. This was a deliberate privacy choice (no raw training data
leaves the device), so don't fight it. The only raw numbers you can average are
`prs_hit`, `finding_count`, `group_count`, `insight_age_days`,
`step_index`, and `remaining_free_workouts`.

**`workout abandoned` always arrives late.** It's detected on the *next* app
launch, 12+ hours after the fact. Never put it on a same-day chart next to
`workout completed` — it will look artificially low today and spike tomorrow.

---

## 1b. What the shipped build actually sends (as of 2026-08-09)

**App Store version is 1.3. Most events in this guide are not in it yet.**
`first set logged`, all onboarding events, all insight events, `empty state shown`,
`workout abandoned`, `workout resumed`, `exercise created`, `template created` and
`review prompt requested` were all added in commit `f4d2e65` (2026-08-08), which
lives only on `NewMain` and has never been released.

Shipped in 1.3 — these can contain real user data:

> `workout started`, `workout completed`, `workout discarded`,
> `paywall shown`, `paywall dismissed`, `purchase started`, `purchase completed`,
> `purchase cancelled`, `restore purchases tapped`, `import started`,
> `import completed`, `backup exported`, `backup imported`,
> `unit system toggled`, `analytics opt-out toggled`
>
> Screens (`$screen_name`): `Home`, `Calendar`, `Charts`, `Settings`,
> `Active Workout`, `Workout Summary`, `Paywall`
>
> Plus PostHog's `Application Installed` / `Opened` / `Became Active`

All `workout completed` properties listed below — including `access_tier` and
`remaining_free_workouts` — are already in 1.3.

**Therefore, until 1.4 ships:** Dashboard 3 (Monetization) and Dashboard 5
(Health) are fully populated with real data. Dashboard 2 (Core loop) works except
`workout abandoned`, `workout resumed` and `template created`. Dashboard 1
(Activation) can only do `Application Installed` → `workout started` →
`workout completed`. Dashboard 4 (Insights) will be empty.

**Any event outside the shipped list that appears in PostHog right now is a debug
build — i.e. you.** DEBUG builds use the same project token as production, so
simulator runs land in production analytics. See gap 6 in section 5.

## 2. What each event actually means

### Lifecycle (PostHog sends these itself)
| Event | Meaning |
|---|---|
| `Application Installed` | First launch after install. Your denominator for activation. |
| `Application Opened` | Cold launch. |
| `Application Became Active` | Foreground, incl. returning from background — inflates "opens", don't use it for retention. |

### Onboarding
| Event | Key properties | Meaning |
|---|---|---|
| `onboarding step viewed` | `step`, `step_index` | Steps: `welcome`, `units`, `bodyweight`, `smart_suggestions`, `apple_health`, `import_prompt`. `apple_health` is absent on hardware without HealthKit, so it has a smaller denominator than its neighbours by design. |
| `onboarding step skipped` | `step`, `step_index` | Explicit skip. Not the same as dropping off. |
| `onboarding completed` | `step` (last step), `unit_system` | Reached the end. |

### The core loop
| Event | Key properties | Meaning |
|---|---|---|
| `workout started` | `source`, `template_used`, `copied_previous`, `count_toward_progression` | Sources: `empty`, `exercise_list`, `template`, `copy_previous`. |
| `first set logged` | `elapsed_seconds_bucket`, `source` | Fires once per workout. **This is your true activation event** — it separates "opened a workout" from "actually trained". |
| `workout completed` | `duration_bucket`, `set_count_bucket`, `exercise_count_bucket`, `total_reps_bucket`, `prs_hit`, `time_of_day`, `day_of_week`, `access_tier`, `remaining_free_workouts`, `rir_entered`, `average_rir_bucket`, `perceived_effort_entered`, `notes_entered` | The success event. `access_tier` is `free` or `subscribed`. |
| `workout discarded` | `duration_bucket`, `set_count_bucket`, `source` | Deliberate throw-away. |
| `workout abandoned` | `set_count_bucket`, `source`, `template_used` | Walked away, never returned. Lagged (see above). |
| `workout resumed` | `set_count_bucket` | Came back to an in-flight session. |

`started` = `completed` + `discarded` + `abandoned` + `resumed`-then-terminal.
The ratio between those three terminal states is the single most useful health
number you have.

### Activation / depth
| Event | Key properties | Meaning |
|---|---|---|
| `exercise created` | `source` | Currently only ever `create_exercise_form`. |
| `template created` | `exercise_count_bucket`, `source` | Strong retention predictor — worth watching. |
| `empty state shown` | `screen_name`, `has_data` | A screen rendered with nothing in it. Only fires for Home, Charts and Insights. |

### Monetization
| Event | Key properties | Meaning |
|---|---|---|
| `paywall shown` | `source` | Sources: `paywall` (hit the 5-workout wall), `settings`, `membership_settings`. |
| `paywall dismissed` | `source` | |
| `purchase started` / `completed` / `cancelled` | `source` | `cancelled` = user backed out of Apple's sheet. |
| `restore purchases tapped` | `source` | Spikes here usually mean a support problem, not intent. |

Free limit is **5 workouts** (`RevenueCatConfiguration.freeWorkoutLimit`), so
`remaining_free_workouts` on `workout completed` counts down 4→0.

### Training Insights
Every event carries `rule_id`, one of: `strengthTrend`, `consistency`,
`droppedExercise`, `volumeRamp`, `restSweetSpot`, `targetAdherence`,
`muscleBalance`, `prPace`, `rirCalibration`, `deloadReadiness`.

| Event | Key properties | Meaning |
|---|---|---|
| `$screen` where `$screen_name = Insights` | `finding_count`, `has_new`, `has_baseline` | **Opening Insights is a screen event, not its own event.** There is no `insights opened` — it was a duplicate of this screen call and was removed. Filter `$screen` to `$screen_name = Insights` wherever this guide says "Insights opened". |
| `insight expanded` | `rule_id` | Read the finding. Implicit interest. |
| `insight rated` | `rule_id`, `rating` (`useful`/`not_useful`), `insight_age_days` | Explicit verdict, only reachable from an expanded card. |
| `insight snoozed` | `rule_id`, `insight_age_days` | **The strongest kill signal** — hiding a finding for three weeks beats any thumbs-down and has no response-rate bias. |
| `muscle panel expanded` | `group_count` | |

### Data & settings
| Event | Key properties | Meaning |
|---|---|---|
| `import started` | `source_type`, `unit_system` | |
| `import completed` | `result`, `source_type`, `row_count_bucket`, `set_count_bucket`, `workout_count_bucket`, `error_type` | `result` is `success` or a failure. Import failure is a churn cliff — a user who can't get their history in leaves. |
| `backup exported` / `backup imported` | — | |
| `unit system toggled` | `unit_system` | |
| `analytics opt-out toggled` | `enabled` | Fires in both directions (deliberately sent *before* the opt-out takes effect). |
| `review prompt requested` | `trigger`, `completed_workout_count` | |

### Apple Health
| Event | Key properties | Meaning |
|---|---|---|
| `apple health prompt shown` | `source` | Repster's own ask, before HealthKit's. Sources: `onboarding`, `settings`, `whats_new`. Only fires where Repster raises the offer itself — the Settings toggle is already a decision, so it goes straight to `answered`. Idempotent per surface. |
| `apple health prompt answered` | `source`, `result` | `result` is `not_now` (declined in Repster, iOS never asked), `authorized`, `denied`, `unavailable`, or `failed`. |
| `apple health disabled` | `source` | Switched off again later. Always `settings`. |

`shown` → `answered: authorized` is the connect rate for a surface, and comparing
`not_now` against `denied` separates "doesn't want it" from "iOS asked and they
said no" — only the second is unrecoverable without a trip to the Health app.

Note `step_index` for `import_prompt` moved from 4 to 5 in 1.4 when the Apple
Health step was inserted ahead of it. The `step` name is unchanged; build funnels
on the name, not the index.

Every event also carries `app_version` and `build_number` — always available as a
breakdown or filter, and the first thing to check when a metric moves.

---

## 3. The five dashboards

Build them in this order. Dashboard 1 and 4 are where the decisions are.

### Dashboard 1 — Activation: install → first real set
The question: *of everyone who installs, how many ever log a single set?*

1. **Activation funnel** (Funnel, 14-day conversion window, last 30 days)
   `Application Installed` → `onboarding completed` → `workout started` →
   `first set logged` → `workout completed`
2. **Onboarding drop-off by step** (Funnel, ordered)
   `onboarding step viewed` five times, each filtered to one `step` value:
   `welcome`, `units`, `bodyweight`, `smart_suggestions`, `import_prompt`
3. **Skip rate by step** (Trends, unique users, breakdown `step`) — `onboarding step skipped`
4. **Time to first set** (Trends, total count, breakdown `elapsed_seconds_bucket`) — `first set logged`
5. **Empty states hit** (Trends, unique users, breakdown `screen_name`) — `empty state shown`
6. **Activation rate trend** (Trends, weekly) — unique users on `first set logged` ÷ unique users on `Application Installed`

### Dashboard 2 — The core loop
The question: *do people keep training in the app?*

1. **Weekly active loggers** (Trends, unique users, weekly) — `workout completed`
2. **Retention** (Retention, weekly, 8 periods) — cohortise on `workout completed`, return on `workout completed`
3. **Lifecycle** (Lifecycle, weekly) — `workout completed` (new / returning / resurrecting / dormant)
4. **Terminal state of started workouts** (Trends, total count) — `workout completed`, `workout discarded`, `workout abandoned` on one chart, weekly
5. **Where workouts start** (Trends, breakdown `source`) — `workout started`
6. **Template users vs not** (Trends, unique users, breakdown `template_used`) — `workout completed`
7. **Session shape** (Trends, breakdown `duration_bucket`, then a second tile for `set_count_bucket`) — `workout completed`
8. **When people train** (Trends, breakdown `day_of_week`; second tile `time_of_day`) — `workout completed`
9. **Templates created** (Trends, unique users) — `template created`

### Dashboard 3 — Monetization
The question: *does hitting the wall convert, and from where?*

1. **Purchase funnel** (Funnel, 1-day window, breakdown `source`)
   `paywall shown` → `purchase started` → `purchase completed`
2. **Paywall exposure by source** (Trends, unique users, breakdown `source`) — `paywall shown`
3. **Conversion rate over time** (Trends, weekly) — `purchase completed` unique users ÷ `paywall shown` unique users
4. **Approaching the wall** (Trends, unique users, breakdown `remaining_free_workouts`) — `workout completed`
5. **Free vs subscribed volume** (Trends, breakdown `access_tier`) — `workout completed`
6. **Abandoned at Apple's sheet** (Trends) — `purchase cancelled` vs `purchase completed`
7. **Restore taps** (Trends, weekly) — `restore purchases tapped`, broken down by `source`

### Dashboard 4 — Training Insights: which rules earn their place
The question: *which of the ten rules do I keep, sharpen, or cut?*
This is the one that pays for itself.

1. **Insights opened** (Trends, unique users, weekly) — `$screen`, filtered to `$screen_name = Insights`
2. **Findings shown per open** (Trends, average of `finding_count`) — same `$screen` filter
3. **Expands by rule** (Trends, total count, breakdown `rule_id`) — `insight expanded`
4. **Verdict by rule** (Trends, total count, breakdown `rule_id`, filtered to `rating = not_useful`) — `insight rated`; duplicate the tile for `rating = useful`
5. **Snoozes by rule** (Trends, total count, breakdown `rule_id`) — `insight snoozed` — **read this one first**
6. **Snooze-to-expand ratio by rule** (SQL insight — see below) — the actual kill list
7. **Age at judgement** (Trends, average of `insight_age_days`) — `insight snoozed`
8. **Muscle panel opens** (Trends, unique users) — `muscle panel expanded`

SQL for tile 6 (paste into a SQL insight):

```sql
SELECT
    properties.rule_id AS rule,
    countIf(event = 'insight expanded')  AS expands,
    countIf(event = 'insight snoozed')   AS snoozes,
    countIf(event = 'insight rated' AND properties.rating = 'useful')     AS useful,
    countIf(event = 'insight rated' AND properties.rating = 'not_useful') AS not_useful,
    round(countIf(event = 'insight snoozed') / nullif(countIf(event = 'insight expanded'), 0), 2) AS snooze_per_expand
FROM events
WHERE event IN ('insight expanded', 'insight snoozed', 'insight rated')
  AND timestamp > now() - INTERVAL 60 DAY
GROUP BY rule
ORDER BY snooze_per_expand DESC
```

High `snooze_per_expand` = people read it and actively want it gone. Cut those first.

### Dashboard 5 — Health & data ops
The question: *is anything quietly broken?*

1. **Import funnel** (Funnel, 1-hour window) — `import started` → `import completed`
2. **Import outcomes** (Trends, breakdown `result`) — `import completed`
3. **Import failures by source** (Trends, breakdown `source_type`, filtered `result != success`) — `import completed`
4. **Backups** (Trends) — `backup exported`, `backup imported`
5. **Version mix** (Trends, unique users, breakdown `app_version`) — `Application Opened`
6. **Analytics opt-outs** (Trends, breakdown `enabled`) — `analytics opt-out toggled`
7. **Screen traffic** (Trends, unique users, breakdown `$screen_name`) — `$screen`
8. **Unit preference** (Trends, breakdown `unit_system`) — `unit system toggled`
9. **Review prompts** (Trends, breakdown `trigger`) — `review prompt requested`

---

## 4. Prompts to paste into PostHog Max

One per dashboard. Paste verbatim — they name exact events and properties, which
is what stops the AI inventing things that don't exist in your project.

### Prompt 1 — Activation

> Create a dashboard called "Repster — Activation" for my iOS app. Use only these
> events and properties, they all exist in this project:
>
> 1. Funnel, last 30 days, 14-day conversion window: `Application Installed` →
>    `onboarding completed` → `workout started` → `first set logged` →
>    `workout completed`.
> 2. Ordered funnel of `onboarding step viewed`, five steps, each filtered to a
>    different value of the `step` property in this order: `welcome`, `units`,
>    `bodyweight`, `smart_suggestions`, `import_prompt`.
> 3. Trend, unique users, weekly, of `onboarding step skipped` broken down by `step`.
> 4. Trend, total count, of `first set logged` broken down by `elapsed_seconds_bucket`.
> 5. Trend, unique users, of `empty state shown` broken down by `screen_name`.
> 6. Trend, weekly, showing unique users of `first set logged` divided by unique
>    users of `Application Installed`.
>
> Note: `first set logged` is my real activation event — it fires once per workout
> on the first completed set.

### Prompt 2 — Core loop

> Create a dashboard called "Repster — Core Loop". Use only these events and
> properties:
>
> 1. Trend, unique users, weekly: `workout completed`.
> 2. Weekly retention insight over 8 periods, cohortised on `workout completed`
>    and returning on `workout completed`.
> 3. Weekly lifecycle insight for `workout completed`.
> 4. Trend, total count, weekly, with three series on one chart: `workout completed`,
>    `workout discarded`, `workout abandoned`.
> 5. Trend of `workout started` broken down by the `source` property (values:
>    `empty`, `exercise_list`, `template`, `copy_previous`).
> 6. Trend, unique users, of `workout completed` broken down by `template_used`.
> 7. Trend of `workout completed` broken down by `duration_bucket`.
> 8. Trend of `workout completed` broken down by `set_count_bucket`.
> 9. Trend of `workout completed` broken down by `day_of_week`.
> 10. Trend of `workout completed` broken down by `time_of_day`.
> 11. Trend, unique users, weekly: `template created`.
>
> Important: `workout abandoned` is detected on the next app launch, at least 12
> hours after it happens, so it always lags. Don't compare it to today's
> `workout completed`.

### Prompt 3 — Monetization

> Create a dashboard called "Repster — Monetization". My app has a 5-workout free
> limit and a single subscription. Use only these events and properties:
>
> 1. Funnel, 1-day conversion window: `paywall shown` → `purchase started` →
>    `purchase completed`, broken down by the `source` property (values: `paywall`,
>    `settings`, `membership_settings`).
> 2. Trend, unique users, of `paywall shown` broken down by `source`.
> 3. Trend, weekly, of unique users on `purchase completed` divided by unique users
>    on `paywall shown`.
> 4. Trend, unique users, of `workout completed` broken down by
>    `remaining_free_workouts` (an integer counting down from 4 to 0).
> 5. Trend of `workout completed` broken down by `access_tier` (values: `free`,
>    `subscribed`).
> 6. Trend, weekly, with two series: `purchase cancelled` and `purchase completed`.
> 7. Trend, weekly, of `restore purchases tapped` broken down by `source`.

### Prompt 4 — Training Insights

> Create a dashboard called "Repster — Training Insights" to decide which of my
> ten insight rules to keep or cut. Every insight event carries a `rule_id`
> property with one of these values: `strengthTrend`, `consistency`,
> `droppedExercise`, `volumeRamp`, `restSweetSpot`, `targetAdherence`,
> `muscleBalance`, `prPace`, `rirCalibration`, `deloadReadiness`.
>
> Opening the Insights screen is recorded as the built-in `$screen` event with
> `$screen_name = Insights`; the finding properties ride on that same event.
>
> 1. Trend, unique users, weekly: `$screen` filtered to `$screen_name = Insights`.
> 2. Trend showing the average of the `finding_count` property on that same
>    filtered `$screen` event.
> 3. Trend, total count, of `insight expanded` broken down by `rule_id`.
> 4. Trend, total count, of `insight rated` filtered to `rating = useful`, broken
>    down by `rule_id`.
> 5. Trend, total count, of `insight rated` filtered to `rating = not_useful`,
>    broken down by `rule_id`.
> 6. Trend, total count, of `insight snoozed` broken down by `rule_id`.
> 7. Trend showing the average of `insight_age_days` on `insight snoozed`.
> 8. Trend, unique users, of `muscle panel expanded`.
>
> Then add a SQL insight called "Rule kill list" using this query:
>
> ```sql
> SELECT
>     properties.rule_id AS rule,
>     countIf(event = 'insight expanded')  AS expands,
>     countIf(event = 'insight snoozed')   AS snoozes,
>     countIf(event = 'insight rated' AND properties.rating = 'useful')     AS useful,
>     countIf(event = 'insight rated' AND properties.rating = 'not_useful') AS not_useful,
>     round(countIf(event = 'insight snoozed') / nullif(countIf(event = 'insight expanded'), 0), 2) AS snooze_per_expand
> FROM events
> WHERE event IN ('insight expanded', 'insight snoozed', 'insight rated')
>   AND timestamp > now() - INTERVAL 60 DAY
> GROUP BY rule
> ORDER BY snooze_per_expand DESC
> ```
>
> There is no `insights opened` event and no `source` property on the Insights
> screen view — both were removed as duplicates.

### Prompt 5 — Health & data ops

> Create a dashboard called "Repster — Health". Use only these events and properties:
>
> 1. Funnel, 1-hour conversion window: `import started` → `import completed`.
> 2. Trend of `import completed` broken down by the `result` property.
> 3. Trend of `import completed` broken down by `source_type`, filtered to
>    `result` is not `success`.
> 4. Trend, weekly, with two series: `backup exported` and `backup imported`.
> 5. Trend, unique users, of `Application Opened` broken down by `app_version`.
> 6. Trend of `analytics opt-out toggled` broken down by `enabled`.
> 7. Trend, unique users, of the `$screen` event broken down by `$screen_name`.
> 8. Trend of `unit system toggled` broken down by `unit_system`.
> 9. Trend of `review prompt requested` broken down by `trigger`.

### Two alerts worth setting up afterwards

> Create an alert that notifies me when the weekly unique-user count of
> `import completed` filtered to `result` is not `success` increases by more than
> 50% week over week.

> Create an alert that notifies me when the weekly conversion rate of the funnel
> `workout started` → `first set logged` drops below 70%.

---

## 5. Instrumentation gaps found while writing this

Small code fixes that would make the dashboards above meaningfully better.

1. **`insight rating reason` never fires.** The helper
   `insightRatingReason(ruleId:reason:)` exists in
   [AnalyticsServiceProtocol.swift:420](Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift:420)
   but has no call site. The "why wasn't this useful" signal — the most
   actionable thing on Dashboard 4 — is not being collected. Either wire it into
   the thumbs-down flow in `InsightCardView` or delete the helper.

2. **Three screens are invisible.** `AnalyticsScreen.exerciseList`, `.templates`
   and `.history` are declared but never fired, so they'll be missing from the
   `$screen_name` breakdown entirely — which reads as "nobody uses them" rather
   than "not measured".

3. ~~**`insights opened` has a hardcoded source.**~~ **Fixed 2026-08-10.** The
   event is gone entirely — it duplicated the Insights `$screen` call fired
   alongside it, so the finding properties moved onto the screen event and the
   fake `source: "hook"` was dropped. One open now costs one event.

4. ~~**Home fires `$screen` twice, differently.**~~ **Fixed 2026-08-10.** Charts
   had the same problem. `ContentView` is now the only emitter of `$screen` for
   the four tabs; `HomeView` and `ChartsTabView` report the empty case with
   `empty state shown` alone and no longer send a second screen event. `$screen`
   counts are comparable across all four tabs from this build onward — screen
   traffic before it is inflated for Home and Charts only.

5. **`exercise created` has one source value.** Only `create_exercise_form` is
   ever sent, so that breakdown is a single bar today.

6. ~~**No dev/production separation.**~~ **Fixed 2026-08-10.** There is still one
   `POSTHOG_PROJECT_TOKEN`, but `AnalyticsServiceFactory.makeService` now returns
   `NoopAnalyticsService` under `#if DEBUG`, so simulator runs write nothing to
   the production project.

   **To verify instrumentation locally**, add this to the scheme's launch
   arguments for that run (Product → Scheme → Edit Scheme → Run → Arguments):

   ```
   -analyticsDebugCaptureEnabled YES
   ```

   That writes to the production project on purpose — use it deliberately, and
   remember those events land in real funnels. The cleaner long-term fix is still
   a second "Repster Dev" project token in the Debug xcconfig, at which point this
   guard can be dropped.

   **Anything captured before 2026-08-10 from a debug build is contamination.**
   Filter it out of historical funnels where it matters.

7. **`Application Installed` casing.** posthog-ios 3.58.1 — the only version this
   project has ever resolved — emits `Application Installed` with a capital I
   (`PostHogAppLifeCycleIntegration.swift:120`). There is no code path in the app
   or SDK that produces a lowercase variant, and the marketing site has no
   posthog-js snippet. Keep the capital-I event in all insights. If a lowercase
   definition shows real 30-day volume in Data Management → Events, something
   outside this repo is writing to the project.
