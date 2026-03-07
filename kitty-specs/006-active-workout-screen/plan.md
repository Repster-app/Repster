# Implementation Plan: Active Workout Screen

**Branch**: `006-active-workout-screen` | **Date**: 2026-02-24 | **Spec**: `kitty-specs/006-active-workout-screen/spec.md`
**Input**: Feature specification from `kitty-specs/006-active-workout-screen/spec.md`

## Summary

Build the active workout screen — the core gym-time UI for set logging. A single focused screen (no bottom nav) with an exercise tab strip, adaptive set table, rest timer, and finish-workout summary sheet. Sets persist immediately on checkbox tap via SetService, PR badges render from cachedPRStatus, and the rest timer auto-starts from exercise.defaultRestTime.

**Prerequisites**: Features 001–005 are merged (SwiftData models, repositories, all six services, ServiceContainer).

## Technical Context

**Language/Version**: Swift (latest stable, Xcode 16+)
**Primary Dependencies**: SwiftUI, SwiftData (via services), Foundation
**Target Platform**: iOS 17.0+, iPhone only, dark mode only
**Architecture**: MVVM with Service + Repository layers per AGENT_RULES S2
**Testing**: Manual testing for v1. No automated tests.
**Performance Goals**: Set save pipeline < 100ms, scrolling 60 FPS, screen transitions < 200ms
**Constraints**: < 150MB memory during active workout. Standard iOS number pad (custom keyboard deferred to v1.1). No third-party UI libs.
**Scale/Scope**: Must remain responsive at 50,000+ sets.

**Key Decisions**:

| Decision | Choice | Source |
|----------|--------|--------|
| ViewModel structure | Single `ActiveWorkoutViewModel` (`@Observable`) owning all screen state | Constitution: thin VMs calling services. Screen is a single focused context. |
| Rest timer state | Lightweight `RestTimerState` value type managed by the VM | Timer is local UI concern, not business logic. |
| Set persistence | Immediate on checkbox tap via `SetService.save()` | specdoc S10, AGENT_RULES S7.3, FR-003 |
| PR badge rendering | Read `cachedPRStatus` from `SetSaveResult.prResult` | Write-time PR pipeline. Constitution: no read-time computation. |
| Tab strip reorder | Persist `orderInExercise` on WorkoutSet when exercises are reordered | screen_tree S3: drag to reorder exercises. |
| Column adaptation | Switch on `exercise.trackingType` to show Weight/Reps, Duration, Weight/Distance, etc. | AGENT_RULES S7.5, FR-002 |
| Workout resume | `workoutService.getActiveWorkout()` on app launch → navigate to active workout | AGENT_RULES S7.3 |
| Input keyboard | Standard iOS `.decimalPad` / `.numberPad` | FR-009, AGENT_RULES S7.6: custom keyboard deferred |
| Navigation | Full-screen cover or NavigationStack push with bottom nav hidden | Constitution: NavigationStack, no NavigationView. FR-001: no bottom nav. |
| DI | Services injected via SwiftUI `@Environment` | Constitution: manual DI via environment. |
| Summary sheet | `.sheet` presentation with workout stats computed from services | FR-008, screen_tree S3 |
| Sub-tabs (History/Charts) | Deferred — features 007/009 will provide reusable components | screen_tree shows sub-tabs but History/Charts are separate features |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| Architecture layers (Views→VMs→Services→Repos→SwiftData) | PASS | Views call ActiveWorkoutViewModel. VM calls WorkoutService, SetService, ExerciseService. No layer skipping. |
| Only repositories touch ModelContext | PASS | VM never accesses ModelContext. All data via service methods. |
| All weight in kg, distance in meters, duration in seconds | PASS | Internal storage unchanged. Unit conversion at UI boundary only (display labels). |
| WorkoutSet naming (not Set) | PASS | All references use `WorkoutSet`. |
| Integer grams for float comparison | N/A | PR comparison is in PRService (feature 003). UI only reads cachedPRStatus. |
| Database aggregation, not Swift iteration | PASS | Summary stats come from pre-computed ExerciseStats. No manual iteration over sets. |
| Write-time PR/stats updates | PASS | SetService.save() triggers pipeline. UI reads results. |
| No startup rebuild | PASS | getActiveWorkout() is single-row fetch. No rebuild. |
| Hard delete only | PASS | Set deletion via SetService.delete(). No soft delete. |
| effectiveWeight never retroactively recalculated | N/A | Set creation uses SetService which handles effectiveWeight. VM doesn't compute it. |
| Sets persist immediately (FR-003) | PASS | Checkbox tap → SetService.save(). Not batched to "Finish". |
| Do NOT invent fields/tables/enums | PASS | All models exist from features 001–005. No new schema. |
| Prefer async/await | PASS | All service calls are async. VM uses Task {} for async work. |
| No third-party deps | PASS | Pure SwiftUI + Foundation. |
| @Observable for ViewModels | PASS | ActiveWorkoutViewModel uses @Observable macro. |
| NavigationStack (not NavigationView) | PASS | Navigation uses NavigationStack. |
| Minimum tap target 44×44pt | PASS | Checkbox 26×26 but tap area expanded to 44×44. All buttons ≥ 44pt. |
| Memory management | PASS | Only current workout's sets in memory. No global set cache. |

