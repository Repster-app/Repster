# App Store screenshot suggestions — the capability layer

Written 2026-08-16 from the SwiftUI source on `NewMain`, not from the rendered frames.

Companion to `live-screenshots-inventory.md` (what is live) and `screenshot-review.md`
(the critique plus Set A / Set B). This document is the layer underneath those two: the
exhaustive inventory of what the app can actually show, and the full menu of frames that
could be built from it. Apple allows ten iPhone screenshots; the menu is deliberately
longer than any one set.

Every frame below cites the file that renders it. Where a proposal in Set A or Set B
points at a view that does not render in the shipping app, that is called out.

---

## 0. Four corrections that change what is buildable

These came out of the source walk and they invalidate specific rows in the existing sets.
They are here first because everything downstream depends on them.

### 0.1 `ExerciseInfoSectionView` and its three cards are dead code

`E1RMCardView`, `LastWorkoutCardView`, and `EstimatedRepsCardView` are only ever
constructed inside `ExerciseInfoSectionView`
([ExerciseInfoSectionView.swift:25](Repster/Features/Workout/Views/Components/ExerciseInfoSectionView.swift:25)),
and `ExerciseInfoSectionView` is referenced nowhere in the app — only by its own
`#Preview` blocks and by a stale comment in
[WeightSuggestionModuleView.swift:3](Repster/Features/Workout/Views/Components/WeightSuggestionModuleView.swift:3).
The Sets sub-tab renders `SetTableView` then `WeightSuggestionModuleView` and stops
([ActiveWorkoutView.swift:206](Repster/Features/Workout/Views/ActiveWorkoutView.swift:206)).

Consequences:

- **Set A #2** ("Last time, in the same row" → `SetTableView` + `LastWorkoutCardView`) is
  not capturable. There is no last-session card, and the set table's placeholders come
  from *target rep guidance*, not from your previous session
  ([SetTableView.swift:936](Repster/Features/Workout/Views/SetTableView.swift:936)). Last
  time's numbers live one tab across, in the History sub-tab.
- **Set B #4** ("e1RM from your peak sets" → `E1RMCardView`) is not capturable either.
  The only non-admin e1RM surfaces are `ExerciseDetailView`'s `BEST E1RM` stat
  ([ExerciseDetailView.swift:142](Repster/Features/Exercise/Views/ExerciseDetailView.swift:142))
  and the `Estimated 1RM` chart metric. The `e1RM 134.2 kg` chip on the suggestions header
  is behind Admin Mode
  ([WeightSuggestionModuleView.swift:88](Repster/Features/Workout/Views/Components/WeightSuggestionModuleView.swift:88)).

The underlying *claims* survive; the screens cited for them do not.

### 0.2 There is no CSV export

`ExportView` produces a Repster-specific JSON archive and says so on screen: the copy
reads that the file is meant for full restore, "not third-party CSV import"
([ExportView.swift:52](Repster/Features/Settings/Views/ExportView.swift:52)). The backup
protocol is `exportBackup() async throws -> Data` with no CSV path anywhere
([ExportServiceProtocol.swift:281](Repster/Core/Services/Protocols/ExportServiceProtocol.swift:281)),
and the only `.commaSeparatedText` content type in the codebase is on the two *import*
pickers. **Set B #7 ("CSV in, CSV out") is not true**, and the ad-kit claim row "Data is
local-first with CSV import and export" is half wrong. CSV in, Repster archive out.

### 0.3 The 1.3 cut is earlier than "Insights and HealthKit"

1.3 released 2026-06-11. The last commit that can be in that binary is `f033e81`
(2026-06-10). `2eddd9d` (2026-06-26, "lot of unremebered changes") still carried
`MARKETING_VERSION = 1.3` — the bump to 1.4 only landed in `25c539f` on 2026-08-10 — but
it shipped to nobody. Everything added in `2eddd9d` or later is 1.4-gated regardless of
what the version string said at the time. That includes the whole first cut of Insights
(`InsightsService`, `InsightRules`, `InsightsView`, `InsightCardView`) and the Insights
section on Home ([HomeSectionConfig.swift:45](Repster/Features/Home/Models/HomeSectionConfig.swift:45)).

### 0.4 There is no iPad set to be missing

The app target is `TARGETED_DEVICE_FAMILY = 1` (iPhone only); only the Live Activity
extension and the test bundle are `1,2`. `screenshot-review.md` §1 lists "no iPad set" as
a gap. It is not a gap.

---

## Phase 1 — the true feature surface

Version gate: **1.3** = in the live build. **1.4** = on `NewMain`, unshipped, cannot
appear on the product page until 1.4 is submitted.

Visual weight: **High** = a distinctive screen. **Medium** = a real surface that reads as
a generic list or form. **Low** = a toggle, context menu, or alert with no photogenic
state.

### Workout — active logging

