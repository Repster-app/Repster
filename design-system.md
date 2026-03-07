# Workout App — Design System

> Reference document for building consistent screens in SwiftUI.
> Derived from the Home, Day View, and Exercise Tracking mockups.

---

## 1. Design Principles

These aren't aesthetic preferences — they're rules that keep the app feeling cohesive as you add screens.

**Quiet confidence.** The app should feel like a well-made tool, not a tech demo. No glows, no gradients, no blur effects. Flat surfaces, clear typography, muted color.

**Data first.** Every screen's job is to present workout data clearly. Decoration that doesn't serve comprehension gets cut. When in doubt, show the number bigger and remove the label.

**Consistent density.** Cards have the same padding. Rows have the same height. Gaps between sections are predictable. The user should never feel like two screens were designed by different people.

**Progressive disclosure.** Home shows summaries → Day View shows exercise cards → Exercise Tracking shows individual sets. Each level adds detail without repeating the previous level's job.

**Gym-proof interaction.** Large tap targets (minimum 44pt). High contrast text on dark backgrounds. Inputs that work with sweaty fingers. No tiny buttons, no swipe-to-reveal actions for critical functions.

---

## 2. Color Tokens

### Backgrounds (darkest → lightest)

| Token              | Hex       | Usage                                      |
|--------------------|-----------|---------------------------------------------|
| `bg`               | `#111113` | Screen background, root view                |
| `bgCard`           | `#1B1B1F` | Cards, table containers, nav items          |
| `bgHover`          | `#222228` | Pressed/highlighted state for cards         |
| `bgSubtle`         | `#262630` | Set number badges, progress bar tracks, tags |
| `bgInput`          | `#1F1F25` | Text input field backgrounds                |

### SwiftUI definition

```swift
extension Color {
    static let bg        = Color(red: 0.067, green: 0.067, blue: 0.075)
    static let bgCard    = Color(red: 0.106, green: 0.106, blue: 0.122)
    static let bgHover   = Color(red: 0.133, green: 0.133, blue: 0.157)
    static let bgSubtle  = Color(red: 0.149, green: 0.149, blue: 0.188)
    static let bgInput   = Color(red: 0.122, green: 0.122, blue: 0.145)
}
```

### Text

| Token      | Hex       | Usage                              |
|------------|-----------|-------------------------------------|
| `text`     | `#EAEAEF` | Primary text, headings, values      |
| `textMid`  | `#9999A8` | Secondary text, descriptions        |
| `textDim`  | `#5C5C6E` | Tertiary text, labels, placeholders |

```swift
extension Color {
    static let textPrimary   = Color(red: 0.918, green: 0.918, blue: 0.937)
    static let textSecondary = Color(red: 0.600, green: 0.600, blue: 0.659)
    static let textTertiary  = Color(red: 0.361, green: 0.361, blue: 0.431)
}
```

### Accent Colors

| Token       | Hex       | Soft variant (10% opacity)     | Usage                          |
|-------------|-----------|-------------------------------|--------------------------------|
| `blue`      | `#5B8DEF` | `rgba(91, 141, 239, 0.10)`   | Primary actions, active states, links |
| `green`     | `#5EC269` | `rgba(94, 194, 105, 0.08)`   | Completed states, positive trends     |
| `gold`      | `#D4A23A` | `rgba(212, 162, 58, 0.10)`   | PR badges, warmup indicators          |
| `red`       | `#E05555` | `rgba(224, 85, 85, 0.08)`    | Negative trends, delete actions       |

```swift
extension Color {
    static let accent      = Color(red: 0.357, green: 0.553, blue: 0.937)
    static let accentSoft  = accent.opacity(0.1)
    static let success     = Color(red: 0.369, green: 0.761, blue: 0.412)
    static let successSoft = success.opacity(0.08)
    static let gold        = Color(red: 0.831, green: 0.635, blue: 0.227)
    static let goldSoft    = gold.opacity(0.1)
    static let danger      = Color(red: 0.878, green: 0.333, blue: 0.333)
    static let dangerSoft  = danger.opacity(0.08)
}
```

