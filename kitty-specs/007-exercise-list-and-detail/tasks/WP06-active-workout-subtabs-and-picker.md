---
work_package_id: "WP06"
subtasks:
  - "T025"
  - "T026"
  - "T027"
  - "T028"
  - "T029"
title: "Active Workout Sub-Tabs & Picker Replacement"
phase: "Phase 2 - Integration"
lane: "done"
assignee: "claude"
agent: "claude"
shell_pid: "81309"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP03", "WP04"]
history:
  - timestamp: "2026-02-25T08:19:17Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP06 - Active Workout Sub-Tabs & Picker Replacement

## IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Implementation Command

Depends on WP03 and WP04:
```bash
spec-kitty implement WP06 --base WP04
```

Note: WP06 needs both WP03 (ExerciseListView for picker) and WP04 (ExerciseHistoryView, ExerciseChartsView for sub-tabs). If WP03 is not yet merged into WP04's branch, you may need to merge both first, or use `--base WP04` and manually merge WP03 changes.

---

## Objectives & Success Criteria

- Add `[Sets] [History] [Charts]` sub-tab picker to `ActiveWorkoutView` per screen_tree.md Section 3
- Wire `ExerciseHistoryView` and `ExerciseChartsView` (from WP04) as sub-tab content
- Reset sub-tab to `.sets` when user switches exercises via the exercise tab strip
- Replace the stub `ExercisePickerSheet` with `ExerciseListView(mode: .addToWorkout)`
- **Success**: In Active Workout, sub-tab picker visible below exercise tabs. Switching to History shows past sessions. Switching to Charts shows graphs. Tapping [+Exercise] opens the full exercise browser with search/filter/sort.

## Context & Constraints

- **Spec**: screen_tree.md Section 3 -- Active Workout sub-tabs: `[Sets] (default)`, `[History]`, `[Charts]`
- **Plan**: `kitty-specs/007-exercise-list-and-detail/plan.md` - Decision 4 (Active Workout Sub-Tab Retrofit)
- **Research**: `kitty-specs/007-exercise-list-and-detail/research.md` - R5 (sub-tab as @State), R8 (ExercisePickerSheet replacement)
- **Constitution**: Sub-tab selection is purely UI state -> `@State` in View is acceptable
- **Existing code**:
  - `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` -- the view to modify
  - `Reppo/Features/Workout/Views/ExercisePickerSheet.swift` -- the stub to delete
  - `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` -- has `showAddExerciseSheet: Bool` and `addExercises(_:)`
- **From WP04**: `ExerciseHistoryView`, `ExerciseChartsView` -- reusable views taking `exerciseId`

## Subtasks & Detailed Guidance

### Subtask T025 - Add ExerciseSubTab picker to ActiveWorkoutView

- **Purpose**: Add a sub-tab picker below the exercise tab strip to switch between Sets, History, and Charts for the current exercise.
- **File**: `Reppo/Features/Workout/Views/ActiveWorkoutView.swift`
- **Steps**:
  1. Add sub-tab state:
     ```swift
     @State private var selectedSubTab: ExerciseSubTab = .sets
     ```

  2. Add the sub-tab picker below the existing `ExerciseTabStripView`. Use a small segmented-style pill strip:
     ```swift
     // After ExerciseTabStripView
     HStack(spacing: 8) {
         ForEach(ExerciseSubTab.allCases, id: \.self) { tab in
             Button {
                 selectedSubTab = tab
             } label: {
                 Text(tab.rawValue)
                     .font(.system(size: 12, weight: selectedSubTab == tab ? .semibold : .regular))
                     .foregroundStyle(selectedSubTab == tab ? .white : Color.textTertiary)
                     .padding(.vertical, 5)
                     .padding(.horizontal, 12)
                     .background(selectedSubTab == tab ? Color.accent : Color.bgCard)
                     .cornerRadius(6)
             }
         }
     }
     .padding(.horizontal, 20)
     .padding(.vertical, 4)
     ```

  3. Switch the main content area based on `selectedSubTab`:
     ```swift
     switch selectedSubTab {
     case .sets:
         // Existing SetTableView content (no changes)
         SetTableView(...)
     case .history:
         // ExerciseHistoryView from WP04
         // Wired in T026
     case .charts:
         // ExerciseChartsView from WP04
         // Wired in T027
     }
     ```

  4. Keep the sub-tab picker compact -- smaller than the exercise tab strip. Use 12pt font, 5pt vertical padding. The active tab uses `.accent` background, inactive uses `.bgCard`.

