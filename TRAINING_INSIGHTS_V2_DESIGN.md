# Training Insights — v2 design

Status: spec. Written 2026-08-08 against branch `NewMain`.

Supersedes the Insights portion of `INSIGHTS_FEATURE_DESIGN.md` (Phase 1, shipped
2026-06-11). That document stays valid as the record of what exists; this one
defines what replaces it.

---

## 1. Why v2

Phase 1 shipped a findings feed reachable from a Home teaser card. Two problems
in practice:

1. **It's usually empty.** The rules are deliberately strict, so most users most
   weeks see "Findings from your training data / Unlocks as you log workouts." A
   surface that is blank by design reads as broken, and people stop tapping it.
2. **Every rule is a diagnosis.** All five shipped rules tell the user what
   they're doing wrong — resting wrong, missing targets, neglecting a muscle,
   overdue for a PR, misjudging effort. Nobody opens an app weekly to be graded.

v2 fixes both by splitting the surface into two layers with different epistemic
status, and by rebalancing the rule catalog toward findings that can be neutral
or good news.

### The organising idea

- **Status** — arithmetic on the user's own data. Always renders, never gated,
  cannot be wrong. Describing.
- **Findings** — interpretation. Gated, occasional, allowed to say nothing.
  Prescribing.

Describing is safe; prescribing is not. So the status layer can be generous and
always-on while findings stay strict. It also means the screen always has
content, which is the actual fix for the empty-feed problem.

---

## 2. Decisions locked

| Decision | Resolution |
|---|---|
| Name | **Training Insights**. "Suggestions" is unavailable — `Smart Suggestions` already owns a Settings screen (`PrescriptionSettingsView.swift:29`) and the workout-screen wand. Two features with one name would contradict each other in public. |
| Placement | Compact hook on Home → full destination screen. Same shape as v1, better hook. |
| Monetization | **Free.** No entitlement check. Insights shipped free (there is no access check anywhere in `Features/Insights/`); gating it now would take something away from existing users. It is a retention feature, and retention is what the subscription sells. |
| Set definition | **Working sets**, called "sets" in UI. Not hard sets. `setType == .working` already excludes warmups, which is most of the value; filtering further on RIR ≤ 3 silently excludes users who don't log RIR and makes the headline number mean different things for different people. |
| Panel window | **Trailing 7 days**, not the calendar week. A calendar week compared to a weekly average shows every group down 80% on a Monday. |
| Muscle attribution | **Primary muscle only.** Half-credit for secondaries is more physiologically honest but produces fractional set counts that are hard to explain on a card that says "sets". |
| Notifications | **Out of scope.** Pre-launch notes flag notification permission being requested too early; nothing here reintroduces it. |

---

## 3. Surfaces

### 3.1 Home hook

Replaces `InsightsTeaserCardView` one-for-one. Same section slot, same height
band as `MonthlyStatsCardView` above it. Nothing else on Home moves; `This
Month` stays exactly where it is.

**Provisional design (variant B — "meter"):** state line, sets this week with
the 8-week average alongside, a meter with a baseline tick, and a findings-count
badge.

> **Open.** None of the three mocked hooks landed. All three reproduced the
> structure of the existing teaser (icon tile + two text lines + a bar), which is
> the component being replaced. Home's real visual language is numbers in cells —
> `MonthlyStatsCardView` uses three large figures on `bgSubtle` tiles. A
> figures-first hook in that grammar is the direction to explore. **The hook is
> one small view and does not block anything else in this spec.**

Non-negotiable regardless of visual direction: **the hook always has content.**
It renders the week's status whether or not any finding fired. The badge means
"there is also advice", never "this card finally has a reason to exist".

### 3.2 Destination screen

`InsightsView` rebuilt, same navigation route. Order, top to bottom:

1. **Status card** — state line, sets this trailing week vs. 8-week baseline, meter.
2. **Last 7 days by muscle** — the panel (§4).
3. **Findings** — 0–3 cards (§5).

Reading down, the claims get progressively stronger. That gradient is the design.

Empty findings renders one honest line — *"Nothing stands out this week /
Findings only appear when the pattern is strong enough to trust"* — not an icon
and an apology. The two sections above it still carry the screen.

---

## 4. Status layer

### 4.1 Windows

- **Current window:** trailing 7 days, ending now, inclusive.
- **Baseline window:** the 8 weeks *preceding* the current window (days 8–63).
  Excluded from its own comparison so the baseline isn't diluted by what it measures.
