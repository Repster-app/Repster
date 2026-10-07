# Sample History for New Users — Scoping

Status: scoped, not started. 2026-09-12. Targets 1.6. Checked against the code 2026-09-26 (§15).
**Scope decided 2026-09-28: v1 is Charts and Home › Recent. The Training Insights sample is a
follow-up** (§3). §12 lists the decisions still open.
Companion: `design/sample-history/` — seven phone screens (the five sample surfaces plus today's
empty Home and Charts for comparison), published at
https://claude.ai/code/artifact/507f6efd-85bc-4c45-a358-8ecb28ff11eb. The mockups are the visual
reference; the sketches below are a summary of them. The mockups' Insights screen and the Home
hook's "See an example" belong to the follow-up, not v1.

---

## 0. The short version

While someone has **no finished workout**, two surfaces show a clearly labelled, read-only
sample history instead of an empty state: **Charts** (all three sub-tabs) and **Home › Recent**.
The **Training Insights** screen gets the same treatment in a follow-up (§3). The sample matches the program they picked in onboarding
("this is what 8 weeks of Upper / Lower looks like"), and it disappears everywhere the moment their
first real workout is finished.

The sample lives in a **throwaway in-memory store** that the real chart code reads.
It never becomes a row in the user's database, so it cannot reach Smart Suggestions, PRs, the
fatigue model, backups, Apple Health, the free-workout quota or analytics workout counts.

Everywhere that *acts on* history rather than *showing* it stays real. That covers the active
workout, suggestions, Calendar, the week strip, Copy Previous, sharing and export.

---

## 1. Why, and a decision this reopens

From the 1.4 funnel (ONBOARDING_REDESIGN_SCOPING.md appendix, 57 onboarding starters):

- All 21 people who finished onboarding without starting a workout saw the empty Home.
- Median time from onboarding to first workout start is 0.0 minutes, so it is now or never.
- `freeWorkoutLimit` went from 5 to 10 on 2026-08-18 because Charts and Insights had nothing to show
  before the old limit ran out (`MonetizationService.swift:31`).

A new user is told Repster "learns what you can lift", then shown a screen with nothing in it. The
sample turns that promise into something they can look at before they have lifted anything.

**This reopens a recorded decision.** ONBOARDING_REDESIGN_SCOPING.md §9 Q2 (2026-09-04):
*"finish onboarding into Home, unchanged. No example data … Home gets its own pass later."* That
decision was about where onboarding lands, and it left Home for a later pass. This is that pass.
It does put example content on Home, so it needs an explicit yes (§12 Q1).

---

## 2. What a brand-new user sees today

Audited from source, on a store with the seeded exercise library and no workouts.

| Surface | Zero-history state | Where |
|---|---|---|
| Home › date header, week strip, Start card | Real; 7 empty days | `HomeView.swift:70-72` |
| Home › Monthly stats | **Not rendered** (`totalWorkouts > 0` guard) | `HomeViewModel.swift:283` |
| Home › Recent PRs | **Not rendered** | `HomeView.swift:169` |
| Home › Training Insights hook | "Training status · Builds as you log workouts" | `TrainingInsightsHookView.swift:85-101` |
| Home › Recent | One grey line: "Complete your first workout to see it here" | `HomeView.swift:288-293` |
| Charts › Breakdown | Pie icon + "No data for this period" | `BreakdownTabView.swift:179` |
| Charts › Workouts | Bar icon + "No data for this period" | `WorkoutsTabView.swift:155` |
| Charts › Exercises | "Select Exercises" prompt | `ExercisesTabView.swift:65` |
| Training Insights | Status card with no data; muscle panel and findings hidden | `InsightsView.swift:46, 91-148` |
| Calendar day detail | "No workout" | `CalendarWorkoutDetailView.swift:250` |
| Exercise › History / PRs | "No history yet" / "No PRs recorded yet" | `ExerciseHistoryView.swift:239`, `ExercisePRsView.swift:104` |
| Copy Previous sheet | "No workouts yet" | `CopyPreviousSheet.swift:148` |
| Templates | Populated if they picked a program; this is real data, not sample | `ProgramCatalogService` |

Two of Home's four customisable sections render nothing, and one renders a line of grey text.
The whole Charts tab is empty.

---

## 3. Where sample data belongs, and where it never goes

**The rule:** sample data may appear on screens that **show** history back to the user. It never
appears on screens that **act on** history. That means anything that prescribes a load, counts
toward something, leaves the device, or states a dated fact about the user's own week.

### Tier 1: build (v1)

| # | Surface | What the sample shows | Why it earns it |
|---|---|---|---|
| 1 | **Charts: all three sub-tabs** | Muscle-group donut, workouts-over-time bars, and an e1RM line for the program's two main lifts, preselected so a chart is drawn on arrival | The tab exists to show what history looks like. Because the real `ChartDataService` does the drawing (§6), every metric, time range and exercise pill works. No combination falls back to "No data for this period". |
| 2 | **Home › Recent** | 2–3 sample workout cards under an "Example history" header. Each opens a read-only detail view. | Replaces the one line most new users see. It is the first thing under the Start card. |

### Follow-up: Training Insights (not in v1)

