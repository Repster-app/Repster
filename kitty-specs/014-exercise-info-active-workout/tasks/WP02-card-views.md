---
work_package_id: "WP02"
subtasks:
  - "T004"
  - "T005"
  - "T006"
  - "T007"
title: "Card Views — All SwiftUI Components"
phase: "Phase 1 - Views"
lane: "done"
assignee: "claude-opus"
agent: "claude-opus"
shell_pid: "80517"
review_status: "approved"
reviewed_by: "claude-opus"
dependencies: ["WP01"]
history:
  - timestamp: "2026-03-01T19:53:31Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-03-01T20:12:53Z"
    lane: "doing"
    agent: "claude-opus"
    shell_pid: "78130"
    action: "Started implementation via workflow command"
  - timestamp: "2026-03-01T20:17:17Z"
    lane: "for_review"
    agent: "claude-opus"
    shell_pid: "78130"
    action: "Ready for review"
  - timestamp: "2026-03-01T20:27:37Z"
    lane: "done"
    agent: "claude-opus"
    shell_pid: "80517"
    action: "Review passed"
---

# Work Package Prompt: WP02 – Card Views — All SwiftUI Components

## Implementation Command

```bash
spec-kitty implement WP02 --base WP01
```

## Objectives & Success Criteria

- Build all four Exercise Info SwiftUI views matching design-system.md tokens exactly
- Each card handles its own unit conversion (kg/lbs) and empty states
- Layout matches the reference design: hero card full-width, compact cards side-by-side
- **Success**: SwiftUI previews render all cards correctly with sample data; all design tokens match

## Context & Constraints

**Design system reference**: `design-system.md` — color tokens, typography, spacing, card patterns.
**View contracts**: `kitty-specs/014-exercise-info-active-workout/contracts/view-contracts.md` — exact layout specs, states, and formatting rules.
**Data model**: `kitty-specs/014-exercise-info-active-workout/data-model.md` — struct definitions for view inputs.
**Existing patterns**: Reference `RecentWorkoutCardView.swift`, `SummaryStatsStrip.swift`, `PRBadgeView.swift` for consistent card styling.
**Constitution**: Dark mode only. SF Symbols for icons. System font. 44pt minimum touch targets. No third-party UI libs.

**Design Tokens Quick Reference**:
| Token | Value |
|-------|-------|
| `Color.bgCard` | `#1B1B1F` |
| `Color.textPrimary` | `#EAEAEF` |
| `Color.textSecondary` | `#9999A8` |
| `Color.textTertiary` | `#5C5C6E` |
| `Color.success` | `#5EC269` |
| `Color.danger` | `#E05555` |
| `Color.border` | `white @ 6%` |
| Card radius | `14pt` |
| Card padding | `14pt` |

## Subtasks & Detailed Guidance

### Subtask T004 – Create E1RMCardView.swift (Hero Card)

- **Purpose**: The most prominent card in the Exercise Info section. Displays the user's estimated one-rep max with today's best set and a historical comparison trend.
- **File**: `Reppo/Features/Workout/Views/Components/E1RMCardView.swift` (NEW)
- **Parallel?**: Yes — independent from T005 and T006.

**Interface**:
```swift
struct E1RMCardView: View {
    let info: E1RMInfo
    let unitPreference: UnitPreference
}
```

**Layout (full-width hero card)**:
```
┌─────────────────────────────────────────┐
│  [icon] Estimated 1RM                   │  Header row
│                                         │
│  105.5 kg                               │  32pt bold, textPrimary
│                                         │
│  Best today: 85 × 8  ┊  vs 4wk ago     │  12pt med labels
│                       ┊  +2.3 kg ▲      │  Trend color
└─────────────────────────────────────────┘
```

**Steps**:

1. Create the view struct with `info: E1RMInfo` and `unitPreference: UnitPreference`.

2. **Header row**: HStack with icon and title.
   - Icon: `Image(systemName: "gauge.open.with.lines.needle.33percent")` sized 14pt.
   - Icon background: small square with `Color.accentColor.opacity(0.08)`, 6pt corner radius, frame 22×22.
   - Title: `"Estimated 1RM"` in `.system(size: 12, weight: .medium)`, `Color.textSecondary`.

3. **Hero value**: Display the e1RM formatted with unit.
   - Use 32pt bold, `Color.textPrimary`.
   - Format weight: apply `UnitConversion.kgToLbs()` if `unitPreference == .imperial`.
   - Show 1 decimal place: `String(format: "%.1f", displayWeight)`.
   - Append unit string: `" kg"` or `" lbs"`.

