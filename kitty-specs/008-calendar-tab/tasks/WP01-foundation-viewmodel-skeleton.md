---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
  - "T005"
title: "Foundation — ViewModel, Color Utility, View Skeleton"
phase: "Phase 0 - Foundation"
lane: "done"
assignee: "claude-opus"
agent: "claude-opus"
shell_pid: "36249"
review_status: "approved"
reviewed_by: "claude-opus"
dependencies: []
history:
  - timestamp: "2026-02-27T09:26:46Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-02-27T09:45:19Z"
    lane: "doing"
    agent: "claude-opus"
    shell_pid: "36249"
    action: "Started implementation via workflow command"
  - timestamp: "2026-02-27T10:00:00Z"
    lane: "for_review"
    agent: "claude-opus"
    action: "Implementation complete: MuscleGroupColors, MuscleGroupDot, CalendarViewModel, CalendarView, ContentView wiring. Build succeeds."
  - timestamp: "2026-02-27T10:15:00Z"
    lane: "done"
    agent: "claude-opus"
    action: "Review passed: Fixed GeometryReader layout bug (moved to outer level). All subtasks verified."
---

# Work Package Prompt: WP01 – Foundation — ViewModel, Color Utility, View Skeleton

## Objectives & Success Criteria

- Create `MuscleGroupColors.swift` utility that maps muscle group strings to distinct SwiftUI Colors.
- Create `MuscleGroupDot.swift` component — a small colored circle for calendar day cells.
- Create `CalendarViewModel.swift` with `@Observable`, all state properties, service dependencies, and method stubs.
- Create `CalendarView.swift` with split-view layout (scrollable calendar top, scrollable detail bottom), header with title and "Today" button.
- Wire `CalendarView` into `ContentView.swift` replacing the placeholder.
- **Success**: Calendar tab appears in bottom nav. The view renders with header, split layout, and empty content areas. MuscleGroupColors returns correct colors for all 8 mapped groups.

## Context & Constraints

- **Architecture**: MVVM with `@Observable` (iOS 17+). Views → ViewModels → Services → Repositories → SwiftData.
- **Constitution**: No third-party UI libs. Dark mode only. No ModelContext in ViewModel. NavigationStack (not NavigationView). SF Symbols for icons.
- **Design tokens**: All colors from `Reppo/Core/Extensions/DesignTokens.swift`. New muscle group colors extend the palette.
- **Existing patterns**: Follow `Reppo/Features/Exercise/` and `Reppo/Features/Workout/` for file organization.
- **Key docs**: `kitty-specs/008-calendar-tab/plan.md`, `kitty-specs/008-calendar-tab/research.md` (RQ-2 for colors, RQ-4 for split layout), `kitty-specs/008-calendar-tab/data-model.md`.

**Implementation command**: `spec-kitty implement WP01`

## Subtasks & Detailed Guidance

### Subtask T001 – Create MuscleGroupColors.swift

- **Purpose**: Provide a static color mapping from muscle group name strings to SwiftUI `Color` values. Used by `MuscleGroupDot` and potentially elsewhere.
- **File**: `Reppo/Core/Extensions/MuscleGroupColors.swift` (new file)
- **Parallel?**: Yes — independent utility, no dependencies.

**Steps**:
1. Create the file at `Reppo/Core/Extensions/MuscleGroupColors.swift`.
2. Define a struct `MuscleGroupColors` with a static function:
   ```swift
   static func color(for muscleGroup: String) -> Color
   ```
3. Implement a `switch` on `muscleGroup.lowercased()` matching these groups:

   | Muscle Group Strings | Color | Hex |
   |---------------------|-------|-----|
   | "chest", "pectorals" | Blue | #5B8DEF (use `Color.accent`) |
   | "back", "lats", "upper back" | Green | #5EC269 (use `Color.success`) |
   | "shoulders", "delts", "deltoids" | Gold | #D4A23A (use `Color.gold`) |
   | "legs", "quads", "quadriceps" | Red | #E05555 (use `Color.danger`) |
   | "biceps", "arms" | Purple | `Color(red: 0.608, green: 0.498, blue: 0.902)` |
   | "triceps" | Teal | `Color(red: 0.306, green: 0.804, blue: 0.769)` |
   | "core", "abs", "abdominals" | Orange | `Color(red: 0.878, green: 0.533, blue: 0.314)` |
   | "glutes", "hamstrings", "posterior chain" | Pink | `Color(red: 0.831, green: 0.420, blue: 0.620)` |

