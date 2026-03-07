---
work_package_id: "WP03"
subtasks:
  - "T011"
  - "T012"
  - "T013"
  - "T014"
  - "T015"
  - "T016"
  - "T017"
title: "Workout Detail — Stats, Exercise Cards, Navigation, Edge Cases"
phase: "Phase 2 - Workout Detail"
lane: "done"
assignee: ""
agent: "claude-opus"
shell_pid: ""
review_status: "approved"
reviewed_by: "claude-opus"
dependencies: ["WP01", "WP02"]
history:
  - timestamp: "2026-02-27T09:26:46Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-02-27T10:55:00Z"
    lane: "doing"
    agent: "claude-opus"
    action: "Started implementation in worktree 008-calendar-tab-WP03"
  - timestamp: "2026-02-27T11:00:00Z"
    lane: "for_review"
    agent: "claude-opus"
    action: "Ready for review: SummaryStatsStrip, CalendarExerciseCard, CalendarWorkoutDetailView, selectDate loading, ExerciseDetail navigation, multi-workout support, edge cases. Build succeeds."
  - timestamp: "2026-02-27T11:15:00Z"
    lane: "done"
    agent: "claude-opus"
    action: "Review passed: Fixed equipmentType.displayName, volume format, force-unwrap. Zero blocking issues."
---

# Work Package Prompt: WP03 – Workout Detail — Stats, Exercise Cards, Navigation, Edge Cases

## Objectives & Success Criteria

- Build the workout detail section in the lower half of the split view.
- Create `SummaryStatsStrip` showing volume, exercise count, set count.
- Create `CalendarExerciseCard` with read-only set rows and PR badges.
- Create `CalendarWorkoutDetailView` as the container orchestrating stats and cards.
- Implement workout detail data loading in `CalendarViewModel` (fetch sets, group by exercise, compute stats).
- Navigation from exercise card to `ExerciseDetailView` (reused from feature 007).
- Handle multiple workouts on the same date with visual separation.
- Handle edge cases: empty state, no workout, long workout scrolling.
- **Success**: Tapping a date shows summary stats and exercise cards. PR badges display correctly. Tapping an exercise card navigates to ExerciseDetailView. Multiple workouts appear stacked. Empty dates show "No workout."

## Context & Constraints

- **Depends on WP01 + WP02**: CalendarView with split layout, CalendarViewModel with dot data, date selection.
- **Architecture**: MVVM. Detail data loaded on-demand when a date is tapped. Not pre-loaded.
- **Reuse from existing codebase**:
  - `PRBadgeView` from `Reppo/Features/Workout/Views/Components/PRBadgeView.swift` — shows gold PR or blue match badge based on `cachedPRStatus`.
  - `ExerciseDetailView` from `Reppo/Features/Exercise/Views/ExerciseDetailView.swift` — takes `exerciseId: UUID`, creates its own ViewModel. Push via NavigationStack.
- **Design patterns**: Follow design-system.md Section 6.2 (Card patterns) and Section 6.4 (Badge styles).
- **Constitution**: Metric storage, convert to user's unit in UI. `hasData` not `completed` for analytics. Read-only set rows (no editing from calendar). Bottom nav visible.
- **Data model**: See `kitty-specs/008-calendar-tab/data-model.md` for `WorkoutDetail` and `ExerciseGroup` structures.

**Existing APIs to use**:
- `SetService.fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]`
- `SetService.fetchExerciseIds(for workoutId: UUID) async throws -> Swift.Set<UUID>`
- `ExerciseService.fetchExercise(_ UUID) async throws -> Exercise?`
- `StatsService.fetchStats(for exerciseId: UUID) async throws -> ExerciseStats?`

**Implementation command**: `spec-kitty implement WP03 --base WP02`

## Subtasks & Detailed Guidance

### Subtask T011 – Create SummaryStatsStrip.swift

- **Purpose**: Horizontal stats strip showing workout summary metrics: total volume, exercise count, set count. Follows the "Summary Stat Card" pattern from design-system.md.
- **File**: `Reppo/Features/Calendar/Views/Components/SummaryStatsStrip.swift` (new file)
- **Parallel?**: Yes — independent presentational component.

**Steps**:
1. Create the view:
   ```swift
   struct SummaryStatsStrip: View {
       let totalVolume: Double
       let exerciseCount: Int
       let setCount: Int
       let duration: Int?  // seconds, optional
   }
   ```

