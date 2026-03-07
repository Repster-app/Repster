---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
  - "T005"
title: "Tab Shell & Navigation Foundation"
phase: "Phase 0 - Foundation"
lane: "done"
assignee: "claude"
agent: "claude-opus"
shell_pid: "38186"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: []
history:
  - timestamp: "2026-02-25T08:19:17Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP01 - Tab Shell & Navigation Foundation

## IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Implementation Command

No dependencies:
```bash
spec-kitty implement WP01
```

---

## Objectives & Success Criteria

- Replace the placeholder `ContentView` with a proper 5-tab navigation shell
- Create the `Features/Exercise/` directory structure for all subsequent WPs
- Create shared enums used across the feature
- App launches with visible tab bar, FAB button centered, and active workout resume still works
- **Success**: Tab bar renders with 4 tabs + center FAB overlay; placeholder views display correctly; fullScreenCover for active workout fires on launch when workout exists

## Context & Constraints

- **Constitution**: SwiftUI primary, `NavigationStack` (not `NavigationView`), dark mode only, design tokens from `DesignTokens.swift`
- **Plan**: `kitty-specs/007-exercise-list-and-detail/plan.md` - Section "Key Architecture Decisions > 1. Tab Bar Navigation Shell"
- **Research**: `kitty-specs/007-exercise-list-and-detail/research.md` - R1: Tab Bar with Center FAB in SwiftUI
- **AGENT_RULES.md**: Section 7.2 - Navigation Structure defines the 5-tab layout
- **Existing code**: `Reppo/App/ContentView.swift` is the current placeholder to replace. `Reppo/App/ReppoApp.swift` injects `modelContainer`, `RepositoryContainer`, `ServiceContainer` into environment.

## Subtasks & Detailed Guidance

### Subtask T001 - Create shared enums

- **Purpose**: Define all enums needed across the feature so they're available to all subsequent WPs.
- **Files**: Create `Reppo/Features/Exercise/Models/ExerciseEnums.swift` (single file for all small enums)
- **Steps**:
  1. Create `MainTab` enum:
     ```swift
     enum MainTab: Int, CaseIterable {
         case programs = 0
         case calendar = 1
         case charts = 2
         case settings = 3
     }
     ```
     Note: FAB is NOT a tab - it's an overlay button. Only 4 real tabs.

  2. Create `ExerciseListMode` enum:
     ```swift
     enum ExerciseListMode {
         case browse          // FAB entry, standalone screen
         case addToWorkout    // From Active Workout [+Exercise], sheet presentation
     }
     ```

  3. Create `ExerciseListSortOrder` enum:
     ```swift
     enum ExerciseListSortOrder: String, CaseIterable {
         case alphabetical = "A-Z"
         case mostRecent = "Most Recent"
         case mostUsed = "Most Used"
     }
     ```

  4. Create `ExerciseDetailTab` enum:
     ```swift
     enum ExerciseDetailTab: String, CaseIterable {
         case history = "History"
         case prs = "PRs"
         case charts = "Charts"
     }
     ```

  5. Create `ExerciseSubTab` enum (for Active Workout sub-tabs):
     ```swift
     enum ExerciseSubTab: String, CaseIterable {
         case sets = "Sets"
         case history = "History"
         case charts = "Charts"
     }
     ```

- **Parallel?**: Yes - independent of other subtasks.

### Subtask T002 - Create Features/Exercise/ directory structure

- **Purpose**: Scaffold the directory tree so subsequent WPs can create files in the right locations.
- **Steps**:
  1. Create the following directories:
     - `Reppo/Features/Exercise/Views/`
     - `Reppo/Features/Exercise/Views/Components/`
     - `Reppo/Features/Exercise/ViewModels/`
     - `Reppo/Features/Exercise/Models/`
  2. Ensure these directories are tracked by Xcode. Add folder references to the Xcode project if needed, or rely on Xcode's automatic file discovery.
- **Parallel?**: Yes - independent file system operation.

### Subtask T003 - Replace ContentView with TabView shell

- **Purpose**: Transform the app from a single-screen placeholder into a proper tabbed navigation app.
- **Files**: `Reppo/App/ContentView.swift` (full rewrite)
- **Steps**:
  1. Read the existing `ContentView.swift` to understand current state (it has `showActiveWorkout` bool and fullScreenCover).
  2. Replace with a `TabView(selection: $selectedTab)` containing 4 tabs:
     ```swift
     TabView(selection: $selectedTab) {
         NavigationStack {
             ProgramsPlaceholderView()
         }
         .tabItem {
             Label("Programs", systemImage: "list.bullet.rectangle")
         }
         .tag(MainTab.programs)

         NavigationStack {
             CalendarPlaceholderView()
         }
         .tabItem {
             Label("Calendar", systemImage: "calendar")
         }
         .tag(MainTab.calendar)

         NavigationStack {
             ChartsPlaceholderView()
         }
         .tabItem {
             Label("Charts", systemImage: "chart.line.uptrend.xyaxis")
         }
         .tag(MainTab.charts)

         NavigationStack {
             SettingsPlaceholderView()
         }
         .tabItem {
             Label("Settings", systemImage: "gearshape")
         }
         .tag(MainTab.settings)
     }
     ```
  3. Add FAB overlay centered on the tab bar:
     ```swift
     .overlay(alignment: .bottom) {
         Button(action: { fabTapped() }) {
             Image(systemName: "plus.circle.fill")
                 .font(.system(size: 56))
                 .foregroundStyle(Color.accent)
                 .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
         }
         .offset(y: -2) // Adjust to sit on tab bar
     }
     ```
  4. FAB action: For now, set a placeholder navigation. WP07 will wire the real navigation.
  5. Apply dark mode background: `.preferredColorScheme(.dark)`
  6. Style the tab bar appearance for dark mode using `UITabBar.appearance()` in an `init()` or `.onAppear`.

