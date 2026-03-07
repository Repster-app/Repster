# Research: 010 Settings + Onboarding

**Feature**: Settings + Onboarding
**Date**: 2026-02-28
**Status**: Complete

## Research Questions

### RQ-1: Onboarding First-Launch Persistence

**Question**: How should first-launch state be persisted and how should the root view conditionally present onboarding vs the main app?

**Decision**: Use `@AppStorage("hasCompletedOnboarding")` in `ReppoApp.swift` to gate root view presentation. Onboarding is shown as a full-screen overlay when the flag is `false`. On completion, set the flag to `true` and the main `ContentView` appears.

**Rationale**:
- `@AppStorage` wraps `UserDefaults`, which is the idiomatic SwiftUI mechanism for lightweight boolean flags that control app-level behavior.
- This flag is a UI concern (whether to show onboarding), not a domain model concern. Storing it on `HealthProfile` would couple a SwiftData query to the very first frame of app launch, adding latency before anything renders.
- `UserDefaults` is available synchronously at launch. `HealthProfile` requires an async SwiftData fetch, which means the app body would need to handle a loading state before deciding what to show.
- The `@AppStorage` property can be read directly in the `ReppoApp.body` computed property without `Task` or `.task {}`.

**Implementation approach**:
```swift
// ReppoApp.swift
@main
struct ReppoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    // ... existing modelContainer, repositories, services ...

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingFlowView(onComplete: {
                    hasCompletedOnboarding = true
                })
            }
        }
        .modelContainer(modelContainer)
        .environment(repositories)
        .environment(services)
    }
}
```

The `if/else` approach is preferred over `.fullScreenCover` or `.sheet` because:
- It provides a clean, instant transition with no animation glitch on first launch.
- It avoids a brief flash of `ContentView` before the cover appears.
- The `onComplete` closure is a simple callback -- no Binding threading needed.

**Alternatives considered**:
- `HealthProfile.hasCompletedOnboarding` field: Rejected. Requires async SwiftData fetch before the first view renders. Adds a domain model field for a purely UI concern. Also, `HealthProfile` may not exist yet on first launch, creating a chicken-and-egg problem.
- `.fullScreenCover(isPresented:)` over `ContentView`: Rejected. Can cause a brief flash of the underlying view before the cover animates in. Also, `ContentView` would begin its `.task` lifecycle (checking for active workouts) before onboarding completes.
- Environment-injected `OnboardingState` object: Over-engineered for a single boolean. `@AppStorage` is simpler and sufficient.

---

### RQ-2: E1RM Formula Options

**Question**: Which e1RM formulas should be available in the picker, and what plain-English descriptions should accompany them (per AGENT_RULES S11)?

**Decision**: Include three formulas: **Epley** (default), **Brzycki**, and **Lombardi**. Each gets a one-sentence plain-English description in the picker UI.