**Post-Phase-1 re-check**: All principles pass. No constitution violations.

## Project Structure

### Documentation (this feature)

```
kitty-specs/006-active-workout-screen/
├── spec.md              # Feature specification
├── meta.json            # Feature metadata
├── plan.md              # This file
├── research.md          # Phase 0: Research findings
├── data-model.md        # Phase 1: View-layer entity mapping
├── contracts/           # Phase 1: ViewModel protocol
│   └── ActiveWorkoutViewModelContract.swift
└── tasks/               # Generated by /spec-kitty.tasks (NOT created here)
```

### Source Code (repository root)

```
Reppo/Features/Workout/
├── Views/
│   ├── ActiveWorkoutView.swift           # Main focused screen
│   ├── ExerciseTabStripView.swift        # Horizontal scrollable tabs
│   ├── SetTableView.swift                # Adaptive set table grid
│   ├── SetRowView.swift                  # Single set row (input fields, badge, checkbox)
│   ├── RestTimerView.swift               # Countdown timer overlay/bar
│   ├── WorkoutSummarySheet.swift         # Finish workout summary
│   └── Components/
│       ├── SetInputField.swift           # Reusable numeric input (weight/reps/duration)
│       ├── PRBadgeView.swift             # Gold PR badge / blue match badge
│       ├── SetNumberBadge.swift          # Set # / warmup "W" / completed checkmark
│       └── CompletionCheckbox.swift      # 26×26 checkbox with expanded tap area
└── ViewModels/
    └── ActiveWorkoutViewModel.swift      # @Observable VM owning all screen state
```

**Existing files touched (minimal)**:
- `Reppo/App/ContentView.swift` — Add navigation to active workout (or placeholder until tab nav feature)

**Structure Decision**: Files placed under `Features/Workout/` per constitution file organization. Views decomposed by component for readability — each is a focused SwiftUI view. Single ViewModel per the engineering alignment.

## Phase 0: Research

Research findings consolidated in `kitty-specs/006-active-workout-screen/research.md`.

### Key Findings

| Topic | Decision | Rationale |
|-------|----------|-----------|
| ViewModel pattern | Single `@Observable` class, not actor | ViewModels must be MainActor-bound for SwiftUI. Services are actors — VM calls them with `await`. |
| Rest timer implementation | `Timer.publish` + `@MainActor` state | Standard SwiftUI timer pattern. No background notifications for v1 — timer is visual only. |
| Tab strip drag reorder | SwiftUI `.onMove` or custom `DragGesture` | Native List supports onMove; for horizontal strip, custom drag gesture with `MoveAnimation`. |
| Set table input UX | Tap field → iOS number pad, no pre-fill from previous set for v1 | FR-009: standard number pad. Pre-fill is UX polish, not in spec. |
| Exercise ordering persistence | Store exercise order as array of exerciseIds on the ViewModel; persist via set `orderInExercise` | No separate "exercise order" model needed. Order derived from sets. |
| Workout resume on app launch | Check `workoutService.getActiveWorkout()` in app root | AGENT_RULES S7.3. Navigate directly if inProgress workout found. |
| Finish workout stats | Read from ExerciseStats (pre-computed) + count sets in current workout | No manual aggregation. Constitution: use pre-computed stats. |
| Sub-tabs (History/Charts) | Stub/defer to features 007 and 009 | screen_tree shows sub-tabs but those are separate feature scopes. |

