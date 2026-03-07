# Research: Exercise List + Detail

**Feature**: 007-exercise-list-and-detail
**Date**: 2026-02-25

## Research Tasks & Findings

### R1: Tab Bar with Center FAB in SwiftUI

**Decision**: Custom `TabView` with a center button overlay.

**Rationale**: SwiftUI's native `TabView` doesn't support a center FAB natively. The standard approach is to use a `TabView` with 4 real tabs (Programs, Calendar, Charts, Settings) plus a dummy center tab that is intercepted. The FAB button is overlaid on top of the tab bar.

**Implementation pattern**:
```swift
TabView(selection: $selectedTab) {
    // 4 real tabs
}
.overlay(alignment: .bottom) {
    // FAB button centered on tab bar
}
```

The FAB tap navigates to `ExerciseListView` via the active tab's NavigationStack, or presents it in a dedicated flow. Per screen_tree.md, the FAB behavior is context-aware:
- No active workout → Push `ExerciseListView` in browse mode
- Active workout exists → Navigate back to active workout

**Alternatives considered**:
- UIKit `UITabBarController` wrapper — rejected (SwiftUI-first per constitution)
- Custom tab bar from scratch — rejected (unnecessary complexity, native `TabView` with overlay is sufficient)

### R2: Exercise List Search Performance

**Decision**: Use existing `ExerciseRepository.search(name:)` for search, client-side filter for muscle groups.

**Rationale**: `ExerciseRepository.search(name:)` already uses `localizedStandardContains` at the SwiftData level, which is efficient. For muscle group filtering, client-side filtering of ~200 exercises is well within performance targets (< 200ms). The exercise list will load all exercises once, then filter/search/sort in the ViewModel.

**Alternatives considered**:
- Server-side / repository-level muscle filter — rejected (over-engineering for ~200 items)
- Combined search+filter repository query — rejected (adds complexity to repository layer for negligible performance gain)

### R3: Exercise Detail as Reusable Component

**Decision**: `ExerciseDetailView` takes `exerciseId: UUID` and creates its own `ExerciseDetailViewModel` internally.

**Rationale**: The component must work in 3 contexts (pushed from List, pushed from Calendar, embedded in Active Workout). The simplest API is a single `exerciseId` parameter. The ViewModel handles all data loading internally.

**Implementation pattern**:
```swift
struct ExerciseDetailView: View {
    let exerciseId: UUID
    @State private var viewModel: ExerciseDetailViewModel

    init(exerciseId: UUID, services: ServiceContainer) {
        self.exerciseId = exerciseId
        self._viewModel = State(initialValue: ExerciseDetailViewModel(
            exerciseId: exerciseId,
            services: services
        ))
    }
}
```

When embedded in Active Workout as sub-tabs, only the History and Charts tabs are shown (PRs tab is not needed in workout context per screen_tree.md Section 3).

**Alternatives considered**:
- Pass pre-loaded data to the view — rejected (creates coupling, each context would need to pre-fetch differently)
- Singleton shared ViewModel — rejected (violates per-screen ownership)

### R4: Swift Charts for Exercise Trends

**Decision**: Functional minimum using `Chart { LineMark(...) }` for e1RM and `Chart { BarMark(...) }` for volume.

**Rationale**: Feature 009 (Charts Tab) will establish the full charting pattern library. Feature 007 only needs basic charts in the Exercise Detail view. Using Swift Charts (native, per constitution) with minimal styling.

**Data source for charts**:
- e1RM trend: Fetch recent `WorkoutSet` rows for this exercise where `e1RM > 0`, plot date vs e1RM
- Volume per session: Fetch sets grouped by workoutId, sum `effectiveWeight * reps` per workout, plot as bars

Both queries go through `SetRepository` with appropriate limits (e.g., last 20 sessions).

**Alternatives considered**:
- Pre-computed chart data in ExerciseStats — not available (ExerciseStats has aggregate totals, not time-series)
- Third-party chart library — rejected (constitution: Swift Charts only)

### R5: Active Workout Sub-Tab Integration

**Decision**: Add sub-tab picker as `@State` in `ActiveWorkoutView`, reuse `ExerciseHistoryView` and `ExerciseChartsView` from Exercise Detail.

**Rationale**: Sub-tab selection is purely UI state (no business logic), so `@State` in the View is appropriate per MVVM rules. The reusable views from Exercise Detail accept an `exerciseId` and load their own data, making integration straightforward.

**Changes to ActiveWorkoutView**:
1. Add `@State private var selectedSubTab: ExerciseSubTab = .sets`
2. Add a segmented/pill picker below the exercise tab strip: `[Sets] [History] [Charts]`
3. Switch content based on `selectedSubTab`
4. Reset to `.sets` when switching exercises

**Changes to ActiveWorkoutViewModel**: None required. Sub-tab state is View-local.

### R6: Exercise List Mode Architecture

**Decision**: Single `ExerciseListView` with a `mode` enum parameter controlling behavior.

**Rationale**: Browse mode and selection mode share 90% of the UI (search, filter, sort, card display). The differences are:
- Browse: tap → push detail; [+ New] visible; "Start Workout (N)" appears on selection
- Selection (from Active Workout): tap → toggle; "Add (N)" confirm button; presented as sheet

A single view with mode parameter avoids code duplication.

```swift
enum ExerciseListMode {
    case browse          // FAB entry, standalone screen
    case addToWorkout    // From Active Workout [+Exercise], sheet presentation
}
```

**Alternatives considered**:
- Two separate views — rejected (90% code duplication)
- Mode derived from environment — rejected (explicit is clearer)

### R7: Muscle Group List for Filter Pills

**Decision**: Derive unique muscle groups from the loaded exercise list at runtime.

**Rationale**: The specdoc does not define a fixed enum for muscle groups — `primaryMuscle` is a `String?` field. The filter pills should show only muscle groups that exist in the user's exercise library. This is computed by mapping `exercises.compactMap { $0.primaryMuscle }` and extracting unique values.

For the seed library (Feature 012), common values will include: Chest, Back, Shoulders, Quads, Hamstrings, Glutes, Biceps, Triceps, Core, Calves, Forearms.

**Alternatives considered**:
- Hardcoded muscle group list — rejected (won't match custom exercises)
- Enum type for primaryMuscle — rejected (specdoc uses String, not enum)

### R8: ExercisePickerSheet Replacement Strategy

**Decision**: Replace `ExercisePickerSheet.swift` with a thin wrapper that presents `ExerciseListView` in `.addToWorkout` mode.

**Rationale**: The current stub does basic multi-select with search only. Feature 007's `ExerciseListView` in `.addToWorkout` mode provides full search + filter + sort + selection. The existing `ExercisePickerSheet.swift` file can either be:
1. Gutted and rewritten as a wrapper that presents `ExerciseListView(mode: .addToWorkout)`
2. Deleted entirely, with `ActiveWorkoutView` presenting `ExerciseListView` directly

**Decision**: Option 2 — delete `ExercisePickerSheet.swift` and present `ExerciseListView(mode: .addToWorkout)` directly from `ActiveWorkoutView`. This avoids an unnecessary wrapper layer.

**Changes needed in ActiveWorkoutView**:
- Replace `.sheet(isPresented: $viewModel.showAddExerciseSheet) { ExercisePickerSheet(...) }` with `.sheet(isPresented: $viewModel.showAddExerciseSheet) { ExerciseListView(mode: .addToWorkout, ...) }`
