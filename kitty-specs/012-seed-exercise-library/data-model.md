# Data Model: Seed Exercise Library

**Feature**: 012-seed-exercise-library
**Date**: 2026-03-01

## New Types

### SeedExerciseFile (Codable container)

Top-level wrapper matching the JSON file structure.

| Field | Type | Source |
|-------|------|--------|
| exercises | [SeedExerciseDTO] | JSON array |

Note: The JSON also contains a `_meta` object — this is ignored during decoding (not needed at runtime).

### SeedExerciseDTO (Codable struct)

Plain struct matching the JSON shape. All enum fields stored as `String` — mapping to Swift enums happens in `toExercise()`.

| Field | Type | JSON Key | Notes |
|-------|------|----------|-------|
| name | String | name | Required |
| equipmentType | String | equipmentType | Raw string, e.g. "barbell", "machine_plate" |
| trackingType | String | trackingType | Raw string, UPPER_SNAKE_CASE, e.g. "WEIGHT_REPS" |
| primaryMuscle | String? | primaryMuscle | Optional |
| secondaryMuscles | [String] | secondaryMuscles | Always present in JSON (may be empty array) |
| movementPattern | String? | movementPattern | Optional |
| unilateral | Bool | unilateral | |
| bodyweightFactor | Double | bodyweightFactor | 0.0 = no bodyweight component |
| weightIncrement | Double? | weightIncrement | Optional |
| defaultRestTime | Int? | defaultRestTime | In seconds |

**File**: `Reppo/Core/Seeding/SeedExerciseDTO.swift`
**Imports**: Foundation only (no SwiftData)

### SeedExerciseDTO+Mapping

Extension on `SeedExerciseDTO` providing `toExercise() throws -> Exercise`.

**Enum mapping table**:

| JSON Value | Swift Enum | Notes |
|-----------|------------|-------|
| "WEIGHT_REPS" | TrackingType.weightReps | UPPER_SNAKE → camelCase |
| "DURATION" | TrackingType.duration | Direct lowercase match |
| "WEIGHT_DISTANCE" | TrackingType.weightDistance | UPPER_SNAKE → camelCase |
| "WEIGHT_REPS_DURATION" | TrackingType.weightRepsDuration | UPPER_SNAKE → camelCase |
| "CUSTOM" | TrackingType.custom | UPPER_SNAKE → camelCase |
| "machine_plate" | EquipmentType.machinePlate | snake_case → camelCase |
| "machine_pin" | EquipmentType.machinePin | snake_case → camelCase |
| "barbell" | EquipmentType.barbell | Direct match |
| "dumbbell" | EquipmentType.dumbbell | Direct match |
| "bodyweight" | EquipmentType.bodyweight | Direct match |
| "cable" | EquipmentType.cable | Direct match |
| "sled" | EquipmentType.sled | Direct match |
| "kettlebell" | EquipmentType.kettlebell | Direct match |
| "band" | EquipmentType.band | Direct match |
| "other" | EquipmentType.other | Direct match |
| "hinge" | MovementPattern.hinge | Direct match |
| "squat" | MovementPattern.squat | Direct match |
| "press" | MovementPattern.press | Direct match |
| "pull" | MovementPattern.pull | Direct match |
| "carry" | MovementPattern.carry | Direct match |
| "rotation" | MovementPattern.rotation | Direct match |
| "other" | MovementPattern.other | Direct match |

Unknown values throw `MappingError` (caught per-exercise by SeedService).

**Fields NOT in JSON** (use Exercise.init() defaults):
- `id`: Auto-generated UUID
- `bilateralLoadFactor`: nil
- `createdAt`: Date()
- `updatedAt`: Date()

## New Services

### SeedDataLoader (enum, static methods)

| Method | Signature | Purpose |
|--------|-----------|---------|
| loadExercises | `static func loadExercises() throws -> [SeedExerciseDTO]` | Load and parse seed_exercises.json from Bundle.main |

**Errors**: `SeedError.fileNotFound`, `SeedError.decodingFailed(Error)`
**File**: `Reppo/Core/Seeding/SeedDataLoader.swift`

### SeedService (enum, static methods)

| Method | Signature | Purpose |
|--------|-----------|---------|
| seedIfNeeded | `static func seedIfNeeded(modelContext: ModelContext)` | Check empty → load → map → insert → save |

**Flow**:
1. `fetchCount(FetchDescriptor<Exercise>())` — if > 0, return
2. `SeedDataLoader.loadExercises()` — parse JSON
3. For each DTO: `dto.toExercise()` — map with enum conversion (try/catch per exercise)
4. `modelContext.insert(exercise)` — add to context
5. `modelContext.save()` — batch persist

**File**: `Reppo/Core/Services/SeedService.swift`

## Existing Types (read-only reference)

### Exercise (@Model)

Already defined in `Reppo/Data/Models/Exercise.swift`. All fields documented in plan.md. SeedService creates instances via `Exercise.init(name:equipmentType:trackingType:...)`.

### Enums

- `EquipmentType`: 10 cases (barbell, dumbbell, machinePlate, machinePin, bodyweight, sled, cable, kettlebell, band, other)
- `TrackingType`: 5 cases (weightReps, duration, weightDistance, weightRepsDuration, custom)
- `MovementPattern`: 7 cases (hinge, squat, press, pull, carry, rotation, other)

All are `String, Codable, CaseIterable` enums in `Reppo/Data/Enums/`.
