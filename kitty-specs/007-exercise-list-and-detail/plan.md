# Implementation Plan: Exercise List + Detail

**Branch**: `007-exercise-list-and-detail` | **Date**: 2026-02-25 | **Spec**: `kitty-specs/007-exercise-list-and-detail/spec.md`
**Input**: Feature specification from `/kitty-specs/007-exercise-list-and-detail/spec.md`

## Summary

Build the Exercise List screen (with search, filter, sort, browse/selection dual mode), reusable Exercise Detail component (History/PRs/Charts tabs), Create/Edit Exercise sheet, and the app-wide 5-tab navigation shell with center FAB. Also retrofit Active Workout with `[Sets] [History] [Charts]` sub-tabs using the reusable Exercise Detail component. The entire data layer (services, repositories, SwiftData models) is already complete — this feature is **purely UI + ViewModel + navigation wiring**.

## Technical Context

**Language/Version**: Swift (latest stable), iOS 17.0+
**Primary Dependencies**: SwiftUI, SwiftData, Swift Charts (all native — no third-party)
**Storage**: SwiftData (already configured via `ModelContainerSetup.createContainer()`)
**Testing**: Manual testing for v1 (no automated tests)
**Target Platform**: iOS 17.0+, iPhone only
**Project Type**: Mobile (single platform)
**Performance Goals**: Search < 200ms for 200+ exercises, list scrolling at 60 FPS, screen transitions < 200ms
**Constraints**: < 100MB memory idle, dark mode only, no third-party UI libs
**Scale/Scope**: ~200 exercises in library, UI-only feature building on complete data layer

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| MVVM with Service/Repository layers | PASS | All views → ViewModels → Services → Repositories |
| `@Observable` for ViewModels (not ObservableObject) | PASS | `ExerciseListViewModel` will use `@Observable @MainActor final class` |
| Views never call Services/Repositories directly | PASS | All data access through ViewModel |
| NavigationStack (not NavigationView) | PASS | Tab bar uses `NavigationStack` per tab |
| Dark mode only | PASS | Using existing `DesignTokens.swift` tokens |
| No third-party UI libs | PASS | Swift Charts for charting, SF Symbols for icons |
| trackingType immutability | PASS | `ExerciseService.updateExercise()` already enforces; UI will disable field when sets exist |
| Write-time PR/stats (no read-time computation) | PASS | Exercise Detail reads pre-computed `ExerciseStats` and `PerformanceRecord` |
| Database aggregation, not Swift iteration | PASS | Using `ExerciseStats` (pre-computed) for card stats, `PRService.fetchPRTable()` for PR display |
| Memory management — no full collection loads | PASS | Exercise list loads name/metadata only; history/charts load on-demand per exercise |
| Integer grams for PR comparison | N/A | Feature 007 displays PRs, does not compute them |
| System font for v1 | PASS | Centralized type scale via design system |
| Minimum tap target 44×44pt | PASS | All interactive elements will meet this |
| SF Symbols for icons | PASS | Used for FAB, tab icons, action buttons |

**Constitution check: PASSED — no violations.**

## Project Structure

### Documentation (this feature)

```
kitty-specs/007-exercise-list-and-detail/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── contracts/           # Phase 1 output (Swift protocols)
└── tasks.md             # Phase 2 output (NOT created by plan)
```

### Source Code (repository root)

```
Reppo/
├── App/
│   ├── ContentView.swift          # MODIFY — replace placeholder with TabView shell
│   └── ReppoApp.swift             # No changes needed
│
├── Features/
│   ├── Exercise/                   # NEW — entire directory
│   │   ├── Views/
│   │   │   ├── ExerciseListView.swift         # Search + filter + sort + dual mode
│   │   │   ├── ExerciseCardView.swift         # Reusable card component
│   │   │   ├── ExerciseDetailView.swift       # Reusable: History/PRs/Charts tabs
│   │   │   ├── ExerciseHistoryView.swift      # Past sessions tab
│   │   │   ├── ExercisePRsView.swift          # Suffix-max PR table tab
│   │   │   ├── ExerciseChartsView.swift       # e1RM trend + volume charts tab
│   │   │   ├── CreateEditExerciseSheet.swift  # Full exercise form
│   │   │   └── Components/
│   │   │       ├── MuscleFilterStrip.swift    # Horizontal pill filter strip
│   │   │       └── SortOptionMenu.swift       # Sort picker (A-Z, recent, most used)
│   │   └── ViewModels/
│   │       ├── ExerciseListViewModel.swift    # List state: search, filter, sort, mode
│   │       ├── ExerciseDetailViewModel.swift  # Detail state: loads history, PRs, charts data
│   │       └── CreateEditExerciseViewModel.swift  # Form state + validation + save
│   │
│   └── Workout/
│       └── Views/
│           ├── ActiveWorkoutView.swift        # MODIFY — add sub-tab UI
│           └── ExercisePickerSheet.swift       # REPLACE — with full browser or remove
│
├── Core/
│   ├── Repositories/
│   │   └── ExerciseRepository.swift           # MAY MODIFY — add fetchByMuscle if needed
│   └── Services/
│       └── (no changes — all APIs already exist)
│
└── Data/
    └── (no changes — all models already exist)
```

**Structure Decision**: Mobile (iOS) feature module structure following established `Features/{Feature}/Views/` + `Features/{Feature}/ViewModels/` pattern from Feature 006.

## Key Architecture Decisions

### 1. Tab Bar Navigation Shell

