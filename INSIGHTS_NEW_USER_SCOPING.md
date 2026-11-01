# Training Insights for new users — scoping

**Status:** option A BUILT 2026-10-22 (uncommitted, device pass outstanding). Option B
scoped in §8, not built. Written 2026-10-22. Builds on
`TRAINING_INSIGHTS_V2_DESIGN.md` (§3 surfaces, §8 cold start) and the Insights follow-up
in `SAMPLE_HISTORY_SCOPING.md`.

---

## 1. What the data says

PostHog, public builds (1.4 and 1.5), TestFlight and the developer's own account
excluded. The Home card is the **only** way into Insights (`HomeView.swift:177`), so
every `$screen` with `$screen_name = Insights` is a tap on that card.

**New users, first seen Aug 24 – Sep 30** (at least three weeks to build history):

| | People |
|---|---|
| New users | 84 |
| Finished at least 1 workout | 17 |
| Finished at least 3 workouts | 5 |
| Trained across a span of 21+ days | **2** |
| Opened Insights | **23** |
| …first open on their first or second day | 20 |
| …first open before finishing any workout | 18 |
| Opened Insights more than once | 6 |

More new users opened Insights (23) than finished a workout (17). The tap is
curiosity on day one, usually before anything has been logged.

**All users, Aug 24 – Oct 21:** 54 of 65 Insights opens (83%) had `finding_count = 0`
and `has_baseline = false`. Every open by anyone with fewer than 10 workouts was in that
state. Nobody expanded, rated or snoozed a finding in 60 days. One person expanded the
muscle panel.

n is small (about 40 installs per two weeks). Read these as counts, not rates.

---

## 2. What a new user actually sees

| Stage | Home card | Insights screen |
|---|---|---|
| **0 workouts** | "Training status / Builds as you log workouts", dashed icon (`TrainingInsightsHookView.swift:85-93`) | One card: "No sets logged yet / Your training status builds as you log workouts / 0 SETS IN THE LAST 7 DAYS" (`TrainingStatusCardView.swift:61-74, 127`). Nothing else renders. |
| **Workouts 1+, first ~4 weeks** | "Your first weeks / N sets this week" | "Your first weeks / Building your usual week — comparisons start in a few weeks / N SETS", plus the muscle panel with this week's counts and no comparison. No findings section. |
| **28 days after the first logged set** | Band headline + bars | Usual-week comparison appears. `minimumBaselineWeeks = 3.0` (`InsightsService.swift:631`) is counted back from the start of the trailing 7-day window, so it lands on day 28, not day 21. `consistency` can fire through the relaxed pass at about the same time (3 complete weeks). |
| **~6 weeks** | same | `strengthTrend` (42-day span), `volumeRamp` (6 weeks) and the rest of the catalog become reachable. |

For fresh installs, Insights is the **first** section on Home
(`HomeSectionConfig.swift:91`), so it is the most prominent thing a new user sees.

---

## 3. The problem

Insights v2 was designed around someone with three or more weeks of history. Its
cold-start rules (v2 §8) make the early screen calm and honest, but almost empty. Only
2 of 84 new users ever reached the point where it fills in.

So the screen fails exactly when it matters most. A new user taps the top card on Home
to find out what the app will do for them. The answer they get is one number, often
zero, and a promise about "a few weeks". Most of them never come back to the screen,
and most never log a second workout.

A related gap: welcome bullet 2, "Rest and fatigue tracked per muscle", has no
user-facing surface anywhere. Per-muscle fatigue appears only in the admin view
(`FatigueLearningAdminView.swift`).

---

## 4. Options, smallest first

### A. Zero-workout state says what the screen is for — BUILT 2026-10-22

**As built** (user approved reopening v2 §8 for this state):

- `TrainingStatusCardView`: when `hasData == false` the card reads "What you'll see here /
  Built from your own workouts as you log them", followed by three rows:
  - AFTER YOUR FIRST WORKOUT: Your sets for the week, split by muscle
  - AFTER ABOUT FOUR WEEKS: How each week compares with your usual
  - ONCE A PATTERN HOLDS: Findings on your strength, consistency and volume
- `TrainingInsightsHookView`: the Home subtitle for that state is "See what your workouts
  will show". A `nil` status (loading or failed fetch) keeps "Builds as you log workouts",
  so existing users never flash the new-user line.
- The copy describes only what the screen renders **today**. The draft below mentioned
  an estimated 1RM per lift, which the screen doesn't show yet. That line is added when
  B ships (§8.6).