4. Default/fallback: return `Color.textTertiary` for any unmatched string.
5. Add a brief header comment referencing `research.md RQ-2`.

**Validation**:
- `MuscleGroupColors.color(for: "chest")` returns blue (accent).
- `MuscleGroupColors.color(for: "CHEST")` returns blue (case-insensitive).
- `MuscleGroupColors.color(for: "unknown")` returns `Color.textTertiary`.

---

### Subtask T002 – Create MuscleGroupDot.swift

- **Purpose**: Small colored circle indicator for calendar day cells. Shows the color for a specific muscle group.
- **File**: `Reppo/Features/Calendar/Views/Components/MuscleGroupDot.swift` (new file)
- **Parallel?**: Yes — depends only on `MuscleGroupColors`.

**Steps**:
1. Create directory structure: `Reppo/Features/Calendar/Views/Components/`.
2. Create the file with a simple SwiftUI view:
   ```swift
   struct MuscleGroupDot: View {
       let muscleGroup: String

       var body: some View {
           Circle()
               .fill(MuscleGroupColors.color(for: muscleGroup))
               .frame(width: 6, height: 6)
       }
   }
   ```
3. Keep it minimal — just a filled circle with the mapped color. Size 6pt diameter as per typical calendar dot patterns.

**Validation**:
- Renders as a small colored circle.
- Color matches the muscle group mapping.

---

### Subtask T003 – Create CalendarViewModel.swift

- **Purpose**: Central @Observable ViewModel for the Calendar tab. Holds all state, data dictionaries, and method stubs for data loading (implemented in WP02/WP03).
- **File**: `Reppo/Features/Calendar/ViewModels/CalendarViewModel.swift` (new file)
- **Parallel?**: No — T004 depends on this.

**Steps**:
1. Create directory: `Reppo/Features/Calendar/ViewModels/`.
2. Create the ViewModel as an `@Observable` class:

   ```swift
   import SwiftUI

   @Observable
   final class CalendarViewModel {
       // MARK: - State
       var selectedDate: Date?
       var calendarDotData: [Date: [String]] = [:]       // date → muscle group names
       var workoutsByDate: [Date: [Workout]] = [:]        // date → workouts
       var workoutDetails: [UUID: WorkoutDetail] = [:]    // workoutId → detail
       var isLoadingDots: Bool = false
       var isLoadingDetail: Bool = false
       var scrollToTodayTrigger: Bool = false

       // MARK: - Cache
       var exerciseCache: [UUID: Exercise] = [:]
       private var loadedDateRange: ClosedRange<Date>?

       // MARK: - Dependencies
       private let workoutService: WorkoutServiceProtocol
       private let setService: SetServiceProtocol
       private let exerciseService: ExerciseServiceProtocol
       private let statsService: StatsServiceProtocol

       init(
           workoutService: WorkoutServiceProtocol,
           setService: SetServiceProtocol,
           exerciseService: ExerciseServiceProtocol,
           statsService: StatsServiceProtocol
       ) {
           self.workoutService = workoutService
           self.setService = setService
           self.exerciseService = exerciseService
           self.statsService = statsService
       }
   }
   ```

3. Add the derived data structures as nested types or top-level structs in the same file:

   ```swift
   struct ExerciseGroup {
       let exercise: Exercise
       let sets: [WorkoutSet]
       let stats: ExerciseStats?
   }

   struct WorkoutDetail {
       let workout: Workout
       let exerciseGroups: [ExerciseGroup]
       let totalVolume: Double
       let exerciseCount: Int
       let setCount: Int
   }
   ```