| Capability | Primary view | Weight | Version | Claim status |
|---|---|---|---|---|
| Set logger: SET / WEIGHT / REPS / RIR / PR / ✓ | [SetTableView.swift:174](Repster/Features/Workout/Views/SetTableView.swift:174) | High | 1.3 | Verifiable — six named columns |
| RIR entry per set, colour-graded −/0–5+ | [SetRowView.swift:324](Repster/Features/Workout/Views/SetRowView.swift:324) | High | 1.3 | Verifiable |
| Smart Suggestions module | [WeightSuggestionModuleView.swift:48](Repster/Features/Workout/Views/Components/WeightSuggestionModuleView.swift:48) | High | 1.3 | Verifiable — "Set N · 122,5 kg for 5–8 reps" |
| Contextual explanation line under each suggestion | [WeightSuggestionData.swift:844](Repster/Features/Workout/Models/WeightSuggestionData.swift:844) | High | 1.3 | Verifiable — four fixed strings, incl. "Easing off slightly to manage session fatigue." |
| Rest timer: ring, ±15s/±30s, exact-seconds editor | [RestTimerView.swift:76](Repster/Features/Workout/Views/RestTimerView.swift:76) | High | 1.3 | Verifiable |
| Live Activity / Dynamic Island | [WorkoutLiveActivityLiveActivity.swift:84](WorkoutLiveActivity/WorkoutLiveActivityLiveActivity.swift:84) | High | 1.3 | Verifiable — title, elapsed, exercise, "Set 2/4 (working)", countdown, "REST COMPLETE / GO" |
| Per-exercise sub-tabs: Sets / History / PRs / Charts / ⚙ | [ActiveWorkoutView.swift:200](Repster/Features/Workout/Views/ActiveWorkoutView.swift:200) | High | 1.3 | Verifiable |
| Previous sessions inside the workout | [ExerciseHistoryView.swift:33](Repster/Features/Exercise/Views/ExerciseHistoryView.swift:33) | High | 1.3 | Verifiable — dated cards, PR badges |
| Rep-max PR table inside the workout | [ExercisePRsView.swift:59](Repster/Features/Exercise/Views/ExercisePRsView.swift:59) | High | 1.3 | Verifiable — REPS / WEIGHT / DATE |
| e1RM chart inside the workout, with trend line | [EmbeddedExerciseChartView.swift](Repster/Features/Charts/Views/EmbeddedExerciseChartView.swift) | High | 1.3 | Verifiable |
| Post-workout recap: time, sets, volume, PR count | [WorkoutSummarySheet.swift:179](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:179) | High | 1.3 | Verifiable |
| Fatigue feedback: Too much drop / About right / Not enough drop | [WorkoutSummarySheet.swift:556](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:556) | High | 1.3 | Verifiable — feeds `FatigueLearningService` |
| Session effort 1–10 ("How hard did it feel?") | [WorkoutSummarySheet.swift:344](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:344) | Medium | 1.3 | Verifiable |
| Save finished workout as a template | [WorkoutSummarySheet.swift:609](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:609) | Medium | 1.3 | Verifiable — "Weights are not included" |
| Warmup sets (`+ Add Warmup`), separate warmup rest time | [SetTableView.swift:313](Repster/Features/Workout/Views/SetTableView.swift:313) | Medium | 1.3 | Verifiable |
| Rep-range targets (`Set Range`, e.g. 5–8) | [SetTableView.swift:1456](Repster/Features/Workout/Views/SetTableView.swift:1456) | Medium | 1.3 | Verifiable |
| Custom numeric keypad with Prev/Next, RIR chips | [SetTableView.swift:1004](Repster/Features/Workout/Views/SetTableView.swift:1004) | Medium | 1.3 | Verifiable, but see §5 — it is a picture of typing |
| Unilateral (left/right) logging | [SetRowView.swift:325](Repster/Features/Workout/Views/SetRowView.swift:325) | Medium | 1.3 | Verifiable — "PRs use the stronger side and are shown per side" |
| 13 set types (drop set, myo-rep, AMRAP, cluster, …) | [SetType.swift:3](Repster/Data/Enums/SetType.swift:3), chosen at [SetRowView.swift:256](Repster/Features/Workout/Views/SetRowView.swift:256) | **Low** | 1.3 | Verifiable, but it is a long-press context menu — no screen |
| Non-weight tracking types (time, distance, weight+time) | [SetTableView.swift:237](Repster/Features/Workout/Views/SetTableView.swift:237), [TrackingType.swift:3](Repster/Data/Enums/TrackingType.swift:3) | Low | 1.3 | Verifiable — headers change to TIME / DIST |
| Per-set notes | [SetRowView.swift:273](Repster/Features/Workout/Views/SetRowView.swift:273) | **Low** | 1.3 | Verifiable — it is an alert box |
| Per-exercise weight increment + rest override | [ExerciseSettingsSheet.swift:77](Repster/Features/Workout/Views/Components/ExerciseSettingsSheet.swift:77) | Low | 1.3 | Verifiable |
| Per-exercise progression exclusion | [WorkoutExclusionSheet.swift:53](Repster/Features/Workout/Views/Components/WorkoutExclusionSheet.swift:53) | Low | 1.3 | Verifiable |
| Whole-session PR exclusion ("Count toward PRs") | [StartWorkoutSheet.swift:127](Repster/Features/Home/Views/StartWorkoutSheet.swift:127) | Medium | 1.3 | Verifiable — "for hotel, travel, or mismatched-equipment sessions" |
| Edit a past workout | [EditWorkoutView.swift:119](Repster/Features/Workout/Views/EditWorkoutView.swift:119) | Low | 1.3 | Verifiable |
| Elapsed workout timer with pause | [ElapsedTimerView.swift](Repster/Features/Workout/Views/ElapsedTimerView.swift) | Low | 1.3 | Verifiable |
| Suggestion diagnostics drawer (per-set internals) | [WeightSuggestionCardView.swift:359](Repster/Features/Workout/Views/Components/WeightSuggestionCardView.swift:359) | Medium | 1.3 | **Admin Mode only** |

### Home

| Capability | Primary view | Weight | Version | Claim status |
|---|---|---|---|---|
| Home: week strip, start card, PRs, recent sessions | [HomeView.swift:127](Repster/Features/Home/Views/HomeView.swift:127) | High | 1.3 | Verifiable |
| Resume an in-progress workout | [StartWorkoutCardView.swift:36](Repster/Features/Home/Views/StartWorkoutCardView.swift:36) | Medium | 1.3 | Verifiable |
| Recent PRs, standard (3) or compact (6), scoped | [RecentPRsView.swift:22](Repster/Features/Home/Views/RecentPRsView.swift:22), [HomeSectionConfig.swift:8](Repster/Features/Home/Models/HomeSectionConfig.swift:8) | Medium | 1.3 | Verifiable |
| Start options: empty / template / copy previous | [StartWorkoutSheet.swift:54](Repster/Features/Home/Views/StartWorkoutSheet.swift:54) | Medium | 1.3 | Verifiable |
| Copy a previous workout | [CopyPreviousSheet.swift:85](Repster/Features/Home/Views/CopyPreviousSheet.swift:85) | Low | 1.3 | Verifiable |
| Monthly stats card | [MonthlyStatsCardView.swift:14](Repster/Features/Home/Views/MonthlyStatsCardView.swift:14) | Low | 1.3 | Verifiable |
| This week vs weekly goal | [ThisWeekActivityView.swift:41](Repster/Features/Home/Views/ThisWeekActivityView.swift:41) | Low | 1.3 | Verifiable |
| Reorder / hide home sections | [CustomizeHomeSheet.swift](Repster/Features/Home/Views/CustomizeHomeSheet.swift) | Low | 1.3 | Verifiable |
| Training Insights hook card | [TrainingInsightsHookView.swift:22](Repster/Features/Home/Views/TrainingInsightsHookView.swift:22) | Medium | **1.4** | Verifiable |

### Insights — entirely 1.4