- **Baseline value:** mean 7-day total over that window, per group and in total.

### 4.2 Set eligibility

Same rules as the existing engine: `setType == .working`, `completed == true`,
`hasData`, workout `status == .completed`, and respecting
`excludesEntireWorkoutFromProgressionHistory` /
`excludedExerciseIdsForProgressionHistory`.

### 4.3 State line

Band on `currentTotal / baselineTotal`:

| Ratio | Copy |
|---|---|
| < 0.60 | Lighter week than your usual |
| 0.60 – 0.85 | A bit below your usual |
| 0.85 – 1.15 | Tracking normally |
| 1.15 – 1.40 | Busier week than your usual |
| > 1.40 | Well above your usual |
| no baseline | *see cold start, §8* |

### 4.4 Muscle panel

**Groups are derived from the user's own exercises**, not from a fixed enum.
Take distinct `ExerciseMuscleGroupCatalog.normalizedValue(exercise.primaryMuscle)`
across exercises with ≥1 eligible set in the last 63 days.

> ⚠️ **Do not use `ExerciseMuscleGroupCatalog.orderedValues(from:)`.** It filters
> to the ten `supportedEntries` and silently drops anything custom
> (`ExerciseMuscleGroupCatalog.swift:66`). `normalizedValue` passes unrecognised
> strings straight through, so users already have custom groups such as "glutes"
> or "calves" in their data, and `MuscleGroupColors` has a hash-based fallback
> palette that renders them correctly. Build the ordered list here instead.
>
> Note the same helper orders the Charts breakdown (`ChartDataService.swift:303`),
> so custom categories may already be dropped there. Out of scope, worth a ticket.

**Excluded groups:** `cardio` and `full body`. They're in the catalog but aren't
muscles; they distort the ranking and "you're neglecting full body" is meaningless.

**Sort: by baseline descending**, tiebreak current descending, then display name.
Sorting by current volume pushes the skipped group to the bottom — that group is
the entire reason to look at the panel.

**Collapsed:** top 6. **Expanded:** all, via `Show all N groups`.

**Row anatomy:**
- Display name via `ExerciseMuscleGroupCatalog.displayName(for:)`
- Bar fill: `current / maxBaselineAcrossGroups`
- Baseline tick: `baseline / maxBaselineAcrossGroups`
- Count (integer), and delta vs. baseline rounded to integer
- Bar colour: `MuscleGroupColors.color(for:)`

**Deltas are not coloured green/red.** That would assert more volume is better,
which isn't reliably true and directly contradicts the readiness rule warning
about accumulated fatigue. Deltas render in `textTertiary`. The single exception:
a group with a real baseline that got **zero** sets shows its delta in `danger` —
that one is factual.

---

## 5. Findings catalog

13 rules. Each conforms to the existing `InsightRule` protocol and lives in
`InsightRules.swift` (or a sibling file — see §10).

### Tier 1 — carry the feed

High coverage, renewable, fire in both directions.

| Rule ID | chartKind | Subject | Gate | Source |
|---|---|---|---|---|
| `strengthTrend` | series | exercise | ≥3 sessions with e1RM, span ≥42d, projected 8-week change ≥3% either direction | `ExerciseStats.estimated1RMTrendSlope` — already computed by `StatsService.computeE1RMTrendSlope` (`StatsService.swift:332`), daily-best linear regression over 60d |
| `consistency` | column | — | ≥3 weeks history; a run of ≥4 weeks at or above the user's median frequency, or a sustained drop | workout dates only |
| `droppedExercise` | timeline | exercise | ≥8 prior sessions, current gap ≥3× median cadence and ≥21 days | `ExerciseStats.lastPerformedDate` |
| `volumeRamp` | column | — | ≥6 weeks history, change ≥25% sustained ≥2 weeks, either direction | working sets per week |
| `deloadReadiness` | series (signed) | — | see §5.1 | `FatigueObservation`, per-set `e1RM`, `Workout.perceivedEffort` |

`strengthTrend` is the single biggest gap in v1 — it's what users most want to
know and can least see, and it's nearly free given the slope already exists.
`consistency` is the cold-start card: workout dates only, so 100% coverage from
about week three.

### Tier 2 — texture