2. **Layout**: Follow design-system.md "Summary Stat Card" pattern:
   ```
   HStack (inside bgCard container, 14pt radius)
   ├── Stat: Volume (e.g., "12,450 kg") — large value + "Volume" label
   ├── Divider (1px border color)
   ├── Stat: Exercises (e.g., "5") — large value + "Exercises" label
   ├── Divider
   ├── Stat: Sets (e.g., "23") — large value + "Sets" label
   ├── Divider (optional, only if duration present)
   └── Stat: Duration (e.g., "1:12:30") — large value + "Duration" label
   ```

3. **Styling** per design-system.md:
   - Background: `Color.bgCard`
   - Corner radius: 14pt
   - Padding: 14pt
   - Large value: 18pt bold, `textPrimary`
   - Label: 10pt uppercase medium, `textTertiary` (labeled as `textDim` in design system — maps to `textTertiary`)
   - Dividers: 1px `Color.border`, inset 2pt top/bottom

4. **Volume formatting**: Convert kg to user's preferred unit if needed. For now, display as formatted weight:
   ```swift
   private func formatVolume(_ kg: Double) -> String {
       if kg >= 1000 {
           return String(format: "%.1fk", kg / 1000)
       }
       return "\(Int(kg))"
   }
   ```
   Append unit suffix: "kg" or "lbs" based on user preference (check if a `UnitPreference` is accessible — it's in the `HealthProfile` model).

5. **Duration formatting**: Convert seconds to `H:MM:SS` or `MM:SS`:
   ```swift
   private func formatDuration(_ seconds: Int) -> String {
       let hours = seconds / 3600
       let minutes = (seconds % 3600) / 60
       let secs = seconds % 60
       if hours > 0 {
           return String(format: "%d:%02d:%02d", hours, minutes, secs)
       }
       return String(format: "%d:%02d", minutes, secs)
   }
   ```

**Validation**:
- Strip renders with correct values.
- Dividers appear between items.
- Text styling matches design-system.md.
- Duration shows only when non-nil.

---

### Subtask T012 – Create CalendarExerciseCard.swift

- **Purpose**: Read-only exercise card showing exercise name, equipment type, set count, and a table of set rows with weight/reps/PR badges. Follows "Exercise Card (Day View)" pattern from design-system.md.
- **File**: `Reppo/Features/Calendar/Views/Components/CalendarExerciseCard.swift` (new file)
- **Parallel?**: Yes — independent presentational component.

**Steps**:
1. Create the view:
   ```swift
   struct CalendarExerciseCard: View {
       let exercise: Exercise
       let sets: [WorkoutSet]
       let stats: ExerciseStats?
       let onTapped: () -> Void
   }
   ```

2. **Layout** per design-system.md "Exercise Card (Day View)":
   ```
   VStack (bgCard, 14pt radius, 14pt padding)
   ├── Header: HStack
   │   ├── Exercise name (15pt semibold, textPrimary)
   │   ├── Spacer
   │   └── Set count badge (bgSubtle, "5 sets", 12pt)
   ├── Set Table:
   │   ├── Column headers: "Set" | "Weight" | "Reps" | "" (PR badge area)
   │   │   Style: 11pt medium, textTertiary
   │   └── ForEach(sets) → Set Row:
   │       ├── Set number (12pt, textSecondary)
   │       ├── Weight with unit (14pt semibold, textPrimary)
   │       ├── Reps (14pt semibold, textPrimary)
   │       └── PRBadgeView(status: set.cachedPRStatus)
   │       Warmup rows: 0.45 opacity
   └── Footer (optional): Best weight from stats
       "Best: 85 kg × 8" (12pt, textTertiary, with green dot)
   ```

3. **Set row rendering**:
   - Filter to sets with `hasData` (show only sets that have actual values).
   - Order by `orderInExercise`.
   - Warmup sets (`setType == .warmup`): render at 0.45 opacity.
   - Weight display: format as `"\(Int(weight)) kg"` (convert to user's unit if needed).
   - Reps display: format as `"\(reps)"`.
   - PR badge: use existing `PRBadgeView(status: set.cachedPRStatus)` from `Reppo/Features/Workout/Views/Components/PRBadgeView.swift`.

4. **Set rows are read-only**: No tap handlers, no editing, no checkboxes. Just display.

5. **Card is tappable**: Entire card wrapped in a `Button` or uses `onTapGesture` calling `onTapped()`. This navigates to `ExerciseDetailView`.

6. **Import PRBadgeView**: Since it's in `Reppo/Features/Workout/Views/Components/`, it should be accessible project-wide (same target).

**Notes**:
- The set number should reflect the visual order (1, 2, 3...), not `orderInExercise` directly if warmups have different numbering. Simplest: just use the index + 1 in the `ForEach`.
- If `exercise.equipmentType` is useful to display (e.g., "Barbell"), show it as a secondary label under the exercise name.

**Validation**:
- Card shows exercise name and set count.
- Set rows show weight, reps, and PR badges.
- Warmup rows appear dimmed (0.45 opacity).
- Card is tappable.
- Styling matches design-system.md card pattern.

---

### Subtask T013 – Create CalendarWorkoutDetailView.swift

- **Purpose**: Container view for the workout detail section. Receives workout data for a selected date and renders `SummaryStatsStrip` + `CalendarExerciseCard` list.
- **File**: `Reppo/Features/Calendar/Views/CalendarWorkoutDetailView.swift` (new file)
- **Parallel?**: No — composes T011 and T012.

**Steps**:
1. Create the view:
   ```swift
   struct CalendarWorkoutDetailView: View {
       let workoutDetails: [WorkoutDetail]
       let selectedDate: Date
       let onExerciseTapped: (UUID) -> Void  // exerciseId
   }
   ```

2. **Layout**:
   ```swift
   var body: some View {
       if workoutDetails.isEmpty {
           emptyState
       } else {
           VStack(spacing: 16) {
               ForEach(workoutDetails, id: \.workout.id) { detail in
                   workoutSection(detail)
               }
           }
           .padding(.horizontal, 16)
           .padding(.vertical, 12)
       }
   }
   ```

3. **Workout section** (for each workout):
   ```swift
   @ViewBuilder
   private func workoutSection(_ detail: WorkoutDetail) -> some View {
       VStack(spacing: 12) {
           // Session label (only if multiple workouts on this date)
           if workoutDetails.count > 1 {
               sessionLabel(detail.workout)
           }

           // Summary stats
           SummaryStatsStrip(
               totalVolume: detail.totalVolume,
               exerciseCount: detail.exerciseCount,
               setCount: detail.setCount,
               duration: detail.workout.duration
           )

           // Exercise cards
           ForEach(detail.exerciseGroups, id: \.exercise.id) { group in
               CalendarExerciseCard(
                   exercise: group.exercise,
                   sets: group.sets,
                   stats: group.stats,
                   onTapped: { onExerciseTapped(group.exercise.id) }
               )
           }
       }
   }
   ```

4. **Empty state**: When no workouts exist for the selected date:
   ```swift
   @ViewBuilder
   private var emptyState: some View {
       VStack(spacing: 8) {
           Text("No workout")
               .font(.system(size: 15, weight: .medium))
               .foregroundStyle(Color.textTertiary)
       }
       .frame(maxWidth: .infinity)
       .padding(.top, 40)
   }
   ```

5. **Session label** (for multiple workouts per date): Derive from `startTime`:
   ```swift
   private func sessionLabel(_ workout: Workout) -> some View {
       let label: String = {
           guard let startTime = workout.startTime else { return "Session" }
           let hour = Calendar.current.component(.hour, from: startTime)
           if hour < 12 { return "Morning Session" }
           if hour < 17 { return "Afternoon Session" }
           return "Evening Session"
       }()

       return Text(label)
           .font(.system(size: 13, weight: .semibold))
           .foregroundStyle(Color.textSecondary)
           .frame(maxWidth: .infinity, alignment: .leading)
   }
   ```

**Validation**:
- Shows summary stats strip + exercise cards for a workout.
- Multiple workouts render with session labels and visual separation.
- Empty state shows when no workouts.
- `onExerciseTapped` is called when an exercise card is tapped.

---

### Subtask T014 – Implement Workout Detail Loading in CalendarViewModel

- **Purpose**: Implement the `selectDate()` method that fetches sets for the selected date's workouts, groups them by exercise, computes summary stats, and builds `WorkoutDetail` objects.
- **File**: `Reppo/Features/Calendar/ViewModels/CalendarViewModel.swift` (edit existing)
- **Parallel?**: No — core ViewModel logic.

**Steps**:
1. Implement `selectDate(_ date: Date)`:

   ```swift
   func selectDate(_ date: Date) async {
       let normalizedDate = Self.normalizeDate(date)
       selectedDate = normalizedDate

       guard let workouts = workoutsByDate[normalizedDate], !workouts.isEmpty else {
           workoutDetails = [:]
           return
       }

       isLoadingDetail = true
       defer { isLoadingDetail = false }

       do {
           var details: [UUID: WorkoutDetail] = [:]

           for workout in workouts {
               // 1. Fetch all sets for this workout
               let sets = try await setService.fetchSets(for: workout.id)

               // 2. Group sets by exerciseId
               var exerciseSetMap: [UUID: [WorkoutSet]] = [:]
               for set in sets {
                   exerciseSetMap[set.exerciseId, default: []].append(set)
               }

               // 3. Build exercise groups, ordered by first set's orderInWorkout
               var exerciseGroups: [ExerciseGroup] = []
               for (exerciseId, exerciseSets) in exerciseSetMap {
                   let exercise = try await cachedExercise(exerciseId)
                   guard let exercise else { continue }

                   let sortedSets = exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise }

                   // Fetch stats for this exercise (optional, for "best" display)
                   let stats = try? await statsService.fetchStats(for: exerciseId)

                   exerciseGroups.append(ExerciseGroup(
                       exercise: exercise,
                       sets: sortedSets,
                       stats: stats
                   ))
               }

               // Sort exercise groups by the minimum orderInWorkout of their sets
               exerciseGroups.sort { lhs, rhs in
                   let lhsOrder = lhs.sets.first?.orderInWorkout ?? Int.max
                   let rhsOrder = rhs.sets.first?.orderInWorkout ?? Int.max
                   return lhsOrder < rhsOrder
               }

               // 4. Compute summary stats
               let completedSets = sets.filter { $0.hasData }
               let totalVolume = completedSets.compactMap(\.volume).reduce(0, +)
               let uniqueExercises = Set(sets.map(\.exerciseId)).count

               details[workout.id] = WorkoutDetail(
                   workout: workout,
                   exerciseGroups: exerciseGroups,
                   totalVolume: totalVolume,
                   exerciseCount: uniqueExercises,
                   setCount: completedSets.count
               )
           }

           workoutDetails = details
       } catch {
           print("CalendarViewModel: Failed to load workout detail: \(error)")
       }
   }
   ```

2. **StatsService dependency** is already included in the ViewModel from WP01 (as `statsService: StatsServiceProtocol`). Use it directly via `self.statsService`.

3. **Expose sorted details** as a computed property for the view:
   ```swift
   var selectedDateWorkoutDetails: [WorkoutDetail] {
       guard let date = selectedDate,
             let workouts = workoutsByDate[date] else { return [] }
       return workouts.compactMap { workoutDetails[$0.id] }
   }
   ```

**Notes**:
- Volume uses `hasData` filter (per constitution — analytics use `hasData`, not `completed`).
- Volume = `effectiveWeight × reps` (via the `volume` computed property on `WorkoutSet`).
- `StatsService.fetchStats` may return nil for exercises with no stats yet — that's fine, `stats` is optional in `ExerciseGroup`.

**Validation**:
- Tapping a date populates `workoutDetails` correctly.
- Summary stats (volume, exercises, sets) are accurate.
- Exercise groups are ordered by their position in the workout.
- Sets within each group are ordered by `orderInExercise`.

---

### Subtask T015 – Implement Navigation to ExerciseDetailView

- **Purpose**: When user taps an exercise card in the workout detail, navigate (push) to `ExerciseDetailView` from feature 007.
- **File**: `Reppo/Features/Calendar/Views/CalendarView.swift` (edit — integrate NavigationStack destination)
- **Parallel?**: No — depends on T013.

**Steps**:
1. In `CalendarView`, update the detail section to pass the navigation callback:

   ```swift
   @ViewBuilder
   private var detailSection: some View {
       ScrollView {
           if let selectedDate = viewModel.selectedDate {
               CalendarWorkoutDetailView(
                   workoutDetails: viewModel.selectedDateWorkoutDetails,
                   selectedDate: selectedDate,
                   onExerciseTapped: { exerciseId in
                       navigationPath.append(exerciseId)
                   }
               )
           } else {
               // Instruction text when no date selected
               Text("Tap a date to see workout details")
                   .font(.system(size: 14))
                   .foregroundStyle(Color.textTertiary)
                   .padding(.top, 40)
                   .frame(maxWidth: .infinity)
           }
       }
   }
   ```

2. Add a `@State private var navigationPath = NavigationPath()` to CalendarView, and use it in the `NavigationStack`:
   ```swift
   NavigationStack(path: $navigationPath) {
       // ... existing content ...
       .navigationDestination(for: UUID.self) { exerciseId in
           ExerciseDetailView(exerciseId: exerciseId)
       }
   }
   ```

3. Check how `ExerciseDetailView` is initialized in the existing codebase. From feature 007:
   - It takes an `exerciseId: UUID` parameter.
   - It creates its own ViewModel internally.
   - It may need service dependencies injected — check its initializer.

4. If `ExerciseDetailView` needs services, they should be available via `@Environment` or the same injection pattern used in the Exercise feature.

**Notes**:
- The `NavigationStack` in CalendarView was added in WP01. Now we add the `.navigationDestination` for `UUID` type.
- If `ExerciseDetailView` uses a different navigation approach (e.g., a custom `NavigationDestination` type instead of raw `UUID`), match that pattern.

**Validation**:
- Tapping an exercise card pushes ExerciseDetailView.
- ExerciseDetailView loads correctly with the exercise data.
- Back button returns to the calendar with state preserved.

---

### Subtask T016 – Handle Multiple Workouts per Date

- **Purpose**: When a date has >1 workout, show all of them stacked in the detail area with session labels and visual separation.
- **File**: `CalendarWorkoutDetailView.swift` (already handles this) + `CalendarViewModel.swift` (verify grouping)
- **Parallel?**: No — builds on T013 and T014.

**Steps**:
1. **Verify ViewModel grouping**: In T014, `workoutsByDate` already groups workouts by date, and `selectDate()` processes all workouts for the selected date. Verify this handles the multi-workout case.

2. **CalendarWorkoutDetailView** already handles multiple workouts via `ForEach(workoutDetails, ...)` with session labels when `workoutDetails.count > 1` (implemented in T013).

3. **Add visual separator** between workouts when there are multiple:
   ```swift
   ForEach(Array(workoutDetails.enumerated()), id: \.element.workout.id) { index, detail in
       if index > 0 {
           Divider()
               .background(Color.border)
               .padding(.vertical, 8)
       }
       workoutSection(detail)
   }
   ```

4. **Verify dot merging**: In `CalendarViewModel.loadDotsForVisibleRange()` (T008), muscle groups from multiple workouts on the same date are merged into one array. Verify this produces unique muscle groups (no duplicates).

5. **Order workouts**: Sort multiple workouts by `startTime` (earliest first). If no `startTime`, sort by `createdAt`:
   ```swift
   // In selectedDateWorkoutDetails computed property:
   return workouts
       .compactMap { workoutDetails[$0.id] }
       .sorted { ($0.workout.startTime ?? $0.workout.createdAt) < ($1.workout.startTime ?? $1.workout.createdAt) }
   ```

**Validation**:
- Two workouts on the same date: both appear with session labels ("Morning Session", "Evening Session").
- Each workout has its own summary stats and exercise cards.
- Visual divider separates the workouts.
- Calendar dots merge muscle groups from both workouts.

---

### Subtask T017 – Handle Edge Cases

- **Purpose**: Handle remaining edge cases — empty state variants, long workout scrolling, and edge conditions.
- **File**: Various (CalendarView, CalendarWorkoutDetailView, CalendarDayCell)
- **Parallel?**: No — finishing touches.

**Steps**:
1. **No date selected (initial state)**: When `selectedDate == nil`, the detail section shows instruction text: "Tap a date to see workout details" in `textTertiary`. (Already handled in T015.)

2. **Date with no workout**: When user taps a date that has no workouts, show empty state: "No workout" text. (Already handled in T013 `emptyState`.)

3. **Date with workout but no sets with data**: A workout exists but all sets have `hasData == false`. Summary stats should show zeros. Exercise cards may be empty.
   - In T014, `completedSets.filter { $0.hasData }` handles this — count will be 0, volume will be 0.

4. **Long workout with many exercises**: The detail section is in a `ScrollView`, so it scrolls naturally. Verify this works with 8+ exercises.

5. **Exercise with no primaryMuscle**: If `exercise.primaryMuscle` is nil, no dot is added for that exercise. The dot array for a date may be shorter or empty even though workouts exist. This is acceptable.

6. **Bottom navigation visibility**: CalendarView is embedded in a `TabView` in `ContentView`. The tab bar is automatically visible. Verify this — if NavigationStack hides the tab bar on push, that's correct behavior (tab bar hides on `ExerciseDetailView` push, shows on calendar main view). Per constitution: "Bottom nav visible on tab screens, HIDDEN on focused screens."

7. **Loading states**: While `isLoadingDots` or `isLoadingDetail` is true, consider showing a subtle loading indicator (e.g., `ProgressView()` in the relevant section). Keep it minimal — no full-screen loaders.
   ```swift
   if viewModel.isLoadingDetail {
       ProgressView()
           .frame(maxWidth: .infinity)
           .padding(.top, 20)
   }
   ```

8. **Future scheduled sessions** (spec acceptance scenario 4): The spec mentions "blue outline" for scheduled future sessions. For v1, this likely means a future date with a programmed workout (from the Programs feature, which is placeholder-only). Since Programs is not implemented in v1, this scenario can be deferred. If needed, check for workouts with `status == .inProgress` on future dates and show a blue outline circle on the day number.

**Validation**:
- All edge cases handled gracefully — no crashes, no blank screens.
- Empty states show appropriate messages.
- Long workout detail scrolls properly.
- Tab bar visibility correct (visible on calendar, hidden on push to ExerciseDetail).

---

## Risks & Mitigations

- **ExerciseDetailView integration**: Already confirmed reusable from feature 007. Verify its initializer signature hasn't changed since the plan was written. Check `Reppo/Features/Exercise/Views/ExerciseDetailView.swift`.
- **Volume calculation accuracy**: Use `effectiveWeight × reps` via the `volume` computed property on `WorkoutSet`. This is the correct formula per constitution.
- **Unit conversion**: The constitution says "store metric, convert in UI." For v1, weight display should respect the user's unit preference. Check if `HealthProfile.unitPreference` is accessible via a service or environment. If not available yet, default to "kg" display.
- **StatsService injection**: Adding `StatsService` as a dependency to `CalendarViewModel` requires updating the view initialization chain (CalendarView → ContentView). Verify `ServiceContainer` exposes `StatsService`.
- **Performance**: Fetching sets for a workout on date tap is a single query per workout. With typical 1-2 workouts per date, this is fast. No performance concerns.

## Definition of Done Checklist

- [x] `SummaryStatsStrip.swift` shows volume, exercises, sets, optional duration
- [x] `CalendarExerciseCard.swift` shows exercise name, set rows, PR badges, warmup opacity
- [x] `CalendarWorkoutDetailView.swift` orchestrates stats + cards, handles empty state
- [x] `CalendarViewModel.selectDate()` fetches and groups data correctly
- [x] Tapping exercise card navigates to ExerciseDetailView
- [x] Multiple workouts on same date shown with session labels and dividers
- [x] Empty state (no workout) displays correctly
- [x] Loading state shown while fetching detail
- [x] Set rows are read-only (no editing)
- [x] PR badges use existing PRBadgeView component
- [x] Volume uses `hasData` filter and `effectiveWeight × reps`
- [x] Tab bar visible on calendar, hidden on ExerciseDetail push
- [x] App compiles without errors

## Review Guidance

- Verify that set rows are read-only — no buttons, no text fields, no editing gestures.
- Verify PR badges use `PRBadgeView` from the Workout feature — not a custom reimplementation.
- Verify volume calculation uses `hasData` filter (not `completed`).
- Verify SummaryStatsStrip styling matches design-system.md Section 6.2 "Summary Stat Card" pattern.
- Verify CalendarExerciseCard styling matches design-system.md "Exercise Card (Day View)" pattern.
- Test with a date that has 2 workouts — both should appear with session labels.
- Test tapping through to ExerciseDetailView and back — calendar state should be preserved.
- Verify StatsService was added to CalendarViewModel dependencies correctly.

## Activity Log

- 2026-02-27T09:26:46Z – system – lane=planned – Prompt created.
- 2026-02-27T10:55:00Z – claude-opus – lane=doing – Started implementation in worktree.
- 2026-02-27T11:00:00Z – claude-opus – lane=for_review – Implementation complete. Build succeeds.
- 2026-02-27T11:15:00Z – claude-opus – lane=done – Review passed: equipmentType.displayName, volume format, force-unwrap fix.
