import XCTest
@testable import Repster

/// The push option, and the capability-gate count the explainer reads.
///
/// The push is defined as *the same target taken to failure* rather than a heavier
/// suggestion, so these assert its two guarantees: it never leaves the user's own rep
/// range, and it is never lighter than the set already prescribed.
final class SuggestionExplainerPushTests: XCTestCase {

    private func settings(increment: Double = 2.5) -> SuggestionSettingsSnapshot {
        SuggestionSettingsSnapshot(
            formula: .epley,
            restTimerSeconds: 150,
            weightIncrement: increment,
            fatigueEnabled: true,
            freshnessEnabled: false,
            freshnessPercent: 0.03,
            baseFatigueRate: 0.03,
            recoveryConstant: 180,
            sessionCapabilityPolicy: .observed
        )
    }

    private func target(
        reps: Int,
        rir: Double,
        repRange: ClosedRange<Int>? = nil
    ) -> SuggestionTarget {
        SuggestionTarget(
            reps: reps,
            rir: rir,
            repRange: repRange,
            repsSource: .explicitSet,
            rirSource: .explicitSet
        )
    }

    // MARK: - The push itself

    /// Epley at an effective 73 kg: 8 reps to failure is 2190/38 = 57.63, rounded to 57.5.
    /// The prescription for the same target at RIR 1 is 7 reps, so the push is a different set.
    func testPushTakesTheTopOfTheRepRangeToFailure() {
        let push = SuggestionEngine.pushOption(
            target: target(reps: 7, rir: 1, repRange: 6...8),
            effectiveE1RM: 73,
            prescribedWeight: 57.5,
            prescribedReps: 7,
            settings: settings()
        )

        XCTAssertEqual(push?.reps, 8, "The push should take the top of the user's own range, not reach past it")
        XCTAssertEqual(push?.weight ?? 0, 57.5, accuracy: 0.001)
    }

    /// A fixed target has no higher rep to reach for, so the push has to buy the extra
    /// effort with load instead. At RIR 1 the prescription is 55; at failure it is 57.5.
    func testFixedTargetPushAddsLoadRatherThanReps() {
        let push = SuggestionEngine.pushOption(
            target: target(reps: 8, rir: 1),
            effectiveE1RM: 73,
            prescribedWeight: 55,
            prescribedReps: 8,
            settings: settings()
        )

        XCTAssertEqual(push?.reps, 8)
        XCTAssertEqual(push?.weight ?? 0, 57.5, accuracy: 0.001)
    }

    func testNoPushWhenTheTargetAlreadyGoesToFailure() {
        let push = SuggestionEngine.pushOption(
            target: target(reps: 7, rir: 0, repRange: 6...8),
            effectiveE1RM: 73,
            prescribedWeight: 60,
            prescribedReps: 7,
            settings: settings()
        )

        XCTAssertNil(push, "There is nothing to push toward when the target is already RIR 0")
    }

    func testNoPushWhenItWouldNameTheSetAlreadyPrescribed() {
        let push = SuggestionEngine.pushOption(
            target: target(reps: 8, rir: 1),
            effectiveE1RM: 73,
            prescribedWeight: 57.5,
            prescribedReps: 8,
            settings: settings()
        )

        XCTAssertNil(push, "A push identical to the prescription is not an option, it is noise")
    }

    /// When the suggestion floor raises the prescription above the model, the model's own
    /// push can land underneath it. Calling a lighter set a push would be a lie.
    func testNoPushWhenItWouldBeLighterThanThePrescription() {
        let push = SuggestionEngine.pushOption(
            target: target(reps: 7, rir: 1, repRange: 6...8),
            effectiveE1RM: 73,
            prescribedWeight: 65,
            prescribedReps: 7,
            settings: settings()
        )

        XCTAssertNil(push)
    }

    func testPushRoundsToTheConfiguredIncrement() {
        let coarse = SuggestionEngine.pushOption(
            target: target(reps: 7, rir: 1, repRange: 6...8),
            effectiveE1RM: 73,
            prescribedWeight: 55,
            prescribedReps: 7,
            settings: settings(increment: 5)
        )

        XCTAssertEqual(coarse?.weight ?? 0, 60, accuracy: 0.001, "57.63 on 5 kg steps rounds to 60")
    }

    // MARK: - The capability gate the explainer describes

    func testSessionSetsIgnoredForCapabilityCountsOnlySetsFarFromFailure() {
        let data = makeData(loggedRIRs: [4, 3, 1, nil])

        XCTAssertEqual(
            data.sessionSetsIgnoredForCapability,
            2,
            "RIR 3 is the gate itself and must count as ignored; RIR 1 and an unlogged effort must not"
        )
    }

    func testNoSetsAreIgnoredWhenEverythingWasTakenNearFailure() {
        XCTAssertEqual(makeData(loggedRIRs: [0, 1, 2]).sessionSetsIgnoredForCapability, 0)
    }

    /// The count is read straight off the engine's own threshold rather than a literal in
    /// the view, so the two cannot drift apart.
    func testIgnoredCountTracksTheEngineThreshold() {
        let atThreshold = SuggestionEngine.capabilityEvidenceMaxRIR
        XCTAssertEqual(makeData(loggedRIRs: [atThreshold]).sessionSetsIgnoredForCapability, 1)
        XCTAssertEqual(makeData(loggedRIRs: [atThreshold - 0.5]).sessionSetsIgnoredForCapability, 0)
    }

    private func makeData(loggedRIRs: [Double?]) -> WeightSuggestionData {
        let snapshots = loggedRIRs.enumerated().map { index, rir in
            CompletedSetSnapshot(
                setId: UUID(),
                setNumber: index + 1,
                weight: 60,
                reps: 8,
                rir: rir,
                suggestion: nil
            )
        }

        return SuggestionExplainer.makeWeightSuggestionData(
            preparation: SuggestionPreparation(
                cacheKey: "test",
                completedSessionSets: [],
                completedWorkingSetSnapshots: snapshots,
                setResolutions: [],
                pendingSets: [],
                unavailableReason: .noPendingSets
            ),
            evaluation: .unavailable(.noPendingSets),
            unitPreference: .metric
        )
    }
}