| Capability | Primary view | Weight | Version | Claim status |
|---|---|---|---|---|
| Training status vs your own 8-week baseline | [TrainingStatusCardView.swift:87](Repster/Features/Insights/Views/TrainingStatusCardView.swift:87) | High | 1.4 | Verifiable — five fixed bands, e.g. "Lighter week than your usual" |
| Baseline meter | [BaselineMeterView.swift](Repster/Features/Insights/Views/BaselineMeterView.swift) | Medium | 1.4 | Verifiable |
| Last 7 days by muscle, in sets / reps / volume | [MuscleVolumePanelView.swift:91](Repster/Features/Insights/Views/MuscleVolumePanelView.swift:91) | High | 1.4 | Verifiable |
| Findings feed with per-card mini charts | [InsightsView.swift:76](Repster/Features/Insights/Views/InsightsView.swift:76), [InsightChartViews.swift](Repster/Features/Insights/Views/InsightChartViews.swift) | High | 1.4 | Verifiable |
| Rule: rest sweet spot | [InsightRules.swift:83](Repster/Core/Services/InsightRules.swift:83) | High | 1.4 | Verifiable — "Longer rest is buying you reps on X" + a two-bar comparison |
| Rule: target adherence | [InsightRules.swift:161](Repster/Core/Services/InsightRules.swift:161) | High | 1.4 | Verifiable — below / in range / above proportions |
| Rule: muscle balance | [InsightRules.swift:253](Repster/Core/Services/InsightRules.swift:253) | Medium | 1.4 | Verifiable |
| Rule: PR pace | [InsightRules.swift:398](Repster/Core/Services/InsightRules.swift:398) | Medium | 1.4 | Verifiable — "4 PRs in the last month" |
| Rule: RIR calibration | [InsightRules.swift:446](Repster/Core/Services/InsightRules.swift:446) | High | 1.4 | Verifiable |
| Rule: strength trend | [InsightRules+Progress.swift:72](Repster/Core/Services/InsightRules+Progress.swift:72) | High | 1.4 | Verifiable — "Your bench press is up 6% over 8 weeks" |
| Rule: consistency | [InsightRules+Progress.swift:198](Repster/Core/Services/InsightRules+Progress.swift:198) | Medium | 1.4 | Verifiable |
| Rule: dropped exercise | [InsightRules+Progress.swift:317](Repster/Core/Services/InsightRules+Progress.swift:317) | High | 1.4 | Verifiable — "You've quietly stopped doing barbell row" |
| Rule: volume ramp | [InsightRules+Progress.swift:398](Repster/Core/Services/InsightRules+Progress.swift:398) | Medium | 1.4 | Verifiable |
| Rule: deload readiness | [InsightRules+Readiness.swift:89](Repster/Core/Services/InsightRules+Readiness.swift:89) | Medium | 1.4 | **Careful** — closest thing in the app to a recovery claim; see §5 |
| Snooze an insight, rate it useful | [InsightCardView.swift:69](Repster/Features/Insights/Views/InsightCardView.swift:69) | Low | 1.4 | Verifiable |
| Insight Gallery | [InsightGalleryView.swift](Repster/Features/Insights/Views/InsightGalleryView.swift) | Medium | 1.4 | **Admin Mode only** |

### Charts

| Capability | Primary view | Weight | Version | Claim status |
|---|---|---|---|---|
| Breakdown donut + 4-stat summary | [BreakdownTabView.swift:124](Repster/Features/Charts/Views/BreakdownTabView.swift:124) | High | 1.3 | Verifiable — volume / sets / reps / workouts |
| Eight breakdown presets (volume, sets, reps, workouts × category, exercise) | [ChartModels.swift:12](Repster/Features/Charts/Models/ChartModels.swift:12) | Medium | 1.3 | Verifiable |
| Workouts time series with trend line | [WorkoutsTabView.swift](Repster/Features/Charts/Views/WorkoutsTabView.swift), [TrendLineOverlay.swift](Repster/Features/Charts/Views/Components/TrendLineOverlay.swift) | High | 1.3 | Verifiable |
| Exercise comparison, multi-line | [ExercisesTabView.swift](Repster/Features/Charts/Views/ExercisesTabView.swift), [MultiLineChart.swift](Repster/Features/Charts/Views/Components/MultiLineChart.swift) | High | 1.3 | Verifiable |
| Exercise metrics: e1RM / max weight / max reps / max volume | [ChartModels.swift:133](Repster/Features/Charts/Models/ChartModels.swift:133) | Medium | 1.3 | Verifiable |
| Point navigator → View Workout | [DataPointNavigator.swift](Repster/Features/Charts/Views/Components/DataPointNavigator.swift) | Medium | 1.3 | Verifiable |

### Calendar

| Capability | Primary view | Weight | Version | Claim status |
|---|---|---|---|---|
| Month grid with muscle-group dots | [CalendarDayCell.swift](Repster/Features/Calendar/Views/CalendarDayCell.swift), [MuscleGroupDot.swift](Repster/Features/Calendar/Views/Components/MuscleGroupDot.swift) | High | 1.3 | Verifiable |
| Day detail: volume / exercises / sets / duration | [SummaryStatsStrip.swift](Repster/Features/Calendar/Views/Components/SummaryStatsStrip.swift) | High | 1.3 | Verifiable |
| Per-exercise set tables for a past session | [CalendarExerciseCard.swift:58](Repster/Features/Calendar/Views/Components/CalendarExerciseCard.swift:58) | High | 1.3 | Verifiable |

### Exercise library

| Capability | Primary view | Weight | Version | Claim status |
|---|---|---|---|---|
| Exercise detail header: workouts, best e1RM, last | [ExerciseDetailView.swift:138](Repster/Features/Exercise/Views/ExerciseDetailView.swift:138) | High | 1.3 | Verifiable |
| Rep-max PR table | [ExercisePRsView.swift:59](Repster/Features/Exercise/Views/ExercisePRsView.swift:59) | High | 1.3 | Verifiable |
| Full exercise history | [ExerciseHistoryView.swift](Repster/Features/Exercise/Views/ExerciseHistoryView.swift) | Medium | 1.3 | Verifiable |
| Library with search, muscle filter, sort | [ExerciseListView.swift:148](Repster/Features/Exercise/Views/ExerciseListView.swift:148) | Medium | 1.3 | Verifiable |
| Create a custom exercise | [CreateEditExerciseSheet.swift:84](Repster/Features/Exercise/Views/CreateEditExerciseSheet.swift:84) | Medium | 1.3 | Verifiable |
| Bodyweight factor per exercise | [CreateEditExerciseSheet.swift:177](Repster/Features/Exercise/Views/CreateEditExerciseSheet.swift:177) | Low | 1.3 | Verifiable |
| Assign-muscle-groups flow after import | [AssignMuscleGroupsView.swift:121](Repster/Features/Exercise/Views/AssignMuscleGroupsView.swift:121) | Medium | 1.3 | Verifiable |
| 69 built-in exercises | [seed_exercises.json](Repster/Resources/seed_exercises.json) | — | 1.3 | Verifiable but unflattering; see §5 |

### Templates

| Capability | Primary view | Weight | Version | Claim status |
|---|---|---|---|---|
| Template list: exercise/set counts, muscle tags | [TemplateCardView.swift](Repster/Features/Templates/Views/Components/TemplateCardView.swift), [TemplateListSheet.swift:289](Repster/Features/Templates/Views/TemplateListSheet.swift:289) | High | 1.3 | Verifiable |
| Template editor: per-set rep range + RIR, rest, notes | [CreateEditTemplateView.swift:418](Repster/Features/Templates/Views/CreateEditTemplateView.swift:418) | High | 1.3 | Verifiable |
| Superset grouping | [CreateEditTemplateView.swift:325](Repster/Features/Templates/Views/CreateEditTemplateView.swift:325) | **Low** | 1.3 | **Half-built.** Groups are labelled and coloured in the editor and the ID is carried onto sets ([TemplateService.swift:159](Repster/Core/Services/TemplateService.swift:159)), but nothing in `ActiveWorkoutView`, `ExerciseTabStripView`, or `SetTableView` reads `supersetGroupId`. Invisible while you train. |
| Template JSON share / import | [TemplateListSheet.swift:997](Repster/Features/Templates/Views/TemplateListSheet.swift:997) | Low | 1.3 | Verifiable |
| "AI Helper" — export context, copy prompt, paste JSON | [TemplateListSheet.swift:484](Repster/Features/Templates/Views/TemplateListSheet.swift:484) | Medium | 1.3 | **Not an in-app AI.** It is a three-step copy-paste flow through ChatGPT. See §5 |