4. **Bottom section**: HStack with "Best today" on the left and historical comparison on the right, separated by a vertical divider.
   - **Left side — Best today**:
     - `"Best today: \(formatWeight(info.bestSetWeight)) × \(info.bestSetReps)"`.
     - Font: `.system(size: 12, weight: .medium)`, color: `Color.textSecondary`.
   - **Divider**: `Rectangle().fill(Color.border).frame(width: 1).padding(.vertical, 2)`.
   - **Right side — Historical comparison** (only if `info.historicalE1RM != nil`):
     - Label: `"vs \(info.historicalWeeksAgo ?? 4)wk ago"` in `.system(size: 12, weight: .medium)`, `Color.textTertiary`.
     - Delta value: `"+2.3 kg"` or `"−1.1 kg"`.
       - Always show sign prefix (`+` or `−`).
       - Color: `Color.success` for `.positive`, `Color.danger` for `.negative`, `Color.textSecondary` for `.neutral`.
       - Font: `.system(size: 12, weight: .semibold)`.

5. **Card container**: Wrap everything in:
   ```swift
   VStack(alignment: .leading, spacing: 8) { ... }
       .padding(14)
       .background(Color.bgCard)
       .cornerRadius(14)
   ```

6. **Weight formatting helper** (private):
   ```swift
   private func formatWeight(_ kg: Double) -> String {
       let value = unitPreference == .imperial ? UnitConversion.kgToLbs(kg) : kg
       if value == value.rounded() && value == Double(Int(value)) {
           return "\(Int(value))"
       }
       return String(format: "%.1f", value)
   }
   ```

7. **Handle 4 display states**:
   - Full display (has current + history): Show everything.
   - Current only (no history): Hide right side of bottom HStack. No divider.
   - Fallback (no current sets): Show `info.currentE1RM` as "All-time best" instead of "Best today".
   - No data: Show "No data yet" centered in `Color.textTertiary`.

   *Note*: The provider already handles which state to send. If `info.historicalE1RM == nil`, hide the comparison. If `info.bestSetReps` exists, it's from today's session.

**Validation**:
- [ ] Hero value renders at 32pt bold
- [ ] Unit conversion applied correctly (kg vs lbs)
- [ ] Trend colors: green for positive, red for negative
- [ ] Vertical divider visible between "Best today" and comparison
- [ ] Card uses `bgCard` background, 14pt radius, 14pt padding

---

### Subtask T005 – Create LastWorkoutCardView.swift (Compact Card)

- **Purpose**: Shows the top working sets from the most recent previous session to help users match or beat their last performance.
- **File**: `Reppo/Features/Workout/Views/Components/LastWorkoutCardView.swift` (NEW)
- **Parallel?**: Yes — independent from T004 and T006.

**Interface**:
```swift
struct LastWorkoutCardView: View {
    let info: LastWorkoutInfo
    let unitPreference: UnitPreference
    let isFullWidth: Bool  // true when e1RM card is hidden (duration exercises)
}
```

**Layout**:
```
┌─────────────────┐
│  [icon] Last     │  Header: clock.arrow.circlepath SF Symbol
│  Workout         │
│                  │
│  85×8, 45×8     │  18pt bold, textPrimary
│  9 days ago      │  12pt med, textTertiary
└─────────────────┘
```

**Steps**:

1. **Header row**: Icon + title.
   - Icon: `Image(systemName: "clock.arrow.circlepath")` sized 14pt.
   - Icon background: `Color.accentColor.opacity(0.08)`, 22×22, 6pt radius.
   - Title: `"Last Workout"` in `.system(size: 12, weight: .medium)`, `Color.textSecondary`.

2. **Top sets display**:
   - Join `info.topSets.map(\.formattedLabel)` with `", "`.
   - Font: `.system(size: 18, weight: .bold)`, color: `Color.textPrimary`.
   - If `unitPreference == .imperial`, the formatted label should display in lbs. However, `formattedLabel` is pre-formatted by the provider in kg. **Note**: For unit conversion, either:
     - (a) The provider formats with the correct unit, OR
     - (b) The view reformats from the raw `weight`/`reps` values.
   - **Recommended approach**: Use `info.topSets` raw `weight` and `reps` to format in the view with the correct unit preference. Fall back to `formattedLabel` for duration-based sets.

3. **Relative time**: `info.relativeTimeLabel` in `.system(size: 12, weight: .medium)`, `Color.textTertiary`.

