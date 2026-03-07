# Research: Active Workout Screen (006)

**Date**: 2026-02-24
**Feature**: 006-active-workout-screen

## Research Topics

### 1. ViewModel Threading Model

**Decision**: `@Observable @MainActor final class` (not actor)

**Rationale**: SwiftUI views run on MainActor. ViewModels that publish state to views must also be MainActor-isolated. Services (SetService, WorkoutService, etc.) are plain `actor` types — the VM calls them with `await` from `Task {}` blocks. This matches the standard SwiftUI + Observation pattern for iOS 17+.

**Alternatives considered**:
- Swift `actor` for VM: Rejected — would require `@MainActor` annotations on every published property anyway, defeating the purpose.
- `ObservableObject` with `@Published`: Rejected — constitution requires `@Observable` (iOS 17+).

### 2. Rest Timer Implementation

**Decision**: `Timer.publish(every: 1, on: .main, in: .common)` driving a `RestTimerState` enum.

**Rationale**: Standard SwiftUI timer pattern. The timer is purely visual — it does not persist or trigger any service calls. When the user completes a set, the VM starts a countdown from `exercise.defaultRestTime`. If the app is backgrounded and returns, the remaining time is recalculated from `Date()` vs the timer start time.

**Alternatives considered**:
- `TimelineView(.periodic(every: 1))`: Viable but slightly more complex for countdown-style timers. Better for clocks/animations.
- Background `UNNotification`: Out of scope for v1. Timer is visual-only.
- `DispatchSourceTimer`: Lower-level than needed. `Timer.publish` integrates cleanly with Combine/SwiftUI.

### 3. Exercise Tab Strip — Drag Reorder

**Decision**: Custom horizontal `ScrollView` with `DragGesture` for reorder.

**Rationale**: SwiftUI's built-in `.onMove` modifier only works with `List`/`ForEach` in vertical layout. For a horizontal tab strip, a custom `DragGesture` with calculated drop positions is needed. The gesture updates the exercises array order, which persists to `orderInExercise` on the sets.

**Alternatives considered**:
- `List` with `.onMove`: Only supports vertical layout. Not suitable for horizontal tab strip.
- Simple long-press context menu with "Move Left"/"Move Right": Simpler but less intuitive. Spec explicitly says "drag a tab" for reorder.
- Third-party reorder library: Rejected per constitution (no third-party UI libs).

### 4. Set Table Input Fields

**Decision**: Standard `TextField` with `.keyboardType(.decimalPad)` for weight, `.keyboardType(.numberPad)` for reps/duration.

**Rationale**: FR-009 explicitly states "Standard iOS number pad for v1." Custom keyboard is deferred to v1.1 (AGENT_RULES S7.6). No pre-fill from previous sets — not in spec.

**Alternatives considered**:
- Custom numeric keyboard: Explicitly deferred to v1.1.
- Stepper controls: Less efficient for gym use where users need to type specific numbers.

### 5. Exercise Order Persistence

**Decision**: Maintain an ordered array of exercise UUIDs in the ViewModel. When exercises are reordered, update `orderInExercise` on all affected sets.

**Rationale**: There is no separate "workout-exercise order" table in the schema. The `orderInExercise` field on `WorkoutSet` implicitly captures order. When adding a new exercise, assign the next order index. When reordering tabs, update the order on all sets for the affected exercises.

**Alternatives considered**:
- Separate junction table (WorkoutExercise): Not in the specdoc schema. Constitution says "Do NOT invent fields/tables."
- Order derived from first set timestamp: Fragile — doesn't support manual reorder.

### 6. Workout Resume on App Launch

**Decision**: Call `workoutService.getActiveWorkout()` at app launch. If an inProgress workout exists, navigate directly to ActiveWorkoutView.

**Rationale**: AGENT_RULES S7.3 explicitly states this behavior. The check is a single-row fetch (no performance concern). Navigation handled at the ContentView/root level.

**Alternatives considered**:
- Deep link / state restoration: Over-engineered for this case. Simple fetch + navigate is sufficient.

### 7. Finish Workout Summary Stats

**Decision**: Read pre-computed `ExerciseStats` for totals. Count sets from local ViewModel state (already loaded). Compute workout-specific stats (total volume, set count, PRs) from the in-memory sets.

**Rationale**: Constitution prohibits loading all sets to compute totals. However, the current workout's sets are already in memory (typically 20-40 sets). Counting them is safe and efficient. For historical exercise-level stats, use ExerciseStats.

**Alternatives considered**:
- Fetch aggregated stats from repository: Unnecessary — current workout sets are already loaded.
- Pre-compute workout summary in service layer: Over-engineering — the data is already available.

### 8. Sub-tabs (History / Charts)

**Decision**: Defer to features 007 (Exercise List & Detail) and 009 (Charts Tab). Show only the "Sets" tab for this feature.

**Rationale**: The screen_tree shows History and Charts sub-tabs within each exercise, but these are reusable components from other features. Feature 006 focuses on set entry — the core interaction loop. Sub-tab stubs can be added but will be empty until their features ship.

### 9. Exercise Picker Sheet

**Decision**: Stub the exercise picker sheet for this feature. Feature 007 will provide the full Exercise List component.

**Rationale**: The active workout screen needs an "[+Exercise]" button that opens the exercise list in selection mode. However, the exercise list UI is feature 007's scope. For feature 006, provide a minimal stub or temporary list that allows selecting from existing exercises.

**Approach**: Create a simple `ExercisePickerSheet` that fetches exercises via `ExerciseService.fetchAllExercises()` and displays them in a searchable list. Feature 007 will replace this with the full-featured component.
