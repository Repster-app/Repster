---
work_package_id: "WP03"
subtasks:
  - "T011"
  - "T012"
  - "T013"
  - "T014"
  - "T015"
title: "Exercise List View & Dual Mode"
phase: "Phase 1 - Core Screens"
lane: "done"
assignee: "claude"
agent: "claude"
shell_pid: "76039"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP02"]
history:
  - timestamp: "2026-02-25T08:19:17Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 - Exercise List View & Dual Mode

## IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Implementation Command

Depends on WP02:
```bash
spec-kitty implement WP03 --base WP02
```

---

## Objectives & Success Criteria

- Assemble `ExerciseListView` composing the search bar, muscle filter strip, sort menu, and exercise card list
- Implement browse mode: tap card navigates to Exercise Detail (navigation destination wired, even if detail is a stub)
- Implement selection mode: tap toggles selection, "Start Workout (N)" or "Add (N)" button appears at bottom
- Handle empty state (zero exercises) and no-results state (search/filter returns nothing)
- **Success**: Exercise List displays with functional search, filter, sort. Both modes work correctly. Empty and no-results states display appropriately.

## Context & Constraints

- **Spec**: User Story 1 (browse mode), User Story 2 (selection mode), Edge Cases (empty state, no results)
- **Plan**: `kitty-specs/007-exercise-list-and-detail/plan.md` - Decision 2 (Dual Mode)
- **Contracts**: `kitty-specs/007-exercise-list-and-detail/contracts/view-contracts.md` - ExerciseListView interface
- **Components from WP02**: `ExerciseListViewModel`, `ExerciseCardView`, `MuscleFilterStrip`, `SortOptionMenu`
- **Spec FR-001 to FR-005**: Search, filter, sort, card display, dual modes

## Subtasks & Detailed Guidance

### Subtask T011 - Create ExerciseListView assembly

- **Purpose**: The main Exercise List screen composing all sub-components.
- **File**: `Reppo/Features/Exercise/Views/ExerciseListView.swift`
- **Steps**:
  1. Create the view with mode and callback:
     ```swift
     struct ExerciseListView: View {
         let mode: ExerciseListMode
         var onExercisesSelected: (([UUID]) -> Void)?

         @State private var viewModel: ExerciseListViewModel
         @Environment(ServiceContainer.self) private var services

         init(mode: ExerciseListMode,
              onExercisesSelected: (([UUID]) -> Void)? = nil,
              services: ServiceContainer) {
             self.mode = mode
             self.onExercisesSelected = onExercisesSelected
             self._viewModel = State(initialValue: ExerciseListViewModel(
                 mode: mode,
                 exerciseService: services.exerciseService,
                 statsService: services.statsService
             ))
         }
     }
     ```

  2. Build the body layout:
     ```swift
     var body: some View {
         VStack(spacing: 0) {
             // Filter strip + sort
             VStack(spacing: 8) {
                 MuscleFilterStrip(
                     muscleGroups: viewModel.availableMuscleGroups,
                     selectedFilters: $viewModel.selectedMuscleFilters
                 )
                 HStack {
                     SortOptionMenu(sortOrder: $viewModel.sortOrder)
                     Spacer()
                     Text("\(viewModel.exercises.count) exercises")
                         .font(.system(size: 12))
                         .foregroundStyle(Color.textTertiary)
                 }
                 .padding(.horizontal, 20)
             }
             .padding(.vertical, 8)

             // Exercise list
             if viewModel.exercises.isEmpty {
                 // Empty or no-results state (T014/T015)
             } else {
                 ScrollView {
                     LazyVStack(spacing: 8) {
                         ForEach(viewModel.exercises) { exercise in
                             exerciseCardRow(exercise)
                         }
                     }
                     .padding(.horizontal, 20)
                 }
             }
         }
         .background(Color.bg)
         .searchable(text: $viewModel.searchText, prompt: "Search exercises")
         .navigationTitle("Exercises")
         .task {
             await viewModel.loadExercises()
         }
     }
     ```

  3. The view should wrap everything in the appropriate NavigationStack context (for `.browse` mode it's pushed onto an existing stack; for `.addToWorkout` mode it may need its own stack since it's in a sheet).

- **Parallel?**: No - this is the main assembly.

### Subtask T012 - Implement browse mode

