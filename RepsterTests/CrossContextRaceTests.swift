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

    // MARK: - Backup export (open question — see BACKUP_EXPORT_SCOPING.md F1 / Phase 0)

    /// Unlike everything above, this one's outcome is **not yet known**. It is the experiment,
    /// not the settled pair.
    ///
    /// `WorkoutHistoryBackupService.exportBackup()` calls three `@ModelActor` repositories and
    /// then reads ~40 properties off every returned `Workout`, `WorkoutSet` and `Exercise` from
    /// inside a *different* actor — live models across the boundary, the shape that shipped as
    /// `EXC_BAD_ACCESS` in 1.3 and twice in TestFlight 1.4. It was never converted because export
    /// was not part of the step 1–4 read-path work.
    ///
    /// Two differences from the crashes above, and they cut opposite ways:
    ///
    ///  - The reader here is a **background actor, not `@MainActor`** — so this test deliberately
    ///    does *not* hop to the main actor. Forcing it there would reproduce the known crash
    ///    rather than the question being asked, and would prove nothing about export.
    ///  - But the fault surface per pass is enormous: one export faults every property of every
    ///    model in the store, and a real history is ~12,000 sets. Rare, wide, and reached for
    ///    exactly when a user is being careful with their data.
    ///
    /// Gated because a crash here takes the runner down with it. Run deliberately:
    ///
    /// ```
    /// touch RepsterTests/Fixtures/Local/RUN_EXPORT_RACE_REPRO
    /// xcodebuild test -project Repster.xcodeproj -scheme Repster \
    ///   -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    ///   -only-testing:RepsterTests/CrossContextRaceTests/testExportBackupUnderConcurrentSaves
    /// ```
    ///
    /// **Reading the result.** A SIGSEGV in a `@Model` getter confirms F1: export is a live crash
    /// path and Phase 1 becomes mandatory. A clean run under this load is evidence *against* it
    /// being urgent — not proof of safety, since absence of a crash never is, but enough to let
    /// Phase 1 ride behind the rest of the queue. Record whichever happens in the scoping doc.
    func testExportBackupUnderConcurrentSaves() async throws {
        let marker = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Local/RUN_EXPORT_RACE_REPRO")
        let requested = FileManager.default.fileExists(atPath: marker.path)
        if requested { try? FileManager.default.removeItem(at: marker) }

        try XCTSkipUnless(
            requested,
            "Open question about the backup export read path — may SIGSEGV the runner. "
                + "Run deliberately: touch RepsterTests/Fixtures/Local/RUN_EXPORT_RACE_REPRO"
        )

        let container = try makeContainer()
        let workoutRepo = WorkoutRepository(modelContainer: container)
        let setRepo = SetRepository(modelContainer: container)
        let exerciseRepo = ExerciseRepository(modelContainer: container)
        let service = makeBackupService(
            container: container,
            workoutRepo: workoutRepo,
            setRepo: setRepo,
            exerciseRepo: exerciseRepo
        )

        let exercise = Exercise(name: "Back Squat", equipmentType: .barbell, trackingType: .weightReps)
        try await exerciseRepo.save(exercise)

        // Enough rows that a single export pass faults through a large graph, but small enough
        // that the export passes below stay quick — the cumulative surface is what matters, and
        // it is (passes x rows x properties), not rows alone.
        var writerWorkoutId: UUID?
        for _ in 0..<150 {
            let workout = Workout(date: .now, status: .completed)
            try await workoutRepo.save(workout)
            if writerWorkoutId == nil { writerWorkoutId = workout.id }

            for setIndex in 1...8 {
                try await setRepo.save(
                    WorkoutSet(
                        workoutId: workout.id,
                        exerciseId: exercise.id,
                        date: .now,
                        weight: Double(80 + setIndex),
                        effectiveWeight: Double(80 + setIndex),
                        reps: 5,
                        setType: .working,
                        orderInWorkout: setIndex,
                        orderInExercise: setIndex,
                        completed: true
                    )
                )
            }
        }
        let targetWorkoutId = try XCTUnwrap(writerWorkoutId)

        // Alternated orderings so every writer pass leaves the context genuinely dirty — a
        // `save()` with nothing pending does not tear down the registry state this races against.
        let stored = try await setRepo.fetchChartSets(for: targetWorkoutId)
            .sorted { $0.orderInExercise < $1.orderInExercise }
        let forward = stored.enumerated().map { index, set in
            SetOrderUpdate(setId: set.id, orderInExercise: index + 1)
        }
        let reversed = stored.enumerated().map { index, set in
            SetOrderUpdate(setId: set.id, orderInExercise: stored.count - index)
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for pass in 0..<Self.pairedLoad {
                    try? await setRepo.applyOrdering(pass.isMultiple(of: 2) ? reversed : forward)
                }
            }
            group.addTask {
                for _ in 0..<Self.pairedLoad {
                    try? await workoutRepo.setHealthKitUUID(UUID(), forWorkoutId: targetWorkoutId)
                }
            }
            // The reader: left on the backup actor, not hopped to @MainActor. Each call re-fetches
            // the whole store, so every pass faults from cold.
            group.addTask {
                for _ in 0..<Self.exportPasses {
                    _ = try? await service.exportBackup()
                }
            }
        }

        let survivingWorkouts = try await workoutRepo.fetchAllWorkoutSummaries(limit: nil, offset: nil)
        XCTAssertEqual(survivingWorkouts.count, 150, "the store should be intact after the run")

        let finalExport = try await service.exportBackup()
        XCTAssertFalse(finalExport.isEmpty, "export should still produce an archive after the run")
    }

    /// One export pass reads the entire store, so these are far heavier than the single-fetch
    /// passes the `pairedLoad` writers do. Enough to accumulate millions of faulting reads.
    private static let exportPasses = 150

    /// Still takes the writers' repositories, though only `StatsService` and `PRService` need them
    /// now — and the reason is worth keeping.
    ///
    /// Before Phase 1 the backup service itself took those repositories, and sharing the writers'
    /// instances was the whole game: `ServiceContainer` hands it the same `RepositoryContainer`
    /// actors the app writes through, so the exporter faulted models out of a context others were
    /// saving. Handing it private repositories here would have produced a fast, clean, worthless
    /// run. That is what the crash on 2026-08-17 proved.
    ///
    /// After Phase 1 the service takes no repositories at all — it owns its `ModelContext` — which
    /// is precisely why the race is gone. The writers below still hammer the same store, so the
    /// test keeps exercising a concurrent-save load; there is simply no longer a shared context for
    /// the exporter to fault through.
    private func makeBackupService(
        container: ModelContainer,
        workoutRepo: WorkoutRepository,
        setRepo: SetRepository,
        exerciseRepo: ExerciseRepository
    ) -> WorkoutHistoryBackupService {
        let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
        let performanceRecordRepo = PerformanceRecordRepository(modelContainer: container)
        let healthProfileRepo = HealthProfileRepository(modelContainer: container)

        return WorkoutHistoryBackupService(
            statsService: StatsService(
                exerciseStatsRepository: exerciseStatsRepo,
                setRepository: setRepo,
                exerciseRepository: exerciseRepo,
                healthProfileRepository: healthProfileRepo,
                performanceRecordRepository: performanceRecordRepo
            ),
            prService: PRService(
                performanceRecordRepository: performanceRecordRepo,
                setRepository: setRepo,
                workoutRepository: workoutRepo,
                healthProfileRepository: healthProfileRepo,
                exerciseRepository: exerciseRepo
            ),
            modelContainer: container
        )
    }
}
