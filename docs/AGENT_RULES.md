# Strength Training App — Agent Rules

**Purpose:** Mandatory rules for any AI agent contributing code to this project. Read this file in full before writing any code.  
**Authority:** These rules are derived from the Data Model Specification (v1.3), Tech Stack & Architecture (v1.0), Design System, and Project Overview. If a rule here conflicts with your assumptions, the rule wins.  
**Version:** 1.1  
**Last Updated:** February 2026

---

## 0. v1 Scope

### What ships in v1

- Active workout logging (exercises, sets, reps, weight, RPE/RIR)
- PR detection with subtle badge on set row (write-time, no modals)
- Calendar tab (history view, tap date for workout detail, future scheduled sessions)
- Exercise list/browser (via FAB, browse PRs, stats, history)
- Charts tab (overview dashboard + per-exercise drill-down)
- Settings (units, e1RM formula, warmup preferences, data import/export, rebuild stats)
- CSV import from competitor app (~12,000 sets)
- CSV export
- Onboarding (units, e1RM formula, bodyweight)
- Dark mode only
- Paid upfront (StoreKit 2)
- Firebase Crashlytics

### What ships in v1.1

- Programs tab (full functionality, empty state placeholder in v1)
- Custom numeric keyboard (quick-value buttons, set context toolbar)

### Explicitly NOT in v1

- Light mode / dynamic theme
- Cloud sync / iCloud
- Apple Watch
- iPad support
- CI/CD (Xcode Cloud)
- Automated tests
- Analytics (TelemetryDeck / PostHog)
- Subscriptions / RevenueCat

---

## 1. Project Identity

- **App type:** Local-first iOS strength training tracker
- **Platform:** iOS 17+, iPhone only. No iPad, no Android, no web.
- **Language:** Swift (latest stable)
- **UI:** SwiftUI (primary). UIKit only if SwiftUI has a proven limitation for a specific component.
- **Database:** SwiftData (backed by Core Data storage engine)
- **Architecture:** MVVM with Service and Repository layers
- **Min deployment target:** iOS 17.0

---

## 2. Architecture Rules

### Layer Structure (top to bottom)

```
Views → ViewModels → Services → Repositories → SwiftData
```

- **Views** call ViewModels only. Never call Services or Repositories directly from a View.
- **ViewModels** call Services. ViewModels never access SwiftData ModelContext directly.
- **Services** contain business logic. Services call Repositories for data access.
- **Repositories** are the only layer that touches SwiftData ModelContext.
- Never skip layers. A View must not call a Repository. A ViewModel must not call a Repository.

### Dependency Injection

- Use **manual/simple DI** via initializer injection or SwiftUI `.environment`.
- Do NOT add a DI framework (e.g., Swinject, Factory) unless explicitly approved.

### File Organization

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
│   ├── Models/           (SwiftData @Model classes)
│   └── Persistence/
└── Resources/
```

---

## 3. Data Model Rules (CRITICAL)

These rules are non-negotiable. Violating them will introduce bugs that are painful to find.

### 3.1 Naming

- The `Set` model **must** be named `WorkoutSet` in Swift code to avoid collision with Swift's `Set` type.
- All model IDs are `UUID`.
- All models have `createdAt` and `updatedAt` timestamps.

### 3.2 Units — Internal Storage

| Dimension | Storage Unit | Convert in UI only |
|-----------|-------------|-------------------|
| Weight | **kg** (Float/Double) | Display as kg or lbs based on user preference |
| Distance | **meters** (Float/Double) | Display as m, km, mi, etc. |
| Duration | **seconds** (Int) | Display as mm:ss or hh:mm:ss |

Never store imperial units. Never do math on imperial values. Convert at the UI boundary only.

### 3.3 Effective Weight

Every time a set is **saved**, compute and store `effectiveWeight`:

```
effectiveWeight = weight + (closestBodyweight × exercise.bodyweightFactor)
```

- If `bodyweightFactor == 0` → `effectiveWeight = weight`
- If no bodyweight entry exists → `effectiveWeight = weight` (and warn the user)
- **Never recalculate retroactively.** Historical sets keep their original effectiveWeight.
- All PR comparisons use `effectiveWeight`, not raw `weight`.
- Volume = `effectiveWeight × reps`.

### 3.4 Float Comparison — Integer Grams

**All weight comparisons for PR logic must convert to integer grams first:**

```swift
func toGrams(_ kg: Double) -> Int {
    return Int(round(kg * 1000))
}

