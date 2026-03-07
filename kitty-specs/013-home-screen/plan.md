# Implementation Plan: Home Screen

**Branch**: `013-home-screen` | **Date**: 2026-03-01 | **Spec**: `kitty-specs/013-home-screen/spec.md`
**Input**: Feature specification from `/kitty-specs/013-home-screen/spec.md`

---

## Summary

Replace the Programs placeholder tab with a full Home screen serving as the app's landing page. The Home screen displays six sections: header with date/title, week strip calendar, start workout CTA, quick action cards (copy previous + templates placeholder), this week activity tracker, and recent workouts list. A single `HomeViewModel` composes existing service calls — no new services, repositories, or SwiftData models are required. The `MainTab.programs` enum case is renamed to `.home`.

---

## Technical Context

**Language/Version**: Swift 5.9+, targeting iOS 17.0+
**Primary Dependencies**: SwiftUI, SwiftData (read-only access via existing services)
**Storage**: Existing SwiftData models — Workout, WorkoutSet, Exercise (no schema changes)
**Testing**: Manual testing for v1 (per constitution)
**Target Platform**: iOS 17.0+, iPhone only
**Project Type**: Mobile (single target)
**Performance Goals**: Home screen loads all sections within 1 second (SC-001), 60 FPS scrolling (SC-005)
**Constraints**: No new service/repository methods (FR-016), dark mode only, design system tokens
**Scale/Scope**: ~10 new files (1 ViewModel, 7-8 Views), ~2 modified files (ContentView, ExerciseEnums)

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| MVVM with Service/Repository layers | PASS | HomeViewModel → services → repositories. No layer skipping. |
| Views call ViewModels only | PASS | All Home sub-views receive data from HomeViewModel, never call services directly. |
| @Observable (not ObservableObject) | PASS | HomeViewModel uses `@Observable` + `@MainActor`. |
| async/await over callbacks | PASS | All service calls are async. |
| No new SwiftData models | PASS | Reads existing Workout, WorkoutSet, Exercise models. |
| DI via initializer injection | PASS | HomeViewModel receives service protocols in init(). HomeView receives them from ServiceContainer environment. |
| NavigationStack (not NavigationView) | PASS | Home tab wraps content in NavigationStack. |
| Dark mode only | PASS | All colors from DesignTokens.swift. |
| SF Symbols for icons | PASS | House icon, copy icon, document icon — all SF Symbols. |
| No third-party UI libs | PASS | Pure SwiftUI. |
| 44pt minimum tap targets | PASS | Per SC-006, all interactive elements. |
| System font for v1 | PASS | Uses `.system()` font throughout. |
| Weight stored in kg | PASS | Volume display converts at UI boundary per user preference. |
| No startup rebuild | PASS | Home screen fetches on-demand, no startup computation. |
| Database aggregation preferred | NOTED | Recent workout stats computed from fetched sets — acceptable for ≤5 workouts × ~20 sets each. Not a bulk aggregation. |

**Post-Phase 1 Re-check**: No new violations introduced. Constitution fully satisfied.

---

## Project Structure

### Documentation (this feature)

```
kitty-specs/013-home-screen/
├── spec.md              # Feature specification (complete)
├── plan.md              # This file
├── research.md          # Phase 0 output (complete)
├── data-model.md        # Phase 1 output (complete)
└── tasks.md             # Phase 2 output (NOT created by /spec-kitty.plan)
```

### Source Code (repository root)

```
Reppo/
├── App/
│   └── ContentView.swift              # MODIFY — replace ProgramsPlaceholderView with HomeView,
│                                      #           update tab item label/icon, pass services
├── Features/
│   ├── Home/                          # NEW DIRECTORY
│   │   ├── Views/
│   │   │   ├── HomeView.swift         # NEW — main Home screen (ScrollView + NavigationStack)
│   │   │   ├── WeekStripView.swift    # NEW — 7-day week strip with dots
│   │   │   ├── StartWorkoutCardView.swift  # NEW — start workout CTA card
│   │   │   ├── QuickActionCardsView.swift  # NEW — copy previous + templates side-by-side
│   │   │   ├── ThisWeekActivityView.swift  # NEW — bar chart + session counter
│   │   │   ├── RecentWorkoutCardView.swift # NEW — single recent workout card
│   │   │   └── CopyPreviousSheet.swift     # NEW — modal sheet for selecting past workout
│   │   └── ViewModels/
│   │       └── HomeViewModel.swift    # NEW — single ViewModel for all Home screen data
│   └── Exercise/
│       └── Models/
│           └── ExerciseEnums.swift     # MODIFY — rename MainTab.programs → .home
└── Core/
    └── (no changes)
```