### Data, settings, onboarding

| Capability | Primary view | Weight | Version | Claim status |
|---|---|---|---|---|
| CSV import from FitNotes, Strong, Hevy | [ImportView.swift:87](Repster/Features/Settings/Views/ImportView.swift:87), [ImportServiceProtocol.swift:5](Repster/Core/Services/Protocols/ImportServiceProtocol.swift:5) | High | 1.3 | Verifiable — three named sources, per-source unit handling |
| Import preview: column mapping + sample rows | [ImportView.swift:232](Repster/Features/Settings/Views/ImportView.swift:232) | Medium | 1.3 | Verifiable |
| Import result: sets / workouts / exercises / skipped | [ImportView.swift:372](Repster/Features/Settings/Views/ImportView.swift:372) | High | 1.3 | Verifiable |
| Import during onboarding | [ImportStepView.swift](Repster/Features/Onboarding/Views/ImportStepView.swift) | Medium | 1.3 | Verifiable |
| Backup export (Repster JSON archive) | [ExportView.swift:26](Repster/Features/Settings/Views/ExportView.swift:26) | Medium | 1.3 | Verifiable — **not CSV** |
| Restore backup with preview + counts | [ExportView.swift:166](Repster/Features/Settings/Views/ExportView.swift:166) | Medium | 1.3 | Verifiable |
| Smart Suggestions advanced: default reps, default RIR, recency window, fatigue toggle | [PrescriptionSettingsView.swift:101](Repster/Features/Settings/Views/PrescriptionSettingsView.swift:101) | High | 1.3 | Verifiable |
| e1RM formula: Epley / Brzycki / Lombardi, equations shown | [FormulaPickerSheet.swift:25](Repster/Features/Settings/Views/Components/FormulaPickerSheet.swift:25), [E1RMFormula.swift:16](Repster/Data/Enums/E1RMFormula.swift:16) | Medium | 1.3 | Verifiable — the literal formulae are on screen |
| Default rest time, warmup rest time, timer alert | [SettingsView.swift:728](Repster/Features/Settings/Views/SettingsView.swift:728) | Low | 1.3 | Verifiable |
| Warmups in volume / in PRs toggles | [SettingsView.swift:712](Repster/Features/Settings/Views/SettingsView.swift:712) | Low | 1.3 | Verifiable |
| Units kg / lb, per-unit increment options | [UnitPickerSheet.swift](Repster/Features/Settings/Views/Components/UnitPickerSheet.swift), [UnitConversion.swift](Repster/Core/Extensions/UnitConversion.swift) | Low | 1.3 | Verifiable |
| Bodyweight log with chart | [BodyweightLogView.swift:88](Repster/Features/Settings/Views/BodyweightLogView.swift:88) | Medium | 1.3 | Verifiable |
| Anonymous analytics opt-out | [SettingsView.swift:1013](Repster/Features/Settings/Views/SettingsView.swift:1013) | Low | 1.3 | Verifiable — the footer enumerates exactly what is never sent |
| Rebuild stats / PRs | [RebuildStatsView.swift:28](Repster/Features/Settings/Views/RebuildStatsView.swift:28) | Low | 1.3 | Verifiable |
| Reset app data | [SettingsView.swift:1090](Repster/Features/Settings/Views/SettingsView.swift:1090) | Low | 1.3 | Verifiable |
| Membership: 5 free workouts, then paywall | [MonetizationService.swift:31](Repster/Core/Services/MonetizationService.swift:31); paywall is RevenueCat's `PaywallView` ([ContentView.swift:226](Repster/App/ContentView.swift:226)) | Low | 1.3 | Verifiable, but the paywall is remotely configured — not in this repo |
| Onboarding: welcome, units, bodyweight, suggestion defaults, import | [OnboardingContainerView.swift](Repster/Features/Onboarding/Views/OnboardingContainerView.swift) | Medium | 1.3 | Verifiable |
| Fatigue Learning diagnostics | [FatigueLearningAdminView.swift:27](Repster/Features/Settings/Views/FatigueLearningAdminView.swift:27) | High | 1.3 | **Admin Mode only** — gated at [PrescriptionSettingsView.swift:154](Repster/Features/Settings/Views/PrescriptionSettingsView.swift:154), and the toggle is off by default |
| Apple Health: write-only workout sync + estimated energy | [AppleHealthSettingsView.swift:33](Repster/Features/Settings/Views/AppleHealthSettingsView.swift:33) | Medium | **1.4** | Verifiable — "Repster only writes to Health — it never reads your health data" |
| Apple Health prompt | [AppleHealthPromptView.swift:31](Repster/Features/Health/AppleHealthPromptView.swift:31) | Low | 1.4 | Verifiable |
| What's New sheet | [WhatsNewSheet.swift](Repster/Features/WhatsNew/WhatsNewSheet.swift) | Low | 1.4 | Verifiable |
| Ratings prompt at 3 / 12 / 30 workouts | [ReviewPromptService.swift](Repster/Core/Services/ReviewPromptService.swift) | None | 1.4 | System alert — nothing to capture |

### Things that do not exist

Recorded so nobody proposes a frame for them.

| Claimed / assumed | Reality |
|---|---|
| Programs | `Program`, `ProgramExercise`, `PlannedWorkout`, `PlannedSet` and `ProgramRepository` exist as models; **zero UI references them** anywhere in `Repster/Features` or `Repster/App`. The live headline **BUILD PROGRAMS** names a feature the app does not have — the screen underneath it is the Templates sheet. |
| Plate maths / barbell loading | No plate calculator anywhere in the codebase. |
| CSV export | Does not exist. See §0.2. |
| Supersets during a workout | Template editor only. See the Templates table. |
| Last-session values beside the input row | Does not exist. See §0.1. |
| iCloud sync / accounts | None. Local SwiftData only. Honest, but it also means no cross-device story. |
| iPad | Not a supported device family. |

---

## Phase 2 — diff against the live six

