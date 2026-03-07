---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
  - "T005"
title: "Design Tokens + Atomic Components"
phase: "Phase 0 - Foundation"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "16080"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: []
history:
  - timestamp: "2026-02-24T14:26:08Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP01 – Design Tokens + Atomic Components

## Implementation Command

No dependencies — start from main:
```bash
spec-kitty implement WP01
```

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

- All design token colors defined as Swift `Color` extensions matching design-system.md hex values exactly
- 4 atomic UI components created: SetInputField, PRBadgeView, SetNumberBadge, CompletionCheckbox
- Each component renders correctly with Xcode previews
- All components follow design-system.md specs (sizes, colors, fonts, spacing)
- All tap targets >= 44×44pt per constitution
- Project compiles with zero errors

## Context & Constraints

**Feature**: 006-active-workout-screen
**Architecture**: SwiftUI views only — no business logic, no service calls. Pure presentational components.
**Constitution**: `.kittify/memory/constitution.md` — dark mode only, no third-party UI libs, SF Symbols for icons, system font for v1.
**Plan**: `kitty-specs/006-active-workout-screen/plan.md` — design token table in "Design Token Usage" section.
**Design System Reference**: `design-system.md` Sections 2 (Colors), 4 (Spacing), 6.3 (Set Table), 6.4 (Badges).

**Key constraint**: These are leaf components — they receive data via parameters, emit actions via closures. No `@Environment` service access. No ViewModel dependency.

## Subtasks & Detailed Guidance

### Subtask T001 – Create Color Extension with Design Tokens

- **Purpose**: Centralize all design-system color tokens as `Color` static properties. Every view in this feature (and future features) uses these tokens instead of raw hex values.
- **File**: `Reppo/Core/Extensions/DesignTokens.swift` (new file)
- **Parallel?**: Yes — independent file.

**Steps**:
1. Create `Reppo/Core/Extensions/DesignTokens.swift`
2. Add a `Color` extension with static properties for each token
3. Use `Color(red:green:blue:)` initializer with values converted from hex (0-1 range)
4. For opacity-based tokens (blueSoft, goldSoft, successSoft, border), use `Color.white.opacity()` or base color `.opacity()`

**Token definitions** (from design-system.md):

| Token Name | Hex / Definition | Usage |
|-----------|-----------------|-------|
| `bg` | #111113 | Screen background |
| `bgCard` | #1B1B1F | Cards, containers |
| `bgHover` | #222228 | Pressed/highlighted state |
| `bgSubtle` | #262630 | Badges, tags |
| `bgInput` | #1F1F25 | Text input backgrounds |
| `textPrimary` | #EAEAEF | Headings, values |
| `textSecondary` | #9999A8 | Descriptions |
| `textTertiary` | #5C5C6E | Labels, tertiary |
| `blue` | #5B8DEF | Primary actions, active states |
| `blueSoft` | blue at 10% opacity | Match badge bg |
| `green` | #5EC269 | Completed states |
| `successSoft` | green at 6% opacity | Completed row bg |
| `gold` | #D4A23A | PR badges |
| `goldSoft` | gold at 10% opacity | PR badge bg |
| `red` | #E05555 | Destructive actions |
| `border` | white at 6% opacity | Input borders |

**Example implementation**:
```swift
import SwiftUI

extension Color {
    // MARK: - Backgrounds
    static let bg = Color(red: 0x11/255, green: 0x11/255, blue: 0x13/255)
    static let bgCard = Color(red: 0x1B/255, green: 0x1B/255, blue: 0x1F/255)
    // ... etc

    // MARK: - Semantic
    static let blueSoft = Color.appBlue.opacity(0.10)
    static let goldSoft = Color.appGold.opacity(0.10)
    static let successSoft = Color.appGreen.opacity(0.06)
    static let appBorder = Color.white.opacity(0.06)
}
```

**Important**: Check for naming collisions with SwiftUI built-in colors (`.blue`, `.green`, `.red` exist). Use a prefix like `app` (e.g., `appBlue`, `appGreen`) or a nested enum. Whichever you choose, be consistent.

**Validation**:
- [ ] All 16+ tokens defined
- [ ] No naming collisions with SwiftUI
- [ ] Hex values match design-system.md exactly
- [ ] File compiles