### Border

```swift
static let border = Color.white.opacity(0.06)
```

---

## 3. Typography

### Font

**DM Sans** throughout the entire app. No monospace, no secondary font families.

```swift
// If using custom font:
.font(.custom("DMSans-Regular", size: 15))

// Or use system font as fallback — the key is consistency:
.font(.system(size: 15, weight: .regular, design: .default))
```

### Type Scale

| Name            | Size | Weight    | Usage                                    |
|-----------------|------|-----------|------------------------------------------|
| `pageTitle`     | 26pt | Bold (700)| Screen titles ("Workout")                |
| `exerciseTitle` | 20pt | Bold (700)| Exercise names in tracking view          |
| `sectionTitle`  | 17pt | SemiBold  | Nav titles, card titles                  |
| `heroValue`     | 32pt | Bold (700)| Large stat numbers (1RM)                 |
| `statValue`     | 18pt | Bold (700)| Summary stat numbers                     |
| `setValue`      | 16pt | SemiBold  | Set table values (weight, reps)          |
| `body`          | 15pt | Regular   | Exercise names in cards, descriptions    |
| `cardTitle`     | 15pt | SemiBold  | Recent workout names                     |
| `bodySmall`     | 14pt | Medium    | Quick action titles, nav labels          |
| `caption`       | 13px | Medium    | Dates, subtitles, tab labels             |
| `label`         | 12pt | Medium    | Info card labels, tag text               |
| `microLabel`    | 11pt | SemiBold  | Section headers, column headers          |
| `tinyLabel`     | 10pt | Medium    | Stat labels, day abbreviations, nav text |

### Section Headers

All-caps, letter-spacing 0.08em, `textDim` color, 11pt semibold.

```swift
Text("THIS WEEK")
    .font(.system(size: 11, weight: .semibold))
    .foregroundColor(.textTertiary)
    .kerning(0.8)
    .textCase(.uppercase)
```

---

## 4. Spacing & Layout

### Standard Spacing Values

| Token   | Value | Usage                                |
|---------|-------|--------------------------------------|
| `xs`    | 4pt   | Gap between day chips, inline items  |
| `sm`    | 6-8pt | Gap between cards, small padding     |
| `md`    | 10-12pt| Section gap, card internal padding  |
| `lg`    | 16pt  | Title bar margin-bottom              |
| `xl`    | 20pt  | Section to section gap               |
| `xxl`   | 24pt  | Major section breaks                 |

### Screen Padding

- Horizontal padding: **20pt** on all screens
- No horizontal padding on scrollable strips (day selector, exercise tabs) — they bleed to edges with 20pt internal padding

### Card Padding

- Standard card: **14–16pt** all sides
- Summary strip items: **12pt vertical, 10pt horizontal**
- Set table rows: **0pt vertical (height-based), 12pt horizontal**

---

## 5. Corner Radii

| Token    | Value | Usage                                  |
|----------|-------|----------------------------------------|
| `r`      | 14pt  | Cards, table containers, keyboard      |
| `rSm`    | 10pt  | Buttons, icon buttons, input fields    |
| `rChip`  | 8pt   | Tabs, tags, badges, set number badges  |
| `rBadge` | 4-6pt | PR badges, small indicators            |
| `rFull`  | 50%   | Completion checkmarks (circular)       |

---

## 6. Component Library

### 6.1 Navigation

#### Top Bar (standard)
- Back button (blue text + chevron left) on the left
- Title in center or left-aligned depending on context
- Action buttons on the right (34×34pt, `bgCard`, rounded `rSm`)

#### Exercise Tab Strip
- Horizontally scrollable
- Each tab: `bgCard` background, `textDim` color, 8pt radius, 7pt vertical / 14pt horizontal padding
- Active tab: `blue` background, white text, semibold
- Show shortened exercise names to fit more tabs

#### Bottom Nav (home screens only)
- 5 items with center FAB
- FAB: 46×46pt, `blue` fill, 14pt radius, elevated -16pt from nav baseline
- Nav items: 21pt icons, 10pt labels, `textDim` default, `blue` when active
- Background: gradient fade from `bg` (65% stop) to transparent

