# Contract: Exercise Info Views

**Location**: `Reppo/Features/Workout/Views/Components/`

## ExerciseInfoSectionView

**File**: `ExerciseInfoSectionView.swift`
**Type**: SwiftUI View (container)

### Interface

```swift
struct ExerciseInfoSectionView: View {
    let data: ExerciseInfoData?
    let unitPreference: UnitPreference
    let isLoading: Bool
}
```

### Layout Contract

```
┌──────────────────────────────────────┐
│  EXERCISE INFO          (11pt semi,  │
│                     uppercase, tert) │
├──────────────────────────────────────┤
│                                      │
│  ┌──────────────────────────────┐    │
│  │       E1RM CARD (hero)       │    │   Full width
│  │    105.5 kg  │  Best today   │    │   bgCard, 14pt radius
│  │              │  85 × 8       │    │
│  │              │  vs 4wk: +2.3 │    │
│  └──────────────────────────────┘    │
│                                      │
│  ┌──────────┐  12pt  ┌──────────┐   │
│  │LAST WKOUT│  gap   │EST. REPS │   │   Side-by-side
│  │ 85×8     │        │ Est. 8:  │   │   Equal width
│  │ 45×8     │        │  85 kg   │   │   bgCard, 14pt radius
│  │ 9d ago   │        │ Based on │   │
│  └──────────┘        └──────────┘   │
│                                      │
└──────────────────────────────────────┘
```

### Behavior

- When `data == nil` or `isLoading == true`: Show nothing (don't render placeholder skeleton)
- When `trackingType == .duration`: Hide E1RM card; Last Workout spans full width; Est. Reps hidden
- Section header "EXERCISE INFO" always visible when data is non-nil
- Gap between section header and first card: 10pt
- Gap between hero card and compact cards: 12pt

---

## E1RMCardView (Hero)

**File**: `E1RMCardView.swift`

### Interface

```swift
struct E1RMCardView: View {
    let info: E1RMInfo
    let unitPreference: UnitPreference
}
```

### Layout

```
┌─────────────────────────────────────┐
│  ⏱ Estimated 1RM    (12pt med, sec)│  Icon: gauge.open.with.lines.needle.33percent (SF Symbol)
│                                     │  Icon bg: accentSoft, 6pt radius
│  105.5 kg            (32pt bold, pr)│
│                      ┊              │  Vertical divider (1px, border color)
│  Best today: 85 × 8  ┊ vs 4wk ago  │  12pt med labels
│                      ┊ +2.3 kg ▲   │  Delta: success/danger color
└─────────────────────────────────────┘
```

### States

| State | Display |
|-------|---------|
| Has current session e1RM + history | Full display with delta |
| Has current session e1RM, no history | e1RM value + "Best today" only, no comparison |
| No current session sets (fallback) | Shows `ExerciseStats.bestE1RM` as "All-time best", no "Best today" |
| No data at all | "No data yet" placeholder text |

---

## LastWorkoutCardView (Compact)

**File**: `LastWorkoutCardView.swift`

### Interface

```swift
struct LastWorkoutCardView: View {
    let info: LastWorkoutInfo
    let unitPreference: UnitPreference
    let isFullWidth: Bool  // true when e1RM card is hidden (duration exercises)
}
```

### Layout

```
┌─────────────────┐
│  📋 Last Workout │  Icon: clock.arrow.circlepath (SF Symbol)
│                  │  Icon bg: accentSoft, 6pt radius
│  85×8, 45×8     │  18pt bold, textPrimary
│  9 days ago      │  12pt med, textTertiary
└─────────────────┘
```

### States

| State | Display |
|-------|---------|
| Has previous workout | Top sets + relative time |
| No previous workout | "No previous data" centered in card |

### Formatting

- Weight × Reps format: `"{weight}×{reps}"` (e.g., "85×8")
- Multiple sets separated by `, ` (e.g., "85×8, 45×8")
- Duration format: `UnitConversion.formatDuration(seconds)` (e.g., "2:30")
- Relative time: `RelativeDateTimeFormatter` with `.numeric` style

---

## EstimatedRepsCardView (Compact)

**File**: `EstimatedRepsCardView.swift`

### Interface

```swift
struct EstimatedRepsCardView: View {
    let info: EstimatedRepsInfo
    let unitPreference: UnitPreference
}
```

### Layout

```
┌─────────────────┐
│  🎯 Est. for 8  │  Icon: target (SF Symbol)
│                  │  Icon bg: accentSoft, 6pt radius
│  85 kg           │  18pt bold, textPrimary
│  Based on recent │  11pt semi, textTertiary
│  data            │
└─────────────────┘
```

### States

| State | Display |
|-------|---------|
| Has estimate | Estimated weight + source label |
| Insufficient data | Card is hidden (not rendered) |

---

## Design Tokens Reference

| Token | Value | Usage |
|-------|-------|-------|
| `bgCard` | `#1B1B1F` | Card background |
| `textPrimary` | `#EAEAEF` | Large values |
| `textSecondary` | `#9999A8` | Secondary info |
| `textTertiary` | `#5C5C6E` | Labels, section header |
| `success` | `#5EC269` | Positive delta |
| `danger` | `#E05555` | Negative delta |
| `border` | `white @ 6%` | Card dividers |
| Card radius | `14pt` | All cards |
| Card padding | `14pt` | All sides |
| Hero value | `32pt bold` | e1RM number |
| Stat value | `18pt bold` | Compact card values |
| Label | `12pt medium` | "Best today:", "vs 4wk ago:" |
| Section header | `11pt semibold` | "EXERCISE INFO" uppercase |
| Micro | `11pt semibold` | "Based on recent data" |
