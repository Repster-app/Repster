---
work_package_id: "WP03"
title: "ModelContainer, App Entry Point, and Build Verification"
lane: "done"
dependencies: ["WP02"]
subtasks: ["T023", "T024", "T025", "T026", "T027"]
agent: "claude-opus"
shell_pid: "78635"
reviewed_by: "Magnus Espensen"
review_status: "approved"
history:
  - date: "2026-02-19"
    action: "created"
    by: "spec-kitty.tasks"
---

# WP03: ModelContainer, App Entry Point, and Build Verification

**Implementation command**: `spec-kitty implement WP03 --base WP02`

## Objective

Wire up the SwiftData ModelContainer with all 11 model types, create the app entry point with a placeholder dark-mode view, add unit conversion helpers and the seed exercises JSON resource, then verify the entire project builds and launches with zero errors.

## Context

- **All 9 enums** exist from WP01 in `Reppo/Data/Enums/`
- **All 11 @Model classes** exist from WP02 in `Reppo/Data/Models/`
- This WP wires everything together and confirms the project is buildable
- No real UI in this feature - just a placeholder ContentView
- `seed_exercises.json` is placed in Resources/ but NOT parsed until feature 012
- UnitConversion helpers are utility functions used by future features

## Reference Documents

- `kitty-specs/001-xcode-project-swiftdata-models/plan.md` - ModelContainer config, project structure
- `kitty-specs/001-xcode-project-swiftdata-models/spec.md` - Build verification acceptance criteria
- `.kittify/memory/constitution.md` - Architecture principles
- `seed_exercises.json` (project root) - 67 exercises to copy to Resources/

---

## Subtasks

### T023: Create ModelContainerSetup.swift

**Purpose**: Central factory method that configures SwiftData's ModelContainer with all 11 model types registered. This is the single point of schema configuration.

**File**: `Reppo/Data/Persistence/ModelContainerSetup.swift`

**Implementation**:

```swift
import Foundation
import SwiftData

enum ModelContainerSetup {
    static func createContainer() throws -> ModelContainer {
        let schema = Schema([
            WorkoutSet.self,
            Workout.self,
            Exercise.self,
            ExerciseStats.self,
            PerformanceRecord.self,
            BodyweightEntry.self,
            HealthProfile.self,
            Program.self,
            ProgramExercise.self,
            PlannedWorkout.self,
            PlannedSet.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
```

**Critical rules**:
- ALL 11 model types must be registered (missing one = runtime crash when querying it)
- Use `isStoredInMemoryOnly: false` for persistent storage
- Factory pattern as static method on enum (no instances needed)
- No migration configuration in v1 (clean install only)

**Validation**:
- [ ] All 11 model types listed in Schema array
- [ ] `isStoredInMemoryOnly` is false (persistent)
- [ ] Returns ModelContainer (throwable)
- [ ] No model type missing from the list

---

### T024: Create ReppoApp.swift Entry Point

**Purpose**: The @main app entry point that initializes the ModelContainer and presents a placeholder view.

**File**: `Reppo/App/ReppoApp.swift`

**⚠️ NOTE**: This file already exists from WP01 as a minimal placeholder (`import SwiftUI` only, no SwiftData). **OVERWRITE** it completely — do not append. The existing file has no ModelContainer wiring and will conflict with the new implementation.

**Implementation**:

```swift
import SwiftUI
import SwiftData

@main
struct ReppoApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainerSetup.createContainer()
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
```

**Also create placeholder ContentView**:

**File**: `Reppo/App/ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            Text("Reppo")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
```

**Critical rules**:
- `fatalError` on ModelContainer failure is acceptable for v1 (no recovery possible)
- `.modelContainer()` modifier injects the container into the SwiftUI environment
- ContentView uses dark background (`.preferredColorScheme(.dark)`) per dark-mode-only design
- System font (not DM Sans) per AGENT_RULES Section 7

**Validation**:
- [ ] @main attribute on ReppoApp
- [ ] ModelContainer created via ModelContainerSetup.createContainer()
- [ ] .modelContainer() modifier on WindowGroup
- [ ] ContentView has dark background
- [ ] No third-party UI imports

---

### T025: Create UnitConversion.swift Extension

**Purpose**: Provide reusable unit conversion helpers used across the app. All storage is metric; these convert for display when user prefers imperial.

**File**: `Reppo/Core/Extensions/UnitConversion.swift`

**Implementation**:

```swift
import Foundation

enum UnitConversion {
    // MARK: - Weight

    /// Convert kg to lbs for display
    static func kgToLbs(_ kg: Double) -> Double {
        kg * 2.20462
    }

    /// Convert lbs to kg for storage
    static func lbsToKg(_ lbs: Double) -> Double {
        lbs / 2.20462
    }

    /// Integer grams for float-safe PR comparison
    /// CRITICAL: This is the canonical comparison function per specdoc
    static func toGrams(_ kg: Double) -> Int {
        Int(round(kg * 1000))
    }

    // MARK: - Distance

    /// Convert meters to feet for display
    static func metersToFeet(_ meters: Double) -> Double {
        meters * 3.28084
    }

    /// Convert feet to meters for storage
    static func feetToMeters(_ feet: Double) -> Double {
        feet / 3.28084
    }

    // MARK: - Duration Formatting

    /// Format seconds into "Xm Ys" display string
    static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 && remainingSeconds > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(remainingSeconds)s"
        }
    }
}
```

