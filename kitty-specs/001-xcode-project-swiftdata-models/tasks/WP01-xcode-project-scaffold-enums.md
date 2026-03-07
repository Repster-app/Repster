---
work_package_id: "WP01"
title: "Xcode Project Scaffold + Enums"
lane: "done"
dependencies: []
subtasks: ["T001", "T002", "T003", "T004", "T005", "T006", "T007", "T008", "T009", "T010", "T011"]
agent: "claude-opus"
shell_pid: "52508"
reviewed_by: "Magnus Espensen"
review_status: "approved"
history:
  - date: "2026-02-19"
    action: "created"
    by: "spec-kitty.tasks"
---

# WP01: Xcode Project Scaffold + Enums

**Implementation command**: `spec-kitty implement WP01`

## Objective

Create the Reppo Xcode project targeting iOS 17+ iPhone with SwiftUI lifecycle, establish the complete directory structure per AGENT_RULES Section 2, and implement all 9 enum types from specdoc Appendix A. This is the foundation that every subsequent work package depends on.

## Context

- **App Name**: Reppo
- **Bundle ID**: com.magnusespensen.Reppo
- **Target**: iOS 17.0+, iPhone only
- **Lifecycle**: SwiftUI (@main App struct)
- **No third-party dependencies**
- **Dark mode only** (no UI in this feature, but set appearance if possible)
- All enums conform to `String, Codable, CaseIterable`
- Enums are used by SwiftData @Model classes (WP02), so must be String raw-value types

## Reference Documents

- `kitty-specs/001-xcode-project-swiftdata-models/plan.md` - Project structure, enum definitions
- `kitty-specs/001-xcode-project-swiftdata-models/spec.md` - Acceptance scenarios
- `.kittify/memory/constitution.md` - Architecture and file organization rules

---

## Subtasks

### T001: Create Xcode Project "Reppo"

**Purpose**: Establish the iOS app project with correct target settings.

**Steps**:
1. Create a new Xcode project named "Reppo" with SwiftUI App lifecycle
2. Configure the following target settings:
   - **Bundle Identifier**: `com.magnusespensen.Reppo`
   - **Deployment Target**: iOS 17.0
   - **Supported Destinations**: iPhone only (remove iPad)
   - **Swift Language Version**: Latest stable (Swift 5.9+)
   - **Supported Interface Orientations**: Portrait (primary), Landscape Left/Right (optional)
3. The project must have a `.xcodeproj` (or Swift Package if more appropriate) that can be opened and built in Xcode 16+
4. Remove any default ContentView or boilerplate - we create our own in WP03

**Note on project creation approach**: Since we're creating from CLI, the recommended approach is:
- Create directory `Reppo/` at the project root
- Use `swift package init --type executable` OR create the Xcode project structure manually
- If using SPM, configure Package.swift for iOS 17 target with SwiftUI and SwiftData dependencies
- If creating .xcodeproj manually, ensure all source files are properly referenced

**Files**:
- `Reppo/` directory (project root for iOS app)
- `Reppo.xcodeproj/` or `Reppo/Package.swift`

**Validation**:
- [ ] Project opens in Xcode without errors
- [ ] Deployment target shows iOS 17.0
- [ ] Device target is iPhone only

---

### T002: Create Full Directory Scaffold

**Purpose**: Establish the file organization per AGENT_RULES Section 2 and the plan's project structure.

**Steps**:
1. Create the following directory tree under `Reppo/`:

```
Reppo/
  App/
  Features/
    Workout/
      Views/
      ViewModels/
    Exercise/
      Views/
      ViewModels/
    History/
      Views/
      ViewModels/
    Programs/
      Views/
      ViewModels/
    Settings/
      Views/
      ViewModels/
  Core/
    Services/
    Repositories/
    Extensions/
  Data/
    Models/
    Enums/
    Persistence/
  Resources/
    Assets.xcassets/
```

2. For empty directories that need to exist in git, add a `.gitkeep` file OR a brief placeholder Swift file (e.g., empty file with just a comment like `// Placeholder - implemented in feature 00X`)
3. Ensure all directories are referenced in the Xcode project so they appear in the navigator

**Files**:
- All directories listed above
- Placeholder files as needed for git tracking

**Validation**:
- [ ] All directories exist and are non-empty (gitkeep or placeholder)
- [ ] Directory structure matches plan.md project structure section exactly
- [ ] Xcode navigator shows the folder hierarchy

---

### T003: Create TrackingType Enum

**Purpose**: Define exercise tracking modes per specdoc Appendix A.

**File**: `Reppo/Data/Enums/TrackingType.swift`

**Implementation**:
```swift
import Foundation

enum TrackingType: String, Codable, CaseIterable {
    case weightReps
    case duration
    case weightDistance
    case weightRepsDuration
    case custom
}
```

**Validation**:
- [ ] 5 cases exactly as listed
- [ ] Conforms to String, Codable, CaseIterable

---

### T004: Create SetType Enum

**Purpose**: Define all set classifications per specdoc Appendix A.

**File**: `Reppo/Data/Enums/SetType.swift`

**Implementation**:
```swift
import Foundation

enum SetType: String, Codable, CaseIterable {
    case warmup
    case working
    case partial
    case dropset
    case restpause
    case cluster
    case myo
    case amrap
    case backoff
    case failure
    case tempo
    case isometric
    case eccentric
}
```

**Validation**:
- [ ] All 13 cases exactly as listed
- [ ] Conforms to String, Codable, CaseIterable

---

### T005: Create EquipmentType Enum

**Purpose**: Define equipment categories per specdoc Appendix A.

**File**: `Reppo/Data/Enums/EquipmentType.swift`

