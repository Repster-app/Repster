---
work_package_id: "WP09"
subtasks:
  - "T129"
  - "T130"
  - "T131"
  - "T132"
  - "T133"
  - "T134"
title: "Exercise Selection Modal + Preset Persistence"
phase: "Phase 1 - Exercises"
lane: "planned"
dependencies: ["WP05", "WP08"]
agent: ""
assignee: ""
shell_pid: ""
reviewed_by: ""
review_status: ""
history:
  - timestamp: "2026-03-04T14:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated manually (spec-kitty format)"
---

# Work Package Prompt: WP09 – Exercise Selection Modal + Preset Persistence

## Objectives & Success Criteria

- Create `ChartPreset` model and `ChartPresetStore` for UserDefaults-based preset persistence.
- Create `ExerciseSelectionSheet` modal with Current/Presets tabs, add/remove/reorder exercises.
- Wire "Add Exercise" to existing exercise picker.
- Implement preset CRUD (save, load, delete).
- Wire modal into ExercisesTabView so exercise selection triggers chart data reload.
- **Success**: Tapping exercise button opens modal. Add/remove/reorder exercises works. Save/load presets works. Apply closes modal and updates chart. Presets survive app restart.

## Context & Constraints

- **Spec**: FR-011, FR-012, FR-018 from `kitty-specs/016-charts-tab-v2/spec.md`.
- **Existing exercise picker**: `ExerciseListView` has `.addToWorkout` mode. Consider reusing it via nested sheet.
- **Design**: See exercise selection modal in `prototype-charts-tab.html` (click the exercise selection button in the Exercises tab).
- **Persistence**: UserDefaults with JSON encoding. Key: `"chartExercisePresets"`. No SwiftData model needed.
- **Max exercises**: 10. Enforce in UI (disable Add when at 10).
- **Drag reorder**: Use SwiftUI `ForEach` with `.onMove` modifier.

**Implementation command**: `spec-kitty implement WP09 --base WP08`

## Subtasks & Detailed Guidance

### Subtask T129 – Create ChartPreset.swift

- **File**: `Reppo/Features/Charts/Models/ChartPreset.swift` (new)
- **Parallel?**: Yes

```swift
import Foundation

struct ChartPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var exerciseIds: [UUID]

    init(id: UUID = UUID(), name: String, exerciseIds: [UUID]) {
        self.id = id
        self.name = name
        self.exerciseIds = exerciseIds
    }
}

final class ChartPresetStore {
    private let key = "chartExercisePresets"

    func loadPresets() -> [ChartPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([ChartPreset].self, from: data) else {
            return []
        }
        return presets
    }

    func savePreset(_ preset: ChartPreset) {
        var presets = loadPresets()
        presets.append(preset)
        persist(presets)
    }

    func deletePreset(_ id: UUID) {
        var presets = loadPresets()
        presets.removeAll { $0.id == id }
        persist(presets)
    }

    func updatePreset(_ preset: ChartPreset) {
        var presets = loadPresets()
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
            persist(presets)
        }
    }

    private func persist(_ presets: [ChartPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
```

**Validation**: Presets save and load correctly. Persist across UserDefaults reads. Delete removes the correct preset.

---

### Subtask T130 – Create ExerciseSelectionSheet

- **File**: `Reppo/Features/Charts/Views/Components/ExerciseSelectionSheet.swift` (new)

Structure (matches prototype):
```
Sheet
├── Handle bar
├── Title: "Select Exercises"
├── Subtitle: "Choose up to 10 exercises"
├── Current / Presets toggle tabs
├── Current tab content:
│   ├── ForEach selected exercises:
│   │   ├── Drag handle (≡) via .onMove
│   │   ├── Exercise name
│   │   ├── Category badge (bgSubtle, textDim)
│   │   └── Remove button (−) red circle
│   └── "Add Exercise" row (+ icon, accent color)
├── Presets tab content:
│   └── ForEach presets:
│       ├── Preset name
│       ├── Exercise summary (truncated)
│       └── "Apply" button (accent)
└── Footer:
    ├── "Apply to Graph" (primary accent button)
    └── Row: "Save as Preset" | "Clear Selection" (secondary buttons)
```