**Decided 2026-09-28:** v1 ships Charts and Home › Recent only. Insights needs the most extra
machinery of the three surfaces: a wrapper service, the status handoff from Home, its own gate and
analytics suppression (§6.3, §6.4, §14 fix 2). It follows once v1 is out, on the same store.

| Surface | What the sample shows | Why it earns it |
|---|---|---|
| **Training Insights screen** | Status card ("usual week" meter), muscle volume panel, and the sides card when the program has unilateral lifts (Upper / Lower and Push / Pull / Legs only; §5) | Insights is the feature most starved at cold start. The "usual week" meter draws nothing until there are 3 weeks of baseline (`InsightsService.swift:631`). |
| **Home › Training Insights hook** | Subtitle "See an example", opening the sample Insights screen | Only makes sense once the sample screen exists. |

### Tier 2: cheap once the store exists; decide later

| Surface | Note |
|---|---|
| Home › Recent PRs and Monthly stats *inside* the sample block | These render "this month" and "last 14 days". They are fine inside a labelled block, but a separate sample section each makes Home three-quarters fake. See §12 Q4. |
| Insights findings | After the Insights follow-up. Blocked by a shared-state hazard (§6.3). Synthetic data tuned to pass the rule gates (`InsightRules.swift`: `minimumPairs = 12`, `minimumSets = 12`, …) is fragile. |
| Walkthrough pages | `HowItWorksPage.swift` describes screenshots. The same generator could render them later. |

### Never

| Surface | Why not |
|---|---|
| **Active workout**: previous values, Smart Suggestions, the embedded exercise chart (`ActiveWorkoutView.swift:323`) | Suggestions prescribe real weight to a real person. A sample 60 kg bench history must never set anyone's next set. **This is the hard line.** |
| **Week strip and Calendar** | Dated facts about the user's own days. A dot on last Tuesday says *you* trained last Tuesday. |
| **Home Training Insights hook bars** | It reports "this week". In v1 the hook stays as it is today ("Builds as you log workouts") and opens the real Insights screen. The follow-up swaps the subtitle for "See an example", still with no numbers. |
| **Copy Previous** | Copying a sample would write a real workout seeded with sample targets. |
| **Summary screen / share card** | It would put fake numbers on social media. |
| **Exercise detail History / PRs / chart** | The same chart component is embedded inside the active workout. Keep one rule, "no sample near a workout", and leave these empty. |
| **Export, Apple Health, CSV import dedupe, free-workout quota, review-prompt counter, walkthrough ceiling, `workout completed` analytics** | None of these read the sample store, so they cannot be reached. The isolation test in §10 pins that. |

---

## 4. What it looks like

Home, zero history, Upper / Lower picked in onboarding:

```
Saturday, Sep 12
Workout                                              ⚙
 MON  TUE  WED  THU  FRI  SAT  SUN                        ← real, empty
┌───────────────────────────────────────────────────┐
│ Start Workout                                   + │     ← real
└───────────────────────────────────────────────────┘

TRAINING INSIGHTS
┌───────────────────────────────────────────────────┐
│ ◌  Training status                                │
│    Builds as you log workouts                   › │     ← real, unchanged in v1
└───────────────────────────────────────────────────┘

EXAMPLE HISTORY                                  Hide
┌───────────────────────────────────────────────────┐
│ SAMPLE   Lower B               Week 8 · Day 4   › │
│ 4 exercises · 13 sets · 52 min                    │
│ 7,745 kg                            ● Back ● Legs │
└───────────────────────────────────────────────────┘
┌───────────────────────────────────────────────────┐
│ SAMPLE   Upper B               Week 8 · Day 3   › │
│ 5 exercises · 16 sets · 58 min                    │
│ 4,388 kg               ● Chest ● Back ● Shoulders │
└───────────────────────────────────────────────────┘
  Your first finished workout replaces these.
```

**Sample cards carry a position in the program, not a calendar date.** The week strip directly
above them is real and empty, so "Thursday, Sep 10" on a card would contradict the screen it sits
on. The dates still exist underneath — the charts need them — they are just not shown here.

Charts › Breakdown:

```
Charts
 [ Breakdown | Workouts | Exercises ]
┌───────────────────────────────────────────────────┐
│ ◐ Sample data: 8 weeks of Upper / Lower     Hide  │
└───────────────────────────────────────────────────┘
        ╭───╮     Legs        45%
      ╭─╯   ╰─╮   Back        24%
      │ 212k  │   Chest       13%
      ╰─╮ kg ╭╯   Shoulders    9%
        ╰───╯     Triceps      5%
                  Biceps       4%
  All · 31 workouts · 466 sets · 4,420 reps
```

Charts › Exercises opens with Barbell Bench Press and Barbell Back Squat already selected. It
shows two rising e1RM lines with the existing trend overlay, including one light week so the line
isn't implausibly straight.

Tapping a sample card opens the existing `CalendarWorkoutDetailView` with a Sample banner. The
toolbar has no delete, edit, share, save-as-template or exclude-from-PRs.

---

## 5. The sample dataset

**Length: 8 weeks, ending yesterday.** This is set by the consumers, not by taste:

- *For the Insights follow-up:* the status reads an 8-week baseline plus a 7-day current window
  (`InsightsService.swift:501-502`), but draws the "usual week" meter from 3 baseline weeks
  (`minimumBaselineWeeks`, `:631`). 8 weeks ending yesterday gives **7.0** baseline weeks, well
  clear of the minimum and what a settled user's meter looks like. Under about 4 weeks the meter
  stays empty, which is the feature we are trying to show. A *full* 8-week baseline would take
  9 weeks of sample; not worth the extra length. v1 has no Insights sample, but generating 8 weeks
  now means the follow-up needs no change to the generator.
- Home Recent PRs look back 14 days (`HomeViewModel.swift:302`). Charts default to month and 3-month ranges.
- Longer than 8 weeks starts to read as someone else's training log rather than an illustration.

**Schedule:** the picked program's days per week (3, 4 or 6; 5×5 alternates two sessions over
three days). It includes one missed session and one lighter week, so the chart lines
(and, in the follow-up, the Insights bands) show some variation.

**Content: matched to the picked program.** Sessions, exercises, set counts and rep ranges come
straight from `seed_programs.json`, the same file the onboarding picker uses. "Build my own"
falls back to Full Body.

- **The program choice is not saved today.** `OnboardingViewModel.finish()` materialises the
  templates and keeps `materialisedProgram` only in memory (`OnboardingViewModel.swift:38, 174-181`).
  Add one `UserDefaults` key, `onboardingSelectedProgramId`.
- For people who onboarded on 1.5 and still have zero history: infer the program from a template
  folder whose name matches a catalogue program. `materialise` names the folder after the program,
  or suffixes it on a collision. If nothing matches, fall back to Full Body.

**Loads:** a small starting-load table per exercise for an ordinary intermediate lifter, not the
user's own history and not an advanced lifter's. Progression is simple double progression: reach
the top of the rep range at the target RIR, then add one increment next session.

- **Do not run `LoadPrescriptionService` to generate it.** It is the learner. Running it writes
  fatigue rows and would tie the sample's shape to engine changes.
- Generate natively in the user's unit, snapped to that unit's increments. Imperial users see
  135 / 185 / 225 lb, not 132.3 lb converted from kg. Storage stays in kg like every other set:
  pick the round value in the user's unit, then store its kg equivalent.
- **Fill in the fields `SetService` normally derives at write time.** The sample is inserted
  directly, so it skips `SetService.computeEffectiveWeight` (`SetService.swift:590`) and the e1RM
  calculation. The generator must set `effectiveWeight` and `e1RM` (with `e1RMFormulaVersion`) on
  every set. Without `effectiveWeight`, `volume` is nil on every set (`WorkoutSet.swift:116-118`),
  so the Breakdown donut and every volume chart come up empty. Pull-up (Push / Pull / Legs only,
  `bodyweightFactor` 0.65) adds bodyweight × 0.65: use the bodyweight from onboarding if the user
  gave one, else a fixed nominal value.
- RIR 1–3 on working sets. On unilateral lifts, sides are logged equal. `SidesAnalysis.classify`
  then finds no differing sessions and returns `.even`, so the sides card reads Even rather than
  telling a stranger their left side seems weaker.
- **Only two programs have unilateral lifts** (matters for the Insights follow-up only). Upper / Lower has Bulgarian Split Squat. Push / Pull
  / Legs has Bulgarian Split Squat, Dumbbell Row and Hammer Curl. Full Body and 5×5 have none, so
  their samples show no sides card. That includes the Full Body fallback for "Build my own" and
  for 1.5 users whose program can't be inferred (§12 Q7).

**Deterministic:** a seeded generator keyed on program id and install date. The sample doesn't
reshuffle between launches (people compare screens), and tests can pin its output.

Content review works the same way as the programs: someone who trains checks the starting loads
and the progression before it ships.

---

## 6. Architecture

### 6.1 Options considered

**(a) Real rows in the user's store with an `isSample` flag: rejected.**

- **Every reader would need the filter.** There are about 39 `FetchDescriptor<Workout|WorkoutSet>`
  sites across 7 files (SetRepository alone has 19), and a missed filter fails silently.
- **Writers would ingest the rows.** PRService writes `PerformanceRecord`, StatsService writes
  `ExerciseStats`, and FatigueLearningService writes `FatigueObservation`. The suggestion engine
  reads the same set history (`LoadPrescriptionService.swift:225, 250`), so it would prescribe
  from fake sessions.
- **Backups would carry it.** `ExportService.swift:58-64` fetches every workout and set.
- **Removal means bulk-deleting workouts and sets.** That is the delete-ordering crash class this
  project has already fixed once.

The project rejected option (a) for exercise replace for the same reason: it *"fabricates history
in the new exercise's PR table, e1RM series, charts and fatigue model"*
(EXERCISE_REPLACE_AND_REORDER_DESIGN.md:578).

**(b) Hand-authored view fixtures: rejected for Charts.** The three tabs multiply metric × time
range × aggregation × filter × exercise selection. Every pill a user taps would need its own
fixture, or it would show "No data for this period" *inside the sample*, which is worse than today.
Hand-written numbers also drift from what the real code would draw.

**(c) Recommended: a throwaway in-memory store, read by the real services.**

1. Build a `ModelContainer` with `isStoredInMemoryOnly: true` from `ModelContainerSetup.modelTypes`.
   This is the same construction every test container already uses.
