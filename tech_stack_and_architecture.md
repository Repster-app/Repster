# Strength Training App — Tech Stack & Architecture

**Version:** 1.0  
**Status:** Decisions Locked  
**Last Updated:** January 2026

---

## Document Purpose

This document captures technical decisions for building the workout tracking app. It should be read alongside the Data Model Specification (v1.3) which defines the schema and business logic.

---

## Table of Contents

1. [Project Context](#1-project-context)
2. [Platform Decisions](#2-platform-decisions)
3. [Architecture Pattern](#3-architecture-pattern)
4. [Data Layer](#4-data-layer)
5. [Dependencies](#5-dependencies)
6. [Performance Requirements](#6-performance-requirements)
7. [Development Practices](#7-development-practices)
8. [Analytics & Monitoring](#8-analytics--monitoring)
9. [Monetization](#9-monetization)
10. [Cloud Sync](#10-cloud-sync)
11. [Data Import/Export](#11-data-importexport)
12. [Decision Summary](#12-decision-summary)

---

# 1. Project Context

## 1.1 What We're Building

A local-first strength training app for personal workout tracking. Key features:

- Log workouts with sets, reps, weight
- Automatic PR detection and tracking
- Exercise history and statistics
- Program/template support
- Charts and analytics

## 1.2 Known Constraints

| Constraint | Details |
|------------|---------|
| Single user | No authentication, no multi-user (HealthProfile is local) |
| Local-first | All data on device; no cloud sync for v1 |
| Dataset size | Expected 10,000–50,000+ sets over time |
| Performance | Must stay responsive with large dataset |
| Memory | Avoid bloat (competitor app has memory issues) |

## 1.3 Migration Context

User is migrating from an existing workout app with ~12,000 sets. Data import capability may be needed.

---

# 2. Platform Decisions

## 2.1 Target Platform

| Decision | Choice | Notes |
|----------|--------|-------|
| Platform | **iOS only** | No Android planned |
| Min iOS version | **iOS 17+** | Enables SwiftData; ~80%+ device coverage |
| Devices | **iPhone only** | iPad not supported in v1 (can be added later) |
| Apple Watch | **v2** | Not in v1; architecture should not block it |

## 2.2 UI Framework

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | **SwiftUI** | Modern, declarative, less boilerplate, native SwiftData integration |

**Note:** UIKit can be used for specific components if SwiftUI has limitations, but SwiftUI is the primary framework.

---

# 3. Architecture Pattern

## 3.1 Pattern Choice

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Architecture | **MVVM** | Standard for SwiftUI, good balance of structure and simplicity, AI agents understand it well |

**Why MVVM over alternatives:**
- TCA: Overkill for this app, steep learning curve
- Clean Architecture: Over-engineered for team size
- Simple MV: Too simple, won't scale

## 3.2 Layer Structure

```
┌─────────────────────────────────────────┐
│                  Views                   │
│         (SwiftUI screens/components)     │
├─────────────────────────────────────────┤
│              ViewModels                  │
│    (presentation logic, UI state)        │
├─────────────────────────────────────────┤
│               Services                   │
│  (PRService, StatsService, WorkoutService)│
├─────────────────────────────────────────┤
│             Repositories                 │
│   (SetRepository, ExerciseRepository)    │
├─────────────────────────────────────────┤
│              Data Layer                  │
│             (SwiftData)                  │
└─────────────────────────────────────────┘
```

## 3.3 Key Services

| Service | Responsibility |
|---------|----------------|
| `WorkoutService` | Create/edit/delete workouts, manage active workout state |
| `SetService` | Save sets, trigger PR pipeline, update stats |
| `PRService` | PR evaluation, PerformanceRecord management, suffix-max filtering |
| `StatsService` | ExerciseStats updates, rebuilds |
| `BodyweightService` | Bodyweight entries, closest-weight lookup for effectiveWeight |
| `ExerciseService` | Exercise CRUD, name search |
| `ProgramService` | Program templates, planned workouts |

## 3.4 Dependency Injection

| Decision | Choice | Rationale |
|----------|--------|-----------|
| DI Approach | **Simple / Manual** | No framework needed for v1; pass dependencies via init or SwiftUI Environment |

**Note:** Can add a DI framework (like Factory) later if complexity grows. Not needed initially.

---

# 4. Data Layer

## 4.1 Database Choice

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Database | **SwiftData** | Modern, Swift-native, seamless SwiftUI integration, less boilerplate than Core Data |

**Why SwiftData over alternatives:**
- Core Data: More verbose, older patterns
- GRDB: Too manual for our needs
- Realm: Unnecessary third-party dependency

**Performance Note:** SwiftData uses Core Data's storage engine underneath. Performance issues in past apps were due to bad patterns (loading entire tables into RAM, iterating in code), not the database itself. Following the Data Model Spec's guidance (Section 8) prevents these issues.

## 4.2 Data Access Patterns

From Data Model Spec Section 8, key principles:

| Principle | Implementation |
|-----------|----------------|
| No startup index rebuild | `PerformanceRecord` and `ExerciseStats` are persistent, always current |
| Database aggregation | Use SwiftData predicates and fetch descriptors — don't iterate in Swift |
| Write-time updates | PR and stats updated when set is saved |
| Minimal RAM | Don't cache entire tables; query what's needed |
| Indexed queries | Ensure indexes on `(exerciseId, reps, effectiveWeight)` etc. |

## 4.3 Repository Pattern

Each entity has a repository abstracting data access:

```swift
protocol SetRepository {
    func save(_ set: WorkoutSet) async throws
    func delete(_ set: WorkoutSet) async throws
    func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet]
    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]
}
```

Services use repositories, never access SwiftData ModelContext directly.

## 4.4 PR Pipeline Integration

When `SetService.save(set)` is called:

```
1. Repository saves set
2. PRService.evaluate(set) called
   - Queries PerformanceRecord
   - Updates cachedPRStatus on set
   - Updates PerformanceRecord if new PR
   - Updates old PR set's status to "previous"
3. StatsService.updateStats(for: exerciseId)
   - Incremental update to ExerciseStats
```

This should run on a background context to avoid blocking UI.

---

# 5. Dependencies

## 5.1 Core Dependencies (Locked)

| Dependency | Purpose | Notes |
|------------|---------|-------|
| **Swift Charts** | Built-in charting | iOS 16+, no external library needed |
| **Firebase Crashlytics** | Crash reporting | Free, industry standard |
| **StoreKit 2** | In-app purchases | Native, for paid upfront model |

## 5.2 Future Dependencies (When Needed)

| Dependency | Purpose | When to Add |
|------------|---------|-------------|
| **TelemetryDeck** or **PostHog** | Analytics | When ready to track usage |
| **RevenueCat** | Subscription management | If/when adding subscriptions |

## 5.3 Optional (Add If Needed)

| Dependency | Purpose | Decision |
|------------|---------|----------|
| **swift-algorithms** | Collection utilities | Add if needed |
| **swift-collections** | OrderedDictionary, Deque | Add if needed |

## 5.4 Explicitly Avoided

| Dependency | Reason |
|------------|--------|
| Realm | Unnecessary, using SwiftData |
| Firebase (full suite) | Only using Crashlytics, not database/auth |
| RxSwift/Combine-heavy | SwiftUI has built-in reactivity |
| Core Data | Using SwiftData instead |
| Third-party chart libraries | Swift Charts sufficient |

---

# 6. Performance Requirements

## 6.1 Targets

| Metric | Target | Notes |
|--------|--------|-------|
| App launch | < 2 seconds | Cold start to usable |
| Set save | < 100ms | Including PR pipeline |
| Screen transitions | < 200ms | No perceptible lag |
| List scrolling | 60 FPS | Even with 1000+ rows |
| Memory (idle) | < 100MB | _TBD: validate_ |
| Memory (active workout) | < 150MB | _TBD: validate_ |

## 6.2 Dataset Assumptions

| Scale | Sets | Exercises | Workouts |
|-------|------|-----------|----------|
| Current | 12,000 | ~200 | ~500 |
| 2 years | 25,000 | ~250 | ~1,000 |
| 5 years | 50,000+ | ~300 | ~2,000 |

App must remain responsive at 50k sets.

## 6.3 Performance Strategies

From Data Model Spec:

- **No in-memory indexes** for large tables
- **Lazy loading** for charts (compute on first access)
- **Pagination** for long lists
- **Write-time aggregation** for stats/PRs
- **Indexed queries** for all PR lookups

---

# 7. Development Practices

## 7.1 Code Organization

```
WorkoutApp/
├── App/
│   └── WorkoutApp.swift
├── Features/
│   ├── Workout/
│   │   ├── Views/
│   │   ├── ViewModels/
│   │   └── Models/
│   ├── Exercise/
│   ├── History/
│   ├── Programs/
│   └── Settings/
├── Core/
│   ├── Services/
│   ├── Repositories/
│   └── Extensions/
├── Data/
│   ├── Models/           (SwiftData models)
│   └── Persistence/
└── Resources/
```

## 7.2 Testing Strategy

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Testing Approach | **Manual testing for v1** | Run app, test with real data, identify issues |

**Future (add when needed):**
- Unit tests for PR pipeline (if bugs appear)
- Unit tests for ViewModels
- Skip UI tests initially (high maintenance)

## 7.3 CI/CD

| Decision | Choice | Rationale |
|----------|--------|-----------|
| CI/CD | **Skip for v1** | Add Xcode Cloud later for automated TestFlight builds |

## 7.4 Error Handling

| Approach | Details |
|----------|---------|
| Crash reporting | Firebase Crashlytics (automatic crash reports) |
| User-facing errors | Simple alerts for recoverable errors |
| Logging | Console logs during development; Crashlytics for production |

## 7.5 Design Approach

| Decision | Choice |
|----------|--------|
| Design system | **Mix of HIG + custom** — Stock structure (NavigationStack, TabView, List) with custom styling |
| Dark mode | **Both** — Follow system setting |
| Accessibility | **Basic for v1** — Reasonable contrast, tap targets. Full VoiceOver support later if needed |

---

# 8. Analytics & Monitoring

## 8.1 Crash Reporting

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Provider | **Firebase Crashlytics** | Free, industry standard, good iOS SDK |

**Implementation:** Add Firebase SDK, configure at app launch. Automatic crash reports.

## 8.2 User Analytics

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Analytics | **Optional for v1** | Add TelemetryDeck or PostHog when ready |
| What to track | Basic usage (screens viewed, features used) | Not detailed behavior tracking |

**Options when ready:**
- **TelemetryDeck** — Privacy-first, simpler, good for basic analytics
- **PostHog** — More features, A/B testing capability, self-hostable

**Note:** Can add analytics later without architecture changes.

---

# 9. Monetization

## 9.1 Business Model

| Decision | Choice | Rationale |
|----------|--------|-----------|
| v1 Model | **Paid upfront** (one-time purchase) | Simple, no subscription infrastructure needed |
| Future | **Subscription possible** | May add if needed |

## 9.2 Implementation

| Phase | Approach |
|-------|----------|
| v1 | **StoreKit 2** — Native, straightforward for one-time purchase |
| If adding subscriptions | **RevenueCat** — Free under $2.5k/month, handles edge cases |

## 9.3 Paywall Strategy (If Subscription)

| Approach | Details |
|----------|---------|
| Free tier | X workouts before payment required |
| Gating | Workout count limit (not feature gating) |

---

# 10. Cloud Sync

## 10.1 Decision

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Cloud Sync | **Design for it, don't build it** | Local-only for v1; architecture supports future sync |

## 10.2 Architecture Implications

Already supported by current design:
- UUIDs for all IDs ✓
- `createdAt`/`updatedAt` timestamps on all records ✓
- Repository pattern abstracts data access ✓

**If/when adding sync:** iCloud + CloudKit is the simplest path for iOS-only apps.

---

# 11. Data Import/Export

## 11.1 Export

| Decision | Choice |
|----------|--------|
| Format | **CSV** |
| Scope | All workouts, sets, exercises |

## 11.2 Import

| Decision | Choice |
|----------|--------|
| Priority | **Needed** — User migrating from existing app |
| Source Format | CSV from competitor app |

**Source CSV Structure:**
```
Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind
2021-05-20,Barbell Squat,Legs,40.00,88.18,8,,,,,wr
2021-05-20,Barbell Squat,Legs,42.50,93.70,8,,,,,wr
```

**Import Mapping:**

| CSV Field | Maps To |
|-----------|---------|
| Date | `Set.date`, `Workout.date` |
| Exercise | `Exercise.name` (create if not exists) |
| Category | `Exercise.primaryMuscle` |
| Weight (kg) | `Set.weight` |
| Weight (lbs) | Ignore (derived) |
| Reps | `Set.reps` |
| Distance | `Set.distanceMeters` |
| Time | `Set.durationSeconds` |
| Notes | `Set.notes` |
| Kind | `Set.setType` (map "wr" → "working", etc.) |

**Import Logic:**
1. Group rows by Date → Create Workout per unique date
2. Create Exercises for unknown names (infer equipment from name if possible)
3. Create Sets with proper workout/exercise relationships
4. Run stats rebuild after import
5. Run PR calculation after import

---

# 12. Decision Summary

All major technical decisions locked:

| Category | Decision |
|----------|----------|
| **Platform** | iOS 17+, iPhone only, SwiftUI |
| **Database** | SwiftData |
| **Architecture** | MVVM |
| **Crash Reporting** | Firebase Crashlytics |
| **Analytics** | TelemetryDeck or PostHog (add later) |
| **Monetization** | Paid upfront (StoreKit 2), RevenueCat if subscriptions |
| **Cloud Sync** | Not in v1, designed for future |
| **Testing** | Manual for v1 |
| **CI/CD** | Skip for v1 |
| **Export** | CSV |
| **Import** | CSV from competitor app |

---

# Appendix A: Related Documents

| Document | Location | Status |
|----------|----------|--------|
| Data Model Specification | `workout_app_data_model_specification.md` | ✅ v1.3 Stable |
| Schema Diagram (SVG) | `workout_app_schema.svg` | ✅ Current |
| Schema Diagram (Draw.io) | `workout_app_schema.drawio` | ✅ Current |
| Schema Diagram (Mermaid) | `workout_app_erd.mermaid` | ✅ Current |
| Screen Inventory | `screen_inventory.md` | 🟡 Draft |
| Project Overview | `project_overview.md` | ✅ Current |

---

# Appendix B: Change Log

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | January 2026 | Initial draft with context and open questions |
| 1.0 | January 2026 | All decisions locked: iOS 17+, iPhone only, SwiftData, MVVM, Firebase Crashlytics, paid upfront, manual testing. Added sections for Analytics, Monetization, Cloud Sync, Data Import. Documented CSV import mapping from competitor app. |

---

*End of Document*
