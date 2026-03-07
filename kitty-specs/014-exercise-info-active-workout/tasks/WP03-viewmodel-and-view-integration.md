---
work_package_id: WP03
title: Integration — ViewModel & View Wiring
lane: "done"
dependencies:
- WP01
subtasks:
- T008
- T009
- T010
- T011
phase: Phase 2 - Integration
assignee: "claude-opus"
agent: "claude-opus"
shell_pid: "79213"
review_status: "approved"
reviewed_by: "claude-opus"
history:
- timestamp: '2026-03-01T19:53:31Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
- timestamp: '2026-03-01T20:18:05Z'
  lane: doing
  agent: claude-opus
  shell_pid: '79213'
  action: Started implementation via workflow command
- timestamp: '2026-03-01T20:43:27Z'
  lane: for_review
  agent: claude-opus
  shell_pid: '79213'
  action: Ready for review
- timestamp: '2026-03-01T20:44:57Z'
  lane: done
  agent: claude-opus
  shell_pid: '79213'
  action: Review passed
---

# Work Package Prompt: WP03 – Integration — ViewModel & View Wiring

## Implementation Command

```bash
spec-kitty implement WP03 --base WP02
```

## Objectives & Success Criteria

- Wire `ExerciseInfoProvider` into `ActiveWorkoutViewModel` with caching and loading state
- Insert `ExerciseInfoSectionView` into `ActiveWorkoutView`'s `.sets` sub-tab
- Ensure Exercise Info reloads reactively when sets are completed, edited, or deleted
- **Success**: Start a workout, complete 2 sets, scroll below set table → Exercise Info appears with correct e1RM, last workout, and estimate. Switch exercises → data updates. Complete another set → e1RM "Best today" updates.

## Context & Constraints

**Plan**: `kitty-specs/014-exercise-info-active-workout/plan.md` — engineering alignment table.
**Research R4**: Insertion point is AFTER `SetTableView` in the `.sets` sub-tab ScrollView, NOT inside `SetTableView`.
**Research R5**: Caching pattern: `exerciseInfoLoadedForExerciseId` mirrors existing `historyLoadedForExerciseId`.
**Constitution**: Views call ViewModels only. ViewModels call Services. `@Observable` pattern. `async/await`.

**Key files to read before implementing**:
- `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` — understand existing properties, methods, caching pattern
- `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` — understand .sets sub-tab layout, ScrollView structure
- `Reppo/Features/Workout/Views/SetTableView.swift` — understand where the set table ends (reference only)

## Subtasks & Detailed Guidance

### Subtask T008 – Add ViewModel Properties and Caching

- **Purpose**: Add the properties needed to store Exercise Info data, loading state, and cache tracking. Extend the existing cache clearing mechanism.
- **File**: `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` (MODIFY)
- **Parallel?**: No — must be done before T009.

**Steps**:

1. **Read the existing file** first. Understand the property layout, especially:
   - `subTabHistory: [WorkoutHistoryGroup]`
   - `subTabChartData: ExerciseChartData?`
   - `private var historyLoadedForExerciseId: UUID?`
   - `private var chartsLoadedForExerciseId: UUID?`
   - `func clearSubTabCache()`

2. **Add new properties** alongside the existing sub-tab state:
   ```swift
   // Exercise Info state
   var exerciseInfoData: ExerciseInfoData?
   var isLoadingExerciseInfo: Bool = false
   private var exerciseInfoLoadedForExerciseId: UUID?
   ```

3. **Extend `clearSubTabCache()`** to also clear exercise info:
   ```swift
   func clearSubTabCache() {
       subTabHistory = []
       subTabChartData = nil
       historyLoadedForExerciseId = nil
       chartsLoadedForExerciseId = nil
       // Add these lines:
       exerciseInfoData = nil
       exerciseInfoLoadedForExerciseId = nil
   }
   ```
   This ensures exercise info is cleared when the user switches exercises via the tab strip.

**Validation**:
- [ ] `exerciseInfoData` property exists as `ExerciseInfoData?`
- [ ] `isLoadingExerciseInfo` property exists as `Bool`
- [ ] `clearSubTabCache()` resets exercise info state
- [ ] Property names follow existing naming pattern

---

### Subtask T009 – Add loadExerciseInfo() Method

- **Purpose**: Implement the async method that delegates to `ExerciseInfoProvider.compute()`, handles errors, and manages cache state.
- **File**: `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` (MODIFY)
- **Parallel?**: No — depends on T008 properties.

**Steps**:

1. **Add the method** near the existing `loadHistoryForCurrentExercise()` and `loadChartsForCurrentExercise()`:

   ```swift
   func loadExerciseInfo() async {
       guard let exercise = currentExercise,
             let workout = workout else { return }

       // Cache check — don't re-fetch if already loaded for this exercise
       if exerciseInfoLoadedForExerciseId == exercise.id {
           return
       }

       isLoadingExerciseInfo = true
       defer { isLoadingExerciseInfo = false }

       do {
           let data = try await ExerciseInfoProvider.compute(
               currentSets: currentSets,
               exerciseId: exercise.id,
               currentWorkoutId: workout.id,
               trackingType: exercise.trackingType,
               weightIncrement: exercise.weightIncrement,
               setService: setService,
               statsService: statsService,
               healthProfileRepo: healthProfileRepo
           )
           exerciseInfoData = data
           exerciseInfoLoadedForExerciseId = exercise.id
       } catch {
           // Graceful degradation — show empty state on error
           exerciseInfoData = nil
           exerciseInfoLoadedForExerciseId = exercise.id
           print("ExerciseInfo load failed: \(error)")
       }
   }
   ```

2. **Verify service dependencies**: The ViewModel already has `setService`, `statsService` injected. You may need to add `healthProfileRepo` if it's not already available. Check the ViewModel's initializer.

   If `healthProfileRepo` is NOT already injected:
   - Add it to the init: `let healthProfileRepo: HealthProfileRepository`
   - Pass it from wherever the ViewModel is created (likely `ActiveWorkoutView` or a coordinator)
   - Check how other ViewModels in the codebase access `HealthProfileRepository`

3. **Alternative if HealthProfile is accessed differently**: The existing codebase may access HealthProfile through a `SettingsService` or environment. Match the existing pattern. Search for `healthProfileRepo` or `HealthProfileRepository` usage in other ViewModels to find the correct injection approach.

**Validation**:
- [ ] Cache check prevents redundant fetches
- [ ] Loading state (`isLoadingExerciseInfo`) set correctly with `defer`
- [ ] Error handling gracefully shows empty state (no crashes)
- [ ] Method follows `async/await` pattern (no completion handlers)
- [ ] All needed services are properly injected

---

### Subtask T010 – Insert ExerciseInfoSectionView in ActiveWorkoutView

- **Purpose**: Wire the Exercise Info section into the active workout screen's `.sets` sub-tab, after the set table, inside the existing ScrollView.
- **File**: `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` (MODIFY)
- **Parallel?**: No — depends on T008 and T009.

**Steps**:

1. **Read the existing file** and locate the `.sets` case in the sub-tab switch statement. It should look approximately like:
   ```swift
   case .sets:
       ScrollView {
           SetTableView(viewModel: viewModel)
               .padding(.horizontal, 20)
               .padding(.top, 8)
       }
   ```

2. **Insert ExerciseInfoSectionView** after `SetTableView`, inside the same `ScrollView`:
   ```swift
   case .sets:
       ScrollView {
           SetTableView(viewModel: viewModel)
               .padding(.horizontal, 20)
               .padding(.top, 8)

           // Exercise Info section (FR-001)
           ExerciseInfoSectionView(
               data: viewModel.exerciseInfoData,
               unitPreference: unitPreference,  // See note below
               isLoading: viewModel.isLoadingExerciseInfo
           )
           .padding(.horizontal, 20)
           .padding(.top, 16)
           .padding(.bottom, 20)
       }
   ```

3. **Trigger loading**: Add a `.task` modifier (or `.onChange`) to load exercise info when the exercise changes or when the `.sets` tab is shown:
   ```swift
   // Option A: .task with id (re-triggers when exercise changes)
   .task(id: viewModel.currentExercise?.id) {
       await viewModel.loadExerciseInfo()
   }
   ```
   Place this on the `ScrollView` or on the `ExerciseInfoSectionView` — whichever is more appropriate given the existing code structure.

4. **Obtain unitPreference**: Check how the existing view accesses user preferences. Options:
   - If HealthProfile is already read in the view or passed as a binding → use it directly.
   - If not available, you may need to pass it through from the ViewModel: add a `unitPreference: UnitPreference` computed property to the ViewModel that reads from HealthProfile.
   - Check existing views like the set table or chart views to see how they handle unit display.

5. **Verify scroll behavior**: After insertion, the user should be able to scroll naturally from the set table → Add buttons → Exercise Info section. The section should not be clipped or overlapping.

**Important**: Do NOT insert `ExerciseInfoSectionView` inside `SetTableView.swift`. It goes in `ActiveWorkoutView.swift`, inside the same `ScrollView` that wraps `SetTableView`. This maintains separation of concerns.

**Validation**:
- [ ] Exercise Info section appears below set table and Add buttons in `.sets` sub-tab
- [ ] Section is NOT visible in `.history` or `.charts` sub-tabs
- [ ] `loadExerciseInfo()` triggers on initial load and exercise switch
- [ ] Horizontal padding matches SetTableView (20pt)
- [ ] Scrolling works smoothly through the entire content

---

### Subtask T011 – Add Reactivity on Set Changes

- **Purpose**: When the user completes, edits, or deletes a set during the active workout, the Exercise Info should update to reflect the new data (e.g., "Best today" e1RM changes after a heavier set).
- **File**: `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` (MODIFY)
- **Parallel?**: No — depends on T008/T009 existing.

**Steps**:

