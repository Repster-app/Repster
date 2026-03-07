---
work_package_id: "WP04"
subtasks:
  - "T016"
  - "T017"
  - "T018"
  - "T019"
  - "T020"
title: "Exercise Detail View"
phase: "Phase 1 - Core Screens"
lane: "done"
assignee: "claude"
agent: "claude"
shell_pid: "76877"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-25T08:19:17Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP04 - Exercise Detail View

## IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Implementation Command

Depends on WP01:
```bash
spec-kitty implement WP04 --base WP01
```

---

## Objectives & Success Criteria

- Build the reusable `ExerciseDetailView` with History/PRs/Charts tab picker
- Build `ExerciseDetailViewModel` with lazy-loaded data per tab
- Build `ExerciseHistoryView` showing past sessions grouped by workout
- Build `ExercisePRsView` rendering the suffix-max filtered PR table
- Build `ExerciseChartsView` with e1RM trend (LineMark) and volume per session (BarMark)
- **Success**: Exercise Detail works as a standalone pushed view. History shows sessions newest first. PR table shows suffix-max filtered results. Charts render e1RM and volume correctly. Component is reusable in 3 contexts.

## Context & Constraints

- **Spec**: User Story 3 (Exercise Detail reused component), FR-006, FR-007, SC-002, SC-004
- **Constitution**: Write-time PR/stats (read pre-computed), database aggregation not Swift iteration, Swift Charts only, `@Observable @MainActor` ViewModels
- **Plan**: `kitty-specs/007-exercise-list-and-detail/plan.md` - Decision 3 (reusable component), Decision 7 (charts functional minimum)
- **Research**: `kitty-specs/007-exercise-list-and-detail/research.md` - R3 (component takes exerciseId), R4 (Swift Charts minimum)
- **Data layer**: `PRService.fetchPRTable(for:)` returns suffix-max filtered `[PRTableEntry]`. `SetService.fetchSets(for:exerciseId:limit:)` for history. `StatsService.fetchStats(for:)` for stats. `WorkoutService.fetchWorkout(_:)` for workout dates.
- **Existing components**: `PRBadgeView` (reuse for PR indicators in history), design tokens in `DesignTokens.swift`
- **Supporting types**: `WorkoutHistoryGroup` and `ExerciseChartData` from WP02 T010

## Subtasks & Detailed Guidance

### Subtask T016 - Create ExerciseDetailViewModel

- **Purpose**: Central ViewModel for the Exercise Detail screen, with lazy-loaded data per tab.
- **File**: `Reppo/Features/Exercise/ViewModels/ExerciseDetailViewModel.swift`
- **Steps**:
  1. Create the ViewModel:
     ```swift
     @Observable @MainActor
     final class ExerciseDetailViewModel {
         private let exerciseId: UUID
         private let exerciseService: any ExerciseServiceProtocol
         private let prService: any PRServiceProtocol
         private let setService: any SetServiceProtocol
         private let statsService: any StatsServiceProtocol
         private let workoutService: any WorkoutServiceProtocol

         var exercise: Exercise?
         var stats: ExerciseStats?
         var prTable: [PRTableEntry] = []
         var historyWorkouts: [WorkoutHistoryGroup] = []
         var chartData: ExerciseChartData?
         var isLoading: Bool = false
         var hasSets: Bool = false
     }
     ```

  2. Implement `loadExercise()` - loads exercise metadata + stats (called on appear):
     ```swift
     func loadExercise() async {
         isLoading = true
         exercise = try? await exerciseService.fetchExercise(exerciseId)
         stats = try? await statsService.fetchStats(for: exerciseId)
         hasSets = (try? await exerciseService.exerciseHasSets(exerciseId)) ?? false
         isLoading = false
     }
     ```

  3. Implement `loadHistory()` - fetches sets grouped by workout:
     ```swift
     func loadHistory() async {
         let sets = (try? await setService.fetchSets(for: exerciseId, limit: nil)) ?? []
         // Group by workoutId
         let grouped = Dictionary(grouping: sets) { $0.workoutId }
         historyWorkouts = grouped.map { workoutId, workoutSets in
             WorkoutHistoryGroup(
                 id: workoutId,
                 date: workoutSets.first?.date ?? Date(),
                 sets: workoutSets.sorted { $0.orderInExercise < $1.orderInExercise }
             )
         }
         .sorted { $0.date > $1.date } // Newest first
     }
     ```
     Note: Use `SetService.fetchSets(for exerciseId:, limit:)` (pass-through to SetRepository). Consider limiting to last 50 sessions initially.

  4. Implement `loadPRs()`:
     ```swift
     func loadPRs() async {
         prTable = (try? await prService.fetchPRTable(for: exerciseId)) ?? []
     }
     ```

  5. Implement `loadCharts()`:
     ```swift
     func loadCharts() async {
         let sets = (try? await setService.fetchSets(for: exerciseId, limit: nil)) ?? []
         // e1RM points: sets with e1RM > 0, grouped per workout, take best per session
         // Volume points: sum effectiveWeight * reps per workout
         let grouped = Dictionary(grouping: sets) { $0.workoutId }
         var e1rmPoints: [ExerciseChartData.ChartPoint] = []
         var volumePoints: [ExerciseChartData.VolumePoint] = []

         for (_, workoutSets) in grouped {
             guard let date = workoutSets.first?.date else { continue }
             // Best e1RM in this session
             if let bestE1RM = workoutSets.compactMap({ $0.e1RM }).max(), bestE1RM > 0 {
                 e1rmPoints.append(.init(date: date, value: bestE1RM))
             }
             // Total volume in this session
             let volume = workoutSets.reduce(0.0) { total, set in
                 total + (set.effectiveWeight * Double(set.reps ?? 0))
             }
             if volume > 0 {
                 volumePoints.append(.init(date: date, volume: volume))
             }
         }

         chartData = ExerciseChartData(
             e1RMPoints: e1rmPoints.sorted { $0.date < $1.date },
             volumePerSession: volumePoints.sorted { $0.date < $1.date }
         )
     }
     ```

  6. Implement `deleteExercise()`:
     ```swift
     func deleteExercise() async throws {
         try await exerciseService.deleteExercise(exerciseId)
     }
     ```