| Capability | Status in the live set |
|---|---|
| Charts breakdown donut, workouts chart, exercises chart | **Covered** — TRACK PROGRESS |
| Home: start card, recent PRs, recent sessions | **Covered** — START FAST |
| Calendar month + day detail set tables | **Covered** — REVIEW HISTORY |
| Template list | **Covered** — BUILD PROGRAMS (under a headline naming a feature that does not exist) |
| Set logger + Smart Suggestions | **Covered** — TRAIN SMARTER |
| Fatigue Learning diagnostics | **Covered**, at one-third scale inside AND MORE… |
| Exercise detail (workouts / best e1RM / e1RM chart) | **Incidental** — cropped right-edge device in TRACK PROGRESS |
| Per-exercise history with PR badges | **Incidental** — rear device in AND MORE… |
| Rest timer | **Incidental** — a `0:04` sheet fragment in AND MORE… |
| RIR column, PR badges, warmup button, sub-tab strip, exercise chips | **Incidental** — present in TRAIN SMARTER, unreadable at thumbnail scale |
| Custom keypad + RIR picker | **Incidental** — front device in AND MORE…, and the frame that ships `50 kg × 0 reps` |
| Live Activity / Lock Screen / Dynamic Island | **Absent** |
| Rep-max PR table | **Absent** |
| Workout summary / recap | **Absent** |
| Fatigue feedback (Too much drop / About right / Not enough drop) | **Absent** |
| Contextual suggestion explanation line | **Absent** (the live TRAIN SMARTER frame shows an older, now-changed string) |
| Smart Suggestions settings (recency, default RIR, fatigue toggle) | **Absent** |
| e1RM formula picker | **Absent** |
| CSV import — source picker, preview, result | **Absent** |
| Backup / restore | **Absent** |
| Warmup handling, units, rest configuration | **Absent** |
| Bodyweight log | **Absent** |
| Exercise library / custom exercise creation | **Absent** |
| Template editor (rep ranges, RIR targets) | **Absent** |
| Onboarding | **Absent** |
| Insights, Apple Health, What's New | **Absent** — correctly, all 1.4 |

### Absent because they deserve to be

Bodyweight log, units, rest-time configuration, warmup toggles, rebuild stats, reset data,
edit-past-workout, copy-previous, home customisation, set types, per-set notes, exercise
creation, onboarding. Each is either a form, a context menu, or an alert. None of them is
a reason to install, and a slot spent on one is a slot not spent on the load model.
Onboarding is the only borderline case, and it loses on principle: nobody installs an app
to look at its setup flow.

### Absent by oversight

These are the real misses, and they are not the same problem as the above:

1. **The Live Activity.** The most visually distinctive thing the app renders, on the one
   surface an iPhone user looks at fifty times a day, and it is nowhere. Set A did propose
   it, but pointed at `RestTimerView` — the in-app sheet, not the Lock Screen render,
   which lives in a different target entirely.
2. **The rep-max table.** A dated ladder of every rep-max for an exercise is the single
   most legible "this app remembers everything" image available, and no set proposed it.
   Both sets routed "PRs" to `RecentPRsView`, the three-row home teaser.
3. **Import — the result screen.** Both sets proposed the import *entry* point. The entry
   point is three tiles and a disabled button. The screen that carries the argument is
   `Import Complete` with the counts on it.
4. **The workout summary.** A whole post-session surface with duration, sets, volume, PR
   count, effort rating, and a save-as-template button. Absent from the live set and from
   both proposals.
5. **The fatigue feedback loop.** Three buttons per exercise, in the user's face at the
   end of every session, feeding the model that both sets want to sell. Both sets went to
   the admin diagnostics screen instead.

---

## Phase 3 — the suggestion sheet

Ten slots exist. Twenty-eight frames are listed. Assemble from these.

Notation: **Capture** = `exists` means a usable source PNG is already in
`marketing/source/screenshots/`; everything else is a new capture. All existing sources
are 1206×2622 (6.3"), not the 1320×2868 (6.9") the product page specifies — see §4.

### Group A — Capability: what the app does

| # | Frame | Headline | Subtitle | Screen + state | Data required | Argument | Version | Capture | @320×480 | Strength |
|---|---|---|---|---|---|---|---|---|---|---|
| A1 | Next weight | **It picks the weight** | Set by set, from your own recent sessions. | [WeightSuggestionModuleView.swift:48](Repster/Features/Workout/Views/Components/WeightSuggestionModuleView.swift:48) in the Sets sub-tab, two pending suggestions, admin off | Barbell Back Squat; Set 1 **122,5 kg** for 5–8 reps; Set 2 **125 kg** for 5–7 reps | The app answers the question you were going to answer badly yourself | 1.3 | `exists` — crop the card region of `active-sets.png`; the table above it is all zeros | "122,5 kg" | **Strong** — one big number, one exercise name |
| A2 | Rep-max ladder | **Every rep max, dated** | 1 through 12, each with the day you hit it. | [ExercisePRsView.swift:59](Repster/Features/Exercise/Views/ExercisePRsView.swift:59) via ExerciseDetail → PRs | Barbell Back Squat: 1×140 kg Apr 29 2026, 3×140, 4×135, 5×130, 6×122,5 Apr 20, 7×110 Apr 11 … | Nothing you have ever lifted gets lost | 1.3 | new | A dense numeric ladder | **Strong** — reads as substance at any size |
| A3 | History mid-set | **Last three sessions** | What you did here before, without leaving the set. | [ExerciseHistoryView.swift:33](Repster/Features/Exercise/Views/ExerciseHistoryView.swift:33), History sub-tab, rest timer visible | Apr 29: 140×3 ★, 135×4 ★, 130×5 ★; Apr 20: 122,5×6 ★, 127,5×5, 132,5×4; Apr 11: 110×7 ★ | Your history is in the workout, not in a separate app | 1.3 | `exists` — `active-history.png` | Gold PR badges in a column | **Strong** |
| A4 | Lock Screen | **Rest timer, screen locked** | Live Activity and Dynamic Island keep the clock in reach. | [WorkoutLiveActivityLiveActivity.swift:84](WorkoutLiveActivity/WorkoutLiveActivityLiveActivity.swift:84), Lock Screen presentation, rest running | "Morning Workout" · 43:12 · Barbell Back Squat · Set 2/4 (working) · 2:57 remaining | You don't have to hold your phone between sets | 1.3 | new — Lock Screen capture, plus a Dynamic Island variant | A Lock Screen silhouette — instantly recognisable | **Strong** — the only frame that doesn't look like every other tracker |
| A5 | Five-year donut | **Five years of volume** | Every set you've logged, by muscle group. | [BreakdownTabView.swift:124](Repster/Features/Charts/Views/BreakdownTabView.swift:124), Breakdown / All | **5.0M kg** centre; Legs 39%, Back 25%, Chest 18%, Shoulders 8%; 11,345 sets · 114,667 reps · 556 workouts; May 20 2021 → May 2 2026 | This app holds a training career, not a week | 1.3 | new (flat, single device — the live one is inside an angled 4-up) | Donut + "5.0M kg" | **Strong** — the largest honest number the app owns |
| A6 | Session recap | **Then it adds up** | Duration, sets, volume and every PR, the moment you finish. | [WorkoutSummarySheet.swift:179](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:179), recap hero + exercise recap | 1:34:55 · 29 sets · 11.8k kg · "3 PRs this session"; 9 exercises listed with set counts | Logging pays off at the end of the session, not months later | 1.3 | new | "3 PRs this session" | **Strong** |
| A7 | Templates | **Start from a template** | Save a session once, then repeat it forever. | [TemplateListSheet.swift:289](Repster/Features/Templates/Views/TemplateListSheet.swift:289) | Arms 4 ex · 13 sets; Legs 6 · 12; Full Body 7 · 15; Upper Body 2 9 · 20 | You are one tap from training | 1.3 | new | Four coloured avatars | **Situational** — live BUILD PROGRAMS already does this, better headline; keep only if the template frame stays |
| A8 | Template targets | **Reps and RIR, planned** | Set a rep range and an RIR target before you walk in. | [CreateEditTemplateView.swift:418](Repster/Features/Templates/Views/CreateEditTemplateView.swift:418), one exercise expanded | Barbell Back Squat: 4 sets, ranges 5–8 / 5–8 / 5–7 / 5–7, RIR 3/3/2/1, rest 180 s | Programming lives in the template, so the workout is just execution | 1.3 | new | "5–8" and RIR chips | **Situational** — strong for the technical page, invisible on the broad one |
| A9 | Calendar | **A month of training** | Every session, tagged by the muscles you hit. | [CalendarView.swift](Repster/Features/Calendar/Views/CalendarView.swift) + [CalendarExerciseCard.swift:58](Repster/Features/Calendar/Views/Components/CalendarExerciseCard.swift:58), a day selected | March 2026, 26 selected; 11.8k kg · 9 exercises · 29 sets · 1:34:55; Chest Press Machine 5 sets with two ★ PR rows | Consistency is visible at a glance | 1.3 | new | Coloured dot grid | **Situational** — duplicates the live REVIEW HISTORY frame almost exactly |