| Rule ID | chartKind | Subject | Gate |
|---|---|---|---|
| `lateralAsymmetry` | comparison | exercise | ≥8 sessions with both sides logged, gap ≥8%, stable or widening |
| `relativeStrength` | comparison | exercise | bodyweight logged within 30d, e1RM crosses a new round bodyweight multiple |
| `repRangeDrift` | range | exercise | ≥15 working sets in each window, median rep shift ≥2 |
| `prPace` | timeline | — | replaces `prRhythm`; same `PerformanceRecord` data, allowed to fire positively |

`lateralAsymmetry` uses `leftReps` / `rightReps` / `leftRIR` / `rightRIR`, which
already exist on `WorkoutSet` — designed in v1, never built. `relativeStrength`
will be silent for most users (needs recent bodyweight) but is the best share-card
candidate in the set.

### Existing five — rebuilt

Same rules, same gates. Only `chartKind` and copy register change.

| Rule ID | chartKind | Change |
|---|---|---|
| `muscleBalance` | ranking | unchanged logic |
| `targetAdherence` | proportion | was three separate bars; it's parts of a whole, so one stacked bar with a key |
| `restSweetSpot` | comparison | unchanged logic. Caveat stands: `restDurationSeconds` is only captured when the timer runs to zero, so short rests are systematically under-sampled |
| `rirCalibration` | series (signed) | was eight unsigned bars, which discarded the sign — the sign *is* the finding. Needs a zero line |
| `prRhythm` | — | **retired**, replaced by `prPace` |

### 5.1 `deloadReadiness` in full

This is the rule where being wrong costs the most. Conservative gates and hedged
language are requirements, not polish.

**Fires only when all hold:**

1. ≥6 weeks of history and ≥12 completed sessions.
2. **Regression:** ≥3 exercises where session-best `e1RM` over the last 14 days
   is ≥3% below the prior 28 days.
3. **Corroboration** — at least one of:
   - median `FatigueObservation.normalizedError` shifted positive by ≥0.04 vs. the prior window; or
   - median `Workout.perceivedEffort` up ≥1 point, with ≥4 rated sessions in each window.
4. **Guard:** working-set count over the last 14 days is **not** below the prior
   baseline. Without this the rule detects a week off and calls it fatigue. This
   guard is the difference between a trustworthy rule and an embarrassing one.

**Refire interval: 21 days minimum** (§6.3).

**Copy register:** "Your sessions are landing under your usual output" and "a
lighter week often resets this". Never "take a deload week."

**Coverage note:** `FatigueObservation` only exists where Smart Suggestions
produced a prediction, so signal 3a is not universal. Signal 2 (session-best
e1RM, populated by `SetService.swift:59` for everyone) is the primary detector;
fatigue error is corroboration, not the other way round.

---

## 6. Curation

Changes to `InsightsService.runAnalysis` (`InsightsService.swift:140`).

### 6.1 Positive floor

If no finding clears its gate, emit the best available **progress-category**
finding (`strengthTrend`, `consistency`, `prPace`, `relativeStrength`) at a
lowered bar. It's describing, not prescribing — "your squat is up 6%" needs no
confidence interval to be safe to say.

Effect: once a user has ~3 weeks of data, the feed always has at least one card.

### 6.2 Tone cap

At most **2 diagnostic cards in a feed of 3**. Diagnostic = `muscleBalance`,
`targetAdherence`, `rirCalibration`, `deloadReadiness`, `droppedExercise`,
`lateralAsymmetry`, `volumeRamp` (when ramping down). The user is never shown an
all-criticism screen.

### 6.3 Refire intervals

`InsightRule` gains `minimumRefireInterval: TimeInterval?`. Today records are
deleted when a finding stops holding and only `snoozedUntil` (user-initiated)
survives — so a rule can reappear the moment it's re-detected. Track last-fired
per `(ruleId, subjectId)` and suppress within the interval.

`deloadReadiness`: 21 days. Others: nil unless testing shows churn.

---

## 7. Data model & engine changes

### 7.1 `InsightRecord.chartKind`

New non-optional `String` with a default of `"ranking"` so existing rows
lightweight-migrate. Seven kinds:

| Kind | Shape |
|---|---|
| `series` | something over time, possibly signed — line with emphasised endpoint, or bars around a zero line |
| `column` | discrete periods, current emphasised |
| `ranking` | ordered categories in subject colours |
| `proportion` | parts of a whole, one stacked bar with a key |
| `comparison` | two groups, or a value against a mark |
| `range` | an interval that moved — two segments on a shared axis |
| `timeline` | events and the gaps between them |

