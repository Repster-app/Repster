---
work_package_id: "WP03"
subtasks:
  - "T015"
  - "T016"
  - "T017"
  - "T018"
  - "T019"
title: "Per-Exercise Cards — Card List with Sparklines"
phase: "Phase 1 - User Story 2"
lane: "done"
dependencies: ["WP01"]
agent: "claude"
assignee: "Magnus Espensen"
shell_pid: "10268"
reviewed_by: "Magnus Espensen"
review_status: "approved"
history:
  - timestamp: "2026-02-27T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-02-28T08:33:48Z"
    lane: "doing"
    agent: "claude"
    shell_pid: "93019"
    action: "Started implementation via workflow command"
  - timestamp: "2026-02-28T08:37:10Z"
    lane: "for_review"
    agent: "claude"
    shell_pid: "93019"
    action: "Ready for review: Per-exercise cards — fetchExerciseCardData service method, ExerciseChartCard component with sparklines/trend arrows, LazyVStack card list, edge cases handled. Build succeeds with 0 errors."
  - timestamp: "2026-02-28T13:25:58Z"
    lane: "doing"
    agent: "claude"
    shell_pid: "10268"
    action: "Started review via workflow command"
  - timestamp: "2026-02-28T13:26:44Z"
    lane: "done"
    agent: "claude"
    shell_pid: "10268"
    action: "Review passed: fetchExerciseCardData correctly builds sparkline from per-set e1RM values, trend uses last 2 sparkline points, LazyVStack with .buttonStyle(.plain), cards sorted by lastPerformed descending. Build succeeds."
---

# Work Package Prompt: WP03 – Per-Exercise Cards — Card List with Sparklines

## Objectives & Success Criteria

- Implement exercise card data loading in ChartDataService (ExerciseStats + sparkline e1RM data + trend direction).
- Create ExerciseChartCard component with exercise name, current e1RM, trend arrow, and mini sparkline.
- Wire the card list into ChartsDashboardView PER EXERCISE section.
- Handle edge cases: no exercises with stats, duration-only exercises without e1RM.
- **Success**: PER EXERCISE section shows exercise cards sorted by most recently performed. Each card displays name, current e1RM (or "-"), trend arrow (↑/↓/→), and sparkline. Cards are tappable (navigation target placeholder until WP04).

## Context & Constraints

- **Spec references**: FR-004 (cards show e1RM, trend, sparkline, sorted by most recent), User Story 2 acceptance scenarios.
- **Data sources**: `ExerciseStats.bestE1RM` for current e1RM, `ExerciseStats.lastPerformedDate` for sorting, `WorkoutSet` for sparkline data.
- **Sparkline**: Last 8 sessions' best e1RM per exercise (per plan.md decision #7).
- **Existing repos**: `ExerciseStatsRepository.fetchAll()`, `SetRepository.fetchSets(exerciseId:from:to:)` (from WP01).
- **ExerciseRepository**: `fetch(byId:)` for exercise name lookup.
- **Design**: Dark mode, bgCard background, accent for sparkline color.

**Implementation command**: `spec-kitty implement WP03 --base WP01`

## Subtasks & Detailed Guidance

### Subtask T015 – Implement ChartDataService.fetchExerciseCardData()

- **Purpose**: Build the data for all exercise cards — name, current e1RM, sparkline points, and trend direction.
- **File**: `Reppo/Core/Services/ChartDataService.swift` (edit — replace stub)
- **Spec**: FR-004

**Steps**:
1. Fetch all ExerciseStats: `let allStats = try await exerciseStatsRepository.fetchAll()`.
2. Filter to stats with `lastPerformedDate != nil` (exercises that have been performed).
3. Sort by `lastPerformedDate` descending (most recent first).
4. For each stat entry, build `ExerciseCardData`:
   a. Fetch exercise metadata: `let exercise = try await exerciseRepository.fetch(byId: stat.exerciseId)`.
   b. Get `currentE1RM = stat.bestE1RM` (may be 0 for duration-only exercises).
   c. Build sparkline: Fetch recent sets for this exercise:
      ```swift
      let sets = try await setRepository.fetchSets(exerciseId: stat.exerciseId, from: nil, to: Date())
      ```
   d. Group by `workoutId`, take max `e1RM` per workout (where e1RM > 0):
      ```swift
      let grouped = Dictionary(grouping: sets) { $0.workoutId }
      let sessionE1RMs: [(Date, Double)] = grouped.compactMap { (_, workoutSets) in
          guard let date = workoutSets.first?.date,
                let maxE1RM = workoutSets.compactMap({ $0.e1RM }).filter({ $0 > 0 }).max()
          else { return nil }
          return (date, maxE1RM)
      }
      .sorted { $0.0 < $1.0 }
      ```
   e. Take last 8 sessions: `let last8 = sessionE1RMs.suffix(8).map { $0.1 }`.
   f. Compute trend direction:
      ```swift
      let trend: TrendDirection
      if last8.count >= 2 {
          let latest = last8[last8.count - 1]
          let previous = last8[last8.count - 2]
          if latest > previous { trend = .up }
          else if latest < previous { trend = .down }
          else { trend = .flat }
      } else {
          trend = .flat
      }
      ```
   g. Create `ExerciseCardData(id: stat.exerciseId, name: exercise?.name ?? "Unknown", currentE1RM: stat.bestE1RM > 0 ? stat.bestE1RM : nil, trendDirection: trend, sparklinePoints: last8, lastPerformed: stat.lastPerformedDate)`.

