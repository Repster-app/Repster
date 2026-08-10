// HealthKitServiceProtocol.swift
// Contract for mirroring finished workouts into Apple Health.
// Spec: HEALTHKIT_INTEGRATION_EXPLORATION.md (direction A — write only)

import Foundation

/// Outcome of an authorization request. HealthKit deliberately never reveals
/// read authorization, but Repster is write-only so `authorized` here is truthful.
enum HealthKitAuthorizationResult: Sendable, Equatable {
    /// The user granted write access to workouts.
    case authorized
    /// The user explicitly declined, or has previously declined.
    case denied
    /// HealthKit is not available on this device (e.g. iPad without Health, simulator quirks).
    case unavailable
    /// The request itself failed. Carries a description for display.
    case failed(String)
}

/// Everything needed to write one `HKWorkout`, as a plain value type.
///
/// Deliberately NOT a `Workout` model. Passing live SwiftData models across an
/// actor boundary is the crash class that shipped in 1.3 (`EXC_BAD_ACCESS`).
/// The caller reads the fields it needs inside its own actor and hands over a value.
struct HealthKitWorkoutPayload: Sendable, Equatable {
    let start: Date
    let end: Date
    /// Bodyweight closest to the workout date, used for the MET energy estimate.
    /// `nil` means no bodyweight has ever been logged — the workout is still written,
    /// just without an energy sample. See `SetService.computeEffectiveWeight` for the
    /// same degrade-silently precedent.
    let bodyweightKg: Double?

    init(start: Date, end: Date, bodyweightKg: Double?) {
        self.start = start
        self.end = end
        self.bodyweightKg = bodyweightKg
    }
}

/// HealthKitService mirrors finished Repster workouts into Apple Health.
///
/// Responsibilities:
/// - Own the `HKHealthStore` and the write-authorization request
/// - Write a finished workout as an `HKWorkout` (`.traditionalStrengthTraining`)
/// - Optionally attach a MET-based active-energy estimate
/// - Delete a previously written workout
///
/// HealthKitService does NOT:
/// - Read anything from Health. Repster requests share permission only.
/// - Throw into the workout finish path. Every method degrades to a no-op or `nil`.
/// - Decide *when* to sync. That's the caller's job (`WorkoutService.finishWorkout`).
protocol HealthKitServiceProtocol: Sendable {

    /// Whether HealthKit exists on this device at all. `false` on unsupported hardware.
    ///
    /// These three are synchronous so the Settings UI can read them in a view body.
    /// The actor implementation satisfies them with `nonisolated` members backed by
    /// `UserDefaults`, which is thread-safe.
    var isAvailable: Bool { get }

    /// Whether the user has turned the integration on in Settings.
    /// Device-local by design — see `HealthKitPreferences`.
    var isEnabled: Bool { get }

    /// Whether to attach the MET-based energy estimate. Defaults to `false`.
    var writesEstimatedEnergy: Bool { get }

    /// Request write authorization for workouts and active energy.
    ///
    /// Call this ONLY from an explicit user action (the Settings toggle) — never at
    /// launch or during onboarding. Requests both types in one prompt so enabling the
    /// energy estimate later doesn't trigger a second permission sheet.
    func requestAuthorization() async -> HealthKitAuthorizationResult

    /// Write a finished workout to Health.
    ///
    /// - Returns: The HealthKit object UUID to persist on the `Workout`, or `nil` if the
    ///   integration is off, unauthorized, unavailable, or the write failed. Never throws.
    func saveWorkout(_ payload: HealthKitWorkoutPayload) async -> UUID?

    /// Delete a workout Repster previously wrote. Silently does nothing if the sample
    /// is already gone — HealthKit only permits deleting samples this app saved.
    func deleteWorkout(healthKitUUID: UUID) async
}

/// Inert implementation for tests and previews, mirroring `NoopAnalyticsService`.
///
/// The real service is already inert when the integration is switched off, but depending
/// on that would make any test that touches the preference keys start hitting HealthKit.
struct NoopHealthKitService: HealthKitServiceProtocol {
    var isAvailable: Bool { false }
    var isEnabled: Bool { false }
    var writesEstimatedEnergy: Bool { false }

    func requestAuthorization() async -> HealthKitAuthorizationResult { .unavailable }
    func saveWorkout(_ payload: HealthKitWorkoutPayload) async -> UUID? { nil }
    func deleteWorkout(healthKitUUID: UUID) async {}
}