- **Notes**: Use `SetService.fetchSets(for exerciseId:, limit:)` for history and chart data. Each WorkoutSet has a `workoutId` field for grouping. Use `WorkoutService.fetchWorkout(_:)` if you need workout dates beyond what's on the sets themselves.
- **Parallel?**: No - other views depend on this.

### Subtask T017 - Create ExerciseDetailView shell

- **Purpose**: The main detail view with exercise header info and History/PRs/Charts tab picker.
- **File**: `Reppo/Features/Exercise/Views/ExerciseDetailView.swift`
- **Steps**:
  1. Create the view:
     ```swift
     struct ExerciseDetailView: View {
         let exerciseId: UUID
         @State private var viewModel: ExerciseDetailViewModel
         @State private var selectedTab: ExerciseDetailTab = .history

         init(exerciseId: UUID, /* service dependencies */) {
             self.exerciseId = exerciseId
             self._viewModel = State(initialValue: ExerciseDetailViewModel(
                 exerciseId: exerciseId,
                 // inject services
             ))
         }
     }
     ```

  2. Build the body:
     ```swift
     var body: some View {
         VStack(spacing: 0) {
             // Exercise header
             if let exercise = viewModel.exercise {
                 exerciseHeader(exercise)
             }

             // Tab picker
             Picker("Tab", selection: $selectedTab) {
                 ForEach(ExerciseDetailTab.allCases, id: \.self) { tab in
                     Text(tab.rawValue).tag(tab)
                 }
             }
             .pickerStyle(.segmented)
             .padding(.horizontal, 20)
             .padding(.vertical, 8)

             // Tab content
             switch selectedTab {
             case .history:
                 ExerciseHistoryView(viewModel: viewModel)
             case .prs:
                 ExercisePRsView(viewModel: viewModel)
             case .charts:
                 ExerciseChartsView(viewModel: viewModel)
             }
         }
         .background(Color.bg)
         .navigationTitle(viewModel.exercise?.name ?? "Exercise")
         .navigationBarTitleDisplayMode(.inline)
         .task {
             await viewModel.loadExercise()
             await viewModel.loadHistory() // Default tab
         }
         .onChange(of: selectedTab) { _, newTab in
             Task {
                 switch newTab {
                 case .history: await viewModel.loadHistory()
                 case .prs: await viewModel.loadPRs()
                 case .charts: await viewModel.loadCharts()
                 }
             }
         }
     }
     ```

  3. Exercise header: Show name, primaryMuscle, equipmentType, stats summary (total workouts, best e1RM, last performed).

  4. **Reusability consideration**: The sub-views (`ExerciseHistoryView`, `ExercisePRsView`, `ExerciseChartsView`) should also be usable standalone (WP06 needs History and Charts embedded in Active Workout). Two approaches:
     - A) Sub-views take the shared ViewModel (simpler but couples to ExerciseDetailViewModel)
     - B) Sub-views take an `exerciseId` and create their own data loading (more reusable but duplicates fetch logic)

     **Recommendation**: Use approach A for the tabs within ExerciseDetailView, but also expose standalone initializers on `ExerciseHistoryView` and `ExerciseChartsView` that accept `exerciseId` and create a lightweight ViewModel internally. WP06 will use the standalone initializers.

