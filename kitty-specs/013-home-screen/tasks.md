# Work Packages: Home Screen

**Inputs**: Design documents from `/kitty-specs/013-home-screen/`
**Prerequisites**: plan.md (required), spec.md (user stories), research.md, data-model.md, quickstart.md

**Tests**: No automated tests required (manual testing per constitution).

**Organization**: Fine-grained subtasks (`Txxx`) roll up into work packages (`WPxx`). Each work package is independently deliverable and testable.

**Prompt Files**: Each work package references a matching prompt file in `kitty-specs/013-home-screen/tasks/`.

---

## Work Package WP01: HomeViewModel — Foundation & Data Loading (Priority: P0)

**Goal**: Create the HomeViewModel with all data loading logic for the Home screen's read-only sections: week strip, this week activity, recent workouts, and active workout detection.
**Independent Test**: Instantiate HomeViewModel with service mocks, call loadData(), verify all state properties are populated correctly.
**Prompt**: `kitty-specs/013-home-screen/tasks/WP01-homeviewmodel-foundation.md`
**Estimated Size**: ~450 lines

### Included Subtasks
- [x] T001 Rename `MainTab.programs` → `.home` in `Reppo/Features/Exercise/Models/ExerciseEnums.swift`
- [x] T002 Create `HomeViewModel.swift` — class structure, `@Observable` `@MainActor`, all state properties, data structs (`WeekDay`, `RecentWorkoutSummary`, `CopyPreviousWorkout`), service dependencies, exercise cache, init
- [x] T003 Implement `checkActiveWorkout()` — sets `hasActiveWorkout` flag
- [x] T004 Implement `loadWeekStrip()` — fetch workouts for current Mon–Sun, build `[WeekDay]` with today highlighting and workout dots
- [x] T005 Implement `loadThisWeekActivity()` — count completed workouts this week, derive `thisWeekWorkoutDays` set
- [x] T006 Implement `loadRecentWorkouts()` — fetch last 5 completed workouts, build `[RecentWorkoutSummary]` with exercise caching for muscle groups
- [x] T007 Implement `loadData()` orchestration method calling all load methods

### Implementation Notes
- Follow CalendarViewModel pattern: `@Observable`, `cachedExercise()` helper, error handling via print.
- All load methods are async. `loadData()` calls them sequentially or with TaskGroup.
- Week range computed from `Calendar.current`: Monday of current week through Sunday.
- Filter workouts by `.completed` status for dots, activity, and recent sections.
- `fetchAllWorkouts(limit: 5, offset: 0)` may return in-progress workouts — filter in ViewModel.

### Parallel Opportunities
- T001 (enum rename) is independent and can be done first or in parallel with T002.
- T003–T006 are sequential within HomeViewModel but logically independent methods.

### Dependencies
- None (foundation work package).

### Risks & Mitigations
- `fetchAllWorkouts` returns all statuses — must filter to `.completed` for recent workouts.
- Exercise cache prevents N+1 queries but must handle nil exercises gracefully.

---

## Work Package WP02: HomeViewModel — Copy Previous & Workout Actions (Priority: P1)

**Goal**: Add Copy Previous workflow and workout action methods to HomeViewModel — start empty workout, load copy candidates, copy a past workout with active workout conflict handling.
**Independent Test**: Call `copyWorkout()` with a mock workout, verify new workout created with duplicated working sets and correct weight/reps pre-filled.
**Prompt**: `kitty-specs/013-home-screen/tasks/WP02-homeviewmodel-copy-previous.md`
**Estimated Size**: ~400 lines

### Included Subtasks
- [x] T008 Implement `startEmptyWorkout()` — call `workoutService.startWorkout()`, return the new workout
- [x] T009 Implement `loadCopyPreviousWorkouts()` — fetch all completed workouts, build `[CopyPreviousWorkout]` with stats and muscle groups
- [x] T010 Implement `copyWorkout(_ workoutId:)` — fetch source sets, filter to `.working`, check for active workout conflict, handle confirmation state, create new workout, duplicate sets with pre-filled weight/reps
- [x] T011 Implement `discardActiveAndCopy()` — delete active workout via `deleteWorkout()`, then proceed with copy

