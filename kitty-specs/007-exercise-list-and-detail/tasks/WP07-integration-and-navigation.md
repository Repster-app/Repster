---
work_package_id: "WP07"
subtasks:
  - "T030"
  - "T031"
  - "T032"
  - "T033"
  - "T034"
title: "Integration & Navigation Wiring"
phase: "Phase 2 - Integration"
lane: "done"
assignee: "claude"
agent: "claude-wp07"
shell_pid: "7953"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP03", "WP04", "WP05", "WP06"]
history:
  - timestamp: "2026-02-25T08:19:17Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP07 - Integration & Navigation Wiring

## IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Implementation Command

Depends on WP03, WP04, WP05, WP06:
```bash
spec-kitty implement WP07 --base WP06
```

Note: WP07 integrates all prior WPs. Ensure WP03, WP04, WP05, and WP06 are all merged before starting. Use `--base WP06` (which should already include WP03 and WP04).

---

## Objectives & Success Criteria

- Wire FAB button to navigate to ExerciseListView in browse mode
- Wire browse-mode card tap to push ExerciseDetailView
- Wire "Start Workout" button to create workout and open ActiveWorkoutView
- Wire [+ New] button to present CreateEditExerciseSheet
- Wire Edit/Delete actions from ExerciseDetailView
- **Success**: All end-to-end flows work: FAB -> browse -> detail; FAB -> select -> start workout; create/edit/delete exercises. Active workout resume on launch still works.

## Context & Constraints

- **Spec**: All user stories integrated, FR-001 through FR-010
- **Plan**: `kitty-specs/007-exercise-list-and-detail/plan.md` - All key architecture decisions
- **Screen_tree.md Section 3**: Navigation table -- FAB->List (push), List->Detail (push), List->[+New] (sheet), List->Start Workout (push focused)
- **AGENT_RULES.md Section 7.2-7.3**: Navigation structure, active workout flow
- **Constitution**: Bottom nav visible on browse, HIDDEN on focused screens (active workout)
- **From prior WPs**:
  - WP01: ContentView with TabView + FAB
  - WP03: ExerciseListView with browse/selection modes
  - WP04: ExerciseDetailView with History/PRs/Charts
  - WP05: CreateEditExerciseSheet
  - WP06: ActiveWorkoutView with sub-tabs and new picker

## Subtasks & Detailed Guidance

### Subtask T030 - Wire FAB to ExerciseListView navigation

- **Purpose**: The center FAB button should navigate to the Exercise List in browse mode.
- **File**: `Reppo/App/ContentView.swift`
- **Steps**:
  1. Read the current ContentView to understand the FAB button action (WP01 left it as a placeholder).

  2. The FAB should push `ExerciseListView(mode: .browse)` onto a NavigationStack. Options:
     - **Option A**: Use a dedicated `@State` navigation path for a FAB-triggered NavigationStack overlay
     - **Option B**: Push onto the active tab's NavigationStack via a shared navigation path
     - **Option C**: Use a `@State var showExerciseList = false` and a `NavigationLink(isActive:)` pattern

     **Recommended approach**: Use a `@State private var showExerciseList = false` flag and present the Exercise List via `fullScreenCover` or by pushing onto a NavigationStack that wraps the entire TabView content.

     Alternatively, a simpler approach: The FAB sets `showExerciseList = true`, and this is a `navigationDestination(isPresented:)` on the tab view's NavigationStack:
     ```swift
     NavigationStack(path: $navigationPath) {
         TabView(selection: $selectedTab) { ... }
         .navigationDestination(for: String.self) { destination in
             if destination == "exerciseList" {
                 ExerciseListView(mode: .browse, ...)
             }
         }
     }
     ```

  3. When FAB is tapped and there IS an active workout, navigate back to it (the fullScreenCover should still be showing). The FAB should be context-aware per screen_tree.md.

  4. Bottom nav should be VISIBLE when the Exercise List is shown in browse mode. This means it should NOT be a fullScreenCover (which hides the tab bar). It should be a push navigation within the tab structure.

- **Notes**: Getting the FAB -> NavigationStack -> ExerciseList flow right with the tab bar visible requires careful navigation architecture. Test that the tab bar remains visible on the Exercise List screen.
- **Parallel?**: Yes - targets ContentView independently.

### Subtask T031 - Wire browse-mode card tap to ExerciseDetailView

- **Purpose**: In browse mode, tapping an exercise card should push ExerciseDetailView.
- **File**: `Reppo/Features/Exercise/Views/ExerciseListView.swift`
- **Steps**:
  1. WP03 set up `NavigationLink(value: exercise.id)` and `.navigationDestination(for: UUID.self)` for browse mode.

  2. Verify this is correctly wired:
     ```swift
     .navigationDestination(for: UUID.self) { exerciseId in
         ExerciseDetailView(exerciseId: exerciseId, /* services */)
     }
     ```

  3. Verify `ServiceContainer` is passed to `ExerciseDetailView`. Per contracts, the view takes `services: ServiceContainer` and creates its ViewModel internally, extracting the needed services (exerciseService, prService, setService, statsService, workoutService).

  4. Verify the Exercise Detail screen shows with the navigation title and back button.

  5. Bottom nav behavior: Exercise Detail is PUSHED, so by default the tab bar may still show. Per screen_tree.md, Exercise Detail should hide the tab bar when pushed. Use `.toolbar(.hidden, for: .tabBar)` on `ExerciseDetailView`.

