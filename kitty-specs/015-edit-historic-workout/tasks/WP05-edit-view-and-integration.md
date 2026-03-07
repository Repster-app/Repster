---
work_package_id: WP05
title: EditWorkoutView + Integration
lane: "done"
dependencies:
- WP02
- WP04
subtasks:
- T020
- T021
- T022
- T023
- T024
- T025
- T026
phase: Phase 2 - User Stories 1-4 (P1)
assignee: ''
agent: "claude-opus-reviewer"
shell_pid: "54595"
review_status: "approved"
reviewed_by: "Magnus Espensen"
history:
- timestamp: '2026-03-02T14:27:05Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP05 – EditWorkoutView + Integration

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP05 --base WP04
```

Depends on WP02 (views accept protocol) and WP04 (EditWorkoutViewModel complete with SetTableDataSource conformance).

---

## Objectives & Success Criteria

1. Create `EditWorkoutView` — a full-screen cover that assembles the edit workout UI.
2. Wire it up from `WorkoutDetailFromHomeView` so "Edit Workout" actually works.
3. Verify the full end-to-end flow: open detail → tap Edit → edit sets/exercises/notes → dismiss → detail refreshes.

**Success**: Navigate to a completed workout, tap menu → "Edit Workout", edit values, add/remove sets and exercises, edit notes, dismiss. Detail screen refreshes with all changes. Active workout flow remains unaffected.

## Context & Constraints

- **Architecture**: `EditWorkoutView` mirrors `ActiveWorkoutView` but is much simpler — no timer, no sub-tabs (History/Charts), no finish flow, no rest timer. Just header + tab strip + set table + notes.
- **Reference**: `ActiveWorkoutView` at `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` — follow the same layout patterns.
- **Presentation**: `.fullScreenCover` (same as ActiveWorkoutView).
- **ServiceContainer**: Already in SwiftUI environment (set in `ReppoApp.swift`). `WorkoutDetailFromHomeView` currently receives individual services — it also needs `@Environment(ServiceContainer.self)` to pass to EditWorkoutView.
- **Design system tokens**: Use `Color.bg`, `Color.bgCard`, `Color.accent`, `Color.textPrimary`, `Color.textSecondary`, `Color.textTertiary` (per existing app patterns).

## Subtasks & Detailed Guidance

### Subtask T020 – Create EditWorkoutView with header bar

- **Purpose**: Establish the EditWorkoutView struct with the header bar (Done button, title, +Exercise button).
- **File**: `Reppo/Features/Workout/Views/EditWorkoutView.swift` (NEW)
- **Steps**:
  1. Create the file with this structure:
     ```swift
     // EditWorkoutView.swift
     // Full-screen edit view for completed workouts.
     // Simplified version of ActiveWorkoutView without timers, sub-tabs, or finish flow.
     // Spec: 015-edit-historic-workout, FR-001 through FR-012

     import SwiftUI

     struct EditWorkoutView: View {

         // MARK: - State

         @State private var viewModel: EditWorkoutViewModel

         // MARK: - Dependencies

         private let services: ServiceContainer

         // MARK: - Environment

         @Environment(\.dismiss) private var dismiss

         // MARK: - Init

         init(workoutId: UUID, services: ServiceContainer) {
             _viewModel = State(initialValue: EditWorkoutViewModel(
                 workoutId: workoutId,
                 workoutService: services.workoutService,
                 setService: services.setService,
                 exerciseService: services.exerciseService,
                 statsService: services.statsService
             ))
             self.services = services
         }

         // MARK: - Body

         var body: some View {
             VStack(spacing: 0) {
                 headerBar

                 // Tab strip + content added in T021
             }
             .background(Color.bg.ignoresSafeArea())
             .task {
                 await viewModel.loadWorkout()
             }
         }

         // MARK: - Header Bar

         private var headerBar: some View {
             HStack(spacing: 8) {
                 // Done / dismiss button
                 Button {
                     Task {
                         await viewModel.saveNotes()
                         dismiss()
                     }
                 } label: {
                     Text("Done")
                         .font(.system(size: 16, weight: .semibold))
                         .foregroundColor(.accent)
                         .frame(height: 44)
                 }

                 Spacer()

                 Text("Edit Workout")
                     .font(.system(size: 16, weight: .semibold))
                     .foregroundColor(.textPrimary)

                 Spacer()

                 // +Exercise button
                 Button {
                     viewModel.showAddExerciseSheet = true
                 } label: {
                     Image(systemName: "plus")
                         .font(.system(size: 18, weight: .semibold))
                         .foregroundColor(.accent)
                         .frame(width: 44, height: 44)
                 }
             }
             .padding(.horizontal, 20)
             .padding(.vertical, 8)
         }
     }
     ```
  2. Verify it compiles (the body is incomplete but structurally valid).
- **Notes**: The header follows `ActiveWorkoutView.headerBar` styling but replaces the back chevron with "Done" text, removes the elapsed timer, and removes the "Finish" button. The Done button saves notes and dismisses.

### Subtask T021 – Integrate ExerciseTabStripView and SetTableView

- **Purpose**: Compose the main content area using the protocol-refactored shared components.
- **File**: `Reppo/Features/Workout/Views/EditWorkoutView.swift`
- **Steps**:
  1. Update the body to include the tab strip and set table:
     ```swift
     var body: some View {
         VStack(spacing: 0) {
             headerBar

             // Exercise tab strip
             ExerciseTabStripView(dataSource: viewModel)

             if viewModel.currentExercise != nil {
                 // Set table in a scrollable area
                 ScrollView {
                     SetTableView(dataSource: viewModel)
                         .padding(.horizontal, 20)
                         .padding(.top, 8)

                     // Notes section added in T022
                 }
             } else if !viewModel.isLoading {
                 emptyExerciseState
             }

             Spacer(minLength: 0)
         }
         .background(Color.bg.ignoresSafeArea())
         .task {
             await viewModel.loadWorkout()
         }
     }
     ```
  2. Add the empty state view (same pattern as ActiveWorkoutView):
     ```swift
     // MARK: - Empty State

     private var emptyExerciseState: some View {
         VStack(spacing: 16) {
             Spacer()

             Image(systemName: "dumbbell")
                 .font(.system(size: 48))
                 .foregroundColor(.textTertiary)

             Text("No exercises")
                 .font(.headline)
                 .foregroundColor(.textSecondary)

             Text("Add exercises to start editing")
                 .font(.subheadline)
                 .foregroundColor(.textTertiary)

             Button {
                 viewModel.showAddExerciseSheet = true
             } label: {
                 Text("Add Exercises")
                     .font(.system(size: 16, weight: .semibold))
                     .foregroundColor(.white)
                     .padding(.horizontal, 24)
                     .frame(height: 44)
                     .background(Color.accent)
                     .cornerRadius(10)
             }

             Spacer()
         }
         .frame(maxWidth: .infinity)
     }
     ```
- **Notes**: The layout is `VStack(spacing: 0) { headerBar → ExerciseTabStripView → ScrollView { SetTableView + notes } }`. No sub-tab picker (History/Charts tabs are not needed for editing). No rest timer.

### Subtask T022 – Add notes TextEditor section

- **Purpose**: Allow users to view and edit workout notes below the set table.
- **File**: `Reppo/Features/Workout/Views/EditWorkoutView.swift`
- **Steps**:
  1. Add a notes section inside the ScrollView, below SetTableView:
     ```swift
     ScrollView {
         SetTableView(dataSource: viewModel)
             .padding(.horizontal, 20)
             .padding(.top, 8)

         // Notes section
         notesSection
             .padding(.horizontal, 20)
             .padding(.top, 16)
             .padding(.bottom, 20)
     }
     ```
  2. Create the notes computed property:
     ```swift
     // MARK: - Notes Section

     private var notesSection: some View {
         VStack(alignment: .leading, spacing: 8) {
             Text("Notes")
                 .font(.system(size: 14, weight: .semibold))
                 .foregroundColor(.textSecondary)

             ZStack(alignment: .topLeading) {
                 // Placeholder text when empty
                 if viewModel.notesText.isEmpty {
                     Text("Add workout notes...")
                         .font(.system(size: 15))
                         .foregroundColor(.textTertiary)
                         .padding(.horizontal, 12)
                         .padding(.vertical, 12)
                 }

                 TextEditor(text: $viewModel.notesText)
                     .font(.system(size: 15))
                     .foregroundColor(.textPrimary)
                     .scrollContentBackground(.hidden)
                     .frame(minHeight: 80)
                     .padding(.horizontal, 8)
                     .padding(.vertical, 4)
             }
             .background(Color.bgCard)
             .cornerRadius(10)
         }
     }
     ```
- **Notes**: The `TextEditor` needs `.scrollContentBackground(.hidden)` to use the custom bgCard background. The placeholder overlay shows "Add workout notes..." when the text is empty. Notes are saved when the user taps "Done" (via `saveNotes()` in the header button action).

### Subtask T023 – Add exercise picker sheet integration

- **Purpose**: Present the exercise picker when the user taps "+Exercise" to add exercises to the workout.
- **File**: `Reppo/Features/Workout/Views/EditWorkoutView.swift`
- **Steps**:
  1. Add the sheet modifier to the outermost VStack:
     ```swift
     .sheet(isPresented: $viewModel.showAddExerciseSheet) {
         exercisePickerSheet
     }
     ```
  2. Add the exercise picker view:
     ```swift
     // MARK: - Exercise Picker

     private var exercisePickerSheet: some View {
         NavigationStack {
             ExerciseListView(
                 mode: .addToWorkout,
                 onExercisesSelected: { selectedIds in
                     Task {
                         await viewModel.addExercises(selectedIds)
                         viewModel.showAddExerciseSheet = false
                     }
                 },
                 services: services
             )
         }
     }
     ```
- **Notes**: This is identical to `ActiveWorkoutView.exercisePickerSheet`. Uses `ExerciseListView` in `.addToWorkout` mode. The `services` parameter is the `ServiceContainer` passed via init. On selection, calls `viewModel.addExercises(selectedIds)` then dismisses the sheet.

### Subtask T024 – Add loading state handling

- **Purpose**: Show a loading spinner while the workout data is being fetched.
- **File**: `Reppo/Features/Workout/Views/EditWorkoutView.swift`
- **Steps**:
  1. Add a loading overlay to the body:
     ```swift
     var body: some View {
         VStack(spacing: 0) {
             headerBar

             ExerciseTabStripView(dataSource: viewModel)

             if viewModel.isLoading {
                 Spacer()
                 ProgressView()
                     .tint(Color.accent)
                 Spacer()
             } else if viewModel.currentExercise != nil {
                 ScrollView {
                     SetTableView(dataSource: viewModel)
                         .padding(.horizontal, 20)
                         .padding(.top, 8)

                     notesSection
                         .padding(.horizontal, 20)
                         .padding(.top, 16)
                         .padding(.bottom, 20)
                 }
             } else {
                 emptyExerciseState
             }

             Spacer(minLength: 0)
         }
         .background(Color.bg.ignoresSafeArea())
         .task {
             await viewModel.loadWorkout()
         }
         .sheet(isPresented: $viewModel.showAddExerciseSheet) {
             exercisePickerSheet
         }
     }
     ```
  2. This replaces the earlier body from T021 — it adds the `viewModel.isLoading` branch and consolidates the full body with notes and the exercise picker sheet.
- **Notes**: The loading state shows a centered `ProgressView` with the accent tint. Once loading completes, either the set table + notes or the empty state is shown. The ExerciseTabStripView is always visible (it shows nothing when `exercises` is empty).

### Subtask T025 – Wire up WorkoutDetailFromHomeView

- **Purpose**: Enable the "Edit Workout" button and present EditWorkoutView as a full-screen cover.
- **File**: `Reppo/Features/Home/Views/WorkoutDetailFromHomeView.swift`
- **Steps**:
  1. Add new state and environment properties:
     ```swift
     @State private var showEditWorkout = false
     @Environment(ServiceContainer.self) private var services
     ```
  2. Update the "Edit Workout" button (currently disabled at lines 42-48):
     ```swift
     // BEFORE
     Button {
         // Future: edit workout
     } label: {
         Label("Edit Workout", systemImage: "pencil")
     }
     .disabled(true)

     // AFTER
     Button {
         showEditWorkout = true
     } label: {
         Label("Edit Workout", systemImage: "pencil")
     }
     ```
     Remove the `.disabled(true)` modifier and add the action.
  3. Add the `.fullScreenCover` modifier to the ScrollView (after the `.task` modifier):
     ```swift
     .fullScreenCover(isPresented: $showEditWorkout) {
         EditWorkoutView(workoutId: workoutId, services: services)
     }
     ```
- **Notes**:
  - `ServiceContainer` is already in the SwiftUI environment — `HomeView` has `@Environment(ServiceContainer.self)` and it flows down through the NavigationStack.
  - The `workoutId` is already available as a property on `WorkoutDetailFromHomeView`.
  - Place the `.fullScreenCover` modifier on the outermost `ScrollView` or the `body` — after the existing `.task` and `.confirmationDialog` modifiers.

### Subtask T026 – Add data reload on edit dismiss

- **Purpose**: Refresh the workout detail data when the edit screen is dismissed so changes are reflected.
- **File**: `Reppo/Features/Home/Views/WorkoutDetailFromHomeView.swift`
- **Steps**:
  1. Add an `.onChange` modifier to detect when the edit sheet dismisses:
     ```swift
     .onChange(of: showEditWorkout) { _, isShowing in
         if !isShowing {
             Task {
                 await loadDetail()
             }
         }
     }
     ```
  2. Place this after the `.fullScreenCover` modifier.
- **Notes**: When `showEditWorkout` transitions from `true` to `false` (edit screen dismissed), the detail view reloads all data. This ensures edited set values, added/removed sets, added/removed exercises, and notes changes are all reflected. The `loadDetail()` method already handles the full data refresh.

## Risks & Mitigations

- **ServiceContainer not in environment**: `WorkoutDetailFromHomeView` is navigated to from `HomeView` via `.navigationDestination(for: UUID.self)`. The `@Environment(ServiceContainer.self)` should already propagate. If it doesn't (crash at runtime), check that `ReppoApp` injects `.environment(services)` on the root view.
- **ExerciseListView `.addToWorkout` mode**: This mode is already used by `ActiveWorkoutView.exercisePickerSheet`. The callback interface is `onExercisesSelected: ([UUID]) -> Void`. Verify by reading `ExerciseListView.swift` if unsure.
- **TextEditor binding**: `viewModel.notesText` must be a `var` (not private) for `$viewModel.notesText` binding to work. It's declared as `var notesText: String` in the ViewModel (WP03) — this is correct for `@Observable`.
- **SwiftUI observation through existential**: The `ExerciseTabStripView(dataSource: viewModel)` and `SetTableView(dataSource: viewModel)` calls pass an `@Observable` type through `any SetTableDataSource`. If observation doesn't propagate (views don't update), test by changing exercise/set data and verifying UI updates. This was verified to work during WP02 with `ActiveWorkoutViewModel`.

## Definition of Done Checklist

- [ ] `EditWorkoutView.swift` exists in `Reppo/Features/Workout/Views/`
- [ ] Header bar has Done button (saves notes + dismisses), title, and +Exercise button
- [ ] `ExerciseTabStripView(dataSource: viewModel)` renders exercise tabs
- [ ] `SetTableView(dataSource: viewModel)` renders sets with full interactivity
- [ ] Notes `TextEditor` section displays below set table with placeholder text
- [ ] Exercise picker sheet opens from +Exercise button
- [ ] Loading state shows ProgressView while workout loads
- [ ] Empty state shows when no exercises exist
- [ ] `WorkoutDetailFromHomeView` "Edit Workout" button is enabled and functional
- [ ] `.fullScreenCover` presents `EditWorkoutView` correctly
- [ ] Detail view reloads data when edit screen dismisses
- [ ] Project builds without errors
- [ ] Full flow verified: open detail → edit → modify data → dismiss → detail refreshes

## Review Guidance

- **Critical**: Verify the Done button calls `saveNotes()` before `dismiss()`. If notes aren't saved, the user's edits are lost.
- Verify `@Environment(ServiceContainer.self)` is accessible in `WorkoutDetailFromHomeView`. If the environment value isn't propagated, the app will crash.
- Verify the exercise picker callback correctly calls `addExercises` then closes the sheet.
- Verify `.onChange(of: showEditWorkout)` fires `loadDetail()` on dismiss — this is the mechanism that refreshes the detail view.
- Test the active workout flow is still unaffected after these changes.

## Activity Log

- 2026-03-02T14:27:05Z – system – lane=planned – Prompt created.
- 2026-03-02T19:35:21Z – claude-opus – shell_pid=52826 – lane=doing – Started implementation via workflow command
- 2026-03-02T19:39:34Z – claude-opus – shell_pid=52826 – lane=for_review – Ready for review: EditWorkoutView created with header bar (Done + +Exercise), ExerciseTabStripView and SetTableView via SetTableDataSource, notes TextEditor with placeholder, exercise picker sheet, loading ProgressView, empty state. WorkoutDetailFromHomeView wired up: Edit Workout button enabled, fullScreenCover presents EditWorkoutView, data reload on dismiss via onChange. Added to pbxproj. Build succeeds. Required rebasing on both WP02 (protocol refactoring) and WP04 (ViewModel).
- 2026-03-02T19:40:00Z – claude-opus-reviewer – shell_pid=54595 – lane=doing – Started review via workflow command
- 2026-03-02T19:40:49Z – claude-opus-reviewer – shell_pid=54595 – lane=done – Review passed: All 7 subtasks verified. T020 header bar has Done button (saveNotes before dismiss - critical check passed), title, +Exercise. T021 ExerciseTabStripView and SetTableView use dataSource protocol correctly. T022 notes TextEditor with placeholder, scrollContentBackground hidden, bgCard. T023 exercise picker matches ActiveWorkoutView pattern exactly. T024 loading ProgressView with accent tint. T025 WorkoutDetailFromHomeView wired: showEditWorkout state, ServiceContainer from environment, fullScreenCover. T026 onChange reload on dismiss. ActiveWorkoutView unchanged. Build succeeds.