- **Notes**: Read the existing `ActiveWorkoutView.swift` carefully to understand where the exercise tab strip and set table are positioned. The sub-tab picker goes between the exercise tab strip and the set table.
- **Parallel?**: No - modifies the main view structure.

### Subtask T026 - Wire ExerciseHistoryView as History sub-tab

- **Purpose**: Show the exercise's past sessions when the History sub-tab is selected.
- **File**: `Reppo/Features/Workout/Views/ActiveWorkoutView.swift`
- **Steps**:
  1. In the `selectedSubTab` switch, for `.history`:
     ```swift
     case .history:
         if let exercise = viewModel.currentExercise {
             ExerciseHistoryView(exerciseId: exercise.id, /* services */)
         }
     ```

  2. `ExerciseHistoryView` from WP04 should have a standalone initializer that takes `exerciseId` and loads data itself. If it only takes a `historyWorkouts` array, you'll need to either:
     - Use the standalone initializer (preferred)
     - Create a lightweight ViewModel that loads history for the exercise

  3. The history view should fit within the Active Workout layout (scrollable, same background).

- **Notes**: The History sub-tab in Active Workout shows the same data as the History tab in Exercise Detail. Same component, same data, different embedding context.
- **Parallel?**: Yes - independent content wiring.

### Subtask T027 - Wire ExerciseChartsView as Charts sub-tab

- **Purpose**: Show the exercise's charts when the Charts sub-tab is selected.
- **File**: `Reppo/Features/Workout/Views/ActiveWorkoutView.swift`
- **Steps**:
  1. In the `selectedSubTab` switch, for `.charts`:
     ```swift
     case .charts:
         if let exercise = viewModel.currentExercise {
             ExerciseChartsView(exerciseId: exercise.id, /* services */)
         }
     ```

  2. Same approach as T026 -- use the standalone initializer from WP04's `ExerciseChartsView`.

  3. Charts should fit within the Active Workout layout and scroll if needed.

- **Parallel?**: Yes - independent content wiring.

### Subtask T028 - Reset sub-tab on exercise switch

- **Purpose**: When the user switches exercises via the exercise tab strip, reset to the Sets sub-tab.
- **File**: `Reppo/Features/Workout/Views/ActiveWorkoutView.swift`
- **Steps**:
  1. Add an `.onChange` handler for the selected exercise index:
     ```swift
     .onChange(of: viewModel.selectedExerciseIndex) { _, _ in
         selectedSubTab = .sets
     }
     ```

  2. This ensures the user always sees the Sets table when switching exercises (the primary interaction during a workout).

  3. Place this modifier on the outer container in `ActiveWorkoutView.body`.

- **Notes**: Without this reset, switching exercises while on the History tab would show history for a different exercise, which could be confusing.
- **Parallel?**: No - depends on T025.

### Subtask T029 - Replace ExercisePickerSheet with ExerciseListView

- **Purpose**: Replace the minimal stub picker with the full exercise browser.
- **Files**:
  - `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` (modify sheet presentation)
  - `Reppo/Features/Workout/Views/ExercisePickerSheet.swift` (delete this file)