Existing `chartLabels` / `chartValues` stay as-is.

### 7.2 ✅ Analysis signature was date-blind

**Done (Phase 1).** Signature now carries the local start-of-day, so the pipeline
recomputes at most once per day even with no new workouts. Covered by
`testSignatureChangesWithTheDaySoRollingWindowsStayFresh`.


`currentDataSignature()` (`InsightsService.swift:270`) returns
`"v{version}-{count}-{latestWorkoutDate}"`. No date component, so **nothing
recomputes unless a workout is completed.**

A trailing 7-day window changes every day as sets fall out the back. Take four
days off and the status panel keeps insisting you did 47 sets this week — on the
most visible number in the app. (The 14-day `muscleBalance` window has the same
bug today; it's invisible only because findings are occasional.)

**Fix:** add day granularity to the signature so it recomputes at most once per
day. One line.

### 7.3 ✅ `InsightAnalysisContext` recomputed on every access

**Done (Phase 1).**

`eligibleWorkingSets` was a computed property that re-flatMapped every workout
and set on each access. Three rules read it today; the v2 set has most of a dozen
doing so, plus the status computation — all on every Home appearance. Now
materialized once in a custom `init`.

`workoutsById` / `workout(_:)` turned out to be dead code — nothing in the app or
tests ever called the lookup, so the per-access dictionary rebuild never actually
ran. Both deleted rather than optimized. If a future rule needs workout lookup,
add it back as a stored property.

### 7.4 Status computation

Lives on `InsightsService`, not a new service, so it reuses the single
`buildContext` fetch. Extend `InsightsServiceProtocol` with:

```swift
func fetchTrainingStatus() async throws -> TrainingStatus
```

`TrainingStatus` is a `Sendable` value type: state band, current/baseline totals,
and `[MuscleVolumeRow]` (group value, display name, current, baseline, delta).

### 7.5 `analysisVersion`

Bump to `2`. Invalidates stored signatures so every existing user gets a fresh
analysis on next Home load.

### 7.6 Units

Nine new rules render weights. Every one must go through
`UnitConversion.formatWeightLabel(_:unitPreference:)` as `restSweetSpot` already
does. `HealthProfile.unitPreferenceRawValue` is a user preference, not a constant.

---

## 8. Cold start

The positive floor handles the usual empty feed but not a new install.
`consistency` needs 3 weeks; the baseline needs 8. On day three there is no
baseline to compare against.

**Day-1 through week-3 state:**
- Status card shows totals with **no comparison** and no state band.
- Muscle panel shows current counts with **no ticks and no deltas**.
- Findings section is absent, not empty-stated.
- Copy states what it *is* showing, never what it can't. No progress bars toward
  unlocking, no "not enough data yet".

This is the first impression for every new install, and "not enough data yet" is
precisely the failure v2 exists to fix.

---

## 9. Analytics

All events route through `AnalyticsService`, so the existing opt-out
(`analyticsOptOutToggled`) applies automatically. Follow existing naming:
lowercase-spaced events, snake_case properties.

### 9.1 Events

| Event | Properties |
|---|---|
| `insights opened` | `source` (hook \| deep_link), `finding_count`, `has_new`, `has_baseline` |
| `insight expanded` | `rule_id` |
| `insight rated` | `rule_id`, `rating` (useful \| not_useful), `insight_age_days`, `was_expanded` |
| `insight rating reason` | `rule_id`, `reason` (wrong \| obvious \| not_actionable \| dont_care) |
| `insight snoozed` | `rule_id`, `insight_age_days` |
| `muscle panel expanded` | `group_count` |

**`rule_id` on every event is non-negotiable.** The entire question is which
rules to keep, sharpen, or kill; an aggregate "insights engagement" number is a
dashboard you look at once and can't act on.

**Never send** headline text, detail text, or chart values. Those contain
exercise names and real weights — training data leaving the device, which is what
the replay masking exists to prevent. The existing `*_bucket` convention
(`duration_bucket`, `set_count_bucket`) is the established posture: shapes, not values.

### 9.2 Feedback UI

**Implicit first.** `snooze` is already built and wired to the card menu
(`InsightsService.swift:123`) and currently fires no analytics. Someone actively
dismissing a finding for three weeks is a clearer verdict than any thumbs-down,
and it's free of response-rate bias. Same for expansion — `InsightCardView`
already toggles on tap.

**Explicit, minimal.** "Was this useful? 👍 👎" appears **only in the expanded
card state**, never on the collapsed card. Keeps the feed clean and self-selects
for people who actually read the finding.

**Reason follow-up is a fixed option list, not free text.** PostHog surveys are
configured multiple-choice only and the privacy policy says so
(`AnalyticsService.swift:71`).

### 9.3 What replay will not tell you

`maskAllTextInputs` masks every text layer in SwiftUI
(`AnalyticsService.swift:87`), so Training Insights records as redacted
rectangles. Replay shows scrolling and taps, never what was read. Explicit events
are the only path — don't assume replay covers it.

### 9.4 Kill threshold — decide before shipping

After **200 firings**, a rule with **<30% useful** and **>25% snooze** gets
pulled or retuned. Setting the number now is what makes this an experiment rather
than a dashboard.

---

## 10. Work list

New files need hand-registration in `project.pbxproj` — the project uses explicit
file references, so a file on disk will not compile until registered.

**New files**
- `Features/Home/Views/TrainingInsightsHookView.swift`
- `Features/Insights/Views/TrainingStatusCardView.swift`
- `Features/Insights/Views/MuscleVolumePanelView.swift`
- `Features/Insights/Views/InsightChartViews.swift` — the seven chart kinds
- `Core/Services/InsightRules+Progress.swift` — Tier 1 rules
- `Core/Services/InsightRules+Patterns.swift` — Tier 2 rules
- `RepsterTests/InsightRulesTests.swift`

**Modified**
- `Core/Services/InsightsService.swift` — signature fix, context perf fix, status computation, positive floor, tone cap, refire intervals, rule registry, `analysisVersion` → 2
- `Core/Services/Protocols/InsightsServiceProtocol.swift` — `fetchTrainingStatus()`, `TrainingStatus`, `InsightCategory` cases, `chartKind` on `InsightItem`
- `Core/Services/InsightRules.swift` — `targetAdherence` / `rirCalibration` chart kinds, retire `prRhythm`
- `Data/Models/InsightRecord.swift` — `chartKind`, refire tracking
- `Features/Insights/Views/InsightsView.swift` — status + panel + findings
- `Features/Insights/Views/InsightCardView.swift` — chart dispatch, rating row in expanded state
- `Features/Home/Views/HomeView.swift` — hook swap
- `Features/Home/ViewModels/HomeViewModel.swift` — status summary
- `Core/Services/Protocols/AnalyticsServiceProtocol.swift` — events + properties
- `RepsterTests/InsightsServiceTests.swift`

**Deleted**
- `Features/Home/Views/InsightsTeaserCardView.swift`

### Test budget

Thresholds are the risk surface. 13 rules × gates is where bad advice comes from,
and `deloadReadiness` is the one users will act on and judge the app for. Rule
tests are real work, not a tail task — budget them explicitly.

---

## 11. Phasing

1. **Engine correctness** — signature fix, context perf fix. Ships independently,
   fixes live bugs.
2. **Status layer** — `TrainingStatus`, muscle panel, destination screen restructure, cold start.
3. **Rules** — Tier 1 + `deloadReadiness`, curation changes, `chartKind` + chart components.
4. **Analytics** — events, rating UI.
5. **Hook** — figures-first exploration, replace provisional B.
6. **Tier 2 rules** — follow-on.

Phase 1 is worth doing first regardless: both issues affect shipped code today.

---

## 12. Out of scope

- Push notifications of any kind.
- Gating behind the RevenueCat entitlement.
- Share rendering of insights (aligns with the share-card feature, tracked separately).
- Deep-link actions from findings into editors (deferred from Phase 1, still deferred).
- Fixing `ExerciseMuscleGroupCatalog.orderedValues` for the Charts breakdown.
- Resolving the overlap between the muscle panel and Charts → Breakdown.

---

## 13. Open questions

1. **Hook design.** Provisional B. Figures-first direction to explore (§3.1).
2. **Findings history.** Records are deleted when a finding stops holding
   (`InsightsService.swift:209`). With 13 rules competing for 3 slots, most
   findings a user earns they will never see, and "your squat is up 6%" appears
   once then vanishes. Decide whether there's an archive.
3. **Charts → Breakdown overlap.** Muscle-group volume now lives in two places.
   Deliberate coexistence or consolidation?