- **Parallel?**: No - this is the shell that hosts the tab views.

### Subtask T018 - Create ExerciseHistoryView

- **Purpose**: Show past sessions for this exercise, grouped by workout, newest first.
- **File**: `Reppo/Features/Exercise/Views/ExerciseHistoryView.swift`
- **Steps**:
  1. Create the view that displays `historyWorkouts`:
     ```swift
     struct ExerciseHistoryView: View {
         let historyWorkouts: [WorkoutHistoryGroup]

         var body: some View {
             if historyWorkouts.isEmpty {
                 emptyState
             } else {
                 ScrollView {
                     LazyVStack(spacing: 12) {
                         ForEach(historyWorkouts) { group in
                             workoutSessionCard(group)
                         }
                     }
                     .padding(.horizontal, 20)
                 }
             }
         }
     }
     ```

  2. Each `workoutSessionCard` shows:
     - Date header (formatted: "Feb 20, 2026")
     - Set rows with: set number, weight (with unit), reps, PR badge
     - Use `PRBadgeView` for cachedPRStatus display (already built in Feature 006)

  3. Set row format (simplified, not full `SetRowView`):
     ```swift
     private func setRow(_ set: WorkoutSet, index: Int) -> some View {
         HStack {
             Text("\(index + 1)")
                 .font(.system(size: 13, weight: .semibold))
                 .foregroundStyle(Color.textTertiary)
                 .frame(width: 24)

             if let weight = set.weight {
                 Text("\(formatWeight(weight))")
                     .font(.system(size: 14, weight: .medium))
                     .foregroundStyle(Color.textPrimary)
             }

             if let reps = set.reps {
                 Text("x \(reps)")
                     .font(.system(size: 14))
                     .foregroundStyle(Color.textSecondary)
             }

             Spacer()

             PRBadgeView(status: set.cachedPRStatus)
         }
     }
     ```

  4. Empty state: "No history yet" message.
  5. Also provide a standalone initializer that takes `exerciseId` and loads data itself (for WP06 reuse in Active Workout sub-tabs).

- **Parallel?**: Yes - independent view file.

### Subtask T019 - Create ExercisePRsView

- **Purpose**: Render the suffix-max filtered rep-max PR table.
- **File**: `Reppo/Features/Exercise/Views/ExercisePRsView.swift`
- **Steps**:
  1. Create the view displaying `prTable`:
     ```swift
     struct ExercisePRsView: View {
         let prTable: [PRTableEntry]

         var body: some View {
             if prTable.isEmpty {
                 emptyState
             } else {
                 ScrollView {
                     VStack(spacing: 0) {
                         // Header row
                         HStack {
                             Text("REPS")
                             Spacer()
                             Text("WEIGHT")
                             Spacer()
                             Text("DATE")
                         }
                         .font(.system(size: 11, weight: .semibold))
                         .foregroundStyle(Color.textTertiary)
                         .padding(.horizontal, 20)
                         .padding(.vertical, 8)

                         Divider().background(Color.border)

                         // PR rows
                         ForEach(prTable, id: \.reps) { entry in
                             prRow(entry)
                             Divider().background(Color.border)
                         }
                     }
                 }
             }
         }
     }
     ```

  2. Each PR row shows:
     - Reps count (left, bold)
     - Weight with unit (center, using `UnitConversion` for kg/lbs)
     - Date (right, formatted)
     - Gold accent for the 1RM row (reps == 1)

  3. `PRTableEntry` has: `reps: Int`, `value: Double`, `setId: UUID`, `date: Date`. The suffix-max filtering is already done by `PRService.fetchPRTable()` -- just display the results.

  4. Empty state: "No PRs recorded yet" with a dumbbell icon.

  5. Unit conversion: Read user's `unitPreference` to display weight in kg or lbs. Check `UnitConversion.swift` for available helpers.

- **Parallel?**: Yes - independent view file.

### Subtask T020 - Create ExerciseChartsView