- **Purpose**: In browse mode, tapping an exercise card navigates to Exercise Detail.
- **File**: `Reppo/Features/Exercise/Views/ExerciseListView.swift` (within `exerciseCardRow`)
- **Steps**:
  1. When `mode == .browse`, wrap the card in a `NavigationLink`:
     ```swift
     @ViewBuilder
     private func exerciseCardRow(_ exercise: Exercise) -> some View {
         let stats = viewModel.allExerciseStats[exercise.id]
         let isSelected = viewModel.selectedExerciseIds.contains(exercise.id)

         if mode == .browse {
             NavigationLink(value: exercise.id) {
                 ExerciseCardView(
                     exercise: exercise,
                     stats: stats,
                     isSelected: isSelected,
                     mode: mode
                 )
             }
             .buttonStyle(.plain)
         } else {
             // Selection mode (T013)
         }
     }
     ```

  2. Add `.navigationDestination(for: UUID.self)` to navigate to ExerciseDetailView:
     ```swift
     .navigationDestination(for: UUID.self) { exerciseId in
         ExerciseDetailView(exerciseId: exerciseId, services: services)
     }
     ```
     Note: ExerciseDetailView is built in WP04. For now, create a minimal stub if WP04 is not yet merged, or rely on the NavigationLink being wired correctly.

  3. Browse mode supports **dual interaction** via the selection circle on `ExerciseCardView`:
     - **Tap card body** (the `NavigationLink`) → navigates to Exercise Detail
     - **Tap selection circle** (`onSelectionToggle` closure) → toggles exercise selection without navigating
     - When `viewModel.hasSelection` is true, "Start Workout (N)" button appears at bottom via `safeAreaInset(edge: .bottom)`

     Wire the card like this:
     ```swift
     if mode == .browse {
         NavigationLink(value: exercise.id) {
             ExerciseCardView(
                 exercise: exercise,
                 stats: stats,
                 isSelected: isSelected,
                 mode: mode,
                 onSelectionToggle: {
                     viewModel.toggleSelection(exercise.id)
                 }
             )
         }
         .buttonStyle(.plain)
     }
     ```
     The `NavigationLink` handles card body taps. The `onSelectionToggle` `Button` inside `ExerciseCardView` handles circle taps (SwiftUI button hit-testing gives the inner button priority).

- **Parallel?**: No - depends on T011.

### Subtask T013 - Implement selection mode

- **Purpose**: In selection mode (.addToWorkout), tapping toggles exercise selection, and an action button appears at the bottom.
- **File**: `Reppo/Features/Exercise/Views/ExerciseListView.swift`
- **Steps**:
  1. When `mode == .addToWorkout`, wrap the ENTIRE card in a `Button` (no navigation — tap anywhere toggles selection):
     ```swift
     Button {
         viewModel.toggleSelection(exercise.id)
     } label: {
         ExerciseCardView(
             exercise: exercise,
             stats: stats,
             isSelected: isSelected,
             mode: mode,
             onSelectionToggle: {
                 viewModel.toggleSelection(exercise.id)
             }
         )
     }
     .buttonStyle(.plain)
     ```
     In this mode, both the outer `Button` and the inner selection circle trigger `toggleSelection`. The circle is a visual affordance, but the entire card is tappable.

  2. Add a bottom action button using `safeAreaInset(edge: .bottom)`:
     ```swift
     .safeAreaInset(edge: .bottom) {
         if viewModel.hasSelection {
             Button {
                 let ids = Array(viewModel.selectedExerciseIds)
                 onExercisesSelected?(ids)
             } label: {
                 Text(actionButtonTitle)
                     .font(.system(size: 16, weight: .semibold))
                     .foregroundStyle(.white)
                     .frame(maxWidth: .infinity)
                     .padding(.vertical, 14)
                     .background(Color.accent)
                     .cornerRadius(12)
             }
             .padding(.horizontal, 20)
             .padding(.bottom, 8)
         }
     }
     ```

  3. Action button title varies by mode:
     - `.browse`: "Start Workout (\(viewModel.selectedCount))" — triggers `onStartWorkout` callback (wired in WP07 T032)
     - `.addToWorkout`: "Add (\(viewModel.selectedCount))" — triggers `onExercisesSelected` callback

  4. In `.addToWorkout` mode (sheet), add a dismiss/cancel button in the toolbar.

- **Parallel?**: No - depends on T011.