### Implementation Notes
- Copy duplicates only `setType == .working` sets (no warmup sets).
- Each duplicated set: new UUID, new workoutId, same exerciseId/weight/reps/orderInWorkout/orderInExercise, setType = .working, completed = false.
- Use `setService.save()` for each duplicated set (triggers PR pipeline + stats — correct behavior).
- Active workout conflict: if `getActiveWorkout()` returns non-nil when user selects a workout to copy, set `showDiscardConfirmation = true` and store `pendingCopyWorkoutId`.
- `discardActiveAndCopy()` calls `workoutService.deleteWorkout()` then retries the copy.

### Parallel Opportunities
- WP02 can proceed in parallel with WP03 (different files).

### Dependencies
- Depends on WP01 (HomeViewModel class, state properties, data structs).

### Risks & Mitigations
- Race condition: user starts workout via FAB while Copy Previous sheet is open — guard with `getActiveWorkout()` check before creating copied workout.
- Large source workout with many sets — copy loop is sequential but bounded by typical workout size (~20–40 sets).

---

## Work Package WP03: Home Screen Sub-Views (Priority: P1)

**Goal**: Create all presentational sub-views for the Home screen: week strip, start workout card, quick action cards, this week activity, and recent workout card.
**Independent Test**: Each sub-view renders correctly in Xcode Preview with mock data, follows design system tokens.
**Prompt**: `kitty-specs/013-home-screen/tasks/WP03-home-screen-subviews.md`
**Estimated Size**: ~450 lines

### Included Subtasks
- [x] T012 [P] Create `WeekStripView.swift` — 7-day HStack, today accent background, workout dots
- [x] T013 [P] Create `StartWorkoutCardView.swift` — bgCard, "READY TO TRAIN" label, title/subtitle, [+] button
- [x] T014 [P] Create `QuickActionCardsView.swift` — two equal-width side-by-side cards
- [x] T015 [P] Create `ThisWeekActivityView.swift` — section header, 7-day bar chart, session counter
- [x] T016 [P] Create `RecentWorkoutCardView.swift` — date, stats row, muscle group tag pills

### Implementation Notes
- All sub-views are pure presentation: accept data as parameters, no ViewModel references.
- All sub-views go in `Reppo/Features/Home/Views/`.
- Follow design-system.md tokens: `Color.bg`, `Color.bgCard`, `Color.accent`, `Color.textPrimary`/`Secondary`/`Tertiary`.
- Section headers: 11pt semibold, uppercase, textTertiary, 0.8 letter spacing.
- Cards: bgCard background, 14pt corner radius, 14pt padding.
- Touch targets: 44pt minimum for all interactive elements.
- Volume display: kg only for v1 (matching existing `SummaryStatsStrip` pattern).

### Parallel Opportunities
- All 5 sub-views are independent files — all can be implemented in parallel.

### Dependencies
- Depends on WP01 (needs `WeekDay`, `RecentWorkoutSummary` data struct definitions).

### Risks & Mitigations
- Bar chart in ThisWeekActivityView must handle days with no workouts gracefully.
- Week strip must correctly compute day abbreviations for Mon–Sun regardless of device locale.

---

## Work Package WP04: Integration — HomeView + CopyPreviousSheet + ContentView (Priority: P1)

**Goal**: Assemble all components into the final HomeView, create the Copy Previous sheet, wire into ContentView (replacing Programs placeholder), and handle navigation + data refresh.
**Independent Test**: Launch app, verify Home tab is first tab with house icon, all sections render, Start Workout and Copy Previous flows work end-to-end, Recent cards navigate to detail.
**Prompt**: `kitty-specs/013-home-screen/tasks/WP04-integration.md`
**Estimated Size**: ~450 lines

### Included Subtasks
- [x] T017 Create `HomeView.swift` — `NavigationStack` + `ScrollView` + `VStack` layout, header (date/title/avatar), all sub-views wired to ViewModel, `.task`/`.onAppear` for data loading
- [x] T018 Create `CopyPreviousSheet.swift` — `.sheet` presentation, workout list, empty state, tap handler, `.confirmationDialog` for active workout conflict
- [x] T019 Update `ContentView.swift` — replace `ProgramsPlaceholderView` with `HomeView`, update tab item to "Home" with `house` SF Symbol, pass `onStartWorkout` callback, update `MainTab.programs` → `.home` references
- [x] T020 Implement workout detail navigation — `navigationDestination` from Recent cards, load `WorkoutDetail` on demand, reuse `CalendarWorkoutDetailView` pattern
- [x] T021 Implement data refresh on reappear + empty states for all sections + design system compliance verification

