---
work_package_id: "WP05"
subtasks:
  - "T101"
  - "T102"
  - "T103"
  - "T104"
  - "T105"
  - "T106"
  - "T107"
  - "T108"
  - "T109"
  - "T110"
  - "T111"
  - "T112"
title: "Foundation — New Models, Enums, 3-Tab Shell, Shared Components"
phase: "Phase 0 - Foundation"
lane: "planned"
dependencies: []
agent: ""
assignee: ""
shell_pid: ""
reviewed_by: ""
review_status: ""
history:
  - timestamp: "2026-03-04T14:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated manually (spec-kitty format)"
---

# Work Package Prompt: WP05 – Foundation — New Models, Enums, 3-Tab Shell, Shared Components

## Objectives & Success Criteria

- Add all new enum and struct types to `ChartModels.swift` (BreakdownMetric, WorkoutsMetric, WorkoutsAggregation, WorkoutsFilter, WorkoutsTimeRange, BreakdownTimeRange, ExerciseMetric, BreakdownDataPoint, WorkoutsTimeSeriesPoint, ExerciseProgressSeries, ExerciseProgressPoint, TrendLineData).
- Create `TrendLineCalculator` utility for linear regression.
- Create `ChartsTabViewModel` coordinator with SubTab enum and 3 child VM stubs.
- Create `ChartsTabView` with 3-tab picker and tab content switching.
- Create 6 shared reusable components: ChartSubTabPicker, ChartDropdown, ChartTimePills, DataPointNavigator, TrendLineOverlay, ChartLegend.
- Wire `ChartsTabView` into `ContentView` replacing `ChartsDashboardView`.
- **Success**: Charts tab shows 3-tab picker (Breakdown/Workouts/Exercises). Each tab shows placeholder content. All new types compile. Shared components render. App builds without errors.

## Context & Constraints

- **Architecture**: MVVM with `@Observable` (iOS 17+). Views → ViewModels → Services → Repositories → SwiftData.
- **Constitution**: No third-party UI libs. Dark mode only. Swift Charts for charting. SF Symbols for icons.
- **Design tokens**: All colors from `Reppo/Core/Extensions/DesignTokens.swift`. Follow `design-system.md`.
- **Existing code**: Current Charts tab uses `ChartsDashboardView` — we're replacing it with `ChartsTabView`. Do NOT delete old files yet (that's WP10).
- **Key docs**: `kitty-specs/016-charts-tab-v2/data-model.md` (all type definitions), `kitty-specs/016-charts-tab-v2/plan.md` (architecture), `prototype-charts-tab.html` (visual reference).
- **Prototype**: Open `prototype-charts-tab.html` in a browser for visual reference of all tabs, dropdowns, pills, and components.

**Implementation command**: `spec-kitty implement WP05`

## Subtasks & Detailed Guidance

### Subtask T101 – Add New Enums to ChartModels.swift

- **Purpose**: Add all new enum types needed by the 3 chart tabs.
- **File**: `Reppo/Features/Charts/Models/ChartModels.swift` (edit — append below existing types)
- **Parallel?**: Yes

**Steps**:
1. Open existing `ChartModels.swift`.
2. Append the following enums BELOW existing types (do NOT modify existing types):

