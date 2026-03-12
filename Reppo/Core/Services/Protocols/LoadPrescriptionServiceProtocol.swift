// LoadPrescriptionServiceProtocol.swift
// Contract for the fatigue-aware weight prescription engine.
// Based on: RIR_Fatigue_Aware_1RM_Model.pdf
// Feature: Weight Prescription (magic wand)

import Foundation

/// Input describing a single set in the current session for fatigue modeling.
/// Used by the prescription engine to accumulate session fatigue.
struct SessionSetContext: Sendable {
    /// Weight used for this set (kg).
    let weight: Double
    /// Reps performed (or target reps for upcoming sets).
    let reps: Int
    /// RIR at completion (nil if not recorded).
    let rir: Double?
    /// When this set was completed (nil if not yet completed).
    let completedAt: Date?
    /// Whether this set has been completed.
    let completed: Bool
}

/// Request to prescribe weight for a single set.
struct PrescriptionRequest: Sendable {
    /// The exercise to prescribe for.
    let exerciseId: UUID
    /// Target reps for this set. For rep ranges, use the midpoint.
    let targetReps: Int
    /// Target RIR for this set.
    let targetRIR: Double
    /// The set's position in the exercise (0-indexed).
    let setIndex: Int
    /// All completed sets for this exercise in the current session (for fatigue calculation).
    let completedSessionSets: [SessionSetContext]
}

/// Result of a weight prescription calculation.
struct PrescriptionResult: Sendable {
    /// The prescribed weight in kg, rounded to the nearest increment.
    let prescribedWeight: Double
    /// The raw weight before rounding (for debug display).
    let rawWeight: Double
    /// The weight increment used for rounding (for debug display).
    let weightIncrement: Double
    /// The base e1RM used for the calculation (before fatigue).
    let baseE1RM: Double
    /// The effective e1RM after fatigue discount.
    let effectiveE1RM: Double
    /// The intensity factor applied (reps + RIR → %1RM).
    let intensityFactor: Double
    /// The fatigue discount applied (1.0 = no fatigue).
    let fatigueDiscount: Double
    /// Whether a freshness bonus was applied.
    let freshnessApplied: Bool
    /// Source of the e1RM estimate.
    let e1RMSource: E1RMSource
    /// When rep range optimization was used, the optimal rep count chosen.
    /// Nil when no range was provided (single target reps).
    let bestReps: Int?
}

/// Shared base e1RM estimate result for consumers that need a consistent source/value pair.
struct BaseE1RMEstimate: Sendable {
    let value: Double?
    let source: E1RMSource
}

/// How the base e1RM was determined.
enum E1RMSource: Sendable {
    /// From recent workout history in the recency window (top-performance baseline).
    case recentPerformance
    /// From the PR table (PerformanceRecord) — less reliable for current strength.
    case historicalPR
    /// No data available — prescription not possible.
    case noData
}

/// Service for prescribing weights based on estimated 1RM, fatigue modeling, and user settings.
///
/// The engine follows a layered model:
/// 1. Base e1RM capacity from recent workout history (top recent workout peaks)
/// 2. Session fatigue accumulation from completed sets
/// 3. Rest-time fatigue decay
/// 4. Readiness bounded to a narrow band around capacity
/// 5. Intensity factor from target reps + RIR
/// 6. Rounding to nearest weight increment
///
/// See: RIR_Fatigue_Aware_1RM_Model.pdf for full algorithm documentation.
protocol LoadPrescriptionServiceProtocol: Sendable {

    /// Estimate base e1RM capacity baseline for an exercise using the same logic as prescription generation.
    ///
    /// Uses recent workout history in the recency window, then PR fallback when needed.
    /// - Parameters:
    ///   - exerciseId: The exercise to estimate for.
    ///   - completedSessionSets: Completed sets from the current session context.
    /// - Returns: The estimated base e1RM and source metadata.
    func estimateBaseE1RM(
        exerciseId: UUID,
        completedSessionSets: [SessionSetContext]
    ) async throws -> BaseE1RMEstimate

    /// Prescribe a weight for a single set.
    ///
    /// - Parameter request: The prescription request containing exercise, targets, and session context.
    /// - Returns: The prescription result, or nil if no data is available for this exercise.
    func prescribe(_ request: PrescriptionRequest) async throws -> PrescriptionResult?

    /// Prescribe weights for multiple sets at once (batch operation).
    ///
    /// More efficient than calling prescribe() repeatedly because it fetches
    /// exercise data and e1RM only once.
    ///
    /// - Parameters:
    ///   - exerciseId: The exercise to prescribe for.
    ///   - sets: Array of (targetReps, targetRIR, setIndex, repRange) tuples.
    ///     When `repRange` is provided, the engine evaluates all reps in the range
    ///     and picks the (weight, reps) pair closest to the target e1RM after rounding.
    ///   - completedSessionSets: All completed sets for this exercise in the current session.
    /// - Returns: Array of prescription results (nil entries where prescription not possible).
    func prescribeBatch(
        exerciseId: UUID,
        sets: [(targetReps: Int, targetRIR: Double, setIndex: Int, repRange: ClosedRange<Int>?)],
        completedSessionSets: [SessionSetContext]
    ) async throws -> [PrescriptionResult?]
}