## Phase 1: Design & Contracts

### ActiveWorkoutViewModel — Core State

```swift
@Observable
@MainActor
final class ActiveWorkoutViewModel {
    // MARK: - Dependencies (injected)
    private let workoutService: any WorkoutServiceProtocol
    private let setService: any SetServiceProtocol
    private let exerciseService: any ExerciseServiceProtocol

    // MARK: - Workout State
    var workout: Workout?
    var exercises: [Exercise] = []           // Ordered list of exercises in this workout
    var selectedExerciseIndex: Int = 0       // Active tab
    var setsByExercise: [UUID: [WorkoutSet]] = [:]  // exerciseId → sets

    // MARK: - UI State
    var isLoading: Bool = false
    var showFinishSheet: Bool = false
    var showAddExerciseSheet: Bool = false
    var restTimer: RestTimerState = .idle
    var elapsedTime: TimeInterval = 0        // Since workout.startTime

    // MARK: - Computed
    var currentExercise: Exercise? { ... }
    var currentSets: [WorkoutSet] { ... }
    var workoutDuration: String { ... }      // Formatted elapsed time
}
```

### RestTimerState

```swift
enum RestTimerState: Equatable {
    case idle
    case running(remaining: Int, total: Int)  // seconds
    case finished
}
```

### Key Methods

```swift
// MARK: - Lifecycle
func loadActiveWorkout() async                  // Fetch or create workout + exercises + sets
func resumeWorkout(_ workoutId: UUID) async     // Resume from app relaunch

// MARK: - Set Operations
func completeSet(_ set: WorkoutSet, weight: Double?, reps: Int?, duration: Int?) async
    // → SetService.save() → update cachedPRStatus in local state → start rest timer
func addSet(for exerciseId: UUID) async         // Create new working set
func addWarmupSet(for exerciseId: UUID) async   // Create new warmup set
func deleteSet(_ set: WorkoutSet) async         // → SetService.delete()
func changeSetType(_ set: WorkoutSet, to type: SetType) async

// MARK: - Exercise Operations
func addExercises(_ exerciseIds: [UUID]) async  // From exercise picker sheet
func removeExercise(at index: Int) async        // Long-press delete (with confirmation in View)
func reorderExercises(from: IndexSet, to: Int)  // Tab drag reorder

// MARK: - Timer
func startRestTimer(duration: Int)              // Auto-called after set completion
func addTime(_ seconds: Int)                    // +30s button
func dismissTimer()                             // Manual dismiss

// MARK: - Finish
func finishWorkout(notes: String?, rpe: Double?) async
    // → WorkoutService.finishWorkout() → navigate to Calendar
```

### View Decomposition

```
ActiveWorkoutView
├── VStack
│   ├── Header Bar
│   │   ├── Back button (dismiss)
│   │   ├── Elapsed timer (live updating)
│   │   ├── [+ Exercise] button
│   │   └── [Finish Workout] button
│   │
│   ├── ExerciseTabStripView
│   │   ├── ScrollView(.horizontal)
│   │   │   └── ForEach exercises → tab button
│   │   ├── Long-press → .contextMenu { Delete Exercise }
│   │   └── Drag gesture for reorder
│   │
│   ├── SetTableView (for currentExercise)
│   │   ├── Header row (column labels adapted to trackingType)
│   │   ├── ForEach currentSets → SetRowView
│   │   │   ├── SetNumberBadge (number / "W" / green check)
│   │   │   ├── SetInputField(s) (weight, reps, duration — per trackingType)
│   │   │   ├── PRBadgeView (gold PR / blue = / empty)
│   │   │   └── CompletionCheckbox
│   │   ├── [+ Add Set] button
│   │   └── [+ Add Warmup] button
│   │
│   └── RestTimerView (overlay or inline, shown when timer running)
│       ├── Circular/linear countdown
│       ├── Time remaining label
│       ├── [+30s] button
│       └── [Dismiss] button
│
├── .sheet(isPresented: $showAddExerciseSheet)
│   └── Exercise picker (feature 007 provides this; stub for now)
│
└── .sheet(isPresented: $showFinishSheet)
    └── WorkoutSummarySheet
        ├── Date + duration
        ├── Total volume + total sets
        ├── Exercise list (set counts, best lift each)
        ├── PRs highlighted
        ├── Notes text field → Workout.notes
        ├── RPE selector (1–10) → Workout.perceivedEffort
        └── [Save & Close] → finishWorkout()
```