### Group B — Differentiation: why this one and not Hevy

| # | Frame | Headline | Subtitle | Screen + state | Data required | Argument | Version | Capture | @320×480 | Strength |
|---|---|---|---|---|---|---|---|---|---|---|
| B1 | Descending targets | **Set 3 costs more** | Fatigue accumulates per set and decays with the rest you take. | [WeightSuggestionModuleView.swift](Repster/Features/Workout/Views/Components/WeightSuggestionModuleView.swift), four pending suggestions, descending | Barbell Back Squat: Set 1 125 kg, Set 2 122,5 kg, Set 3 120 kg, Set 4 117,5 kg — all for 5–8 reps | Nobody else prices set 3 differently from set 1 | 1.3 | new — must be produced by a real session with fatigue applied, not mocked | Four descending weights | **Strong** — the sharpest statement of the differentiator |
| B2 | The explanation line | **Easing off for fatigue** | The app tells you why the number moved. | [WeightSuggestionCardView.swift:163](Repster/Features/Workout/Views/Components/WeightSuggestionCardView.swift:163) — `contextualUserSummary` in the fatigue branch ([WeightSuggestionData.swift:848](Repster/Features/Workout/Models/WeightSuggestionData.swift:848)) | Set 3 · **120 kg** for 5–8 reps, with the literal string "Easing off slightly to manage session fatigue." | The mechanism is stated in the product, to the user, without Admin Mode | 1.3 | new — must be a state where `meaningfulFatigue` is true | The sentence itself | **Strong** — the honest, non-admin version of the fatigue claim |
| B3 | Rest as an input | **Cut rest, target drops** | Rest is an input to the next weight, not just a stopwatch. | [RestTimerView.swift:76](Repster/Features/Workout/Views/RestTimerView.swift:76) with `−30s` visible, suggestion card in the same frame | Timer at 2:57 with −30s / −15s / +15s / +30s; suggestion below it | The timer is wired into the model, not decorative | 1.3 | partial — `active-history.png` has the timer; needs a composite or a fresh capture with both | Timer ring + "−30s" | **Situational** — it is a before/after, which a still cannot show; this is the App Preview video, not a screenshot |
| B4 | Feedback loop | **Was the drop right?** | Grade the taper after a session and it adjusts per exercise. | [WorkoutSummarySheet.swift:556](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:556), feedback section expanded | Barbell Back Squat and Barbell Row rows, each with **Too much drop / About right / Not enough drop**; "About right" selected on one | The model asks you whether it was wrong — no other tracker does | 1.3 | new | Three labelled buttons | **Strong** — user-facing, shipped, and nobody proposed it |
| B5 | RIR column | **RIR is a column** | Weight, reps and RIR in one row. Warmups stay out of the estimates. | [SetTableView.swift:174](Repster/Features/Workout/Views/SetTableView.swift:174) with completed sets and RIR filled | 1: 122,5 · 8 · RIR 3 · ★ PR · ✓; 2: 120 · 8 · RIR 2 · ✓; 3: 117,5 · 7 · RIR 1 · ✓ | If you log RIR this is built for you; if you don't, keep scrolling | 1.3 | new — `active-sets.png` shows an empty table and cannot be used | Coloured RIR chips | **Strong** for the technical page, **weak** for the broad one — it is a deliberate filter |
| B6 | Rest sweet spot | **Longer rest, more reps** | Measured on your own sets, at your own weight. | [InsightRules.swift:83](Repster/Core/Services/InsightRules.swift:83) rendered as an [InsightCardView](Repster/Features/Insights/Views/InsightCardView.swift) with a two-bar comparison chart | Real firing: "Longer rest is buying you reps on Barbell Back Squat", bars "~90s" vs "~3.0 min" with the two rep means, methodology "18 timed rests at 120 kg" | The app found something in your data you would not have found | **1.4** | new — the rule has to fire on a real database | Two bars + the headline | **Strong** — the most differentiated single card in the app |
| B7 | Strength trend finding | **Up 6% in eight weeks** | Findings from your own training, not a generic tip feed. | [InsightRules+Progress.swift:72](Repster/Core/Services/InsightRules+Progress.swift:72) as an InsightCardView | "Your barbell back squat is up 6% over 8 weeks" with the series chart | Insights are measured, not motivational | **1.4** | new | The percentage | **Situational** — strong card, but A5 already argues progress |
| B8 | Peak sets | **Peak sets, not last** | One bad session doesn't reset your numbers. | [EmbeddedExerciseChartView.swift](Repster/Features/Charts/Views/EmbeddedExerciseChartView.swift) via the workout's Charts sub-tab, metric **Estimated 1RM**, range 1y | An **ascending** e1RM series with a rising trend line over ≥12 months | The capacity estimate is robust to a bad day | 1.3 | existing capture is **unusable** — `active-chart.png` has four points, a ↘ **0.9%** badge and a falling red trend line | Line + trend | **Situational** — the claim is true ([LoadPrescriptionService.swift:214](Repster/Core/Services/LoadPrescriptionService.swift:214)) but the screen that proves it is a chart of *outcomes*, and it must not be a declining one |
| B9 | Warmups | **Warmups never count** | Excluded from volume, PRs and every estimate — or included, your call. | [SetTableView.swift:313](Repster/Features/Workout/Views/SetTableView.swift:313) with two warmup rows dimmed above working sets, or [SettingsView.swift:712](Repster/Features/Settings/Views/SettingsView.swift:712) | Warmups 60×8, 80×5 dimmed; working 122,5×8 RIR 3 ★ PR | The numbers aren't polluted by the easy sets | 1.3 | new | Dimmed rows above bright ones | **Weak** alone — a qualifier, not a reason; better as B5's subtitle |

### Group C — Switching cost: you already log somewhere else

