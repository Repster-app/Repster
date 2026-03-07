---
work_package_id: "WP02"
subtasks:
  - "T006"
  - "T007"
  - "T008"
  - "T009"
  - "T010"
title: "Calendar Grid — Month Grids, Day Cells, Dots, Scrolling"
phase: "Phase 1 - Calendar Grid"
lane: "done"
assignee: "claude-opus"
agent: "claude-opus"
shell_pid: ""
review_status: "approved"
reviewed_by: "claude-opus"
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-27T09:26:46Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-02-27T10:20:00Z"
    lane: "doing"
    agent: "claude-opus"
    action: "Started implementation in worktree 008-calendar-tab-WP02"
  - timestamp: "2026-02-27T10:40:00Z"
    lane: "for_review"
    agent: "claude-opus"
    action: "Ready for review: CalendarMonthView, CalendarDayCell, dot data loading, Today scroll, incremental loading. Build succeeds."
  - timestamp: "2026-02-27T10:50:00Z"
    lane: "done"
    agent: "claude-opus"
    action: "Review passed: Made exerciseCache private, cached DateFormatters as static let. Zero blocking issues."
---

# Work Package Prompt: WP02 – Calendar Grid — Month Grids, Day Cells, Dots, Scrolling

## Objectives & Success Criteria

- Build vertically scrollable month grids with correct day layouts.
- Day cells show muscle group dots (max 3 + overflow), today highlighting (blue fill), and date selection.
- Implement data loading: fetch workouts for visible date range, derive muscle groups from the `Workout → WorkoutSet → Exercise.primaryMuscle` chain.
- "Today" button scrolls to the current month.
- Incremental loading fetches new months as user scrolls.
- **Success**: Calendar displays month grids. Dates with workouts show colored dots. Today is highlighted. "Today" button works. Tapping a date selects it visually.

## Context & Constraints

