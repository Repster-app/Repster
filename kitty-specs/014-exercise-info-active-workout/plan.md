# Implementation Plan: Exercise Info in Active Workout

**Branch**: `014-exercise-info-active-workout` | **Date**: 2026-03-01 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/kitty-specs/014-exercise-info-active-workout/spec.md`

## Summary

Add a contextual "EXERCISE INFO" section below the set table in `ActiveWorkoutView`'s `.sets` sub-tab, showing three data cards: **Estimated 1RM** (hero, full-width), **Last Workout** (compact), and **Est. for N reps** (compact, side-by-side with Last Workout). The section provides at-a-glance metrics so lifters can make informed weight/rep decisions without leaving the logging flow.

**Technical approach**: Create a dedicated `ExerciseInfoProvider` helper that encapsulates all computation logic, fed by existing `SetService`/`StatsService` methods. A clean `ExerciseInfoData` value type holds the results. Modular SwiftUI views (`ExerciseInfoSectionView` + 3 card subviews) render the data within the existing `SetTableView` scroll area. No service or repository interface changes required.

## Technical Context

**Language/Version**: Swift 5.9+, targeting iOS 17.0+
**Primary Dependencies**: SwiftUI, SwiftData, `@Observable` (Observation framework)
**Storage**: SwiftData — reads from `WorkoutSet`, `ExerciseStats`, `HealthProfile` models
**Testing**: Manual testing for v1 (no automated tests required per constitution)
**Target Platform**: iOS 17.0+, iPhone only, dark mode only
**Project Type**: Mobile (single-platform iOS)
**Performance Goals**: Exercise Info loads within 500ms of tab selection; 60 FPS scrolling maintained
**Constraints**: No new service/repository interfaces; uses existing write-time computed values (`e1RM`, `effectiveWeight`); memory-efficient (no full history in RAM)
**Scale/Scope**: 3 new View files, 1 ViewModel extension, 1 Provider helper, 1 data model struct

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| MVVM layers (View → ViewModel → Service → Repository) | ✅ PASS | Views call `ActiveWorkoutViewModel`, which delegates to `ExerciseInfoProvider` (helper), which calls `SetService`/`StatsService`. No layer skipping. |
| No ModelContext from ViewModel | ✅ PASS | All data access through existing Service → Repository chain |
| Uses `effectiveWeight` for calculations | ✅ PASS | e1RM and comparisons use `WorkoutSet.effectiveWeight` (pre-computed at save-time) |
| Write-time computed values | ✅ PASS | `WorkoutSet.e1RM` is pre-computed at save-time; we read, never recalculate retroactively |
| No startup rebuild | ✅ PASS | Feature reads on-demand when exercise tab is selected, no startup work |
| Database aggregation over Swift iteration | ✅ PASS | Uses `ExerciseStats.bestE1RM` (pre-computed) and `SetRepository.fetchSets` with limit for last workout lookup. No full-collection iteration. |
| Dark mode only | ✅ PASS | Uses `design-system.md` tokens: `bgCard`, `textPrimary`, `success`/`danger` |
| SF Symbols, system font | ✅ PASS | Icons via SF Symbols; typography via system font with design-system scale |
| 44pt minimum touch targets | ✅ PASS | Cards meet minimum height; no interactive tap targets smaller than 44pt |
| No third-party dependencies | ✅ PASS | Pure SwiftUI + SwiftData |
| Integer grams for weight comparison | ✅ PASS | Historical comparison uses `toGrams()` pattern for delta calculation |
| `hasData` for analytics/PR (not `completed`) | ✅ PASS | Working set filtering uses `hasData` and `setType != .warmup` |
| Store metric, convert in UI | ✅ PASS | All values stored/computed in kg; UI conversion via `UnitPreference` |
| Do NOT invent schema | ✅ PASS | No new `@Model` classes. `ExerciseInfoData` is a transient view struct only. |

**Gate result**: ✅ ALL PASS — Proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```
kitty-specs/014-exercise-info-active-workout/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (internal contracts)
└── checklists/
    └── requirements.md  # Pre-existing quality checklist