4. **Empty state**: If `info.topSets.isEmpty`, show `"No previous data"` centered, `.system(size: 14, weight: .medium)`, `Color.textTertiary`.

5. **Card container**: Same as hero card — `bgCard`, 14pt radius, 14pt padding. VStack with `.leading` alignment, spacing 6.

6. **Full-width mode**: When `isFullWidth == true`, the card has no frame constraints (it naturally takes full width from the parent). When `false`, it shares an HStack with `EstimatedRepsCardView`.

**Validation**:
- [ ] Top sets display at 18pt bold
- [ ] Relative time label is correct
- [ ] Empty state shows "No previous data"
- [ ] Card matches design tokens (bgCard, 14pt radius)

---

### Subtask T006 – Create EstimatedRepsCardView.swift (Compact Card)

- **Purpose**: Shows the estimated weight for the user's current rep target, reducing guesswork for weight selection.
- **File**: `Reppo/Features/Workout/Views/Components/EstimatedRepsCardView.swift` (NEW)
- **Parallel?**: Yes — independent from T004 and T005.

**Interface**:
```swift
struct EstimatedRepsCardView: View {
    let info: EstimatedRepsInfo
    let unitPreference: UnitPreference
}
```

**Layout**:
```
┌─────────────────┐
│  [icon] Est.     │  Header: target SF Symbol
│  for 8 reps      │
│                  │
│  85 kg           │  18pt bold, textPrimary
│  Based on recent │  11pt semi, textTertiary
│  data            │
└─────────────────┘
```

**Steps**:

1. **Header row**: Icon + dynamic title.
   - Icon: `Image(systemName: "target")` sized 14pt.
   - Icon background: `Color.accentColor.opacity(0.08)`, 22×22, 6pt radius.
   - Title: `"Est. for \(info.targetReps) reps"` in `.system(size: 12, weight: .medium)`, `Color.textSecondary`.

2. **Estimated weight value**:
   - Convert if imperial: `UnitConversion.kgToLbs(info.estimatedWeight)`.
   - Format: integer if whole number, otherwise 1 decimal.
   - Append unit: `" kg"` or `" lbs"`.
   - Font: `.system(size: 18, weight: .bold)`, `Color.textPrimary`.

3. **Source label**: `info.sourceLabel` ("Based on recent data") in `.system(size: 11, weight: .semibold)`, `Color.textTertiary`.

4. **Card container**: `bgCard`, 14pt radius, 14pt padding. VStack `.leading`, spacing 6.

5. **Note**: This entire view is only rendered when `info` is non-nil. The parent (`ExerciseInfoSectionView`) handles the nil check.

**Validation**:
- [ ] Dynamic rep count in title (e.g., "Est. for 8 reps", "Est. for 5 reps")
- [ ] Weight formatted correctly with unit
- [ ] Source label visible at 11pt

---

### Subtask T007 – Create ExerciseInfoSectionView.swift (Container)

- **Purpose**: The container view that renders the section header and arranges the three card views according to the layout contract. Handles nil/loading states and tracking type visibility.
- **File**: `Reppo/Features/Workout/Views/Components/ExerciseInfoSectionView.swift` (NEW)
- **Parallel?**: No — depends on T004, T005, T006.

**Interface**:
```swift
struct ExerciseInfoSectionView: View {
    let data: ExerciseInfoData?
    let unitPreference: UnitPreference
    let isLoading: Bool
}
```

**Steps**:

1. **Guard clause**: If `data == nil` or `isLoading == true`, render `EmptyView()`. No skeleton placeholders.

2. **Section header**:
   ```swift
   Text("EXERCISE INFO")
       .font(.system(size: 11, weight: .semibold))
       .foregroundColor(.textTertiary)
       .kerning(0.8)
       .textCase(.uppercase)
   ```

3. **Card layout** — use VStack with 12pt spacing:
   ```swift
   VStack(spacing: 12) {
       // Hero card (if e1RM available)
       if let e1RMInfo = data.e1RMInfo {
           E1RMCardView(info: e1RMInfo, unitPreference: unitPreference)
       }

       // Compact cards row
       HStack(spacing: 12) {
           if let lastWorkoutInfo = data.lastWorkoutInfo {
               LastWorkoutCardView(
                   info: lastWorkoutInfo,
                   unitPreference: unitPreference,
                   isFullWidth: data.e1RMInfo == nil && data.estimatedRepsInfo == nil
               )
           }
           if let estimatedRepsInfo = data.estimatedRepsInfo {
               EstimatedRepsCardView(
                   info: estimatedRepsInfo,
                   unitPreference: unitPreference
               )
           }
       }
   }
   ```

