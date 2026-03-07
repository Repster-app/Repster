# Contract: ExerciseInfoProvider

**Type**: Internal helper (struct or enum with static methods)
**Location**: `Reppo/Features/Workout/ViewModels/ExerciseInfoProvider.swift`

## Purpose

Encapsulates all computation logic for the Exercise Info section. Accepts raw data from services and returns a fully-computed `ExerciseInfoData` value ready for view rendering.

## Public Interface

### Primary Method

```swift
static func compute(
    currentSets: [WorkoutSet],
    exerciseId: UUID,
    currentWorkoutId: UUID,
    trackingType: TrackingType,
    weightIncrement: Double?,
    setService: SetService,
    statsService: StatsService,
    healthProfileRepo: HealthProfileRepository
) async throws -> ExerciseInfoData
```

**Parameters**:
- `currentSets`: The in-memory sets for this exercise in the active workout (from `viewModel.currentSets`)
- `exerciseId`: The current exercise's UUID
- `currentWorkoutId`: Active workout's UUID (to exclude from "last workout" lookup)
- `trackingType`: Exercise's tracking type (determines card visibility)
- `weightIncrement`: Exercise's weight increment for rounding (optional)
- `setService`: For fetching historical exercise sets
- `statsService`: For fetching pre-computed ExerciseStats (fallback e1RM)
- `healthProfileRepo`: For reading e1RM formula preference and unit preference

**Returns**: `ExerciseInfoData` with all three card models populated (or nil where not applicable).

**Throws**: Only if service calls fail (network-free, so unlikely).

## Internal Computation Steps

### Step 1: Fetch Historical Data
```
allSets = setService.fetchSets(for: exerciseId, limit: nil)
historicalSets = allSets.filter { $0.workoutId != currentWorkoutId }
profile = healthProfileRepo.fetchOrCreate()
formula = E1RMFormula(rawValue: profile.e1RMFormula) ?? .epley
```

### Step 2: Compute E1RM Info (if weight-based tracking)
```
todayWorkingSets = currentSets.filter { $0.setType == .working && $0.hasData && $0.e1RM != nil }
bestTodaySet = todayWorkingSets.max(by: { ($0.e1RM ?? 0) < ($1.e1RM ?? 0) })
currentE1RM = bestTodaySet?.e1RM ?? statsService.fetchStats(exerciseId)?.bestE1RM

fourWeekTarget = Calendar.current.date(byAdding: .day, value: -28, to: Date())
historicalWindow = historicalSets.filter { $0.date between (target - 7d) and (target + 7d) }
historicalE1RM = historicalWindow.compactMap(\.e1RM).max() ?? nearestAvailable
delta = currentE1RM - historicalE1RM (via toGrams comparison)
```

### Step 3: Compute Last Workout Info
```
grouped = Dictionary(grouping: historicalSets) { $0.workoutId }
sortedGroups = grouped.sorted { $0.value.first!.date > $1.value.first!.date }
lastGroup = sortedGroups.first
topSets = lastGroup.sets
    .filter { $0.setType == .working && $0.hasData }
    .sorted { ($0.effectiveWeight ?? 0) > ($1.effectiveWeight ?? 0) }
    .prefix(2)
daysAgo = Calendar.current.dateComponents([.day], from: lastGroup.date, to: Date()).day
```

### Step 4: Compute Estimated Reps Info (if weight-based tracking)
```
latestWorkingSet = currentSets.last { $0.setType == .working && $0.hasData }
targetReps = latestWorkingSet?.reps ?? 8
bestE1RM = currentE1RM ?? statsService.fetchStats(exerciseId)?.bestE1RM
estimatedWeight = formula.reverseCalculate(e1RM: bestE1RM, reps: targetReps)
snappedWeight = snap(estimatedWeight, to: weightIncrement ?? 2.5)
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| No completed sets in current workout | e1RM falls back to `ExerciseStats.bestE1RM` |
| No historical data at all | `historicalE1RM = nil`, `lastWorkoutInfo = nil`, `estimatedRepsInfo = nil` |
| Duration-based exercise | `e1RMInfo = nil`, `estimatedRepsInfo = nil` |
| Service call failure | Propagate error to ViewModel; ViewModel shows empty state |

## Performance Budget

- Single `fetchSets` call: ~50-200ms for exercises with extensive history
- In-memory computation: < 10ms
- Total: < 500ms (SC-001 target)
