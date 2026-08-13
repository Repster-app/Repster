import XCTest
import SwiftData
@testable import Repster

/// The paired control for the cross-context crash class.
///
/// A clean run proves nothing on its own — it could mean the fix works, or it could mean the
/// harness stopped exercising the bug. So this file holds **both** halves:
///
///  - `testSnapshotPathIsCleanUnderConcurrentSaves` runs in the normal suite and must pass.
///  - `testLiveModelPathStillCrashesUnderConcurrentSaves` is the control. It is expected to
///    **crash the test runner** (SIGSEGV inside SwiftData, not a failed assertion), so it is
///    gated behind an environment variable and never runs by default.
///
/// Run the control deliberately by dropping a marker file, then selecting the test:
///
/// ```
/// touch RepsterTests/Fixtures/Local/RUN_RACE_REPRO
/// xcodebuild test -project Repster.xcodeproj -scheme Repster \
///   -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///   -only-testing:RepsterTests/CrossContextRaceTests/testLiveModelPathStillCrashesUnderConcurrentSaves
/// ```
///
/// The marker is **consumed** — deleted before the run starts — so a forgotten file cannot
/// crash a later full-suite run. `Fixtures/Local/` is gitignored.
///
/// > A marker file rather than an environment variable, because the `TEST_RUNNER_` prefix
/// > that SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md §7.5 recommends **does not work in this
/// > project** — verified 2026-08-13 by dumping `ProcessInfo.processInfo.environment` inside
/// > the test process: neither `TEST_RUNNER_RUN_RACE_REPRO=1` nor a bare `RUN_RACE_REPRO=1`
/// > passed to `xcodebuild` arrives. The control silently skipped instead of running.
///
/// Expect `Restarting after unexpected exit, crash, or test timeout` and 0 tests completed,
/// with a report in `~/Library/Logs/DiagnosticReports/` whose faulting frame is a `@Model`
/// property getter at `KERN_INVALID_ADDRESS 0x8000000000000010`. **That is the passing result
/// for the control.** If it stops crashing, this file has stopped detecting the bug and the
/// snapshot half is no longer evidence of anything.
///
/// The shape that matters (learned the hard way — see SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md
/// §7.5): the reader must **re-fetch on every pass**. A SwiftData property faults only on its
/// first read, so holding one array and re-reading it materialises everything once and then
/// never faults again — a harness that does that passes in 0.4 s and proves nothing.
final class CrossContextRaceTests: XCTestCase {

    /// Shared by the snapshot test and its control, so the pair can never drift apart — a
    /// clean snapshot run is only evidence if the control ran under the *same* load. This is
    /// the configuration recorded as crashing the control in
    /// SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md §14.3: 2 writers x 2,000 saves against 2,000
    /// main-actor re-fetch passes. Lower it and the control may stop detecting the bug.
    private static let pairedLoad = 2_000

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Exercise.self, Workout.self, WorkoutSet.self, ExerciseStats.self,
            PerformanceRecord.self, BodyweightEntry.self, HealthProfile.self,
            FatigueObservation.self, FatigueLearningSetAudit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func seedWorkouts(_ repo: WorkoutRepository, count: Int) async throws -> UUID {
        var firstId: UUID?
        for _ in 0..<count {
            let workout = Workout(date: .now, status: .completed)
            try await repo.save(workout)
            if firstId == nil { firstId = workout.id }
        }
        return firstId!
    }

    // MARK: - The snapshot path (runs in the suite)

    /// Snapshots crossing the actor boundary, read on the main actor while the owning context
    /// saves. This is what every converted screen now does, and it must be clean.
    func testSnapshotPathIsCleanUnderConcurrentSaves() async throws {
        let container = try makeContainer()
        let repo = WorkoutRepository(modelContainer: container)
        let targetId = try await seedWorkouts(repo, count: 200)

        await withTaskGroup(of: Void.self) { group in
            // Writers — the shape of the HealthKit mirror landing during a Home reload.
            for _ in 0..<2 {
                group.addTask {
                    for _ in 0..<Self.pairedLoad {
                        try? await repo.setHealthKitUUID(UUID(), forWorkoutId: targetId)
                    }
                }
            }
            // Reader — re-fetches every pass, so every pass faults from cold.
            group.addTask { @MainActor in
                for _ in 0..<Self.pairedLoad {
                    let summaries = (try? await repo.fetchAllWorkoutSummaries(limit: nil, offset: nil)) ?? []
                    _ = summaries.filter { $0.status == .completed }.count
                }
            }
        }

        let survived = try await repo.fetchAllWorkoutSummaries(limit: nil, offset: nil)
        XCTAssertEqual(survived.count, 200, "the store should be intact after the run")
    }