```swift
// MARK: - Charts Tab v2 Enums

enum BreakdownMetric: String, CaseIterable, Identifiable {
    case volumeByCategory = "Volume by Category"
    case setsByCategory = "Sets by Category"
    case repsByCategory = "Reps by Category"
    case workoutsByCategory = "Workouts by Category"
    case volumeByExercise = "Volume by Exercise"
    case setsByExercise = "Sets by Exercise"
    case repsByExercise = "Reps by Exercise"
    case workoutsByExercise = "Workouts by Exercise"

    var id: String { rawValue }

    var groupBy: BreakdownGroupBy {
        switch self {
        case .volumeByCategory, .setsByCategory, .repsByCategory, .workoutsByCategory: return .category
        case .volumeByExercise, .setsByExercise, .repsByExercise, .workoutsByExercise: return .exercise
        }
    }

    var aggregateType: BreakdownAggregateType {
        switch self {
        case .volumeByCategory, .volumeByExercise: return .volume
        case .setsByCategory, .setsByExercise: return .sets
        case .repsByCategory, .repsByExercise: return .reps
        case .workoutsByCategory, .workoutsByExercise: return .workouts
        }
    }
}

enum BreakdownGroupBy { case category, exercise }

enum BreakdownAggregateType { case volume, sets, reps, workouts }

enum BreakdownTimeRange: String, CaseIterable, Identifiable {
    case all = "All"
    case year = "Year"
    case month = "Month"
    case week = "Week"
    case day = "Day"

    var id: String { rawValue }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .all: return nil
        case .year: return cal.date(byAdding: .year, value: -1, to: Date())
        case .month: return cal.date(byAdding: .month, value: -1, to: Date())
        case .week: return cal.date(byAdding: .weekOfYear, value: -1, to: Date())
        case .day: return cal.startOfDay(for: Date())
        }
    }
}

enum WorkoutsMetric: String, CaseIterable, Identifiable {
    case reps = "Reps"
    case sets = "Sets"
    case volume = "Volume"
    case workouts = "Workouts"
    case distance = "Distance"
    case time = "Time"

    var id: String { rawValue }
}

enum WorkoutsAggregation: String, CaseIterable, Identifiable {
    case perWorkout = "Per Workout"
    case perWeek = "Per Week"
    case perMonth = "Per Month"
    case perYear = "Per Year"

    var id: String { rawValue }
}

enum WorkoutsFilter: Identifiable, Equatable, Hashable {
    case all
    case category(String)
    case exercise(UUID, name: String)

    var id: String {
        switch self {
        case .all: return "all"
        case .category(let name): return "cat:\(name)"
        case .exercise(let id, _): return "ex:\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .category(let name): return name
        case .exercise(_, let name): return name
        }
    }

    // Explicit Hashable conformance required for enums with associated values.
    // Needed by ChartDropdown<T: Hashable>.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum WorkoutsTimeRange: String, CaseIterable, Identifiable {
    case all = "All"
    case oneYear = "1y"
    case sixMonths = "6mo"
    case threeMonths = "3mo"
    case oneMonth = "1mo"

    var id: String { rawValue }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .all: return nil
        case .oneYear: return cal.date(byAdding: .year, value: -1, to: Date())
        case .sixMonths: return cal.date(byAdding: .month, value: -6, to: Date())
        case .threeMonths: return cal.date(byAdding: .month, value: -3, to: Date())
        case .oneMonth: return cal.date(byAdding: .month, value: -1, to: Date())
        }
    }
}

enum ExerciseMetric: String, CaseIterable, Identifiable {
    case estimatedOneRM = "Estimated 1RM"
    case maxWeight = "Max Weight"
    case maxReps = "Max Reps"
    case maxVolume = "Max Volume"
    case maxWeightForReps = "Max Weight for Reps"
    case workoutVolume = "Workout Volume"
    case workoutReps = "Workout Reps"
    case personalRecords = "Personal Records"
    case maxDistance = "Max Distance"
    case maxTime = "Max Time"
    case minPace = "Min Pace"

    var id: String { rawValue }

    var isWeightBased: Bool {
        switch self {
        case .maxDistance, .maxTime, .minPace: return false
        default: return true
        }
    }
}
```

**Validation**: All enums compile. `BreakdownMetric.volumeByCategory.groupBy == .category`. `WorkoutsTimeRange.sixMonths.startDate` returns a date 6 months ago.

---

### Subtask T102 – Add New Structs to ChartModels.swift

- **Purpose**: Add new data structures for the 3 chart tabs.
- **File**: `Reppo/Features/Charts/Models/ChartModels.swift` (edit — append below enums from T101)
- **Parallel?**: Yes

**Steps**:
1. Append below the enums:

```swift
// MARK: - Charts Tab v2 Data Structures

struct BreakdownDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

struct WorkoutsTimeSeriesPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String?
}

struct ExerciseProgressSeries: Identifiable {
    let id: UUID          // exerciseId
    let name: String
    let color: Color
    let points: [ExerciseProgressPoint]
}

struct ExerciseProgressPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct TrendLineData {
    let slope: Double
    let intercept: Double
    let startPoint: (x: Double, y: Double)
    let endPoint: (x: Double, y: Double)

    var isPositive: Bool { slope > 0 }
    var isNegative: Bool { slope < 0 }
    var formattedSlope: String { String(format: "%.2f", slope) }
}
```