4. **Tracking type visibility logic**:
   - `weightReps` / `weightRepsDuration`: Show all three cards.
   - `duration` / `weightDistance` / `custom`: Hide E1RM card, hide Est. Reps card. Last Workout gets `isFullWidth: true`.
   - If ALL card data is nil → render `EmptyView()` (nothing to show).

5. **Full container**:
   ```swift
   VStack(alignment: .leading, spacing: 10) {
       // Section header
       Text("EXERCISE INFO")
           .font(.system(size: 11, weight: .semibold))
           .foregroundColor(.textTertiary)
           .kerning(0.8)

       // Cards
       VStack(spacing: 12) { ... }
   }
   ```

6. **Note on padding**: This view does NOT apply horizontal padding. The parent (`ActiveWorkoutView`) applies `.padding(.horizontal, 20)` to match the `SetTableView` spacing.

**Validation**:
- [ ] Section header "EXERCISE INFO" renders at 11pt semibold, textTertiary, uppercase, 0.8 letter spacing
- [ ] Hero card spans full width above compact cards
- [ ] Compact cards are side-by-side in HStack with equal width
- [ ] Duration exercises show only Last Workout at full width
- [ ] EmptyView rendered when no data or loading

## Risks & Mitigations

- **Risk**: Compact cards render at unequal heights → **Mitigation**: Use `.frame(maxWidth: .infinity)` on each compact card so they share HStack space equally. Consider `.frame(minHeight:)` if needed.
- **Risk**: Long set labels overflow on small screens → **Mitigation**: Use `.lineLimit(1)` on value text; `formattedLabel` is intentionally compact ("85×8").
- **Risk**: Unit preference not available → **Mitigation**: Default to `.metric` if HealthProfile can't be loaded.

## Definition of Done Checklist

- [ ] All 4 view files created in `Reppo/Features/Workout/Views/Components/`
- [ ] E1RMCardView handles all 4 display states
- [ ] LastWorkoutCardView handles normal + empty + full-width states
- [ ] EstimatedRepsCardView shows dynamic rep count
- [ ] ExerciseInfoSectionView handles nil data, loading, tracking type visibility
- [ ] All cards use exact design tokens from design-system.md
- [ ] Unit conversion (kg/lbs) works correctly in all cards
- [ ] SwiftUI previews work with sample data

## Review Guidance

- Compare card styling pixel-by-pixel against design tokens (bgCard, 14pt radius, correct font sizes).
- Verify tracking type visibility: duration exercises should show ONLY Last Workout.
- Check unit conversion works for both `.metric` and `.imperial` preferences.
- Verify empty state rendering for each card.
- Ensure `ExerciseInfoSectionView` returns `EmptyView` when data is nil.

## Activity Log

- 2026-03-01T19:53:31Z – system – lane=planned – Prompt created.
<<<<<<< HEAD
- 2026-03-01T20:12:53Z – claude_opus –shell_pid=78130 – lane=doing – Started implementation via workflow command
- 2026-03-01T20:17:17Z – claude_opus –shell_pid=78130 – lane=for_review – Ready for review: 4 SwiftUI card views (E1RMCardView hero, LastWorkoutCardView, EstimatedRepsCardView, ExerciseInfoSectionView container). All design tokens match, unit conversion works, previews included. Build clean.
- 2026-03-01T20:26:10Z – claude_opus –shell_pid=80517 – lane=doing – Started review via workflow command
- 2026-03-01T20:27:37Z – claude_opus –shell_pid=80517 – lane=done – Review passed: All 4 SwiftUI views match design tokens exactly (bgCard, 14pt radius/padding, correct font sizes/weights/colors). Unit conversion (kg/lbs) works in all cards. E1RMCardView handles all 4 display states. Container correctly gates cards by tracking type and isFullWidth. Previews cover all states. Build clean.
=======
- 2026-03-01T20:12:53Z – claude-opus – shell_pid=78130 – lane=doing – Started implementation via workflow command
- 2026-03-01T20:17:17Z – claude-opus – shell_pid=78130 – lane=for_review – Ready for review: 4 SwiftUI card views (E1RMCardView hero, LastWorkoutCardView, EstimatedRepsCardView, ExerciseInfoSectionView container). All design tokens match, unit conversion works, previews included. Build clean.
>>>>>>> 014-exercise-info-active-workout-WP03
