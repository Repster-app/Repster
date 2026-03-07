---
work_package_id: "WP03"
subtasks:
  - "T012"
  - "T013"
  - "T014"
  - "T015"
  - "T016"
title: "Home Screen Sub-Views"
phase: "Phase 2 - UI Components"
lane: "done"
assignee: "claude-opus"
agent: "claude-opus-reviewer"
shell_pid: "67377"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01"]
history:
  - timestamp: "2026-03-01T17:56:08Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-03-01T18:31:24Z"
    lane: "doing"
    agent: "claude-opus"
    shell_pid: "66143"
    action: "Started implementation"
  - timestamp: "2026-03-01T18:38:16Z"
    lane: "for_review"
    agent: "claude-opus"
    shell_pid: "66143"
    action: "Ready for review"
  - timestamp: "2026-03-01T18:39:55Z"
    lane: "done"
    agent: "claude-opus-reviewer"
    shell_pid: "67377"
    action: "Review passed"
---

# Work Package Prompt: WP03 – Home Screen Sub-Views

## Implementation Command

```bash
spec-kitty implement WP03 --base WP01
```

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

- Create 5 pure presentation sub-views for the Home screen.
- All views follow design-system.md tokens exactly (colors, spacing, typography, corner radii).
- All views accept data as parameters — no ViewModel or service references.
- All interactive elements meet 44pt minimum tap target (SC-006).
- Each view renders correctly with both populated data and empty/zero states.

## Context & Constraints

- **Design System**: `design-system.md` — Section 2 (colors), Section 3 (typography), Section 4 (spacing), Section 5 (corner radii), Section 6.2 (card patterns).
- **Design Tokens**: `Reppo/Core/Extensions/DesignTokens.swift` — `Color.bg`, `.bgCard`, `.bgSubtle`, `.accent`, `.textPrimary`, `.textSecondary`, `.textTertiary`, `.border`.
- **Typography**: System font. Section headers: 11pt semibold, uppercase, textTertiary, 0.8 kerning. Card titles: 15pt semibold. Body: 15pt regular.
- **Cards**: `bgCard` background, 14pt corner radius, 14pt padding, no borders.
- **Data Structs** (defined in WP01): `WeekDay`, `RecentWorkoutSummary`.
- **Reference Components**: `Reppo/Features/Calendar/Views/Components/SummaryStatsStrip.swift` — example of design system compliance.
- **All files** go in `Reppo/Features/Home/Views/`.

---

## Subtasks & Detailed Guidance

### Subtask T012 – Create WeekStripView.swift

**Purpose**: Compact 7-day calendar showing Mon–Sun for the current week, with today highlighted and dots on workout days.

**Steps**:
1. Create `Reppo/Features/Home/Views/WeekStripView.swift`.
2. Accept `weekDays: [WeekDay]` as input.
3. Layout:

```swift
struct WeekStripView: View {
    let weekDays: [WeekDay]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDays) { day in
                dayCell(day)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    private func dayCell(_ day: WeekDay) -> some View {
        VStack(spacing: 4) {
            // Day abbreviation
            Text(day.abbreviation)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(day.isToday ? Color.accent : Color.textTertiary)

            // Date number
            Text("\(day.dateNumber)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(day.isToday ? .white : Color.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    day.isToday
                        ? Circle().fill(Color.accent)
                        : Circle().fill(Color.clear)
                )

            // Workout dot
            Circle()
                .fill(day.hasWorkout ? Color.accent : Color.clear)
                .frame(width: 6, height: 6)
        }
    }
}
```

**Files**: `Reppo/Features/Home/Views/WeekStripView.swift` (new, ~45 lines)

**Notes**:
- Today's cell: accent-colored circle background behind the date number, accent-colored abbreviation text.
- Non-today cells: clear background, textPrimary date, textTertiary abbreviation.
- Workout dot: 6pt accent circle. Clear (invisible) if no workout.
- The card wraps all 7 days in a single bgCard container.

### Subtask T013 – Create StartWorkoutCardView.swift

**Purpose**: Primary CTA card for starting a new workout.

**Steps**:
1. Create `Reppo/Features/Home/Views/StartWorkoutCardView.swift`.
2. Accept closures: `onCardTapped: () -> Void`, `onPlusTapped: () -> Void`.
3. Layout:

```swift
struct StartWorkoutCardView: View {
    let onCardTapped: () -> Void
    let onPlusTapped: () -> Void

    var body: some View {
        Button(action: onCardTapped) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("READY TO TRAIN")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accent)
                        .kerning(0.8)

                    Text("Start Workout")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text("Log exercises, sets & reps")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Button(action: onPlusTapped) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accent)
                        .cornerRadius(22)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
```