5. **Performance consideration**: This fetches sets for each exercise sequentially. For ~50 active exercises × ~30 sets each ≈ ~1500 total set fetches. This is bounded and acceptable for v1. If slow, can be optimized later with batch queries.

**Edge cases**:
- Exercise with 0 sessions (stat exists but no sets) → skip or show with empty sparkline.
- Duration-only exercise (no e1RM values) → `currentE1RM = nil`, empty sparkline, trend = `.flat`.
- Exercise with only 1 session → sparkline has 1 point, trend = `.flat`.

**Validation**:
- Returns cards sorted by `lastPerformed` descending.
- Sparkline has at most 8 points.
- Trend direction reflects comparison of last 2 sparkline points.

---

### Subtask T016 – Create ExerciseChartCard.swift

- **Purpose**: Card component showing exercise name, current e1RM value, trend direction arrow, and a mini sparkline chart.
- **File**: `Reppo/Features/Charts/Views/Components/ExerciseChartCard.swift` (new file)
- **Parallel?**: Yes — pure view component.

**Steps**:
1. Create the card layout:
```swift
import SwiftUI
import Charts

struct ExerciseChartCard: View {
    let data: ExerciseCardData

    var body: some View {
        HStack(spacing: 12) {
            // Left: Name + e1RM + trend
            VStack(alignment: .leading, spacing: 4) {
                Text(data.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let e1rm = data.currentE1RM {
                        Text(String(format: "%.1f", e1rm))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("kg")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Text("—")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                    }

                    trendArrow
                }
            }

            Spacer()

            // Right: Sparkline
            if !data.sparklinePoints.isEmpty {
                sparkline
                    .frame(width: 80, height: 32)
            }
        }
        .padding(14)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Trend Arrow

    private var trendArrow: some View {
        Group {
            switch data.trendDirection {
            case .up:
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.success)
            case .down:
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.danger)
            case .flat:
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Sparkline

    private var sparkline: some View {
        Chart(Array(data.sparklinePoints.enumerated()), id: \.offset) { index, value in
            LineMark(
                x: .value("Session", index),
                y: .value("e1RM", value)
            )
            .foregroundStyle(Color.accent)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}
```

2. **Sparkline design**: Minimal line chart — no axes, no labels, no grid. Just a trend line. Uses `.catmullRom` interpolation for smooth curves.
3. **e1RM display**: Show value with 1 decimal and "kg" suffix. If nil (duration-only exercise), show dash.
4. **Trend arrows**: Green up-right for improving, red down-right for declining, gray right for flat. Uses SF Symbols.
5. **Card styling**: bgCard background, 14pt padding, 14pt corner radius — matches existing chart cards.

**Validation**:
- Card renders exercise name (single line, truncated if long).
- e1RM shows correctly formatted or dash for no data.
- Sparkline draws a smooth line for 2+ points. Single point or empty → sparkline hidden.
- Trend arrow color and direction match trend data.

---

### Subtask T017 – Implement ChartsDashboardViewModel.loadExerciseCards()

- **Purpose**: Call ChartDataService and populate the exercise cards array in the ViewModel.
- **File**: `Reppo/Features/Charts/ViewModels/ChartsDashboardViewModel.swift` (edit — replace stub)

**Steps**:
1. Implement `loadExerciseCards()`:
   ```swift
   func loadExerciseCards() async {
       guard !cardsLoaded else { return }
       do {
           exerciseCards = try await chartDataService.fetchExerciseCardData()
           cardsLoaded = true
       } catch {
           print("[ChartsDashboard] Failed to load exercise cards: \(error)")
       }
   }
   ```

2. This is called from `loadDashboard()` (already set up in WP01). The guard prevents re-loading.

**Validation**:
- `exerciseCards` array is populated after loading.
- Guard prevents duplicate fetches.

---

### Subtask T018 – Wire Exercise Card List into ChartsDashboardView

- **Purpose**: Render the exercise card list in the PER EXERCISE section of ChartsDashboardView with LazyVStack and NavigationLink.
- **File**: `Reppo/Features/Charts/Views/ChartsDashboardView.swift` (edit — replace exercise section placeholder)

