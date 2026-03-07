---
work_package_id: "WP07"
subtasks:
  - "T031"
  - "T032"
  - "T033"
  - "T034"
  - "T035"
title: "Workout Summary Sheet — Finish Flow"
phase: "Phase 1 - Core UI"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "8697"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP02"]
history:
  - timestamp: "2026-02-24T14:26:08Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP07 – Workout Summary Sheet — Finish Flow

## Implementation Command

Depends on WP02:
```bash
spec-kitty implement WP07 --base WP02
```

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Objectives & Success Criteria

- "Finish Workout" presents a summary sheet with workout statistics
- Summary shows: date, duration, total volume, total sets, per-exercise breakdown, PRs hit
- User can enter workout notes and select session RPE (1-10)
- "Save & Close" calls WorkoutService.finishWorkout(), sets status=completed, dismisses screens
- Covers spec User Story 5 and FR-008

## Context & Constraints

**Feature**: 006-active-workout-screen — User Story 5 (Finish Workout)
**Spec**: spec.md — User Story 5 acceptance scenarios
**Plan**: `kitty-specs/006-active-workout-screen/plan.md` — Finish Workout data flow, WorkoutSummaryData types
**Data Model**: `kitty-specs/006-active-workout-screen/data-model.md` — Finish Workout Flow sequence
**Constitution**: All weight in kg, unit conversion at UI boundary, no startup rebuild