- `hasData` is false only for someone who has never ticked a set
  (`earliestLoggedSetDate`). Lapsed users keep their history and never see this state.
- No "Start a workout" button. No analytics change.

**Original proposal:**

**Scope:** view-only. The 0-workout state of `TrainingStatusCardView` and the Home card
subtitle. **Reversible:** yes. **Reaches:** 18 of the 23 new users who opened Insights.

Replace "No sets logged yet" with a short description of what the screen will show and
when. Tie it to the welcome bullets:

> After your first workout: sets per muscle and an estimated 1RM for each lift.
> From about week three: how each week compares with your usual.

A "Start a workout" button on this state is an optional extra.

**Reopens a recorded decision.** V2 §8 says copy should state what the screen *is*
showing, never what it can't, with "no progress bars toward unlocking". This option
would be a preview, not "not enough data", but it does describe the future. It needs an
explicit yes.

**What it won't do:** it gives nobody a reason to come back. It only stops the first
tap from landing on an empty screen.

### B. Real content from workout 1 (the actual fix) — build scope in §8

Things the data can already say without a baseline. All of them describe; none of them
prescribe.

- **B1. "Since you started" per lift.** First vs latest estimated 1RM (or top set) for
  every exercise done at least twice. Works from the second session of a lift, often in
  week one. It is the early version of `strengthTrend`, which needs 42 days. It makes
  welcome bullet 1 visible. It overlaps the per-exercise charts in the Charts tab, but
  Charts needs the user to go and pick an exercise.
- **B2. Starting estimated 1RM after workout 1.** A small table: "Your starting marks:
  Bench 62 kg, Squat 80 kg…". Delivers bullet 1 on day one. B1 is this table's
  workout-2 form.
- **B3. This week vs last week from week 2.** Show last week beside this week, with no
  band and no "usual". It fills the two-week gap before the baseline exists. Week-to-week
  numbers are noisy, which is why this is the weakest of the three.

The Home card should carry the best of these for new users, for example "Bench +5 kg
since your first session". It is the most-seen surface, and a real number there is the
biggest lever.

**Scope:** medium. New status or section computation in `InsightsService` (no new
`InsightRule`; this is status-layer arithmetic, not a gated finding), new views, tests.
**Reversible:** yes. Every piece hides when the user has history.

### C. Sample Insights screen