`ContentView.swift` will be replaced with a proper `TabView` containing 5 tabs:
- **Programs** — Empty state placeholder (v1)
- **Calendar** — Empty state placeholder (Feature 008)
- **FAB (center)** — Custom center button, not a real tab. Pushes to `ExerciseListView`
- **Charts** — Empty state placeholder (Feature 009)
- **Settings** — Empty state placeholder (Feature 010)

Each tab wraps content in its own `NavigationStack`. The FAB navigates to `ExerciseListView` via the active tab's `NavigationStack` (or a dedicated one).

Active workout resume: On launch, if `WorkoutService.getActiveWorkout()` returns non-nil, present `ActiveWorkoutView` via `fullScreenCover` (existing behavior preserved).

### 2. Exercise List Dual Mode

The Exercise List operates in two modes controlled by a context flag:

- **Browse mode** (default, entered from FAB): Tap card → push `ExerciseDetailView`. Bottom nav visible. [+ New] button available. "Start Workout (N)" button appears when exercises selected.
- **Selection mode** (entered from Active Workout [+Exercise]): Tap card → toggle selection. "Add (N)" confirm button. Presented as sheet (replaces `ExercisePickerSheet`).

The same `ExerciseListView` + `ExerciseListViewModel` serves both contexts. Mode is passed via init parameter.

### 3. Exercise Detail as Reusable Component

`ExerciseDetailView` accepts an `exerciseId: UUID` and renders `[History] [PRs] [Charts]` tabs. It works in three contexts:
- **Pushed** from Exercise List (browse mode) — full screen
- **Pushed** from Calendar (Feature 008) — full screen
- **Embedded** in Active Workout — as sub-tab content alongside Sets tab

The `ExerciseDetailViewModel` is instantiated per-exercise and loads data on appear.

### 4. Active Workout Sub-Tab Retrofit

`ActiveWorkoutView` gains a sub-tab picker per exercise: `[Sets] [History] [Charts]`.
- Sub-tab selection is `@State` in the View (pure UI state, no business logic per MVVM rules).
- `[Sets]` shows existing `SetTableView` (no changes).
- `[History]` shows `ExerciseHistoryView` (reused from Exercise Detail).
- `[Charts]` shows `ExerciseChartsView` (reused from Exercise Detail).

### 5. Muscle Group Filtering

The spec requires filtering by `primaryMuscle`. Current `ExerciseRepository` has `fetchAll()` and `search(name:)` but no muscle filter. Two options:
- **Client-side filter**: Load all exercises, filter in ViewModel. Acceptable for ~200 exercises.
- **Repository method**: Add `fetchByMuscle(primaryMuscle:)` to `ExerciseRepository`.

**Decision**: Client-side filter in `ExerciseListViewModel`. The exercise list is bounded (~200 items) and already loaded for display. Adding a repository method is over-engineering for this dataset size.

### 6. Sort Options

Three sort modes per spec:
- **A-Z**: Sort by `exercise.name` (alphabetical)
- **Most Recent**: Sort by `ExerciseStats.lastPerformedDate` (requires stats fetch)
- **Most Used**: Sort by `ExerciseStats.totalWorkouts` (requires stats fetch)

`ExerciseListViewModel` will fetch both exercises and their stats, then sort client-side.

### 7. Charts — Functional Minimum

`ExerciseChartsView` renders two charts using Swift Charts:
- **e1RM Trend**: `LineMark` plotting `e1RM` values over time from `WorkoutSet` data
- **Volume Per Session**: `BarMark` plotting total volume per workout

Data fetched on-demand per exercise via `SetRepository` queries. No interactivity (tap-to-highlight deferred to Feature 009).

### 8. Exercise Card Data

Each `ExerciseCardView` displays:
- `exercise.name`, `exercise.primaryMuscle`, `exercise.equipmentType`, `exercise.trackingType`
- `stats.lastPerformedDate` (from `ExerciseStats`)
- Best lift: `stats.maxWeight` or `stats.bestE1RM` (from `ExerciseStats`)

All data comes from pre-computed `ExerciseStats` — no on-demand queries per card.

## Parallel Work Analysis

### Dependency Graph

```
WP01 (Tab Shell) ──────┬──> WP02 (Card & Components) ──> WP03 (List View)  ──┐
                        ├──> WP04 (Detail View) ────────> WP06 (AW Retrofit) ──┤──> WP07 (Integration)
                        └──> WP05 (Create/Edit Sheet)  ───────────────────────┘
```

### Work Distribution

- **Sequential first**: WP01 (Tab Shell) provides the navigation frame and shared enums
- **Parallel streams after WP01**: WP02 (Card & Components), WP04 (Detail View), WP05 (Create/Edit) can all proceed in parallel
- **WP03** (List View) depends on WP02 (needs ExerciseListViewModel, ExerciseCardView, components)
- **WP06** (Active Workout Retrofit) depends on WP03 + WP04 (needs ExerciseListView for picker, History/Charts views for sub-tabs)
- **WP07** (Integration) is the final pass wiring all navigation flows

### Coordination Points

- WP02 owns `ExerciseCardView` and `ExerciseListViewModel` — consumed by WP03
- WP04 produces `ExerciseHistoryView` and `ExerciseChartsView` — consumed by WP06
- WP07 connects browse-mode tap → WP04's `ExerciseDetailView` push navigation
- WP07 wires FAB → WP03's `ExerciseListView` and "Start Workout" flow