**Rationale**:
- These are the three most widely recognized e1RM estimation formulas in strength training literature.
- Epley (`weight * (1 + reps / 30)`) is the industry standard, used by most tracking apps and research papers. It is already the codebase default (`e1RMFormula: String = "epley"`).
- Brzycki (`weight * 36 / (37 - reps)`) is the most common alternative, preferred by some powerlifters for its slightly more conservative estimates at higher rep ranges.
- Lombardi (`weight * reps^0.10`) is a simpler power-law model that some users prefer for its behavior at very high reps.
- Three options keep the picker simple. More formulas (Wathen, Mayhew, O'Conner) add noise without meaningful user value for v1.

**Plain-English descriptions** (per AGENT_RULES S11):

| Formula | String Key | Description |
|---------|-----------|-------------|
| Epley | `"epley"` | "Most widely used. Accurate for moderate rep ranges (1-10 reps)." |
| Brzycki | `"brzycki"` | "Slightly more conservative. Preferred by some powerlifters." |
| Lombardi | `"lombardi"` | "Simple power formula. Consistent across all rep ranges." |

**Storage**: The `e1RMFormula` field on `HealthProfile` is already a `String`. The three keys (`"epley"`, `"brzycki"`, `"lombardi"`) are stored as raw string values. An enum with `rawValue: String` will be used for type safety in Swift code, but the stored value remains a plain string for forward compatibility.

```swift
enum E1RMFormula: String, CaseIterable, Identifiable {
    case epley
    case brzycki
    case lombardi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .epley: "Epley"
        case .brzycki: "Brzycki"
        case .lombardi: "Lombardi"
        }
    }

    var description: String {
        switch self {
        case .epley: "Most widely used. Accurate for moderate rep ranges (1-10 reps)."
        case .brzycki: "Slightly more conservative. Preferred by some powerlifters."
        case .lombardi: "Simple power formula. Consistent across all rep ranges."
        }
    }
}
```

**Edge case**: Changing the e1RM formula does NOT retroactively recompute existing `PerformanceRecord` values. Each `WorkoutSet` stores `e1RMFormulaVersion` at the time it was saved. Future sets use the new formula. The spec explicitly states this behavior (spec edge case: "e1RM formula change: future sets use new formula, existing sets keep their e1RMFormulaVersion").

**Alternatives considered**:
- Including more formulas (Wathen, Mayhew, O'Conner, Wathan, Adams): Rejected for v1. Diminishing returns. These can be added later without schema changes since the field is a String.
- Enum stored on HealthProfile instead of String: Rejected. The current `String` type provides forward compatibility -- new formulas can be added without a SwiftData migration.

---

### RQ-3: Settings Form Patterns in SwiftUI

**Question**: What is the best SwiftUI pattern for grouped settings with Form/List, section headers, toggles, and navigation links to sub-screens?

**Decision**: Use SwiftUI `Form` with `Section` headers for the main settings screen. Toggles use `Toggle` directly in `Form` rows. Sub-screens (Units picker, e1RM formula picker) use `.sheet` presentation. Navigation to deeper screens (Bodyweight Log, Rebuild Stats) use `NavigationLink` within the `Form`.

**Rationale**:
- `Form` automatically provides the grouped inset list style expected for iOS settings screens, with proper dark mode styling.
- `Section("HEADER")` provides the uppercase section header styling that matches the screen_tree layout (GENERAL, WORKOUT PREFERENCES, DATA, BODY, ABOUT).
- Per screen_tree Section 5, Units and e1RM Formula open as sheets (`[sheet]` annotation), while deeper screens like Bodyweight Log and Rebuild Stats are pushed as full screens.
- This matches the existing app pattern where sheets are used for focused selection tasks and navigation pushes for content-heavy screens.

**Implementation structure**:
```swift
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("GENERAL") {
                // Units row -> sheet
                Button { showUnitsSheet = true } label: {
                    HStack {
                        Text("Units")
                        Spacer()
                        Text(viewModel.unitPreference.displayName)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                // e1RM Formula row -> sheet
                Button { showFormulaSheet = true } label: {
                    HStack {
                        Text("e1RM Formula")
                        Spacer()
                        Text(viewModel.formulaDisplayName)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            Section("WORKOUT PREFERENCES") {
                Toggle("Include Warmups in Volume", isOn: $viewModel.includeWarmupsInVolume)
                Toggle("Include Warmups in PRs", isOn: $viewModel.includeWarmupsInPRs)
                // Default Rest Time -> picker
            }

            Section("DATA") {
                Button("Import Data (CSV)") { /* stub for feature 011 */ }
                Button("Export Data (CSV)") { /* stub for feature 011 */ }
                NavigationLink("Rebuild Stats") { RebuildStatsView(...) }
            }

            Section("BODY") {
                NavigationLink("Bodyweight Log") { BodyweightLogView(...) }
            }

            Section("ABOUT") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(Color.textSecondary)
                }
                Button("Send Feedback") { sendFeedback() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
    }
}
```

**Dark mode styling**: Use `.scrollContentBackground(.hidden)` on the `Form` and apply `.background(Color.bg)` to replace the system background. Section headers and row backgrounds will use the app's design tokens (`Color.bgCard`, `Color.textPrimary`, etc.) consistent with the rest of the app.

**Alternatives considered**:
- `List` with manual grouping: Rejected. `Form` provides native grouped styling out of the box. `List` would require manual section styling.
- Custom `VStack`/`ScrollView` layout: Rejected. Over-engineering. `Form` is the standard SwiftUI settings pattern and provides proper accessibility, keyboard avoidance, and scroll behavior.
- All sub-screens as navigation pushes: Rejected. screen_tree explicitly marks Units and e1RM as `[sheet]` presentations.

---

### RQ-4: HealthProfile Field Additions

**Question**: Should `defaultRestTimeSeconds: Int?` be added to `HealthProfile`? Should `hasCompletedOnboarding` be stored on `HealthProfile` or in `@AppStorage`?

**Decision**: Add `defaultRestTimeSeconds: Int? = nil` to `HealthProfile`. Keep `hasCompletedOnboarding` in `@AppStorage` (see RQ-1).

**Rationale for defaultRestTimeSeconds on HealthProfile**:
- This is a user preference that applies globally as a fallback when an exercise does not have its own `defaultRestTime` set.
- It belongs alongside the other user preferences (`unitPreference`, `includeWarmupsInVolume`, etc.) on the same single-row model.
- `Int?` with `nil` default means "no global default" -- the rest timer will use the exercise-specific `defaultRestTime`, or no timer if neither is set.
- The existing `HealthProfileRepository.fetchOrCreate()` will supply `nil` for this field, preserving backward compatibility with existing data.

**Model change**:
```swift
@Model
final class HealthProfile {
    var id: UUID
    var unitPreference: UnitPreference
    var includeWarmupsInVolume: Bool
    var includeWarmupsInPRs: Bool
    var e1RMFormula: String
    var defaultRestTimeSeconds: Int?  // NEW: global fallback rest time
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        unitPreference: UnitPreference = .metric,
        includeWarmupsInVolume: Bool = false,
        includeWarmupsInPRs: Bool = false,
        e1RMFormula: String = "epley",
        defaultRestTimeSeconds: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) { ... }
}
```

**Rest time picker values**: Offer preset intervals: 30s, 60s, 90s, 120s, 150s, 180s, 240s, 300s. Display using `UnitConversion.formatDuration()` which already handles the "1m 30s" / "2m" / "45s" formatting.

**Rationale for hasCompletedOnboarding in @AppStorage**:
- See RQ-1. It is a UI gating concern, not a domain preference. `@AppStorage` is synchronous, avoids async SwiftData fetch on cold launch, and decouples onboarding gating from the model layer.

**Alternatives considered**:
- `defaultRestTimeSeconds` in `@AppStorage`: Rejected. It is a user training preference that should live alongside other preferences in the data model. `@AppStorage` should be reserved for UI-only state like `hasCompletedOnboarding`.
- `defaultRestTimeSeconds: Int = 90`: Rejected. A non-nil default would impose a rest timer on all users immediately. `nil` means opt-in.
- `hasCompletedOnboarding` on `HealthProfile`: Rejected per RQ-1 rationale.

---

### RQ-5: Bodyweight Trend Chart (Settings > BODY)

**Question**: How should the bodyweight trend chart be implemented in the Bodyweight Log screen?

**Decision**: Use Swift Charts with `LineMark` for the trend line and `PointMark` for individual entries. Data sourced from `BodyweightService.fetchAllEntries()`. The chart shows all entries with a connecting line, no smoothing or moving average for v1.

**Rationale**:
- Swift Charts is an approved dependency (AGENT_RULES S12) and is already used extensively in feature 009 (Charts Tab).
- `LineMark` + `PointMark` composited on the same `Chart` is the standard pattern for a trend-with-data-points visualization.
- Bodyweight entries are sparse (typically 1 per day at most, often less). Even a year of daily entries is ~365 points, well within Swift Charts performance limits.
- No moving average or smoothing for v1 -- the raw data line is sufficient. Users can visually identify trends from the line shape.

**Implementation approach**:
```swift
struct BodyweightChartView: View {
    let entries: [BodyweightEntry]
    let unitPreference: UnitPreference

    var body: some View {
        Chart(entries, id: \.id) { entry in
            let weight = unitPreference == .imperial
                ? UnitConversion.kgToLbs(entry.bodyweightKg)
                : entry.bodyweightKg

            LineMark(
                x: .value("Date", entry.date),
                y: .value("Weight", weight)
            )
            .foregroundStyle(Color.accent)

            PointMark(
                x: .value("Date", entry.date),
                y: .value("Weight", weight)
            )
            .foregroundStyle(Color.accent)
            .symbolSize(30)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
    }
}
```

**Key details**:
- `chartYScale(domain: .automatic(includesZero: false))`: Bodyweight charts should NOT start at zero. The Y axis should tightly bound the data range to show meaningful variation.
- Unit conversion happens at the view layer. Stored values are always in kg. When `unitPreference == .imperial`, convert via `UnitConversion.kgToLbs()` for display.
- Weight axis label shows "kg" or "lbs" based on unit preference.
- Chart height: Fixed at ~200pt to fit above the entry list without dominating the screen.

**Empty state**: When no bodyweight entries exist, show a motivational message: "Log your bodyweight to track trends and improve effectiveWeight accuracy for bodyweight exercises." with a prominent [+Add] button.

**Entry list below chart**: Chronological list (newest first) of all entries, each showing date and weight in the user's preferred unit. Swipe-to-delete for removing entries.

**Alternatives considered**:
- Moving average / smoothed trend line: Deferred to v1.1. Adds complexity (window size selection, edge behavior) without essential user value for launch.
- Separate chart screen: Rejected. The screen_tree shows the chart and entries on the same screen ("trend chart, chronological entries, [+Add] entry").
- Bar chart per day: Rejected. Line + point is the standard bodyweight visualization. Bar chart would be misleading for sparse data.

---

### RQ-6: Rebuild UI Patterns

**Question**: How should the UI handle progress during `rebuildAll()` operations?

**Decision**: Show a confirmation alert before starting, then a modal `ProgressView` overlay during the rebuild, then a completion status message. The user cannot interact with the app during a rebuild.

**Rationale**:
- Rebuilds are destructive-in-the-sense-of-replacing operations. A confirmation alert ("This will recompute all PRs/Stats from raw data. Continue?") prevents accidental triggers.
- `ProgressView` with `.progressViewStyle(.circular)` in a centered overlay provides clear feedback that a long-running operation is in progress.
- The modal overlay (blocking interaction) prevents the user from navigating away or making changes while data is being recomputed, which could cause inconsistencies.
- Per SC-003, rebuild for 12,000+ sets should complete within 30 seconds. An indeterminate spinner is acceptable for this duration.

**Implementation approach**:
```swift
struct RebuildStatsView: View {
    @State private var viewModel: RebuildStatsViewModel

    var body: some View {
        List {
            Section {
                Text("Rebuild recomputes all stats and PRs from your raw workout data. Use this after importing data or if you notice any discrepancies.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Button("Rebuild PRs") { viewModel.confirmRebuildPRs() }
                Button("Rebuild Stats") { viewModel.confirmRebuildStats() }
                Button("Rebuild All") { viewModel.confirmRebuildAll() }
            }
        }
        .overlay {
            if viewModel.isRebuilding {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(Color.accent)
                        Text(viewModel.rebuildStatusMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(32)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 16))
                }
                .ignoresSafeArea()
            }
        }
        .alert("Confirm Rebuild", isPresented: $viewModel.showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Rebuild", role: .destructive) { viewModel.executeRebuild() }
        } message: {
            Text(viewModel.confirmationMessage)
        }
        .alert("Rebuild Complete", isPresented: $viewModel.showCompletion) {
            Button("OK") {}
        } message: {
            Text(viewModel.completionMessage)
        }
    }
}
```

**Rebuild flow**:
1. User taps a rebuild button.
2. Confirmation alert appears with a description of what will happen.
3. On confirm, `isRebuilding = true` shows the progress overlay.
4. ViewModel calls `prService.rebuildAll()` and/or `statsService.rebuildAll()`.
5. On completion, `isRebuilding = false`, `showCompletion = true`.
6. Completion alert shows "Rebuild complete. All PRs/Stats have been recomputed."

**Error handling**: If rebuild throws, show an error alert with the localized description. The user can retry.

**Alternatives considered**:
- Determinate progress bar: Rejected. Neither `PRService.rebuildAll()` nor `StatsService.rebuildAll()` currently report progress incrementally. Adding progress callbacks would complicate the service API for a feature used rarely. An indeterminate spinner is sufficient for a sub-30-second operation.
- Background rebuild with banner notification: Rejected. Rebuilds are rare maintenance operations. Blocking the UI ensures data consistency and is acceptable for the expected duration.
- Inline progress in the list row: Rejected. Less visible than a modal overlay. Users might navigate away mid-rebuild.

---

### RQ-7: Unit Propagation After Preference Change

**Question**: When the user switches unit preference (kg to lbs or vice versa), how do all displayed weights update across the app?

**Decision**: All weight display is computed at the view layer by reading `HealthProfile.unitPreference` and converting via `UnitConversion`. When the SettingsViewModel saves the updated preference to `HealthProfile`, other screens pick up the change on their next data load. No notification or observation mechanism is needed for v1.

**Rationale**:
- All weights are stored in kg (the canonical unit). Display conversion happens in ViewModels or Views by reading the current `unitPreference` from `HealthProfile`.
- ViewModels fetch `HealthProfile` from the repository at load time. When the user returns to another tab after changing units, the ViewModel reloads and picks up the new preference.
- SwiftData `@Model` objects are observed by SwiftUI when used with `@Query` or when the model context changes. However, since ViewModels use repositories (not `@Query`), the propagation relies on ViewModel reload cycles.
- For the Settings tab itself, the ViewModel holds the `HealthProfile` reference and updates it directly. The UI reflects changes immediately via `@Observable`.

**Implementation details**:
1. `SettingsViewModel` fetches `HealthProfile` via `healthProfileRepo.fetchOrCreate()` on load.
2. When the user changes units, the ViewModel updates `profile.unitPreference` and calls `healthProfileRepo.save(profile)`.
3. Other ViewModels (ActiveWorkout, Calendar, Charts, ExerciseDetail) fetch `HealthProfile` in their load methods. On next appearance, they read the updated value.
4. The "Include Warmups in PRs" toggle is special: changing it triggers a confirmation alert, then `prService.rebuildAll()` (per FR-004 and spec acceptance scenario 6).
5. The "Include Warmups in Volume" toggle triggers `statsService.rebuildAll()` for consistency.

**Edge cases**:
- Active workout in progress: If the user changes units mid-workout, the ActiveWorkoutViewModel will not automatically reflect the change until the next set is loaded or the view reappears. This is acceptable for v1 -- unit changes mid-workout are an extreme edge case.
- Chart data: Charts fetch data in kg and convert for display. The ChartsDashboardViewModel fetches unit preference on load, so returning to Charts after a unit change will show the new units.

**Alternatives considered**:
- `NotificationCenter` broadcast on unit change: Rejected. Adds coupling and complexity. The natural ViewModel reload cycle is sufficient. Notification-based reactivity is hard to test and maintain.
- Shared `@Observable` singleton for `HealthProfile`: Rejected. The codebase uses repository-based data access, not shared in-memory singletons. A singleton would bypass the established architecture.
- `@Query` with `HealthProfile`: Rejected. ViewModels are `@Observable` classes that use repositories, not SwiftUI `@Query`. Mixing patterns would be inconsistent.

---

### RQ-8: Send Feedback Implementation

**Question**: How should "Send Feedback" be implemented in the About section?

**Decision**: Use a `mailto:` URL opened via `UIApplication.shared.open()`. This opens the user's default mail client with a pre-populated subject line and app version in the body.

**Rationale**:
- `mailto:` is the simplest approach that works on all iOS devices with a mail client configured.
- No third-party dependencies, no server infrastructure, no API keys.
- The subject line and body template help organize incoming feedback.
- This is a v1 feature -- more sophisticated feedback mechanisms (in-app form, crash reporter integration) can be added later.

**Implementation approach**:
```swift
private func sendFeedback() {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    let subject = "Reppo Feedback"
    let body = "\n\n---\nApp Version: \(version) (\(build))\niOS: \(UIDevice.current.systemVersion)"

    let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

    if let url = URL(string: "mailto:feedback@example.com?subject=\(encodedSubject)&body=\(encodedBody)") {
        UIApplication.shared.open(url)
    }
}
```

**Fallback**: If no mail client is configured, `UIApplication.shared.open()` will silently fail on iOS. For v1, this is acceptable. A future enhancement could check `UIApplication.shared.canOpenURL(mailtoURL)` and show an alert with the email address if no mail client is available.

**Version number display**: The About section also shows the app version. Use `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` for the version string and `Bundle.main.infoDictionary?["CFBundleVersion"]` for the build number. Display as "Version 1.0 (42)".

**Alternatives considered**:
- `MFMailComposeViewController` (MessageUI framework): Provides an in-app mail composer. However, it requires checking `canSendMail()` first, wrapping UIKit in `UIViewControllerRepresentable`, and adds complexity. The simple `mailto:` URL is sufficient for v1.
- In-app feedback form with backend: Over-engineered for v1. Requires server infrastructure and API endpoints.
- GitHub Issues link: Not user-facing. End users should not need a GitHub account.