- **Notes**: If WP03 already implemented this with a stub, this subtask is about verifying the real `ExerciseDetailView` works correctly when navigated to.
- **Parallel?**: No - depends on the navigation structure from T030.

### Subtask T032 - Wire "Start Workout" button flow

- **Purpose**: When exercises are selected and "Start Workout (N)" is tapped, create a workout and navigate to ActiveWorkoutView.
- **File**: `Reppo/Features/Exercise/Views/ExerciseListView.swift` and `Reppo/App/ContentView.swift`
- **Steps**:
  1. In `ExerciseListView`, when the "Start Workout" button is tapped in browse mode:
     ```swift
     Button {
         startWorkoutWithSelectedExercises()
     } label: {
         Text("Start Workout (\(viewModel.selectedCount))")
         // ... styling
     }
     ```

  2. The `startWorkoutWithSelectedExercises()` function needs to:
     - Call `WorkoutService.startWorkout()` to create a new workout
     - For each selected exercise ID, add to the workout (this may involve `ActiveWorkoutViewModel`)
     - Navigate to `ActiveWorkoutView` via `fullScreenCover`

  3. This is complex because the navigation crosses view boundaries (ExerciseListView -> ContentView's fullScreenCover). Options:
     - **Option A**: Use an environment-level callback or `@Binding` to trigger the ContentView's `showActiveWorkout`
     - **Option B**: Use a shared app-level state (e.g., an `AppState` observable)
     - **Option C**: Use `NotificationCenter` or a custom coordinator

     **Recommended**: Pass a closure from ContentView through to ExerciseListView:
     ```swift
     ExerciseListView(
         mode: .browse,
         onStartWorkout: { exerciseIds in
             // ContentView handles: create workout, set showActiveWorkout = true
         },
         ...
     )
     ```

  4. In ContentView, the `onStartWorkout` closure:
     - Creates a new workout via `WorkoutService`
     - Creates `ActiveWorkoutViewModel` with the selected exercises
     - Sets `showActiveWorkout = true` to trigger fullScreenCover

  5. The Active Workout's `fullScreenCover` hides the tab bar (existing behavior from Feature 006).

- **Notes**: Selection in browse mode uses the leading selection circle on each ExerciseCardView (see WP02 T009, WP03 T012). Users tap the circle to select, then tap "Start Workout (N)" at the bottom. This is the most architecturally complex subtask. The flow crosses multiple view layers. Keep it as simple as possible -- a closure callback is cleaner than global state.
- **Parallel?**: No - depends on navigation structure.

### Subtask T033 - Wire [+ New] to CreateEditExerciseSheet

- **Purpose**: The [+ New] button in ExerciseListView should present CreateEditExerciseSheet for creating a new exercise.
- **File**: `Reppo/Features/Exercise/Views/ExerciseListView.swift`
- **Steps**:
  1. Add state for the sheet:
     ```swift
     @State private var showCreateSheet = false
     ```

  2. Add a toolbar button or floating button:
     ```swift
     .toolbar {
         ToolbarItem(placement: .topBarTrailing) {
             Button {
                 showCreateSheet = true
             } label: {
                 Image(systemName: "plus")
             }
         }
     }
     ```

  3. Present the sheet:
     ```swift
     .sheet(isPresented: $showCreateSheet) {
         CreateEditExerciseSheet(
             exercise: nil,  // nil = create mode
             services: services,
             onSave: {
                 Task {
                     await viewModel.loadExercises()
                 }
             }
         )
     }
     ```

  4. The `onSave` callback reloads the exercise list so the new exercise appears.

- **Notes**: Also wire this from the empty state (T014) where the [+ New] prompt exists.
- **Parallel?**: Yes - targets ExerciseListView independently.

### Subtask T034 - Wire Edit/Delete from ExerciseDetailView

- **Purpose**: ExerciseDetailView should support editing and deleting exercises.
- **File**: `Reppo/Features/Exercise/Views/ExerciseDetailView.swift`
- **Steps**:
  1. Add toolbar actions for Edit and Delete:
     ```swift
     .toolbar {
         ToolbarItem(placement: .topBarTrailing) {
             Menu {
                 Button {
                     showEditSheet = true
                 } label: {
                     Label("Edit Exercise", systemImage: "pencil")
                 }

                 Button(role: .destructive) {
                     showDeleteConfirmation = true
                 } label: {
                     Label("Delete Exercise", systemImage: "trash")
                 }
             } label: {
                 Image(systemName: "ellipsis.circle")
             }
         }
     }
     ```

  2. Wire Edit sheet:
     ```swift
     @State private var showEditSheet = false

     .sheet(isPresented: $showEditSheet) {
         CreateEditExerciseSheet(
             exercise: viewModel.exercise,
             services: services,
             onSave: {
                 Task {
                     await viewModel.loadExercise()
                 }
             }
         )
     }
     ```

  3. Wire Delete confirmation:
     ```swift
     @State private var showDeleteConfirmation = false

     .confirmationDialog(
         "Delete Exercise",
         isPresented: $showDeleteConfirmation,
         titleVisibility: .visible
     ) {
         Button("Delete", role: .destructive) {
             Task {
                 try? await viewModel.deleteExercise()
                 dismiss()
             }
         }
     } message: {
         Text("This will permanently delete this exercise and all its recorded sets, PRs, and stats. This cannot be undone.")
     }
     ```

  4. After delete: `dismiss()` pops back to the Exercise List. The list should refresh (it will re-run `.task` on appear, or use a callback).

  5. Delete cascade: `ExerciseService.deleteExercise()` handles the full cascade (sets, ExerciseStats, PerformanceRecords). The UI just needs to call it and navigate away.

- **Notes**: The delete confirmation message should be clear about what gets deleted (per constitution: hard delete only, everything is gone).
- **Parallel?**: Yes - targets ExerciseDetailView independently.

## Risks & Mitigations

- **Navigation architecture complexity**: The "Start Workout" flow crosses ContentView -> ExerciseListView -> ActiveWorkoutView boundaries. Keep the callback chain simple. If it gets too complex, consider using an `@EnvironmentObject` AppState for workout state.
- **Tab bar visibility**: Exercise List should show tab bar (browse mode). Exercise Detail should hide it. Active Workout hides it. Verify `.toolbar(.hidden, for: .tabBar)` is applied correctly on the right views.
- **Active workout resume regression**: After all navigation changes, verify the app still resumes an active workout on launch. This is critical functionality from Feature 006.
- **Delete pop-back**: After deleting an exercise from the detail view, the navigation should pop back cleanly. Test that the NavigationStack handles this without leaving stale state.
- **Service dependency injection**: All views receive `ServiceContainer` (not individual services/repositories). Ensure `ServiceContainer` is accessible via `@Environment` in all new views. Check that the environment injection chain works from ReppoApp -> ContentView -> TabView -> ExerciseListView -> ExerciseDetailView. ViewModels receive individual service protocols extracted by their parent view.

## Definition of Done Checklist

- [ ] FAB navigates to ExerciseListView in browse mode
- [ ] Tab bar visible on Exercise List, hidden on Exercise Detail
- [ ] Browse-mode card tap pushes ExerciseDetailView with correct data
- [ ] "Start Workout" creates workout and opens ActiveWorkoutView with selected exercises
- [ ] [+ New] presents CreateEditExerciseSheet in create mode
- [ ] Edit from detail presents CreateEditExerciseSheet in edit mode
- [ ] Delete from detail shows confirmation, cascades delete, pops back to list
- [ ] Active workout resume on launch still works
- [ ] All navigation flows are clean (no stale state, no navigation stack issues)
- [ ] `tasks.md` updated with status change

## Review Guidance

- **Full flow testing**: Test every navigation path from the quickstart.md test flows
- Verify FAB -> Exercise List (tab bar visible)
- Verify Exercise List -> Exercise Detail (tab bar hidden)
- Verify "Start Workout" -> Active Workout (full screen cover, no tab bar)
- Verify [+ New] -> Create -> save -> list refreshed
- Verify Edit -> save -> detail refreshed
- Verify Delete -> confirm -> pop to list -> list refreshed
- Verify active workout resume on cold launch
- Verify environment injection chain (services accessible in all views)

## Activity Log

- 2026-02-25T08:19:17Z - system - lane=planned - Prompt created.
- 2026-02-26T20:08:59Z – claude_wp07 – shell_pid=7953 – lane=doing – Started implementation via workflow command
- 2026-02-26T20:13:27Z – claude_wp07 – shell_pid=7953 – lane=for_review – Ready for review: All navigation flows wired — FAB->browse list, card->detail, Start Workout->active workout, +New->create sheet, Edit/Delete from detail
- 2026-02-26T20:20:56Z – claude_wp07 – shell_pid=7953 – lane=done – Review passed: ContentView wires FAB→NavigationStack push to ExerciseListView(browse) (T030/T032), tab bar hidden on ExerciseDetailView via .toolbar(.hidden, for: .tabBar) (T031), +New button and empty-state CTA in ExerciseListView (T033), Edit/Delete menu in ExerciseDetailView (T034), WorkoutSummarySheet finish flow (T035). startWorkoutWithExercises correctly creates workout + sets then presents ActiveWorkoutView. All DoD items met.
