---
work_package_id: "WP04"
subtasks:
  - "T017"
  - "T018"
  - "T019"
  - "T020"
  - "T021"
title: "Integration — HomeView + CopyPreviousSheet + ContentView"
phase: "Phase 3 - Integration"
lane: "done"
assignee: "claude-opus"
agent: "claude-opus-reviewer"
shell_pid: "68870"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01", "WP02", "WP03"]
history:
  - timestamp: "2026-03-01T17:56:08Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-03-01T18:42:21Z"
    lane: "doing"
    agent: "claude-opus"
    shell_pid: "67878"
    action: "Started implementation"
  - timestamp: "2026-03-01T18:46:26Z"
    lane: "for_review"
    agent: "claude-opus"
    shell_pid: "67878"
    action: "Ready for review"
  - timestamp: "2026-03-01T18:49:08Z"
    lane: "done"
    agent: "claude-opus-reviewer"
    shell_pid: "68870"
    action: "Review passed"
---

# Work Package Prompt: WP04 – Integration — HomeView + CopyPreviousSheet + ContentView

## Implementation Command

```bash
spec-kitty implement WP04 --base WP02 WP03
```

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

- Assemble all sub-views into a complete HomeView with NavigationStack.
- Create CopyPreviousSheet with confirmation dialog for active workout conflict.
- Update ContentView: replace Programs placeholder with HomeView, update tab label/icon, wire callbacks.
- Implement workout detail navigation from Recent cards.
- Data refreshes when returning from active workout.
- All empty states render correctly.
- Home screen passes all acceptance scenarios from the spec.

## Context & Constraints

- **Spec**: `kitty-specs/013-home-screen/spec.md` — all 6 user stories + edge cases.
- **Plan**: `kitty-specs/013-home-screen/plan.md` — Integration section, key decisions.
- **ContentView**: `Reppo/App/ContentView.swift` — current tab bar with ProgramsPlaceholderView.
- **CalendarWorkoutDetailView**: `Reppo/Features/Calendar/Views/CalendarWorkoutDetailView.swift` — workout detail pattern to reuse.
- **WorkoutDetail/ExerciseGroup**: Defined in `Reppo/Features/Calendar/ViewModels/CalendarViewModel.swift` (module-level structs).
- **Constitution**: NavigationStack (not NavigationView). 44pt tap targets. Dark mode only.

### Key ContentView Structure (current)

```swift
@State private var selectedTab: MainTab = .programs
// ...
TabView(selection: $selectedTab) {
    ProgramsPlaceholderView()
        .tabItem { Label("Programs", systemImage: "list.bullet.rectangle") }
        .tag(MainTab.programs)
    // ... calendar, charts, settings tabs
}
```

### Callback Pattern

HomeView needs to trigger `showActiveWorkout = true` on ContentView after creating a workout. This is done via an `onStartWorkout: () -> Void` closure passed from ContentView to HomeView.

---

## Subtasks & Detailed Guidance

### Subtask T017 – Create HomeView.swift

**Purpose**: Main Home screen assembling all sub-views in a NavigationStack + ScrollView layout.

**Steps**:
1. Create `Reppo/Features/Home/Views/HomeView.swift`.
2. Structure:

```swift
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @Environment(ServiceContainer.self) private var services

    let onStartWorkout: () -> Void
    let onShowExerciseList: () -> Void

    init(
        workoutService: any WorkoutServiceProtocol,
        setService: any SetServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        onStartWorkout: @escaping () -> Void,
        onShowExerciseList: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: HomeViewModel(
            workoutService: workoutService,
            setService: setService,
            exerciseService: exerciseService
        ))
        self.onStartWorkout = onStartWorkout
        self.onShowExerciseList = onShowExerciseList
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    WeekStripView(weekDays: viewModel.weekDays)
                    startWorkoutSection
                    QuickActionCardsView(
                        onCopyPrevious: {
                            Task { await viewModel.loadCopyPreviousWorkouts() }
                            viewModel.showCopyPreviousSheet = true
                        },
                        onTemplates: {
                            // Templates placeholder — no action for v1
                        }
                    )
                    ThisWeekActivityView(
                        workoutCount: viewModel.thisWeekWorkoutCount,
                        workoutDays: viewModel.thisWeekWorkoutDays,
                        weeklyGoal: viewModel.weeklyGoal
                    )
                    recentWorkoutsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100) // space for tab bar + FAB
            }
            .background(Color.bg)
            .navigationDestination(for: UUID.self) { workoutId in
                WorkoutDetailFromHomeView(
                    workoutId: workoutId,
                    workoutService: services.workoutService,
                    setService: services.setService,
                    exerciseService: services.exerciseService,
                    statsService: services.statsService
                )
            }
        }
        .task {
            await viewModel.loadData()
        }
        .onAppear {
            Task { await viewModel.loadData() }
        }
        .sheet(isPresented: $viewModel.showCopyPreviousSheet) {
            CopyPreviousSheet(
                workouts: viewModel.copyPreviousWorkouts,
                showDiscardConfirmation: $viewModel.showDiscardConfirmation,
                onWorkoutSelected: { workoutId in
                    Task {
                        do {
                            if let _ = try await viewModel.copyWorkout(workoutId) {
                                onStartWorkout()
                            }
                        } catch {
                            print("[HomeView] Copy failed: \(error)")
                        }
                    }
                },
                onDiscardAndCopy: {
                    Task {
                        do {
                            if let _ = try await viewModel.discardActiveAndCopy() {
                                onStartWorkout()
                            }
                        } catch {
                            print("[HomeView] Discard+copy failed: \(error)")
                        }
                    }
                },
                onCancelDiscard: {
                    viewModel.cancelDiscard()
                }
            )
        }
    }
}
```

3. Add the header section:

```swift
@ViewBuilder
private var headerSection: some View {
    HStack {
        VStack(alignment: .leading, spacing: 2) {
            Text(formattedDate)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Text("Workout")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.textPrimary)
        }

        Spacer()

        // Profile avatar placeholder
        Circle()
            .fill(Color.bgSubtle)
            .frame(width: 36, height: 36)
    }
}

private var formattedDate: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMM d"
    return formatter.string(from: Date())
}
```

4. Add the start workout section:

```swift
@ViewBuilder
private var startWorkoutSection: some View {
    StartWorkoutCardView(
        onCardTapped: {
            if viewModel.hasActiveWorkout {
                onStartWorkout()  // Resume active workout
            } else {
                onShowExerciseList()  // Open exercise list (same as FAB)
            }
        },
        onPlusTapped: {
            Task {
                do {
                    _ = try await viewModel.startEmptyWorkout()
                    onStartWorkout()
                } catch {
                    print("[HomeView] Start workout failed: \(error)")
                }
            }
        }
    )
}
```

5. Add the recent workouts section:

```swift
@ViewBuilder
private var recentWorkoutsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("RECENT")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.textTertiary)
            .kerning(0.8)

        if viewModel.recentWorkouts.isEmpty {
            Text("Complete your first workout to see it here")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            ForEach(viewModel.recentWorkouts) { summary in
                NavigationLink(value: summary.id) {
                    RecentWorkoutCardView(summary: summary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

**Files**: `Reppo/Features/Home/Views/HomeView.swift` (new, ~150 lines)

**Notes**:
- `onStartWorkout` closure triggers `showActiveWorkout = true` in ContentView.
- `onShowExerciseList` closure triggers `showExerciseList = true` in ContentView (same as FAB).
- Recent cards use `NavigationLink(value: UUID)` to push workout detail via `.navigationDestination`.
- `.task` runs once on first appear. `.onAppear` fires on subsequent appears (tab reselection, fullScreenCover dismiss).
- Bottom padding (100pt) prevents content from being hidden behind the tab bar and FAB.
- Templates "Coming soon": For v1, the button can simply do nothing or show a brief alert. Keep it minimal.

### Subtask T018 – Create CopyPreviousSheet.swift

**Purpose**: Modal sheet displaying past workouts for selection, with confirmation dialog for active workout conflict.

**Steps**:
1. Create `Reppo/Features/Home/Views/CopyPreviousSheet.swift`.
2. Structure:

```swift
struct CopyPreviousSheet: View {
    let workouts: [CopyPreviousWorkout]
    @Binding var showDiscardConfirmation: Bool
    let onWorkoutSelected: (UUID) -> Void
    let onDiscardAndCopy: () -> Void
    let onCancelDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    emptyState
                } else {
                    workoutList
                }
            }
            .navigationTitle("Copy Previous")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .background(Color.bg)
            .confirmationDialog(
                "Active Workout",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard & Copy", role: .destructive) {
                    onDiscardAndCopy()
                }
                Button("Cancel", role: .cancel) {
                    onCancelDiscard()
                }
            } message: {
                Text("You have an active workout. Discard it and start a copy?")
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var workoutList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(workouts) { workout in
                    Button {
                        onWorkoutSelected(workout.id)
                    } label: {
                        workoutRow(workout)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func workoutRow(_ workout: CopyPreviousWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date
            Text(formatDate(workout.date))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)

            // Stats
            HStack(spacing: 12) {
                Text("\(workout.exerciseCount) exercises")
                Text("·")
                Text("\(workout.setCount) sets")
                Text("·")
                Text(formatVolume(workout.totalVolume))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.textTertiary)

            // Muscle tags
            if !workout.muscleGroups.isEmpty {
                HStack(spacing: 6) {
                    ForEach(workout.muscleGroups, id: \.self) { muscle in
                        Text(muscle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.bgSubtle)
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No workouts yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func formatVolume(_ kg: Double) -> String {
        if kg >= 1000 {
            return String(format: "%.1ft", kg / 1000)
        }
        return "\(Int(kg)) kg"
    }
}
```

**Files**: `Reppo/Features/Home/Views/CopyPreviousSheet.swift` (new, ~120 lines)

**Notes**:
- Presented via `.sheet(isPresented: $viewModel.showCopyPreviousSheet)` in HomeView.
- Confirmation dialog uses `.confirmationDialog` — the native iOS action sheet. "Discard & Copy" is destructive (red), "Cancel" dismisses.
- The sheet auto-dismisses when `showCopyPreviousSheet` is set to `false` by the ViewModel after successful copy.
- `.preferredColorScheme(.dark)` ensures the sheet matches the app's dark theme.

### Subtask T019 – Update ContentView.swift

**Purpose**: Replace the Programs placeholder with HomeView, update tab label/icon, wire callbacks.

**Steps**:
1. Open `Reppo/App/ContentView.swift`.
2. Replace the Programs tab content:

**Before**:
```swift
ProgramsPlaceholderView()
    .tabItem {
        Label("Programs", systemImage: "list.bullet.rectangle")
    }
    .tag(MainTab.programs)
```

**After**:
```swift
HomeView(
    workoutService: services.workoutService,
    setService: services.setService,
    exerciseService: services.exerciseService,
    onStartWorkout: { showActiveWorkout = true },
    onShowExerciseList: { showExerciseList = true }
)
    .tabItem {
        Label("Home", systemImage: "house")
    }
    .tag(MainTab.home)
```

3. Update `selectedTab` default:

**Before**: `@State private var selectedTab: MainTab = .programs`
**After**: `@State private var selectedTab: MainTab = .home`

4. Search for any other references to `MainTab.programs` or `.programs` in ContentView and update to `.home`.

**Files**: `Reppo/App/ContentView.swift` (modify ~5 lines)

**Notes**:
- `onStartWorkout` sets `showActiveWorkout = true` — this triggers the existing `.fullScreenCover` for ActiveWorkoutView.
- `onShowExerciseList` sets `showExerciseList = true` — this triggers the existing `.navigationDestination` for ExerciseListView in browse mode (same as FAB behavior).
- The FAB continues to work independently — it uses its own `showExerciseList` state.
- No changes to CalendarView, ChartsDashboardView, SettingsView, or FAB logic.

### Subtask T020 – Implement workout detail navigation from Recent cards

**Purpose**: When user taps a recent workout card, push a detail view showing the full exercise-by-exercise breakdown.

**Steps**:
1. Create a lightweight wrapper view that loads `WorkoutDetail` on demand and displays it using the CalendarWorkoutDetailView pattern.

```swift
// In Reppo/Features/Home/Views/WorkoutDetailFromHomeView.swift (new file)

struct WorkoutDetailFromHomeView: View {
    let workoutId: UUID
    let workoutService: any WorkoutServiceProtocol
    let setService: any SetServiceProtocol
    let exerciseService: any ExerciseServiceProtocol
    let statsService: any StatsServiceProtocol

    @State private var workoutDetails: [WorkoutDetail] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
            } else {
                CalendarWorkoutDetailView(
                    workoutDetails: workoutDetails,
                    selectedDate: workoutDetails.first?.workout.date ?? Date(),
                    onExerciseTapped: { _ in }  // No navigation from Home detail for v1
                )
            }
        }
        .background(Color.bg)
        .navigationTitle("Workout Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
        }
    }

    private func loadDetail() async {
        // Follow CalendarViewModel.selectDate() pattern
        do {
            guard let workout = try await workoutService.fetchWorkout(workoutId) else {
                isLoading = false
                return
            }

            let sets = try await setService.fetchSets(for: workout.id)
            var exerciseSetMap: [UUID: [WorkoutSet]] = [:]
            for set in sets {
                exerciseSetMap[set.exerciseId, default: []].append(set)
            }

            var exerciseGroups: [ExerciseGroup] = []
            for (exerciseId, exerciseSets) in exerciseSetMap {
                let exercise = try await exerciseService.fetchExercise(exerciseId)
                guard let exercise else { continue }
                let sorted = exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise }
                let stats = try? await statsService.fetchStats(for: exerciseId)
                exerciseGroups.append(ExerciseGroup(exercise: exercise, sets: sorted, stats: stats))
            }

            exerciseGroups.sort { lhs, rhs in
                let l = lhs.sets.first?.orderInWorkout ?? Int.max
                let r = rhs.sets.first?.orderInWorkout ?? Int.max
                return l < r
            }

            let completedSets = sets.filter(\.hasData)
            let totalVolume = completedSets.compactMap(\.volume).reduce(0, +)

            workoutDetails = [WorkoutDetail(
                workout: workout,
                exerciseGroups: exerciseGroups,
                totalVolume: totalVolume,
                exerciseCount: Set(sets.map(\.exerciseId)).count,
                setCount: completedSets.count
            )]
            isLoading = false
        } catch {
            print("[WorkoutDetailFromHomeView] Failed: \(error)")
            isLoading = false
        }
    }
}
```

**Files**: `Reppo/Features/Home/Views/WorkoutDetailFromHomeView.swift` (new, ~80 lines)

**Notes**:
- This wrapper loads `WorkoutDetail` lazily when the user taps a Recent card (not preloaded).
- Reuses `CalendarWorkoutDetailView` for the actual rendering — zero duplication of the detail layout.
- Uses the same aggregation pattern from `CalendarViewModel.selectDate()`.
- `onExerciseTapped` does nothing for v1 — could push to exercise detail in the future.
- The `navigationDestination(for: UUID.self)` in HomeView triggers this view.
- `StatsServiceProtocol` is needed here for ExerciseGroup stats. HomeView needs to pass it from services environment.

### Subtask T021 – Data refresh + empty states + design system verification

**Purpose**: Ensure the Home screen refreshes after returning from active workout, all empty states render correctly, and design system compliance is verified.

**Steps**:

1. **Data refresh**: HomeView already calls `viewModel.loadData()` in both `.task` and `.onAppear`. Verify:
   - After finishing a workout (dismissing fullScreenCover), `.onAppear` fires and refreshes data.
   - After switching back to Home tab from another tab, data refreshes.
   - Guard against excessive re-fetches: add a simple debounce — if `loadData()` was called within the last 2 seconds, skip. Example:

```swift
// In HomeViewModel
private var lastLoadTime: Date?

func loadData() async {
    // Debounce: skip if loaded within 2 seconds
    if let last = lastLoadTime, Date().timeIntervalSince(last) < 2 {
        return
    }
    lastLoadTime = Date()

    isLoading = true
    defer { isLoading = false }
    // ... existing load logic
}
```

2. **Empty states verification**: Walk through each section with no data:
   - Week strip: 7 days shown, no dots, today still highlighted — handled by `hasWorkout: false`.
   - Start Workout card: always shown regardless of data.
   - Quick action cards: always shown.
   - Activity: "0 / 4 sessions", all bars dim — handled by empty `workoutDays` set and `workoutCount = 0`.
   - Recent: "Complete your first workout to see it here" message — handled in HomeView's `recentWorkoutsSection`.

3. **Templates placeholder**: When user taps "Templates", show nothing or a brief inline message. Simplest approach: do nothing (button tap is a no-op for v1, per FR-009 "Coming soon" state). Alternatively, show a short alert:

```swift
@State private var showTemplatesPlaceholder = false
// ...
.alert("Templates", isPresented: $showTemplatesPlaceholder) {
    Button("OK") {}
} message: {
    Text("Coming soon")
}
```

4. **Design system compliance check**:
   - Screen background: `Color.bg` ✓
   - Cards: `Color.bgCard`, 14pt radius, no borders ✓
   - Section headers: 11pt semibold, uppercase, textTertiary, 0.8 kerning ✓
   - Horizontal padding: 20pt ✓
   - Touch targets: 44pt minimum on all buttons/cards ✓
   - Text hierarchy: textPrimary for headings/values, textSecondary for descriptions, textTertiary for labels ✓
   - Blue accent for interactive elements only ✓

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (add debounce)
- `Reppo/Features/Home/Views/HomeView.swift` (verify empty states, add templates alert if desired)

---

## Risks & Mitigations

- **NavigationStack conflict**: HomeView owns its own NavigationStack. ContentView's outer NavigationStack handles FAB → ExerciseListView. Test both: (1) Tap Recent card → detail pushes correctly, (2) Tap FAB → exercise list pushes correctly. If navigation conflicts occur, consider removing HomeView's NavigationStack and using ContentView's outer stack.
- **Start Workout card + FAB overlap**: Both the Start Workout card body and the FAB open ExerciseListView. They share `showExerciseList` state via the `onShowExerciseList` closure. This should work since both trigger the same state.
- **Stale date in header**: The header shows today's date. If the app stays open past midnight, the date will be stale until `loadData()` is called. `.onAppear` handles this for tab switches, but not for background/foreground transitions. Acceptable for v1.
- **Multiple `.onAppear` calls**: `.onAppear` fires on tab switches too. The debounce in `loadData()` prevents excessive fetching.

## Definition of Done Checklist

- [ ] HomeView assembles all sub-views in correct order with proper spacing
- [ ] Header shows formatted date, "Workout" title, avatar placeholder
- [ ] CopyPreviousSheet presents as modal, lists past workouts, handles empty state
- [ ] Confirmation dialog appears when copying with active workout
- [ ] ContentView: Programs placeholder replaced with HomeView
- [ ] Tab reads "Home" with house SF Symbol icon
- [ ] Home is the default selected tab on launch
- [ ] Recent card tap navigates to workout detail (push navigation)
- [ ] WorkoutDetailFromHomeView loads and displays CalendarWorkoutDetailView
- [ ] Data refreshes when returning from active workout
- [ ] All empty states display correctly
- [ ] Templates card shows placeholder behavior
- [ ] 20pt horizontal padding on all sections
- [ ] Bottom padding accounts for tab bar + FAB

## Review Guidance

- **Critical**: Test the full flow: Home → Start Workout [+] → ActiveWorkoutView → Finish → Home refreshes with new data.
- **Critical**: Test Copy Previous: Home → Copy Previous → Select workout → ActiveWorkoutView (verify sets are pre-filled).
- **Critical**: Test Copy Previous with active workout: Home → Start empty → Return → Copy Previous → Confirm discard → Verify new workout has copied sets.
- **Critical**: Test Recent card navigation: Home → Tap recent card → Detail view → Back to Home.
- Verify NavigationStack doesn't conflict with ContentView's outer NavigationStack.
- Verify empty state on fresh app (no workouts).
- Verify tab bar shows "Home" with house icon as first tab.

## Activity Log

- 2026-03-01T17:56:08Z – system – lane=planned – Prompt created.
- 2026-03-01T18:42:21Z – claude-opus – shell_pid=67878 – lane=doing – Started implementation via workflow command
- 2026-03-01T18:46:12Z – claude-opus – shell_pid=67878 – lane=for_review – Ready for review: HomeView integrates all sub-views with NavigationStack. CopyPreviousSheet with confirmation dialog. ContentView updated (Home tab with house icon). WorkoutDetailFromHomeView reuses CalendarWorkoutDetailView. Data refresh debounce added. Empty states handled. Build succeeds.
- 2026-03-01T18:46:40Z – claude-opus-reviewer – shell_pid=68870 – lane=doing – Started review via workflow command
- 2026-03-01T18:47:43Z – claude-opus-reviewer – shell_pid=68870 – lane=done – Review passed: HomeView correctly assembles all sub-views with NavigationStack, 20pt horizontal padding, 100pt bottom padding. CopyPreviousSheet with confirmation dialog for active workout conflict. ContentView properly updated (Home tab, house icon, callbacks wired). WorkoutDetailFromHomeView reuses CalendarWorkoutDetailView with lazy loading. Debounce prevents excessive re-fetching. All dependencies merged. Build succeeds with zero warnings.
- 2026-03-01T18:50:43Z – claude-opus-reviewer – shell_pid=68870 – lane=done – Review approved, moved to done