**Files**: `Reppo/Features/Home/Views/StartWorkoutCardView.swift` (new, ~45 lines)

**Notes**:
- The entire card is tappable (outer Button) — opens ExerciseListView or resumes active workout.
- The [+] button is a nested Button — creates empty workout. Use `.buttonStyle(.plain)` on both to prevent tap propagation issues.
- [+] button: 44x44pt circle with accent background and white plus icon. Meets tap target requirement.
- "READY TO TRAIN" uses the section header style but with accent color instead of textTertiary.

### Subtask T014 – Create QuickActionCardsView.swift

**Purpose**: Two side-by-side action cards: "Copy Previous" and "Templates".

**Steps**:
1. Create `Reppo/Features/Home/Views/QuickActionCardsView.swift`.
2. Accept closures: `onCopyPrevious: () -> Void`, `onTemplates: () -> Void`.
3. Layout:

```swift
struct QuickActionCardsView: View {
    let onCopyPrevious: () -> Void
    let onTemplates: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            quickActionCard(
                icon: "doc.on.doc",
                title: "Copy Previous",
                action: onCopyPrevious
            )

            quickActionCard(
                icon: "doc.text",
                title: "Templates",
                action: onTemplates
            )
        }
    }

    private func quickActionCard(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accent)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)

                Spacer()
            }
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
```

**Files**: `Reppo/Features/Home/Views/QuickActionCardsView.swift` (new, ~40 lines)

**Notes**:
- Both cards are equal width (HStack with default distribution).
- Icon on left, title right-aligned to icon. Spacer pushes content left.
- SF Symbols: `doc.on.doc` for copy, `doc.text` for templates.
- Each card must meet 44pt minimum height for tap targets.

### Subtask T015 – Create ThisWeekActivityView.swift

**Purpose**: Weekly activity bar chart with session counter.

**Steps**:
1. Create `Reppo/Features/Home/Views/ThisWeekActivityView.swift`.
2. Accept: `workoutCount: Int`, `workoutDays: Set<Int>`, `weeklyGoal: Int`.
3. Layout:

```swift
struct ThisWeekActivityView: View {
    let workoutCount: Int
    let workoutDays: Set<Int>  // 0=Mon..6=Sun
    let weeklyGoal: Int

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("THIS WEEK")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            VStack(spacing: 12) {
                // Bar chart
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(workoutDays.contains(index) ? Color.accent : Color.bgSubtle)
                                .frame(height: 32)

                            Text(dayLabels[index])
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isToday(index) ? Color.accent : Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                // Session counter
                HStack(spacing: 4) {
                    Text("\(workoutCount)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accent)
                    Text("/ \(weeklyGoal) sessions")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
    }

    private func isToday(_ index: Int) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let todayIndex = (weekday + 5) % 7  // Mon=0..Sun=6
        return index == todayIndex
    }
}
```

**Files**: `Reppo/Features/Home/Views/ThisWeekActivityView.swift` (new, ~55 lines)

**Notes**:
- Section header ("THIS WEEK") is OUTSIDE the card, above it. The bar chart and counter are inside the card.
- Bars: narrow rounded rectangles. Filled with accent color if workout on that day, `bgSubtle` otherwise.
- Today's day label: accent colored to distinguish from others.
- Session counter: "X / 4 sessions" where X is accent, rest is textSecondary.
- Same weekday conversion as HomeViewModel: `(weekday + 5) % 7`.

### Subtask T016 – Create RecentWorkoutCardView.swift

**Purpose**: Single card displaying a recent completed workout's summary.

**Steps**:
1. Create `Reppo/Features/Home/Views/RecentWorkoutCardView.swift`.
2. Accept: `summary: RecentWorkoutSummary`.
3. Layout (plain view — no Button wrapper, since HomeView wraps this in NavigationLink):

```swift
struct RecentWorkoutCardView: View {
    let summary: RecentWorkoutSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Date
            Text(formatDate(summary.date))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)

            // Stats row
            HStack(spacing: 16) {
                statItem("\(summary.exerciseCount)", label: "exercises")
                statItem("\(summary.setCount)", label: "sets")
                statItem(formatDuration(summary.durationMinutes), label: "duration")
                statItem(formatVolume(summary.totalVolume), label: "volume")
            }

            // Muscle group tags
            if !summary.muscleGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(summary.muscleGroups, id: \.self) { muscle in
                            Text(muscle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.bgSubtle)
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Components

    private func statItem(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .textCase(.uppercase)
        }
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 1 { return "< 1m" }
        return "\(minutes)m"
    }

    private func formatVolume(_ kg: Double) -> String {
        if kg >= 1000 {
            return String(format: "%.1ft", kg / 1000)
        }
        return "\(Int(kg)) kg"
    }
}
```