- **Notes**: The tab bar icons should use SF Symbols matching AGENT_RULES Section 7.2. The FAB must be larger and visually distinct from the tab items.
- **Parallel?**: No - this is the main structural change.

### Subtask T004 - Create placeholder views for 4 tabs

- **Purpose**: Each tab needs a minimal placeholder view so the app is functional.
- **Files**: Create a single file `Reppo/Features/Exercise/Views/TabPlaceholderViews.swift` (or individual files if preferred)
- **Steps**:
  1. Create `ProgramsPlaceholderView`:
     ```swift
     struct ProgramsPlaceholderView: View {
         var body: some View {
             VStack(spacing: 16) {
                 Image(systemName: "list.bullet.rectangle")
                     .font(.system(size: 48))
                     .foregroundStyle(Color.textTertiary)
                 Text("Programs")
                     .font(.title2.bold())
                     .foregroundStyle(Color.textPrimary)
                 Text("Coming in v1.1")
                     .foregroundStyle(Color.textTertiary)
             }
             .frame(maxWidth: .infinity, maxHeight: .infinity)
             .background(Color.bg)
         }
     }
     ```
  2. Create similar placeholders for Calendar ("Coming in Feature 008"), Charts ("Coming in Feature 009"), Settings ("Coming in Feature 010").
  3. Each placeholder should have the `.bg` background color and centered content with an SF Symbol icon.

- **Parallel?**: Yes - independent of ContentView rewrite.

### Subtask T005 - Wire active workout resume on launch

- **Purpose**: Preserve the existing behavior where the app navigates to an active workout on launch.
- **Files**: `Reppo/App/ContentView.swift` (within the new TabView structure)
- **Steps**:
  1. Keep the `@State private var showActiveWorkout = false` state.
  2. Keep the `.fullScreenCover(isPresented: $showActiveWorkout) { ActiveWorkoutView(...) }` modifier on the TabView.
  3. On `.task { }` or `.onAppear`, check `WorkoutService.getActiveWorkout()`:
     ```swift
     .task {
         if let activeWorkout = try? await services.workoutService.getActiveWorkout() {
             if activeWorkout.status == .inProgress {
                 showActiveWorkout = true
             }
         }
     }
     ```
  4. Ensure the `ActiveWorkoutView` is still presented with the correct ViewModel and service dependencies from the environment.
  5. Read the existing `ContentView.swift` to see exactly how this is currently wired and preserve the pattern.

- **Notes**: This must work identically to the current behavior. The only change is that the fullScreenCover is now on a TabView instead of a plain VStack.
- **Parallel?**: No - depends on T003 (ContentView rewrite).

## Risks & Mitigations

- **FAB overlay positioning**: The FAB must sit centered on the tab bar, not inside any tab's content. Use `.overlay(alignment: .bottom)` on the TabView itself, with appropriate offset.
- **Tab bar dark mode styling**: SwiftUI's default tab bar may not match the design system colors. Use `UITabBar.appearance()` to set `backgroundColor`, `unselectedItemTintColor`, etc. in an initializer.
- **Active workout resume regression**: The fullScreenCover pattern must survive the ContentView rewrite. Test by simulating an in-progress workout.

## Definition of Done Checklist

- [ ] All 5 enums created and compiling
- [ ] `Features/Exercise/` directory structure exists
- [ ] ContentView shows TabView with 4 tabs and center FAB
- [ ] Each tab shows its placeholder view
- [ ] FAB button is visually distinct and centered on tab bar
- [ ] Active workout resume still works via fullScreenCover
- [ ] Dark mode styling applied to tab bar
- [ ] `tasks.md` updated with status change

## Review Guidance

- Verify tab bar matches AGENT_RULES Section 7.2 layout
- Verify FAB is visually prominent and centered
- Verify active workout resume by checking the `.task {}` / `.onAppear` logic
- Verify all enums have correct cases matching plan.md and data-model.md
- Verify dark mode background colors use `DesignTokens.swift` tokens

## Activity Log

- 2026-02-25T08:19:17Z - system - lane=planned - Prompt created.
- 2026-02-25T14:35:13Z – claude_opus – shell_pid=38186 – lane=doing – Started implementation via workflow command
- 2026-02-26T14:39:22Z – claude_opus – shell_pid=38186 – lane=for_review – Ready for review: Tab shell with 4 tabs + FAB overlay, enums, dark mode styling, and active workout resume wired.
- 2026-02-26T14:39:22Z – claude_opus – shell_pid=38186 – lane=done – Review passed: All 5 subtasks verified. Enums match spec. TabView shell with 4 tabs + FAB overlay follows AGENT_RULES S7.2. Dark mode styling uses correct DesignTokens. Active workout resume preserved. Xcode project updated.