```

### Source Code (repository root)

```
Reppo/
├── Features/
│   └── Workout/
│       ├── Views/
│       │   ├── ActiveWorkoutView.swift          # MODIFY: Add ExerciseInfoSectionView in .sets sub-tab
│       │   ├── SetTableView.swift               # REFERENCE ONLY: Understand insertion point
│       │   └── Components/
│       │       ├── ExerciseInfoSectionView.swift # NEW: Container for the 3 cards + section header
│       │       ├── E1RMCardView.swift            # NEW: Hero card — e1RM value, best today, vs 4wk
│       │       ├── LastWorkoutCardView.swift     # NEW: Compact card — last session top sets
│       │       └── EstimatedRepsCardView.swift   # NEW: Compact card — weight estimate for N reps
│       ├── ViewModels/
│       │   └── ActiveWorkoutViewModel.swift      # MODIFY: Add loadExerciseInfo() + ExerciseInfoProvider
│       └── Models/
│           └── ExerciseInfoData.swift            # NEW: Value type holding computed info for display
├── Core/
│   ├── Services/
│   │   ├── SetService.swift                     # REFERENCE ONLY: fetchSets(for exerciseId:)
│   │   └── StatsService.swift                   # REFERENCE ONLY: fetchStats(for exerciseId:)
│   └── Repositories/
│       ├── SetRepository.swift                  # REFERENCE ONLY: fetchSets date-range queries
│       └── HealthProfileRepository.swift        # REFERENCE ONLY: fetchOrCreate()
└── Data/
    ├── Models/
    │   ├── WorkoutSet.swift                     # REFERENCE ONLY: e1RM, effectiveWeight properties
    │   ├── ExerciseStats.swift                  # REFERENCE ONLY: bestE1RM
    │   └── Exercise.swift                       # REFERENCE ONLY: trackingType, bodyweightFactor
    └── Enums/
        └── E1RMFormula.swift                    # REFERENCE ONLY: calculate(weight:reps:)
```

**Structure Decision**: Mobile (iOS) feature module pattern. New files are added under `Features/Workout/` following the existing organization. No new directories — components go into the existing `Components/` folder. The `ExerciseInfoData` model is a transient view struct (not a `@Model`), placed in `Features/Workout/Models/`.

## Engineering Alignment

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Data model** | `ExerciseInfoData` struct (value type) | Clean, testable, decoupled from SwiftData. Holds e1RM info, last workout summary, and rep estimate for display. |
| **Computation layer** | `ExerciseInfoProvider` (helper class/struct) | Encapsulates all calculation logic. Injected with services. Keeps `ActiveWorkoutViewModel` clean and focused. Scalable — easy to add new cards later. |
| **ViewModel integration** | `loadExerciseInfo()` on `ActiveWorkoutViewModel` | Delegates to `ExerciseInfoProvider`. Called when `.sets` sub-tab is visible. Caches by `exerciseInfoLoadedForExerciseId` (matches existing caching pattern). |
| **View composition** | `ExerciseInfoSectionView` → 3 child card views | Section header + hero card (full width) + HStack of 2 compact cards. Each card is an independent, reusable SwiftUI view. |
| **Data sourcing — e1RM** | Read `WorkoutSet.e1RM` (pre-computed) | Already stored at save-time. Today's best = `max(currentSets.compactMap(\.e1RM))` for working sets with `hasData`. |
| **Data sourcing — 4wk comparison** | `SetService.fetchSets(for: exerciseId, limit: nil)` → filter by date | Reuse history data already fetched for sub-tabs. Filter sets from ~28 days ago, find best e1RM. Falls back to nearest available. |
| **Data sourcing — last workout** | Group history by `workoutId`, take first group (newest, excluding current) | Same data source as History sub-tab. Filter to working sets, sort by effectiveWeight desc, take top sets. |
| **Data sourcing — rep estimate** | Reverse-calculate from best recent e1RM using `E1RMFormula` | Given e1RM and target reps → solve for weight. Uses HealthProfile formula preference. |
| **Visibility** | `.sets` sub-tab only | Per user confirmation. Inserted below Add Set / Add Warmup buttons inside the same ScrollView. |
| **Duration-based exercises** | Hide e1RM and Est. for N reps cards; show adapted Last Workout only | `trackingType == .duration` → filter out weight/rep cards. Last Workout shows duration values instead. |
| **Unit display** | Convert from kg at UI boundary using `UnitPreference` | Per constitution. All internal values in kg. Display adapts via HealthProfile.unitPreference. |
| **Empty states** | Graceful placeholders per card | "No data yet" for e1RM, "No previous data" for Last Workout, hidden for Est. reps if insufficient history. |
| **Trend colors** | `Color.success` (+) / `Color.danger` (−) | Per design-system.md. Applied to the "vs 4wk ago" delta text. |

## Complexity Tracking

*No constitution violations. No complexity justifications needed.*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
