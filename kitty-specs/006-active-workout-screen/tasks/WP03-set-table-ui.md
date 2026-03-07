---
work_package_id: "WP03"
subtasks:
  - "T012"
  - "T013"
  - "T014"
  - "T015"
  - "T016"
  - "T017"
title: "SetRowView + SetTableView — Set Table UI"
phase: "Phase 1 - Core UI"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "18740"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01", "WP02"]
history:
  - timestamp: "2026-02-24T14:26:08Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 – SetRowView + SetTableView — Set Table UI

## Implementation Command

Depends on WP01 and WP02:
```bash
spec-kitty implement WP03 --base WP02
```

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above.
- **Mark as acknowledged**: Update `review_status: acknowledged` when addressing feedback.

---

## Review Feedback

*[This section is empty initially.]*

---

## Objectives & Success Criteria

- `SetRowView` renders a single set row with correct components (badge, inputs, PR badge, checkbox)
- `SetTableView` renders the full set table with header row, set rows, and add buttons
- Column layout matches design-system Section 6.3: Set (42pt), Weight (1fr), Reps (1fr), PR (44pt), Check (40pt)
- Columns adapt to exercise `trackingType` (WEIGHT_REPS, DURATION, WEIGHT_DISTANCE, WEIGHT_REPS_DURATION)
- Warmup rows render at 0.5 opacity with "W" badge
- Completed rows render with green tint and green check badge
- Long-press context menu on rows provides "Edit Set Type" and "Delete Set"
- Row height is 52pt with 1px dividers at white 3% opacity

## Context & Constraints

**Feature**: 006-active-workout-screen — User Story 2 (Set Table Layout)
**Design System**: `design-system.md` Section 6.3 (Set Table), Section 6.4 (Badges)
**Plan**: `kitty-specs/006-active-workout-screen/plan.md` — Column adaptation section, design token table
**Constitution**: Dark mode only, 44pt minimum tap targets, SF Symbols, no third-party UI libs
**AGENT_RULES**: Section 7.5 — Set table columns adapt to trackingType

**Depends on**:
- WP01: Atomic components (SetInputField, PRBadgeView, SetNumberBadge, CompletionCheckbox) and design tokens
- WP02: ActiveWorkoutViewModel (provides data bindings via `currentSets`, `currentExercise`)

## Subtasks & Detailed Guidance

### Subtask T012 – Create SetRowView

- **Purpose**: A single row in the set table, composing the atomic components from WP01 into a horizontal layout.
- **File**: `Reppo/Features/Workout/Views/SetRowView.swift` (new file)

**Steps**:
1. Create `SetRowView` with parameters:
   - `set: WorkoutSet` (the set data)
   - `exercise: Exercise` (for trackingType to determine which input fields)
   - `setNumber: Int` (display number in the badge)
   - `weightText: Binding<String>` (input binding for weight field)
   - `repsText: Binding<String>` (input binding for reps field)
   - `durationText: Binding<String>` (input binding for duration field)
   - `distanceText: Binding<String>` (input binding for distance field)
   - `onComplete: () -> Void` (checkbox tap callback)

2. Layout as `HStack(spacing: 4)`:
   ```
   | SetNumberBadge(42pt) | Input fields (1fr each) | PRBadgeView(44pt) | CompletionCheckbox(40pt) |
   ```

3. Fixed-width columns use `.frame(width: N)`. Flexible input columns use `.frame(maxWidth: .infinity)`.

4. Row frame: `.frame(height: 52)` with `12pt` horizontal padding.

5. Bottom divider: `.overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.03)), alignment: .bottom)`

6. Input fields shown depend on `exercise.trackingType`:
   - `.weightReps` → weight + reps fields
   - `.duration` → duration field only
   - `.weightDistance` → weight + distance fields
   - `.weightRepsDuration` → weight + reps + duration fields

**Validation**:
- [ ] Row is 52pt tall
- [ ] Column widths match spec (Set 42pt, inputs flexible, PR 44pt, Check 40pt)
- [ ] Correct input fields shown for each trackingType
- [ ] Divider renders at bottom

### Subtask T013 – Create SetTableView

- **Purpose**: The container view that renders the header row and all set rows for the current exercise.
- **File**: `Reppo/Features/Workout/Views/SetTableView.swift` (new file)

**Steps**:
1. Create `SetTableView` with parameters:
   - `viewModel: ActiveWorkoutViewModel` (or pass sets/exercise directly)
   - Uses `viewModel.currentExercise` and `viewModel.currentSets`