**Rule: Exercise tracking view does NOT have a bottom nav.** It's a focused full-screen experience.

### 6.2 Cards

#### Standard Card
```
Background: bgCard
Radius: 14pt (r)
Padding: 14-16pt
Border: none (no visible borders on cards)
Hover/press: bgHover
```

#### Summary Stat Card
- Row of 4 equal-width items inside one `bgCard` container
- Large value (18pt bold) + tiny label (10pt, uppercase, `textDim`)
- Dividers between items: 1px `border` color, inset 2pt top/bottom

#### Recent Workout Card
```
Structure:
├── Row: name (15pt semibold) | date (12pt, textDim)
├── Row: stat × 4 (value 14pt bold + label 10pt uppercase)
└── Row: muscle tags (bgSubtle pills, 11pt, textMid)
```

#### Exercise Card (Day View)
```
Structure:
├── Header: index (bgSubtle badge) + name + set count + green check
├── Set Table: column headers + rows
│   ├── Set number | Weight with unit | Reps | PR badge area
│   └── Warmup rows at 0.45 opacity
└── Footer: green dot + "Best: 85 kg × 8"
```

### 6.3 Set Table (Exercise Tracking)

Grid layout with 5 columns:

| Column    | Width   | Content                          |
|-----------|---------|----------------------------------|
| Set       | 42pt    | Number badge or warmup "W"       |
| Weight    | 1fr     | Editable input field             |
| Reps      | 1fr     | Editable input field             |
| PR        | 44pt    | Badge or empty                   |
| Check     | 40pt    | Checkbox                         |

- Row height: **52pt**
- Row dividers: 1px at `white 3% opacity`
- Warmup rows: **0.5 opacity** on entire row

#### Set Number Badge
- Default: 28×28pt, `bgSubtle`, 8pt radius, 13pt semibold `textDim`
- Completed: same size, `green` fill, white checkmark icon
- Warmup: no background, italic "W"

#### Input Field
- Background: `bgInput`
- Border: 1px `border`
- Focused: border becomes `blue`, background gets slight blue tint
- Completed: background `green` at 6% opacity, border `green` at 15% opacity
- Text: 16pt semibold, centered

#### Completion Checkbox
- 26×26pt, 6pt radius
- Unchecked: 2px border `textDim`, empty
- Checked: `blue` fill, white checkmark

### 6.4 Badges

#### PR Badge
- `goldSoft` background, `gold` text
- 1px border at `gold` 20% opacity
- Star icon + "PR" text
- Size: 8-9pt bold, 3pt vertical / 5-6pt horizontal padding

#### Match Badge
- Same layout, but `blueSoft` / `blue` / "="

#### Muscle Tag
- `bgSubtle` background (in day view cards)
- OR `bgCard` background (in day view header area)
- `textMid` text, 11-12pt medium, 3-5pt vertical / 8-10pt horizontal padding
- 5-6pt radius

### 6.5 Custom Numeric Keyboard

```
Structure:
├── Toolbar
│   ├── Field label ("Set 4 → kg") — 13pt semibold, field name in blue
│   └── Actions: "Next" (blue) + "Done" (blue)
├── Quick Values Row
│   └── 5 equal buttons: −5, −2.5, Last, +2.5, +5
├── Number Grid (3 columns)
│   └── 1-9, dot, 0, backspace
```

- Background: `#1A1A1E` (slightly lighter than bgCard)
- Top border: 1px `white 8% opacity`
- Key size: **48pt height**, 10pt radius
- Key background: `#2A2A30`
- Key press: `#3A3A42`
- Backspace key: `#222228` with icon in `textMid`
- Key text: 22pt semibold
- Quick value buttons: `bgSubtle`, 12pt semibold, `textMid`

**Animation:** Slides up from bottom, 350ms, cubic-bezier(0.32, 0.72, 0, 1). Content area shrinks simultaneously.

### 6.6 Info Section (Exercise Tracking)