```swift
import SwiftUI

struct ExerciseSelectionSheet: View {
    @Binding var selectedExercises: [(id: UUID, name: String, category: String)]
    @Binding var isPresented: Bool
    let onApply: () -> Void
    let exerciseService: any ExerciseServiceProtocol

    @State private var activeTab: SelectionTab = .current
    @State private var presets: [ChartPreset] = []
    @State private var showAddExercise = false
    @State private var showSavePresetAlert = false
    @State private var presetName = ""

    private let presetStore = ChartPresetStore()

    enum SelectionTab { case current, presets }

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.bgSubtle)
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 16)

            // Title
            Text("Select Exercises")
                .font(.system(size: 20, weight: .bold))
            Text("Choose up to 10 exercises")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 16)

            // Current / Presets tabs
            HStack(spacing: 4) {
                tabButton("Current", tab: .current)
                tabButton("Presets", tab: .presets)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Content
            ScrollView {
                if activeTab == .current {
                    currentTabContent
                } else {
                    presetsTabContent
                }
            }

            // Footer
            footerButtons
        }
        .background(Color.bgCard)
        .onAppear { presets = presetStore.loadPresets() }
    }

    // ... implement tab button, current tab, presets tab, footer
}
```

Key behaviors:
- `.onMove` for drag reorder on the exercise list
- Remove button animates out the row
- "Add Exercise" opens nested sheet or exercise picker

---

### Subtask T131 – Wire "Add Exercise" Action

Two options:
- **Option A (recommended)**: Present `ExerciseListView(mode: .addToWorkout)` in a nested `.sheet`. On selection, add exercise to `selectedExercises` and dismiss.
- **Option B**: Simple inline search within the modal.

Go with Option A — reuses existing code. Wire the selection callback to append to `selectedExercises`.

Check: prevent duplicates (don't add an exercise already in the list).

---

### Subtask T132 – Implement Preset CRUD

- **Save**: "Save as Preset" shows an alert with a text field for the name. On confirm, save via `ChartPresetStore.savePreset()`.
- **Load**: Tapping "Apply" on a preset populates `selectedExercises` with that preset's exercises (look up names from exercise service, filter out deleted exercises).
- **Delete**: Swipe-to-delete on preset rows in the Presets tab.

```swift
// Save
.alert("Save Preset", isPresented: $showSavePresetAlert) {
    TextField("Preset name", text: $presetName)
    Button("Save") {
        let preset = ChartPreset(name: presetName, exerciseIds: selectedExercises.map { $0.id })
        presetStore.savePreset(preset)
        presets = presetStore.loadPresets()
        presetName = ""
    }
    Button("Cancel", role: .cancel) { }
}
```

---

### Subtask T133 – Wire Modal into ExercisesTabView

1. ExercisesTabView presents `ExerciseSelectionSheet` as `.sheet(isPresented: $viewModel.showExerciseSelector)`.
2. On "Apply to Graph": close sheet, call `viewModel.updateExercises(newSelection)` which triggers data reload.
3. Exercise selection trigger button in ExercisesTabView shows selected names (e.g., "Bench Press, Squat +1 more") in accent color.

---

### Subtask T134 – Edge Cases

- **Max 10**: Disable "Add Exercise" row when `selectedExercises.count >= 10`. Show subtle text "(10/10)".
- **Duplicate prevention**: Check exerciseId before adding.
- **Preset with deleted exercise**: When loading preset, look up each exerciseId. Filter out ones that return nil from exerciseService. If preset becomes empty, show brief alert.
- **Empty presets tab**: Show "No saved presets" message.
- **Reorder**: `.onMove` modifies the array order. Colors on the chart follow array order.

---

## Definition of Done Checklist

- [ ] ChartPreset struct and ChartPresetStore created with CRUD
- [ ] ExerciseSelectionSheet renders with Current/Presets tabs
- [ ] Add exercise works (via exercise picker, no duplicates)
- [ ] Remove exercise works with animation
- [ ] Drag reorder works via .onMove
- [ ] Save as Preset works with name alert
- [ ] Load preset populates exercises (filters deleted)
- [ ] Delete preset works (swipe-to-delete)
- [ ] Clear Selection removes all exercises
- [ ] Apply to Graph closes modal and triggers chart reload
- [ ] Max 10 exercises enforced
- [ ] Presets persist across app restart
- [ ] Wired into ExercisesTabView
- [ ] App compiles without errors

## Review Guidance

- Verify UserDefaults persistence with JSON encoding/decoding.
- Verify exercise lookup when loading presets (handles deleted exercises).
- Verify max 10 limit is enforced in UI.
- Verify .onMove works for reorder.
- Verify Apply callback triggers ExercisesTabViewModel.updateExercises().
- Verify no duplicate exercises can be added.
- Verify sheet styling matches design system (bgCard background, accent buttons).

## Activity Log