2. **Copy the user's real exercises into it with their real IDs** (`Exercise.init(id:…)`,
   `Exercise.swift:119-120`). Don't re-seed: `seed_exercises.json` has no IDs, so a re-seed mints
   new UUIDs. Copying keeps saved chart presets valid, since they store exercise IDs in
   `UserDefaults` (`ChartPreset.swift:10, 23, 52`). It also picks up renames and custom exercises.

   **Copy the user's `HealthProfile` too.** The sample-served services read settings from their
   own store, not the real one. In v1 that only keeps the warm-up settings of `StatsService` and
   `PRService` matching the user's; without a profile they create a default one
   (`StatsService.swift:71`, `PRService.swift:272`). The Insights follow-up needs it more:
   `InsightsService` falls back to `.metric` without one (`InsightsService.swift:671, 717`), so an
   imperial user would see metric Insights.
3. Insert the generated `Workout` and `WorkoutSet` rows in **one context, saved once**, before any
   reader touches the store.
4. Rebuild PRs and stats against the sample store, so PR and stats rows exist for the charts
   that read them. Call `PRService.rebuild(for:)` and `StatsService.rebuild(for:)`
   (`PRService.swift:459`, `StatsService.swift:70`) once per exercise the sample uses: 5 to 21,
   depending on the program. **Not** `rebuildAll()`: both loop `exerciseRepo.fetchAll()`, the whole
   library (69 seeded exercises plus custom ones), so most of ~140 calls would rebuild exercises
   the sample never touches. Both paths go only through repositories and have no outside side
   effects.
5. Create `RepositoryContainer(modelContainer: sampleContainer)` (`RepositoryContainer.swift:21`)
   and build from it **only** `ChartDataService`, `StatsService` and `PRService`. v1 never builds
   a sample-backed `InsightsService`. In the follow-up it takes the model container itself
   (`InsightsService(modelContainer:)`, `ServiceContainer.swift:171-173`), and reaches screens only
   inside `SampleInsightsService` (§6.3).
   **Never construct a `ServiceContainer` for the sample.** Its init wires `SubscriptionService`,
   `AccessControlService` and `HealthKitService` (`ServiceContainer.swift:46-47, 102`).
6. Inject those services into the screens. The three view models already take their data services
   by protocol (`HomeView.swift:34-56`, `ChartsTabView.swift:17-23`, `InsightsView.swift:14-22`).
   The environment `ServiceContainer` stays real, so analytics calls in the views keep going to the
   real analytics service, which is what we want.
7. Disposal is dropping the reference. There is no delete path, no schema change and no migration.

### 6.2 Home does not need services at all

Home's recent cards can be built straight from the sample store's repository snapshots with
`WorkoutAggregateSummary.summarize`. It is pure and is already what `HomeViewModel.swift:366` calls.

The read-only detail reuses `CalendarWorkoutDetailView`, which takes `[WorkoutDetail]` values
(`WorkoutDetailFromHomeView.swift:53-62`) built with `ExerciseGroup.build`, also pure
(`CalendarViewModel.swift:34`). A new `SampleWorkoutDetailView` builds the same value and passes
`nil` for the five optional actions: save as template, edit, delete, share and edit progression.
`onExerciseTapped` is not optional (`CalendarWorkoutDetailView.swift:21`), so it gets a no-op, and
the exercise rows must not look tappable (§6.5: no navigation from sample into real Exercise
detail).

### 6.3 The one hazard in reusing InsightsService (follow-up only)

**Not in v1.** v1 never builds a sample-backed `InsightsService`, so nothing in this section can
happen in it; the isolation test (§10) still checks the two keys. It is kept for the follow-up.

`InsightsService` keeps state in **`UserDefaults.standard`**: the last analysis signature and
per-rule refire timestamps (`InsightsService.swift:170-171, 202-206, 416-425`). If a sample-backed
instance called `refreshIfNeeded()`, it would overwrite the real instance's state. That would
re-run the real analysis and could suppress real findings behind refire intervals.

`fetchTrainingStatus()` and `fetchSidesStatus()` don't touch `UserDefaults` (`:214-230`). Only
`refreshIfNeeded()` and the `runAnalysis` it triggers write the keys.

**But the screen doesn't call just those two.** `InsightsViewModel.load()`
(`InsightsViewModel.swift:48-92`) calls `fetchActiveInsights()`, both status fetches,
`refreshIfNeeded()` (`:76`) and `markAllSeen()`. Hand it a sample-backed `InsightsService` as the
code stands, and the first open overwrites both keys.

So the sample reaches the screen through a small wrapper, `SampleInsightsService:
InsightsServiceProtocol`. It forwards `fetchTrainingStatus()` and `fetchSidesStatus()` to the
sample-backed instance and answers everything else with nothing: `refreshIfNeeded()` returns
`false`, `fetchActiveInsights()` returns `[]`, `newInsightCount()` returns 0, and `markAllSeen()`,
`snooze` and `ruleDiagnostics` do nothing or return empty. The protocol has eight methods, so the
wrapper is small. The guarantee lives in the type, not in a flag the view model has to remember,
and `InsightsViewModel` needs no change.

The findings section then stays hidden in sample mode, which is already how cold start behaves
(`InsightsView.swift:91-93`). Sample findings would need a `UserDefaults` suite injected into
`InsightsService` first.

Two things stay real:

- **Home's insights service.** `HomeViewModel.loadInsightsSummary()` also calls
  `refreshIfNeeded()` (`HomeViewModel.swift:141`), which is right against the real store. The
  hook's sample subtitle (§3) is a view change and needs no sample service.
- **Home's status must not reach the sample screen.** Home opens Insights with
  `initialStatus: viewModel.trainingStatus` (`HomeView.swift:117-120`), and `load()` skips its own
  status fetch whenever it is handed one (`InsightsViewModel.swift:55-59`). In sample mode that
  status is the real, empty one, so the screen would show an empty status card above a sample
  sides card. Pass `initialStatus: nil` in sample mode.

### 6.4 The gate

`SampleHistoryGate` shows the sample when the user has **zero completed workouts** and hasn't
pressed Hide. It is data-driven, so there is no "has ever finished a workout" flag to keep in sync.

| Surface | Real-is-empty test |
|---|---|
| Home | `recentWorkouts.isEmpty`, already computed |
| Charts | The same shared "has a completed workout" count. **Not** `fetchEarliestCompletedWorkoutDate()`, which loads every workout (§14, fix 3) |
| Insights (follow-up) | The same shared count. **Not** `TrainingStatus.hasData`, which turns true at the first ticked set (below) |

- **One rule on every surface: the sample shows until the first workout is finished.** Real Charts
  include in-progress ticked sets (`ChartDataService.swift:61-62`), but the gate counts completed
  workouts only. Sets ticked during the first workout therefore appear when it is finished. An
  earlier draft said Charts turned real at the first ticked set; that was wrong (§14).
- **Insights has the same trap (follow-up).** `TrainingStatus.hasData` is `historyStart != nil || sawAnySet`
  (`InsightsService.swift:624`). `historyStart` comes from `earliestLoggedSetDate()` (`:686`),
  which checks set completion with no workout-status filter. Gating on it would drop the Insights
  sample at the first ticked set of the first workout while Home and Charts kept theirs. An
  earlier draft of this table did exactly that (§15).
- **One Hide button hides every surface.** One `@AppStorage` key; three separate dismissals would
  be nagging.

### 6.5 Labelling and interaction rules

- Every sample surface has a visible **Sample** pill and a one-line banner.
- The pill reuses the PR badge's shape — 9pt bold, 4pt radius, a 20% border — in the app's slate
  `stale` token. That token already means archival or lower-confidence rather than warning, which
  is exactly what a sample is.
- Every sample card, chart and banner also carries a **dashed slate border**, so colour is never
  the only signal and the marking survives greyscale.
- VoiceOver reads "Sample:" before each sample card and chart.
- Sample is **read-only**: no delete, edit, share, save-as-template, copy or PR exclusion, and no
  navigation from a sample chart into the real Exercise detail.
- Copy on every sample surface says the same thing: "Your first finished workout replaces this."

### 6.6 Cost

8 weeks × 3–6 sessions × 4–5 exercises × 3–4 sets comes to about 300–600 sets. Build lazily off
the main actor the first time a sample surface appears, keep it for the app session, and rebuild
when the unit preference changes. PR and stats rebuilds cover only the sample's own exercises
(§6.1, step 4). Measure the build, rebuilds included, on the oldest supported device.

---

## 7. Changes by layer

**New**

| File | Role |
|---|---|
| `Core/Sample/SampleHistoryGenerator.swift` | Pure. Takes (program, exercise snapshots, unit, bodyweight, reference date, seed) and returns sample workouts as values, with `effectiveWeight` and `e1RM` already set (§5) |
| `Resources/sample_history_loads.json` | Starting load and increment per exercise name, in kg and lb. Names must match `seed_exercises.json`. |
| `Core/Sample/SampleHistoryStore.swift` | Actor. Builds the in-memory container, copies exercises and the health profile, inserts, rebuilds PRs and stats for the sample's exercises, exposes the read services |
| `Core/Sample/SampleHistoryGate.swift` | Show/hide rule and the Hide key |
| `Features/Shared/Views/SampleDataBanner.swift` | Pill and banner |
| `Features/Home/Views/SampleHistorySection.swift` | Home block |
| `Features/Home/Views/SampleWorkoutDetailView.swift` | Read-only detail on `CalendarWorkoutDetailView` |

**Changed**

| File | Change |
|---|---|
| `HomeView` / `HomeViewModel` | Branch the Recent section (`HomeView.swift:288-293`). The Insights hook is unchanged in v1 |
| `ChartsTabView` / `ChartsTabViewModel` | Swap `chartDataService` when the gate says sample; add banner; preselect two lifts on Exercises; no workout drill-down from sample data (§14, fix 4) |
| `OnboardingViewModel.finish()` | Save `onboardingSelectedProgramId` |
| `SettingsService.resetAllAppData()` → `clearStoredAppState` | Clear the Hide key too; a reset means starting fresh |
| `AnalyticsServiceProtocol` | Changes described in §8 |

**Follow-up (Insights), not in v1**

| File | Change |
|---|---|
| `Core/Sample/SampleInsightsService.swift` (new) | Wrapper that forwards only the two status fetches; every other method is a no-op (§6.3) |
| `HomeView` Insights destination (`HomeView.swift:117-120`) | In sample mode, pass `SampleInsightsService` and `initialStatus: nil` (§6.3) |
| `TrainingInsightsHookView` | "See an example" subtitle in sample mode (§3) |
| `InsightsView` | Banner; sample-aware analytics (§14, fix 2). `InsightsViewModel` is unchanged (§6.3) |