| # | Frame | Headline | Subtitle | Screen + state | Data required | Argument | Version | Capture | @320×480 | Strength |
|---|---|---|---|---|---|---|---|---|---|---|
| C1 | Import sources | **Strong, Hevy, FitNotes** | Bring the export you already have. | [ImportView.swift:87](Repster/Features/Settings/Views/ImportView.swift:87), idle state, Strong selected, unit picker visible | The three source tiles; "Strong exports don't include units — pick the one used in your export." | You don't have to abandon your history to try this | 1.3 | new | Three named tiles | **Strong** — highest-intent message in the category |
| C2 | Import result | **11,345 sets imported** | Your whole history, with PRs and stats rebuilt. | [ImportView.swift:372](Repster/Features/Settings/Views/ImportView.swift:372), completed state | Real counts from an actual import — Sets Imported, Workouts Created, Exercises Created, "Completed in N seconds". Do not invent these | The migration is done, not promised | 1.3 | new — requires running a real import first | The big count | **Strong** |
| C3 | Import preview | **See it before it lands** | Column mapping and sample rows before anything is written. | [ImportView.swift:232](Repster/Features/Settings/Views/ImportView.swift:232), preview state | Source: Strong · Units: Metric · Rows Found: 24,118; column mapping list; sample rows | Nothing is imported behind your back | 1.3 | new | Dense two-column list | **Weak** — busy, and C1/C2 make the same argument better |
| C4 | Backup | **Take it all with you** | A full backup file you can restore any time. | [ExportView.swift:26](Repster/Features/Settings/Views/ExportView.swift:26) or the restore preview at [ExportView.swift:166](Repster/Features/Settings/Views/ExportView.swift:166) | Restore preview card: Archive Version, Exported date, Workouts, Exercises, Sets, Date Range | Leaving is possible, so staying is a choice | 1.3 | new | An icon and a button — very little | **Weak** — and the copy must **not** say CSV (§0.2) |

### Group D — Trust and control: the model is yours

| # | Frame | Headline | Subtitle | Screen + state | Data required | Argument | Version | Capture | @320×480 | Strength |
|---|---|---|---|---|---|---|---|---|---|---|
| D1 | Model settings | **Tune it or off** | Recency window, default RIR and the fatigue model are all yours. | [PrescriptionSettingsView.swift:101](Repster/Features/Settings/Views/PrescriptionSettingsView.swift:101) — `defaultsSection`, `recencySection`, `fatigueSection`, Admin Mode **off** | Default Reps 8; Default RIR 2; Recency Window 6 weeks; Fatigue on; footer "How far back to look for performance data. Shorter windows adapt faster to strength changes." | The model is exposed, adjustable and switchable off — that is the trust claim | 1.3 | new — still the blocked capture from ad-kit concept 05 | Three labelled controls | **Strong** for the technical page |
| D2 | Formula picker | **Pick your 1RM formula** | Epley, Brzycki or Lombardi — the equations are on screen. | [FormulaPickerSheet.swift:25](Repster/Features/Settings/Views/Components/FormulaPickerSheet.swift:25) | The three rows with their literal descriptions: "weight × (1 + reps / 30)", "weight × 36 / (37 − reps)", "weight × reps^0.10" | The maths isn't hidden, and you get to disagree with it | 1.3 | new | Three names, formulae illegible | **Situational** — the argument is that equations exist, and *that* survives; the equations themselves do not |
| D3 | Self-grading model | **It grades its predictions** | Per-exercise error tracking that corrects the fatigue rate. | [FatigueLearningAdminView.swift:27](Repster/Features/Settings/Views/FatigueLearningAdminView.swift:27) | Applied Rate 1.80% (global baseline), Qualifying Workouts 11; One Arm Pulldown 2.10%, Seated Dip 2.40%, Chest Assisted Row 3.40%, each "Using 50% local learning" | The model measures its own error rather than asserting correctness | 1.3 | new — despite `screenshot-review.md` §5, there is **no** fatigue-learning capture in `marketing/source/`; the only such imagery is baked into the live composite | Percentages in a list | **Situational** — see §5: this screen is reachable only after enabling Admin Mode, which is off by default |
| D4 | Skip a session | **Skip PRs this session** | For hotel gyms and mismatched equipment. Suggestions still work. | [StartWorkoutSheet.swift:127](Repster/Features/Home/Views/StartWorkoutSheet.swift:127) | The "Count toward PRs" toggle off, with its footer copy | Your record book doesn't get polluted by a bad-equipment day | 1.3 | new | One toggle | **Weak** — real, thoughtful, and far too small for a slot |
| D5 | Training status | **This week vs yours** | Sets in the last 7 days against your own 8-week baseline. | [TrainingStatusCardView.swift:87](Repster/Features/Insights/Views/TrainingStatusCardView.swift:87) + [MuscleVolumePanelView.swift:91](Repster/Features/Insights/Views/MuscleVolumePanelView.swift:91) | "Busier week than your usual" · **24 SETS** · 8-week avg 12 · baseline meter; muscle rows Legs / Back / Chest / Shoulders with deltas | The comparison is to you, not to a population | **1.4** | new | "24 SETS" + meter | **Strong** — this is the frame Set A #6 wanted, with the file that renders it |
| D6 | Data boundary | **Your lifts stay here** | Weights, reps, notes and CSV contents are never sent. | [SettingsView.swift:1034](Repster/Features/Settings/Views/SettingsView.swift:1034) — the analytics footer | The literal footer: "Workout notes, exercise names, set weights, reps, CSV contents, and bodyweight values are never sent." | Local-first is stated precisely rather than as "privacy-first" hand-waving | 1.3 | new | A toggle and grey text | **Weak** visually — but the *sentence* is the strongest privacy copy in the repo; use it as a subtitle on C1 or C4 instead of spending a slot |
| D7 | Apple Health | **Counts toward your rings** | Finished workouts go to Health. Repster never reads it. | [AppleHealthSettingsView.swift:33](Repster/Features/Settings/Views/AppleHealthSettingsView.swift:33) | Sync Workouts on; Estimated Calories on; the write-only footer | Fits the rest of your iPhone, without taking your health data | **1.4** | new | Two toggles — nothing | **Weak** as a frame; it is a bullet in the description, not a screenshot |

### Duplicate arguments — do not ship together

- **A1 and B1 and B2** all argue "the app picks your weight". Ship exactly one as the lead.
  A1 for the broad page, B1 or B2 for the technical page.
- **A5, A9 and B7** all argue "your progress is visible over time". A5 wins on scale.
- **A7 and A8** both argue templates. A8 is A7 for a narrower reader.
- **C1, C2 and C3** are one argument in three states. C1 opens it, C2 closes it, C3 adds nothing.
- **B4 and D3** are both "the model checks itself". B4 is the user-facing one and is the
  better frame; D3 is the engineering evidence behind it.
- **B9 and B5** — fold B9 into B5's subtitle.

---

## 4. Frames nobody has proposed, and why they were missed

1. **A4 — the Lock Screen Live Activity.** Set A proposed a Live Activity frame but cited
   `RestTimerView`, the in-app sheet. The Lock Screen and Dynamic Island renders live in a
   separate target (`WorkoutLiveActivity/`), which a reviewer reading `Repster/Features/`
   never opens. It is the single most recognisable image the app can produce and it is on
   nobody's list.
