---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
  - "T005"
  - "T006"
  - "T007"
title: "Foundation — Models, Repository Methods, ChartDataService, Dashboard Skeleton"
phase: "Phase 0 - Foundation"
lane: "done"
dependencies: []
agent: "claude"
assignee: "Magnus Espensen"
shell_pid: "91062"
reviewed_by: "Magnus Espensen"
review_status: "approved"
history:
  - timestamp: "2026-02-27T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-02-28T08:13:27Z"
    lane: "doing"
    agent: "claude"
    shell_pid: "89491"
    action: "Started implementation via workflow command"
  - timestamp: "2026-02-28T08:21:18Z"
    lane: "for_review"
    agent: "claude"
    shell_pid: "89491"
    action: "Ready for review: ChartModels, SetRepository date-range queries, ChartDataService actor with stubs, ServiceContainer wiring, ChartsDashboardViewModel/View, ContentView integration. BUILD SUCCEEDED with 0 errors."
  - timestamp: "2026-02-28T08:22:19Z"
    lane: "doing"
    agent: "claude"
    shell_pid: "91062"
    action: "Started review via workflow command"
  - timestamp: "2026-02-28T08:23:40Z"
    lane: "done"
    agent: "claude"
    shell_pid: "91062"
    action: "Review passed: All 7 subtasks verified. ChartModels match data-model.md exactly. SetRepository uses FetchDescriptor+Predicate correctly. ChartDataService is actor with 5 repo deps. ViewModel uses protocol type. BUILD SUCCEEDED with 0 errors."
---

# Work Package Prompt: WP01 – Foundation — Models, Repository Methods, ChartDataService, Dashboard Skeleton

## Objectives & Success Criteria

- Create all chart data model types in `ChartModels.swift` (overview, exercise card, detail chart, time range).
- Add date-range query methods to `SetRepository` for chart data fetching.
- Create `ChartDataService` actor with repository dependencies and method stubs.
- Register `ChartDataService` in `ServiceContainer`.
- Create `ChartsDashboardViewModel` with @Observable, state properties, and loading stubs.
- Create `ChartsDashboardView` with section layout and wire into ContentView replacing the placeholder.
- **Success**: Charts tab appears in bottom nav. View renders with section headers. All types compile. ChartDataService initializes correctly. App builds without errors.

## Context & Constraints

- **Architecture**: MVVM with `@Observable` (iOS 17+). Views → ViewModels → Services → Repositories → SwiftData.
- **Constitution**: No third-party UI libs. Dark mode only. No ModelContext in ViewModel. NavigationStack (not NavigationView). SF Symbols.
- **Design tokens**: All colors from `Reppo/Core/Extensions/DesignTokens.swift`.
- **Existing patterns**: Follow `Reppo/Features/Exercise/` and `Reppo/Features/Workout/` for file organization. Follow `Reppo/Core/Services/ServiceContainer.swift` for DI pattern.
- **Key docs**: `kitty-specs/009-charts-tab/plan.md`, `kitty-specs/009-charts-tab/data-model.md`, `kitty-specs/009-charts-tab/research.md`.
- **Existing repository**: `SetRepository` is a `@ModelActor` at `Reppo/Core/Repositories/SetRepository.swift`. It uses `SetRepositoryProtocol`. New methods must follow the same pattern.
- **WorkoutRepository** already has `fetchWorkouts(for dateRange: ClosedRange<Date>)` — do NOT add a new workout fetch method.

**Implementation command**: `spec-kitty implement WP01`

## Subtasks & Detailed Guidance

### Subtask T001 – Create ChartModels.swift

- **Purpose**: Define all chart data structures used across the Charts feature.
- **File**: `Reppo/Features/Charts/Models/ChartModels.swift` (new file)
- **Parallel?**: Yes — independent, no dependencies.

**Steps**:
1. Create directory structure: `Reppo/Features/Charts/Models/`.
2. Create the file with all types from `data-model.md`:

```swift
import SwiftUI

// MARK: - Overview Chart Data

struct OverviewChartData {
    let weeklyVolume: [WeeklyVolumePoint]
    let trainingFrequency: [WeeklyFrequencyPoint]
    let muscleGroupDistribution: [MuscleGroupVolume]
}

struct WeeklyVolumePoint: Identifiable {
    let id = UUID()
    let weekStart: Date
    let volume: Double
}

struct WeeklyFrequencyPoint: Identifiable {
    let id = UUID()
    let weekStart: Date
    let sessions: Int
}

struct MuscleGroupVolume: Identifiable {
    let id = UUID()
    let muscleGroup: String
    let volume: Double
    let color: Color
}

// MARK: - Exercise Card Data

struct ExerciseCardData: Identifiable {
    let id: UUID          // Exercise ID
    let name: String
    let currentE1RM: Double?
    let trendDirection: TrendDirection
    let sparklinePoints: [Double]
    let lastPerformed: Date?
}

enum TrendDirection {
    case up, down, flat
}

// MARK: - Exercise Detail Chart Data

struct ExerciseDetailChartData {
    let e1RMTrend: [ExerciseChartData.ChartPoint]
    let volumePerSession: [ExerciseChartData.VolumePoint]
    let topWeightPerSession: [TopWeightPoint]
    let repPRProgression: RepPRProgressionData
}

struct TopWeightPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
}

struct RepPRProgressionData {
    let series: [RepSeries]
}

struct RepSeries: Identifiable {
    let id = UUID()
    let reps: Int
    let label: String
    let points: [RepPRPoint]
}

struct RepPRPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
}

// MARK: - Time Range

enum TimeRange: String, CaseIterable {
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "All"

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: Date())
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: Date())
        case .oneYear: return calendar.date(byAdding: .year, value: -1, to: Date())
        case .all: return nil
        }
    }
}
```

3. Note: `ExerciseDetailChartData` references `ExerciseChartData.ChartPoint` and `ExerciseChartData.VolumePoint` from the existing `Reppo/Features/Exercise/Models/ExerciseModels.swift`. These are reused types.

**Validation**:
- All types compile without errors.
- `TimeRange.sixMonths.startDate` returns a date 6 months ago.
- `ExerciseDetailChartData` correctly references existing `ExerciseChartData` nested types.

---

### Subtask T002 – Add SetRepository Date-Range Query Methods

- **Purpose**: Add two new query methods to SetRepository for chart data fetching. These use date-range predicates to bound the data fetch per specdoc S8.10 / FR-009.
- **File**: `Reppo/Core/Repositories/SetRepository.swift` (edit existing file)
- **Parallel?**: Yes — independent of T001.

**Steps**:
1. Open `Reppo/Core/Repositories/SetRepository.swift`.
2. Add the protocol methods to `SetRepositoryProtocol`:

```swift
/// Fetch sets within a date range where hasData is true.
/// Used by overview charts (weekly volume, muscle group distribution).
func fetchSets(from startDate: Date, to endDate: Date) throws -> [WorkoutSet]

/// Fetch sets for a specific exercise within an optional date range.
/// Used by exercise detail charts and sparkline data.
/// If startDate is nil, fetches all history for the exercise.
func fetchSets(exerciseId: UUID, from startDate: Date?, to endDate: Date) throws -> [WorkoutSet]
```

3. Implement in the `SetRepository` actor:

```swift
func fetchSets(from startDate: Date, to endDate: Date) throws -> [WorkoutSet] {
    var descriptor = FetchDescriptor<WorkoutSet>(
        predicate: #Predicate<WorkoutSet> {
            $0.date >= startDate && $0.date <= endDate
        },
        sortBy: [SortDescriptor(\.date)]
    )
    return try modelContext.fetch(descriptor)
}

func fetchSets(exerciseId: UUID, from startDate: Date?, to endDate: Date) throws -> [WorkoutSet] {
    let descriptor: FetchDescriptor<WorkoutSet>
    if let startDate {
        descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate<WorkoutSet> {
                $0.exerciseId == exerciseId && $0.date >= startDate && $0.date <= endDate
            },
            sortBy: [SortDescriptor(\.date)]
        )
    } else {
        descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate<WorkoutSet> {
                $0.exerciseId == exerciseId && $0.date <= endDate
            },
            sortBy: [SortDescriptor(\.date)]
        )
    }
    return try modelContext.fetch(descriptor)
}
```

4. **Important**: The `hasData` filtering should happen in Swift after fetching (since `hasData` is a computed property, not a stored field). Filter in ChartDataService, not in the predicate.