    /// The same shape one level down: set snapshots read on the main actor while
    /// `SetRepository` writes. This is the surface step 5 converts.
    func testSetSnapshotPathIsCleanUnderConcurrentSaves() async throws {
        let container = try makeContainer()
        let setRepo = SetRepository(modelContainer: container)
        let workoutId = UUID()
        let exerciseId = UUID()

        for index in 1...25 {
            let set = WorkoutSet(
                workoutId: workoutId,
                exerciseId: exerciseId,
                weight: Double(80 + index),
                reps: 5,
                orderInWorkout: index,
                orderInExercise: index,
                completed: true
            )
            try await setRepo.save(set)
        }
        // Two *different* orderings, alternated, so every writer pass actually mutates.
        //
        // Writing back the values already stored would leave the context with nothing
        // pending, and `save()` with no dirty objects does not tear down the registry state
        // this test exists to race against — the writer would be free and the run would prove
        // nothing while still passing.
        let stored = try await setRepo.fetchChartSets(for: workoutId)
            .sorted { $0.orderInExercise < $1.orderInExercise }
        let forward = stored.enumerated().map { index, set in
            SetOrderUpdate(setId: set.id, orderInExercise: index + 1)
        }
        let reversed = stored.enumerated().map { index, set in
            SetOrderUpdate(setId: set.id, orderInExercise: stored.count - index)
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for pass in 0..<500 {
                    try? await setRepo.applyOrdering(pass.isMultiple(of: 2) ? reversed : forward)
                }
            }
            group.addTask { @MainActor in
                for _ in 0..<500 {
                    let snapshots = (try? await setRepo.fetchChartSets(for: workoutId)) ?? []
                    _ = snapshots.filter { $0.completed }.map(\.effectiveWeight).count
                }
            }
        }

        let survived = try await setRepo.fetchChartSets(for: workoutId)
        XCTAssertEqual(survived.count, 25)
    }

    // MARK: - The live-model control (gated — expected to crash)

    /// Expected to **crash the runner**. See the file comment for how and why to run it.
    func testLiveModelPathStillCrashesUnderConcurrentSaves() async throws {
        let marker = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Local/RUN_RACE_REPRO")
        let requested = FileManager.default.fileExists(atPath: marker.path)
        // Consume it first: if this crashes the runner (the expected result), the marker must
        // already be gone or the next full-suite run dies too.
        if requested { try? FileManager.default.removeItem(at: marker) }

        try XCTSkipUnless(
            requested,
            "Control for the cross-context crash — expected to SIGSEGV the runner. "
                + "Run deliberately: touch RepsterTests/Fixtures/Local/RUN_RACE_REPRO"
        )

        let container = try makeContainer()
        let repo = WorkoutRepository(modelContainer: container)
        let targetId = try await seedWorkouts(repo, count: 200)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    for _ in 0..<Self.pairedLoad {
                        if let workout = try? await repo.fetch(byId: targetId) {
                            try? await repo.save(workout)
                        }
                    }
                }
            }
            group.addTask { @MainActor in
                for _ in 0..<Self.pairedLoad {
                    // Live models across the boundary, re-fetched so each pass faults cold.
                    let live = (try? await repo.fetchAllWorkouts(limit: nil, offset: nil)) ?? []
                    _ = live.filter { $0.status == .completed }.count
                }
            }
        }

        XCTFail(
            "The control did not crash. Either SwiftData's behaviour changed or this harness "
                + "stopped exercising the bug — in which case the snapshot tests above are no "
                + "longer evidence that anything is fixed."
        )
    }
}