// Correct
let isNewPR = toGrams(newSet.effectiveWeight) > toGrams(existingPR.value)
let isMatch = toGrams(newSet.effectiveWeight) == toGrams(existingPR.value)

// WRONG — never use == or > on raw floats for PR comparison
let isNewPR = newSet.effectiveWeight > existingPR.value  // BUG
```

Storage remains as float kg. Grams conversion is for comparison logic only.

### 3.5 trackingType is Immutable

Once an Exercise has associated sets, its `trackingType` **cannot be changed**. Enforce this in the `ExerciseRepository` or `ExerciseService`. The UI must prevent editing `trackingType` when sets exist.

### 3.6 hasData vs completed

These are different concepts:

- `completed` — stored boolean, user tapped "done" (UI workflow)
- `hasData` — **computed property**, the set has actual values

```swift
var hasData: Bool {
    (weight ?? 0 > 0 && reps ?? 0 > 0) ||
    (durationSeconds ?? 0 > 0) ||
    (distanceMeters ?? 0 > 0)
}
```

**Rule:** Analytics, PR calculations, and volume calculations use `hasData`, NOT `completed`.

### 3.7 Set Types and PR Eligibility

| Type | PR Eligible | Volume Eligible |
|------|------------|----------------|
| `warmup` | **No** (unless user setting overrides) | **No** (unless user setting overrides) |
| `partial` | **No** (always) | **No** (always) |
| All others (`working`, `dropset`, `restpause`, `amrap`, etc.) | **Yes** | **Yes** |

Check `excludeFromPRs` as an independent override — users can manually exclude any individual set.

---

## 4. PR Pipeline Rules (CRITICAL)

The PR pipeline is the most complex business logic in the app. Follow these rules exactly.

### 4.1 Write-Time, Not Read-Time

PRs and stats are computed **when a set is saved**, not when a screen is displayed. After `SetService.save(set)`:

1. `PRService.evaluate(set)` — check/update PerformanceRecord, set `cachedPRStatus`
2. `StatsService.updateStats(for: exerciseId)` — update ExerciseStats

This runs on a background context.

### 4.2 PR Ownership

- **Earliest occurrence wins.** If two sets have the same effectiveWeight for the same reps, the first one (by date) owns the PR.
- Exact matches do NOT create a new PR record. The matching set gets `cachedPRStatus = "matched"`.
- Same-workout matches get `cachedPRStatus = null` (no badge shown for consecutive identical sets in the same session).

### 4.3 PerformanceRecord Table

- **Single table** for all PR types (`repMax`, `e1RM`, `maxVolume`).
- Uniqueness constraint: `(exerciseId, recordType, reps)`
- Always query `PerformanceRecord` for PR lookups. Only query the `Set` table when a PR owner is deleted/edited and you need to find the next best.

### 4.4 On Set Edit (PR owner)

If the edited set was the current PR owner and the new value is **lower**:
- Query `Set` table to find the new best candidate
- Update `PerformanceRecord` to point to the new winner

### 4.5 On Set Delete (PR owner)

- Query `Set` table to find the new best candidate
- If none exists, delete the `PerformanceRecord` row

### 4.6 Suffix-Max Filtering for PR Display

When displaying a PR table, hide rows where a higher-rep PR has equal or greater weight. Iterate from highest reps to lowest, tracking `maxWeightSeen`. Only show rows where `value > maxWeightSeen`.

---

## 5. Performance Rules (CRITICAL)

These rules exist because competitor apps have severe performance and memory issues. Do not repeat their mistakes.

### 5.1 No Startup Rebuild

The app must NOT rebuild indexes, caches, PRs, or stats at startup. `PerformanceRecord` and `ExerciseStats` are always current because they're updated at write-time. Provide a manual "Rebuild Stats" action in Settings for rare maintenance scenarios (data import, migration, corruption recovery).

### 5.2 Database Aggregation, Not Swift Iteration

```swift
// ❌ NEVER DO THIS
let sets = try await repository.fetchAllSets(for: exerciseId) // loads 500+ sets
var total = 0.0
for set in sets { total += set.weight * Double(set.reps) }

