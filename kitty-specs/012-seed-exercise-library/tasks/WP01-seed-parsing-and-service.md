---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
title: "Seed Data Parsing + SeedService"
phase: "Phase 1 - Core Implementation"
lane: "done"
assignee: "claude-opus"
agent: "claude-opus-reviewer"
shell_pid: "26607"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: []
history:
  - timestamp: "2026-02-22T11:32:10Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-03-01T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Reset to planned — previous done/approved state was from cross-feature contamination (no actual code delivered)"
  - timestamp: "2026-03-01T13:42:31Z"
    lane: "doing"
    agent: "claude-opus"
    shell_pid: "22552"
    action: "Started implementation via workflow command"
  - timestamp: "2026-03-01T13:47:37Z"
    lane: "for_review"
    agent: "claude-opus"
    shell_pid: "22552"
    action: "Ready for review: SeedExerciseDTO, SeedDataLoader, SeedService, DTO-to-Exercise mapping. All 4 files created, registered in pbxproj. Build succeeds zero errors."
  - timestamp: "2026-03-01T15:55:46Z"
    lane: "doing"
    agent: "claude-opus-reviewer"
    shell_pid: "26607"
    action: "Started review via workflow command"
  - timestamp: "2026-03-01T15:56:12Z"
    lane: "done"
    agent: "claude-opus-reviewer"
    shell_pid: "26607"
    action: "Review passed: All 4 files verified. Enum mappings complete. Build succeeds zero errors."
---

# Work Package Prompt: WP01 – Seed Data Parsing + SeedService

## Implementation Command

```bash
spec-kitty implement WP01
```

No dependencies — this is the starting work package.

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review. If you see feedback here, treat each item as a must-do before completion.]*

---

## Objectives & Success Criteria

Build the complete seeding pipeline: parse `seed_exercises.json` from the app bundle into `Exercise` model objects and insert them into SwiftData on first launch.

**Success criteria**:
- `SeedExerciseDTO` correctly decodes all 67 exercises from JSON
- All enum values map correctly (WEIGHT_REPS → .weightReps, machine_plate → .machinePlate, etc.)
- `SeedService.seedIfNeeded(modelContext:)` inserts 67 exercises when table is empty
- `SeedService.seedIfNeeded(modelContext:)` does nothing when table has exercises
- Invalid JSON entries are skipped with `print()` warning (FR-008)
- All 67 exercises complete in under 1 second (FR-007)

## Context & Constraints

**Architecture**: This feature creates files in `Core/Seeding/` (DTOs + loader) and `Core/Services/` (SeedService). The SeedService touches `ModelContext` directly — this is acceptable because seeding is a one-time initialization concern, not ongoing data access that would normally go through a Repository.

**Constitution compliance**:
- Services contain business logic ✓ (seeding decision logic)
- No UI involvement ✓ (seeding is headless)
- No startup rebuild ✓ (seeding only runs once, checks count first)
- UUIDs for all IDs ✓ (Exercise.init() generates UUID automatically)

**Key reference files**:
- Exercise model: `Reppo/Data/Models/Exercise.swift`
- Enums: `Reppo/Data/Enums/EquipmentType.swift`, `TrackingType.swift`, `MovementPattern.swift`
- Seed data: `Reppo/Resources/seed_exercises.json`
- Constitution: `.kittify/memory/constitution.md`
- Spec: `kitty-specs/012-seed-exercise-library/spec.md`

**Existing Exercise model fields** (all must be populated by seeding):
```swift
@Model final class Exercise {
    var id: UUID                        // Auto-generated
    var name: String                    // From JSON
    var equipmentType: EquipmentType    // From JSON (needs mapping)
    var trackingType: TrackingType      // From JSON (needs mapping)
    var primaryMuscle: String?          // From JSON (plain string)
    var secondaryMuscles: [String]      // From JSON (array of strings)
    var movementPattern: MovementPattern? // From JSON (needs mapping)
    var unilateral: Bool                // From JSON
    var bilateralLoadFactor: Double?    // NOT in JSON — defaults to nil
    var bodyweightFactor: Double        // From JSON
    var weightIncrement: Double?        // From JSON
    var defaultRestTime: Int?           // From JSON
    var createdAt: Date                 // Auto-generated
    var updatedAt: Date                 // Auto-generated
}
```