4. Add method stubs (implementations come in WP02 and WP03):

   ```swift
   // MARK: - Data Loading (WP02)
   func loadDotsForVisibleRange(around date: Date) async { }
   func scrollToToday() { scrollToTodayTrigger.toggle() }

   // MARK: - Date Selection (WP03)
   func selectDate(_ date: Date) async { }
   ```

5. Add a helper to normalize dates (strip time component for dictionary keys):

   ```swift
   static func normalizeDate(_ date: Date) -> Date {
       Calendar.current.startOfDay(for: date)
   }
   ```

**Notes**:
- Use `WorkoutServiceProtocol`, `SetServiceProtocol`, `ExerciseServiceProtocol`, `StatsServiceProtocol` (protocol types) for DI, matching the existing pattern in the codebase.
- The `scrollToTodayTrigger` is a toggle that the view observes via `.onChange` to trigger `ScrollViewReader.scrollTo`.

**Validation**:
- ViewModel initializes with empty state.
- Dependencies are injected via initializer.
- Data structures compile correctly.

---

### Subtask T004 – Create CalendarView.swift

- **Purpose**: Main calendar screen with split-view layout. Header with "Calendar" title and "Today" button. Upper section for calendar grid (empty for now). Lower section for workout detail (empty for now).
- **File**: `Reppo/Features/Calendar/Views/CalendarView.swift` (new file)
- **Parallel?**: No — depends on T003 (ViewModel).

**Steps**:
1. Create directory: `Reppo/Features/Calendar/Views/`.
2. Create the view with this structure:

   ```swift
   import SwiftUI

   struct CalendarView: View {
       @State private var viewModel: CalendarViewModel

       init(workoutService: WorkoutServiceProtocol,
            setService: SetServiceProtocol,
            exerciseService: ExerciseServiceProtocol,
            statsService: StatsServiceProtocol) {
           _viewModel = State(initialValue: CalendarViewModel(
               workoutService: workoutService,
               setService: setService,
               exerciseService: exerciseService,
               statsService: statsService
           ))
       }

       var body: some View {
           NavigationStack {
               VStack(spacing: 0) {
                   // Upper: Calendar grid
                   calendarSection

                   // Divider
                   Rectangle()
                       .fill(Color.border)
                       .frame(height: 1)

                   // Lower: Workout detail
                   detailSection
               }
               .background(Color.bg)
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                   ToolbarItem(placement: .principal) {
                       Text("Calendar")
                           .font(.system(size: 17, weight: .semibold))
                           .foregroundStyle(Color.textPrimary)
                   }
                   ToolbarItem(placement: .topBarTrailing) {
                       Button {
                           viewModel.scrollToToday()
                       } label: {
                           Image(systemName: "calendar.badge.clock")
                               .foregroundStyle(Color.accent)
                       }
                   }
               }
           }
       }

       // MARK: - Sections

       @ViewBuilder
       private var calendarSection: some View {
           GeometryReader { geometry in
               ScrollView {
                   // Placeholder — WP02 will add LazyVStack of months
                   Text("Calendar Grid")
                       .foregroundStyle(Color.textTertiary)
                       .frame(maxWidth: .infinity, maxHeight: .infinity)
               }
               .frame(height: geometry.size.height * 0.55)
           }
       }

       @ViewBuilder
       private var detailSection: some View {
           ScrollView {
               // Placeholder — WP03 will add workout detail
               Text("Select a date")
                   .foregroundStyle(Color.textTertiary)
                   .frame(maxWidth: .infinity)
                   .padding(.top, 40)
           }
       }
   }
   ```

3. Use `GeometryReader` on the upper section to allocate ~55% of available height to the calendar.
4. The lower section fills the remaining space (no explicit height — fills naturally).
5. `NavigationStack` wraps everything for navigation support (ExerciseDetail push in WP03).
6. Use `Color.bg` background, `Color.border` for the divider.