Already scoped as the follow-up in `SAMPLE_HISTORY_SCOPING.md` (§ "Follow-up: Training
Insights", §6.3 UserDefaults hazard). It depends on sample-history v1, which is not
built. It is the largest option, and it shows what the screen *could* look like rather
than giving the user something about themselves. Leave it as it is.

### D. Per-muscle fatigue surface (welcome bullet 2)

Not recommended now. The fatigue model never measures real rest (rest is nil unless the
timer runs to zero) and skips sets without RIR. `REPSTER_COACH_SCOPING.md` already rules
that nothing built on that data can be a headline surface. Parked.

### Not recommended: hiding the card until the first workout

It is the most-tapped door for new users. The problem is what's behind it, not the door
itself.

---

## 5. Measurement

- **Already possible:** count Insights opens per new user, and their `finding_count` /
  `has_baseline`, by workout count at the time (reconstructed in SQL, as in §1).
- **Add with any option:** a `workout_count_bucket` (or `stage`) property on the Insights
  `$screen` event, so cold-start opens can be counted without reconstructing them. The
  known gap still stands: no event records which rules were *shown*.
- **Signal to watch:** new users opening Insights two or more times in their first 14
  days (today 6 of 84). For A specifically: whether day-one openers start a workout
  afterwards. Expect single-digit counts per fortnight; compare cohorts by count.

---

## 6. Recommendation

1. **A — done** (2026-10-22, see §4A).
2. **B1 + B2 next**, scoped in §8. They are the only options that give a new user a reason
   to come back, and they make welcome bullet 1 visible. B3 (week vs last week) is dropped
   from this round: it is noisy, and B1/B2 already fill the first four weeks.
3. **C stays parked** behind sample-history v1. **D stays parked** behind the
   fatigue-model fixes.

---

## 7. Open questions

- **Q1.** ~~Reopen v2 §8 for the zero-workout state?~~ **Yes** (2026-10-22). A is built.
- **Q2.** Should the Home card carry the "since you started" number? Recommended yes, in
  §8.4. Needs your call.
- **Q3.** Is B in 1.6 or the release after?
- **Q4.** ~~What counts as "the same lift"?~~ Recommended in §8.3: exact exercise id,
  same as Charts. Revisit only if users complain.
- **Q5.** Is six weeks the right point to retire the section (§8.2)? Recommended because
  that is when `strengthTrend` can take over.

---

## 8. Option B — build scope (not built)

### 8.1 What the user sees

A new section on the Insights screen, **"Estimated 1RM since you started"**, for every
lift with a weighted working set:

| Lift state | Row |
|---|---|
| Trained once | `Bench Press   62.5 kg` · "1 session" |
| Trained 2+ times, best is higher than the first | `Bench Press   62.5 → 67.5 kg   +5 kg` · "3 sessions" |
| Trained 2+ times, nothing higher yet | `Squat   80 kg` · "2 sessions" |

- One footnote line, in the style of the status card's "usual week" line: *"Best
  estimated 1RM per session, from your working sets."*
- Rows are ordered lifts-with-a-gain first (largest gain first), then everything else by
  most recently trained. Six rows when collapsed, with "Show all N lifts" after that,
  matching `MuscleVolumePanelView.collapsedRowCount = 6`.
- No colours for up or down, and no arrows other than the first → best one. This follows
  the v2 rule that numbers state, they don't grade.

**Why "first → best" and not "first → latest":** a new user's second session is often
lighter, or in a different rep range. First → latest would show a drop in week one, and
it would mostly be noise. First → best never goes down, and it says only what is true:
"your best so far". Charts still has the full series.

### 8.2 Who sees it, and when it goes away

- **Shows** when `hasData` is true and the first logged set is **less than 42 days old**.
- **Retires at 42 days**, which is `StrengthTrendInsightRule.minimumSpanDays`. That is the point
  where the real strength-trend finding can fire, so the user moves from a "since you
  started" table to a proper trend with no gap between them.
- Uses the `historyStart` that `trainingStatus(from:historyStart:)` already receives
  (`earliestLoggedSetDate`). So:
  - Imported histories are past 42 days and never see the section, which is correct.
  - Lapsed users with old history never see it.
- The status context is windowed to 9 weeks (`statusWindowStart`), which more than
  covers 42 days. **No extra fetch is needed.**

### 8.3 Computation

- **Where:** `InsightsService.trainingStatus(from:historyStart:)`, next to the muscle
  rows. It is status-layer arithmetic, not an `InsightRule`. It never persists, never
  ranks against findings, and never touches the refire state in `UserDefaults`.
- **Input:** `context.eligibleWorkingSets`, so warm-ups, excluded workouts and excluded
  exercises are already filtered out the same way every rule filters them. Only sets with
  `e1RM > 0` count.
- **Per session:** reuse `StrengthTrendInsightRule.dailyBestE1RM(_:since:)`
  (`InsightRules+Progress.swift:115`): the best e1RM per calendar day per exercise. First
  = earliest day's best. Best = max over all days. Sessions = number of days.
- **Same lift = same `exerciseId`** (Q4). This matches Charts, PRs and `strengthTrend`. A
  user who swaps barbell for dumbbell bench gets two rows, as they would everywhere else.
- **e1RM is the stored value**, with no rep cap and no recompute. That is the same number
  Charts and exercise detail show, so the screens never disagree. Known limitation,
  inherited app-wide: Epley over high reps runs high.
- **Units:** values stay in kg internally. The view formats them with
  `UnitConversion.formatWeightLabel(_:unitPreference:)`, and the delta gets a "+"
  prefix. Rounding the gain to the user's increment avoids a "+2.4 kg" that looks like an
  error.
- **Model:** a new `StartedLift` struct (exerciseId, name, firstE1RM, bestE1RM, sessions,
  lastDate), with `var startedLifts: [StartedLift] = []` on `TrainingStatus`. A `var`
  with a default keeps all 10 existing `TrainingStatus(...)` call sites compiling.
  `TrainingStatus` is `Equatable`, so the new struct must be too.

### 8.4 Where it lives

**Insights screen:** directly under the status card, above the muscle panel. For a new
user it is the most personal thing on the screen, and it describes (it doesn't rank), so
it fits the v2 order: status describes, the panel ranks, findings interpret.

**Home card (Q2, recommended):** while the section is live and at least one lift has a
gain, the hook's subtitle becomes `Bench Press +5 kg since your first session`, using the
largest gain. Otherwise it stays as today ("N sets this week"). The headline is still
"Your first weeks".
- The subtitle has `lineLimit(1)` and `minimumScaleFactor(0.85)`. A long exercise name
  will truncate, so the name goes first and the number has to survive, e.g. by building
  the string as `name` + `" +5 kg"` and truncating the name only.
- This is the biggest lever in B: it is the most-seen surface, and a real personal number
  there is something the user can only get by logging.

### 8.5 Edge cases

| Case | Behaviour |
|---|---|
| Bodyweight exercise with a blank weight | `effectiveWeight` is nil, so there's no e1RM and no row. Correct, and consistent with Charts. |
| Cardio / distance / time exercises | No weighted reps, so no e1RM and no row. |
| Unilateral per-side sets | e1RM already comes from the post-derivation reps (`SetService.swift:155-165`). Same number as Charts. |
| Formula changed in Settings between sessions | First and best may come from different formulas. Rare; accepted, same as Charts. |
| Every set in a workout excluded from PRs/progression | Filtered by `eligibleWorkingSets`, so it doesn't count. |
| Exercise deleted | Not in `exercisesById`, so the row is skipped. |
| Two workouts on one calendar day | One session (daily best). Same as `strengthTrend`. |
| Sample history (when built) | Unaffected. Sample Insights reads through its own wrapper service (`SAMPLE_HISTORY_SCOPING.md` §6.3). |

### 8.6 Copy changes elsewhere

- Option A's preview row becomes **"AFTER YOUR FIRST WORKOUT — Your sets for the week by
  muscle, and an estimated 1RM for each lift"**. It becomes true the day B ships, and not
  before (see the comment on `previewStages` in `TrainingStatusCardView.swift`).
- The cold-start subtitle "Building your usual week — comparisons start in a few weeks"
  stays as it is.

### 8.7 Analytics

- Add `stage` to the Insights `$screen` event (`insightsViewed`), with values `no_data`,
  `first_weeks` and `baseline`. It lets PostHog count opens per state directly instead of
  reconstructing it in SQL, and it's the property the success metric below needs.
- Add `started_lift_count` (bucketed, like the other counts) when the section shows.
- **Never send exercise names or weights.** This is the existing rule at the top of the
  Insights analytics block.
- Update `POSTHOG_ANALYTICS_GUIDE.md` §Training Insights and `AnalyticsServiceTests`
  (lines 159, 175). Both files currently have **your uncommitted changes**. Commit those
  first, so the B diff stays separable.

**Success signal:** new users opening Insights on 2+ different days in their first 14
days. Baseline: 6 of 84 (Aug 24 – Sep 30 cohort). About 40 installs a fortnight, so
compare cohort counts, not rates.

### 8.8 Files and effort

| File | Change |
|---|---|
| `Core/Services/Protocols/InsightsServiceProtocol.swift` | `StartedLift`, the `startedLifts` field |
| `Core/Services/InsightsService.swift` | Compute in `trainingStatus(from:historyStart:)`; a 42-day constant |
| `Features/Insights/Views/` (new view) | The section. **A new file must be hand-registered in `project.pbxproj`**, which currently has your uncommitted changes. Alternative: put the view in `TrainingStatusCardView.swift` and avoid touching the project file. |
| `Features/Insights/Views/InsightsView.swift` | Place the section |
| `Features/Home/Views/TrainingInsightsHookView.swift` | Subtitle (§8.4) |
| `Features/Insights/Views/TrainingStatusCardView.swift` | A's preview copy (§8.6) |
| `AnalyticsServiceProtocol.swift`, `InsightsView.swift`, guide, tests | §8.7 |

Medium effort: roughly one service function, one view, one subtitle change and the
analytics property. No migration, no persisted state, no new fetch. **Reversible:** every
piece hides itself once the user is past 42 days.

### 8.9 Tests (`InsightsServiceTests`, via `service.trainingStatus(referenceDate:)` like the existing status tests at :455-522)

1. No sets: `startedLifts` is empty.
2. One session: one row with first == best and sessions == 1.
3. Three sessions rising: first, best and gain are correct.
4. Second session lower than the first: best == first, and no negative values.
5. Warm-ups, an excluded workout and an excluded exercise don't count.
6. A set with nil e1RM (bodyweight) gives no row.
7. First set 42+ days old: empty, even with recent sets.
8. Two sets on one day: one session, the higher e1RM wins.
9. Ordering: lifts with a gain first, by size; then by most recently trained.
10. The Home subtitle picks the largest gain, and falls back when nothing has improved.
    Keep the selection in a static function so it can be tested without the view.
