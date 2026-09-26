# Repster growth funnel audit — 19 September 2026

Read-only analysis of live PostHog data in Repster's Default project (180066), using Europe/Copenhagen time. No app code, pricing, flags, or saved dashboards were changed.

## Recommendation

Prioritize helping a new user complete their first real workout. The strongest specific hypothesis is the handoff between selecting a ready-made program in onboarding and starting one of its saved routines. The data do not yet justify attributing low revenue primarily to price or committing to a freemium redesign.

## 1. Activation

Native PostHog ordered funnel, unique analytics persons, seven-day conversion window:

welcome → onboarding completed → workout started → first set logged → workout completed with a nonzero set-count bucket.

The first step uses first-ever onboarding-event occurrence filtered to welcome. Versions are attributed at that first step. Internal-team, TestFlight, and emulator flags equal to true are excluded; unknown values remain.

| Step | v1.4 entrants | v1.5 entrants |
|---|---:|---:|
| Welcome | 58 | 29 |
| Completed onboarding | 51 | 25 |
| Started workout | 27 | 16 |
| Logged a first set | 11 | 6 |
| Completed nonempty workout | 8 | 2 |

Period: 10 August through the partial day of 19 September. These are observed onboarding arrivals, not all App Store downloads.

The v1.4 group has had sufficient follow-up: 8/58 (13.8%) reached a nonempty completed workout within seven days. Of the 27 who started, 11 logged a first set. This places a substantial loss before the purchase decision.

Most v1.5 entrants are recent. Only six had entered before 12 September; those six yielded six onboarding completions, two workout starts, and no first sets within seven days. This tiny mature group is insufficient to evaluate the release.

A separate validation kept observations through 19 September while limiting the first step to before 12 September. It reproduced the mature results, avoiding reliance on ambiguous endpoint behavior.

