# Repster — feature scoping brief

Handoff document for scoping the next round of features. Written 2026-08-08 against branch `NewMain`.

Everything under "What exists today" was verified by reading the code, not assumed. File paths and line numbers are accurate as of this date. Items under "What's missing" were confirmed absent by search.

---

## Project constraints that apply to every item below

Read these first — they change how several of these features have to be built.

- **Deployment target is iOS 17.0** (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`). Anything requiring iOS 18+ APIs (e.g. controls, some interactive-widget behaviour) needs either an availability gate or a deployment bump.
- **Targets today:** `Repster` (app), `WorkoutLiveActivityExtension` (widget extension — currently Live Activity *only*), `RepsterTests`. There is no watchOS target and no WidgetKit timeline widget.
- **New files must be hand-registered in `project.pbxproj`.** The project uses explicit file references with short IDs rather than folder groups. Adding a file to disk is not enough; it will not compile until it is registered. Budget time for this on every item.
- **SwiftData + `@ModelActor` repositories.** There is a known crash class here: passing live main-context model objects into a `@ModelActor` repository caused the `EXC_BAD_ACCESS` that shipped in 1.3. Pass IDs across the actor boundary and re-fetch inside, never live models.
- **Monetization is RevenueCat** (`Core/Services/MonetizationService.swift`), entitlement identifier `"Repster"`, with a free tier of 5 workouts (`freeWorkoutLimit = 5`) before `paywallRequired`. Every new feature needs an explicit decision: free, or behind the entitlement.
- **Units are a user preference**, not a constant. `HealthProfile.unitPreferenceRawValue` is metric/imperial. Anything that renders a weight — share cards, widgets, the Watch app — must respect it.
- **The app is live on the App Store** (since 2026-05-21). All of this is post-launch work on a shipped codebase with real users and real data, so migrations matter.

### ~~⚠️ Constraint that conflicts with the supersets request~~ — RESOLVED 2026-08-08

**The "don't change workout-logging code" constraint is lifted.** It was never an architectural boundary — it was a guardrail to stop AI making unrelated changes to `Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` and `Core/Services/SetService.swift`. Relevant, scoped changes to those files are fine.

Consequences for this document:
- **Item 7 (supersets) is unblocked.** Option (b) auto-advance, as recommended below, can proceed.
- **Item 6 (deload)** is unaffected — still build it as an Insights rule.
- Insights Phase 0 (populating `WorkoutSet.startedAt`) is re-doable whenever it's worth the effort.

There is a related dormant issue: `WorkoutSet.startedAt` exists on the model (`Data/Models/WorkoutSet.swift:15`) but is **never populated**, because that was part of the reverted Phase 0. Several features would benefit from real per-set timing. If the logging code opens up for supersets, populating `startedAt` in the same pass is cheap and unlocks better rest analytics.

---

## 1. Shareable workout summary card — *your top pick*

**Sizing: S.** The cheapest item on this list and the one with the clearest payoff.

### What exists today
- `Features/Workout/Views/WorkoutSummarySheet.swift` — the sheet shown on Finish. Already presents stats, title, notes, session effort (1–10), and per-exercise fatigue feedback.
- `WorkoutSummaryData` (`ActiveWorkoutViewModel.swift:19`) already computes everything a card needs: `date`, `duration`, `totalSets`, `primaryMetric`, `exerciseSummaries[]`, `prsHit`.
- `ExerciseSummary` (`ActiveWorkoutViewModel.swift:29`) per exercise: `exerciseName`, `setCount`, `bestWeight`, `bestReps`, `hadPR`.
- A `UIActivityViewController` SwiftUI wrapper already exists twice and can be reused or lifted into a shared component: `Features/Settings/Views/ExportView.swift:349` and `Features/Templates/Views/TemplateListSheet.swift:989`.
- Brand blue is `#5B8DEF`; design tokens live in `Core/Extensions/DesignTokens.swift`.

### What's missing
- No `ImageRenderer` usage anywhere in the codebase — nothing currently rasterizes a SwiftUI view to an image.
- No `ShareLink` usage — the two existing share paths go through `UIActivityViewController` with file URLs (export/template sharing), not images.
- No card layout, no branding treatment for shared images.

### Scope
- A `WorkoutShareCardView` — a fixed-aspect SwiftUI view (1080×1920 for stories, and/or 1080×1080 square) rendering headline stats, date, duration, PR callouts, and Repster branding.
- Render via `ImageRenderer` at `scale = 3`, hand the `UIImage` to the existing share wrapper or a `ShareLink`.
- Entry point: a Share button on `WorkoutSummarySheet`, plus ideally the same action from a past workout in history/calendar detail so people can share retroactively.

### Decisions to make
- **Which stats make the card?** Volume-heavy cards read as bragging; PR-focused cards read as milestones. A card that says "3 PRs" is more shareable than one that says "12,400 kg".
- **One layout or a small picker?** Story vs square vs feed.
- **Does it include the exercise list?** Full breakdown is informative but visually noisy and leaks more personal data than some users want.
- **Free or gated?** Recommendation: **free**, deliberately. A gated share card can't do marketing for you, and marketing is the main reason to build it.
- Should the Insights feature feed it — e.g. a card variant that shares an insight rather than a workout? The insight content already exists (see item 6).

### Risks
Low. Nothing touches the data model or the logging path. The main risk is design iteration time, not engineering.

---

## 2. HealthKit integration

**Sizing: M.** Highest-value integration for a shipped fitness app, and a prerequisite for the Watch app.

### What exists today
- Nothing. `import HealthKit` appears nowhere in the project; there is no `HKHealthStore`, no entitlement, no usage-description keys.
- `Core/Services/BodyweightService.swift` + `Data/Models/BodyweightEntry.swift` + `BodyweightEntryRepository` — the bodyweight side already has a clean service to sync against.
- `Data/Models/HealthProfile.swift` holds unit preference and training settings (note: this is *your* settings model, unrelated to HealthKit despite the name — worth being careful about the naming collision in discussion).
- `Features/Settings/Views/BodyweightLogView.swift` — existing manual bodyweight entry UI.

### What's missing
Everything: entitlement, permission flow, read path, write path, settings toggle, sync/dedupe logic.

### Scope
- **Write:** finished workouts as `HKWorkout` with `.traditionalStrengthTraining`, including duration and (if available) energy burned, so Repster workouts appear in Apple Health and count toward Activity rings.
- **Read:** bodyweight from Health to populate `BodyweightEntry`, replacing/augmenting manual entry.
- **Optional write:** bodyweight entered in Repster back to Health.
- Settings section with per-direction toggles, plus a clear "not connected" state.

### Decisions to make
- **Permission timing.** Your own pre-launch todo list flags that notification permission was requested too early at launch. Do not repeat that here: request HealthKit authorization only when the user enables the integration in Settings, never at first launch.
- **Bidirectional bodyweight sync needs a conflict/dedupe rule** — which source wins, and how to avoid an echo loop where a write triggers a read that triggers a write.
- **Backfill or not?** Writing historical workouts to Health on first connect is nice but can dump hundreds of entries into the user's Health app at once. Recommendation: offer it as an explicit one-time action, default off.
- Which extra metrics to write (energy, heart rate) — heart rate realistically depends on the Watch app.

### Risks
- HealthKit permission is opaque by design: the app cannot tell whether read access was denied vs. simply has no data. UI must handle "we might have nothing because you said no" gracefully.
- Requires a real device for QA; HealthKit in the simulator is unreliable.
- App Store privacy answers need updating — you already have a checklist at `marketing/app-store/privacy-review-checklist.md`.

---

## 3. Home Screen / Lock Screen widgets

**Sizing: S–M.** Cheap because the extension already exists.

### What exists today
- `WorkoutLiveActivityExtension` target with `WorkoutLiveActivityBundle.swift` — a `WidgetBundle` that currently registers **only** `WorkoutLiveActivityWidget()` (the Live Activity for an in-progress workout, incl. Dynamic Island).
- `WorkoutActivityAttributes.swift` and `LiveActivityManager.swift` in `Features/Workout/Models/`.
- `Core/Services/StatsService.swift` and `AnalyticsService.swift` for aggregate numbers.

### What's missing
- No WidgetKit *timeline* widget of any kind (no `TimelineProvider`, no static widget). The extension does Live Activities only.
- No App Group / shared container for the widget to read workout data from — this is the real work.

### Scope
Add one or more timeline widgets to the existing bundle. Candidates, roughly in order of usefulness:
- **Next planned workout** (from `Program` / `PlannedWorkout`) with a tap-to-start deep link.
- **Streak / workouts this week.**
- **Recent PR** — pairs nicely with the share card's PR emphasis.
- Weekly volume trend as a small chart.

### Decisions to make
- **Data access is the architectural question.** The widget extension cannot reach the app's SwiftData store without an App Group container, and the store is currently app-local. Options: (a) move the SwiftData store into an App Group, (b) write a small denormalized snapshot (JSON/`UserDefaults` in a shared suite) on workout finish for the widget to read. Option (b) is far less invasive and avoids migrating a shipped store — but note it means writing on finish, which brushes against the workout-logging constraint. Option (a) is cleaner long-term and doesn't touch logging code, but is a store migration on a live app.
- Which widget families to support (systemSmall/Medium/Large, accessory* for Lock Screen).
- Refresh cadence and budget — widget timeline reloads are rationed by the system.
- Free or gated? Recommendation: free. Widgets drive re-engagement, which drives retention, which is what you're actually selling.

### Risks
- The App Group / store-migration decision is the one that can turn this from S into L. Settle it before estimating.
- Deep links need a URL scheme and routing that doesn't exist yet.

---

## 4. Apple Watch app

**Sizing: L.** The biggest item here by a wide margin. Treat it as its own project, not a release line item.

### What exists today
- Nothing watch-related. No watchOS target, no `WatchConnectivity`.

### What's missing
Everything: target, UI, data sync, complications.

### Scope
- New watchOS app target + a companion sync layer.
- Set logging from the wrist: at minimum log/complete a set and see the rest timer; realistically also weight/reps adjustment.
- `HKWorkoutSession` for heart rate capture and to keep the app alive during a session.
- Complications for quick start.

### Decisions to make
- **Standalone or companion?** Full standalone (watch can log without the phone nearby) roughly doubles the sync complexity. A companion-only app that requires the phone is much cheaper and covers most gym scenarios.
- **Sync strategy:** `WatchConnectivity` message passing vs. a shared CloudKit store. Note there is no CloudKit in the project today, so the latter drags in the whole sync question you've otherwise deferred.
- **How much of the app comes along?** Recommendation: logging + rest timer only. Do not port charts, history, or programs.
- Conflict resolution when both devices edit the same workout.

### Dependencies
- **Do HealthKit (item 2) first.** The Watch app will want `HKWorkoutSession` and heart rate, and you want the Health write path settled before adding a second writer.
- Widgets (item 3) first is also mildly useful — solving the shared-data-container problem there informs the watch sync design.

### Risks
- This is the item most likely to expand. The watch UI is not a scaled-down phone UI; set logging on a 45mm screen is a genuine design problem.
- Requires real-device QA throughout; watch simulators are poor for this.

---

## 5. Exercise guidance content

**Sizing: S engineering, L content.** The code is trivial; the bottleneck is writing the material.

### What exists today
`Data/Models/Exercise.swift` has structural metadata only:
- `name`, `equipmentType`, `trackingType`
- `primaryMuscle`, `secondaryMuscles[]`, `movementPattern`
- `unilateral`, `unilateralRepTargetMode`, `bilateralLoadFactor`, `bodyweightFactor`
- `weightIncrement`, `defaultRestTime`
- fatigue-model fields (`fatigueRate`, `recoveryConstant`, learning fields)

Seed data comes from `Core/Seeding/` (`SeedExerciseDTO.swift`, `SeedExerciseDTO+Mapping.swift`).

### What's missing
- No instruction text, no form cues, no images, no video, no muscle diagrams. There is nowhere to put them on the model.

### Scope
- Add fields to `Exercise` (e.g. `instructions: String?`, `cues: [String]`, `commonMistakes: [String]`) — a lightweight SwiftData migration.
- Extend the seed DTO + JSON, and make sure existing users' seeded exercises get backfilled (they already have rows, so this is an update path, not just a fresh seed).
- Surface in exercise detail and ideally as a peek from the active workout.

### Decisions to make
- **Where does the content come from?** This is the whole project. Writing cues for a full exercise library is a serious authoring effort, and correctness matters — bad form advice on a fitness app is a real-world safety issue, not just a quality issue. Options: write it yourself, license a dataset, or scope down to the top ~40 most-used exercises.
- **Text only, or media?** Illustrations/animations balloon app size and cost; text cues are cheap and shippable.
- Custom user-created exercises won't have guidance — how does the UI handle that absence?
- **Free or gated?** This is a plausible paywall feature, but note that gating safety information is a bad look. Recommendation: free if it's form cues, gated only if it becomes a richer library.

### Risks
- Backfilling content onto exercises that users may have edited — the update path needs care not to clobber user modifications.
- Content licensing if you don't write it yourself.

---

## 6. Deload / readiness suggestions

**Sizing: M.** Most of the data plumbing already exists. This is mainly a product and trust problem.

### What exists today — more than you might expect
- `Core/Services/FatigueLearningService.swift` + `Data/Models/FatigueObservation.swift`. Each completed set already records `predictedEffectiveE1RM`, `actualE1RM`, `normalizedError` (signed: negative = model too aggressive, positive = user underperforming), `baseE1RM`, `prescribedWeight`, `actualWeight`, `setIndex`.
- `WorkoutSummarySheet` already collects **per-exercise fatigue feedback** ("less aggressive / about right / more aggressive") and a session effort 1–10.
- **The Insights feature already shipped** (`Core/Services/InsightsService.swift`, `InsightRules.swift`, `Features/Insights/`, `Data/Models/InsightRecord.swift`) with a gated findings feed, a home teaser card, and a "N new" badge. Existing rules: `RestSweetSpotInsightRule`, `TargetAdherenceInsightRule`, `MuscleBalanceInsightRule`, `PRRhythmInsightRule`, `RIRCalibrationInsightRule`. Spec at `INSIGHTS_FEATURE_DESIGN.md`.

### The key recommendation
**Build this as a sixth insight rule, not a new system.** A `DeloadReadinessInsightRule` gets the feed UI, the gating, the badge, the lifecycle/dismissal handling, and the lazy refresh pipeline for free. That turns this from a feature into a rule plus a copy pass, and it keeps the "app gives advice" surface consistent in one place.

Note the engine deliberately runs lazily via `refreshIfNeeded()` on Home load rather than on workout finish — specifically to avoid touching workout code. Keep it that way unless the logging constraint lifts.

### What's missing
- No rule that reads accumulated fatigue error over time to detect a downward trend.
- No notion of "readiness" as a surfaced concept.

### Scope
- A rule that looks for sustained positive `normalizedError` (user consistently underperforming prediction) across multiple sessions and exercises, ideally corroborated by session effort trending up while volume/e1RM trends flat or down.
- Copy that suggests rather than instructs.

### Decisions to make
- **What's the trigger threshold?** This is the crux. Too sensitive and it tells everyone to deload constantly, which destroys trust in the whole Insights feed. Recommendation: require a high bar of corroborating evidence and a minimum data history before it can ever fire.
- **How strong is the language?** "You may be accumulating fatigue" vs. "Take a deload week." Recommendation: the former.
- **Frequency cap** — this insight should be able to fire at most once every few weeks.
- Should it be dismissible with feedback ("not helpful") to tune future firing?

### Risks
- **This is the item where being wrong costs the most.** "The app told me to deload" is a claim users will act on and judge you for. Conservative thresholds and hedged language are not optional polish here.
- Overlaps conceptually with Smart Suggestions — make sure the two don't contradict each other on the same screen.

---

## 7. Supersets — execution support ⚠️ *see constraint at top*

**Sizing: M.** The data layer is done. The UI is entirely absent.

### What exists today — it's half-built
The **data model and template authoring** support supersets:
- `Data/Models/TemplateExercise.swift:10` — `var supersetGroupId: UUID?`
- `Data/Models/WorkoutSet.swift:36` — `var supersetGroupId: UUID?`
- `Features/Templates/ViewModels/CreateEditTemplateViewModel.swift` — 27 references; this is where grouping is actually authored.
- `Features/Templates/Views/CreateEditTemplateView.swift` — 9 references (grouping UI).
- `Core/Services/TemplateService.swift` — 15 references, incl. carrying `supersetGroupId` through template→workout and duplication paths.
- `ExportService` / `ImportService` round-trip the field.

The **execution side has zero support**:
- `grep -ri superset Repster/Features/Workout/` returns **nothing**. Not one reference across `ActiveWorkoutView`, `ActiveWorkoutViewModel`, `SetTableView`, `SetRowView`, `ExerciseTabStripView`, or `RestTimerView`.

So today a user can define a superset in a template, start the workout, and the app behaves exactly as if the grouping didn't exist.

### The core UX problem
The active workout is organized as **one exercise at a time**, navigated by a horizontal tab strip (`ExerciseTabStripView` — tap a tab to switch, with reorder and delete in the context menu). A superset means alternating between two or more exercises set-by-set, which is fundamentally at odds with a one-exercise-per-screen model. **This is the design decision that determines the size of the whole feature.** Options:

- **(a) Grouped tab / combined view** — a superset renders as a single tab containing both exercises' set rows interleaved. Best UX, most work, most disruption to `SetTableView`.
- **(b) Auto-advance** — keep the current tabs, but completing a set in a grouped exercise automatically jumps to the next exercise in the group. Much cheaper, keeps the existing structure, but the tab strip needs to visually communicate the grouping.
- **(c) Visual-only** — mark grouped exercises in the tab strip and skip rest between them, with no navigation change. Cheapest, weakest.

Recommendation: **(b)**, with the grouping shown as a visual pairing in the tab strip. It delivers the actual benefit (fast alternation, no rest between paired exercises) without rewriting the set table.

### Scope
- Rest-timer behaviour: no rest (or short rest) *within* a group, full rest *after* the last exercise in the group. This is the single most important functional change — it's why people use supersets. Touches `RestTimerView` and the timer logic in `ActiveWorkoutViewModel`.
- Set-completion flow / auto-advance.
- Visual grouping in `ExerciseTabStripView`.
- Creating or dissolving a superset **during** a live workout (currently only possible when authoring a template).
- Verify `supersetGroupId` actually propagates template→workout at runtime — the field is carried in `TemplateService`, but since nothing consumes it downstream, that path has effectively never been exercised. **Test this first; it may already be broken.**
- Live Activity should reflect the group state.
- Summary/history display of grouped work.

### Decisions to make
- Which of (a)/(b)/(c) above.
- How does rest work inside a group — zero, or a short configurable transition rest? (`HealthProfile` already has `defaultRestTimeSeconds` and `defaultWarmupRestTimeSeconds`, so a third default fits the existing pattern.)
- Do supersets affect Smart Suggestions? Alternating exercises changes the fatigue picture, and `FatigueLearningService` currently models per-exercise fatigue with recovery over rest time. Short rests inside a superset may skew the model. **Worth checking whether superset workouts would poison the fatigue learning data.**
- Trisets/giant sets, or pairs only? The `UUID?` group model already supports N exercises, so this is a UI question, not a data one.
- Circuits (rounds) — explicitly in or out of scope? Recommendation: out, for now.

### Risks
- **Requires opening up the workout-logging code** — see the constraint at the top of this document. This is the gate.
- Rest-timer logic is entangled with Live Activity state; changes there are the most user-visible regression risk in the app.
- Fatigue-model interaction (above) could quietly degrade Smart Suggestions for superset users.

---

## Suggested sequencing

| # | Feature | Size | Depends on | Notes |
|---|---------|------|-----------|-------|
| 1 | Share card | S | — | Ship first. Cheap, no data-model risk, markets the app. |
| 2 | HealthKit | M | — | Do before the Watch app. |
| 3 | Widgets | S–M | — | Settle the App Group question before estimating. |
| 7 | Supersets | M | logging-code decision | Blocked on the constraint, not on engineering. |
| 6 | Deload / readiness | M | — | Build as an Insights rule. |
| 5 | Exercise guidance | S code / L content | content sourcing | Start the content in parallel with everything else. |
| 4 | Watch app | L | HealthKit, ideally widgets | Its own project. |

Items 1, 2, 3 and 6 are mutually independent and can be scoped in parallel. Item 7's position depends entirely on the logging-code decision. Item 4 should be last regardless.

---

## Open questions to resolve before detailed scoping

1. ~~**Is the "don't touch workout-logging code" constraint lifted for supersets?**~~ **Resolved 2026-08-08: lifted.** Item 7 is unblocked.
2. **Widget data access:** App Group + SwiftData store migration, or a denormalized snapshot file?
3. **Where does exercise guidance content come from,** and who writes it?
4. **Which of these are free vs. behind the RevenueCat entitlement?** Recommendation: share card, widgets and HealthKit free; guidance and deload gated with the rest of Insights.
5. **Watch app: standalone or phone-companion?** Roughly a 2× difference in effort.
6. **Do supersets need to be excluded from — or corrected for in — fatigue learning?**