No schema change and no migration. `ModelContainerSetup.createContainer()` is untouched.

---

## 8. Analytics

**Keep the existing empty-state series readable.** `empty state shown` fires for Home and Charts
(`HomeView.swift:274-279`, `ChartsTabView.swift:63-68`). The Charts trigger is
`breakdownHasData == false`, and in sample mode the breakdown *has* data, so the event would stop
firing. Compute the trigger from the **real** service, and add `sample_shown: true|false` so the
series stays comparable across the release.

New events:

- `sample history viewed` with `screen` (home / charts; insights joins in the follow-up), once per view lifetime
- `sample workout opened`
- `sample history hidden` with `screen`

**Measuring it:** activation (onboarding completed → first workout started and finished). This hits
the same limit as the onboarding redesign: 57 people can only detect roughly a doubling
(ONBOARDING_REDESIGN_SCOPING.md §4.6). **Ship on the reasoning** and read the numbers
directionally. The secondary check is whether first sessions reach Charts more often.

The sample holds no personal data, so session replay needs no masking change.

---

## 9. Edge cases

| Case | Handling |
|---|---|
| "Build my own" picked | Full Body sample; banner reads "a sample full-body program". In the Insights follow-up, no sides card (§5) |
| Onboarded on 1.5, choice not saved | Infer from template folder name, else Full Body (§5) |
| Program exercise deleted or renamed | Skip it; the same rule as `materialise` (ONBOARDING §6). Never fail the sample. |
| Imperial units | Round lb values with lb increments, stored as kg. Charts and Home format with the app's own unit setting, as they do today |
| Unit changed while the sample is showing | Rebuild the store |
| Mid first workout | Home shows the resume card and keeps the Recent sample. Charts keeps the sample too; nothing is finished yet. Both gate on completed workouts (§6.4). |
| Finishes first workout | Everything goes real on the next load. Charts show one data point, which is honest but a steep drop; see §12 Q2. |
| Deletes their only workout | Sample returns unless Hidden (the gate is data-driven) |
| Reset all data | Sample returns; the Hide key is cleared |
| Imported CSV history | Never shown; they have history |
| Paywall | Browsing the sample is never a workout, so it can't touch the quota. Nothing to gate. |

---

## 10. Tests

**Unit**

- **Isolation (the highest-value test).** Build the sample store, browse every sample service, then
  assert the real container's counts of `Workout`, `WorkoutSet`, `PerformanceRecord`,
  `ExerciseStats`, `FatigueObservation` and `InsightRecord` are unchanged. Also assert that
  `insightsLastAnalysisSignature` and `insightsLastFiredByRule` in `UserDefaults` are untouched.
  v1 builds no sample `InsightsService`, so this pins that nothing reached one. In the follow-up,
  drive Insights through `InsightsViewModel.load()` with `SampleInsightsService`, not just the two
  status fetches, so the `refreshIfNeeded()` path is covered.
- The generator is deterministic: same seed, same output.
- Every program in `seed_programs.json` generates a sample whose exercises all resolve, and every
  name in `sample_history_loads.json` resolves against `seed_exercises.json`.
- Loads are snapped to increments in both units. No set is dated today or later. Every set is
  completed and has data. Every set has `effectiveWeight` and `e1RM`, and Pull-up's
  `effectiveWeight` includes bodyweight.
- Charts over the sample store return data for every `WorkoutsTimeRange` and for the Breakdown
  week, month, year and all ranges. The two preselected lifts have at least 6 points each.
- *Follow-up:* Insights over the sample store: `hasData == true`, `baselineSets != nil` (about 7 baseline
  weeks), muscles non-empty. With an imperial profile, the status reads imperial. Opening
  Insights from the sample hook shows the sample status, not Home's real one.
- Gate:
  - zero completed workouts → sample
  - sets ticked in an in-progress first workout → still sample, on Home and Charts
  - one completed workout → real
  - Hidden → real empty state
  - imported history → real

**On device**

- Fresh install → onboarding → Home shows the sample → finish a short workout → the sample is gone
  everywhere.
- The free-workout counter is unchanged after browsing the sample.
- Export produces an empty archive.
- Nothing is written to Apple Health.
- VoiceOver reads "Sample:".

---

## 11. Build order

| PR | Contents | Depends on |
|---|---|---|
| **PR1** | Generator (including `effectiveWeight` and `e1RM`), load table, determinism and catalogue tests. Pure code, no UI. | — |
| **PR2** | `SampleHistoryStore` (exercises and health profile copied, per-exercise rebuilds) and the isolation test | PR1 |
| **PR3** | Gate, Hide key, save the onboarding program id | — |
| **PR4** | **Charts**: service swap, banner, preselected lifts. The biggest payoff, so it ships first. | PR2, PR3 |
| **PR5** | Home sample block + read-only detail | PR2, PR3 |
| *PR6 (follow-up)* | *Insights status, muscle panel and sides, through `SampleInsightsService` with `initialStatus: nil`; hook subtitle* | *PR2, PR3* |
| **PR7** | Analytics, including the `sample_shown` property on `empty state shown` | PR4, PR5 |