**Validation**:
- Both methods compile and match the protocol.
- Existing SetRepository methods are not affected.
- Test mentally: fetching sets from 12 weeks ago to now should return a bounded subset.

---

### Subtask T003 – Create ChartDataService.swift

- **Purpose**: Central service actor for chart data aggregation. Encapsulates fetch + group + aggregate logic. Method stubs now, implementations in WP02-WP04.
- **File**: `Reppo/Core/Services/ChartDataService.swift` (new file)
- **Parallel?**: No — depends on T001 (model types) and T002 (repository methods).

**Steps**:
1. Create the protocol and actor:

```swift
import Foundation

protocol ChartDataServiceProtocol: Sendable {
    func fetchWeeklyVolume(weeks: Int) async throws -> [WeeklyVolumePoint]
    func fetchTrainingFrequency(weeks: Int) async throws -> [WeeklyFrequencyPoint]
    func fetchMuscleGroupDistribution(weeks: Int) async throws -> [MuscleGroupVolume]
    func fetchExerciseCardData() async throws -> [ExerciseCardData]
    func fetchExerciseDetailCharts(exerciseId: UUID, range: TimeRange) async throws -> ExerciseDetailChartData
}

actor ChartDataService: ChartDataServiceProtocol {

    // MARK: - Dependencies
    private let setRepository: any SetRepositoryProtocol
    private let workoutRepository: any WorkoutRepositoryProtocol
    private let exerciseRepository: any ExerciseRepositoryProtocol
    private let exerciseStatsRepository: any ExerciseStatsRepositoryProtocol
    private let performanceRecordRepository: any PerformanceRecordRepositoryProtocol

    init(
        setRepository: any SetRepositoryProtocol,
        workoutRepository: any WorkoutRepositoryProtocol,
        exerciseRepository: any ExerciseRepositoryProtocol,
        exerciseStatsRepository: any ExerciseStatsRepositoryProtocol,
        performanceRecordRepository: any PerformanceRecordRepositoryProtocol
    ) {
        self.setRepository = setRepository
        self.workoutRepository = workoutRepository
        self.exerciseRepository = exerciseRepository
        self.exerciseStatsRepository = exerciseStatsRepository
        self.performanceRecordRepository = performanceRecordRepository
    }

    // MARK: - Shared Helpers

    /// Canonical filter for sets eligible for chart aggregation.
    /// Applied post-fetch since hasData is a computed property.
    private func chartEligibleSets(_ sets: [WorkoutSet]) -> [WorkoutSet] {
        sets.filter { $0.hasData && $0.setType != .warmup && $0.setType != .partial }
    }

    // MARK: - Overview (WP02)

    func fetchWeeklyVolume(weeks: Int) async throws -> [WeeklyVolumePoint] {
        [] // Stub — implemented in WP02
    }

    func fetchTrainingFrequency(weeks: Int) async throws -> [WeeklyFrequencyPoint] {
        [] // Stub — implemented in WP02
    }

    func fetchMuscleGroupDistribution(weeks: Int) async throws -> [MuscleGroupVolume] {
        [] // Stub — implemented in WP02
    }

    // MARK: - Exercise Cards (WP03)

    func fetchExerciseCardData() async throws -> [ExerciseCardData] {
        [] // Stub — implemented in WP03
    }

    // MARK: - Exercise Detail (WP04)

    func fetchExerciseDetailCharts(exerciseId: UUID, range: TimeRange) async throws -> ExerciseDetailChartData {
        // Stub — implemented in WP04
        ExerciseDetailChartData(
            e1RMTrend: [],
            volumePerSession: [],
            topWeightPerSession: [],
            repPRProgression: RepPRProgressionData(series: [])
        )
    }
}
```

