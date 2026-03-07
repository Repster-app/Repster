---
work_package_id: "WP05"
subtasks:
  - "T022"
  - "T023"
  - "T024"
  - "T025"
  - "T026"
title: "ActiveWorkoutView — Screen Assembly + Navigation"
phase: "Phase 2 - Integration"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "6525"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP03", "WP04"]
history:
  - timestamp: "2026-02-24T14:26:08Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP05 – ActiveWorkoutView — Screen Assembly + Navigation

## Implementation Command

Depends on WP03 and WP04:
```bash
spec-kitty implement WP05 --base WP04
```

Note: WP05 depends on both WP03 (SetTableView) and WP04 (ExerciseTabStripView). Use `--base WP04` since WP04 already includes WP02→WP01 chain. WP03 should also be merged before starting this WP.

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Objectives & Success Criteria

- `ActiveWorkoutView` assembles header + tab strip + set table into a focused full-screen experience
- No bottom navigation visible (FR-001)
- Header shows: back button, live elapsed timer, +Exercise button, Finish Workout button
- Elapsed timer updates every second showing time since workout start (FR-013)
- +Exercise button presents ExercisePickerSheet stub (FR-007)
- Navigation: ContentView checks for active workout on launch and navigates to it (AGENT_RULES S7.3)
- Screen background is `bg` (#111113) with 20pt horizontal padding

## Context & Constraints

**Feature**: 006-active-workout-screen — Screen assembly + navigation wiring
**Plan**: `kitty-specs/006-active-workout-screen/plan.md` — View Decomposition section
**Constitution**: NavigationStack (not NavigationView), no bottom nav on focused screens, 44pt tap targets
**AGENT_RULES**: Section 7.3 — Active workout flow, workout resume on app launch

**Depends on**:
- WP01 (design tokens), WP02 (ViewModel), WP03 (SetTableView), WP04 (ExerciseTabStripView)

**ContentView current state**: Minimal placeholder (`Reppo/App/ContentView.swift`) showing "reppo" text. This WP replaces it with active workout navigation.

## Subtasks & Detailed Guidance

### Subtask T022 – Create ActiveWorkoutView Main Layout

- **Purpose**: The main focused screen composing all sub-views into a vertical layout.
- **File**: `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` (new file)

**Steps**:
1. Create `ActiveWorkoutView`:
   ```swift
   struct ActiveWorkoutView: View {
       @State private var viewModel: ActiveWorkoutViewModel

       init(workoutService: any WorkoutServiceProtocol,
            setService: any SetServiceProtocol,
            exerciseService: any ExerciseServiceProtocol) {
           _viewModel = State(initialValue: ActiveWorkoutViewModel(
               workoutService: workoutService,
               setService: setService,
               exerciseService: exerciseService
           ))
       }

       var body: some View {
           VStack(spacing: 0) {
               // Header bar (T023)
               ActiveWorkoutHeaderView(viewModel: viewModel)

               // Exercise tab strip (from WP04)
               ExerciseTabStripView(viewModel: viewModel)

               // Set table (from WP03)
               if viewModel.currentExercise != nil {
                   SetTableView(viewModel: viewModel)
               } else {
                   // Empty state: no exercises yet
                   emptyExerciseState
               }

               Spacer()

               // Rest timer (WP06 — placeholder for now)
           }
           .background(Color.bg.ignoresSafeArea())
           .task {
               await viewModel.loadActiveWorkout()
           }
           // Sheets
           .sheet(isPresented: $viewModel.showAddExerciseSheet) {
               ExercisePickerSheet(viewModel: viewModel)
           }
           .sheet(isPresented: $viewModel.showFinishSheet) {
               // WorkoutSummarySheet (WP07 — placeholder for now)
               Text("Workout Summary — Coming in WP07")
           }
       }

       private var emptyExerciseState: some View {
           VStack(spacing: 16) {
               Image(systemName: "dumbbell")
                   .font(.system(size: 48))
                   .foregroundColor(Color.textTertiary)
               Text("No exercises yet")
                   .font(.headline)
                   .foregroundColor(Color.textSecondary)
               Button("Add Exercises") {
                   viewModel.showAddExerciseSheet = true
               }
               .foregroundColor(Color.appBlue)
           }
           .frame(maxWidth: .infinity, maxHeight: .infinity)
       }
   }
   ```

2. Ensure no bottom navigation: If presented via `.fullScreenCover`, the parent's tab bar is naturally hidden. If using NavigationStack push, may need `.toolbar(.hidden, for: .tabBar)`.

3. Background: `Color.bg.ignoresSafeArea()` to fill the entire screen.

**Validation**:
- [ ] Screen composes header + tab strip + set table vertically
- [ ] bg background fills entire screen including safe areas
- [ ] Empty state shown when no exercises
- [ ] Sheets for exercise picker and finish summary are wired
- [ ] loadActiveWorkout() called on appear

### Subtask T023 – Build Header Bar

- **Purpose**: Top bar with back button, elapsed timer, and action buttons.
- **File**: `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` (as a subview or separate file)

**Steps**:
1. Create header bar (can be a private subview or separate `ActiveWorkoutHeaderView`):
   ```swift
   HStack {
       // Back / dismiss
       Button(action: { /* dismiss */ }) {
           Image(systemName: "chevron.left")
               .font(.system(size: 18, weight: .semibold))
               .foregroundColor(Color.textPrimary)
               .frame(width: 44, height: 44)
       }

       Spacer()

       // Elapsed timer (T024)
       ElapsedTimerView(startTime: viewModel.workout?.startTime)

       Spacer()

       // +Exercise
       Button(action: { viewModel.showAddExerciseSheet = true }) {
           Image(systemName: "plus")
               .font(.system(size: 18, weight: .semibold))
               .foregroundColor(Color.appBlue)
               .frame(width: 44, height: 44)
       }

       // Finish Workout
       Button("Finish") {
           viewModel.showFinishSheet = true
       }
       .font(.system(size: 14, weight: .semibold))
       .foregroundColor(.white)
       .padding(.horizontal, 12)
       .padding(.vertical, 8)
       .background(Color.appBlue)
       .cornerRadius(8)
   }
   .padding(.horizontal, 20)
   .padding(.vertical, 8)
   ```

2. Back button: For `.fullScreenCover`, use `@Environment(\.dismiss)`. For NavigationStack, use the standard back behavior.

3. All buttons must have 44pt tap targets.

**Validation**:
- [ ] Back button dismisses the screen
- [ ] +Exercise opens picker sheet
- [ ] Finish opens summary sheet
- [ ] All buttons >= 44pt tap targets
- [ ] Elapsed timer visible and centered

### Subtask T024 – Implement Elapsed Timer

- **Purpose**: Live-updating display showing time since workout started.
- **File**: `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` or separate `ElapsedTimerView.swift`

**Steps**:
1. Use `TimelineView(.periodic(every: 1))` for efficient once-per-second updates:
   ```swift
   struct ElapsedTimerView: View {
       let startTime: Date?

       var body: some View {
           TimelineView(.periodic(every: 1)) { context in
               if let startTime {
                   let elapsed = context.date.timeIntervalSince(startTime)
                   Text(formatElapsed(elapsed))
                       .font(.system(size: 16, weight: .semibold, design: .monospaced))
                       .foregroundColor(Color.textPrimary)
               }
           }
       }

       private func formatElapsed(_ interval: TimeInterval) -> String {
           let total = Int(interval)
           let hours = total / 3600
           let minutes = (total % 3600) / 60
           let seconds = total % 60
           if hours > 0 {
               return String(format: "%d:%02d:%02d", hours, minutes, seconds)
           }
           return String(format: "%d:%02d", minutes, seconds)
       }
   }
   ```

2. `TimelineView` is preferred over `Timer.publish` for this use case — it's purpose-built for views that update on a schedule and handles lifecycle automatically.

3. Format: "M:SS" for under 1 hour, "H:MM:SS" for over 1 hour. Use monospaced design to prevent layout shifts.

**Validation**:
- [ ] Timer ticks every second
- [ ] Format shows correct elapsed time
- [ ] Monospaced font prevents jumping
- [ ] Timer handles nil startTime gracefully

### Subtask T025 – Create ExercisePickerSheet Stub

- **Purpose**: Temporary exercise picker until feature 007 provides the full Exercise List. Users need to add exercises to their workout.
- **File**: `Reppo/Features/Workout/Views/ExercisePickerSheet.swift` (new file)
- **Parallel?**: Yes — independent of main screen internals.

**Steps**:
1. Create a simple sheet that:
   - Fetches all exercises via `exerciseService.fetchAllExercises()` on appear
   - Displays in a searchable `List`
   - Multi-select with checkmarks (track selected exerciseIds in `@State`)
   - "Add Selected" button at bottom

   ```swift
   struct ExercisePickerSheet: View {
       let viewModel: ActiveWorkoutViewModel
       @Environment(\.dismiss) private var dismiss
       @State private var exercises: [Exercise] = []
       @State private var selectedIds: Swift.Set<UUID> = []
       @State private var searchText = ""

       var filteredExercises: [Exercise] {
           if searchText.isEmpty { return exercises }
           return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
       }

       var body: some View {
           NavigationStack {
               List(filteredExercises) { exercise in
                   HStack {
                       Text(exercise.name)
                           .foregroundColor(Color.textPrimary)
                       Spacer()
                       if selectedIds.contains(exercise.id) {
                           Image(systemName: "checkmark")
                               .foregroundColor(Color.appBlue)
                       }
                   }
                   .contentShape(Rectangle())
                   .onTapGesture {
                       if selectedIds.contains(exercise.id) {
                           selectedIds.remove(exercise.id)
                       } else {
                           selectedIds.insert(exercise.id)
                       }
                   }
               }
               .searchable(text: $searchText)
               .navigationTitle("Add Exercises")
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                   ToolbarItem(placement: .cancellationAction) {
                       Button("Cancel") { dismiss() }
                   }
                   ToolbarItem(placement: .confirmationAction) {
                       Button("Add (\(selectedIds.count))") {
                           Task {
                               await viewModel.addExercises(Array(selectedIds))
                               dismiss()
                           }
                       }
                       .disabled(selectedIds.isEmpty)
                   }
               }
           }
           .task {
               // Fetch exercises — need ExerciseService access
               // The VM has exerciseService, or inject it separately
           }
       }
   }
   ```

2. **Service access**: The picker needs ExerciseService to fetch exercises. Either pass it as a parameter, access via `@Environment`, or have the ViewModel provide a method.

3. This is a **stub** — feature 007 will replace it with the full exercise browser. Keep it simple.

**Validation**:
- [ ] Sheet shows list of exercises
- [ ] Search filters exercises by name
- [ ] Multi-select works (checkmarks appear/disappear)
- [ ] "Add" button adds selected exercises to workout
- [ ] "Cancel" dismisses without changes

### Subtask T026 – Wire Navigation in ContentView

- **Purpose**: Connect the app's root to the active workout screen. Handle workout resume on app launch per AGENT_RULES S7.3.
- **File**: `Reppo/App/ContentView.swift` (modify existing)

**Steps**:
1. Read the current `ContentView.swift` — it's a placeholder showing "reppo" text.
2. Add active workout detection on launch:
   ```swift
   struct ContentView: View {
       @Environment(ServiceContainer.self) private var services
       @State private var showActiveWorkout = false
       @State private var hasCheckedForActive = false

       var body: some View {
           ZStack {
               Color.bg.ignoresSafeArea()

               VStack(spacing: 20) {
                   Text("reppo")
                       .font(.largeTitle)
                       .fontWeight(.bold)
                       .foregroundStyle(.white)

                   // Temporary: Start Workout button for dev testing
                   Button("Start Workout") {
                       Task {
                           _ = try? await services.workoutService.startWorkout()
                           showActiveWorkout = true
                       }
                   }
                   .foregroundColor(Color.appBlue)
               }
           }
           .preferredColorScheme(.dark)
           .fullScreenCover(isPresented: $showActiveWorkout) {
               ActiveWorkoutView(
                   workoutService: services.workoutService,
                   setService: services.setService,
                   exerciseService: services.exerciseService
               )
           }
           .task {
               // Check for active workout on launch
               guard !hasCheckedForActive else { return }
               hasCheckedForActive = true
               if let _ = try? await services.workoutService.getActiveWorkout() {
                   showActiveWorkout = true
               }
           }
       }
   }
   ```

3. **Key behavior**: On first launch, if an inProgress workout exists, navigate directly to it. This handles the "app killed during workout" edge case.

4. Use `.fullScreenCover` for the active workout to completely hide the content behind it (no bottom nav visible).

5. The "Start Workout" button is temporary — the real FAB will come with the tab navigation feature. This allows testing the active workout flow.

**Validation**:
- [ ] App checks for active workout on launch
- [ ] If active workout exists, navigates to ActiveWorkoutView automatically
- [ ] "Start Workout" button creates a workout and navigates
- [ ] Active workout screen is full-screen (no bottom nav visible)
- [ ] Dismissing active workout returns to ContentView

## Risks & Mitigations

- **Navigation stack complexity**: Using `.fullScreenCover` is simplest for hiding bottom nav. When the real tab navigation arrives (future feature), this may need to change. Keep it simple for now.
- **ServiceContainer availability**: Ensure `@Environment(ServiceContainer.self)` is available in ContentView. Check that `ReppoApp.swift` injects it via `.environment(services)`.
- **Exercise picker service access**: The picker sheet needs ExerciseService. Either pass the ViewModel (which has it) or inject via @Environment.

## Definition of Done Checklist

- [ ] ActiveWorkoutView assembles all sub-views correctly
- [ ] Header bar with back, timer, +Exercise, Finish all functional
- [ ] Elapsed timer ticks every second
- [ ] Exercise picker sheet opens and adds exercises
- [ ] ContentView navigates to active workout on launch if one exists
- [ ] Full-screen presentation hides any bottom UI
- [ ] Empty state shown when no exercises
- [ ] Project builds with zero errors

## Review Guidance

- Verify full-screen presentation (no bottom nav leaking)
- Verify elapsed timer format and monospaced font
- Verify workout resume on app relaunch
- Test exercise picker search and multi-select
- Check that back button properly dismisses
- Verify empty exercise state prompts to add exercises

## Activity Log

- 2026-02-24T14:26:08Z – system – lane=planned – Prompt created.
- 2026-02-24T19:22:49Z – claude – shell_pid=19762 – lane=doing – Started implementation via workflow command
- 2026-02-24T19:28:34Z – claude – shell_pid=19762 – lane=for_review – Ready for review: ActiveWorkoutView (screen assembly), ElapsedTimerView (TimelineView 1s timer), ExercisePickerSheet (stub with search/multi-select), ContentView (active workout detection on launch via fullScreenCover). Also registered all 12 Feature 006 files in project.pbxproj and fixed SetRowView set keyword ambiguity. Build succeeds zero errors.
- 2026-02-25T07:34:20Z – claude – shell_pid=6525 – lane=doing – Started review via workflow command
- 2026-02-25T07:34:27Z – claude – shell_pid=6525 – lane=done – Review passed: ActiveWorkoutView assembles header+tabs+table correctly, ElapsedTimerView uses TimelineView with monospaced font, ExercisePickerSheet stub with search/multi-select, ContentView wires active workout detection via fullScreenCover. All 12 Feature 006 files registered in pbxproj. No blocking layer violations (picker service access spec-allowed), design tokens used consistently, build succeeds.