**Files**: `Reppo/Features/Home/Views/RecentWorkoutCardView.swift` (new, ~70 lines)

**Notes**:
- This is a **plain view** (no Button wrapper). Tap handling is done by `NavigationLink` in HomeView (WP04). This avoids SwiftUI's Button-inside-NavigationLink tap conflicts.
- Date format: "Wednesday, Mar 1" — matches spec header date format.
- Stats row: inline stat items (value above label). Labels are uppercase, 10pt, textTertiary.
- Duration: "52m" format, or "< 1m" for very short sessions (per spec edge case).
- Volume: "1.5t" for >=1000kg, otherwise "850 kg". Matches `SummaryStatsStrip` pattern using "t" for tonnes.
- Muscle tags: horizontal scroll, `bgSubtle` pills, 11pt textSecondary, 6pt radius.

---

## Risks & Mitigations

- **Design system drift**: All color and spacing values must match `DesignTokens.swift` exactly. Cross-reference `design-system.md` if unsure.
- **Week strip locale**: Day abbreviations are hardcoded ("M", "T", "W"...) not locale-dependent. This matches the spec requirement of Mon–Sun always.
- **Muscle group overflow**: If a workout hits many muscle groups, horizontal scroll on tags prevents layout overflow.
- **Zero duration**: `formatDuration(0)` returns "< 1m" per spec edge case.

## Definition of Done Checklist

- [ ] All 5 sub-views created in `Reppo/Features/Home/Views/`
- [ ] WeekStripView: 7 cells, today highlighted, workout dots
- [ ] StartWorkoutCardView: "READY TO TRAIN" label, title, subtitle, [+] button
- [ ] QuickActionCardsView: two equal-width cards side by side
- [ ] ThisWeekActivityView: section header, 7 bars, session counter
- [ ] RecentWorkoutCardView: date, 4-stat row, muscle tags
- [ ] All colors from DesignTokens.swift (bg, bgCard, bgSubtle, accent, text colors)
- [ ] All touch targets ≥ 44pt
- [ ] Section headers: 11pt semibold, uppercase, textTertiary, 0.8 kerning
- [ ] Cards: bgCard, 14pt radius, 14pt padding
- [ ] No borders on cards (per design system)

## Review Guidance

- Verify each view is pure presentation (no ViewModel/service references).
- Verify design token usage — no hardcoded hex colors.
- Verify tap targets on StartWorkoutCardView [+] button and card bodies.
- Check corner radii: cards = 14pt, tags = 6pt, today circle = full circle.
- Verify "< 1m" edge case for duration formatting.
- Verify volume formatting threshold (>=1000 → tonnes).

## Activity Log

- 2026-03-01T17:56:08Z – system – lane=planned – Prompt created.
- 2026-03-01T18:31:24Z – claude-opus – shell_pid=66143 – lane=doing – Started implementation via workflow command
- 2026-03-01T18:38:16Z – claude-opus – shell_pid=66143 – lane=for_review – Ready for review: All 5 Home Screen sub-views created (WeekStripView, StartWorkoutCardView, QuickActionCardsView, ThisWeekActivityView, RecentWorkoutCardView). All use DesignTokens, pure presentation with no ViewModel references, 44pt tap targets. Build succeeds.
- 2026-03-01T18:39:00Z – claude-opus-reviewer – shell_pid=67377 – lane=doing – Started review via workflow command
- 2026-03-01T18:40:04Z – claude-opus-reviewer – shell_pid=67377 – lane=done – Review passed: All 5 sub-views match spec exactly. Design tokens correct (no hardcoded hex). Pure presentation (no ViewModel refs). Tap targets met (44pt on StartWorkoutCardView plus button, QuickActionCards minHeight). Card patterns consistent (bgCard, 14pt radius/padding, no borders). Section headers correct (11pt semibold, uppercase, textTertiary, 0.8 kerning). Edge cases handled (< 1m duration, volume tonnes threshold). Xcode project properly configured. Build succeeds with zero warnings.
- 2026-03-01T18:50:43Z – claude-opus-reviewer – shell_pid=67377 – lane=done – Review approved, moved to done