2. Note: `ChartDataService` is an `actor` (like other services), NOT a `@ModelActor` (it doesn't touch ModelContext directly — it uses repositories).

**Validation**:
- Compiles with all method stubs returning empty data.
- Protocol conformance is correct.
- Dependencies match existing repository protocol types.

---

### Subtask T004 – Add ChartDataService to ServiceContainer

- **Purpose**: Wire ChartDataService into the DI container so ViewModels can receive it.
- **File**: `Reppo/Core/Services/ServiceContainer.swift` (edit existing file)
- **Parallel?**: No — depends on T003.

**Steps**:
1. Open `Reppo/Core/Services/ServiceContainer.swift`.
2. Add a new property:
   ```swift
   let chartDataService: any ChartDataServiceProtocol
   ```
3. In the `init`, create ChartDataService after the repositories are available. ChartDataService depends only on repositories, not on other services. Add it early in the init:
   ```swift
   self.chartDataService = ChartDataService(
       setRepository: repositoryContainer.setRepository,
       workoutRepository: repositoryContainer.workoutRepository,
       exerciseRepository: repositoryContainer.exerciseRepository,
       exerciseStatsRepository: repositoryContainer.exerciseStatsRepository,
       performanceRecordRepository: repositoryContainer.performanceRecordRepository
   )
   ```
4. Place it after the existing repository-only services (e.g., after BodyweightService creation).

**Validation**:
- ServiceContainer compiles with the new property.
- ChartDataService receives all 5 repository dependencies.

---

### Subtask T005 – Create ChartsDashboardViewModel.swift

- **Purpose**: @Observable ViewModel for the Charts Dashboard. Holds state for overview data and exercise cards. Method stubs for loading.
- **File**: `Reppo/Features/Charts/ViewModels/ChartsDashboardViewModel.swift` (new file)
- **Parallel?**: No — depends on T003/T004.

**Steps**:
1. Create directory: `Reppo/Features/Charts/ViewModels/`.
2. Create the ViewModel:

```swift
import SwiftUI

@Observable
final class ChartsDashboardViewModel {

    // MARK: - State
    var overviewData: OverviewChartData?
    var exerciseCards: [ExerciseCardData] = []
    var isLoading: Bool = false
    var overviewLoaded: Bool = false
    var cardsLoaded: Bool = false

    var isEmpty: Bool {
        overviewData == nil && exerciseCards.isEmpty && !isLoading
    }

    // MARK: - Dependencies
    private let chartDataService: any ChartDataServiceProtocol

    init(chartDataService: any ChartDataServiceProtocol) {
        self.chartDataService = chartDataService
    }

    // MARK: - Data Loading

    func loadDashboard() async {
        guard !overviewLoaded else { return }
        isLoading = true
        await loadOverview()
        await loadExerciseCards()
        isLoading = false
    }

    func loadOverview() async {
        // Stub — implemented in WP02
    }

    func loadExerciseCards() async {
        // Stub — implemented in WP03
    }
}
```

**Validation**:
- ViewModel compiles with @Observable.
- Dependencies use protocol type (`any ChartDataServiceProtocol`).
- `isEmpty` computed property works correctly.

---

### Subtask T006 – Create ChartsDashboardView.swift

- **Purpose**: Main Charts tab screen with ScrollView, OVERVIEW section header, PER EXERCISE section header, and placeholder content. Wrapped in NavigationStack for drill-down navigation.
- **File**: `Reppo/Features/Charts/Views/ChartsDashboardView.swift` (new file)
- **Parallel?**: No — depends on T005.

**Steps**:
1. Create directory: `Reppo/Features/Charts/Views/`.
2. Create the view:

```swift
import SwiftUI

struct ChartsDashboardView: View {

    @State private var viewModel: ChartsDashboardViewModel

    init(chartDataService: any ChartDataServiceProtocol) {
        _viewModel = State(initialValue: ChartsDashboardViewModel(
            chartDataService: chartDataService
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // OVERVIEW section
                    overviewSection

                    // PER EXERCISE section
                    exerciseSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(Color.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Charts")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .task {
            await viewModel.loadDashboard()
        }
    }

    // MARK: - Overview Section

    @ViewBuilder
    private var overviewSection: some View {
        Text("OVERVIEW")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.textTertiary)
            .kerning(0.8)

        // Placeholder — WP02 will add 3 overview charts here
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            Text("Overview charts coming in WP02")
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    // MARK: - Exercise Section

    @ViewBuilder
    private var exerciseSection: some View {
        Text("PER EXERCISE")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.textTertiary)
            .kerning(0.8)

        // Placeholder — WP03 will add exercise card list here
        Text("Exercise cards coming in WP03")
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}
```

3. Follow the section header styling from ExerciseChartsView (11pt semibold, textTertiary, kerning 0.8).
4. The `.task` modifier triggers lazy data loading on first appear (FR-007, SC-003).

**Validation**:
- View renders with "Charts" title, OVERVIEW and PER EXERCISE section headers.
- Loading indicator shows during data fetch.
- Background is Color.bg (dark theme).

---

### Subtask T007 – Wire ChartsDashboardView into ContentView

- **Purpose**: Replace `ChartsPlaceholderView()` in ContentView with the new `ChartsDashboardView`.
- **File**: `Reppo/App/ContentView.swift` (edit existing file)
- **Parallel?**: No — depends on T006.

**Steps**:
1. Open `Reppo/App/ContentView.swift`.
2. Find `ChartsPlaceholderView()` in the TabView for `.charts` tab.
3. Replace with:
   ```swift
   ChartsDashboardView(
       chartDataService: services.chartDataService
   )
   ```
4. The `services` variable is `@Environment(ServiceContainer.self)` — already available. Access `chartDataService` from it (added in T004).

**Expected change**:
```swift
// Before:
ChartsPlaceholderView()
    .tabItem { Label("Charts", systemImage: "chart.line.uptrend.xyaxis") }
    .tag(MainTab.charts)

// After:
ChartsDashboardView(chartDataService: services.chartDataService)
    .tabItem { Label("Charts", systemImage: "chart.line.uptrend.xyaxis") }
    .tag(MainTab.charts)
```

**Validation**:
- App launches, Charts tab shows ChartsDashboardView with section headers.
- Other tabs still work correctly.
- No compiler errors.

---

## Risks & Mitigations

- **SetRepository `#Predicate` limitations**: SwiftData predicates don't support computed properties like `hasData`. Filter `hasData` in the service layer after fetching, not in the predicate.
- **ServiceContainer ordering**: ChartDataService depends only on repositories, so place it early in init (after repo-only services).
- **Type references**: `ExerciseDetailChartData` references `ExerciseChartData.ChartPoint` from `ExerciseModels.swift`. Ensure the import path is correct (both are in the same module).

## Definition of Done Checklist

- [ ] `ChartModels.swift` created with all chart data types
- [ ] `SetRepository` has 2 new date-range query methods (protocol + implementation)
- [ ] `ChartDataService.swift` created with protocol and actor, all method stubs
- [ ] `ServiceContainer.swift` updated with `chartDataService` property
- [ ] `ChartsDashboardViewModel.swift` created with @Observable, state, loading stubs
- [ ] `ChartsDashboardView.swift` created with section layout and NavigationStack
- [ ] `ContentView.swift` updated — ChartsPlaceholderView replaced
- [ ] App compiles without errors
- [ ] Charts tab appears in bottom nav and renders the new view

## Review Guidance

- Verify ChartModels types match data-model.md exactly.
- Verify SetRepository methods use `FetchDescriptor` with `#Predicate` — not raw Core Data queries.
- Verify ChartDataService is an `actor` (not `@ModelActor`), receives 5 repository dependencies.
- Verify ServiceContainer creates ChartDataService with correct repository references.
- Verify ViewModel uses `any ChartDataServiceProtocol` (protocol type, not concrete).
- Verify ChartsDashboardView uses `.task` for lazy loading (not `.onAppear` with Task {}).
- Verify NavigationStack wraps the view for future drill-down navigation.

## Activity Log

- 2026-02-28T08:13:27Z – claude – shell_pid=89491 – lane=doing – Started implementation via workflow command
- 2026-02-28T08:21:18Z – claude – shell_pid=89491 – lane=for_review – Ready for review: ChartModels, SetRepository date-range queries, ChartDataService actor with stubs, ServiceContainer wiring, ChartsDashboardViewModel/View, ContentView integration. BUILD SUCCEEDED with 0 errors.
- 2026-02-28T08:22:19Z – claude – shell_pid=91062 – lane=doing – Started review via workflow command
- 2026-02-28T08:23:40Z – claude – shell_pid=91062 – lane=done – Review passed: All 7 subtasks verified. ChartModels match data-model.md exactly. SetRepository uses FetchDescriptor+Predicate correctly. ChartDataService is actor with 5 repo deps and chartEligibleSets helper. ServiceContainer wired correctly. ViewModel uses protocol type. View uses .task and NavigationStack. ContentView replacement clean. BUILD SUCCEEDED with 0 errors.