### Subtask T014 - Implement empty state

- **Purpose**: When there are zero exercises (fresh install before seed loads), show a helpful empty state.
- **File**: `Reppo/Features/Exercise/Views/ExerciseListView.swift`
- **Steps**:
  1. Check if `viewModel.allExercises.isEmpty` (raw, not filtered) after loading:
     ```swift
     if viewModel.isLoading {
         ProgressView()
     } else if viewModel.allExercises.isEmpty {
         // True empty state - no exercises at all
         VStack(spacing: 16) {
             Image(systemName: "dumbbell")
                 .font(.system(size: 48))
                 .foregroundStyle(Color.textTertiary)
             Text("No Exercises Yet")
                 .font(.title3.bold())
                 .foregroundStyle(Color.textPrimary)
             Text("Create your first exercise to get started")
                 .font(.subheadline)
                 .foregroundStyle(Color.textTertiary)
             Button("+ New Exercise") {
                 showCreateSheet = true
             }
             .foregroundStyle(Color.accent)
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
     }
     ```

- **Parallel?**: Yes - independent conditional branch.

### Subtask T015 - Implement no-results state

- **Purpose**: When search/filter returns nothing (but exercises exist), show "No exercises found".
- **File**: `Reppo/Features/Exercise/Views/ExerciseListView.swift`
- **Steps**:
  1. Check if filtered `exercises` is empty but `allExercises` is not:
     ```swift
     } else if viewModel.exercises.isEmpty {
         // Filter/search returned nothing
         VStack(spacing: 12) {
             Image(systemName: "magnifyingglass")
                 .font(.system(size: 36))
                 .foregroundStyle(Color.textTertiary)
             Text("No exercises found")
                 .font(.subheadline)
                 .foregroundStyle(Color.textTertiary)
             if !viewModel.selectedMuscleFilters.isEmpty {
                 Button("Clear Filters") {
                     viewModel.selectedMuscleFilters.removeAll()
                 }
                 .foregroundStyle(Color.accent)
             }
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
     }
     ```

  2. Include a "Clear Filters" button when muscle filters are active.

- **Parallel?**: Yes - independent conditional branch.

## Risks & Mitigations

- **Mode complexity**: Two modes in one view adds conditional logic. Keep mode-specific behavior in small, isolated functions rather than spreading `if mode == .browse` throughout the body.
- **Navigation in sheet**: When presented as a sheet (`.addToWorkout`), the view needs its own `NavigationStack` for the search bar to work with `.searchable`. Wrap in `NavigationStack` when mode is `.addToWorkout`.
- **Performance**: `LazyVStack` ensures smooth scrolling for 200+ exercise cards. Do not use `List` (harder to style) or `VStack` (loads all at once).

## Definition of Done Checklist

- [ ] ExerciseListView renders with search bar, filter strip, sort menu, and card list
- [ ] Browse mode: tap card navigates to detail (via NavigationLink)
- [ ] Selection mode: tap toggles selection, action button appears with correct count
- [ ] Empty state shows when zero exercises exist
- [ ] No-results state shows when search/filter returns nothing
- [ ] All styling uses DesignTokens.swift colors
- [ ] `tasks.md` updated with status change

## Review Guidance

- Verify both modes work correctly and don't interfere
- Verify `.searchable` modifier works in both standalone and sheet contexts
- Verify empty and no-results states are visually distinct
- Verify selection count updates immediately on toggle
- Verify LazyVStack is used (not List or VStack) for card scrolling

## Activity Log

- 2026-02-25T08:19:17Z - system - lane=planned - Prompt created.
- 2026-02-26T14:56:45Z – claude – shell_pid=76039 – lane=doing – Started implementation via workflow command
- 2026-02-26T14:58:51Z – claude – shell_pid=76039 – lane=for_review – Ready for review: ExerciseListView with dual mode (browse/addToWorkout), search, filter, sort, empty state, no-results state. NavigationLink to detail stub. Build succeeds zero errors.
- 2026-02-26T20:20:38Z – claude – shell_pid=76039 – lane=done – Review passed: ExerciseListView correctly implements dual mode (browse/addToWorkout), searchable, MuscleFilterStrip, SortOptionMenu, LazyVStack list, NavigationLink for browse / Button for addToWorkout, empty/no-results states, action button with count. All DoD items met.
