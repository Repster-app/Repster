# Implementation Plan: Edit Historic Workout

**Branch**: `015-edit-historic-workout` | **Date**: 2026-03-02 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/kitty-specs/015-edit-historic-workout/spec.md`

## Summary

Enable editing of completed workouts from the workout detail screen. Tapping the existing "Edit Workout" toolbar menu item opens a full-screen edit view that reuses the active workout's set entry components via a shared protocol. Users can edit set values, add/delete sets, add/remove exercises, and edit workout notes. All changes persist immediately using the existing SetService pipeline. Requires protocol-based decoupling of SetTableView and ExerciseTabStripView.

## Technical Context

**Language/Version**: Swift (latest stable), iOS 17.0+
**Primary Dependencies**: SwiftUI, SwiftData
**Storage**: SwiftData (on-device)
**Testing**: Manual testing for v1 (per constitution)
**Target Platform**: iOS 17.0+, iPhone only
**Project Type**: Mobile (single platform)
**Performance Goals**: Set save pipeline < 100ms (SC-002), edit screen load < 1s (SC-001)
**Constraints**: Dark mode only, no cloud sync, no automated tests
**Scale/Scope**: Single workout edit at a time, up to ~50 exercises/500 sets per workout

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| MVVM with Service/Repository layers | PASS | EditWorkoutViewModel → Services → Repositories |
| Views call ViewModels only | PASS | EditWorkoutView calls EditWorkoutViewModel only |
| ViewModels call Services only | PASS | Uses SetService, WorkoutService, ExerciseService |
| @Observable for ViewModels | PASS | @Observable @MainActor pattern |
| No layer skipping | PASS | Protocol decoupling preserves layer boundaries |
| No new schema inventions | PASS | No new entities; one new method on WorkoutServiceProtocol |
| Sets persist immediately | PASS | FR-004 aligns with constitution principle |
| Write-time PR computation | PASS | Uses existing SetService.edit() pipeline |
| effectiveWeight at save time | PASS | SetService.edit() recomputes effectiveWeight |
| No startup rebuild | PASS | No new startup work |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```
kitty-specs/015-edit-historic-workout/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── view-contracts.md
└── tasks.md             # Phase 2 output (NOT created here)
```

### Source Code (repository root)

```
Reppo/
├── Features/
│   ├── Workout/
│   │   ├── Protocols/
│   │   │   └── SetTableDataSource.swift        # NEW
│   │   ├── ViewModels/
│   │   │   ├── ActiveWorkoutViewModel.swift     # MODIFY (conform to protocol)
│   │   │   └── EditWorkoutViewModel.swift       # NEW
│   │   └── Views/
│   │       ├── ActiveWorkoutView.swift          # MODIFY (update call sites)
│   │       ├── EditWorkoutView.swift            # NEW
│   │       ├── SetTableView.swift               # MODIFY (accept protocol)
│   │       └── ExerciseTabStripView.swift        # MODIFY (accept protocol)
│   └── Home/
│       └── Views/
│           └── WorkoutDetailFromHomeView.swift  # MODIFY (wire up edit button)
└── Core/
    └── Services/
        ├── Protocols/
        │   └── WorkoutServiceProtocol.swift     # MODIFY (add updateWorkoutMetadata)
        └── WorkoutService.swift                 # MODIFY (implement updateWorkoutMetadata)
```

**Structure Decision**: New files live in the existing `Reppo/Features/Workout/` directory. A new `Protocols/` subfolder holds the shared protocol. This follows the established file organization from the constitution.

## Architecture Overview

### Component Reuse via Protocol

```
┌──────────────────────────────────┐
│   SetTableDataSource (protocol)  │
│                                  │
│  exercises: [Exercise]           │
│  selectedExerciseIndex: Int      │
│  currentExercise: Exercise?      │
│  currentSets: [WorkoutSet]       │
│  completeSet(...)  async         │
│  addSet(for:)  async             │
│  addWarmupSet(for:)  async       │
│  deleteSet(_:)  async            │
│  changeSetType(_:to:)  async     │
│  reorderExercises(from:to:)      │
│  removeExercise(at:)  async      │
└──────────┬───────────┬───────────┘
           │           │
     ┌─────┴─────┐ ┌───┴──────────┐
     │ Active    │ │ Edit         │
     │ Workout   │ │ Workout      │
     │ ViewModel │ │ ViewModel    │
     └───────────┘ └──────────────┘
           │           │
           ▼           ▼
     ┌─────────────────────────┐
     │  SetTableView           │
     │  ExerciseTabStripView   │
     │  (accept protocol)      │
     └─────────────────────────┘
```

### Data Flow: Edit Existing Set

```
User edits weight → taps checkbox
  → EditWorkoutViewModel.completeSet(set, weight:85, ...)
    → set.weight = 85, set.updatedAt = Date()
    → setService.edit(set) [existing pipeline]
      → recompute effectiveWeight
      → persist to SwiftData
      → PRService.evaluateAfterEdit()
      → StatsService.updateStats()
    → update local state with SetSaveResult
    → UI refreshes
```

### Data Flow: Add New Set

```
User taps "+ Add Set"
  → EditWorkoutViewModel.addSet(for: exerciseId)
    → create WorkoutSet(workoutId, exerciseId, completed: false)
    → setService.save(newSet) [immediate]
    → track newSet.id in newSetIds
    → append to setsByExercise

User fills values → taps checkbox
  → completeSet detects newSetIds → setService.save() (not edit())
```

### Navigation Flow

```
HomeView → WorkoutDetailFromHomeView
  → toolbar menu → "Edit Workout"
  → .fullScreenCover → EditWorkoutView(workoutId, services)
    → EditWorkoutViewModel manages state
    → on dismiss → WorkoutDetailFromHomeView reloads
```
