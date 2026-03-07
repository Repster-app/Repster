---
work_package_id: "WP04"
subtasks:
  - "T018"
  - "T019"
  - "T020"
  - "T021"
title: "ExerciseTabStripView — Tab Navigation"
phase: "Phase 1 - Core UI"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "19533"
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

# Work Package Prompt: WP04 – ExerciseTabStripView — Tab Navigation

## Implementation Command

Depends on WP01 and WP02:
```bash
spec-kitty implement WP04 --base WP02
```

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Objectives & Success Criteria

- Horizontal scrollable tab strip showing exercise names
- Active tab: blue bg + white text + 8pt radius
- Inactive tabs: bgCard bg + textTertiary text + 8pt radius
- Tapping a tab switches `selectedExerciseIndex` on the ViewModel
- Long-press shows "Delete Exercise" context menu with confirmation
- Drag gesture allows reordering tabs
- Auto-scrolls to keep active tab visible
- Covers spec User Story 3 and FR-005

## Context & Constraints

**Feature**: 006-active-workout-screen — User Story 3 (Exercise Tab Strip)
**Design System**: Active tab = `blue` bg + white text, inactive = `bgCard` + `textTertiary`, 8pt radius
**Plan**: `kitty-specs/006-active-workout-screen/plan.md` — Tab strip section
**Research**: `kitty-specs/006-active-workout-screen/research.md` — Topic 3 (drag reorder decision)
**Constitution**: No third-party UI libs, 44pt tap targets, NavigationStack

## Subtasks & Detailed Guidance

### Subtask T018 – Create ExerciseTabStripView

- **Purpose**: The horizontal scrollable container for exercise tabs.
- **File**: `Reppo/Features/Workout/Views/ExerciseTabStripView.swift` (new file)

**Steps**:
1. Create `ExerciseTabStripView` with parameter: `viewModel: ActiveWorkoutViewModel`
2. Layout:
   ```swift
   ScrollViewReader { proxy in
       ScrollView(.horizontal, showsIndicators: false) {
           HStack(spacing: 8) {
               ForEach(Array(viewModel.exercises.enumerated()), id: \.element.id) { index, exercise in
                   ExerciseTab(
                       name: exercise.name,
                       isActive: index == viewModel.selectedExerciseIndex
                   )
                   .id(exercise.id)
                   .onTapGesture {
                       viewModel.selectedExerciseIndex = index
                   }
               }
           }
           .padding(.horizontal, 20)
           .padding(.vertical, 8)
       }
       .onChange(of: viewModel.selectedExerciseIndex) { _, newIndex in
           // Auto-scroll to active tab
           if newIndex < viewModel.exercises.count {
               withAnimation {
                   proxy.scrollTo(viewModel.exercises[newIndex].id, anchor: .center)
               }
           }
       }
   }
   ```

3. Create a private `ExerciseTab` subview for individual tab rendering (or inline it).

4. If there's only 1 exercise, still show the tab strip (single tab) — consistent UI.

5. If there are 0 exercises, show empty state or hide the strip.

**Validation**:
- [ ] Tab strip scrolls horizontally
- [ ] Each exercise has a tab
- [ ] Tapping tab updates selectedExerciseIndex
- [ ] No scroll indicators visible

### Subtask T019 – Implement Tab Styling

- **Purpose**: Active and inactive tab visual states per design system.
- **File**: `ExerciseTabStripView.swift` (style the tab)

**Steps**:
1. Individual tab styling:
   ```swift
   struct ExerciseTab: View {
       let name: String
       let isActive: Bool

       var body: some View {
           Text(name)
               .font(.system(size: 14, weight: .medium))
               .lineLimit(1)
               .padding(.horizontal, 16)
               .padding(.vertical, 8)
               .background(isActive ? Color.appBlue : Color.bgCard)
               .foregroundColor(isActive ? .white : Color.textTertiary)
               .cornerRadius(8)
       }
   }
   ```

2. Minimum tab width: ensure tappable (pad short names). Minimum height should meet 44pt tap target (8pt padding top + bottom + text height ≈ 36-40pt — may need to adjust to 10pt padding).

3. Use `contentShape(Rectangle())` if needed to ensure full tap area.

**Validation**:
- [ ] Active tab: blue background, white text, 8pt radius
- [ ] Inactive tab: bgCard background, textTertiary text, 8pt radius
- [ ] Tab text truncated with lineLimit(1) for long names
- [ ] Tap target >= 44pt height

### Subtask T020 – Add Long-Press Context Menu

- **Purpose**: Long-pressing a tab shows "Delete Exercise" option with a confirmation dialog.
- **File**: `ExerciseTabStripView.swift`
- **Parallel?**: Yes — independent of drag gesture.

