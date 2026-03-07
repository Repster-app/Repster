# View & ViewModel Contracts: Exercise List + Detail

**Feature**: 007-exercise-list-and-detail
**Date**: 2026-02-25

These contracts define the public interfaces for new Views and ViewModels. Since this is a UI-only feature on an iOS app (no REST API), contracts are defined as Swift protocol/interface specifications.

---

## ViewModels

### ExerciseListViewModel

```swift
@Observable @MainActor
final class ExerciseListViewModel {
    // MARK: - State
    var exercises: [Exercise]              // Filtered/sorted list for display
    var allExerciseStats: [UUID: ExerciseStats]  // Stats keyed by exerciseId
    var searchText: String
    var selectedMuscleFilters: Set<String>  // Active muscle group filters
    var sortOrder: ExerciseListSortOrder
    var selectedExerciseIds: Set<UUID>      // Selection mode selections
    var isLoading: Bool
    var availableMuscleGroups: [String]     // Derived from loaded exercises

    // MARK: - Computed
    var selectedCount: Int                  // selectedExerciseIds.count
    var hasSelection: Bool                  // !selectedExerciseIds.isEmpty

    // MARK: - Init
    init(mode: ExerciseListMode,
         exerciseService: any ExerciseServiceProtocol,
         statsService: any StatsServiceProtocol)

    // MARK: - Actions
    func loadExercises() async              // Fetch all + stats, apply filters
    func toggleSelection(_ exerciseId: UUID)  // Toggle in selectedExerciseIds
    func clearSelection()
    func deleteExercise(_ exerciseId: UUID) async  // Cascade delete via ExerciseService
}
```

### ExerciseDetailViewModel

```swift
@Observable @MainActor
final class ExerciseDetailViewModel {
    // MARK: - State
    var exercise: Exercise?
    var stats: ExerciseStats?
    var prTable: [PRTableEntry]            // Suffix-max filtered
    var historyWorkouts: [WorkoutHistoryGroup]  // Sets grouped by workout
    var chartData: ExerciseChartData?
    var isLoading: Bool
    var hasSets: Bool                      // For trackingType lock check

    // MARK: - Init
    init(exerciseId: UUID,
         exerciseService: any ExerciseServiceProtocol,
         prService: any PRServiceProtocol,
         setService: any SetServiceProtocol,
         statsService: any StatsServiceProtocol,
         workoutService: any WorkoutServiceProtocol)

    // MARK: - Actions
    func loadAll() async                   // Fetch exercise, stats, PRs, history, charts
    func loadHistory() async               // Fetch history tab data only
    func loadPRs() async                   // Fetch PR table only
    func loadCharts() async                // Fetch chart data only
    func deleteExercise() async            // Cascade delete
}
```

### CreateEditExerciseViewModel

```swift
@Observable @MainActor
final class CreateEditExerciseViewModel {
    // MARK: - State (form fields)
    var name: String
    var equipmentType: EquipmentType
    var trackingType: TrackingType
    var primaryMuscle: String
    var secondaryMuscles: [String]
    var movementPattern: MovementPattern?
    var unilateral: Bool
    var bilateralLoadFactor: Double?
    var bodyweightFactor: Double
    var weightIncrement: Double?
    var defaultRestTime: Int?

    // MARK: - UI State
    var isEditing: Bool                    // true = edit mode, false = create mode
    var isTrackingTypeLocked: Bool         // true when exercise has sets
    var isSaving: Bool
    var validationErrors: [String]

    // MARK: - Computed
    var isValid: Bool                      // Name not empty + required fields set
    var navigationTitle: String            // "New Exercise" or "Edit Exercise"

    // MARK: - Init
    init(exercise: Exercise?,              // nil = create, non-nil = edit
         exerciseService: any ExerciseServiceProtocol)

    // MARK: - Actions
    func save() async throws              // Create or update via ExerciseService
    func checkTrackingTypeLock() async     // Query exerciseHasSets()
}
```

---

## Supporting Types

### WorkoutHistoryGroup

```swift
struct WorkoutHistoryGroup: Identifiable {
    let id: UUID              // workoutId
    let date: Date
    let sets: [WorkoutSet]
}
```

Groups sets by workout for the History tab display. Sorted newest first.

### ExerciseChartData

```swift
struct ExerciseChartData {
    let e1RMPoints: [ChartPoint]          // date + e1RM value
    let volumePerSession: [VolumePoint]   // date + total volume

    struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    struct VolumePoint: Identifiable {
        let id = UUID()
        let date: Date
        let volume: Double
    }
}
```

---

## Views — Public Interface

### ExerciseListView

```swift
struct ExerciseListView: View {
    init(mode: ExerciseListMode,
         onExercisesSelected: (([UUID]) -> Void)?,  // Callback for addToWorkout mode
         services: ServiceContainer)
}
```

- `mode: .browse` — standalone screen, tap card pushes detail
- `mode: .addToWorkout` — sheet presentation, tap toggles selection, confirm button calls `onExercisesSelected`

### ExerciseDetailView

```swift
struct ExerciseDetailView: View {
    init(exerciseId: UUID, services: ServiceContainer)
}
```

Reusable in any NavigationStack context. Internally manages its own ViewModel.

### ExerciseHistoryView / ExerciseChartsView (Reusable Sub-Views)

```swift
struct ExerciseHistoryView: View {
    init(exerciseId: UUID, services: ServiceContainer)
}

struct ExerciseChartsView: View {
    init(exerciseId: UUID, services: ServiceContainer)
}
```

Used both inside `ExerciseDetailView` tabs and embedded in `ActiveWorkoutView` sub-tabs.

### CreateEditExerciseSheet

```swift
struct CreateEditExerciseSheet: View {
    init(exercise: Exercise?,              // nil = create, non-nil = edit
         services: ServiceContainer,
         onSave: (() -> Void)?)            // Refresh callback
}
```

### ExerciseCardView

```swift
struct ExerciseCardView: View {
    init(exercise: Exercise,
         stats: ExerciseStats?,
         isSelected: Bool,                 // Selection mode highlight
         mode: ExerciseListMode)
}
```

Reusable card matching design-system.md Section 6.2 card patterns.
