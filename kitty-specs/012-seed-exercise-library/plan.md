# Implementation Plan: Seed Exercise Library

**Branch**: `012-seed-exercise-library` | **Date**: 2026-03-01 | **Spec**: `kitty-specs/012-seed-exercise-library/spec.md`
**Input**: Feature specification from `kitty-specs/012-seed-exercise-library/spec.md`

## Summary

Load 67 pre-configured exercises from a bundled `seed_exercises.json` file into SwiftData on first app launch. The seeding pipeline: parse JSON into DTOs, map DTOs to `Exercise` model objects (handling enum format mismatches), insert into SwiftData if the Exercise table is empty. Idempotent — runs once, never re-seeds.

## Technical Context

**Language/Version**: Swift (latest stable), iOS 17.0+
**Primary Dependencies**: SwiftData, Foundation (JSONDecoder)
**Storage**: SwiftData (existing `Exercise` @Model)
**Testing**: Manual verification (no automated tests for v1 per constitution)
**Target Platform**: iOS 17.0+, iPhone only
**Project Type**: Mobile (existing Xcode project)
**Performance Goals**: Seeding completes in < 1 second (67 inserts + 1 save)
**Constraints**: Synchronous execution in `ReppoApp.init()`, before any view renders
**Scale/Scope**: 67 exercises, one-time operation

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Rule | Status | Notes |
|------|--------|-------|
| Services contain business logic | PASS | SeedService orchestrates seeding logic |
| Repositories are the only layer that touches ModelContext | EXCEPTION | SeedService accesses ModelContext directly — justified because seeding is a one-time initialization concern, not ongoing data access. No repository needed for a one-shot batch insert. |
| No startup rebuild | PASS | Seeding is NOT a rebuild — it runs once on empty table, not every launch |
| UUIDs for all IDs | PASS | Exercise.init() generates UUID automatically |
| No UI involvement in service logic | PASS | Seeding is headless — no views, no ViewModels |
| Prefer async/await | N/A | Synchronous is correct here — 67 inserts in init() before views render |
| No third-party deps | PASS | Foundation + SwiftData only |
| File organization matches constitution | PASS | DTOs in Core/Seeding/, service in Core/Services/ |

## Project Structure

### Documentation (this feature)

```
kitty-specs/012-seed-exercise-library/
├── plan.md              # This file
├── data-model.md        # Phase 1: DTO and mapping definitions
├── spec.md              # Feature specification (exists)
├── tasks.md             # Work package index (exists)
└── tasks/
    ├── WP01-seed-parsing-and-service.md
    └── WP02-app-wiring-and-verification.md
```

### Source Code (repository root)

```
Reppo/
├── Core/
│   ├── Seeding/                          # NEW directory
│   │   ├── SeedExerciseDTO.swift         # NEW — Codable DTO matching JSON shape
│   │   └── SeedDataLoader.swift          # NEW — Bundle JSON loading
│   └── Services/
│       └── SeedService.swift             # NEW — Seeding orchestration
├── App/
│   └── ReppoApp.swift                    # MODIFY — Add seeding call in init()
├── Data/
│   ├── Models/
│   │   └── Exercise.swift                # EXISTING — Target model (read-only)
│   └── Enums/
│       ├── EquipmentType.swift           # EXISTING — Read-only reference
│       ├── TrackingType.swift            # EXISTING — Read-only reference
│       └── MovementPattern.swift         # EXISTING — Read-only reference
└── Resources/
    └── seed_exercises.json               # EXISTING — 67 exercises (read-only)
```

**Structure Decision**: Mobile iOS project. New files placed in `Core/Seeding/` (DTOs + loader) and `Core/Services/` (SeedService), following the existing project layout. Only modification to existing code is `ReppoApp.swift`.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| SeedService direct ModelContext access | One-time initialization — check empty table, batch insert 67 rows, done | Adding a SeedRepository would create a permanent abstraction for a one-shot operation that never runs again after first launch |

## Design Decisions

### 1. Enum Mapping Strategy

JSON values don't match Swift enum rawValues:
- `trackingType`: JSON uses `UPPER_SNAKE_CASE` ("WEIGHT_REPS"), Swift uses camelCase (`.weightReps`)
- `equipmentType`: JSON uses `snake_case` ("machine_plate"), Swift uses camelCase (`.machinePlate`)
- `movementPattern`: JSON uses lowercase — matches Swift rawValues directly

**Decision**: Explicit `switch` statements in a `toExercise()` mapping method. Safer than `init(rawValue:)` and produces clear error messages for unknown values.

### 2. DTO Separation

`SeedExerciseDTO` is a plain `Codable` struct with `String` fields for enums. It does NOT import SwiftData. Mapping to `Exercise` happens in a separate extension method. This keeps JSON parsing decoupled from model creation.

### 3. Idempotency Check

Use `modelContext.fetchCount(FetchDescriptor<Exercise>())` — lightweight count query, no data loaded. Seeds only when count == 0. No UserDefaults flag needed.

### 4. Error Handling

Per-exercise try/catch in SeedService. Invalid entries are skipped with `print()` warning (FR-008). Seeding continues for remaining exercises. Single `modelContext.save()` after all inserts (batch).

### 5. ReppoApp.swift Integration Point

Current `ReppoApp.init()` creates `ModelContainer` → `RepositoryContainer` → `ServiceContainer`. The seeding call goes after `ModelContainer` creation, using a local `ModelContext(container)`. This context is temporary — data persists via `modelContext.save()`.

```swift
// After: let container = try ModelContainerSetup.createContainer()
// Before: self.repositories = RepositoryContainer(...)
let seedContext = ModelContext(container)
SeedService.seedIfNeeded(modelContext: seedContext)
```