2. Layout:
   ```swift
   VStack(spacing: 0) {
       // Header row
       headerRow(for: exercise.trackingType)

       // Set rows
       ScrollView {
           LazyVStack(spacing: 0) {
               ForEach(sets) { set in
                   SetRowView(...)
               }
           }
       }

       // Add buttons (T016)
   }
   .background(Color.bgCard)
   .cornerRadius(12)
   ```

3. Header row: Same column layout as SetRowView but with text labels instead of inputs:
   - "SET" | "WEIGHT" | "REPS" | "PR" | "✓"
   - Labels in `textTertiary`, 11-12pt semibold, uppercase
   - Adapt labels to trackingType (e.g., "DURATION" instead of "WEIGHT"/"REPS")

4. Use `LazyVStack` for performance with many sets.

5. Manage input state: Each set row needs `@State` text bindings for its input fields. Consider using a helper that converts `set.weight` (Double?) to/from String for the TextField.

**Validation**:
- [ ] Header row shows correct column labels
- [ ] All sets render as SetRowView rows
- [ ] bgCard background with rounded corners
- [ ] LazyVStack used for scrolling performance

### Subtask T014 – Implement Column Adaptation

- **Purpose**: The set table must show different columns based on `exercise.trackingType` per AGENT_RULES S7.5.
- **Files**: Both `SetRowView.swift` and `SetTableView.swift` (header labels)

**Steps**:
1. Create a helper (can be a private function or computed property):
   ```swift
   enum SetTableColumn: CaseIterable {
       case setNumber, weight, reps, duration, distance, prBadge, checkbox
   }

   func columnsForTrackingType(_ type: TrackingType) -> [SetTableColumn] {
       var cols: [SetTableColumn] = [.setNumber]
       switch type {
       case .weightReps: cols += [.weight, .reps]
       case .duration: cols += [.duration]
       case .weightDistance: cols += [.weight, .distance]
       case .weightRepsDuration: cols += [.weight, .reps, .duration]
       case .custom: cols += [.weight, .reps]  // fallback
       }
       cols += [.prBadge, .checkbox]
       return cols
   }
   ```

2. Both SetRowView and the header row use this function to determine which input fields / labels to show.

3. Header label mapping:
   | Column | Label |
   |--------|-------|
   | weight | "KG" or "WEIGHT" |
   | reps | "REPS" |
   | duration | "TIME" |
   | distance | "DIST" |

4. When there's only 1 input field (DURATION), it gets the full flexible width. When there are 2 or 3, they split evenly.

**Validation**:
- [ ] WEIGHT_REPS shows Weight + Reps columns
- [ ] DURATION shows single Duration column
- [ ] WEIGHT_DISTANCE shows Weight + Distance columns
- [ ] WEIGHT_REPS_DURATION shows Weight + Reps + Duration columns
- [ ] Header labels adapt to match

### Subtask T015 – Implement Warmup and Completed Row Styling

- **Purpose**: Visual differentiation for warmup sets (dimmed) and completed sets (green tint).
- **File**: `SetRowView.swift` (modify existing)

**Steps**:
1. **Warmup rows** (when `set.setType == .warmup`):
   - Apply `.opacity(0.5)` to the entire row (or 0.45 — spec says 0.45-0.5)
   - SetNumberBadge already handles "W" badge for warmup
   - The opacity dims everything — inputs, badge, checkbox

2. **Completed rows** (when `set.completed == true`):
   - Apply `Color.successSoft` (green at 6% opacity) as background: `.background(Color.successSoft)`
   - SetNumberBadge already handles green checkmark for completed
   - Input fields already handle completed styling (green border)
   - CompletionCheckbox already handles checked state

3. **Both warmup AND completed**: Apply both modifiers (warmup opacity + completed green bg).

4. Ensure warmup opacity does NOT affect the tap target interactivity — only visual dimming.

**Validation**:
- [ ] Warmup rows are visually dimmed (0.5 opacity)
- [ ] Completed rows have green tint background
- [ ] Warmup + completed rows show both effects
- [ ] Tap targets still work on dimmed rows

### Subtask T016 – Add [+ Add Set] and [+ Add Warmup] Buttons

- **Purpose**: Buttons below the set table for adding new rows.
- **File**: `SetTableView.swift` (add below set rows)
- **Parallel?**: Yes — independent of row/table internals.