**v1 is PR1–PR5 and PR7.** PR6 is the Insights follow-up. It needs only PR2 and PR3, so it can land
in any later release without touching v1's code.

The long poles are PR1's content (starting loads and progression, reviewed by someone who trains)
and PR2's isolation guarantees. PR4–PR6 are mostly wiring once the store exists.

---

## 12. Open questions

1. **Reopen the 2026-09-04 "no example data" decision for Home?** **Decided 2026-09-28: yes.**
   Home › Recent is in v1. That decision covered the onboarding landing and left Home for a later
   pass.
2. **When does it disappear?**
   - *Recommended:* at the first finished workout.
   - *Alternative:* after N workouts (for example 3), so Charts don't drop to a single dot.
   - Mixing sample and real data on one screen is ruled out either way.
3. **Program-matched or one fixed sample for everyone?** Recommended: program-matched. It shows
   *their* plan, and the generator makes it no more work than a fixed sample.
4. **Home: Recent cards only, or also sample Recent PRs and Monthly stats inside the same block?**
   Recommended: Recent only in v1.
5. **Insights findings?** Moot for v1, which has no Insights sample. For the follow-up the
   recommendation stands: no findings. They need the `UserDefaults` injection first, and synthetic
   data tuned to fire rules is fragile.
6. **Real numbers or unit-less shapes?** Recommended: real numbers in the user's unit. A chart with
   no values doesn't show what the feature does.
7. **No sides card for Full Body or 5×5?** Moot for v1, which has no Insights sample. For the
   follow-up: neither program has a unilateral lift, and Full Body is also the fallback (§5).
   Recommended: accept it. Adding a unilateral accessory to those samples would show a program the
   user didn't pick.

---

## 13. Not in scope

- Sample data in the active workout, Calendar, week strip, Exercise detail, Copy Previous or
  sharing (§3, never).
- **Follow-up, not v1:** the Training Insights sample and the Home hook's "See an example"
  (§3, §6.3, PR6).
- A paywall that shows the sample charts.
- Reusing the generator behind a DEBUG launch argument to render App Store screenshots from
  consistent data. It is a natural follow-on, and the v2 screenshot set in
  `marketing/generated/app-store-v2` would benefit, but it is separate work.

---

## 14. Safety review (2026-09-13)

The question: can this touch an existing user's data, and does the sample always go away when
it should? This section checks the code itself, not what the design says it intends.

### Verified safe

| Risk | Evidence |
|---|---|
| Sample rows reaching the user's store | Every write the design makes goes to the sample container's own context: the inserts and the PR and stats rebuilds. The only shared state among the reused services is InsightsService's two `UserDefaults` keys (§6.3), and v1 doesn't reuse InsightsService. PRService, StatsService, ChartDataService and the repositories have no statics, NotificationCenter traffic or singletons. |
| Two containers in one process | This already happens on every test run. RepsterTests is hosted in the app (`TEST_HOST = Repster.app`), and the app builds its on-disk container at launch with no test detection. Twenty test files then create in-memory containers alongside it. |
| iCloud syncing a second store | `Repster.entitlements` grants HealthKit only. There is no iCloud container, so SwiftData has nothing to sync to. Still set `cloudKitDatabase: .none` on the sample configuration, so adding iCloud later can't change this. |
| Quota, review prompt, Apple Health, walkthrough counter | All of these fire from `finishWorkout` or from closing the active-workout screen. The sample never creates a workout, so none of them can run. |
| Export | `ExportService` reads only the real container. |
| Who counts as having no history | `WorkoutStatus` has exactly two cases, `inProgress` and `completed`. CSV import writes `.completed` (`ImportService.swift:119`). Backup restore copies each workout's archived status (`ExportService.swift:503`). Imported and restored users therefore never see the sample. |
| Copying exercise IDs | No model uses `@Attribute(.unique)`, and the two stores are separate, so the same ID in both is allowed. |
| Existing users with history | The sample store is built only when a gate passes. These users pay for the gate check and nothing else, and the gate must be cheap (fix 3). |
| Existing users who never finished a workout | They will see the sample after updating. This is intended: they are in the same position as a new install. |

### Must fix before this ships

These are design gaps; the code doesn't have them yet only because the feature isn't built.

1. **Charts never reloads after a workout.**
   - Home refreshes when the workout screen closes (`homeRefreshTrigger`, `ContentView.swift:292, 309`), but Charts is passed nothing.
   - Each Charts sub-tab loads only while `chartData == nil` (`BreakdownTabView.swift:84-88`, `WorkoutsTabView.swift:121-125`).
   - **Consequence:** as written, someone who sees the sample, finishes their first workout and returns to Charts would **still see the sample until they relaunch**.
   - **Fix:** give Charts the same refresh trigger as Home, and re-run the gate on it.
   - This staleness exists today for every user, separately from this feature.
2. **Sample interactions would count as real Insights usage** (Insights follow-up).
   - `InsightsView` fires `insightsViewed` on every open, with `hasBaseline`, `sidesState` and `findingCount` (`InsightsView.swift:82-87`).
   - It also fires `musclePanelExpanded`, `sidesGroupOpened` and `sidesExerciseOpened`.
   - **Consequence:** in sample mode these would report a baseline the user does not have.
   - **Fix:** every event fired from a sample surface either carries `sample: true` or is suppressed. §8 only covered `empty state shown`. In v1 the same rule covers the Home and Charts events.
