# Quickstart: Exercise List + Detail

**Feature**: 007-exercise-list-and-detail
**Date**: 2026-02-25

## Prerequisites

- Xcode (latest stable) with iOS 17.0+ SDK
- Feature 006 (Active Workout) merged to main
- Feature 012 (Seed Exercise Library) recommended for test data (or manually create exercises)

## What's Already Built

The **entire data layer** is complete. You do NOT need to create or modify:

- SwiftData models: `Exercise`, `ExerciseStats`, `PerformanceRecord`, `WorkoutSet`, `Workout`
- Repositories: `ExerciseRepository`, `ExerciseStatsRepository`, `PerformanceRecordRepository`, `SetRepository`
- Services: `ExerciseService`, `PRService`, `StatsService`, `SetService`, `WorkoutService`
- Container wiring: `RepositoryContainer`, `ServiceContainer`
- Design tokens: `DesignTokens.swift`
- Existing components: `PRBadgeView`, `SetRowView`, `ExerciseTabStripView`

## What This Feature Builds

All new code goes in `Reppo/Features/Exercise/` (new directory) plus modifications to:
- `Reppo/App/ContentView.swift` — replace placeholder with TabView shell
- `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` — add sub-tabs
- `Reppo/Features/Workout/Views/ExercisePickerSheet.swift` — delete (replaced by ExerciseListView)

## Build Order

1. **Tab Shell** → `ContentView.swift` with 5-tab layout + FAB
2. **Exercise List** → `ExerciseListView` + `ExerciseListViewModel` + `ExerciseCardView`
3. **Exercise Detail** → `ExerciseDetailView` + tabs (History, PRs, Charts)
4. **Create/Edit Sheet** → `CreateEditExerciseSheet` + form ViewModel
5. **Active Workout Retrofit** → Add sub-tabs to `ActiveWorkoutView`, delete `ExercisePickerSheet`
6. **Integration** → Wire navigation, test all flows end-to-end

## Key Patterns to Follow

```swift
// ViewModel pattern (per AGENT_RULES)
@Observable @MainActor
final class ExerciseListViewModel {
    private let exerciseService: any ExerciseServiceProtocol
    // ... state properties
}

// View pattern
struct ExerciseListView: View {
    @State private var viewModel: ExerciseListViewModel
    @Environment(ServiceContainer.self) private var services
}

// Design tokens (per DesignTokens.swift)
Color.bgCard      // Card backgrounds
Color.accent       // Active states
Color.textPrimary  // Main text
Color.textTertiary // Labels, secondary info
```

## Test Flows

1. **Browse**: FAB → Exercise List → search "squat" → filter "Quads" → tap card → Exercise Detail → History/PRs/Charts tabs
2. **Selection**: FAB → Exercise List → select 3 exercises → "Start Workout (3)" → Active Workout opens
3. **Create**: Exercise List → [+ New] → fill form → save → exercise appears in list
4. **Edit**: Exercise Detail → Edit → modify fields → save → verify trackingType locked if sets exist
5. **Active Workout Sub-tabs**: Active Workout → select exercise → [History] tab → [Charts] tab → [Sets] tab
6. **Add from Workout**: Active Workout → [+Exercise] → Exercise List (selection mode) → select → "Add (N)"