**Enum mapping challenge**: JSON values don't match Swift enum rawValues:

| Field | JSON Value | Swift Enum Case | Swift rawValue |
|-------|-----------|-----------------|----------------|
| trackingType | "WEIGHT_REPS" | `.weightReps` | "weightReps" |
| trackingType | "DURATION" | `.duration` | "duration" |
| trackingType | "WEIGHT_DISTANCE" | `.weightDistance` | "weightDistance" |
| equipmentType | "machine_plate" | `.machinePlate` | "machinePlate" |
| equipmentType | "machine_pin" | `.machinePin` | "machinePin" |
| equipmentType | "barbell" | `.barbell` | "barbell" |
| equipmentType | (all others) | lowercase match | lowercase match |
| movementPattern | "squat" | `.squat` | "squat" |
| movementPattern | (all others) | lowercase match | lowercase match |

**Key insight**: `equipmentType` and `movementPattern` JSON values are lowercase and mostly match rawValues directly — except `machine_plate` → `machinePlate` and `machine_pin` → `machinePin`. `trackingType` is ALL_CAPS in JSON but camelCase in Swift.

---

## Subtasks & Detailed Guidance

### Subtask T001 – Create SeedExerciseDTO

**Purpose**: Define a plain `Codable` struct that matches the JSON shape exactly. This decouples JSON parsing from SwiftData model creation.

**Steps**:

1. Create file `Reppo/Core/Seeding/SeedExerciseDTO.swift`
2. Define the struct:

```swift
import Foundation

/// DTO for deserializing exercises from seed_exercises.json.
/// Uses custom CodingKeys to handle JSON naming conventions.
struct SeedExerciseDTO: Codable {
    let name: String
    let equipmentType: String      // Raw string from JSON
    let trackingType: String       // Raw string from JSON (UPPER_SNAKE_CASE)
    let primaryMuscle: String?
    let secondaryMuscles: [String]
    let movementPattern: String?   // Raw string from JSON
    let unilateral: Bool
    let bodyweightFactor: Double
    let weightIncrement: Double?
    let defaultRestTime: Int?
}

/// Top-level container for the JSON file
struct SeedExerciseFile: Codable {
    let exercises: [SeedExerciseDTO]
}
```

3. **Design decision**: Keep all enum fields as `String` in the DTO. Mapping to Swift enums happens in T004 (the mapping extension). This keeps the DTO simple and testable.

4. Note: `secondaryMuscles` defaults to `[]` in the Exercise model, but in the DTO it's a required field (all 67 exercises have it in JSON, even if empty array).

**Files**: `Reppo/Core/Seeding/SeedExerciseDTO.swift` (new, ~25 lines)
**Parallel?**: Yes — independent of T002.

---

### Subtask T002 – Create SeedDataLoader

**Purpose**: Load and parse `seed_exercises.json` from the app bundle. Separates file I/O from business logic.

**Steps**:

1. Create file `Reppo/Core/Seeding/SeedDataLoader.swift`
2. Implement:

```swift
import Foundation

enum SeedDataLoader {
    enum SeedError: Error {
        case fileNotFound
        case decodingFailed(Error)
    }

    static func loadExercises() throws -> [SeedExerciseDTO] {
        guard let url = Bundle.main.url(forResource: "seed_exercises", withExtension: "json") else {
            throw SeedError.fileNotFound
        }

        let data = try Data(contentsOf: url)

        do {
            let file = try JSONDecoder().decode(SeedExerciseFile.self, from: data)
            return file.exercises
        } catch {
            throw SeedError.decodingFailed(error)
        }
    }
}
```

3. Uses `Bundle.main` to find the resource — this works because `seed_exercises.json` is already in `Reppo/Resources/`.
4. Returns `[SeedExerciseDTO]`, not `[Exercise]` — the mapping happens in the service layer.

**Files**: `Reppo/Core/Seeding/SeedDataLoader.swift` (new, ~25 lines)
**Parallel?**: Yes — independent of T001.

---

### Subtask T003 – Create SeedService

**Purpose**: Orchestrate the seeding pipeline: check if Exercise table is empty → load DTOs → map to Exercise models → insert into SwiftData.

**Steps**:

1. Create file `Reppo/Core/Services/SeedService.swift`
2. Implement:

```swift
import Foundation
import SwiftData

enum SeedService {
    /// Seeds the exercise library if the database is empty.
    /// Call once during app initialization.
    static func seedIfNeeded(modelContext: ModelContext) {
        // FR-003: Only seed when Exercise table is empty
        let descriptor = FetchDescriptor<Exercise>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0

        guard count == 0 else { return }

        // Load DTOs from bundle
        let dtos: [SeedExerciseDTO]
        do {
            dtos = try SeedDataLoader.loadExercises()
        } catch {
            print("[SeedService] Failed to load seed data: \(error)")
            return
        }

        // Map and insert each exercise
        var inserted = 0
        for dto in dtos {
            do {
                let exercise = try dto.toExercise()
                modelContext.insert(exercise)
                inserted += 1
            } catch {
                // FR-008: Skip invalid entries, log warning
                print("[SeedService] Skipping exercise '\(dto.name)': \(error)")
            }
        }

        // Save all at once (batch insert)
        do {
            try modelContext.save()
            print("[SeedService] Seeded \(inserted) exercises")
        } catch {
            print("[SeedService] Failed to save seed data: \(error)")
        }
    }
}
```

3. **Key design decisions**:
   - `static func` on an enum (no instances needed)
   - Takes `ModelContext` as parameter (injected from ReppoApp)
   - Uses `fetchCount` for the empty check (lightweight, no data loaded)
   - Inserts all exercises, then saves once (batch — faster than save-per-insert)
   - Per-exercise try/catch for FR-008 (graceful skip on invalid entries)
   - Uses `print()` for logging (no logging framework in v1)

4. **Threading**: This runs synchronously in `ReppoApp.init()`. For 67 exercises, this is well under 1 second. No async needed.

**Files**: `Reppo/Core/Services/SeedService.swift` (new, ~40 lines)
**Parallel?**: No — depends on T001 (DTO) and T002 (loader).

---

### Subtask T004 – Create DTO → Exercise Mapping

**Purpose**: Convert `SeedExerciseDTO` string fields to proper Swift enum values and create `Exercise` model instances.

**Steps**:

1. Add a `toExercise()` method as an extension on `SeedExerciseDTO` in the same file (`SeedExerciseDTO.swift`) or a separate file `Reppo/Core/Seeding/SeedExerciseDTO+Mapping.swift`.

2. Implement enum mapping:

```swift
import Foundation

extension SeedExerciseDTO {
    enum MappingError: Error {
        case invalidTrackingType(String)
        case invalidEquipmentType(String)
        case invalidMovementPattern(String)
    }

    func toExercise() throws -> Exercise {
        let mappedTrackingType = try Self.mapTrackingType(trackingType)
        let mappedEquipmentType = try Self.mapEquipmentType(equipmentType)
        let mappedMovementPattern = try movementPattern.map { try Self.mapMovementPattern($0) }

        return Exercise(
            name: name,
            equipmentType: mappedEquipmentType,
            trackingType: mappedTrackingType,
            primaryMuscle: primaryMuscle,
            secondaryMuscles: secondaryMuscles,
            movementPattern: mappedMovementPattern,
            unilateral: unilateral,
            bodyweightFactor: bodyweightFactor,
            weightIncrement: weightIncrement,
            defaultRestTime: defaultRestTime
        )
    }

    // MARK: - Enum Mapping

    private static func mapTrackingType(_ value: String) throws -> TrackingType {
        switch value {
        case "WEIGHT_REPS": return .weightReps
        case "DURATION": return .duration
        case "WEIGHT_DISTANCE": return .weightDistance
        case "WEIGHT_REPS_DURATION": return .weightRepsDuration
        case "CUSTOM": return .custom
        default: throw MappingError.invalidTrackingType(value)
        }
    }

    private static func mapEquipmentType(_ value: String) throws -> EquipmentType {
        switch value {
        case "barbell": return .barbell
        case "dumbbell": return .dumbbell
        case "machine_plate": return .machinePlate
        case "machine_pin": return .machinePin
        case "bodyweight": return .bodyweight
        case "sled": return .sled
        case "cable": return .cable
        case "kettlebell": return .kettlebell
        case "band": return .band
        case "other": return .other
        default: throw MappingError.invalidEquipmentType(value)
        }
    }

    private static func mapMovementPattern(_ value: String) throws -> MovementPattern {
        switch value {
        case "hinge": return .hinge
        case "squat": return .squat
        case "press": return .press
        case "pull": return .pull
        case "carry": return .carry
        case "rotation": return .rotation
        case "other": return .other
        default: throw MappingError.invalidMovementPattern(value)
        }
    }
}
```