- **Purpose**: Render e1RM trend and volume per session charts using Swift Charts.
- **File**: `Reppo/Features/Exercise/Views/ExerciseChartsView.swift`
- **Steps**:
  1. Import Charts: `import Charts`

  2. Create the view with two chart sections:
     ```swift
     struct ExerciseChartsView: View {
         let chartData: ExerciseChartData?

         var body: some View {
             if let data = chartData {
                 ScrollView {
                     VStack(spacing: 24) {
                         e1rmChart(data.e1RMPoints)
                         volumeChart(data.volumePerSession)
                     }
                     .padding(.horizontal, 20)
                 }
             } else {
                 emptyState
             }
         }
     }
     ```

  3. e1RM trend chart:
     ```swift
     private func e1rmChart(_ points: [ExerciseChartData.ChartPoint]) -> some View {
         VStack(alignment: .leading, spacing: 8) {
             Text("ESTIMATED 1RM TREND")
                 .font(.system(size: 11, weight: .semibold))
                 .foregroundStyle(Color.textTertiary)
                 .kerning(0.8)

             Chart(points) { point in
                 LineMark(
                     x: .value("Date", point.date),
                     y: .value("e1RM", point.value)
                 )
                 .foregroundStyle(Color.accent)

                 PointMark(
                     x: .value("Date", point.date),
                     y: .value("e1RM", point.value)
                 )
                 .foregroundStyle(Color.accent)
                 .symbolSize(20)
             }
             .frame(height: 200)
             .chartYAxis {
                 AxisMarks(position: .leading)
             }
         }
         .padding(14)
         .background(Color.bgCard)
         .cornerRadius(14)
     }
     ```

  4. Volume per session chart:
     ```swift
     private func volumeChart(_ points: [ExerciseChartData.VolumePoint]) -> some View {
         VStack(alignment: .leading, spacing: 8) {
             Text("VOLUME PER SESSION")
                 .font(.system(size: 11, weight: .semibold))
                 .foregroundStyle(Color.textTertiary)
                 .kerning(0.8)

             Chart(points) { point in
                 BarMark(
                     x: .value("Date", point.date),
                     y: .value("Volume", point.volume)
                 )
                 .foregroundStyle(Color.accent.opacity(0.7))
             }
             .frame(height: 200)
             .chartYAxis {
                 AxisMarks(position: .leading)
             }
         }
         .padding(14)
         .background(Color.bgCard)
         .cornerRadius(14)
     }
     ```

  5. Chart styling: Use `.accent` color for chart marks. Dark mode background via `.bgCard` card wrapper. Minimal axis labels. No interactivity (deferred to Feature 009).

  6. Empty state: "No chart data yet" when chartData is nil or both point arrays are empty.

  7. Also provide a standalone initializer for WP06 reuse.

- **Notes**: This is functional minimum per plan decision. Keep charts simple. Feature 009 will add polish, interactivity, and additional chart types.
- **Parallel?**: Yes - independent view file.

## Risks & Mitigations

- **SetService API**: Use `SetService.fetchSets(for exerciseId:, limit:)` for history and chart data. This is a thin pass-through to the repository. Verify the return type includes all needed fields (workoutId, date, reps, effectiveWeight, e1RM).
- **Large history sets**: An exercise performed 100+ times could have thousands of sets. Use `LazyVStack` and consider pagination (initial load = last 20 sessions).
- **Chart with few data points**: e1RM chart with only 1-2 points looks sparse. Handle gracefully (still render, the line/bar will just be short).
- **PRTableEntry import**: `PRTableEntry` is defined in `PRService`. Ensure it's accessible from the view layer (it should be if it's a public struct).

## Definition of Done Checklist

- [ ] ExerciseDetailViewModel loads exercise, stats, history, PRs, and chart data
- [ ] ExerciseDetailView shows header + tab picker + tab content
- [ ] History tab shows sessions grouped by workout, newest first, with PR badges
- [ ] PRs tab shows suffix-max filtered table with reps/weight/date
- [ ] Charts tab shows e1RM LineMark and volume BarMark
- [ ] Empty states for each tab when no data exists
- [ ] Component is reusable (takes exerciseId, creates own ViewModel)
- [ ] All colors from DesignTokens.swift
- [ ] `tasks.md` updated with status change

## Review Guidance

- Verify History tab groups sets by workout correctly
- Verify PRs tab displays suffix-max filtered results (compare with PRService output)
- Verify Charts use Swift Charts (native), not third-party
- Verify component works when navigated to via NavigationLink (pushed)
- Verify empty states for all 3 tabs
- Verify data loading is lazy (per-tab, not all at once)

## Activity Log

- 2026-02-25T08:19:17Z - system - lane=planned - Prompt created.
- 2026-02-26T15:01:37Z – claude – shell_pid=76877 – lane=doing – Started implementation via workflow command
- 2026-02-26T15:09:08Z – claude – shell_pid=76877 – lane=for_review – Ready for review: Exercise Detail View with History/PRs/Charts tabs, lazy-loaded data per tab, EquipmentType.displayName, SetService.fetchSets(for exerciseId:), StatsService.fetchStats(for:)
- 2026-02-26T20:20:42Z – claude – shell_pid=76877 – lane=done – Review passed: ExerciseDetailView correctly implements History/PRs/Charts tab picker with lazy loading via .onChange(of: selectedTab), exercise header with stats, Edit/Delete toolbar actions with sheets and confirmationDialog. ExerciseHistoryView, ExercisePRsView, ExerciseChartsView sub-views all present. All DoD items met.