**Validation**: All structs compile. `BreakdownDataPoint` and `WorkoutsTimeSeriesPoint` are `Identifiable`.

---

### Subtask T103 – Create TrendLineCalculator.swift

- **Purpose**: Pure utility for linear regression calculation. Used by Workouts and Exercises tabs for trend lines.
- **File**: `Reppo/Core/Utilities/TrendLineCalculator.swift` (new file)
- **Parallel?**: Yes

**Steps**:
1. Create the utility:

```swift
import Foundation

struct TrendLineCalculator {
    /// Computes simple linear regression on an array of (x, y) pairs.
    /// Returns nil if fewer than 2 points.
    static func compute(values: [Double]) -> TrendLineData? {
        guard values.count >= 2 else { return nil }

        let n = Double(values.count)
        let indices = values.indices.map { Double($0) }

        let xMean = indices.reduce(0, +) / n
        let yMean = values.reduce(0, +) / n

        var numerator: Double = 0
        var denominator: Double = 0

        for i in values.indices {
            let x = Double(i)
            numerator += (x - xMean) * (values[i] - yMean)
            denominator += (x - xMean) * (x - xMean)
        }

        guard denominator != 0 else { return nil }

        let slope = numerator / denominator
        let intercept = yMean - slope * xMean

        return TrendLineData(
            slope: slope,
            intercept: intercept,
            startPoint: (x: 0, y: intercept),
            endPoint: (x: Double(values.count - 1), y: slope * Double(values.count - 1) + intercept)
        )
    }
}
```

**Validation**: `TrendLineCalculator.compute(values: [1, 2, 3, 4, 5])` returns slope ≈ 1.0. `compute(values: [5])` returns nil. `compute(values: [])` returns nil.

---

### Subtask T104 – Create ChartsTabViewModel.swift

- **Purpose**: Coordinator ViewModel that owns the 3 sub-tab ViewModels and manages active tab state.
- **File**: `Reppo/Features/Charts/ViewModels/ChartsTabViewModel.swift` (new file)
- **Parallel?**: No — depends on T101

**Steps**:
```swift
import SwiftUI

@Observable
final class ChartsTabViewModel {

    enum SubTab: Int, CaseIterable {
        case breakdown = 0
        case workouts = 1
        case exercises = 2

        var title: String {
            switch self {
            case .breakdown: return "Breakdown"
            case .workouts: return "Workouts"
            case .exercises: return "Exercises"
            }
        }
    }

    // MARK: - State
    var activeTab: SubTab = .breakdown

    // MARK: - Dependencies
    let chartDataService: any ChartDataServiceProtocol
    let exerciseService: any ExerciseServiceProtocol

    init(chartDataService: any ChartDataServiceProtocol,
         exerciseService: any ExerciseServiceProtocol) {
        self.chartDataService = chartDataService
        self.exerciseService = exerciseService
    }
}
```

> **Cross-WP modification note**: `ChartsTabViewModel` will be modified by subsequent WPs to add child ViewModel properties:
> - WP06 adds `let breakdownVM: BreakdownTabViewModel`
> - WP07 adds `let workoutsVM: WorkoutsTabViewModel`
> - WP08 adds `let exercisesVM: ExercisesTabViewModel`
>
> For now the coordinator just holds the active tab and service dependencies. Child VMs are created and wired in their respective WPs.

**Validation**: Compiles. `SubTab.allCases.count == 3`.

---

### Subtask T105 – Create ChartsTabView.swift

- **Purpose**: Top-level Charts tab view with 3-tab picker and content switching.
- **File**: `Reppo/Features/Charts/Views/ChartsTabView.swift` (new file)
- **Parallel?**: No — depends on T104, T106