2. **A2 — the rep-max ladder.** Both sets sent "PRs" to `RecentPRsView`, the three-row home
   teaser, because that is what the live START FAST frame shows. `ExercisePRsView` is a
   different, denser, far better screen and it never came up.
3. **A6 — the workout summary.** An entire post-session surface — recap, effort rating,
   exercise breakdown, save-as-template — that appears in no inventory, no critique and no
   proposed set. It is missed because it is a sheet that appears after `Finish`, so it
   never shows up while browsing tabs.
4. **B4 — the fatigue feedback buttons.** Missed for the same reason: it is inside the
   summary sheet, behind a disclosure. Both sets reached for `FatigueLearningAdminView`
   instead, which is the admin-only version of the same idea.
5. **B2 — the contextual explanation line.** `contextualUserSummary` emits one of four
   fixed sentences, one of which is literally about session fatigue. The live TRAIN
   SMARTER frame shows an *older* version of this copy, so anyone auditing from the
   rendered screenshots rather than from source could not know the current strings exist.
6. **B6 — the rest sweet-spot insight.** Insights got summarised in both sets as "sets per
   muscle vs baseline", which is one panel. There are **ten** implemented rules, and the
   rest/reps one is the most differentiated single card the app can draw.
7. **C2 — the import result screen.** Both sets proposed the import feature and pointed at
   `ImportView` generically. `ImportView` has five distinct states; the one that carries
   the argument is `completed`, and it is the only one with a number on it.
8. **D2 — the e1RM formula picker.** Three formulas with their equations printed in the
   row subtitles. Nobody mentioned it in any document.

---

## 5. Captures required before any of this renders

Current inventory is three real app captures and three site-scraped images
(`marketing/source/README.md`). Everything else below is new.

**Blocking constraints for the whole shoot**

- [ ] Recapture at **6.9"** (1320×2868). All six existing sources are 1206×2622 (6.3"),
      which is the wrong size for the frames `product-page.md` specifies.
- [ ] Use a database with real training history — the seeded values in
      `live-screenshots-inventory.md` are the reference. **No zero-rep sets.**
      `active-sets.png` currently ships an entirely zero-filled set table, which is where
      the live `50 kg × 0 reps` frame came from.
- [ ] **Admin Mode off** for every capture except D3. It leaks an `ADMIN` pill onto the
      Smart Suggestions header ([WeightSuggestionModuleView.swift:59](Repster/Features/Workout/Views/Components/WeightSuggestionModuleView.swift:59)),
      switches the suggestion row to a monospaced diagnostics style, and adds an
      `e1RM 134.2 kg` chip — none of which a normal user sees.
- [ ] Dark mode; clean status bar.

**Captures, in dependency order**

- [ ] `active-sets-filled.png` — Sets tab with completed sets carrying weight, reps and
      RIR. Unblocks **B5**, **B9**, and replaces the unusable `active-sets.png` table.
- [ ] `suggestions-descending.png` — four pending suggestions with descending targets in a
      real session. Unblocks **B1**.
- [ ] `suggestion-fatigue-line.png` — a suggestion whose `contextualUserSummary` is
      "Easing off slightly to manage session fatigue." Unblocks **B2**.
- [ ] `workout-summary.png` — the recap with a real PR count. Unblocks **A6**.
- [ ] `summary-fatigue-feedback.png` — same sheet, feedback section expanded. Unblocks **B4**.
- [ ] `exercise-prs.png` — the rep-max table. Unblocks **A2**.
- [ ] `live-activity-lockscreen.png` and `live-activity-island.png`. Unblocks **A4**.
- [ ] `charts-breakdown.png` — flat, single device, All range. Unblocks **A5**.
- [ ] `import-sources.png` and `import-complete.png` — the second requires actually running
      an import. Unblocks **C1**, **C2**.
- [ ] `prescription-settings.png` — still the blocked capture from ad-kit concept 05.
      Unblocks **D1**.
- [ ] `formula-picker.png`. Unblocks **D2**.
- [ ] `exercise-e1rm-chart.png` — a **rising** 12-month e1RM series. Unblocks **B8**;
      until it exists, B8 cannot be built, because the existing capture shows a decline.
- [ ] `fatigue-learning.png` — a real capture, not the composite. Unblocks **D3**.
- [ ] 1.4 only: `insights-status.png` (**D5**), `insight-rest-sweet-spot.png` (**B6**),
      `insight-strength-trend.png` (**B7**). Each needs the corresponding rule to fire on a
      real database, which cannot be forced from the UI.

---

## 6. What should stay off the page

| Thing | Why |
|---|---|
| The custom numeric keypad | It is a picture of typing. The live AND MORE… frame leads with it, in an ad for an app whose pitch is that logging is fast. |
| "AND MORE…", or anything like it | A slot that says you ran out of things worth naming. |
| **Fatigue Learning** as a hero frame | Reachable only after switching on Admin Mode inside Settings → Smart Suggestions ([PrescriptionSettingsView.swift:154](Repster/Features/Settings/Views/PrescriptionSettingsView.swift:154)), which is off by default. It is a troubleshooting screen — it has a red **Reset All** button, per-set audit rows and median error figures. Showing it as the product implies a default experience that no user has. If it ships, ship it once, deep in the set, and caption it as diagnostics. |
| Insight Gallery | Same gate ([SettingsView.swift:334](Repster/Features/Settings/Views/SettingsView.swift:334)). |
| "AI" of any kind | The AI Helper is: export a JSON context file, copy a prompt, paste it into ChatGPT, paste the response back ([TemplateListSheet.swift:484](Repster/Features/Templates/Views/TemplateListSheet.swift:484)). Advertising "AI workout builder" over that is a claim the screen cannot support. |
| Supersets | Grouped and coloured in the template editor, carried in the data, and **rendered nowhere during the workout**. A superset frame would sell something a user cannot see while training. |
| "BUILD PROGRAMS" | There is no Programs feature. The models exist; no view references them. The current headline names a capability the app does not have. |
| "CSV export" / "CSV in, CSV out" | Export is a Repster JSON archive. See §0.2. |
| The exercise count | 69 built-in exercises. Competitors advertise several hundred. Custom exercise creation is the answer to this question; the number is not. |
| The paywall or "5 free workouts" | The paywall is RevenueCat-hosted and remotely configured, so it isn't reproducible from this repo, and a screenshot of a price is not an argument for installing. |
| Reset App Data, Rebuild Stats, Restore Backup | Screens a user only sees when something has gone wrong. |
| Bodyweight log | Thin: a line chart and a list. It supports the bodyweight-factor and Health-calories features rather than standing alone. |
| The deload-readiness insight | "Your sessions are landing under your usual output" is the closest thing in the app to a recovery recommendation. It is factual about output and says nothing medical — but on a store page, next to a headline, it is the one card that could read as advice about your body. Keep it out of the frames; the guardrail in `ad-kit.md` §2 exists for exactly this. |
| `active-chart.png` as shot | A red ↘ **0.9%** badge and a falling trend line, on four data points. |