**Steps**:
1. Add two buttons below the set rows in SetTableView:
   ```swift
   HStack(spacing: 12) {
       Button("+ Add Set") {
           Task {
               await viewModel.addSet(for: exercise.id)
           }
       }
       Button("+ Add Warmup") {
           Task {
               await viewModel.addWarmupSet(for: exercise.id)
           }
       }
   }
   .padding(.vertical, 12)
   ```

2. Style: `textSecondary` color, 14pt font, minimum 44pt tap height.

3. Buttons should be centered or left-aligned below the table.

**Validation**:
- [ ] Both buttons visible below set table
- [ ] Tapping "Add Set" adds a working set row
- [ ] Tapping "Add Warmup" adds a warmup set row
- [ ] Tap targets >= 44pt

### Subtask T017 – Add Long-Press Context Menu on Set Rows

- **Purpose**: Long-press on a set row shows "Edit Set Type" and "Delete Set" options per FR-012.
- **File**: `SetRowView.swift` (add `.contextMenu` modifier)

**Steps**:
1. Add `.contextMenu` modifier to the row container:
   ```swift
   .contextMenu {
       // Edit Set Type submenu
       Menu("Edit Set Type") {
           ForEach(SetType.allCases, id: \.self) { type in
               Button(type.displayName) {
                   Task {
                       await viewModel.changeSetType(set, to: type)
                   }
               }
           }
       }

       Divider()

       // Delete Set (destructive)
       Button("Delete Set", role: .destructive) {
           Task {
               await viewModel.deleteSet(set)
           }
       }
   }
   ```

2. `SetType` may not have a `displayName` property — add a computed property or use `rawValue`. Check the `SetType` enum in `Reppo/Data/Enums/SetType.swift`.

3. The current set type should be indicated (checkmark or disabled) in the submenu.

**Validation**:
- [ ] Long-press shows context menu
- [ ] "Edit Set Type" submenu lists all set types
- [ ] "Delete Set" is styled as destructive (red)
- [ ] Actions call correct ViewModel methods
- [ ] Current set type is visually indicated

## Risks & Mitigations

- **Input state management**: Each row needs independent text bindings for weight/reps/duration. Consider a `@State` dictionary on SetTableView keyed by set.id, or use a wrapper view that owns the `@State` for each row.
- **String ↔ Double conversion**: TextFields work with Strings but model stores Doubles/Ints. Create a helper formatter or use `.onChange` to convert. Handle empty strings gracefully (nil weight, not zero).
- **Column width distribution**: When trackingType has 3 input columns (WEIGHT_REPS_DURATION), the space is tight. Test that all 3 fields are usable.

## Definition of Done Checklist

- [ ] SetRowView and SetTableView created and rendering
- [ ] Column adaptation works for all 5 trackingTypes
- [ ] Warmup rows at 0.5 opacity, completed rows with green tint
- [ ] Add Set / Add Warmup buttons functional
- [ ] Long-press context menu works on set rows
- [ ] Row height is 52pt, dividers render correctly
- [ ] Project builds with zero errors

## Review Guidance

- Verify column widths match design-system (42pt, 1fr, 1fr, 44pt, 40pt)
- Test all 5 trackingTypes to verify column adaptation
- Verify warmup and completed visual states
- Check that context menu actions are wired correctly
- Verify no business logic in Views (all actions delegate to ViewModel)

## Activity Log

- 2026-02-24T14:26:08Z – system – lane=planned – Prompt created.
- 2026-02-24T19:12:30Z – claude – shell_pid=18036 – lane=doing – Started implementation via workflow command
- 2026-02-24T19:16:00Z – claude – shell_pid=18036 – lane=for_review – Ready for review: SetRowView (T012/T014/T015/T017) + SetTableView (T013/T016) — 728 lines. Column adaptation for all 5 trackingTypes, warmup/completed styling, long-press context menu, add set/warmup buttons, per-row @State text bindings. Build succeeds zero errors.
- 2026-02-24T19:16:39Z – claude – shell_pid=18740 – lane=doing – Started review via workflow command
- 2026-02-24T19:17:50Z – claude – shell_pid=18740 – lane=done – Review passed: SetRowView + SetTableView — correct column layout (42/flex/44/40pt), all 5 trackingTypes adapted, warmup opacity + completed green tint, context menu with set type submenu + delete, add buttons with 44pt targets, SetRowWrapper manages per-row @State bindings. Pure presentational Views, no layer violations. Build succeeds.