**Steps**:
1. Replace the exercise section placeholder:
   ```swift
   @ViewBuilder
   private var exerciseSection: some View {
       if !viewModel.exerciseCards.isEmpty {
           Text("PER EXERCISE")
               .font(.system(size: 11, weight: .semibold))
               .foregroundStyle(Color.textTertiary)
               .kerning(0.8)

           LazyVStack(spacing: 8) {
               ForEach(viewModel.exerciseCards) { card in
                   NavigationLink {
                       // Placeholder destination — replaced in WP04
                       Text("Exercise Charts Detail for \(card.name)")
                           .foregroundStyle(Color.textPrimary)
                   } label: {
                       ExerciseChartCard(data: card)
                   }
                   .buttonStyle(.plain)
               }
           }
       }
   }
   ```

2. Use `LazyVStack` for efficient rendering with many exercises.
3. `NavigationLink` wraps each card. Destination is a placeholder `Text` for now — WP04 will replace it with `ExerciseChartsDetailView`.
4. `.buttonStyle(.plain)` ensures the card renders as designed (no default button styling).

**Validation**:
- Exercise cards render in a vertical list.
- Cards are tappable and navigate to a placeholder screen.
- Sorting matches `lastPerformed` descending (most recent first).

---

### Subtask T019 – Handle Edge Cases

- **Purpose**: Handle empty states and special cases in the PER EXERCISE section.
- **File**: `Reppo/Features/Charts/Views/ChartsDashboardView.swift` (edit)

**Steps**:
1. If `exerciseCards` is empty and loading is complete, show the motivational empty state (shared with overview):
   ```swift
   // In exerciseSection:
   if viewModel.exerciseCards.isEmpty && !viewModel.isLoading {
       // Empty state handled by the overview empty state
       // Only show PER EXERCISE header if there are cards
   }
   ```

2. The overall empty state (no workouts at all) is already handled by T014's empty state in the overview section. If overview is empty, the exercise list will also be empty.

3. For exercises without e1RM (duration-only like planks):
   - `currentE1RM` is `nil` → card shows "—" (handled in T016).
   - Sparkline is empty → sparkline section hidden (handled in T016).
   - These cards still appear in the list (they have stats like totalSets, totalWorkouts).

4. For exercises with only 1 session:
   - Sparkline has 1 point → sparkline hidden (1 point isn't a meaningful line).
   - Trend is `.flat`.

**Validation**:
- No exercise cards → no PER EXERCISE section header shown.
- Duration-only exercises show "—" for e1RM, no sparkline.
- Single-session exercises show with flat trend.

---

## Risks & Mitigations

- **Sequential fetching for sparklines**: Fetching sets per exercise is O(N) in exercise count. For 50 exercises this is ~50 sequential async calls. If slow, consider batching or limiting to top 20 most recent exercises with a "Show all" button.
- **Unit display**: e1RM values are stored in kg. The card currently displays raw kg. For imperial users, convert in the view or ViewModel. Check how CalendarView handles this.
- **Exercise name truncation**: Long exercise names may overflow. `.lineLimit(1)` with truncation handles this.

## Definition of Done Checklist

- [ ] `fetchExerciseCardData()` returns cards sorted by lastPerformed descending
- [ ] Each card has name, currentE1RM (or nil), trend direction, sparkline points
- [ ] Sparkline has at most 8 points from recent sessions
- [ ] `ExerciseChartCard` renders correctly with all data variants
- [ ] Trend arrows show correct direction and color
- [ ] Cards are listed in PER EXERCISE section with LazyVStack
- [ ] Cards are tappable with NavigationLink (placeholder destination)
- [ ] Empty state: no PER EXERCISE section when no exercises
- [ ] Duration-only exercises show "—" for e1RM
- [ ] App compiles without errors

## Review Guidance

- Verify sparkline data comes from actual `e1RM` values on sets, not from `ExerciseStats.bestE1RM`.
- Verify trend direction comparison uses the last 2 sparkline points, not arbitrary values.
- Verify `LazyVStack` is used (not `VStack`) for efficient rendering.
- Verify `.buttonStyle(.plain)` on NavigationLink to prevent default button styling.
- Verify exercise cards sort order matches spec (most recent first).
- Check that duration-only exercises don't crash (nil-safe e1RM handling).

## Activity Log

- 2026-02-28T08:33:48Z – claude – shell_pid=93019 – lane=doing – Started implementation via workflow command
- 2026-02-28T08:37:10Z – claude – shell_pid=93019 – lane=for_review – Ready for review: Per-exercise cards — fetchExerciseCardData service method, ExerciseChartCard component with sparklines/trend arrows, LazyVStack card list in dashboard, edge cases handled. Build succeeds with 0 errors.
- 2026-02-28T13:25:58Z – claude – shell_pid=10268 – lane=doing – Started review via workflow command
- 2026-02-28T13:26:44Z – claude – shell_pid=10268 – lane=done – Review passed: fetchExerciseCardData correctly builds sparkline from per-set e1RM values (not ExerciseStats.bestE1RM), trend uses last 2 sparkline points, LazyVStack with .buttonStyle(.plain), cards sorted by lastPerformed descending, duration-only exercises nil-safe with dash display, sparkline requires 2+ points. Build succeeds.
