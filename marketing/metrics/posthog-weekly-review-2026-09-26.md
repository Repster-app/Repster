# Repster: weekly PostHog review, 26 September 2026

Read-only review of Repster's Default project (180066), using **19–25 September** versus **12–18 September**, Europe/Copenhagen. Both windows contain seven complete days. Today's partial day is excluded.

**Main finding:** the selected-program-to-workout handoff remains the clearest issue to investigate. Overall traffic is approximately flat, while a few users show meaningful repeat training.

## Weekly comparison

| Metric | 12–18 Sep | 19–25 Sep |
|---|---:|---:|
| Active analytics persons, any event | 33 | 31 |
| People viewing onboarding welcome | 22 | 20 |
| People completing onboarding | 18 | 18 |
| People starting workouts | 18 | 15 |
| People logging a workout's first set | 9 | 10 |
| People completing a workout with logged sets | 6 | 8 |
| Completed workouts with logged sets | 16 | 15 |
| People starting templates | 2 | 3 |
| People viewing a paywall | 0 | 1 |

These are independently counted weekly activity metrics, not a conversion funnel. Unique weekly users come from native trends period aggregates, not the sum of daily users.

[Current-week query](https://eu.posthog.com/project/180066/insights/new#q=%7B%22kind%22%3A%22InsightVizNode%22%2C%22source%22%3A%7B%22dateRange%22%3A%7B%22date_from%22%3A%222026-09-19%22%2C%22date_to%22%3A%222026-09-25%22%7D%2C%22interval%22%3A%22day%22%2C%22kind%22%3A%22TrendsQuery%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22internal_team%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22person%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_emulator%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_testflight%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%5D%2C%22series%22%3A%5B%7B%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%2C%22name%22%3A%22Active%20users%22%7D%2C%7B%22event%22%3A%22onboarding%20step%20viewed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22step%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22welcome%22%5D%7D%5D%7D%2C%7B%22event%22%3A%22onboarding%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%7D%2C%7B%22event%22%3A%22workout%20started%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%7D%2C%7B%22event%22%3A%22first%20set%20logged%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%7D%2C%7B%22event%22%3A%22workout%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%221%22%2C%222-3%22%2C%224-6%22%2C%227-10%22%2C%2211%2B%22%5D%7D%5D%7D%2C%7B%22event%22%3A%22template%20started%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%7D%2C%7B%22event%22%3A%22paywall%20shown%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%7D%2C%7B%22event%22%3A%22workout%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22total%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%221%22%2C%222-3%22%2C%224-6%22%2C%227-10%22%2C%2211%2B%22%5D%7D%5D%7D%5D%2C%22trendsFilter%22%3A%7B%22aggregationAxisFormat%22%3A%22numeric%22%2C%22display%22%3A%22ActionsTable%22%2C%22metricColorByDirection%22%3Afalse%2C%22metricShowChange%22%3Atrue%2C%22metricSummary%22%3A%22total%22%2C%22showAlertThresholdLines%22%3Afalse%2C%22showLabelsOnSeries%22%3Afalse%2C%22showLegend%22%3Afalse%2C%22showMultipleYAxes%22%3Afalse%2C%22showPercentStackView%22%3Afalse%2C%22showValuesOnSeries%22%3Afalse%2C%22smoothingIntervals%22%3A1%2C%22yAxisScaleType%22%3A%22linear%22%7D%7D%7D) · [Previous-week query](https://eu.posthog.com/project/180066/insights/new#q=%7B%22kind%22%3A%22InsightVizNode%22%2C%22source%22%3A%7B%22dateRange%22%3A%7B%22date_from%22%3A%222026-09-12%22%2C%22date_to%22%3A%222026-09-18%22%7D%2C%22interval%22%3A%22day%22%2C%22kind%22%3A%22TrendsQuery%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22internal_team%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22person%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_emulator%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_testflight%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%5D%2C%22series%22%3A%5B%7B%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%2C%22name%22%3A%22Active%20users%22%7D%2C%7B%22event%22%3A%22onboarding%20step%20viewed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22step%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22welcome%22%5D%7D%5D%7D%2C%7B%22event%22%3A%22onboarding%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%7D%2C%7B%22event%22%3A%22workout%20started%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%7D%2C%7B%22event%22%3A%22first%20set%20logged%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%7D%2C%7B%22event%22%3A%22workout%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%221%22%2C%222-3%22%2C%224-6%22%2C%227-10%22%2C%2211%2B%22%5D%7D%5D%7D%2C%7B%22event%22%3A%22template%20started%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%7D%2C%7B%22event%22%3A%22paywall%20shown%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22dau%22%7D%2C%7B%22event%22%3A%22workout%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22total%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%221%22%2C%222-3%22%2C%224-6%22%2C%227-10%22%2C%2211%2B%22%5D%7D%5D%7D%5D%2C%22trendsFilter%22%3A%7B%22aggregationAxisFormat%22%3A%22numeric%22%2C%22display%22%3A%22ActionsTable%22%2C%22metricColorByDirection%22%3Afalse%2C%22metricShowChange%22%3Atrue%2C%22metricSummary%22%3A%22total%22%2C%22showAlertThresholdLines%22%3Afalse%2C%22showLabelsOnSeries%22%3Afalse%2C%22showLegend%22%3Afalse%2C%22showMultipleYAxes%22%3Afalse%2C%22showPercentStackView%22%3Afalse%2C%22showValuesOnSeries%22%3Afalse%2C%22smoothingIntervals%22%3A1%2C%22yAxisScaleType%22%3A%22linear%22%7D%7D%7D)

## 1. Selected programs still are not becoming template workouts

Among the 20 first-time welcome entrants during 19–25 September:

- 16 selected a program.
- Eight of those 16 subsequently started workouts.
- All eight used only the empty-workout source.
- None of the 16 recorded a template start.

This repeats the specific pattern found in the [19 September audit](posthog-funnel-audit-2026-09-19.md). It supports investigating how users find and launch the program they selected. It does not establish whether template creation failed or whether choosing an empty workout was intentional.

The native ordered new-user funnel, with observations capped at the week end, was:

| Step | New entrants reaching step |
|---|---:|
| First-ever onboarding welcome | 20 |
| Onboarding completed | 18 |
| Workout started | 9 |
| First set logged | 5 |
| Workout completed with logged sets | 2 |

Half of the onboarding completers had not started a workout by the cutoff. Four of nine starters had no first-set event. Two of 20 entrants had completed a workout so far. **This is not a mature seven-day conversion rate:** recent entrants still need follow-up.

The equivalent previous-week observation was 21 → 17 → 12 → 4 → 2. Its welcome count is 21 rather than the table's 22 because the funnel requires a first-ever onboarding event. These small, incompletely followed cohorts do not establish a release improvement or regression.

[Current activation query](https://eu.posthog.com/project/180066/insights/new#q=%7B%22kind%22%3A%22InsightVizNode%22%2C%22source%22%3A%7B%22dateRange%22%3A%7B%22date_from%22%3A%222026-09-19%22%2C%22date_to%22%3A%222026-09-25%22%7D%2C%22funnelsFilter%22%3A%7B%22breakdownAttributionType%22%3A%22first_touch%22%2C%22exclusions%22%3A%5B%5D%2C%22funnelAggregateByHogQL%22%3Anull%2C%22funnelOrderType%22%3A%22ordered%22%2C%22funnelStepReference%22%3A%22total%22%2C%22funnelVizType%22%3A%22steps%22%2C%22funnelWindowInterval%22%3A7%2C%22funnelWindowIntervalUnit%22%3A%22day%22%2C%22layout%22%3A%22vertical%22%7D%2C%22kind%22%3A%22FunnelsQuery%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22internal_team%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22person%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_emulator%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_testflight%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22timestamp%20%3C%20toDateTime('2026-09-26%2000%3A00%3A00'%2C%20'Europe%2FCopenhagen')%22%2C%22type%22%3A%22hogql%22%7D%5D%2C%22series%22%3A%5B%7B%22event%22%3A%22onboarding%20step%20viewed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22first_time_for_user%22%2C%22optionalInFunnel%22%3Afalse%2C%22properties%22%3A%5B%7B%22key%22%3A%22step%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22welcome%22%5D%7D%5D%7D%2C%7B%22event%22%3A%22onboarding%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22workout%20started%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22first%20set%20logged%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22workout%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%221%22%2C%222-3%22%2C%224-6%22%2C%227-10%22%2C%2211%2B%22%5D%7D%5D%7D%5D%7D%7D) · [Previous activation query](https://eu.posthog.com/project/180066/insights/new#q=%7B%22kind%22%3A%22InsightVizNode%22%2C%22source%22%3A%7B%22dateRange%22%3A%7B%22date_from%22%3A%222026-09-12%22%2C%22date_to%22%3A%222026-09-18%22%7D%2C%22funnelsFilter%22%3A%7B%22breakdownAttributionType%22%3A%22first_touch%22%2C%22exclusions%22%3A%5B%5D%2C%22funnelAggregateByHogQL%22%3Anull%2C%22funnelOrderType%22%3A%22ordered%22%2C%22funnelStepReference%22%3A%22total%22%2C%22funnelVizType%22%3A%22steps%22%2C%22funnelWindowInterval%22%3A7%2C%22funnelWindowIntervalUnit%22%3A%22day%22%2C%22layout%22%3A%22vertical%22%7D%2C%22kind%22%3A%22FunnelsQuery%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22internal_team%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22person%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_emulator%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_testflight%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22timestamp%20%3C%20toDateTime('2026-09-19%2000%3A00%3A00'%2C%20'Europe%2FCopenhagen')%22%2C%22type%22%3A%22hogql%22%7D%5D%2C%22series%22%3A%5B%7B%22event%22%3A%22onboarding%20step%20viewed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22first_time_for_user%22%2C%22optionalInFunnel%22%3Afalse%2C%22properties%22%3A%5B%7B%22key%22%3A%22step%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22welcome%22%5D%7D%5D%7D%2C%7B%22event%22%3A%22onboarding%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22workout%20started%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22first%20set%20logged%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22workout%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%221%22%2C%222-3%22%2C%224-6%22%2C%227-10%22%2C%2211%2B%22%5D%7D%5D%7D%5D%7D%7D)

**Priority:** inspect the first-use path from program selection to launching a prefilled session, and then recording its first set. The event pattern provides a concrete hypothesis to validate.

## 2. A small but encouraging repeat-training signal

Eight people completed workouts with logged sets, compared with six the previous week. Total completions were nearly unchanged: 15 versus 16.

- All 15 current-week completions reported at least seven sets; 14 reported 11 or more.
- One person whose first recorded nonempty completion was on 19 September completed five workouts during the week.
- Three people completed at least two workouts.
- Four of the six previous-week completers also completed a workout this week.
- Three people had their first-ever recorded nonempty completion this week. This population differs from the first-welcome funnel; older installations can complete their first workout now.

The four-of-six figure is overlap between calendar windows, not formal first-workout retention. Five of the 15 completions came from one person, so activity remains concentrated. These are promising individual behaviors, not evidence of broad sustained growth.

## 3. Very little exposure to the purchase decision

One person saw the paywall twice, both times through Settings. No purchase events were present in the complete unfiltered 14-day event inventory. There were no recorded workout-limit paywall exposures in the current week.

Observed free-workout completion events showed remaining allowances from three to nine. This does not establish every free user's current balance.

There is too little checkout exposure to diagnose pricing or purchase conversion. The observed loss is earlier in the journey.

## 4. Acquisition is still predominantly Apple Ads

This week had 18 attribution-resolved identities, all marked Apple Search Ads first downloads. The previous week had 17 Apple Ads first-download identities and four organic-category identities.

This describes attribution events, not all App Store downloads, ad efficiency, or verified new humans. Spend data were not available in this review, so no acquisition-cost conclusion is warranted.

## 5. No recorded exception spike

The unfiltered event inventory contained no exception events in either week. Daily activity continued throughout both windows; current-week daily active counts ranged from five to ten.

This means no exceptions were recorded, not proof that the app had no crashes or errors.

## Method and limits

- Excluded events marked person `internal_team=true`, event `$is_testflight=true`, or event `$is_emulator=true`; unknown flags were retained.
- Project automatic test filters are empty and disabled. Unmarked friends can remain in the data.
- Person-on-events is enabled, so later person-property changes need not apply to earlier events.
- Analytics persons are anonymous installation identities. Reinstalls and multiple devices may count separately; collection is optional.
- Meaningful completion requires a known nonzero `set_count_bucket`: 1, 2–3, 4–6, 7–10, or 11+.
- `first set logged` fires once per workout, not once per person's lifetime.
- Completion events lack workout IDs for independent exact deduplication.
- Native trends and funnels were used for their standard metrics. SQL was used for cross-event audits, historical dates, and calendar-window overlap.
- No sampling setting was requested; returned results exposed no sampling factor.
- No app code, pricing, campaigns, saved insights, flags, or PostHog settings were changed.

The [companion JSON](posthog-weekly-review-2026-09-26.json) contains the queries and returned aggregate evidence. See [PostHog aggregation definitions](https://posthog.com/docs/product-analytics/trends/aggregations) for period totals versus daily counts.