3. **Why explicit switch statements instead of `init(rawValue:)`**: The JSON values don't match Swift enum rawValues (e.g., "WEIGHT_REPS" vs "weightReps", "machine_plate" vs "machinePlate"). Explicit mapping is safer and produces clear error messages.

4. **All cases covered**: Every enum case from the existing Swift enums is mapped, plus a `default` that throws for unknown values (FR-008 — caught by SeedService per-exercise error handling).

5. **`movementPattern` is optional**: The mapping handles `nil` by using `movementPattern.map { ... }` — if the JSON value is null, the result is nil.

**Files**: `Reppo/Core/Seeding/SeedExerciseDTO+Mapping.swift` (new, ~65 lines) OR extend `SeedExerciseDTO.swift`
**Parallel?**: No — depends on T001 (DTO struct definition).

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| JSON enum values don't match Swift rawValues | Medium | Explicit switch-based mapping covers all cases. MappingError provides clear diagnostics. |
| `Bundle.main.url` returns nil in tests/previews | Low | This code runs in the app target only. If needed for tests later, inject a `Bundle` parameter. |
| `fetchCount` unavailable or behaves differently on iOS 17 | Low | `fetchCount(FetchDescriptor<Exercise>())` is standard SwiftData API, available on iOS 17. |
| Large JSON file parsing performance | Very Low | 67 exercises is tiny. JSONDecoder handles this in milliseconds. |

## Definition of Done Checklist

- [ ] `SeedExerciseDTO.swift` created with all JSON fields as properties
- [ ] `SeedExerciseFile` wrapper struct decodes the top-level JSON structure
- [ ] `SeedDataLoader.swift` loads and parses `seed_exercises.json` from Bundle.main
- [ ] `SeedService.swift` checks Exercise table count, seeds only when empty
- [ ] DTO → Exercise mapping handles all 10 equipmentType values
- [ ] DTO → Exercise mapping handles all 3 trackingType values in JSON (WEIGHT_REPS, DURATION, WEIGHT_DISTANCE)
- [ ] DTO → Exercise mapping handles all 6 movementPattern values in JSON
- [ ] Invalid entries throw MappingError, caught and logged by SeedService
- [ ] All 67 exercises parse without errors
- [ ] `bilateralLoadFactor` defaults to nil (not in JSON)
- [ ] `createdAt` and `updatedAt` auto-set by Exercise.init()
- [ ] Project compiles with zero errors
- [ ] `tasks.md` updated with status change

## Review Guidance

- **Architecture check**: SeedService lives in `Core/Services/`. DTOs live in `Core/Seeding/`. Neither imports SwiftUI.
- **Enum mapping check**: Verify all switch cases cover the existing enum definitions in `Data/Enums/`. Ensure `default` throws (not silently ignores).
- **Idempotency check**: `fetchCount` returns > 0 on non-empty table → early return.
- **Error handling check**: Per-exercise try/catch in SeedService → skip + log, don't abort entire seeding.
- **Batch save check**: Single `modelContext.save()` after all inserts (not per-insert).

## Activity Log

- 2026-02-22T11:32:10Z – system – lane=planned – Prompt generated via /spec-kitty.tasks
- 2026-03-01T12:00:00Z – system – lane=planned – Reset to planned (previous entries were cross-feature contamination)
- 2026-03-01T13:42:31Z – claude_opus – shell_pid=22552 – lane=doing – Started implementation via workflow command
- 2026-03-01T13:47:37Z – claude_opus – shell_pid=22552 – lane=for_review – Ready for review: SeedExerciseDTO, SeedDataLoader, SeedService, DTO mapping. All 4 files created, registered in pbxproj. Build succeeds zero errors.
- 2026-03-01T15:55:46Z – claude_opus_reviewer – shell_pid=26607 – lane=doing – Started review via workflow command
- 2026-03-01T15:56:12Z – claude_opus_reviewer – shell_pid=26607 – lane=done – Review passed: All 4 files verified. Enum mappings complete. Build succeeds zero errors.