- [Current activation query](https://eu.posthog.com/project/180066/insights/new#q=%7B%22kind%22%3A%22InsightVizNode%22%2C%22source%22%3A%7B%22breakdownFilter%22%3A%7B%22breakdown%22%3A%22%24app_version%22%2C%22breakdown_limit%22%3A25%2C%22breakdown_type%22%3A%22event%22%7D%2C%22dateRange%22%3A%7B%22date_from%22%3A%222026-08-10%22%2C%22date_to%22%3A%222026-09-19%22%7D%2C%22funnelsFilter%22%3A%7B%22breakdownAttributionType%22%3A%22step%22%2C%22breakdownAttributionValue%22%3A0%2C%22exclusions%22%3A%5B%5D%2C%22funnelAggregateByHogQL%22%3Anull%2C%22funnelOrderType%22%3A%22ordered%22%2C%22funnelStepReference%22%3A%22total%22%2C%22funnelVizType%22%3A%22steps%22%2C%22funnelWindowInterval%22%3A7%2C%22funnelWindowIntervalUnit%22%3A%22day%22%2C%22layout%22%3A%22vertical%22%7D%2C%22kind%22%3A%22FunnelsQuery%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22internal_team%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22person%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_emulator%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_testflight%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%5D%2C%22series%22%3A%5B%7B%22event%22%3A%22onboarding%20step%20viewed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22first_time_for_user%22%2C%22optionalInFunnel%22%3Afalse%2C%22properties%22%3A%5B%7B%22key%22%3A%22step%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22welcome%22%5D%7D%5D%7D%2C%7B%22event%22%3A%22onboarding%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22workout%20started%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22first%20set%20logged%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22workout%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%220%22%5D%7D%5D%7D%5D%7D%7D)
- [Mature entry-window query](https://eu.posthog.com/project/180066/insights/new#q=%7B%22kind%22%3A%22InsightVizNode%22%2C%22source%22%3A%7B%22breakdownFilter%22%3A%7B%22breakdown%22%3A%22%24app_version%22%2C%22breakdown_limit%22%3A25%2C%22breakdown_type%22%3A%22event%22%7D%2C%22dateRange%22%3A%7B%22date_from%22%3A%222026-08-10%22%2C%22date_to%22%3A%222026-09-19%22%7D%2C%22funnelsFilter%22%3A%7B%22breakdownAttributionType%22%3A%22step%22%2C%22breakdownAttributionValue%22%3A0%2C%22exclusions%22%3A%5B%5D%2C%22funnelAggregateByHogQL%22%3Anull%2C%22funnelOrderType%22%3A%22ordered%22%2C%22funnelStepReference%22%3A%22total%22%2C%22funnelVizType%22%3A%22steps%22%2C%22funnelWindowInterval%22%3A7%2C%22funnelWindowIntervalUnit%22%3A%22day%22%2C%22layout%22%3A%22vertical%22%7D%2C%22kind%22%3A%22FunnelsQuery%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22internal_team%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22person%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_emulator%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_testflight%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%5D%2C%22series%22%3A%5B%7B%22event%22%3A%22onboarding%20step%20viewed%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22first_time_for_user%22%2C%22optionalInFunnel%22%3Afalse%2C%22properties%22%3A%5B%7B%22key%22%3A%22step%22%2C%22operator%22%3A%22exact%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22welcome%22%5D%7D%2C%7B%22key%22%3A%22timestamp%20%3C%20toDateTime('2026-09-12%2000%3A00%3A00'%2C%20'Europe%2FCopenhagen')%22%2C%22type%22%3A%22hogql%22%7D%5D%7D%2C%7B%22event%22%3A%22onboarding%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22workout%20started%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22first%20set%20logged%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22workout%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%220%22%5D%7D%5D%7D%5D%7D%7D)

These are query links, not newly saved insights.

## 2. Selected programs are not reaching the workout

A cross-event record audit aligned to the v1.5 first-onboarding cohort found:

- 29 entrants.
- 21 selected a ready-made program.
- 13 of those 21 subsequently had workout starts recorded.
- Only one of the 21 had a Templates screen view recorded.
- None of the 21 had a template-start event recorded.
- Across all 29 entrants, 16 started a workout and 10 had no first-set event by the audit.
- Fifteen of the 16 starters used only the empty-workout source across observed starts; one later used another source.

These are overlapping activity counts, not a separate native conversion funnel. They establish recorded behavior, not why it occurred.

Code inspection supports a plausible explanation:

1. Onboarding materializes the selected program into templates in `OnboardingViewModel.completeOnboarding()`.
2. `OnboardingContainerView` calls a parameterless `onComplete()`; the saved-program result is not used there to launch or select a routine.
3. Home's Start Workout action opens `StartWorkoutSheet`.
4. That sheet puts a highlighted **Empty Workout** first. **Use Template** is lower in the sheet.
5. Template launches explicitly emit `source = template` and `template started`, so the observed pattern is not explained by the current template path simply labeling everything empty.

Relevant source:

- [Program creation](/Users/nikolettkiraly/Downloads/NewWorkoutProject/Repster/Features/Onboarding/ViewModels/OnboardingViewModel.swift:174)
- [Onboarding completion handoff](/Users/nikolettkiraly/Downloads/NewWorkoutProject/Repster/Features/Onboarding/Views/OnboardingContainerView.swift:71)
- [Home start action](/Users/nikolettkiraly/Downloads/NewWorkoutProject/Repster/Features/Home/Views/HomeView.swift:241)
- [Start choices](/Users/nikolettkiraly/Downloads/NewWorkoutProject/Repster/Features/Home/Views/StartWorkoutSheet.swift:40)
- [Template start instrumentation](/Users/nikolettkiraly/Downloads/NewWorkoutProject/Repster/Features/Templates/Views/TemplateFlowView.swift:588)

**First product change to scope:** after choosing a program, show its actual first session prominently on Home, with an action such as “Start Push A” that opens the prefilled workout. Then make the action for recording the first set easy to discover.

This is a hypothesis to validate with a short usability observation or replay inspection. No recordings were watched in this audit. Choosing an empty workout may sometimes be intentional; users may be browsing outside the gym. Template-materialization failures are another possibility that this aggregate audit does not rule out.

## 3. Returning to train

Native first-ever retention on nonempty `workout completed`, returning on that same event, using weekly 24-hour windows and noncumulative retention:

| First-workout cohort week | People | Returned in week 1 |
|---|---:|---:|
| 10 August | 6 | 1 |
| 17 August | 7 | 3 |
| 24 August | 6 | 1 |
| Combined mature cohorts | 19 | 5 |

Five of 19 (26.3%) completed another nonempty workout in the next seven-day retention period. This is a small sample and could contain friends whose granted access is not marked. It is not daily app-open retention, and it is not the same population as the welcome funnel: earlier installs can finish their first workout during these weeks.

Later cohorts were not used for this summary because their follow-up is incomplete.

- [Workout retention query](https://eu.posthog.com/project/180066/insights/new#q=%7B%22kind%22%3A%22InsightVizNode%22%2C%22source%22%3A%7B%22dateRange%22%3A%7B%22date_from%22%3A%222026-08-10%22%2C%22date_to%22%3A%222026-09-19%22%7D%2C%22kind%22%3A%22RetentionQuery%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22internal_team%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22person%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_emulator%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_testflight%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%5D%2C%22retentionFilter%22%3A%7B%22aggregationPropertyType%22%3A%22event%22%2C%22aggregationType%22%3A%22count%22%2C%22cumulative%22%3Afalse%2C%22period%22%3A%22Week%22%2C%22retentionReference%22%3A%22total%22%2C%22retentionType%22%3A%22retention_first_ever_occurrence%22%2C%22returningEntity%22%3A%7B%22id%22%3A%22workout%20completed%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%220%22%5D%7D%5D%2C%22type%22%3A%22events%22%7D%2C%22targetEntity%22%3A%7B%22id%22%3A%22workout%20completed%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%220%22%5D%7D%5D%2C%22type%22%3A%22events%22%7D%2C%22timeWindowMode%22%3A%2224_hour_windows%22%2C%22totalIntervals%22%3A6%7D%7D%7D)
- [PostHog retention definitions](https://posthog.com/docs/product-analytics/retention)

## 4. Payment observations

For 10 August–19 September, a native seven-day ordered payment funnel recorded:

| Route | Unique paywall viewers | Purchase starts | Completion callbacks |
|---|---:|---:|---:|
| Workout-limit paywall | 18 | 3 | 3 |
| Voluntary Settings paywall | 1 | 0 | 0 |

All three completion callbacks were on v1.3 during 10–20 August. This period spans different free-workout limits. These are not three verified organic paying customers: the app does not send transaction amount, product, production/sandbox environment, or a grant marker. Reconcile with RevenueCat/App Store transactions before calculating paying customers or revenue.

`access_tier = subscribed` means an active entitlement and includes grants. `paywall dismissed` can fire after purchase and is not a reliable rejection event. Direct lifetime purchases from membership settings bypass the paywall and therefore fall outside this funnel.

Among observed v1.5 free-user nonempty completions, the remaining allowance ranged from nine down to six. These users have not supplied evidence about conversion after exhausting ten free workouts.

- [Payment query](https://eu.posthog.com/project/180066/insights/new#q=%7B%22kind%22%3A%22InsightVizNode%22%2C%22source%22%3A%7B%22breakdownFilter%22%3A%7B%22breakdown%22%3A%22source%22%2C%22breakdown_limit%22%3A25%2C%22breakdown_type%22%3A%22event%22%7D%2C%22dateRange%22%3A%7B%22date_from%22%3A%222026-08-10%22%2C%22date_to%22%3A%222026-09-19%22%7D%2C%22funnelsFilter%22%3A%7B%22breakdownAttributionType%22%3A%22first_touch%22%2C%22exclusions%22%3A%5B%5D%2C%22funnelAggregateByHogQL%22%3Anull%2C%22funnelOrderType%22%3A%22ordered%22%2C%22funnelStepReference%22%3A%22total%22%2C%22funnelVizType%22%3A%22steps%22%2C%22funnelWindowInterval%22%3A7%2C%22funnelWindowIntervalUnit%22%3A%22day%22%2C%22layout%22%3A%22vertical%22%7D%2C%22kind%22%3A%22FunnelsQuery%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22internal_team%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22person%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_emulator%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_testflight%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%5D%2C%22series%22%3A%5B%7B%22event%22%3A%22paywall%20shown%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22purchase%20started%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22purchase%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%5D%7D%7D)

The annual/lifetime price spacing remains worth reviewing, but this dataset does not establish the optimum price. A permanent free core would change the later purchase decision without automatically resolving the earlier logging drop-off.

## 5. Acquisition

Attribution events during 10 August–19 September, with the same marked-test exclusions, covered:

- 89 Apple Search Ads first-download identities.
- Two Apple Search Ads redownload identities.
- 12 identities categorized as organic with unknown conversion type.

These are attribution-resolved identities, not a complete install census. Some existing installations receive attribution when upgrading. “Organic” means not attributed to the app's Apple Ads campaigns; it does not distinguish social links, referrals, App Store search, or friends. It should not be presented as 12 independently acquired customers.

A separate native attribution-to-workout funnel for entries through 11 September yielded 72 paid-attributed identities → 33 starts → 16 first sets → 13 nonempty completions, versus eight organic-category identities → five → five → five. The latter is too small and too potentially mixed with friends to claim an organic acquisition advantage; the former also includes attribution types, not only first downloads.

[Attribution-to-workout query](https://eu.posthog.com/project/180066/insights/new#q=%7B%22kind%22%3A%22InsightVizNode%22%2C%22source%22%3A%7B%22breakdownFilter%22%3A%7B%22breakdown%22%3A%22acquisition_channel%22%2C%22breakdown_limit%22%3A25%2C%22breakdown_type%22%3A%22event%22%7D%2C%22dateRange%22%3A%7B%22date_from%22%3A%222026-08-10%22%2C%22date_to%22%3A%222026-09-11%22%7D%2C%22funnelsFilter%22%3A%7B%22breakdownAttributionType%22%3A%22step%22%2C%22breakdownAttributionValue%22%3A0%2C%22exclusions%22%3A%5B%5D%2C%22funnelAggregateByHogQL%22%3Anull%2C%22funnelOrderType%22%3A%22ordered%22%2C%22funnelStepReference%22%3A%22total%22%2C%22funnelVizType%22%3A%22steps%22%2C%22funnelWindowInterval%22%3A7%2C%22funnelWindowIntervalUnit%22%3A%22day%22%2C%22layout%22%3A%22vertical%22%7D%2C%22kind%22%3A%22FunnelsQuery%22%2C%22properties%22%3A%5B%7B%22key%22%3A%22internal_team%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22person%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_emulator%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%2C%7B%22key%22%3A%22%24is_testflight%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%22true%22%5D%7D%5D%2C%22series%22%3A%5B%7B%22event%22%3A%22attribution%20resolved%22%2C%22kind%22%3A%22EventsNode%22%2C%22math%22%3A%22first_time_for_user%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22workout%20started%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22first%20set%20logged%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%7D%2C%7B%22event%22%3A%22workout%20completed%22%2C%22kind%22%3A%22EventsNode%22%2C%22optionalInFunnel%22%3Afalse%2C%22properties%22%3A%5B%7B%22key%22%3A%22set_count_bucket%22%2C%22operator%22%3A%22is_not%22%2C%22type%22%3A%22event%22%2C%22value%22%3A%5B%220%22%5D%7D%5D%7D%5D%7D%7D)

Next advertising analysis needs Apple Ads spend and search-term exports. Keyword IDs are captured on person properties when Apple supplies them, but early events may predate enrichment. Cost per completed first workout and per returning lifter would be more useful early measures than cost per install alone.

## 6. Measurement limits

- The user is unsure whether `internal_team` covers friends. This report excludes marked internal events, not a verified friends cohort.
- Project-wide automatic test-account filters are empty and disabled. Explicit filters were supplied in the audit.
- Person-on-events is enabled. A later `internal_team` or attribution update need not apply retrospectively to earlier events.
- Analytics collection is optional; missing events can reflect opt-out, app lifecycle, or instrumentation rather than abandonment.
- Identities are anonymous installations; reinstallations or different devices need not equal different humans.
- `first set logged` is emitted once per workout, not once per person's lifetime. The activation sequence handles that distinction.
- Empty workout completions exist and were excluded from meaningful completion/retention.
- Completion events contain no workout ID for independent exact deduplication.
- No query sampling option was requested; returned payloads did not expose a sampling factor.
- The code inspection refers to the local checkout, which has unrelated uncommitted work. The deployed binary was not independently inspected.
- No application, analytics configuration, campaign, or price changes were made.

## Suggested order

1. Verify the selected-program handoff with a few observed first-use sessions, then scope a direct start of the chosen session.
2. Check whether more new users log a first set and complete a workout.
3. Follow those people through their next workout; allow new cohorts time to mature.
4. Reconcile purchase callbacks with production transactions and distinguish granted access.
5. Review ad search terms and first-workout cost.
6. Test clearer App Store/social messaging in parallel with a small content schedule.
7. Decide price spacing and any free/premium split with evidence from users who actually reach those decisions.

The companion JSON stores the native queries, aggregate results, query links, and program-handoff SQL for reproducibility.