### Subtask T002 – Create SetInputField Component

- **Purpose**: Reusable numeric input field for weight, reps, duration, and distance values in the set table. Used in every set row.
- **File**: `Reppo/Features/Workout/Views/Components/SetInputField.swift` (new file)
- **Parallel?**: Yes — independent file.

**Steps**:
1. Create the component file
2. Define the view with parameters: `value: Binding<String>`, `placeholder: String`, `keyboardType: UIKeyboardType`, `isCompleted: Bool`, `isFocused: FocusState<Bool>.Binding` (or use `@FocusState` internally)
3. Implement the three visual states:
   - **Default**: `bgInput` background, 1px `border` (white 6% opacity), text: 16pt semibold centered
   - **Focused**: border becomes `blue`, background gets slight blue tint (blue at 3-5% opacity)
   - **Completed**: background `green` at 6% opacity, border `green` at 15% opacity
4. Use `TextField` with the appropriate `.keyboardType()` modifier
5. Add Xcode preview with default, focused, and completed states

**Specifications**:
- Background: `bgInput` (#1F1F25)
- Border: 1px `border` (white 6% opacity) — use `.overlay(RoundedRectangle(...).stroke(...))`
- Text: 16pt semibold, centered — `.font(.system(size: 16, weight: .semibold))`, `.multilineTextAlignment(.center)`
- Corner radius: 6-8pt (match input field aesthetic)
- Height: fits within 52pt row height (approx 36-40pt)

**Validation**:
- [ ] Three visual states render correctly (default, focused, completed)
- [ ] Keyboard types work (.decimalPad for weight, .numberPad for reps/duration)
- [ ] Text is centered and 16pt semibold
- [ ] Xcode preview shows all states

### Subtask T003 – Create PRBadgeView Component

- **Purpose**: Renders the PR badge (gold star + "PR") or match badge (blue "=") based on `cachedPRStatus`. Shows nothing for nil or `.previous`.
- **File**: `Reppo/Features/Workout/Views/Components/PRBadgeView.swift` (new file)
- **Parallel?**: Yes — independent file.

**Steps**:
1. Create the component with parameter: `status: CachedPRStatus?`
2. Switch on status:
   - `.current` → Gold badge: `goldSoft` background, `gold` text, SF Symbol `star.fill` + "PR" text
   - `.matched` → Blue badge: `blueSoft` background, `blue` text, "=" text
   - `.previous` or `nil` → `EmptyView()` (no badge)
3. Badge sizing: 8-9pt bold text, 3pt vertical / 5-6pt horizontal padding
4. Add 1px border: `gold` at 20% opacity for PR badge, `blue` at 20% for match badge
5. Corner radius: small (4-6pt)

**Specifications** (from design-system.md Section 6.4):
- PR Badge: `goldSoft` bg, `gold` text, star icon + "PR", 1px gold 20% border
- Match Badge: `blueSoft` bg, `blue` text, "=" symbol, 1px blue 20% border
- Font: 8-9pt bold (`.caption2` weight `.bold` or `.system(size: 8, weight: .bold)`)
- Padding: 3pt vertical, 5-6pt horizontal

**Validation**:
- [ ] Gold badge renders for `.current` status
- [ ] Blue badge renders for `.matched` status
- [ ] Nothing renders for nil or `.previous`
- [ ] Badge fits within the 44pt PR column width
- [ ] Preview shows all 3 states

### Subtask T004 – Create SetNumberBadge Component

- **Purpose**: Shows the set number (1, 2, 3...), warmup indicator ("W"), or completion checkmark in the leftmost column of the set table.
- **File**: `Reppo/Features/Workout/Views/Components/SetNumberBadge.swift` (new file)
- **Parallel?**: Yes — independent file.

**Steps**:
1. Create the component with parameters: `number: Int`, `setType: SetType`, `isCompleted: Bool`
2. Switch on state:
   - **Default** (not warmup, not completed): 28×28pt frame, `bgSubtle` background, 8pt corner radius, number in 13pt semibold `textTertiary`
   - **Warmup** (`setType == .warmup`): No background, italic "W" in `textTertiary`
   - **Completed** (`isCompleted == true`): 28×28pt frame, `green` fill, white checkmark SF Symbol (`checkmark`)
3. Center content within the badge

**Specifications** (from design-system.md Section 6.3):
- Size: 28×28pt
- Default bg: `bgSubtle` (#262630)
- Corner radius: 8pt
- Font: 13pt semibold
- Warmup: italic "W", no background
- Completed: `green` fill, white `checkmark` icon

**Validation**:
- [ ] Default state shows number with bgSubtle background
- [ ] Warmup shows italic "W" with no background
- [ ] Completed shows green circle with white checkmark
- [ ] All states are 28×28pt
- [ ] Preview shows all 3 states

### Subtask T005 – Create CompletionCheckbox Component

- **Purpose**: The tap target for completing a set. Small visual checkbox with an expanded tap area for gym-friendly use.
- **File**: `Reppo/Features/Workout/Views/Components/CompletionCheckbox.swift` (new file)
- **Parallel?**: Yes — independent file.

**Steps**:
1. Create the component with parameters: `isChecked: Bool`, `onToggle: () -> Void`
2. Visual states:
   - **Unchecked**: 26×26pt frame, 6pt corner radius, 2pt `textTertiary` border, empty interior
   - **Checked**: 26×26pt frame, 6pt corner radius, `blue` fill, white `checkmark` SF Symbol
3. Expand tap area: `.frame(width: 44, height: 44)` outer container with `.contentShape(Rectangle())` to ensure the full 44×44pt area is tappable
4. Use `Button(action: onToggle)` for the tap handler

**Specifications** (from design-system.md Section 6.3):
- Visual size: 26×26pt
- Corner radius: 6pt
- Unchecked border: 2pt, `textTertiary` color
- Checked fill: `blue` (#5B8DEF)
- Checked icon: white `checkmark` SF Symbol
- Tap target: 44×44pt minimum

**Validation**:
- [ ] Unchecked shows bordered empty square
- [ ] Checked shows blue filled square with white checkmark
- [ ] Tap area is 44×44pt (verify with accessibility inspector or by tapping near edges)
- [ ] Preview shows both states

## Risks & Mitigations

- **Color naming collisions**: SwiftUI has built-in `.blue`, `.green`, `.red`. Use `appBlue` or similar prefix. Choose convention in T001 and use consistently in T002-T005.
- **Component reusability**: These components will be reused by features 007-010. Keep them general — parameterize fully, no hardcoded layout assumptions.

## Definition of Done Checklist

- [ ] All subtasks completed and validated
- [ ] DesignTokens.swift compiles with all tokens
- [ ] All 4 components have working Xcode previews
- [ ] All tap targets >= 44×44pt
- [ ] No hardcoded hex values in component files (all use design tokens)
- [ ] Project builds with zero errors

## Review Guidance

- Verify hex values match design-system.md exactly
- Verify component sizing matches specs (28×28 badge, 26×26 checkbox, etc.)
- Verify three visual states on each component
- Check that color extension naming is consistent and collision-free
- Verify no business logic leaked into components (pure presentational)

## Activity Log

- 2026-02-24T14:26:08Z – system – lane=planned – Prompt created.
- 2026-02-24T18:51:05Z – claude – shell_pid=14565 – lane=doing – Started implementation via workflow command
- 2026-02-24T18:58:51Z – claude – shell_pid=14565 – lane=for_review – Ready for review: 5 files created — DesignTokens.swift (16 color tokens), SetInputField (3 visual states), PRBadgeView (current/matched/empty), SetNumberBadge (default/warmup/completed), CompletionCheckbox (44pt tap target). Build succeeds with zero errors/warnings.
- 2026-02-24T18:59:46Z – claude – shell_pid=16080 – lane=doing – Started review via workflow command
- 2026-02-24T19:01:10Z – claude – shell_pid=16080 – lane=done – Review passed: All 17 color tokens match design-system.md exactly. 4 atomic components (SetInputField, PRBadgeView, SetNumberBadge, CompletionCheckbox) implement all visual states per spec. No hardcoded hex, no SwiftUI color collisions, no business logic. 44pt tap targets verified. Build succeeds with zero errors.