// ✅ DO THIS
let total = try await repository.fetchTotalVolume(for: exerciseId)
// Uses: SELECT SUM(effectiveWeight * reps) FROM WorkoutSet WHERE exerciseId = ?

// ✅ OR THIS (best — already computed)
let stats = try await repository.fetchExerciseStats(for: exerciseId)
let total = stats.totalVolume
```

### 5.3 Memory Management

**Always in database, never loaded entirely into RAM:**
- `WorkoutSet` (10,000+ rows)
- `Workout` (1,000+ rows)
- `PerformanceRecord`
- `ExerciseStats`
- `BodyweightEntry`

**In memory only when actively displayed:**
- Current workout's sets (released when leaving workout screen)
- Exercise history (released when navigating away)
- Chart data points (released when leaving chart)

**Acceptable in session memory (small, bounded):**
- Exercise name list for autocomplete (~200 strings)
- User settings (1 object)
- Active workout state (1 workout + its sets)

**Never as global in-memory cache:**
- All workouts in a dictionary
- All exercises with all their sets
- All PRs for all exercises

### 5.4 Required Database Indexes

```sql
-- PR lookup (used on every set save)
CREATE INDEX idx_performance_record ON PerformanceRecord(exerciseId, recordType, reps);

-- Set queries for PR recomputation (rare but must be fast)
CREATE INDEX idx_set_pr_lookup ON WorkoutSet(exerciseId, reps, effectiveWeight DESC, date ASC);
```

Ensure these indexes exist in your SwiftData model configuration.

### 5.5 Performance Targets

| Metric | Target |
|--------|--------|
| App launch (cold) | < 2 seconds |
| Set save (including PR pipeline) | < 100ms |
| Screen transitions | < 200ms |
| List scrolling | 60 FPS |
| Memory (idle) | < 100MB |
| Memory (active workout) | < 150MB |

---

## 6. Service Responsibilities

| Service | Does | Does NOT |
|---------|------|----------|
| `SetService` | Save/edit/delete sets, orchestrate PR + stats pipeline | Access ModelContext directly |
| `PRService` | Evaluate PR eligibility, update PerformanceRecord, update cachedPRStatus | Modify sets beyond cachedPRStatus |
| `StatsService` | Update ExerciseStats incrementally or via rebuild | Own PR logic |
| `WorkoutService` | Create/edit/delete workouts, manage active workout state | Handle individual set logic |
| `BodyweightService` | CRUD for bodyweight entries, closest-weight lookup | Calculate effectiveWeight (that's SetService's job) |
| `ExerciseService` | Exercise CRUD, name search, enforce trackingType immutability | Store analytics (that's ExerciseStats) |
| `ProgramService` | Program/template CRUD, planned workout generation | Own workout execution logic |
| `ImportService` | CSV import, data mapping, trigger bulk rebuild | Normal set-by-set PR pipeline (use bulk rebuild instead) |

---

## 7. SwiftUI / UI Rules

### 7.1 General

- Follow Apple Human Interface Guidelines as a baseline.
- **Dark mode only for v1.** Do not build a light theme. All color tokens assume dark backgrounds.
- Minimum tap target: 44×44 points.
- No third-party UI component libraries. Use native SwiftUI components.
- Use `NavigationStack` (not deprecated `NavigationView`).
- Use `Swift Charts` for all charting (no third-party chart libraries).
- **Icons:** Use SF Symbols as the default icon set.
- **Font:** System font for v1. DM Sans will be added in a polish phase — do not hardcode font names; use a centralized type scale so the swap is easy.
- **Design System:** Follow `design-system.md` for all color tokens, spacing, typography scale, corner radii, and component patterns. When in doubt, refer to that document.

### 7.2 Navigation Structure

**5 tabs with center FAB:**

```
[ Programs ] [ Calendar ] [ + FAB + ] [ Charts ] [ Settings ]
```

- **Programs tab** — Training program management. **v1: empty state / placeholder.** Build out in v1.1.
- **Calendar tab** — Primary history view. Shows past workouts and future scheduled sessions. Tap a date to see full workout detail.
- **FAB (center)** — Starts a new workout. Opens the exercise list where user picks exercises. Also serves as the exercise browsing/PR viewing entry point when no workout is active. (This behavior may change — keep the navigation destination easy to swap.)
- **Charts tab** — Overview dashboard (total volume trends, frequency, muscle group distribution) with drill-down into per-exercise charts (e1RM trend, volume over time).
- **Settings tab** — User preferences, unit selection, e1RM formula, data import/export, rebuild stats.

**Bottom nav is visible on all main tab screens. It is NOT visible on focused screens** (active workout/exercise tracking, settings detail, etc.).

### 7.3 Active Workout Flow

```
FAB tap → Exercise List → Select exercises → Active Workout screen (focused, no bottom nav)
```

- Sets are saved individually as they are completed — workout data survives app termination naturally.
- Add a `status` field on `Workout` (`inProgress` / `completed`) so the app knows to reopen an active workout on relaunch.
- When the app launches and finds a workout with `status = inProgress`, navigate directly to it.
- "Finish Workout" flips status to `completed`.
- No separate draft/auto-save system needed — the existing write-on-completion model handles persistence.

### 7.4 PR Celebration

- **Subtle badge on the set row.** No modals, no toasts, no interruptions.
- Use the gold PR badge from the design system (`goldSoft` background, `gold` text, star icon + "PR").
- For matched PRs: blue badge with "=" symbol.
- The badge renders based on `cachedPRStatus` which is set at write-time by the PR pipeline.

### 7.5 Unit Display

- Read user's `unitPreference` from `HealthProfile` (metric or imperial).
- Display weights in the user's preferred unit. Store always in kg.
- All unit conversion happens in the View or ViewModel layer, never in Services or Repositories.

### 7.6 Custom Numeric Keyboard

- **v1: Use standard iOS number pad.**
- **v1.1: Build custom numeric keyboard** with quick-value buttons (−5, −2.5, Last, +2.5, +5), set context toolbar, and slide-up animation as specified in the design system (Section 6.5). This is a priority enhancement.

### 7.7 Screen Hierarchy

```
Main Tab Bar (bottom nav visible)
├── Programs (v1: empty state)
├── Calendar
│   └── Tap date → Workout Detail (Day View)
│       └── Tap exercise → Exercise History / PR Table
├── [FAB] → Exercise List
│   ├── Browse / search exercises
│   ├── View exercise detail (PRs, stats, history)
│   └── Select exercises → Active Workout (focused, no bottom nav)
│       ├── Exercise Tab Strip (switch between exercises)
│       ├── Set Table (editable, tap input for keyboard)
│       ├── Add Set / Add Warmup
│       └── Exercise Info (hero card + tiles)
├── Charts
│   ├── Overview dashboard
│   └── Drill into per-exercise charts
└── Settings
    ├── Units, e1RM formula, warmup preferences
    ├── Data import / export
    ├── Rebuild stats (maintenance)
    └── About / crash reporting