**Key constraint**: Summary stats are computed from local ViewModel state (current workout's sets already in memory). Do NOT load all sets from database — the in-memory data is sufficient and safe (typically 20-40 sets per workout).

## Subtasks & Detailed Guidance

### Subtask T031 – Create Summary Data Types + Computation

- **Purpose**: Define the data structures for workout summary and implement the computation method.
- **File**: `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` (add types + method)

**Steps**:
1. Define summary types (can be in the ViewModel file or a separate helper):
   ```swift
   struct WorkoutSummaryData {
       let date: Date
       let duration: TimeInterval
       let totalSets: Int
       let totalVolume: Double
       let exerciseSummaries: [ExerciseSummary]
       let prsHit: Int
   }

   struct ExerciseSummary: Identifiable {
       let id: UUID  // exerciseId
       let exerciseName: String
       let setCount: Int
       let bestWeight: Double?
       let bestReps: Int?
       let hadPR: Bool
   }
   ```

2. Add computation method to ViewModel:
   ```swift
   func computeSummary() -> WorkoutSummaryData? {
       guard let workout else { return nil }

       let startTime = workout.startTime ?? Date()
       let duration = Date().timeIntervalSince(startTime)

       var totalSets = 0
       var totalVolume: Double = 0
       var prsHit = 0
       var exerciseSummaries: [ExerciseSummary] = []

       for exercise in exercises {
           let sets = setsByExercise[exercise.id] ?? []
           let dataSets = sets.filter { $0.hasData }
           let completedSets = sets.filter { $0.completed }

           let exerciseSetCount = dataSets.count
           totalSets += exerciseSetCount

           // Volume: sum of effectiveWeight × reps for completed sets
           let exerciseVolume = completedSets.reduce(0.0) { sum, set in
               sum + (set.volume ?? 0)
           }
           totalVolume += exerciseVolume

           // Best weight in this exercise
           let bestWeight = completedSets.compactMap(\.effectiveWeight).max()

           // Best reps at heaviest weight
           let bestReps = completedSets.compactMap(\.reps).max()

           // PRs hit
           let exercisePRs = sets.filter { $0.cachedPRStatus == .current }.count
           prsHit += exercisePRs

           exerciseSummaries.append(ExerciseSummary(
               id: exercise.id,
               exerciseName: exercise.name,
               setCount: exerciseSetCount,
               bestWeight: bestWeight,
               bestReps: bestReps,
               hadPR: exercisePRs > 0
           ))
       }

       return WorkoutSummaryData(
           date: workout.date,
           duration: duration,
           totalSets: totalSets,
           totalVolume: totalVolume,
           exerciseSummaries: exerciseSummaries,
           prsHit: prsHit
       )
   }
   ```

3. Note: `hasData` and `volume` are computed properties on WorkoutSet (from feature 001). Verify they exist and work correctly.

**Validation**:
- [ ] Summary computation returns correct totals
- [ ] Per-exercise breakdown has correct set counts and best lifts
- [ ] PRs correctly counted (cachedPRStatus == .current)
- [ ] Handles empty workout gracefully (0 sets)

### Subtask T032 – Create WorkoutSummarySheet View

- **Purpose**: The main summary sheet UI showing workout statistics.
- **File**: `Reppo/Features/Workout/Views/WorkoutSummarySheet.swift` (new file)

**Steps**:
1. Create `WorkoutSummarySheet`:
   ```swift
   struct WorkoutSummarySheet: View {
       let viewModel: ActiveWorkoutViewModel
       @Environment(\.dismiss) private var dismiss

       @State private var notes: String = ""
       @State private var selectedRPE: Int? = nil
       @State private var isSaving = false

       var body: some View {
           NavigationStack {
               ScrollView {
                   VStack(spacing: 20) {
                       if let summary = viewModel.computeSummary() {
                           // Date + Duration header
                           headerSection(summary: summary)

                           // Stats row
                           statsRow(summary: summary)

                           // Exercise breakdown
                           exerciseList(summary: summary)

                           // PRs highlight (if any)
                           if summary.prsHit > 0 {
                               prsSection(count: summary.prsHit)
                           }

                           // Notes + RPE (T033)
                           notesSection
                           rpeSelector
                       }
                   }
                   .padding(.horizontal, 20)
               }
               .background(Color.bg)
               .navigationTitle("Workout Complete")
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                   ToolbarItem(placement: .confirmationAction) {
                       Button("Save & Close") {
                           Task { await saveAndClose() }
                       }
                       .fontWeight(.semibold)
                       .disabled(isSaving)
                   }
               }
           }
       }
   }
   ```

2. Header section: Date formatted ("Mon, Feb 24"), duration formatted ("1h 23m"):
   ```swift
   private func headerSection(summary: WorkoutSummaryData) -> some View {
       VStack(spacing: 4) {
           Text(summary.date, style: .date)
               .font(.subheadline)
               .foregroundColor(Color.textSecondary)
           Text(formatDuration(summary.duration))
               .font(.system(size: 32, weight: .bold))
               .foregroundColor(Color.textPrimary)
       }
       .padding(.top, 20)
   }
   ```

3. Stats row: Two or three stat cards (Total Sets, Total Volume, PRs):
   ```swift
   private func statsRow(summary: WorkoutSummaryData) -> some View {
       HStack(spacing: 12) {
           StatCard(label: "Sets", value: "\(summary.totalSets)")
           StatCard(label: "Volume", value: formatVolume(summary.totalVolume))
           if summary.prsHit > 0 {
               StatCard(label: "PRs", value: "\(summary.prsHit)", highlight: true)
           }
       }
   }
   ```

4. Exercise list: Each exercise with name, set count, and best lift:
   ```swift
   private func exerciseList(summary: WorkoutSummaryData) -> some View {
       VStack(spacing: 8) {
           ForEach(summary.exerciseSummaries) { exercise in
               HStack {
                   VStack(alignment: .leading, spacing: 2) {
                       HStack {
                           Text(exercise.exerciseName)
                               .font(.system(size: 15, weight: .medium))
                               .foregroundColor(Color.textPrimary)
                           if exercise.hadPR {
                               PRBadgeView(status: .current)
                           }
                       }
                       Text("\(exercise.setCount) sets")
                           .font(.caption)
                           .foregroundColor(Color.textSecondary)
                   }
                   Spacer()
                   if let weight = exercise.bestWeight {
                       Text(formatWeight(weight))
                           .font(.system(size: 15, weight: .semibold))
                           .foregroundColor(Color.textPrimary)
                   }
               }
               .padding(.vertical, 8)
               .padding(.horizontal, 12)
               .background(Color.bgCard)
               .cornerRadius(8)
           }
       }
   }
   ```

5. Volume formatting: Show in kg (e.g., "12,450 kg"). Weight formatting: Show in kg with unit label. Use the user's UnitPreference if available (from HealthProfile), but for v1 default to kg.

**Validation**:
- [ ] Summary sheet shows date and formatted duration
- [ ] Stats row shows total sets, volume, and PR count
- [ ] Exercise list shows each exercise with set count and best weight
- [ ] PRs highlighted with gold badge
- [ ] Design tokens used consistently

### Subtask T033 – Add Notes TextEditor and RPE Selector

- **Purpose**: Allow user to enter workout notes and select session RPE (1-10).
- **File**: `WorkoutSummarySheet.swift` (add sections)
- **Parallel?**: Yes — independent of stats computation.

**Steps**:
1. Notes section:
   ```swift
   private var notesSection: some View {
       VStack(alignment: .leading, spacing: 8) {
           Text("Notes")
               .font(.system(size: 13, weight: .semibold))
               .foregroundColor(Color.textSecondary)
           TextEditor(text: $notes)
               .frame(minHeight: 80)
               .padding(8)
               .background(Color.bgInput)
               .cornerRadius(8)
               .overlay(
                   RoundedRectangle(cornerRadius: 8)
                       .stroke(Color.appBorder, lineWidth: 1)
               )
               .font(.system(size: 15))
               .foregroundColor(Color.textPrimary)
       }
   }
   ```

2. RPE selector — horizontal row of 1-10 buttons:
   ```swift
   private var rpeSelector: some View {
       VStack(alignment: .leading, spacing: 8) {
           Text("Session RPE")
               .font(.system(size: 13, weight: .semibold))
               .foregroundColor(Color.textSecondary)
           HStack(spacing: 6) {
               ForEach(1...10, id: \.self) { rpe in
                   Button("\(rpe)") {
                       selectedRPE = (selectedRPE == rpe) ? nil : rpe
                   }
                   .font(.system(size: 14, weight: selectedRPE == rpe ? .bold : .regular))
                   .foregroundColor(selectedRPE == rpe ? .white : Color.textSecondary)
                   .frame(width: 32, height: 32)
                   .background(selectedRPE == rpe ? Color.appBlue : Color.bgSubtle)
                   .cornerRadius(6)
               }
           }
       }
   }
   ```

3. Tapping the same RPE again deselects it (optional RPE).

4. Pre-populate notes from `viewModel.workout?.notes` if any exist (e.g., mid-workout notes).

**Validation**:
- [ ] Notes text editor accepts free-form text
- [ ] RPE selector shows 1-10 buttons
- [ ] Selected RPE is highlighted in blue
- [ ] Tapping selected RPE deselects it
- [ ] TextEditor styling matches design tokens

### Subtask T034 – Implement finishWorkout() in ViewModel

- **Purpose**: Call WorkoutService to finish the workout with notes and RPE data.
- **File**: `ActiveWorkoutViewModel.swift` (add method)

**Steps**:
1. Implement `finishWorkout(notes:perceivedEffort:)`:
   ```swift
   func finishWorkout(notes: String?, perceivedEffort: Double?) async {
       guard let workoutId = workout?.id else { return }

       do {
           // Call WorkoutService.finishWorkout()
           try await workoutService.finishWorkout(workoutId)

           // Notes and perceivedEffort may need separate handling.
           // Check WorkoutServiceProtocol — if finishWorkout() doesn't accept
           // these params, may need to update the workout object before finishing,
           // or call a separate update method.

           // Dismiss rest timer if running
           dismissTimer()

       } catch {
           print("Failed to finish workout: \(error)")
       }
   }
   ```

2. **Critical**: Read `WorkoutServiceProtocol.finishWorkout()` signature. It may only take a `workoutId` and handle status+endTime+duration internally. If notes/RPE aren't accepted:
   - Option A: The workout object is a SwiftData `@Model` — update `workout.notes` and `workout.perceivedEffort` directly before calling finish (if the object is still managed).
   - Option B: Check if WorkoutService has an `updateWorkout()` or if there's a way to pass these fields.
   - Do NOT invent new service methods — use what exists.

3. The actual navigation dismissal is handled in the sheet's `saveAndClose()` function (T035).

**Validation**:
- [ ] WorkoutService.finishWorkout() called successfully
- [ ] Notes and RPE saved to workout
- [ ] Rest timer dismissed
- [ ] Errors handled gracefully

### Subtask T035 – Handle Post-Finish Navigation

- **Purpose**: After saving, dismiss the summary sheet AND the active workout screen, returning to the main view.
- **File**: `WorkoutSummarySheet.swift` (saveAndClose method)

**Steps**:
1. Implement `saveAndClose()` in the sheet:
   ```swift
   private func saveAndClose() async {
       isSaving = true
       await viewModel.finishWorkout(
           notes: notes.isEmpty ? nil : notes,
           perceivedEffort: selectedRPE.map(Double.init)
       )
       isSaving = false

       // Dismiss the sheet
       dismiss()

       // The active workout screen should also dismiss.
       // This can be handled by:
       // 1. Setting a flag on the ViewModel: viewModel.isWorkoutFinished = true
       // 2. The ActiveWorkoutView observes this and calls its own dismiss
       // 3. Or use a shared navigation state
   }
   ```

2. In `ActiveWorkoutView`, observe a "finished" state:
   ```swift
   // Add to ActiveWorkoutViewModel:
   var isWorkoutFinished = false

   // In ActiveWorkoutView:
   @Environment(\.dismiss) private var dismiss

   .onChange(of: viewModel.isWorkoutFinished) { _, finished in
       if finished {
           dismiss()
       }
   }
   ```

3. After both dismissals, user should be back at ContentView. Future features will navigate to Calendar tab instead.

4. **Important**: Set `isWorkoutFinished = true` in `finishWorkout()` after the service call succeeds. The sheet dismissal chain: sheet dismisses → ActiveWorkoutView sees isWorkoutFinished → dismisses itself.

**Validation**:
- [ ] "Save & Close" calls finishWorkout then dismisses sheet
- [ ] Active workout screen also dismisses after sheet
- [ ] User returns to ContentView (or Calendar tab in future)
- [ ] Loading state prevents double-tap
- [ ] Navigation doesn't leave orphaned screens

## Risks & Mitigations

- **WorkoutService.finishWorkout() API mismatch**: The method may not accept notes/RPE. Read the protocol carefully. If needed, update the workout's notes/perceivedEffort fields before calling finish.
- **Double dismissal coordination**: Dismissing a sheet AND its parent view can be tricky in SwiftUI. Using the `isWorkoutFinished` flag on the ViewModel provides a clean signal. Test that both dismissals happen smoothly without animation glitches.
- **Volume computation accuracy**: Using `set.volume` (effectiveWeight × reps) from the computed property. Verify this exists on WorkoutSet. If not, compute manually: `(set.effectiveWeight ?? 0) * Double(set.reps ?? 0)`.

## Definition of Done Checklist

- [ ] Summary sheet shows all required stats (date, duration, sets, volume, exercises, PRs)
- [ ] Notes text editor works
- [ ] RPE selector works (1-10)
- [ ] "Save & Close" finishes workout via service
- [ ] Both sheet and active workout screen dismiss after save
- [ ] Design tokens used throughout
- [ ] Project builds with zero errors

## Review Guidance

- Verify summary stats are computed correctly (not from database, from local state)
- Verify notes and RPE are saved to the workout
- Test the double-dismissal flow (sheet → active workout → ContentView)
- Check that volume calculation matches constitution (effectiveWeight × reps)
- Verify empty workout summary (0 exercises, 0 sets) doesn't crash

## Activity Log

- 2026-02-24T14:26:08Z – system – lane=planned – Prompt created.
- 2026-02-25T07:42:00Z – claude – shell_pid=7825 – lane=doing – Started implementation via workflow command
- 2026-02-25T07:45:53Z – claude – shell_pid=7825 – lane=for_review – Ready for review: WorkoutSummarySheet with stats (date, duration, sets, volume, PRs), per-exercise breakdown, notes TextEditor, RPE 1-10 selector. Double-dismiss via isWorkoutFinished flag. Replaces WP05 placeholder. Build succeeds.
- 2026-02-25T07:47:27Z – claude – shell_pid=8697 – lane=doing – Started review via workflow command
- 2026-02-25T07:47:45Z – claude – shell_pid=8697 – lane=done – Review passed: WorkoutSummarySheet shows date/duration/sets/volume/PRs from in-memory state, per-exercise breakdown with PRBadgeView, notes TextEditor with scrollContentBackground(.hidden), RPE 1-10 toggle selector, Cancel + Save & Close toolbar, isWorkoutFinished double-dismiss pattern, placeholder removed. Design tokens consistent throughout.
