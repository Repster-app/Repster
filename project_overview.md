# Strength Training App — Project Overview

**Last Updated:** January 2026

---

## Quick Reference

This document serves as an index to all project documentation. Start here when resuming work.

---

## Document Inventory

| Document | Version | Status | Purpose |
|----------|---------|--------|---------|
| **Data Model Specification** | 1.3 | ✅ Stable | Complete schema, PR logic, implementation contracts |
| **Tech Stack & Architecture** | 1.0 | ✅ Locked | Platform, database, architecture decisions |
| **Screen Inventory** | 0.1 | 🟡 Draft | UI screens, navigation, data requirements |
| **Schema Diagram (SVG)** | — | ✅ Current | Visual ERD (viewable in browser) |
| **Schema Diagram (Draw.io)** | — | ✅ Current | Editable ERD |
| **Schema Diagram (Mermaid)** | — | ✅ Current | Code-based ERD |

---

## Tech Stack Decisions (Locked)

| Category | Decision |
|----------|----------|
| **Platform** | iOS 17+, iPhone only |
| **UI Framework** | SwiftUI |
| **Database** | SwiftData |
| **Architecture** | MVVM |
| **Crash Reporting** | Firebase Crashlytics |
| **Analytics** | TelemetryDeck or PostHog (add later) |
| **Monetization v1** | Paid upfront (StoreKit 2) |
| **Monetization future** | RevenueCat (if adding subscriptions) |
| **Cloud Sync** | Not in v1, designed for future |
| **Testing** | Manual for v1 |
| **CI/CD** | Skip for v1, Xcode Cloud later |
| **Data Export** | CSV |
| **Data Import** | CSV from competitor app |

---

## Key Decisions Made

### Data Model (v1.3)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| PR storage | Single `PerformanceRecord` table | Prevents state drift between separate tables |
| Bodyweight handling | `bodyweightFactor` (0.0–1.0) on Exercise | More precise than boolean |
| Effective weight | Stored on Set at save time | Historical accuracy without join complexity |
| PR comparison | Integer grams (not float epsilon) | Deterministic equality checks |
| Volume formula | `effectiveWeight × reps` | Accurate across bodyweight/weighted exercises |
| Soft delete | No — hard delete | Simpler; rebuildable stats/PRs handle recalculation |
| PR display | Suffix-max filtering | Shows "capability frontier" not all historical bests |
| Tie-breaker | Earliest date wins | PR date doesn't slide forward on repeats |

### Performance Principles

| Principle | Details |
|-----------|---------|
| No startup rebuild | `PerformanceRecord` and `ExerciseStats` are always current |
| Write-time updates | PR and stats computed when set is saved |
| Database aggregation | Use SQL SUM/MAX/GROUP BY, don't iterate in Swift |
| Minimal RAM | Exercise names (~200) in memory; everything else queried |
| Indexed queries | Required indexes documented in spec Section 7.6 |

---

## Open Decisions

### UX (needs decision)

| Question | Options |
|----------|---------|
| Tab structure | 5 tabs as proposed? |
| Active workout persistence | Keep in memory or auto-save draft? |
| PR celebration | Modal, banner, or subtle badge? |
| Superset visualization | How to display in active workout? |

### Tech Stack — All Locked ✅

See Tech Stack & Architecture document (v1.0) for all decisions.

---

## Tables Quick Reference

### Core Tables
- `Set` — Atomic performance record (the main event)
- `Workout` — Session container
- `Exercise` — Exercise metadata and configuration

### Derived/Cached Tables
- `PerformanceRecord` — PRs (repMax, e1RM, maxVolume)
- `ExerciseStats` — Cached aggregates per exercise

### User/Health Tables
- `HealthProfile` — Local user settings
- `BodyweightEntry` — Bodyweight history

### Program Tables
- `Program` — Training program definition
- `ProgramExercise` — Exercise prescriptions in program
- `PlannedWorkout` — Scheduled workout templates
- `PlannedSet` — Target sets within planned workouts

---

## Critical Fields to Remember

| Field | Table | Why It Matters |
|-------|-------|----------------|
| `effectiveWeight` | Set | Includes bodyweight contribution; used for PRs and volume |
| `cachedPRStatus` | Set | Fast PR badge display without query |
| `bodyweightFactor` | Exercise | 0.0–1.0 multiplier for effective weight calc |
| `trackingType` | Exercise | **Immutable once sets exist** |
| `recordType` | PerformanceRecord | Enum: repMax, e1RM, maxVolume |

---

## File Locations

All documents should be in the outputs directory:

```
/mnt/user-data/outputs/
├── workout_app_data_model_specification.md   (main spec)
├── tech_stack_and_architecture.md            (tech decisions)
├── screen_inventory.md                        (UI screens)
├── workout_app_schema.svg                     (visual ERD)
├── workout_app_schema.drawio                  (editable ERD)
└── workout_app_erd.mermaid                    (code ERD)
```

---

## Next Steps

1. **Finalize tech decisions** — iOS version, database choice, architecture
2. **Review screen inventory** — Confirm all screens, navigation, priorities
3. **Create user flows** — Detailed step-by-step for critical paths
4. **Define MVP scope** — What ships first?
5. **Start implementation** — Data layer first, then core screens

---

## Context for AI Assistants

When resuming this project in a new session:

1. Read this overview first
2. Load the Data Model Specification (v1.3) for schema details
3. Reference Tech Stack doc for open decisions
4. Reference Screen Inventory for UI requirements

The data model is stable and should not change significantly. Tech stack and UI decisions are still being finalized.

---

*End of Document*