- **Depends on WP01**: CalendarView skeleton, CalendarViewModel with stubs, MuscleGroupDot component, MuscleGroupColors utility.
- **Architecture**: MVVM with `@Observable`. ViewModel calls services; never touches ModelContext.
- **Constitution**: No third-party libs. Use `Calendar.current` for date math. Minimum 44x44pt tap targets.
- **Design tokens**: `Color.accent` (#5B8DEF) for today fill and selection, `Color.bg` for screen background, `Color.bgCard` for card backgrounds, `Color.textPrimary`/`textSecondary`/`textTertiary` for text.
- **Performance**: Calendar must load within 200ms budget. Use `LazyVStack`/`LazyVGrid` for efficient rendering.
- **Key references**: `kitty-specs/008-calendar-tab/research.md` (RQ-1 for grid, RQ-3 for data loading), `kitty-specs/008-calendar-tab/data-model.md`.

**Existing APIs to use**:
- `WorkoutService.fetchWorkouts(for: ClosedRange<Date>) async throws -> [Workout]`
- `SetService.fetchExerciseIds(for: UUID) async throws -> Swift.Set<UUID>` (returns exercise IDs for a workout)
- `ExerciseService.fetchExercise(_ UUID) async throws -> Exercise?`

**Implementation command**: `spec-kitty implement WP02 --base WP01`

## Subtasks & Detailed Guidance

### Subtask T006 – Create CalendarMonthView.swift

- **Purpose**: Render a single month as a grid — month/year header, weekday labels row, and a 7-column `LazyVGrid` of day cells.
- **File**: `Reppo/Features/Calendar/Views/CalendarMonthView.swift` (new file)
- **Parallel?**: Can be developed alongside T007 (DayCell).

**Steps**:
1. Create the file with a struct:
   ```swift
   struct CalendarMonthView: View {
       let month: Date  // First day of the month (e.g., 2026-02-01)
       let calendarDotData: [Date: [String]]
       let selectedDate: Date?
       let today: Date
       let onDateTapped: (Date) -> Void
   }
   ```

2. **Month/year header**: Display "February 2026" at top-left using `DateFormatter` with format `"MMMM yyyy"`. Style: 17pt semibold, `textPrimary`.

3. **Weekday headers row**: Fixed HStack with 7 items: `["S", "M", "T", "W", "T", "F", "S"]` (or use locale-aware weekday symbols from `Calendar.current.veryShortWeekdaySymbols`). Style: 12pt medium, `textTertiary`. Use same grid column sizing.

4. **Day grid**: `LazyVGrid` with 7 flexible columns:
   ```swift
   let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

   LazyVGrid(columns: columns, spacing: 4) {
       // Leading empty cells for first weekday offset
       ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
           Color.clear.frame(height: 50)
       }
       // Day cells
       ForEach(daysInMonth, id: \.self) { date in
           CalendarDayCell(
               date: date,
               muscleGroups: calendarDotData[CalendarViewModel.normalizeDate(date)] ?? [],
               isToday: Calendar.current.isDate(date, inSameDayAs: today),
               isSelected: selectedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false,
               onTapped: { onDateTapped(date) }
           )
       }
   }
   ```

5. **Date math helpers** (can be computed properties or private functions):
   - `firstWeekdayOffset`: Number of empty cells before the 1st day. Calculated as `Calendar.current.component(.weekday, from: firstOfMonth) - 1` (for Sunday-start; adjust if locale uses Monday-start).
   - `daysInMonth`: Array of `Date` values for each day. Use `Calendar.current.range(of: .day, in: .month, for: month)` to get the day count, then generate dates.

6. **ID for ScrollViewReader**: Set `.id(monthId)` on the outer container where `monthId` is a string like `"2026-02"` derived from the month date.

**Edge cases**:
- February in leap years (29 days) — handled automatically by `Calendar.current`.
- Months starting on Sunday (0 offset) — no empty cells needed.
- Months starting on Saturday (6 offset) — 6 empty cells before the 1st.

**Validation**:
- Month header shows correct month name and year.
- Days are laid out in correct grid positions (1st falls on correct weekday).
- Grid has 7 columns with consistent cell sizing.

---

### Subtask T007 – Create CalendarDayCell.swift

- **Purpose**: Individual day cell showing the day number, today highlight, selection state, and up to 3 muscle group dots with overflow indicator.
- **File**: `Reppo/Features/Calendar/Views/CalendarDayCell.swift` (new file)
- **Parallel?**: Can be developed alongside T006 (MonthView).

**Steps**:
1. Create the view:
   ```swift
   struct CalendarDayCell: View {
       let date: Date
       let muscleGroups: [String]
       let isToday: Bool
       let isSelected: Bool
       let onTapped: () -> Void
   }
   ```

2. **Layout** (vertical stack):
   ```
   VStack(spacing: 2) {
       // Day number with optional highlight
       dayNumberView

       // Muscle group dots (max 3 + overflow)
       dotsView
   }
   .frame(height: 50)  // Ensures minimum 44pt tap target
   .contentShape(Rectangle())  // Full cell is tappable
   .onTapGesture { onTapped() }
   ```

3. **Day number view**:
   - Default: `Text("\(dayNumber)")` in 14pt regular, `textPrimary`.
   - **Today**: Blue filled circle behind the number. `Text("\(dayNumber)")` in white, 14pt semibold, overlaid on a `Circle().fill(Color.accent)` sized ~30pt.
   - **Selected (not today)**: Subtle highlight — `Circle().stroke(Color.accent, lineWidth: 1.5)` behind the number, or `bgHover` fill.
   - Extract the day number: `Calendar.current.component(.day, from: date)`.

4. **Dots view**:
   - If `muscleGroups.isEmpty`: no dots (empty space).
   - If `muscleGroups.count <= 3`: Show `HStack(spacing: 2)` of `MuscleGroupDot(muscleGroup:)` for each.
   - If `muscleGroups.count > 3`: Show first 3 dots + a gray overflow indicator.
     ```swift
     HStack(spacing: 2) {
         ForEach(muscleGroups.prefix(3), id: \.self) { group in
             MuscleGroupDot(muscleGroup: group)
         }
         if muscleGroups.count > 3 {
             Text("+\(muscleGroups.count - 3)")
                 .font(.system(size: 7, weight: .medium))
                 .foregroundStyle(Color.textTertiary)
         }
     }
     ```

5. **Sizing**: Each cell should be at least 44x44pt (minimum tap target per constitution). The 50pt height + flexible width from the grid ensures this.

**Edge cases**:
- Date that is both today AND selected: Show today styling (blue fill takes priority).
- Date with no muscle groups but has a workout: dots area is empty (this is fine — dots only show muscle groups).

**Validation**:
- Day numbers display correctly (1-28/29/30/31).
- Today shows blue filled circle with white text.
- Selected date shows visual distinction.
- Dots render correctly: 0, 1, 2, 3, or 3 + overflow.
- Cell is tappable across its full area.

---

### Subtask T008 – Implement Dot Data Loading in CalendarViewModel

- **Purpose**: Implement the `loadDotsForVisibleRange()` method that fetches workouts for a date range, derives muscle groups via the `Workout → WorkoutSet exerciseIds → Exercise.primaryMuscle` chain, and populates `calendarDotData` and `workoutsByDate`.
- **File**: `Reppo/Features/Calendar/ViewModels/CalendarViewModel.swift` (edit existing stub from WP01)
- **Parallel?**: No — core ViewModel logic.

**Steps**:
1. Implement `loadDotsForVisibleRange(around date: Date)`:

   ```swift
   func loadDotsForVisibleRange(around date: Date) async {
       isLoadingDots = true
       defer { isLoadingDots = false }

       let calendar = Calendar.current

       // Compute range: month of `date` ± 1 month buffer
       guard let startOfPrevMonth = calendar.date(byAdding: .month, value: -1, to: calendar.startOfMonth(for: date)),
             let endOfNextMonth = calendar.date(byAdding: .month, value: 2, to: calendar.startOfMonth(for: date))
       else { return }

       let dateRange = startOfPrevMonth...endOfNextMonth

       // Skip if already loaded for this range
       if let loaded = loadedDateRange, loaded.contains(dateRange.lowerBound) && loaded.contains(dateRange.upperBound) {
           return
       }

       do {
           // 1. Fetch workouts for range
           let workouts = try await workoutService.fetchWorkouts(for: dateRange)

           // 2. Group workouts by normalized date
           var dateWorkouts: [Date: [Workout]] = [:]
           for workout in workouts {
               let key = Self.normalizeDate(workout.date)
               dateWorkouts[key, default: []].append(workout)
           }

           // 3. For each workout, get exercise IDs and derive muscle groups
           var dotData: [Date: [String]] = [:]
           for (date, dateWorkoutList) in dateWorkouts {
               var muscleGroups: [String] = []
               for workout in dateWorkoutList {
                   let exerciseIds = try await setService.fetchExerciseIds(for: workout.id)
                   for exerciseId in exerciseIds {
                       let exercise = try await cachedExercise(exerciseId)
                       if let muscle = exercise?.primaryMuscle, !muscleGroups.contains(muscle) {
                           muscleGroups.append(muscle)
                       }
                   }
               }
               dotData[date] = muscleGroups
           }

           // 4. Merge into existing data (don't overwrite data for months already loaded)
           for (date, groups) in dotData {
               calendarDotData[date] = groups
           }
           for (date, workoutList) in dateWorkouts {
               workoutsByDate[date] = workoutList
           }

           // 5. Update loaded range
           if let existing = loadedDateRange {
               loadedDateRange = min(existing.lowerBound, dateRange.lowerBound)...max(existing.upperBound, dateRange.upperBound)
           } else {
               loadedDateRange = dateRange
           }
       } catch {
           print("CalendarViewModel: Failed to load dot data: \(error)")
       }
   }
   ```

2. Add a helper for exercise caching:
   ```swift
   private func cachedExercise(_ id: UUID) async throws -> Exercise? {
       if let cached = exerciseCache[id] {
           return cached
       }
       let exercise = try await exerciseService.fetchExercise(id)
       if let exercise {
           exerciseCache[id] = exercise
       }
       return exercise
   }
   ```

3. Add a `Calendar` extension helper for `startOfMonth`:
   ```swift
   extension Calendar {
       func startOfMonth(for date: Date) -> Date {
           let components = dateComponents([.year, .month], from: date)
           return self.date(from: components) ?? date
       }
   }
   ```
   Place this in the same file or in `Reppo/Core/Extensions/` if preferred.

**Performance notes**:
- The exercise cache (`[UUID: Exercise]`) avoids re-fetching the same exercise for every workout. Exercises are relatively static — the cache is safe for the calendar session lifetime.
- For 3 months × ~30 workouts = ~90 workout fetch calls for exercise IDs. Each call is lightweight (returns `Set<UUID>`).
- Typical user has ~50 unique exercises total, so the cache stays small.

**Validation**:
- After loading, `calendarDotData` contains entries for dates that have workouts.
- Each date's muscle group array contains unique strings (no duplicates).
- `workoutsByDate` is correctly grouped.
- Cache prevents duplicate exercise fetches.

---

### Subtask T009 – Implement "Today" Button Scroll-to Behavior

- **Purpose**: When user taps "Today" in the toolbar, the calendar scrolls to show the current month.
- **File**: `Reppo/Features/Calendar/Views/CalendarView.swift` (edit — update calendar section)
- **Parallel?**: No — requires ScrollViewReader integration.

**Steps**:
1. Wrap the upper calendar `ScrollView` in a `ScrollViewReader`:
   ```swift
   ScrollViewReader { proxy in
       ScrollView {
           LazyVStack(spacing: 16) {
               ForEach(months, id: \.self) { month in
                   CalendarMonthView(
                       month: month,
                       calendarDotData: viewModel.calendarDotData,
                       selectedDate: viewModel.selectedDate,
                       today: Date(),
                       onDateTapped: { date in
                           Task { await viewModel.selectDate(date) }
                       }
                   )
                   .id(monthId(for: month))
               }
           }
           .padding(.horizontal, 16)
       }
       .onChange(of: viewModel.scrollToTodayTrigger) { _, _ in
           withAnimation {
               proxy.scrollTo(monthId(for: Calendar.current.startOfMonth(for: Date())), anchor: .top)
           }
       }
   }
   ```

2. Generate the `months` array — a computed property or state that produces `Date` values for first-of-month for a range of months (e.g., 12 months back to 3 months forward):
   ```swift
   private var months: [Date] {
       let calendar = Calendar.current
       let today = Date()
       var result: [Date] = []
       for offset in -12...3 {
           if let month = calendar.date(byAdding: .month, value: offset, to: calendar.startOfMonth(for: today)) {
               result.append(month)
           }
       }
       return result
   }
   ```

3. Helper for month ID string:
   ```swift
   private func monthId(for date: Date) -> String {
       let formatter = DateFormatter()
       formatter.dateFormat = "yyyy-MM"
       return formatter.string(from: date)
   }
   ```

4. On `CalendarView.onAppear`, scroll to the current month and trigger initial data load:
   ```swift
   .task {
       await viewModel.loadDotsForVisibleRange(around: Date())
   }
   ```

**Notes**:
- The months array generates 12 past months + current + 3 future = 16 months. This is enough for initial display. If user scrolls beyond this, T010 handles loading more.
- Using `.id(monthId)` on each `CalendarMonthView` enables `ScrollViewReader` targeting.
- The initial scroll to today should happen immediately without animation (use `.onAppear` or `DispatchQueue.main.async`).

**Validation**:
- "Today" button scrolls calendar to show the current month.
- Scroll animation is smooth.
- Calendar shows ~16 months initially.

---

### Subtask T010 – Implement Scroll-Based Incremental Data Loading

- **Purpose**: As the user scrolls the calendar to see new months, detect the visible range and fetch dot data for newly visible months that haven't been loaded yet.
- **File**: `Reppo/Features/Calendar/Views/CalendarView.swift` + `CalendarViewModel.swift` (edit existing)
- **Parallel?**: No — builds on T008 and T009.

**Steps**:
1. Use `onAppear` on `CalendarMonthView` to detect when a month becomes visible:
   ```swift
   CalendarMonthView(...)
       .id(monthId(for: month))
       .onAppear {
           Task {
               await viewModel.loadDotsForVisibleRange(around: month)
           }
       }
   ```

2. The `loadDotsForVisibleRange` method (from T008) already handles:
   - Computing a ±1 month buffer around the target date.
   - Skipping if the range is already loaded (`loadedDateRange` check).
   - Merging new data into existing dictionaries.

3. **Expand the months array** if the user scrolls to the edges. Options:
   - **Simple approach**: Generate a generous initial range (24 months back, 6 forward) so most users never hit the edge. This avoids dynamic month array management.
   - **Dynamic approach**: Track scroll position and append months when near edges. More complex but handles power users with years of data.

   **Recommended for v1**: Use the simple approach with 24+6 = 30 months. A user with 2 years of workout data is well covered. Extend later if needed.

4. Update the `months` computed property:
   ```swift
   private var months: [Date] {
       let calendar = Calendar.current
       let today = Date()
       var result: [Date] = []
       for offset in -24...6 {
           if let month = calendar.date(byAdding: .month, value: offset, to: calendar.startOfMonth(for: today)) {
               result.append(month)
           }
       }
       return result
   }
   ```

**Performance notes**:
- `onAppear` on `LazyVStack` children fires as they enter the visible area. This is the right trigger for lazy loading.
- The `loadedDateRange` check in the ViewModel prevents redundant fetches.
- LazyVStack only instantiates views for visible months, so 30 months in the array doesn't create 30 views upfront.

**Validation**:
- Scrolling up/down loads dot data for newly visible months.
- Previously loaded months retain their dot data (no flicker).
- No redundant network/database calls for already-loaded ranges.
- Scrolling remains smooth at 60 FPS.

---

## Risks & Mitigations

- **Date math bugs**: Month boundaries, leap years, different locale start-of-week. Use `Calendar.current` consistently — it handles all of these. Test with February and months starting on different weekdays.
- **Scroll performance**: `LazyVStack` + `LazyVGrid` should handle 30 months efficiently. If performance issues arise, reduce the initial month range or add debouncing to `onAppear` loading.
- **First weekday locale**: `Calendar.current` may return Monday as first weekday in some locales. For consistency, consider hardcoding Sunday-start or using `calendar.firstWeekday`.
- **Exercise cache staleness**: If a user edits an exercise's `primaryMuscle` and then switches to the calendar, the cache may have stale data. This is acceptable for v1 — the cache is cleared on view appear or can be invalidated explicitly.

## Definition of Done Checklist

- [x] `CalendarMonthView.swift` renders month header + weekday labels + 7-col grid of days
- [x] `CalendarDayCell.swift` shows day number, today highlight (blue fill), selection state, muscle group dots (max 3 + overflow)
- [x] `CalendarViewModel.loadDotsForVisibleRange()` fetches and populates dot data correctly
- [x] "Today" button scrolls to current month
- [x] Scrolling to new months triggers incremental data loading
- [x] No duplicate exercise fetches (cache working)
- [x] Day cells have minimum 44x44pt tap target
- [x] All colors from DesignTokens + MuscleGroupColors — no raw hex in views
- [x] App compiles without errors

## Review Guidance

- Verify date math: check that day 1 of each month falls on the correct weekday column.
- Verify the `onAppear`-based loading doesn't cause excessive API calls (check the `loadedDateRange` guard).
- Verify today highlighting: blue filled circle with white text, correct date.
- Verify dot overflow: 3 dots + "+N" text when >3 muscle groups.
- Verify scroll-to-today animates smoothly and lands on the correct month.
- Check that `LazyVStack` is used (not `VStack`) for the month list — critical for performance.

## Activity Log

- 2026-02-27T09:26:46Z – system – lane=planned – Prompt created.
- 2026-02-27T10:20:00Z – claude-opus – lane=doing – Started implementation in worktree.
- 2026-02-27T10:40:00Z – claude-opus – lane=for_review – Implementation complete. Build succeeds.
- 2026-02-27T10:50:00Z – claude-opus – lane=done – Review passed: exerciseCache private, static DateFormatters.