**Steps**:
1. Add `.contextMenu` to each tab:
   ```swift
   .contextMenu {
       Button("Delete Exercise", role: .destructive) {
           exerciseToDelete = index  // trigger confirmation
       }
   }
   ```

2. Add a confirmation alert:
   ```swift
   .alert("Delete Exercise?", isPresented: $showDeleteConfirmation) {
       Button("Cancel", role: .cancel) { }
       Button("Delete", role: .destructive) {
           Task {
               await viewModel.removeExercise(at: exerciseToDeleteIndex)
           }
       }
   } message: {
       Text("This will remove the exercise and all its sets from this workout.")
   }
   ```

3. Track `@State private var showDeleteConfirmation = false` and `@State private var exerciseToDeleteIndex = 0`.

**Validation**:
- [ ] Long-press shows context menu with "Delete Exercise"
- [ ] Confirmation alert appears before deletion
- [ ] Cancel dismisses without action
- [ ] Delete calls viewModel.removeExercise()

### Subtask T021 – Implement Drag-to-Reorder Gesture

- **Purpose**: Allow users to reorder exercises by dragging tabs. Spec says "drag a tab to reorder."
- **File**: `ExerciseTabStripView.swift`
- **Parallel?**: Yes — independent of context menu.

**Steps**:
1. This is the most complex subtask. Two approaches:

   **Approach A — LongPressGesture + DragGesture sequence** (recommended):
   ```swift
   .gesture(
       LongPressGesture(minimumDuration: 0.3)
           .sequenced(before: DragGesture())
           .onChanged { value in
               // Track drag position, calculate target index
           }
           .onEnded { value in
               // Finalize reorder
               viewModel.reorderExercises(...)
           }
   )
   ```

   **Approach B — Simple fallback** (if drag gesture conflicts with ScrollView):
   Add "Move Left" / "Move Right" buttons to the context menu instead of drag.

2. During drag:
   - Show visual feedback (scale, opacity, or shadow on the dragged tab)
   - Calculate target position based on x-offset
   - Show insertion indicator

3. On drop:
   - Call `viewModel.reorderExercises(from:to:)`
   - Animate the reorder

4. **Important**: The drag gesture MUST NOT conflict with the ScrollView's horizontal scroll. Using a `LongPressGesture` as a gate (hold to activate drag) prevents accidental drags during scrolling.

**Validation**:
- [ ] Long-press then drag moves a tab
- [ ] Visual feedback during drag (opacity/scale change)
- [ ] Tab lands in new position on release
- [ ] ScrollView still scrolls normally (no gesture conflict)
- [ ] If drag proves too complex, fallback to context menu reorder buttons

## Risks & Mitigations

- **Drag gesture vs ScrollView conflict**: This is the primary risk. The `LongPressGesture` gate mitigates it — user must long-press before drag activates. If conflicts persist, fall back to Approach B (context menu Move Left/Right).
- **Auto-scroll during drag**: When dragging a tab to the edge of the ScrollView, it should ideally scroll. This is complex — skip for v1 if needed (user can drag to visible positions).
- **Single exercise**: If only 1 exercise, drag and delete should be disabled/hidden.

## Definition of Done Checklist

- [ ] Tab strip renders with correct styling
- [ ] Tab selection works (tap to switch)
- [ ] Auto-scroll keeps active tab visible
- [ ] Long-press delete with confirmation
- [ ] Drag reorder functional (or fallback implemented)
- [ ] Project builds with zero errors

## Review Guidance

- Verify active/inactive tab colors match design system
- Test with 1, 3, and 10+ exercises
- Verify drag doesn't break scroll
- Verify delete confirmation is required (not immediate)
- Check 44pt minimum tap targets

## Activity Log

- 2026-02-24T14:26:08Z – system – lane=planned – Prompt created.
- 2026-02-24T19:19:23Z – claude – shell_pid=19101 – lane=doing – Started implementation via workflow command
- 2026-02-24T19:20:36Z – claude – shell_pid=19101 – lane=for_review – Ready for review: ExerciseTabStripView (208 lines) — horizontal scrollable tab strip with accent/bgCard styling, 44pt tap targets, auto-scroll via ScrollViewReader, context menu with Move Left/Right reorder + Delete with confirmation alert. Build succeeds zero errors.
- 2026-02-24T19:21:42Z – claude – shell_pid=19533 – lane=doing – Started review via workflow command
- 2026-02-24T19:22:15Z – claude – shell_pid=19533 – lane=done – Review passed: ExerciseTabStripView with correct accent/bgCard styling, 44pt min tap targets, auto-scroll via ScrollViewReader, context menu reorder (Move Left/Right) + delete with confirmation alert. Single exercise protection, no layer violations, build succeeds.