#### Hero Card
```
Layout: horizontal
├── Left: label (12pt textDim) + large value (32pt bold) + unit (16pt textMid)
├── Divider: 1px vertical, 40pt tall, border color
└── Right: 2 rows with colored dots
    ├── Green dot + "Best today: 85 × 8"
    └── Red dot + "vs 4wk ago: −1.1 kg"
```

#### Info Tiles (2-up row)
```
Layout: equal width, side by side
├── Top row: label (11pt textDim) + icon (22×22pt, colored soft bg, 6pt radius)
├── Value: 17pt bold
└── Subtitle: 11pt textDim
```

---

## 7. Iconography

- Stroke-based icons only (no filled icons except checkmarks and stars)
- Stroke width: **1.7–1.8pt** for nav icons, **2pt** for action buttons
- Size: 21pt for nav bar, 16-17pt for action buttons, 12pt for inline/info
- Rounded line caps and joins
- Source: Lucide or SF Symbols — keep consistent across screens

---

## 8. Motion & Transitions

### Screen Entry
- Cards fade in with translateY(8pt) → 0, 400ms ease
- Staggered: 40ms delay between each element group

### Keyboard
- Slide up: 350ms, `cubic-bezier(0.32, 0.72, 0, 1)` (fast start, gentle settle)
- Content area height change: same timing, synchronized

### Micro-interactions
- Card press: background color change, 150ms ease
- Checkbox toggle: 150ms ease
- Input focus: border color change, 150ms ease

### What NOT to animate
- No spring physics on cards
- No scale transforms on press
- No blur transitions
- No color cycling or pulsing

---

## 9. Screen Inventory & Hierarchy

```
Home (bottom nav visible)
├── Day Strip — tap a day with workout dot
├── Start Workout CTA
├── Quick Actions — Copy Previous, Templates
├── Weekly Progress
└── Recent Workouts — tap a card ↓

Day View (bottom nav visible)
├── Back → Home
├── Summary Strip
├── Muscle Tags
└── Exercise Cards — tap a card ↓

Exercise Tracking (NO bottom nav — focused screen)
├── Back → Day View
├── Exercise Tab Strip — switch exercises
├── Exercise Title + Settings/Notes buttons
├── Set Table (editable)
│   └── Tap input → Custom Keyboard slides up
├── Add Set / Add Warmup
└── Exercise Info (Hero + Tiles)
```

---

## 10. SwiftUI Implementation Notes

### Card Pattern
```swift
struct AppCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
    }
}
```

### Section Header Pattern
```swift
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.textTertiary)
            .kerning(0.8)
            .padding(.horizontal, 20)
    }
}
```

### Screen Template
```swift
struct ScreenTemplate<Content: View>: View {
    let content: Content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                content
            }
        }
        .background(Color.bg)
    }
}
```

### Input Field Style
```swift
struct SetInputStyle: TextFieldStyle {
    let isFocused: Bool
    let isCompleted: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 16, weight: .semibold))
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                isCompleted ? Color.success.opacity(0.06) :
                isFocused ? Color.accent.opacity(0.06) :
                Color.bgInput
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isCompleted ? Color.success.opacity(0.15) :
                        isFocused ? Color.accent :
                        Color.border,
                        lineWidth: 1
                    )
            )
            .cornerRadius(8)
    }
}
```

---

## 11. Checklist for New Screens

When building a new screen, verify:

- [ ] Background is `bg` (#111113)
- [ ] Cards use `bgCard` with 14pt radius, no borders
- [ ] Text hierarchy: primary / secondary / tertiary only
- [ ] Section headers are uppercase, 11pt, `textDim`, letter-spaced
- [ ] Horizontal screen padding is 20pt
- [ ] No gradients, glows, or shadows on cards
- [ ] Blue is the only accent for interactive elements
- [ ] Green only for completed/positive states
- [ ] Gold only for PRs and warmup indicators
- [ ] Bottom nav present on main tab screens only
- [ ] Focused screens (tracking, settings detail) have no bottom nav
- [ ] Animations are fade + translateY, staggered, ≤400ms
- [ ] Touch targets are ≥44pt
- [ ] Font is DM Sans (or system default) — no monospace anywhere
