---
work_package_id: "WP05"
subtasks:
  - "T021"
  - "T022"
  - "T023"
  - "T024"
title: "Create/Edit Exercise Sheet"
phase: "Phase 1 - Core Screens"
lane: "done"
assignee: "claude"
agent: "claude"
shell_pid: "80535"
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

# Work Package Prompt: WP05 - Create/Edit Exercise Sheet

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
spec-kitty implement WP05 --base WP01
```

---

## Objectives & Success Criteria

- Build `CreateEditExerciseViewModel` with form state, validation, and save logic
- Build `CreateEditExerciseSheet` UI with all exercise fields from specdoc Section 6.3
- Enforce trackingType immutability when exercise has associated sets (FR-009)
- Wire save flow for both create and update operations
- **Success**: Create new exercise with all fields, verify it saves correctly. Edit existing exercise, verify trackingType is locked when sets exist. Validation prevents saving with empty name.

## Context & Constraints

- **Spec**: User Story 4 (Create/Edit Exercise), FR-008, FR-009, SC-003
- **Constitution**: trackingType immutable once sets exist (Section 5.6), metadata fields from specdoc Section 6.3
- **Plan**: `kitty-specs/007-exercise-list-and-detail/plan.md` - Project Structure shows `CreateEditExerciseSheet.swift` and `CreateEditExerciseViewModel.swift`
- **Contracts**: `kitty-specs/007-exercise-list-and-detail/contracts/view-contracts.md` - CreateEditExerciseViewModel interface
- **Data layer**: `ExerciseService.createExercise(_:)`, `ExerciseService.updateExercise(_:originalTrackingType:)`, `ExerciseService.exerciseHasSets(_:)` -- all already implemented
- **Existing enums**: `EquipmentType`, `TrackingType`, `MovementPattern` -- already defined in `Reppo/Data/Enums/`

## Subtasks & Detailed Guidance

### Subtask T021 - Create CreateEditExerciseViewModel

- **Purpose**: Manage form state, validation, and save logic for creating/editing exercises.
- **File**: `Reppo/Features/Exercise/ViewModels/CreateEditExerciseViewModel.swift`
- **Steps**:
  1. Create the ViewModel:
     ```swift
     @Observable @MainActor
     final class CreateEditExerciseViewModel {
         private let exerciseService: any ExerciseServiceProtocol
         private let existingExercise: Exercise?

         // Form fields
         var name: String = ""
         var equipmentType: EquipmentType = .barbell
         var trackingType: TrackingType = .weightReps
         var primaryMuscle: String = ""
         var secondaryMuscles: [String] = []
         var movementPattern: MovementPattern? = nil
         var unilateral: Bool = false
         var bilateralLoadFactor: Double? = nil
         var bodyweightFactor: Double = 0.0
         var weightIncrement: Double? = nil
         var defaultRestTime: Int? = nil

         // UI state
         var isEditing: Bool
         var isTrackingTypeLocked: Bool = false
         var isSaving: Bool = false
         var validationErrors: [String] = []
         var showError: Bool = false
         var errorMessage: String = ""

         init(exercise: Exercise?, exerciseService: any ExerciseServiceProtocol) {
             self.exerciseService = exerciseService
             self.existingExercise = exercise
             self.isEditing = exercise != nil

             if let exercise = exercise {
                 // Populate form from existing exercise
                 name = exercise.name
                 equipmentType = exercise.equipmentType
                 trackingType = exercise.trackingType
                 primaryMuscle = exercise.primaryMuscle ?? ""
                 secondaryMuscles = exercise.secondaryMuscles
                 movementPattern = exercise.movementPattern
                 unilateral = exercise.unilateral
                 bilateralLoadFactor = exercise.bilateralLoadFactor
                 bodyweightFactor = exercise.bodyweightFactor
                 weightIncrement = exercise.weightIncrement
                 defaultRestTime = exercise.defaultRestTime
             }
         }
     }
     ```

  2. Implement validation:
     ```swift
     var isValid: Bool {
         !name.trimmingCharacters(in: .whitespaces).isEmpty
     }

     var navigationTitle: String {
         isEditing ? "Edit Exercise" : "New Exercise"
     }
     ```

  3. Implement `checkTrackingTypeLock()`:
     ```swift
     func checkTrackingTypeLock() async {
         guard let exercise = existingExercise else { return }
         isTrackingTypeLocked = (try? await exerciseService.exerciseHasSets(exercise.id)) ?? false
     }
     ```

  4. Implement `save()`:
     ```swift
     func save() async throws {
         guard isValid else {
             validationErrors = ["Exercise name is required"]
             return
         }

         isSaving = true
         defer { isSaving = false }

         if isEditing, let existing = existingExercise {
             // Update existing
             existing.name = name.trimmingCharacters(in: .whitespaces)
             existing.equipmentType = equipmentType
             // Don't update trackingType if locked
             if !isTrackingTypeLocked {
                 existing.trackingType = trackingType
             }
             existing.primaryMuscle = primaryMuscle.isEmpty ? nil : primaryMuscle
             existing.secondaryMuscles = secondaryMuscles
             existing.movementPattern = movementPattern
             existing.unilateral = unilateral
             existing.bilateralLoadFactor = bilateralLoadFactor
             existing.bodyweightFactor = bodyweightFactor
             existing.weightIncrement = weightIncrement
             existing.defaultRestTime = defaultRestTime
             existing.updatedAt = Date()

             try await exerciseService.updateExercise(
                 existing,
                 originalTrackingType: existingExercise?.trackingType ?? trackingType
             )
         } else {
             // Create new
             let exercise = Exercise(
                 name: name.trimmingCharacters(in: .whitespaces),
                 equipmentType: equipmentType,
                 trackingType: trackingType,
                 primaryMuscle: primaryMuscle.isEmpty ? nil : primaryMuscle,
                 secondaryMuscles: secondaryMuscles,
                 movementPattern: movementPattern,
                 unilateral: unilateral,
                 bilateralLoadFactor: bilateralLoadFactor,
                 bodyweightFactor: bodyweightFactor,
                 weightIncrement: weightIncrement,
                 defaultRestTime: defaultRestTime
             )
             try await exerciseService.createExercise(exercise)
         }
     }
     ```

  5. Check `Exercise` model init signature -- the `Exercise(...)` initializer may have specific parameter names. Read `Reppo/Data/Models/Exercise.swift` to confirm.

- **Notes**: The `updateExercise` method requires `originalTrackingType` to detect immutability violations. The service layer throws `ExerciseServiceError.trackingTypeImmutable` if violated. The ViewModel prevents this by locking the UI, but the service is a safety net.
- **Parallel?**: No - the view depends on this.

### Subtask T022 - Create CreateEditExerciseSheet UI

- **Purpose**: Full form for creating/editing exercises with all fields from specdoc Section 6.3.
- **File**: `Reppo/Features/Exercise/Views/CreateEditExerciseSheet.swift`
- **Steps**:
  1. Create the sheet view:
     ```swift
     struct CreateEditExerciseSheet: View {
         @State private var viewModel: CreateEditExerciseViewModel
         @Environment(\.dismiss) private var dismiss
         var onSave: (() -> Void)?

         init(exercise: Exercise?,
              services: ServiceContainer,
              onSave: (() -> Void)? = nil) {
             self._viewModel = State(initialValue: CreateEditExerciseViewModel(
                 exercise: exercise,
                 exerciseService: services.exerciseService
             ))
             self.onSave = onSave
         }
     }
     ```

  2. Build the form with grouped sections:
     ```swift
     var body: some View {
         NavigationStack {
             Form {
                 // Section 1: Basic Info
                 Section("Basic Info") {
                     TextField("Exercise Name", text: $viewModel.name)

                     Picker("Equipment", selection: $viewModel.equipmentType) {
                         ForEach(EquipmentType.allCases, id: \.self) { type in
                             Text(type.displayName).tag(type)
                         }
                     }

                     Picker("Tracking Type", selection: $viewModel.trackingType) {
                         ForEach(TrackingType.allCases, id: \.self) { type in
                             Text(type.displayName).tag(type)
                         }
                     }
                     .disabled(viewModel.isTrackingTypeLocked)
                 }

                 // Section 2: Muscles
                 Section("Muscles") {
                     TextField("Primary Muscle", text: $viewModel.primaryMuscle)
                     // Secondary muscles - simple comma-separated input
                     TextField("Secondary Muscles (comma-separated)",
                              text: secondaryMusclesBinding)
                     Picker("Movement Pattern", selection: $viewModel.movementPattern) {
                         Text("None").tag(Optional<MovementPattern>.none)
                         ForEach(MovementPattern.allCases, id: \.self) { pattern in
                             Text(pattern.displayName).tag(Optional(pattern))
                         }
                     }
                 }

                 // Section 3: Advanced
                 Section("Advanced") {
                     Toggle("Unilateral", isOn: $viewModel.unilateral)

                     HStack {
                         Text("Bodyweight Factor")
                         Spacer()
                         TextField("0.0", value: $viewModel.bodyweightFactor,
                                  format: .number)
                             .keyboardType(.decimalPad)
                             .multilineTextAlignment(.trailing)
                             .frame(width: 60)
                     }

                     HStack {
                         Text("Weight Increment")
                         Spacer()
                         TextField("kg", value: $viewModel.weightIncrement,
                                  format: .number)
                             .keyboardType(.decimalPad)
                             .multilineTextAlignment(.trailing)
                             .frame(width: 60)
                     }

                     HStack {
                         Text("Default Rest (sec)")
                         Spacer()
                         TextField("sec", value: $viewModel.defaultRestTime,
                                  format: .number)
                             .keyboardType(.numberPad)
                             .multilineTextAlignment(.trailing)
                             .frame(width: 60)
                     }
                 }

                 // trackingType lock notice
                 if viewModel.isTrackingTypeLocked {
                     Section {
                         Label("Tracking type cannot be changed because this exercise has recorded sets.",
                               systemImage: "lock.fill")
                             .font(.caption)
                             .foregroundStyle(Color.textTertiary)
                     }
                 }
             }
             .navigationTitle(viewModel.navigationTitle)
             .navigationBarTitleDisplayMode(.inline)
             .toolbar {
                 ToolbarItem(placement: .cancellationAction) {
                     Button("Cancel") { dismiss() }
                 }
                 ToolbarItem(placement: .confirmationAction) {
                     Button("Save") {
                         Task {
                             do {
                                 try await viewModel.save()
                                 onSave?()
                                 dismiss()
                             } catch {
                                 viewModel.errorMessage = error.localizedDescription
                                 viewModel.showError = true
                             }
                         }
                     }
                     .disabled(!viewModel.isValid || viewModel.isSaving)
                 }
             }
             .alert("Error", isPresented: $viewModel.showError) {
                 Button("OK") {}
             } message: {
                 Text(viewModel.errorMessage)
             }
             .task {
                 await viewModel.checkTrackingTypeLock()
             }
         }
     }
     ```

  3. Secondary muscles binding (convert between `[String]` and comma-separated `String`):
     ```swift
     private var secondaryMusclesBinding: Binding<String> {
         Binding(
             get: { viewModel.secondaryMuscles.joined(separator: ", ") },
             set: { newValue in
                 viewModel.secondaryMuscles = newValue
                     .split(separator: ",")
                     .map { $0.trimmingCharacters(in: .whitespaces) }
                     .filter { !$0.isEmpty }
             }
         )
     }
     ```

  4. **Enum display names**: `EquipmentType`, `TrackingType`, and `MovementPattern` need `displayName` computed properties for user-friendly labels. Check if these already exist. If not, add extensions in the same file or a shared extension file.

- **Notes**: Use SwiftUI `Form` for clean native iOS form layout. The dark mode styling should apply automatically. The `.scrollContentBackground(.hidden)` modifier and `.background(Color.bg)` may be needed to match the design system background.
- **Parallel?**: No - depends on T021 for the ViewModel.

### Subtask T023 - Implement trackingType lock

- **Purpose**: When editing an exercise that has associated sets, the trackingType picker must be disabled.
- **File**: Already covered in T021 (ViewModel `checkTrackingTypeLock()`) and T022 (View `.disabled(viewModel.isTrackingTypeLocked)`)
- **Steps**:
  1. Verify `isTrackingTypeLocked` is checked on view appear via `.task { await viewModel.checkTrackingTypeLock() }`
  2. Verify the Picker is disabled with `.disabled(viewModel.isTrackingTypeLocked)`
  3. Verify the informational notice appears below the form when locked
  4. Verify the service layer also enforces this (belt-and-suspenders): `ExerciseService.updateExercise()` throws if trackingType changed with sets present

- **Notes**: This is mostly verification that T021 and T022 handle this correctly. No separate file needed.
- **Parallel?**: No - validation of T021/T022.

### Subtask T024 - Wire save flow

- **Purpose**: Ensure create and update paths both work correctly with refresh callbacks.
- **File**: Already covered in T021 (ViewModel `save()`) and T022 (View save button action)
- **Steps**:
  1. **Create flow**:
     - User taps [+ New] in Exercise List -> sheet presents with `exercise: nil`
     - User fills form, taps Save
     - `viewModel.save()` calls `exerciseService.createExercise(_:)`
     - `onSave?()` callback fires (Exercise List ViewModel should reload)
     - Sheet dismisses

  2. **Edit flow**:
     - User taps Edit in Exercise Detail -> sheet presents with `exercise: existingExercise`
     - Form pre-populated from existing values
     - User modifies fields, taps Save
     - `viewModel.save()` calls `exerciseService.updateExercise(_:originalTrackingType:)`
     - If `bodyweightFactor`, `unilateral`, `bilateralLoadFactor`, or `equipmentType` changed, the service auto-triggers PR + Stats rebuild
     - `onSave?()` callback fires (Detail view should reload)
     - Sheet dismisses

  3. **Error handling**:
     - If save fails (e.g., trackingType violation), show alert with error message
     - If name is empty, Save button is disabled
     - If isSaving is true, Save button is disabled (prevent double-tap)

- **Notes**: The `onSave` callback is how parent views know to refresh. The Exercise List ViewModel's `loadExercises()` should be called in the callback.
- **Parallel?**: No - integration of T021/T022.

## Risks & Mitigations

- **Form field count**: 11+ fields could feel overwhelming. The 3-section grouping (Basic, Muscles, Advanced) mitigates this. Consider collapsing Advanced section by default.
- **Enum display names**: If `EquipmentType.displayName` etc. don't exist yet, they need to be added. Check the existing enum files first.
- **Exercise model initializer**: The `Exercise(...)` initializer may have specific required fields or defaults. Read the model file to confirm before writing the save logic.
- **Bodyweight factor validation**: Must be 0.0-1.0. Add a note or clamp the value.

## Definition of Done Checklist

- [ ] CreateEditExerciseViewModel manages all form fields and validation
- [ ] CreateEditExerciseSheet renders all fields from specdoc Section 6.3
- [ ] trackingType picker disabled when exercise has sets
- [ ] Lock notice displayed when trackingType is locked
- [ ] Create flow: new exercise saves correctly
- [ ] Edit flow: existing exercise updates correctly
- [ ] Save button disabled when name is empty or saving in progress
- [ ] Error alert shown on save failure
- [ ] `onSave` callback fires on successful save
- [ ] All colors from DesignTokens.swift
- [ ] `tasks.md` updated with status change

## Review Guidance

- Verify all 11 fields from specdoc Section 6.3 are present in the form
- Verify trackingType is disabled (not just hidden) when locked
- Verify save calls the correct service method (create vs update)
- Verify `updateExercise` passes `originalTrackingType` correctly
- Verify error handling for failed saves
- Verify onSave callback is wired to parent view refresh

## Activity Log

- 2026-02-25T08:19:17Z - system - lane=planned - Prompt created.
- 2026-02-26T15:11:55Z – claude – shell_pid=80535 – lane=doing – Started implementation via workflow command
- 2026-02-26T15:14:56Z – claude – shell_pid=80535 – lane=for_review – Ready for review: Create/Edit Exercise Sheet with form validation, trackingType lock, displayName on all enums, save flow for create and update
- 2026-02-26T20:20:46Z – claude – shell_pid=80535 – lane=done – Review passed: CreateEditExerciseSheet correctly implements create and edit modes, all required fields (name, equipment, primary/secondary muscles, tracking type), tracking type locked in edit mode, save/cancel flow, service integration. All DoD items met.