3. **Don't use `fetchEarliestCompletedWorkoutDate()` as a gate.**
   - It fetches every workout, sorts them, and filters in memory (`WorkoutRepository.swift:101-107`).
   - **Consequence:** a full-history load on every check, for exactly the users who will never see the sample.
   - **Fix:** use one shared, cheap "has a completed workout" count for every sample surface.
4. **Three navigation paths would open a sample workout using real services.**
   - Home routes by `UUID` into `WorkoutDetailFromHomeView`, which loads from the real store and has a delete menu.
   - The Workouts tab does the same in **Per Workout** mode: each data point is a `NavigationLink(value: workoutId)` into a `navigationDestination(for: UUID.self)` built on real services (`WorkoutsTabView.swift:95-99, 112-119`). An earlier draft missed this one (§15).
   - The Exercises tab's **View Workout** button opens the same view (`ExercisesTabView.swift:104-123, 154-177`).
   - **Consequence:** a sample ID finds nothing in the real store, so the result is a blank screen, not data loss.
   - **Fix:** give sample mode its own route type. Don't wrap sample data points in a link on the Workouts tab. Hide View Workout, or point it at the sample detail view.
5. **Reset must discard the sample store.**
   - `resetAllAppData` re-seeds the library, which gives every exercise a new ID.
   - **Consequence:** a sample store built before the reset would reference IDs that no longer exist.
   - **Fix:** discard it on reset, alongside clearing the Hide key (§7).
6. **Leaving sample mode clears the Exercises preselection.**
   - The preselected lifts live in `selectedExercises`, in memory.
   - **Fix:** clear them when the gate flips, so real Charts don't open on lifts the user may never have done.

### Tests this adds to §10

- With Charts already opened, finish a first workout: Charts shows real data with no relaunch.
- Every analytics event fired while the sample is on screen carries `sample: true`.
- Reset with the sample store built: the next sample render uses the new exercise IDs.
- Opening a sample workout from Home, from a Per Workout data point, or through View Workout never calls the real `WorkoutService`.

### What this review can't prove

I read the reused services for shared state, but not every transitive call. What proves it is the
isolation test in §10: build the sample, browse every sample screen, and assert the real store and
the Insights `UserDefaults` keys are unchanged.

(An earlier draft made this test conditional on the iOS 17 cross-actor write race. The minimum
deployment target was raised to 18.0 on 2026-09-13, so that constraint is gone. Writing the sample
store in one context and saving before any reader exists is still the right shape.)

---

## 15. Code check (2026-09-26)

Every file and line reference above was re-read against the code. Most held exactly: the 39
fetch sites, the 20 in-memory test containers, the entitlements, the Insights `UserDefaults`
keys and the program shapes. These did not, and are corrected in place. Since the 2026-09-28 scope
decision, rows 1–3 and 9, and the Insights half of row 5, apply to the Insights follow-up.

| # | The doc said | The code says | Fixed in |
|---|---|---|---|
| 1 | Gate Insights on `TrainingStatus.hasData` | That flag turns true at the first ticked set, so Insights would drop the sample mid-first-workout while Home and Charts kept it. All three now share the completed-workout count. | §6.4, §10 |
| 2 | The sample calls only the two status fetches | `InsightsViewModel.load()` also calls `refreshIfNeeded()`, which writes both shared `UserDefaults` keys. Now enforced by `SampleInsightsService`. | §6.3, §7, §10, §11 |
| 3 | (not covered) | Home hands its own status to Insights, and the view model then skips its fetch. In sample mode that status is the real, empty one. Pass `initialStatus: nil`. | §6.3, §7, §10, §11 |
| 4 | Two navigation paths into real workout detail | Three: the Workouts tab links to it in Per Workout mode. | §14, fix 4 |
| 5 | Copy the user's exercises | Copy the health profile too. Insights, stats and PRs read settings from their own store; without it an imperial user sees metric Insights. | §6.1, §7, §9 |
| 6 | (not covered) | Direct inserts skip `SetService`, so the generator must set `effectiveWeight` and `e1RM` itself, or every volume figure is empty. | §5, §7, §10, §11 |
| 7 | Run `rebuildAll()` for PRs and stats | Both loop the whole library. Rebuild per sample exercise. | §6.1, §6.6 |
| 8 | Shorter than 8 weeks leaves the meter empty | The meter needs 3 baseline weeks; 8 weeks gives 7.0. The length stays; the reason changed. | §3, §5 |
| 9 | Sides card from Bulgarian Split Squat and Dumbbell Row | Hammer Curl too, and only Upper / Lower and Push / Pull / Legs have any. Full Body (also the fallback) and 5×5 show no sides card. | §5, §9, §12 Q7 |
| 10 | The sample detail passes `nil` for every action | `onExerciseTapped` isn't optional; it gets a no-op. | §6.2 |
| 11 | Build `InsightsService` from the `RepositoryContainer` | It takes the model container directly. | §6.1 |
| 12 | `fetchEarliestWorkoutDate()`; `OnboardingViewModel.swift:156-163`; `ExerciseGroup.build` at `:244` | `fetchEarliestCompletedWorkoutDate()`; `:38, 174-181`; `CalendarViewModel.swift:34` | throughout |