1. **Locate `completeSet()`**: This is the method called when the user marks a set as done. After the set is saved and the PR pipeline runs, the Exercise Info data may be stale.

   Add cache invalidation at the end of the method (after local state updates):
   ```swift
   // Invalidate exercise info cache so it reloads with new data
   exerciseInfoLoadedForExerciseId = nil
   ```

2. **Locate `editSet()` or equivalent**: If there's a method for editing a completed set's weight/reps. Add the same invalidation:
   ```swift
   exerciseInfoLoadedForExerciseId = nil
   ```

3. **Locate `deleteSet()`**: Add the same invalidation after the set is removed:
   ```swift
   exerciseInfoLoadedForExerciseId = nil
   ```

4. **Trigger reload**: The view's `.task(id:)` modifier may not re-trigger on cache invalidation alone (since `currentExercise?.id` hasn't changed). Two options:

   **Option A (Preferred)**: After invalidation, immediately call `loadExerciseInfo()`:
   ```swift
   exerciseInfoLoadedForExerciseId = nil
   await loadExerciseInfo()
   ```

   **Option B**: Use an additional `.onChange` in the view that watches `exerciseInfoData` or a trigger counter. This is more complex.

   Choose the approach that best fits the existing code patterns. Option A is simpler and directly mirrors how the ViewModel works.

5. **Debounce consideration**: If the user rapidly completes multiple sets, each completion would trigger a reload. Since the fetch is a single DB query (< 200ms), this is acceptable. No debouncing needed.

6. **Also handle `addSet()` and `addWarmupSet()`**: These don't need invalidation because adding an empty set doesn't change any Exercise Info metrics (no `hasData` yet). Only when a set is *completed* with actual values does the data change.

**Validation**:
- [ ] Complete a set → e1RM "Best today" updates if the new set has a higher e1RM
- [ ] Delete a set → e1RM recalculates without the deleted set
- [ ] Edit a set's weight → Exercise Info reflects the change
- [ ] No infinite loop: invalidation → reload → no re-invalidation (cache is set after reload)
- [ ] Rapid set completions don't cause crashes or visual glitches

## Risks & Mitigations

- **Risk**: `healthProfileRepo` not already injected in ViewModel → **Mitigation**: Check existing DI pattern; may need to add it to init or use environment injection.
- **Risk**: `.task` modifier doesn't re-trigger when cache is invalidated → **Mitigation**: Directly call `loadExerciseInfo()` after invalidation in the ViewModel methods.
- **Risk**: Loading blocks UI thread → **Mitigation**: `loadExerciseInfo()` is `async` and runs off the main actor for the DB fetch. `@MainActor` ViewModel updates happen on return.
- **Risk**: Merge conflicts with existing ActiveWorkoutView/ViewModel changes → **Mitigation**: This WP depends on WP01 + WP02 being merged first. Only add to existing files; don't refactor existing code.

## Definition of Done Checklist

- [ ] `exerciseInfoData` property on ViewModel populated correctly
- [ ] Cache pattern works: data persists on same exercise, clears on switch
- [ ] `ExerciseInfoSectionView` visible in `.sets` sub-tab, hidden in other sub-tabs
- [ ] Loading triggers on initial exercise display and on exercise switch
- [ ] Completing a set invalidates cache and reloads Exercise Info
- [ ] Deleting a set invalidates cache and reloads Exercise Info
- [ ] No infinite reload loops
- [ ] 60 FPS maintained while scrolling through section (SC-005)
- [ ] Exercise Info loads within 500ms of exercise selection (SC-001)

## Review Guidance

- Verify `ExerciseInfoSectionView` is in `ActiveWorkoutView.swift`, NOT in `SetTableView.swift`.
- Verify cache invalidation happens in `completeSet()`, `deleteSet()`, and any `editSet()` method.
- Verify `.task` or equivalent triggers `loadExerciseInfo()` correctly.
- Check that `healthProfileRepo` (or equivalent) is properly injected — no force unwraps or missing dependencies.
- Test exercise switching: data should clear and reload for the new exercise.
- Test empty state: new exercise with no history should show graceful empty.

## Activity Log

- 2026-03-01T19:53:31Z – system – lane=planned – Prompt created.
- 2026-03-01T20:18:05Z – claude_opus –shell_pid=79213 – lane=doing – Started implementation via workflow command
- 2026-03-01T20:43:27Z – claude_opus –shell_pid=79213 – lane=for_review – Ready for review: ViewModel integration with ExerciseInfoProvider (caching, loading, unit preference), ExerciseInfoSectionView inserted in .sets sub-tab, reactive cache invalidation in completeSet/deleteSet/changeSetType, Xcode project refs added. Build clean.
- 2026-03-01T20:44:57Z – claude_opus –shell_pid=79213 – lane=done – Review passed: ExerciseInfoSectionView correctly placed in ActiveWorkoutView (not SetTableView), cache invalidation in completeSet/deleteSet/changeSetType, .task(id:) trigger, healthProfileRepo properly injected. Build clean.