**Structure Decision**: Follows the established feature-module pattern (`Features/Home/Views/`, `Features/Home/ViewModels/`). Sub-views are separate files for readability but all receive data from the single `HomeViewModel`. No new services, repositories, extensions, or shared utilities.

---

## File-by-File Implementation Details

### 1. `ExerciseEnums.swift` — MainTab Rename

**Change**: Rename `case programs = 0` to `case home = 0`.

**Impact**: All references to `MainTab.programs` must update to `MainTab.home`. Only used in `ContentView.swift` (`selectedTab`, `tag()`).

### 2. `ContentView.swift` — Tab Replacement

**Changes**:
- Replace `ProgramsPlaceholderView()` with `HomeView(services: services, onStartWorkout: { showActiveWorkout = true })`.
- Update `.tabItem` to `Label("Home", systemImage: "house")`.
- Update `.tag(MainTab.programs)` to `.tag(MainTab.home)`.
- Update `@State private var selectedTab: MainTab = .programs` to `.home`.
- Add a callback mechanism so HomeView can trigger `showActiveWorkout = true` after creating a workout (for Copy Previous and Start Workout [+] button flows).

**Callback pattern**: Pass a closure `onStartWorkout: () -> Void` to HomeView. When HomeViewModel creates a workout (via start or copy), it calls this closure to trigger the fullScreenCover in ContentView.

### 3. `HomeViewModel.swift` — Core Logic

**Architecture**: `@Observable`, `@MainActor`, single class.

**Dependencies**: `WorkoutServiceProtocol`, `SetServiceProtocol`, `ExerciseServiceProtocol` (injected via init).

**Key methods**:
- `loadData()` — loads all sections in parallel (week strip, active workout check, recent workouts, this week activity)
- `loadWeekStrip()` — fetches workouts for current Mon–Sun, builds `[WeekDay]`
- `loadRecentWorkouts()` — fetches last 5 completed workouts, builds `[RecentWorkoutSummary]`
- `loadThisWeekActivity()` — derives session count and workout day set from week workouts
- `checkActiveWorkout()` — sets `hasActiveWorkout` flag
- `loadCopyPreviousWorkouts()` — fetches all completed workouts for sheet display
- `copyWorkout(_ workoutId: UUID)` — orchestrates the copy flow (fetch sets, check active, create new workout, duplicate sets)
- `startEmptyWorkout()` — calls `workoutService.startWorkout()`
- `discardActiveAndCopy()` — deletes active workout then copies

**Data refresh**: `loadData()` called from `.task` (initial) and `.onAppear` (refresh after returning from active workout).

### 4. `HomeView.swift` — Main Screen

**Structure**:
```swift
NavigationStack {
    ScrollView {
        VStack(spacing: 20) {
            headerSection        // date + "Workout" title + avatar placeholder
            WeekStripView(weekDays: viewModel.weekDays)
            StartWorkoutCardView(hasActiveWorkout: viewModel.hasActiveWorkout, ...)
            QuickActionCardsView(...)
            ThisWeekActivityView(...)
            recentWorkoutsSection  // section header + cards
        }
        .padding(.horizontal, 20)
    }
    .background(Color.bg)
    .navigationDestination(for: UUID.self) { workoutId in
        // Push to workout detail view (reuses CalendarWorkoutDetailView pattern)
    }
}
.task { await viewModel.loadData() }
.onAppear { Task { await viewModel.loadData() } }
```

**Header**: Inline view (not a separate file — too simple). Shows formatted date ("Wednesday, Mar 1"), title "Workout" at 26pt bold, and a 36pt gray circle as avatar placeholder.

### 5. `WeekStripView.swift` — Week Strip Calendar

**Input**: `[WeekDay]` from ViewModel.

**Layout**: `HStack` with 7 equal-width day cells. Each cell shows:
- Day abbreviation (10pt, textTertiary)
- Date number (15pt, bold)
- Accent dot below (6pt circle) if `hasWorkout`
- Today cell: accent-colored background with rounded corners

### 6. `StartWorkoutCardView.swift` — Start Workout CTA

**Input**: `hasActiveWorkout: Bool`, `onCardTapped: () -> Void`, `onPlusTapped: () -> Void`.

**Layout**: `bgCard` background, 14pt radius. Left side: "READY TO TRAIN" label (accent, 11pt uppercase), "Start Workout" (17pt semibold), "Log exercises, sets & reps" (13pt, textSecondary). Right side: [+] button (44pt tap target, accent circle with plus icon).

**Behavior**:
- Card body tap → `onCardTapped` (opens ExerciseListView in browse mode, or resumes active workout)
- [+] button tap → `onPlusTapped` (creates empty workout, or resumes active workout)

### 7. `QuickActionCardsView.swift` — Copy Previous + Templates