### Set Table Column Adaptation (AGENT_RULES S7.5)

```swift
func columnsForTrackingType(_ type: TrackingType) -> [SetTableColumn] {
    var columns: [SetTableColumn] = [.setNumber]  // Always

    switch type {
    case .weightReps:
        columns += [.weight, .reps]
    case .duration:
        columns += [.duration]
    case .weightDistance:
        columns += [.weight, .distance]
    case .weightRepsDuration:
        columns += [.weight, .reps, .duration]
    case .custom:
        columns += [.weight, .reps]  // Fallback
    }

    columns += [.prBadge, .checkbox]  // Always
    return columns
}
```

### Design Token Usage

| Component | Token | Value |
|-----------|-------|-------|
| Screen background | `bg` | #111113 |
| Set table container | `bgCard` | #1B1B1F |
| Input field background | `bgInput` | #1F1F25 |
| Input field border | `border` | white 6% opacity |
| Input focused border | `blue` | #5B8DEF |
| Completed row tint | `green` 6% opacity | #5EC269 at 6% |
| Warmup row opacity | 0.5 | Per design-system 6.3 |
| Set number badge bg | `bgSubtle` | #262630 |
| PR badge bg | `goldSoft` | gold at 10% opacity |
| PR badge text | `gold` | #D4A23A |
| Match badge bg | `blueSoft` | blue at 10% opacity |
| Checkbox checked fill | `blue` | #5B8DEF |
| Tab active bg | `blue` | #5B8DEF with white text |
| Tab inactive bg | `bgCard` | #1B1B1F with `textDim` text |
| Row height | 52pt | Per design-system 6.3 |
| Row divider | 1px white 3% | Per design-system 6.3 |
| Screen padding | 20pt horizontal | Per design-system S4 |

### Data Flow

```
User taps checkbox
    → ActiveWorkoutViewModel.completeSet()
        → SetService.save(set)              // Persists + computes effectiveWeight
            → PRService.evaluate()           // Updates cachedPRStatus
            → StatsService.updateStats()     // Updates ExerciseStats
        ← SetSaveResult { setId, effectiveWeight, prResult }
        → Update local set state with new cachedPRStatus
        → Start rest timer (exercise.defaultRestTime)
    → View re-renders: green row, PR badge if earned

User taps "Finish Workout"
    → showFinishSheet = true
    → WorkoutSummarySheet displayed
        → User enters notes + RPE
        → Taps "Save & Close"
    → ActiveWorkoutViewModel.finishWorkout()
        → WorkoutService.finishWorkout(workoutId)  // status=completed, endTime set
        → Navigate to Calendar tab
```

## Complexity Tracking

| Risk | Severity | Mitigation |
|------|----------|------------|
| Tab strip drag reorder in horizontal ScrollView | Medium | Use custom DragGesture with animation. Fall back to simple long-press reorder menu if gesture conflicts arise. |
| Rest timer accuracy when app backgrounded | Low | Timer is visual-only for v1. No local notifications. If app returns from background, recalculate remaining from timestamps. |
| Set table performance with many sets | Low | Typical workout has 20-40 sets across exercises. LazyVStack for scrolling. No performance concern at this scale. |
| Exercise picker sheet (feature 007 dependency) | Medium | Stub the exercise picker for v1 of this feature. Feature 007 will provide the real component. |
| Elapsed timer live updates | Low | Use `TimelineView` or `Timer.publish` every second. Minimal overhead. |
| Summary sheet stats computation | Low | ExerciseStats is pre-computed. Count current workout's sets from local state. No heavy computation. |

No constitution violations. All decisions traceable to specdoc, AGENT_RULES, design-system, and screen_tree.