**Steps**:
```swift
import SwiftUI

struct ChartsTabView: View {

    @State private var viewModel: ChartsTabViewModel

    init(chartDataService: any ChartDataServiceProtocol,
         exerciseService: any ExerciseServiceProtocol) {
        _viewModel = State(initialValue: ChartsTabViewModel(
            chartDataService: chartDataService,
            exerciseService: exerciseService
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Page header
                HStack {
                    Text("Charts")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Sub-tab picker
                ChartSubTabPicker(
                    selectedTab: $viewModel.activeTab
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Tab content
                ScrollView {
                    tabContent
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100) // Bottom nav clearance
                }
            }
            .background(Color.bg)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab {
        case .breakdown:
            // Placeholder — WP06
            placeholderView("Breakdown chart coming in WP06")
        case .workouts:
            // Placeholder — WP07
            placeholderView("Workouts chart coming in WP07")
        case .exercises:
            // Placeholder — WP08
            placeholderView("Exercises chart coming in WP08")
        }
    }

    private func placeholderView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
```

**Validation**: View renders with "Charts" title, 3-tab picker, and placeholder content. Tab switching works.

---

### Subtask T106 – Create ChartSubTabPicker.swift

- **Purpose**: Horizontal pill bar for switching between Breakdown/Workouts/Exercises.
- **File**: `Reppo/Features/Charts/Views/Components/ChartSubTabPicker.swift` (new file)
- **Parallel?**: Yes

**Steps**:
```swift
import SwiftUI

struct ChartSubTabPicker: View {
    @Binding var selectedTab: ChartsTabViewModel.SubTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartsTabViewModel.SubTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? .white : Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selectedTab == tab ? Color.accent : Color.bgCard)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

**Validation**: 3 pills render. Active pill is accent blue with white text. Inactive pills are bgCard with dim text.

---

### Subtask T107 – Create ChartDropdown.swift

- **Purpose**: Reusable dropdown picker for chart option selection.
- **File**: `Reppo/Features/Charts/Views/Components/ChartDropdown.swift` (new file)
- **Parallel?**: Yes

**Steps**:
```swift
import SwiftUI

struct ChartDropdown<T: Identifiable & Hashable>: View {
    let title: String?
    let options: [T]
    @Binding var selected: T
    let labelFor: (T) -> String

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selected = option
                } label: {
                    HStack {
                        Text(labelFor(option))
                        if option.id == selected.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(labelFor(selected))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.border, lineWidth: 1)
            )
            .cornerRadius(10)
        }
    }
}
```

Uses SwiftUI `Menu` for native dropdown behavior (instead of custom popup). This matches iOS patterns and is gym-proof (large tap targets).

**Validation**: Dropdown shows selected value. Tapping opens native menu. Selecting an option updates binding.

---

### Subtask T108 – Create ChartTimePills.swift

- **Purpose**: Reusable horizontal time range pill bar.
- **File**: `Reppo/Features/Charts/Views/Components/ChartTimePills.swift` (new file)
- **Parallel?**: Yes

**Steps**:
```swift
import SwiftUI