- **Steps**:
  1. Read the current `ActiveWorkoutView.swift` to find the `.sheet` presenting `ExercisePickerSheet`:
     ```swift
     // CURRENT (stub):
     .sheet(isPresented: $viewModel.showAddExerciseSheet) {
         ExercisePickerSheet(viewModel: viewModel, exerciseService: ...)
     }
     ```

  2. Replace with `ExerciseListView` in `.addToWorkout` mode:
     ```swift
     // NEW:
     .sheet(isPresented: $viewModel.showAddExerciseSheet) {
         NavigationStack {
             ExerciseListView(
                 mode: .addToWorkout,
                 onExercisesSelected: { selectedIds in
                     Task {
                         await viewModel.addExercises(selectedIds)
                     }
                     viewModel.showAddExerciseSheet = false
                 },
                 services: services
             )
         }
     }
     ```

  3. Delete `ExercisePickerSheet.swift` entirely -- it's a stub that Feature 007 replaces.

  4. Verify the callback correctly calls `viewModel.addExercises(_:)` which:
     - Fetches each Exercise by ID
     - Appends to `exercises` array
     - Creates initial empty WorkoutSets
     - Switches to the last added exercise

  5. Check how `addExercises` works in `ActiveWorkoutViewModel` -- it may take `[UUID]` or `[Exercise]`. Read the method signature and adapt the callback accordingly.

- **Notes**: The `ExerciseListView` needs `NavigationStack` wrapper when presented as a sheet so that `.searchable` works.
- **Parallel?**: No - modifies the sheet presentation (depends on T025 for context).

## Risks & Mitigations

- **Sub-tab picker visual clutter**: The Active Workout screen is already dense (exercise tabs, set table, rest timer). Keep the sub-tab picker minimal and compact. Use 12pt font, tight padding.
- **ExerciseHistoryView/ExerciseChartsView reusability**: These views from WP04 must support standalone use (take `exerciseId`, load own data). If WP04 only implemented them as sub-views of ExerciseDetailView with shared ViewModel, you'll need to add standalone initializers.
- **addExercises API**: The `ActiveWorkoutViewModel.addExercises(_:)` method exists but may take `[UUID]` or `[Exercise]`. Verify the exact signature before wiring the callback.
- **Sheet dismissal timing**: Ensure `viewModel.showAddExerciseSheet = false` fires after exercises are added, not before.

## Definition of Done Checklist

- [ ] Sub-tab picker visible in Active Workout below exercise tab strip
- [ ] Sets sub-tab shows existing SetTableView (unchanged)
- [ ] History sub-tab shows ExerciseHistoryView with past sessions
- [ ] Charts sub-tab shows ExerciseChartsView with e1RM and volume charts
- [ ] Sub-tab resets to Sets when switching exercises
- [ ] ExercisePickerSheet.swift deleted
- [ ] [+Exercise] sheet shows ExerciseListView with search/filter/sort
- [ ] Selected exercises correctly added to active workout
- [ ] `tasks.md` updated with status change

## Review Guidance

- Verify sub-tab picker is visually compact and doesn't crowd the workout UI
- Verify History and Charts load data for the currently selected exercise
- Verify sub-tab resets to Sets on exercise switch
- Verify ExercisePickerSheet.swift is fully deleted (no orphan references)
- Verify exercise selection from the new picker correctly adds to workout
- Test: Add exercises via picker, verify they appear as tabs in the workout

## Activity Log

- 2026-02-25T08:19:17Z - system - lane=planned - Prompt created.
- 2026-02-26T15:15:24Z – claude – shell_pid=81309 – lane=doing – Started implementation via workflow command
- 2026-02-26T20:13:38Z – claude – shell_pid=81309 – lane=for_review – Ready for review: Sub-tabs [Sets|History|Charts] in ActiveWorkoutView, ExercisePickerSheet replaced with ExerciseListView
- 2026-02-26T20:20:51Z – claude – shell_pid=81309 – lane=done – Review passed: ActiveWorkoutView correctly implements [Sets|History|Charts] sub-tab picker (T025), ExerciseHistoryView (T026), ExerciseChartsView (T027), sub-tab reset on exercise switch (T028), ExerciseListView(mode: .addToWorkout) picker replacement (T029), RestTimerView (T030). Note: ExercisePickerSheet.swift was not deleted but is no longer referenced anywhere — dead code, no functional impact.