**Implementation**:
```swift
import Foundation

enum EquipmentType: String, Codable, CaseIterable {
    case barbell
    case dumbbell
    case machinePlate
    case machinePin
    case bodyweight
    case sled
    case cable
    case kettlebell
    case band
    case other
}
```

**Validation**:
- [ ] All 10 cases exactly as listed
- [ ] Conforms to String, Codable, CaseIterable

---

### T006: Create RecordType Enum

**Purpose**: Define PR record types per specdoc Appendix A.

**File**: `Reppo/Data/Enums/RecordType.swift`

**Implementation**:
```swift
import Foundation

enum RecordType: String, Codable, CaseIterable {
    case repMax
    case e1RM
    case maxVolume
}
```

**Validation**:
- [ ] 3 cases: repMax, e1RM, maxVolume
- [ ] Conforms to String, Codable, CaseIterable

---

### T007: Create CachedPRStatus Enum

**Purpose**: Define PR badge display states per specdoc Appendix A.

**File**: `Reppo/Data/Enums/CachedPRStatus.swift`

**Implementation**:
```swift
import Foundation

enum CachedPRStatus: String, Codable, CaseIterable {
    case current
    case matched
    case previous
}
```

**Validation**:
- [ ] 3 cases: current, matched, previous
- [ ] Conforms to String, Codable, CaseIterable

---

### T008: Create Side Enum

**Purpose**: Define unilateral exercise sides per specdoc Appendix A.

**File**: `Reppo/Data/Enums/Side.swift`

**Implementation**:
```swift
import Foundation

enum Side: String, Codable, CaseIterable {
    case left
    case right
    case both
}
```

**Validation**:
- [ ] 3 cases: left, right, both
- [ ] Conforms to String, Codable, CaseIterable

---

### T009: Create MovementPattern Enum

**Purpose**: Define exercise movement classifications per specdoc Appendix A.

**File**: `Reppo/Data/Enums/MovementPattern.swift`

**Implementation**:
```swift
import Foundation

enum MovementPattern: String, Codable, CaseIterable {
    case hinge
    case squat
    case press
    case pull
    case carry
    case rotation
    case other
}
```

**Validation**:
- [ ] 7 cases exactly as listed
- [ ] Conforms to String, Codable, CaseIterable

---

### T010: Create UnitPreference Enum

**Purpose**: Define user unit display preference per specdoc Appendix A.

**File**: `Reppo/Data/Enums/UnitPreference.swift`

**Implementation**:
```swift
import Foundation

enum UnitPreference: String, Codable, CaseIterable {
    case metric
    case imperial
}
```

**Validation**:
- [ ] 2 cases: metric, imperial
- [ ] Conforms to String, Codable, CaseIterable

---

### T011: Create WorkoutStatus Enum

**Purpose**: Define workout lifecycle states per AGENT_RULES Section 7.3.

**File**: `Reppo/Data/Enums/WorkoutStatus.swift`

**Implementation**:
```swift
import Foundation

enum WorkoutStatus: String, Codable, CaseIterable {
    case inProgress
    case completed
}
```

**Validation**:
- [ ] 2 cases: inProgress, completed
- [ ] Conforms to String, Codable, CaseIterable

---

## Definition of Done

- [ ] Xcode project "Reppo" exists with correct bundle ID and target settings
- [ ] All directories per AGENT_RULES Section 2 file organization exist
- [ ] All 9 enum files exist in `Reppo/Data/Enums/`
- [ ] Every enum conforms to `String, Codable, CaseIterable`
- [ ] Every enum has the exact cases from the plan (no extras, no missing)
- [ ] Project compiles with zero errors

## Risks

| Risk | Mitigation |
|------|-----------|
| Xcode project creation from CLI is tricky | Use swift package init or manual project structure; verify in Xcode |
| Bundle ID typo | Copy exact value: com.magnusespensen.Reppo |
| Missing enum case | Cross-reference each enum against plan.md Phase 1 enum table |

## Reviewer Guidance

1. Verify bundle ID is exactly `com.magnusespensen.Reppo`
2. Verify deployment target is iOS 17.0 (not higher, not lower)
3. Verify iPhone only (no iPad)
4. Count enum cases: TrackingType(5), SetType(13), EquipmentType(10), RecordType(3), CachedPRStatus(3), Side(3), MovementPattern(7), UnitPreference(2), WorkoutStatus(2)
5. Verify all enums use `String` raw values (required for SwiftData storage)
6. Verify directory structure matches plan.md project structure exactly

## Activity Log

- 2026-02-20T17:09:32Z – claude-opus – shell_pid=49888 – lane=doing – Started implementation via workflow command
- 2026-02-20T17:15:55Z – claude-opus – shell_pid=49888 – lane=for_review – Ready for review: Xcode project scaffold with 9 enums, all compiling with zero errors/warnings. Bundle ID com.magnusespensen.Reppo, iOS 17.0+, iPhone only, dark mode, SwiftUI lifecycle. Directory structure matches AGENT_RULES Section 2.
- 2026-02-20T17:16:38Z – claude-opus – shell_pid=52508 – lane=doing – Started review via workflow command
- 2026-02-20T17:22:19Z – claude-opus – shell_pid=52508 – lane=done – Review passed: All 9 enum files correct (cases, conformances, String raw values match plan exactly). Project settings verified: bundle ID com.magnusespensen.Reppo, iOS 17.0, TARGETED_DEVICE_FAMILY=1 (iPhone only), dark mode enforced, no Mac Catalyst. Directory structure matches AGENT_RULES Section 2 completely. All files referenced in Xcode build phases. Clean build succeeds with zero errors and zero source warnings.