**Notes**:
- The `GeometryReader` approach for split layout: wrap the upper `ScrollView` in a `GeometryReader` and set its `.frame(height:)` based on `geometry.size.height`. The lower `ScrollView` takes remaining space.
- The "Today" button uses `calendar.badge.clock` SF Symbol. Alternative: `"calendar"` or a custom label.
- Check how `ContentView.swift` currently initializes views — it uses `ServiceContainer` and `RepositoryContainer` from the environment. Follow the same pattern for injecting services into `CalendarView`.

**Validation**:
- View renders with header showing "Calendar" and a "Today" button.
- Split view visible with placeholder text in both sections.
- Background is `Color.bg` (dark).

---

### Subtask T005 – Wire CalendarView into ContentView

- **Purpose**: Replace the placeholder `CalendarPlaceholderView()` in `ContentView.swift` with the new `CalendarView`.
- **File**: `Reppo/App/ContentView.swift` (edit existing file)
- **Parallel?**: No — depends on T004.

**Steps**:
1. Open `Reppo/App/ContentView.swift`.
2. Find the line where `CalendarPlaceholderView()` is used in the `TabView` for the `.calendar` tab.
3. Replace it with `CalendarView(...)` passing the required service dependencies from `ServiceContainer`.
4. Check how other views in `ContentView` receive their dependencies — likely via `@Environment` or directly from a container. Follow the same pattern.

**Expected change** (approximate):
```swift
// Before:
CalendarPlaceholderView()
    .tabItem { ... }
    .tag(MainTab.calendar)

// After:
CalendarView(
    workoutService: serviceContainer.workoutService,
    setService: serviceContainer.setService,
    exerciseService: serviceContainer.exerciseService,
    statsService: serviceContainer.statsService
)
    .tabItem { ... }
    .tag(MainTab.calendar)
```

**Notes**:
- Check how `ServiceContainer` is accessed in `ContentView` — it may be via `@Environment`, `@State`, or a property. Match the existing pattern.
- If `CalendarPlaceholderView` is defined elsewhere, you can leave it in place (it won't be referenced anymore) or remove it if it's a simple placeholder.

**Validation**:
- App launches, calendar tab shows the new CalendarView with header and split layout.
- Other tabs still work correctly.
- No compiler errors.

---

## Risks & Mitigations

- **Service injection pattern**: Check how ContentView currently injects services into child views. The existing pattern in the codebase may use environment objects, direct property injection, or a container. Match it exactly.
- **Split layout proportions**: The 55/45 split may not feel right on all devices. The percentage is easy to adjust in CalendarView once the grid is populated in WP02.
- **MuscleGroupColors extensibility**: New muscle groups may be added by users. The fallback to `Color.textTertiary` handles unknown groups gracefully.

## Definition of Done Checklist

- [x] `MuscleGroupColors.swift` created with 8 color mappings + fallback
- [x] `MuscleGroupDot.swift` created as a colored circle component
- [x] `CalendarViewModel.swift` created with @Observable, state properties, service deps, method stubs
- [x] `CalendarView.swift` created with split-view layout, header, "Today" button
- [x] `CalendarView` wired into `ContentView.swift` replacing placeholder
- [x] App compiles without errors
- [x] Calendar tab appears in bottom nav and renders the new view
- [x] All files follow existing project naming and organization conventions

## Review Guidance

- Verify MuscleGroupColors has case-insensitive matching and correct fallback.
- Verify CalendarViewModel uses protocol types for service dependencies (not concrete classes).
- Verify CalendarView uses NavigationStack, not NavigationView.
- Verify all colors come from DesignTokens or the new MuscleGroupColors — no raw hex in views.
- Verify the split-view layout renders correctly on iPhone screen sizes.
- Check that ContentView wiring follows the existing dependency injection pattern.

## Activity Log

- 2026-02-27T09:26:46Z – system – lane=planned – Prompt created.
- 2026-02-27T09:45:19Z – claude-opus – shell_pid=36249 – lane=doing – Started implementation via workflow command
- 2026-02-27T10:00:00Z – claude-opus – lane=for_review – Implementation complete. Build succeeds.
- 2026-02-27T10:15:00Z – claude-opus – lane=done – Review passed: Fixed GeometryReader layout bug.