**Layout**: `HStack` with two equal-width cards. Each card: `bgCard`, 14pt radius, icon + title.

- "Copy Previous" (SF Symbol: `doc.on.doc`) → triggers `viewModel.showCopyPreviousSheet = true`
- "Templates" (SF Symbol: `doc.text`) → shows "Coming soon" alert or inline message

### 8. `ThisWeekActivityView.swift` — Activity Bar Chart

**Input**: `workoutCount: Int`, `workoutDays: Set<Int>`, `weeklyGoal: Int`.

**Layout**:
- Section header: "THIS WEEK" (11pt, uppercase, textTertiary)
- `HStack` of 7 day bars (M T W T F S S). Each bar: narrow rectangle, filled with accent color if day has workout, dim otherwise.
- Session counter: "X / 4 sessions" — X in accent color, rest in textSecondary.
- Today's day label: bold or accent-colored.

### 9. `RecentWorkoutCardView.swift` — Single Recent Card

**Input**: `RecentWorkoutSummary`.

**Layout** (follows design-system.md Recent Workout Card pattern):
- Row 1: Workout date (formatted, 13pt textSecondary)
- Row 2: Stats row — 4 inline stats (exercises, sets, duration "Xm", volume "X.Xt")
- Row 3: Muscle group tags as pills (`bgSubtle`, 11pt, textSecondary)

**Tap**: Navigates to workout detail via NavigationStack (`.navigationDestination`).

### 10. `CopyPreviousSheet.swift` — Copy Previous Modal

**Presentation**: `.sheet(isPresented: $viewModel.showCopyPreviousSheet)`

**Layout**:
- Title: "Copy Previous Workout"
- List of `CopyPreviousWorkout` items (date, exercise count, sets, volume, muscle tags)
- Empty state: "No workouts yet" if no completed workouts exist
- Tap handler: calls `viewModel.copyWorkout(workoutId)` which handles active workout check + confirmation dialog

**Confirmation dialog**: `.confirmationDialog` presented when active workout exists. Options: "Discard & Copy" (destructive), "Cancel".

---

## Key Implementation Decisions

### 1. Communication between HomeView and ContentView

HomeView needs to trigger `showActiveWorkout = true` on ContentView after creating or resuming a workout. Two approaches:

**Selected**: Pass an `onStartWorkout: () -> Void` closure from ContentView to HomeView. HomeView passes it to HomeViewModel. After a workout is created (start empty, copy previous, or resume), the ViewModel calls this closure.

**Why**: Simple, explicit, follows the existing `startWorkoutWithExercises` pattern in ContentView. No need for NotificationCenter or shared state.

### 2. FAB behavior from Home tab

The existing FAB in ContentView already opens ExerciseListView in browse mode. The Start Workout card body should do the same thing. Two options:

**Selected**: The Start Workout card body tap uses the same `showExerciseList` state from ContentView (passed down as a binding or closure). The [+] button creates an empty workout directly via HomeViewModel.

**Alternative considered**: Duplicating ExerciseListView navigation in HomeView — rejected to avoid two NavigationStack conflicts.

### 3. Volume display units

Volume is stored in kg. Display is kg only for v1 (no unit preference setting exists yet). Matches the existing `SummaryStatsStrip` pattern. Volume ≥1000 kg displays as tonnes (e.g., "1.5t").

---

## Dependency Graph

```
Phase 1: Foundation
   ├── ExerciseEnums.swift (MainTab rename)
   └── HomeViewModel.swift (core logic, all data loading)

Phase 2: UI Components (parallel, all depend on Phase 1)
   ├── WeekStripView.swift
   ├── StartWorkoutCardView.swift
   ├── QuickActionCardsView.swift
   ├── ThisWeekActivityView.swift
   └── RecentWorkoutCardView.swift

Phase 3: Integration (depends on Phase 1 + 2)
   ├── HomeView.swift (assembles all sub-views)
   ├── CopyPreviousSheet.swift (depends on HomeViewModel copy logic)
   └── ContentView.swift (tab replacement, callback wiring)

Phase 4: Polish & Verification
   └── Manual testing of all acceptance scenarios
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| NavigationStack conflict (HomeView + ContentView outer stack) | Medium | High | HomeView owns its own NavigationStack; ContentView's stack handles FAB only. Test push navigation from Recent cards. |
| Copy Previous + active workout race condition | Low | Medium | Check active workout before creating copy. Use confirmation dialog. |
| Performance with 5 recent workouts × N sets each | Low | Low | Bounded by 5 workouts max. Exercise cache prevents duplicate fetches. |
| Stale data after workout completion | Medium | Medium | `.onAppear` triggers `loadData()` refresh. |