**Critical rules**:
- `toGrams()` MUST use `Int(round(kg * 1000))` - this is the canonical float-safe comparison per constitution "Float Comparison — Integer Grams" principle (not specdoc S7)
- All conversions are pure functions, no state
- Enum namespace (no instances)

**Validation**:
- [ ] `toGrams` uses exact formula: `Int(round(kg * 1000))`
- [ ] kg<->lbs factor is 2.20462
- [ ] meters<->feet factor is 3.28084
- [ ] Duration formatting handles edge cases (0 minutes, 0 seconds)

---

### T026: Add seed_exercises.json to Resources

**Purpose**: Copy the 67-exercise seed data file into the app bundle for use by feature 012 (SeedExerciseLibrary).

**Steps**:
1. Copy `seed_exercises.json` from project root to `Reppo/Resources/seed_exercises.json`
2. Register the file in `Reppo.xcodeproj/project.pbxproj` using the same pattern as `Assets.xcassets`:
   - Add a **PBXBuildFile** entry (e.g. `A10012 /* seed_exercises.json in Resources */`) referencing a new file ref
   - Add a **PBXFileReference** entry (e.g. `B10012 /* seed_exercises.json */`) with `lastKnownFileType = text.json`
   - Add `B10012` to the `D10006 /* Resources */` PBXGroup children
   - Add `A10012` to the `E30001 /* Resources */` PBXResourcesBuildPhase files list
3. Do NOT modify the JSON content - copy exactly as-is

**Source file**: `/Users/magnusespensen/Desktop/NewWorkoutProject/seed_exercises.json` (67 exercises, ~23KB)
**Destination**: `Reppo/Resources/seed_exercises.json`

**Critical rules**:
- File must be in the app bundle at runtime (added to target resources)
- Do NOT parse or validate the JSON in this feature (that's feature 012)
- Do NOT modify any exercise data

**Validation**:
- [ ] File exists at `Reppo/Resources/seed_exercises.json`
- [ ] File content is identical to source
- [ ] File is included in app bundle (target membership)

---

### T027: Full Build Verification

**Purpose**: Confirm the entire project compiles and launches without errors.

**Steps**:
1. Build the project from command line:
   ```bash
   xcodebuild -project Reppo.xcodeproj -scheme Reppo -destination 'platform=iOS Simulator,id=D6B7693F-80B4-4420-9E41-D5747682E961' build
   ```
   (Use the same iPhone 16 simulator ID used in WP01/WP02. Avoid `name=` form as it is ambiguous across OS versions.)
2. Verify zero errors
3. Verify zero warnings (or document any unavoidable framework warnings)
4. If possible, launch in simulator and confirm the dark "Reppo" placeholder screen appears
5. Check that all 11 models are registered by verifying no SwiftData errors in console output

**Validation**:
- [ ] Build succeeds with zero errors
- [ ] No warnings from project code (framework warnings acceptable)
- [ ] App launches in simulator
- [ ] Dark placeholder screen with "Reppo" text visible
- [ ] No SwiftData schema errors in console

---

## Definition of Done

- [ ] `ModelContainerSetup.swift` exists and registers all 11 model types
- [ ] `ReppoApp.swift` exists with @main and ModelContainer injection
- [ ] `ContentView.swift` shows dark placeholder with "Reppo" text
- [ ] `UnitConversion.swift` exists with kg<->lbs, m<->ft, toGrams(), formatDuration()
- [ ] `seed_exercises.json` copied to Resources/ and included in bundle
- [ ] Project builds with zero errors
- [ ] App launches in simulator showing placeholder screen
- [ ] No SwiftData runtime errors in console

## Risks

| Risk | Mitigation |
|------|-----------|
| ModelContainer crashes at runtime if model missing | Count all 11 types in Schema array before building |
| seed_exercises.json not in bundle | Verify target membership in Xcode project settings |
| xcodebuild command path issues | Use absolute path to .xcodeproj, specify exact simulator |
| SwiftData schema migration errors on re-run | Delete app from simulator before re-testing (clean install only in v1) |

## Reviewer Guidance

1. **Count models in Schema**: Must be exactly 11 (WorkoutSet, Workout, Exercise, ExerciseStats, PerformanceRecord, BodyweightEntry, HealthProfile, Program, ProgramExercise, PlannedWorkout, PlannedSet)
2. **Verify toGrams formula**: `Int(round(kg * 1000))` - not truncation, not floor, must be round
3. **Check ContentView**: Dark background, system font, no third-party UI
4. **Verify seed JSON**: Byte-for-byte copy, no modifications
5. **Build output**: Zero errors mandatory, zero warnings preferred

## Activity Log

- 2026-02-22T09:53:39Z – claude-opus – shell_pid=78635 – lane=doing – Started implementation via workflow command
- 2026-02-22T11:09:22Z – claude-opus – shell_pid=78635 – lane=done – Merged to master with WP01 and WP02