### Implementation Notes
- HomeView receives `services: ServiceContainer` and `onStartWorkout: () -> Void` closure.
- `onStartWorkout` is called after HomeViewModel creates a workout (start empty, copy, or resume active) to trigger `showActiveWorkout = true` in ContentView.
- Copy Previous sheet: `.sheet(isPresented: $viewModel.showCopyPreviousSheet)`.
- Confirmation dialog: `.confirmationDialog("Active Workout", isPresented: $viewModel.showDiscardConfirmation)`.
- Workout detail navigation: `.navigationDestination(for: UUID.self)` — push a view that loads WorkoutDetail from services.
- Data refresh: `.onAppear { Task { await viewModel.loadData() } }` — fires when tab is reselected or fullScreenCover dismisses.
- Empty states: "Complete your first workout to see it here" for recent, "0 / 4 sessions" for activity, no dots for week strip.

### Parallel Opportunities
- T017 and T018 can be created in parallel (different files).
- T019 must wait for T017 (needs HomeView to reference in TabView).

### Dependencies
- Depends on WP01 (ViewModel + data loading), WP02 (copy previous + workout actions), WP03 (sub-views).

### Risks & Mitigations
- NavigationStack conflict: HomeView owns its own NavigationStack. ContentView's outer NavigationStack handles FAB → ExerciseListView. Test both navigation paths.
- Start Workout card body tap should open ExerciseListView (same as FAB). This requires coordinating with ContentView's `showExerciseList` state — pass as binding or closure.
- Data staleness: If user leaves app running for days, week strip needs to update. `loadData()` on `.onAppear` handles this.

---

## Dependency & Execution Summary

```
WP01 (Foundation) ──┬──► WP02 (Copy Previous) ──┐
                    │                             ├──► WP04 (Integration)
                    └──► WP03 (Sub-Views) ────────┘
```

- **Sequence**: WP01 → (WP02 ∥ WP03) → WP04
- **Parallelization**: WP02 and WP03 can proceed simultaneously after WP01 completes (different files, no shared mutations).
- **MVP Scope**: WP01 + WP03 + WP04 (with Copy Previous stubbed) delivers a functional Home screen without Copy Previous. Full scope requires all 4 WPs.

---

## Subtask Index (Reference)

| Subtask | Summary | Work Package | Priority | Parallel? |
|---------|---------|--------------|----------|-----------|
| T001 | Rename MainTab.programs → .home | WP01 | P0 | Yes |
| T002 | Create HomeViewModel class structure | WP01 | P0 | No |
| T003 | Implement checkActiveWorkout() | WP01 | P0 | No |
| T004 | Implement loadWeekStrip() | WP01 | P0 | No |
| T005 | Implement loadThisWeekActivity() | WP01 | P0 | No |
| T006 | Implement loadRecentWorkouts() | WP01 | P0 | No |
| T007 | Implement loadData() orchestration | WP01 | P0 | No |
| T008 | Implement startEmptyWorkout() | WP02 | P1 | No |
| T009 | Implement loadCopyPreviousWorkouts() | WP02 | P1 | No |
| T010 | Implement copyWorkout() | WP02 | P1 | No |
| T011 | Implement discardActiveAndCopy() | WP02 | P1 | No |
| T012 | Create WeekStripView.swift | WP03 | P1 | Yes |
| T013 | Create StartWorkoutCardView.swift | WP03 | P1 | Yes |
| T014 | Create QuickActionCardsView.swift | WP03 | P1 | Yes |
| T015 | Create ThisWeekActivityView.swift | WP03 | P1 | Yes |
| T016 | Create RecentWorkoutCardView.swift | WP03 | P1 | Yes |
| T017 | Create HomeView.swift | WP04 | P1 | Yes |
| T018 | Create CopyPreviousSheet.swift | WP04 | P1 | Yes |
| T019 | Update ContentView.swift | WP04 | P1 | No |
| T020 | Workout detail navigation | WP04 | P1 | No |
| T021 | Data refresh + empty states + design system | WP04 | P1 | No |
