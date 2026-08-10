// HealthKitService.swift
// Writes finished workouts into Apple Health. Write-only authorization; the only read is the
// UUID lookup in deleteWorkout, which resolves samples this app wrote so they can be removed.
// Spec: HEALTHKIT_INTEGRATION_EXPLORATION.md (direction A)

import Foundation
import HealthKit

/// Device-local integration flags.
///
/// Deliberately `UserDefaults` rather than `HealthProfile`: HealthKit authorization is
/// per-device, so this state must NOT travel in an export/backup. Restoring a backup on a
/// new phone must not claim the integration is already connected.
///
/// The Settings UI binds to the same keys via `@AppStorage`, so the two stay in step.
enum HealthKitPreferences {
    static let enabledKey = "healthkit.enabled"
    static let estimatedEnergyKey = "healthkit.writesEstimatedEnergy"
    /// Set once Repster has offered the integration in its own UI (onboarding, What's New).
    /// Stops a user who declined from being asked again by a later surface; Settings is
    /// always available and is not gated by this.
    static let hasBeenOfferedKey = "healthkit.hasBeenOffered"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var writesEstimatedEnergy: Bool {
        UserDefaults.standard.bool(forKey: estimatedEnergyKey)
    }

    static var hasBeenOffered: Bool {
        UserDefaults.standard.bool(forKey: hasBeenOfferedKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    static func markOffered() {
        UserDefaults.standard.set(true, forKey: hasBeenOfferedKey)
    }
}

actor HealthKitService: HealthKitServiceProtocol {

    // MARK: - Constants

    /// Compendium of Physical Activities value for multi-exercise resistance training.
    /// Calibrated for a whole session *including* rest periods, which matches
    /// `Workout.duration` (already excludes paused time via `durationSecondsOverride`).
    ///
    /// `Workout.perceivedEffort` is the obvious way to scale this between ~3.5 and ~6.0
    /// later; v1 stays fixed and conservative deliberately — an over-estimate lands in
    /// the user's Move ring and in whatever nutrition app reads their "calories out".
    private static let strengthTrainingMET: Double = 3.5

    // MARK: - Dependencies

    private let healthStore: HKHealthStore?

    init() {
        self.healthStore = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    // MARK: - Availability & Flags

    nonisolated var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    nonisolated var isEnabled: Bool {
        HealthKitPreferences.isEnabled
    }

    nonisolated var writesEstimatedEnergy: Bool {
        HealthKitPreferences.writesEstimatedEnergy
    }

    nonisolated var shouldOfferConnection: Bool {
        isAvailable && !isEnabled && !HealthKitPreferences.hasBeenOffered
    }

    /// Types Repster writes. Requested together so enabling the energy estimate later
    /// never triggers a second permission sheet.
    private var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        ].compactMap { $0 }.reduce(into: Set<HKSampleType>()) { $0.insert($1) }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> HealthKitAuthorizationResult {
        guard let healthStore else { return .unavailable }

        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: [])
        } catch {
            return .failed(error.localizedDescription)
        }

        // Write status is the one thing HealthKit reports truthfully. (Read status is
        // deliberately opaque, but Repster requests no read types, so this is complete.)
        switch healthStore.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied
        case .notDetermined:
            // The sheet was dismissed without a choice.
            return .denied
        @unknown default:
            return .denied
        }
    }

    /// Whether we currently hold write permission for workouts.
    private var canWriteWorkouts: Bool {
        guard let healthStore else { return false }
        return healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: - Write

    func saveWorkout(_ payload: HealthKitWorkoutPayload) async -> UUID? {
        guard let healthStore, isEnabled, canWriteWorkouts else { return nil }
        guard payload.end > payload.start else { return nil }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )

        do {
            try await builder.beginCollection(at: payload.start)

            if let energySample = energySample(for: payload) {
                // `add(_:completion:)` has no async variant — its `(Bool, Error?)`
                // completion doesn't auto-bridge, unlike beginCollection/endCollection.
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    builder.add([energySample]) { _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }

            try await builder.endCollection(at: payload.end)
            let workout = try await builder.finishWorkout()
            return workout?.uuid
        } catch {
            // Never propagate: a Health failure must not fail the workout finish.
            #if DEBUG
            print("[HealthKit] saveWorkout failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// MET-based active-energy estimate: `kcal = MET x bodyweightKg x hours`.
    ///
    /// Returns `nil` when the estimate is switched off, or when no bodyweight has ever
    /// been logged. Substituting a population-average weight was considered and rejected:
    /// it breaks the codebase's degrade-silently precedent, and a fabricated calorie
    /// figure reaches both the Move ring and any nutrition app reading "calories out".
    /// An absent number is better than a wrong one.
    private func energySample(for payload: HealthKitWorkoutPayload) -> HKQuantitySample? {
        guard writesEstimatedEnergy else { return nil }
        guard let kilocalories = Self.estimatedKilocalories(
            bodyweightKg: payload.bodyweightKg,
            start: payload.start,
            end: payload.end
        ) else { return nil }
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }

        return HKQuantitySample(
            type: energyType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
            start: payload.start,
            end: payload.end
        )
    }

    /// `kcal = MET x bodyweightKg x hours`, or `nil` when there's nothing sound to compute
    /// from. Pure and `static` so the rule can be tested without an `HKHealthStore`.
    static func estimatedKilocalories(bodyweightKg: Double?, start: Date, end: Date) -> Double? {
        guard let bodyweightKg, bodyweightKg > 0 else { return nil }

        let hours = end.timeIntervalSince(start) / 3600
        guard hours > 0 else { return nil }

        let kilocalories = strengthTrainingMET * bodyweightKg * hours
        guard kilocalories.isFinite, kilocalories > 0 else { return nil }
        return kilocalories
    }

    // MARK: - Delete

    func deleteWorkout(healthKitUUID: UUID) async {
        guard let healthStore, canWriteWorkouts else { return }

        let predicate = HKQuery.predicateForObject(with: healthKitUUID)

        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: HKObjectType.workoutType(),
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                healthStore.execute(query)
            }

            guard !samples.isEmpty else { return }
            try await healthStore.delete(samples)
        } catch {
            // Best-effort. The sample may already be gone, or was written by another install.
            #if DEBUG
            print("[HealthKit] deleteWorkout failed: \(error.localizedDescription)")
            #endif
        }
    }
}
