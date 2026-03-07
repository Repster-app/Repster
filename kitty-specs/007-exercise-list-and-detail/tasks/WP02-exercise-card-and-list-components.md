---
work_package_id: "WP02"
subtasks:
  - "T006"
  - "T007"
  - "T008"
  - "T009"
  - "T010"
title: "Exercise Card & List Components"
phase: "Phase 0 - Foundation"
lane: "done"
assignee: "claude"
agent: "claude"
shell_pid: "74069"
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

# Work Package Prompt: WP02 - Exercise Card & List Components

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
spec-kitty implement WP02 --base WP01
```

---

## Objectives & Success Criteria

- Build `ExerciseListViewModel` that loads exercises + stats, supports search/filter/sort, and manages selection state
- Build reusable `ExerciseCardView` matching design-system.md card patterns
- Build `MuscleFilterStrip` (horizontal pill strip) and `SortOptionMenu` components
- Create supporting types (`WorkoutHistoryGroup`, `ExerciseChartData`)
- **Success**: ViewModel loads exercises and stats, filters by muscle group, sorts by all 3 options, search works. Card displays all required fields with proper styling. Components render correctly.

## Context & Constraints

- **Constitution**: `@Observable @MainActor` for ViewModels, Views call ViewModels only, dark mode tokens from `DesignTokens.swift`
- **Plan**: `kitty-specs/007-exercise-list-and-detail/plan.md` - Decisions 5 (client-side muscle filter), 6 (sort options), 8 (card data)
- **Contracts**: `kitty-specs/007-exercise-list-and-detail/contracts/view-contracts.md` - ExerciseListViewModel interface, ExerciseCardView interface
- **Design system**: `design-system.md` Section 6.2 (cards: bgCard, 14pt radius, 14pt padding), Section 6.1 (filter pills: bgCard inactive, accent active)
- **Data layer**: `ExerciseService.fetchAllExercises()`, `ExerciseService.searchExercises(name:)`, `StatsService.fetchAllStats()` for stats. All exist and work.

## Subtasks & Detailed Guidance

### Subtask T006 - Create ExerciseListViewModel

- **Purpose**: Central ViewModel powering the Exercise List with search, filter, sort, and selection state.
- **File**: `Reppo/Features/Exercise/ViewModels/ExerciseListViewModel.swift`
- **Steps**:
  1. Create the ViewModel class:
     ```swift
     @Observable @MainActor
     final class ExerciseListViewModel {
         // Dependencies
         private let exerciseService: any ExerciseServiceProtocol
         private let statsService: any StatsServiceProtocol

         // Raw data
         private var allExercises: [Exercise] = []
         var allExerciseStats: [UUID: ExerciseStats] = [:]

         // Display state
         var exercises: [Exercise] = []         // Filtered + sorted for display
         var searchText: String = ""
         var selectedMuscleFilters: Set<String> = []
         var sortOrder: ExerciseListSortOrder = .alphabetical
         var selectedExerciseIds: Set<UUID> = []
         var isLoading: Bool = false
         var availableMuscleGroups: [String] = []

         // Mode
         let mode: ExerciseListMode
     }
     ```

  2. Implement `loadExercises()`:
     - Call `exerciseService.fetchAllExercises()` to get all exercises
     - Fetch `ExerciseStats` for each exercise (batch fetch or iterate)
     - Store in `allExercises` and `allExerciseStats`
     - Derive `availableMuscleGroups` from `allExercises.compactMap { $0.primaryMuscle }` unique + sorted
     - Call `applyFiltersAndSort()` to populate `exercises`

  3. Implement `applyFiltersAndSort()` (private, called whenever search/filter/sort changes):
     - Start with `allExercises`
     - **Search filter**: If `searchText` is not empty, filter by `exercise.name.localizedCaseInsensitiveContains(searchText)`
     - **Muscle filter**: If `selectedMuscleFilters` is not empty, filter by `selectedMuscleFilters.contains(exercise.primaryMuscle ?? "")`
     - **Sort**: Apply `sortOrder`:
       - `.alphabetical`: Sort by `name` ascending
       - `.mostRecent`: Sort by `allExerciseStats[id]?.lastPerformedDate` descending (nil = last)
       - `.mostUsed`: Sort by `allExerciseStats[id]?.totalWorkouts` descending (nil/0 = last)
     - Assign result to `exercises`

  4. Add property observers or use `withObservationTracking` to re-apply filters when `searchText`, `selectedMuscleFilters`, or `sortOrder` change. A simple approach: use `didSet` on each property to call `applyFiltersAndSort()`.

  5. Implement selection methods:
     ```swift
     func toggleSelection(_ exerciseId: UUID) {
         if selectedExerciseIds.contains(exerciseId) {
             selectedExerciseIds.remove(exerciseId)
         } else {
             selectedExerciseIds.insert(exerciseId)
         }
     }

     func clearSelection() {
         selectedExerciseIds.removeAll()
     }

     var selectedCount: Int { selectedExerciseIds.count }
     var hasSelection: Bool { !selectedExerciseIds.isEmpty }
     ```

  6. Implement `deleteExercise(_ exerciseId: UUID)`:
     - Call `exerciseService.deleteExercise(exerciseId)`
     - Remove from `allExercises` and `allExerciseStats`
     - Re-apply filters

- **Notes**: The ViewModel uses `StatsService.fetchAllStats()` to batch-load all ExerciseStats. This is a thin pass-through to the repository, keeping the architecture clean (ViewModels never call repositories directly per constitution).
- **Parallel?**: No - other components depend on this ViewModel.

### Subtask T007 - Create MuscleFilterStrip

- **Purpose**: Horizontal scrollable pill strip for filtering exercises by muscle group.
- **File**: `Reppo/Features/Exercise/Views/Components/MuscleFilterStrip.swift`
- **Steps**:
  1. Create the component:
     ```swift
     struct MuscleFilterStrip: View {
         let muscleGroups: [String]
         @Binding var selectedFilters: Set<String>

         var body: some View {
             ScrollView(.horizontal, showsIndicators: false) {
                 HStack(spacing: 8) {
                     ForEach(muscleGroups, id: \.self) { muscle in
                         MuscleFilterPill(
                             title: muscle,
                             isSelected: selectedFilters.contains(muscle),
                             action: { toggleFilter(muscle) }
                         )
                     }
                 }
                 .padding(.horizontal, 20)
             }
         }
     }
     ```

  2. Create `MuscleFilterPill` (private sub-view):
     ```swift
     private struct MuscleFilterPill: View {
         let title: String
         let isSelected: Bool
         let action: () -> Void

         var body: some View {
             Button(action: action) {
                 Text(title)
                     .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                     .foregroundStyle(isSelected ? .white : Color.textTertiary)
                     .padding(.vertical, 7)
                     .padding(.horizontal, 14)
                     .background(isSelected ? Color.accent : Color.bgCard)
                     .cornerRadius(8)
             }
         }
     }
     ```

  3. Per design-system.md Section 6.1: no horizontal screen padding on the strip (bleeds to edges), 20pt internal padding. Active = accent bg + white text. Inactive = bgCard + textTertiary.
  4. Multiple filters can be active simultaneously (per spec edge case).

- **Parallel?**: Yes - independent component file.

### Subtask T008 - Create SortOptionMenu

- **Purpose**: Sort picker with 3 options matching the spec's sort requirements.
- **File**: `Reppo/Features/Exercise/Views/Components/SortOptionMenu.swift`
- **Steps**:
  1. Create the component:
     ```swift
     struct SortOptionMenu: View {
         @Binding var sortOrder: ExerciseListSortOrder

         var body: some View {
             Menu {
                 ForEach(ExerciseListSortOrder.allCases, id: \.self) { order in
                     Button {
                         sortOrder = order
                     } label: {
                         HStack {
                             Text(order.rawValue)
                             if sortOrder == order {
                                 Image(systemName: "checkmark")
                             }
                         }
                     }
                 }
             } label: {
                 HStack(spacing: 4) {
                     Image(systemName: "arrow.up.arrow.down")
                     Text(sortOrder.rawValue)
                         .font(.system(size: 13, weight: .medium))
                 }
                 .foregroundStyle(Color.textSecondary)
                 .padding(.vertical, 6)
                 .padding(.horizontal, 12)
                 .background(Color.bgCard)
                 .cornerRadius(8)
             }
         }
     }
     ```

- **Parallel?**: Yes - independent component file.

### Subtask T009 - Create ExerciseCardView

- **Purpose**: Reusable card showing exercise summary data per spec FR-004.
- **File**: `Reppo/Features/Exercise/Views/ExerciseCardView.swift`
- **Steps**:
  1. Create the card matching design-system.md Section 6.2:
     ```swift
     struct ExerciseCardView: View {
         let exercise: Exercise
         let stats: ExerciseStats?
         let isSelected: Bool
         let mode: ExerciseListMode

         var onSelectionToggle: (() -> Void)?  // Tap handler for selection circle

         var body: some View {
             HStack(spacing: 12) {
                 // Leading: Selection circle (visible in both modes)
                 Button {
                     onSelectionToggle?()
                 } label: {
                     Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                         .font(.system(size: 22))
                         .foregroundStyle(isSelected ? Color.accent : Color.textTertiary.opacity(0.5))
                 }
                 .buttonStyle(.plain)

                 // Left: Exercise info
                 VStack(alignment: .leading, spacing: 4) {
                     Text(exercise.name)
                         .font(.system(size: 15, weight: .semibold))
                         .foregroundStyle(Color.textPrimary)

                     HStack(spacing: 8) {
                         if let muscle = exercise.primaryMuscle {
                             Text(muscle)
                                 .font(.system(size: 12))
                                 .foregroundStyle(Color.textTertiary)
                         }
                         Text(exercise.equipmentType.displayName)
                             .font(.system(size: 12))
                             .foregroundStyle(Color.textTertiary)
                     }

                     HStack(spacing: 8) {
                         // Last performed
                         if let lastDate = stats?.lastPerformedDate {
                             Text(lastDate, style: .date)
                                 .font(.system(size: 11))
                                 .foregroundStyle(Color.textTertiary)
                         } else {
                             Text("Never performed")
                                 .font(.system(size: 11))
                                 .foregroundStyle(Color.textTertiary)
                         }
                     }
                 }

                 Spacer()

                 // Right: Best lift + selection indicator
                 VStack(alignment: .trailing, spacing: 4) {
                     if let maxWeight = stats?.maxWeight, maxWeight > 0 {
                         Text(formatWeight(maxWeight))
                             .font(.system(size: 14, weight: .bold))
                             .foregroundStyle(Color.textPrimary)
                         Text("Best")
                             .font(.system(size: 10))
                             .foregroundStyle(Color.textTertiary)
                     }

                     // Selection indicator moved to leading circle
                 }
             }
             .padding(14)
             .background(isSelected ? Color.accentSoft : Color.bgCard)
             .cornerRadius(14)
         }
     }
     ```

  2. Card must show: name, primaryMuscle, equipmentType, trackingType badge, lastPerformedDate, best lift (maxWeight from ExerciseStats).
  3. Handle nil stats gracefully (new exercise with no workout history).
  4. Selection state: Leading circle toggles selection (empty circle → filled checkmark). Background changes to `accentSoft` when selected. The `onSelectionToggle` closure is called when the circle is tapped — in browse mode this toggles selection without navigating; in addToWorkout mode the entire card toggles (circle is an additional tap target).
  5. `EquipmentType` needs a `displayName` computed property. Check if it already exists on the enum; if not, add a simple extension.
  6. Weight formatting: Use `HealthProfile.unitPreference` to display kg or lbs. For now, display raw kg with "kg" suffix. Unit conversion helpers exist in `UnitConversion.swift`.

- **Notes**: Card should meet 44pt minimum tap target (the entire card is tappable).
- **Parallel?**: Yes - independent view file.

### Subtask T010 - Create supporting types

- **Purpose**: Define data structures used by Exercise Detail views (needed by WP04).
- **File**: `Reppo/Features/Exercise/Models/ExerciseModels.swift`
- **Steps**:
  1. Create `WorkoutHistoryGroup`:
     ```swift
     struct WorkoutHistoryGroup: Identifiable {
         let id: UUID    // workoutId
         let date: Date
         let sets: [WorkoutSet]
     }
     ```

  2. Create `ExerciseChartData`:
     ```swift
     struct ExerciseChartData {
         let e1RMPoints: [ChartPoint]
         let volumePerSession: [VolumePoint]

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

  3. These are plain value types, not SwiftData models. They exist purely for ViewModel -> View data passing.

- **Parallel?**: Yes - independent model file.

## Risks & Mitigations

- **ExerciseStats fetch performance**: Loading stats for all ~200 exercises at once could be slow if done one-by-one. Use `StatsService.fetchAllStats()` to batch-fetch, then map by exerciseId.
- **EquipmentType.displayName**: The `EquipmentType` enum may not have user-friendly display names. Check the existing enum and add an extension if needed (e.g., `.barbell` -> "Barbell", `.machinePlate` -> "Machine (Plate)").
- **Filter interaction**: When search text is active AND muscle filters are selected, both should apply (AND logic). Test edge case of conflicting filters returning zero results.

## Definition of Done Checklist

- [ ] `ExerciseListViewModel` loads exercises + stats, search/filter/sort all work
- [ ] `MuscleFilterStrip` renders horizontal pills, multiple selection works
- [ ] `SortOptionMenu` switches between 3 sort orders
- [ ] `ExerciseCardView` displays all required fields with proper dark mode styling
- [ ] Supporting types (`WorkoutHistoryGroup`, `ExerciseChartData`) compile correctly
- [ ] All components use `DesignTokens.swift` colors (no hardcoded colors)
- [ ] `tasks.md` updated with status change

## Review Guidance

- Verify `ExerciseListViewModel` uses `@Observable @MainActor final class` pattern
- Verify card layout matches design-system.md Section 6.2
- Verify filter pill styling matches design-system.md Section 6.1
- Verify nil stats are handled gracefully in cards
- Verify sort applies correctly for all 3 options

## Activity Log

- 2026-02-25T08:19:17Z - system - lane=planned - Prompt created.
- 2026-02-26T14:42:15Z – claude – shell_pid=74069 – lane=doing – Started implementation via workflow command
- 2026-02-26T14:55:44Z – claude – shell_pid=74069 – lane=for_review – Ready for review: ExerciseListViewModel with search/filter/sort, MuscleFilterStrip, SortOptionMenu, ExerciseCardView, supporting types. Added fetchAllStats() to StatsService and displayName to EquipmentType. Build succeeds zero errors.
- 2026-02-26T20:20:31Z – claude – shell_pid=74069 – lane=done – Review passed: ExerciseListViewModel, MuscleFilterStrip, SortOptionMenu, ExerciseCardView, ExerciseModels all correctly implemented. Dual-mode filtering, sorting, and stats loading match spec. Type signatures verified ([UUID: ExerciseStats]). All DoD items met.