struct ChartTimePills<T: Identifiable & Hashable>: View {
    let options: [T]
    @Binding var selected: T
    let labelFor: (T) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selected = option
                    }
                } label: {
                    Text(labelFor(option))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(option.id == selected.id ? .white : Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(option.id == selected.id ? Color.accent : Color.bgCard)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

**Validation**: Pills render. Active pill is accent. Tapping a pill updates the selection.

---

### Subtask T109 – Create DataPointNavigator.swift

- **Purpose**: Reusable ← → arrow navigation with value/date display. Used by Workouts and Exercises tabs.
- **File**: `Reppo/Features/Charts/Views/Components/DataPointNavigator.swift` (new file)
- **Parallel?**: Yes

**Steps**:
```swift
import SwiftUI

struct DataPointNavigator: View {
    let value: String?
    let subtitle: String?
    let promptText: String
    let hasPrevious: Bool
    let hasNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgSubtle)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .opacity(hasPrevious ? 1 : 0.3)
            .disabled(!hasPrevious)

            Spacer()

            if let value {
                VStack(spacing: 2) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                Text(promptText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgSubtle)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .opacity(hasNext ? 1 : 0.3)
            .disabled(!hasNext)
        }
        .padding(.top, 12)
    }
}
```

**Validation**: Shows arrows with value/date, or prompt text when no selection. Disabled arrows when at bounds.

---

### Subtask T110 – Create TrendLineOverlay.swift

- **Purpose**: Slope badge component showing trend direction and value.
- **File**: `Reppo/Features/Charts/Views/Components/TrendLineOverlay.swift` (new file)
- **Parallel?**: Yes

**Steps**:
```swift
import SwiftUI

struct SlopeBadge: View {
    let trendLine: TrendLineData

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trendLine.isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
            Text("Slope: \(trendLine.formattedSlope)")
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(trendLine.isPositive ? Color.success.opacity(0.08) : Color.danger.opacity(0.08))
        .foregroundStyle(trendLine.isPositive ? Color.success : Color.danger)
        .cornerRadius(6)
    }
}
```

**Validation**: Positive slope shows green with up-right arrow. Negative shows red with down-right arrow.

---

### Subtask T111 – Create ChartLegend.swift

- **Purpose**: Color-coded legend for donut chart segments and line chart series.
- **File**: `Reppo/Features/Charts/Views/Components/ChartLegend.swift` (new file)
- **Parallel?**: Yes

**Steps**:
```swift
import SwiftUI

struct ChartLegendItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String?
    let color: Color
}

struct ChartLegend: View {
    let items: [ChartLegendItem]
    var columns: Int = 2

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridItems, alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.color)
                        .frame(width: 10, height: 10)
                    Text(item.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    if let value = item.value {
                        Text(value)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
        }
    }
}
```

**Validation**: Renders grid of colored labels. Works with 2-8 items.

---

### Subtask T112 – Wire ChartsTabView into ContentView

- **Purpose**: Replace `ChartsDashboardView` with `ChartsTabView` in the Charts tab.
- **File**: `Reppo/App/ContentView.swift` (edit)
- **Parallel?**: No — depends on T105

**Steps**:
1. Find where `ChartsDashboardView` is used in the TabView for `.charts` tab.
2. Replace with:
```swift
ChartsTabView(
    chartDataService: services.chartDataService,
    exerciseService: services.exerciseService
)
```
3. Keep the same `.tabItem` and `.tag(MainTab.charts)`.

**Validation**: App launches. Charts tab shows new 3-tab picker. Other tabs unaffected.

---

## Risks & Mitigations

- **Generic constraints on ChartDropdown/ChartTimePills**: Ensure `T: Identifiable & Hashable` covers all enum types. All our enums use `String` rawValue which is `Hashable`.
- **WorkoutsFilter not Hashable by default**: `WorkoutsFilter` has associated values — implement `Hashable` conformance manually if needed.
- **Old ChartsDashboardView still exists**: That's fine — it's unreferenced after T112. Cleanup in WP10.

## Definition of Done Checklist

- [ ] All new enums added to ChartModels.swift and compile
- [ ] All new structs added to ChartModels.swift and compile
- [ ] TrendLineCalculator.swift created with linear regression
- [ ] ChartsTabViewModel.swift created with SubTab enum
- [ ] ChartsTabView.swift created with 3-tab layout
- [ ] ChartSubTabPicker.swift created
- [ ] ChartDropdown.swift created (generic)
- [ ] ChartTimePills.swift created (generic)
- [ ] DataPointNavigator.swift created
- [ ] TrendLineOverlay.swift (SlopeBadge) created
- [ ] ChartLegend.swift created
- [ ] ContentView.swift updated to use ChartsTabView
- [ ] App compiles without errors
- [ ] Charts tab shows 3-tab picker with tab switching

## Review Guidance

- Verify new types are APPENDED to ChartModels.swift — existing types not modified.
- Verify all enums conform to `CaseIterable` and `Identifiable` where needed.
- Verify TrendLineCalculator returns nil for < 2 points.
- Verify ChartsTabViewModel uses `any ChartDataServiceProtocol` (protocol type).
- Verify ChartsTabView uses `.background(Color.bg)` and follows design system spacing (20pt horizontal padding).
- Verify shared components use design token colors (bgCard, bgSubtle, textPrimary, textTertiary, accent, etc.).
- Verify ContentView correctly passes `services.chartDataService` and `services.exerciseService`.

## Activity Log