```

---

## 8. User Settings

Stored on `HealthProfile` (single-row local table):

| Setting | Type | Default |
|---------|------|---------|
| `unitPreference` | enum (metric/imperial) | metric |
| `includeWarmupsInVolume` | bool | false |
| `includeWarmupsInPRs` | bool | false |
| `e1RMFormula` | enum | epley |

The e1RM formula is user-selectable (available options: Epley, Brzycki, Lombardi, etc.). Each set snapshots the formula version used at save time via `e1RMFormulaVersion`.

When `includeWarmupsInVolume` or `includeWarmupsInPRs` is changed, a stats/PR rebuild may be required. Prompt the user and run `StatsService.rebuildAll()` / `PRService.rebuildAll()`.

---

## 9. Data Import

The user is migrating from a competitor app with ~12,000 sets via CSV.

### Import Rules

- Group CSV rows by date to create Workouts.
- Create Exercises for unknown names (set sensible defaults for equipment/tracking type).
- Map the `Kind` column to `setType` (e.g., "wr" → "working").
- Do NOT run the normal per-set PR pipeline during bulk import. Instead:
  1. Import all sets
  2. Run `StatsService.rebuildAll()`
  3. Run `PRService.rebuildAll()`
- Validate data before committing (reject malformed rows, report errors).

---

## 10. What NOT to Do

These are explicit anti-patterns. If you find yourself doing any of these, stop and reconsider.

| Anti-Pattern | Why It's Wrong | Do This Instead |
|-------------|---------------|-----------------|
| Loading all sets into memory to compute a total | Unbounded memory growth | Use SQL aggregation or pre-computed ExerciseStats |
| Comparing floats directly for PR equality | Floating point imprecision | Convert to integer grams |
| Rebuilding PR tables at app startup | Slow launch, unnecessary work | PRs are always current via write-time updates |
| Building multiple cache layers with different TTLs | Complexity explosion | Compute at write-time, read from pre-computed tables |
| Storing imperial units in the database | Aggregation bugs | Store metric, convert in UI |
| Putting business logic in Views | Untestable, violates MVVM | Put logic in ViewModels or Services |
| Accessing ModelContext from a ViewModel | Violates layer separation | Use Repository methods |
| Changing trackingType on an exercise that has sets | Breaks historical data integrity | Prevent in UI and enforce in service layer |
| Using NavigationView | Deprecated | Use NavigationStack |
| Adding third-party dependencies without approval | Dependency bloat | Use native APIs first (Swift Charts, StoreKit 2, etc.) |

---

## 11. Onboarding Flow

A lightweight onboarding (2–3 screens max) covers:

1. **Unit preference** — kg or lbs
2. **e1RM formula** — with brief plain-English explanations (default: Epley)
3. **Bodyweight entry** — optional but encouraged (needed for effectiveWeight on bodyweight exercises)

All settings are changeable later in Settings. Do not gate app usage on completing onboarding.

---

## 12. Dependencies

### Approved (use freely)

- Swift Charts (charting)
- Firebase Crashlytics (crash reporting)
- StoreKit 2 (monetization)

### Approved When Needed

- swift-algorithms, swift-collections (if specific utilities are needed)
- TelemetryDeck or PostHog (analytics, add later)
- RevenueCat (if adding subscriptions)

### Explicitly Banned

- Realm, GRDB (using SwiftData)
- Firebase full suite (only Crashlytics)
- RxSwift (SwiftUI has built-in reactivity)
- Core Data directly (using SwiftData)
- Third-party chart libraries (using Swift Charts)
- Any DI framework (manual DI for v1)

---

## 13. Code Style

- Use Swift's standard naming conventions (camelCase for properties/methods, PascalCase for types).
- Prefer `async/await` over completion handlers.
- Use `@Observable` (iOS 17+) for ViewModels, not `ObservableObject` with `@Published`.
- Use Swift's native error handling (`throws`, `do/catch`), not Result types unless there's a specific reason.
- Keep functions short and focused. If a function exceeds ~40 lines, consider breaking it up.
- Add `// MARK:` comments to organize long files.
- Document non-obvious business logic with comments referencing the spec section (e.g., `// See Spec Section 7.2 — PR Pipeline`).

---

## 14. Reference Documents

When in doubt, consult these documents in this priority order:

1. **Data Model Specification v1.3** — Schema, PR logic, implementation contracts (authoritative source of truth)
2. **Tech Stack & Architecture v1.0** — Platform, database, architecture decisions
3. **Design System** (`design-system.md`) — Color tokens, typography, spacing, components, screen patterns
4. **Project Overview** — High-level index and key decisions summary
5. **This file (AGENT_RULES.md)** — Condensed rules for quick reference

If this rules file contradicts the Data Model Specification, the specification wins.

---

*Last Updated: February 2026*
