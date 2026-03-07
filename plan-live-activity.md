# Feature Plan: Live Activity & Dynamic Island

## Why

During a workout the phone is usually locked or in a pocket. Users must unlock and re-open the app just to check the rest timer or see which exercise/set is next. A Live Activity on the Lock Screen (and Dynamic Island on iPhone 14 Pro+) removes that friction entirely.

## Compatibility

| Requirement | Status |
|---|---|
| iOS 16.1+ (ActivityKit) | App targets iOS 17 |
| iPhone 14 Pro+ (Dynamic Island) | Supported, graceful fallback on older phones |
| Existing extension targets | None yet — must create one |

---

## What It Should Show

### Lock Screen (Expanded)
```
┌──────────────────────────────────────────┐
│  Reppo                        01:23:45   │  ← workout elapsed time
│                                          │
│  Bench Press           Set 3/5 (working) │  ← exercise + set progress
│                                          │
│     ██████████░░░░░  1:12 remaining      │  ← rest timer bar + countdown
└──────────────────────────────────────────┘
```

### Dynamic Island (Compact)
- **Leading:** App icon
- **Trailing:** Rest timer countdown (`1:12`) or set indicator (`3/5`)

### Dynamic Island (Expanded — long press)
- Same as Lock Screen layout
- Tap opens the app to the active workout

### When Idle (no rest timer)
```
┌──────────────────────────────────────────┐
│  Reppo                        01:23:45   │
│                                          │
│  Bench Press           Set 3/5 (working) │
│           Ready for next set             │
└──────────────────────────────────────────┘
```

---

## Data Flow

### What already exists

| Data | Source | Location |
|---|---|---|
| Rest timer state | `RestTimerState` enum | `ActiveWorkoutViewModel` line ~35 |
| Elapsed time | `elapsedTime: TimeInterval` | `ActiveWorkoutViewModel` line ~99 |
| Current exercise name | `currentExercise?.name` | `ActiveWorkoutViewModel` computed |
| Set progress | `currentSets`, `setsByExercise` | `ActiveWorkoutViewModel` |
| Workout title | `workout?.displayTitle` | Auto-generated (Morning/Afternoon/Evening Workout) |
| Background timer recovery | `recalculateTimerAfterBackground()` | `ActiveWorkoutViewModel` line ~596 |
| Scene phase monitoring | `@Environment(\.scenePhase)` | `ActiveWorkoutView` line ~102 |

All the data is already available and computed. No new business logic needed — just piping existing state into ActivityKit.

---

## Architecture

### New Files

```
Reppo/
├── Features/Workout/
│   └── Services/
│       └── LiveActivityManager.swift          ← start/update/end activity lifecycle
│
WorkoutLiveActivity/                           ← NEW Widget Extension target
├── WorkoutLiveActivityBundle.swift
├── WorkoutLiveActivityView.swift              ← Lock Screen + Dynamic Island UI
└── SharedModels/
    └── WorkoutActivityAttributes.swift        ← Codable model (shared with main app)
```

### Shared Model (ActivityKit Attributes)

```swift
import ActivityKit

struct WorkoutActivityAttributes: ActivityAttributes {
    // Static context (set once when activity starts)
    let workoutTitle: String
    let workoutStartTime: Date

    struct ContentState: Codable, Hashable {
        // Dynamic state (updated throughout workout)
        var exerciseName: String
        var currentSetNumber: Int
        var totalSets: Int
        var setType: String               // "working" / "warmup" / "deload"
        var restTimerRemaining: Int        // 0 = no timer active
        var restTimerTotal: Int
        var elapsedSeconds: Int
    }
}
```

> This struct must live in a shared framework or be duplicated in both the main target and the widget extension target.

### LiveActivityManager

Injected into `ActiveWorkoutViewModel` via `ServiceContainer`. Responsibilities:

| Method | When Called | What It Does |
|---|---|---|
| `startActivity(workout:)` | Workout begins (`loadActiveWorkout()`) | Requests a new Live Activity |
| `updateActivity(state:)` | Timer tick, set complete, exercise switch | Pushes ContentState update |
| `endActivity()` | Workout finished or discarded | Ends the Live Activity |

### Integration Points in ActiveWorkoutViewModel

```
loadActiveWorkout()      → liveActivityManager.startActivity(...)
completeSet()            → liveActivityManager.updateActivity(...)    // set progress changed
uncompleteSet()          → liveActivityManager.updateActivity(...)
timerTick()              → liveActivityManager.updateActivity(...)    // rest timer countdown
startRestTimer()         → liveActivityManager.updateActivity(...)    // timer started
dismissTimer()           → liveActivityManager.updateActivity(...)    // timer dismissed
selectExerciseAtIndex()  → liveActivityManager.updateActivity(...)    // exercise switched
finishWorkout()          → liveActivityManager.endActivity()
discardWorkout()         → liveActivityManager.endActivity()
```

---

## Implementation Steps

### Phase 1: Extension Setup
1. Create `WorkoutLiveActivity` Widget Extension target in Xcode
2. Add ActivityKit capability to both main app and extension
3. Update entitlements: add `com.apple.developer.activitykit` key
4. Create `WorkoutActivityAttributes.swift` in shared location

### Phase 2: Manager Service
5. Create `LiveActivityManager.swift` with start/update/end methods
6. Add to `ServiceContainer`
7. Inject into `ActiveWorkoutViewModel`

### Phase 3: Wire Up State
8. Call `startActivity` when workout loads
9. Call `updateActivity` from all state-changing methods (see table above)
10. Call `endActivity` on finish/discard
11. Handle app termination gracefully (ActivityKit persists activities)

### Phase 4: UI
12. Design Lock Screen expanded view (timer bar, exercise name, set count)
13. Design Dynamic Island compact view (timer or set indicator)
14. Design Dynamic Island expanded view (full layout)
15. Style to match app design system (colors, fonts)

### Phase 5: Polish
16. Handle edge cases: app killed mid-workout, activity expiry (8h max)
17. Add haptic feedback when rest timer finishes (via push notification from activity)
18. Test on older iPhones (no Dynamic Island — Lock Screen only)

---

## Watch Out For

| Risk | Mitigation |
|---|---|
| Activities auto-expire after 8h | Re-request if workout exceeds 8h (rare) |
| Extension has limited memory | Keep ContentState lightweight (no images, small data) |
| Timer drift in background | Already handled by `recalculateTimerAfterBackground()` |
| Multiple workouts edge case | Only one active workout possible in current design |
| Shared model divergence | Put attributes in a shared Swift package or copy carefully |
| Simulator limitations | Live Activities work in simulator but Dynamic Island needs device |

---

## Testing

| # | Test | Expected |
|---|------|----------|
| 1 | Start workout → lock phone | Live Activity appears on Lock Screen |
| 2 | Complete set → rest timer starts | Timer countdown visible on Lock Screen |
| 3 | Timer finishes | Activity updates to "Ready for next set" |
| 4 | Switch exercise | Exercise name and set count update |
| 5 | Finish workout | Activity dismissed |
| 6 | Force-quit app during workout | Activity persists (stale state is OK) |
| 7 | iPhone 14 Pro+: workout active | Dynamic Island shows compact timer |
| 8 | Long-press Dynamic Island | Expanded view with full workout info |
| 9 | Tap activity | Opens app to active workout |
