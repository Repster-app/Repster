import XCTest
import SwiftData
import Foundation
@testable import Repster

/// Regression harness for SWIFTDATA_LIVE_MODEL_FIX_SCOPING.md: positive controls preserve the old
/// unsafe shapes, while regression cases exercise the real repository/service paths after each
/// migration. A clean regression run means something only while its positive control still crashes.
///
/// Every test is opt-in. Drop its marker, then select it. The marker is consumed before the run
/// starts, so a forgotten file cannot crash a later full-suite run. `Fixtures/Local/` is
/// gitignored. Same convention as `CrossContextRaceTests`, for the same reason: environment
/// variables passed to `xcodebuild` do not reach this test process.
///
/// | Test | Marker | Run on | Expected |
/// |---|---|---|---|
/// | `testBug2Regression_OnboardingFinishWithMainBuiltRepositories` | `RUN_BUG2_ONBOARDING` | iOS 17.5 | Clean |
/// | `testBug2Control_UnsafeExternalWritesWithMainBuiltRepository` | `RUN_BUG2_UNSAFE_WRITES` | iOS 17.5 | **Crash** |
/// | `testBug2Discriminator_UnsafeExternalWritesWithOffMainRepository` | `RUN_BUG2_OFF_MAIN` | iOS 17.5 | Clean |
/// | `testBug2Discriminator_OwnerActorWrites` | `RUN_BUG2_OWNER_WRITES` | iOS 17.5 | Clean |
/// | `testBug3Mechanism_WhenIsBackingDataReplaced` | `RUN_BUG3_MECHANISM` | any | Prints a table |
/// | `testBug3Control_HeldSetsReadWhileOwnerSaves` | `RUN_BUG3_HELD_SETS` | iOS 18.6 | **Crash** |
/// | `testBug3Regression_EngineUsesSnapshotsWhileOwnerSaves` | `RUN_BUG3_ENGINE` | iOS 18.6 | Clean |
/// | `testBug3Control_HeldWorkoutReadOnMainWhileOwnerSaves` | `RUN_BUG3_HELD_WORKOUT` | iOS 18.6 | **Crash** |
/// | `testBug3Discriminator_SnapshotsReadWhileOwnerSaves` | `RUN_BUG3_SNAPSHOTS` | iOS 18.6 | Clean |
///
/// ```bash
/// touch RepsterTests/Fixtures/Local/RUN_BUG2_ONBOARDING
/// xcodebuild test -project Repster.xcodeproj -scheme Repster \
///   -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.5' \
///   -only-testing:RepsterTests/LiveModelRaceReproTests/testBug2Regression_OnboardingFinishWithMainBuiltRepositories
/// ```
///
/// Bug 3 uses `name=iPhone 16 Pro,OS=18.6`. Always pass the OS: without it `xcodebuild` picks the
/// newest runtime, where neither bug has been seen.
///
/// **Reading a result.** For a control, a crash is the passing result: `Restarting after
/// unexpected exit, crash, or test timeout` in the log, and a report in
/// `~/Library/Logs/DiagnosticReports/Repster-*.ips`. Open the report and check the *other*
/// threads, which is what identifies the bug:
/// - Bug 2: `0x8000000000000010`, main thread in `__CFRunLoopDoObservers`, another thread inside a
///   `HealthProfile` setter called from `SettingsService`.
/// - Bug 3: `0x10`, one thread in a `@Model` getter, another in `persistentBackingData.setter`
///   dying in `swift_deallocClassInstance` ("deallocated with non-zero retain count").
///
/// macOS keeps at most about 25 reports per app per rolling day, so after a heavy session the
/// crash still happens but no report is written. Check the `.ips` timestamps before concluding
/// anything from a missing one.
///
/// A control that survives on its target runtime fails with a message saying so. Races do not
/// fire every run, so rerun it a few times before concluding the harness has gone blind.
///
/// `AffectedSetsPreconditionTests` is a further bug-2 control on the set-save path. It is in the
/// default suite and crashes on iOS 17.5 on most runs.
final class LiveModelRaceReproTests: XCTestCase {

    /// The load the investigation's probes crashed under (§9.1, §9.4b).
    private static let rounds = 2_000

    // MARK: - Opt-in gate and reporting

    private func requireMarker(_ name: String, _ purpose: String) throws {
        let marker = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Local/\(name)")
        let requested = FileManager.default.fileExists(atPath: marker.path)
        // Consume it first: if this crashes the runner (a control's expected result), the marker
        // must already be gone.
        if requested { try? FileManager.default.removeItem(at: marker) }
        try XCTSkipUnless(
            requested,
            "\(purpose) Run deliberately: touch RepsterTests/Fixtures/Local/\(name)"
        )
    }

    private static var iOSMajorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    private func log(_ message: String) {
        print("REPRO [\(ProcessInfo.processInfo.operatingSystemVersionString)] \(message)")
    }

    /// Called when a control finishes. Surviving is only a failure on the runtime the bug lives on.
    private func controlSurvived(_ what: String, bugRuntime: Int) {
        log("\(what) survived \(Self.rounds) rounds")
        if Self.iOSMajorVersion == bugRuntime {
            XCTFail(
                "\(what) did not crash on iOS \(bugRuntime). Either the race did not fire this run "
                    + "(rerun a few times), or this harness no longer detects the bug, in which case "
                    + "a clean run after a fix proves nothing."
            )
        }
    }

    /// The app's full schema over an in-memory store, as `WorkoutJourneyTests` uses. Both
    /// bug-3 crashes came from that class, so an on-disk store is not required.
    private static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(ModelContainerSetup.modelTypes),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    // MARK: - Bug 2: a service writes a record its repository owns (iOS 17)

    /// Every repository `SettingsService` and the onboarding screen need, over one store.
    private struct SettingsRepositories: Sendable {
        let container: ModelContainer
        let healthProfile: HealthProfileRepository
        let set: SetRepository
        let workout: WorkoutRepository
        let exercise: ExerciseRepository
        let exerciseStats: ExerciseStatsRepository
        let performanceRecord: PerformanceRecordRepository
        let bodyweight: BodyweightEntryRepository
        let builtOnMainThread: Bool
    }

    /// Builds on whatever thread calls it. A repository's `ModelContext` belongs to the thread it
    /// was created on, which on iOS 17 is what decides whether bug 2 can fire.
    private static func buildSettingsRepositories() throws -> SettingsRepositories {
        let container = try makeContainer()
        return SettingsRepositories(
            container: container,
            healthProfile: HealthProfileRepository(modelContainer: container),
            set: SetRepository(modelContainer: container),
            workout: WorkoutRepository(modelContainer: container),
            exercise: ExerciseRepository(modelContainer: container),
            exerciseStats: ExerciseStatsRepository(modelContainer: container),
            performanceRecord: PerformanceRecordRepository(modelContainer: container),
            bodyweight: BodyweightEntryRepository(modelContainer: container),
            builtOnMainThread: pthread_main_np() != 0
        )
    }

    /// The real onboarding screen over the real `SettingsService`, wired as `ServiceContainer` does.
    @MainActor
    private func makeOnboarding(_ repos: SettingsRepositories) -> OnboardingViewModel {
        let statsService = StatsService(
            exerciseStatsRepository: repos.exerciseStats,
            setRepository: repos.set,
            exerciseRepository: repos.exercise,
            healthProfileRepository: repos.healthProfile,
            performanceRecordRepository: repos.performanceRecord
        )
        let prService = PRService(
            performanceRecordRepository: repos.performanceRecord,
            setRepository: repos.set,
            workoutRepository: repos.workout,
            healthProfileRepository: repos.healthProfile,
            exerciseRepository: repos.exercise
        )
        let settingsService = SettingsService(
            healthProfileRepository: repos.healthProfile,
            prService: prService,
            statsService: statsService,
            modelContainer: repos.container,
            userDefaults: UserDefaults(suiteName: "live-model-repro-\(UUID().uuidString)")!,
            seedExercises: { _ in }
        )
        return OnboardingViewModel(
            settingsService: settingsService,
            bodyweightService: BodyweightService(
                bodyweightEntryRepository: repos.bodyweight,
                healthProfileRepository: repos.healthProfile
            ),
            analyticsService: NoopAnalyticsService(),
            programCatalogService: LiveModelReproNoPrograms()
        )
    }

    /// The device crash's path: `OnboardingViewModel.finish()`, which makes three
    /// `SettingsService` writes in a row. No bodyweight and no program, so nothing else writes.
    @MainActor
    private func finishOnboardingRepeatedly(_ repos: SettingsRepositories) async throws {
        let viewModel = makeOnboarding(repos)
        for round in 0..<Self.rounds {
            // New values every round, so no write is skipped as unchanged.
            viewModel.selectedUnit = round.isMultiple(of: 2) ? .metric : .imperial
            viewModel.defaultTargetReps = 5 + round % 8
            viewModel.defaultTargetRIR = round % 4
            await viewModel.finish()
        }

        // `finish()` swallows errors, so confirm the writes landed. Read through a fresh context,
        // not a repository, so this check can't itself hand a live model across actors.
        let committed = try ModelContext(repos.container).fetch(FetchDescriptor<HealthProfile>())
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed.first?.prescriptionDefaultTargetRIR, (Self.rounds - 1) % 4)
        XCTAssertEqual(committed.first?.prescriptionDefaultTargetReps, 5 + (Self.rounds - 1) % 8)
    }

    /// **Regression.** The real onboarding path now sends mutations to the repository owner.
    /// It must survive on iOS 17.5 with repositories built exactly where the app builds them.
    @MainActor
    func testBug2Regression_OnboardingFinishWithMainBuiltRepositories() async throws {
        try requireMarker(
            "RUN_BUG2_ONBOARDING",
            "Bug 2 regression: real onboarding must stay clean on iOS 17."
        )
        let repos = try Self.buildSettingsRepositories()
        XCTAssertTrue(repos.builtOnMainThread, "must be built where the app builds its repositories")

        try await finishOnboardingRepeatedly(repos)
        log("Bug 2 regression (onboarding, repositories built on main) survived \(Self.rounds) rounds")
    }

    /// **Positive control.** Preserves the old unsafe fetch-mutate-save shape after the app path
    /// is fixed. This must still crash on iOS 17.5 or a clean regression run proves nothing.
    @MainActor
    func testBug2Control_UnsafeExternalWritesWithMainBuiltRepository() async throws {
        try requireMarker(
            "RUN_BUG2_UNSAFE_WRITES",
            "Bug 2 positive control: expected to crash the test runner on iOS 17."
        )
        let repo = HealthProfileRepository(modelContainer: try Self.makeContainer())
        let writer = LiveModelReproUnsafeProfileWriter()
        try await writer.writeRepeatedly(repo, rounds: Self.rounds)
        controlSurvived("Bug 2 positive control (unsafe external writes)", bugRuntime: 17)
    }

    /// **Discriminator: where the repository is built.** The positive control's unsafe writes,
    /// with the repository built off main. This remains clean on iOS 17.5.
    @MainActor
    func testBug2Discriminator_UnsafeExternalWritesWithOffMainRepository() async throws {
        try requireMarker(
            "RUN_BUG2_OFF_MAIN",
            "Bug 2 discriminator: unsafe writes with the repository built off main."
        )
        let repo = try await Task.detached {
            HealthProfileRepository(modelContainer: try Self.makeContainer())
        }.value
        let writer = LiveModelReproUnsafeProfileWriter()

        try await writer.writeRepeatedly(repo, rounds: Self.rounds)
        log("Bug 2 discriminator (unsafe writes, repository built off main) survived \(Self.rounds) rounds")
    }

    /// **Discriminator: who writes.** The same three profile writes per round, but made inside the
    /// actor that owns the context, which is built on main as in the control. If the crash needs a
    /// write from a *different* actor (investigation §9.1 P2), this stays clean on iOS 17.5.
    ///
    /// The owner is a probe, because the app has no "change it inside the owner" method for the
    /// profile yet. Adding one is Phase 1 of the fix.
    @MainActor
    func testBug2Discriminator_OwnerActorWrites() async throws {
        try requireMarker(
            "RUN_BUG2_OWNER_WRITES",
            "Bug 2 discriminator: the control's writes made inside the owning actor."
        )
        let container = try Self.makeContainer()
        XCTAssertTrue(pthread_main_np() != 0)
        let owner = LiveModelReproProfileOwner(modelContainer: container)

        for round in 0..<Self.rounds {
            try await owner.setTargetReps(5 + round % 8)
            try await owner.setTargetRIR(round % 4)
            try await owner.touch()
        }

        let rir = try await owner.targetRIR()
        XCTAssertEqual(rir, (Self.rounds - 1) % 4)
        log("Bug 2 discriminator (owner-actor writes, built on main) survived \(Self.rounds) rounds")
    }

    // MARK: - Bug 3: a held live record read while its owner replaces its backing data (iOS 18)
    //
    // Both bug-3 reports died in `persistentBackingData.setter`: the swapping thread in Swift's
    // "deallocated with non-zero retain count" fatal error, the reader at `0x10`. The mechanism
    // probe below measured when SwiftData replaces a model's backing data on iOS 18.6: on every
    // save of a changed model, on the first fetch after a new model is saved, and when another
    // context saves the row. A plain re-fetch replaces nothing.
    //
    // So the reader must already be *holding* the record when the replacement happens, as the
    // workout screen holds `workout` and `setsByExercise`. Three earlier harnesses, whose readers
    // fetched their own records and so only ever saw them after the swap, ran 2,000 rounds clean
    // on iOS 18.6 (2026-09-12).

    /// Completed working sets for one new workout and exercise, saved through the repository.
    /// Completed with an e1RM, so `LoadPrescriptionService` counts them.
    private static func saveHeldSets(
        _ setRepo: SetRepository,
        count: Int = 3
    ) async throws -> (workoutId: UUID, exerciseId: UUID, setIds: [UUID]) {
        let workoutId = UUID()
        let exerciseId = UUID()
        var setIds: [UUID] = []
        for order in 1...count {
            let weight = 80.0 + Double(order)
            let set = WorkoutSet(
                workoutId: workoutId,
                exerciseId: exerciseId,
                date: Date(),
                weight: weight,
                effectiveWeight: weight,
                reps: 5,
                e1RM: weight * (1 + 5.0 / 30),
                rir: 2,
                setType: .working,
                orderInWorkout: order,
                orderInExercise: order,
                completed: true
            )
            try await setRepo.save(set)
            setIds.append(set.id)
        }
        return (workoutId, exerciseId, setIds)
    }

    /// The owner changes and saves every held set, `rounds` times: an ordinary repository method,
    /// not bug 2's shape. Each save replaces the saved sets' backing data. Alternates the value so
    /// no write is skipped as unchanged.
    private static func ownerSavesRepeatedly(_ setRepo: SetRepository, setIds: [UUID]) async {
        for round in 0..<rounds {
            for setId in setIds {
                try? await setRepo.applyRestDuration(setId: setId, seconds: 60 + round % 2)
            }
        }
    }

    /// **Control, minimal.** A plain actor holds the live `WorkoutSet`s and reads them in a tight
    /// loop, as `LoadPrescriptionService` reads the sets it fetched, while `SetRepository` saves
    /// changes to those same sets.
    @MainActor
    func testBug3Control_HeldSetsReadWhileOwnerSaves() async throws {
        try requireMarker(
            "RUN_BUG3_HELD_SETS",
            "Bug 3 control (held sets): expected to crash the test runner on iOS 18."
        )
        let setRepo = SetRepository(modelContainer: try Self.makeContainer())
        let saved = try await Self.saveHeldSets(setRepo)
        let held = try await setRepo.fetchSets(for: saved.workoutId)
        XCTAssertEqual(held.count, 3)

        let reader = LiveModelReproSetReader()
        let stop = LiveModelReproStopFlag()
        async let passes = reader.readUntilStopped(held, stop: stop)
        await Self.ownerSavesRepeatedly(setRepo, setIds: saved.setIds)
        stop.set()
        log("held-sets reader made \(await passes) passes")

        controlSurvived("Bug 3 control (held sets read off main while the owner saves)", bugRuntime: 18)
    }

    /// **Regression, real path.** The real `LoadPrescriptionService.estimateBaseE1RM` in a loop,
    /// which used to follow crash B's stack through live `WorkoutSet` getters. The repository now
    /// returns `ChartSetData`; concurrent saves can replace live backing data without touching the
    /// values the engine is reading. The held-live-set test above remains the positive control.
    @MainActor
    func testBug3Regression_EngineUsesSnapshotsWhileOwnerSaves() async throws {
        try requireMarker(
            "RUN_BUG3_ENGINE",
            "Bug 3 regression: the suggestion engine must stay clean while its repository saves."
        )
        let container = try Self.makeContainer()
        let setRepo = SetRepository(modelContainer: container)
        let engine = LoadPrescriptionService(
            setRepository: setRepo,
            exerciseRepository: ExerciseRepository(modelContainer: container),
            workoutRepository: WorkoutRepository(modelContainer: container),
            healthProfileRepository: HealthProfileRepository(modelContainer: container)
        )
        let saved = try await Self.saveHeldSets(setRepo, count: 40)

        let baseline = try await engine.estimateBaseE1RM(exerciseId: saved.exerciseId, completedSessionSets: [])
        XCTAssertEqual(
            baseline.source, .recentPerformance,
            "the sets must reach peakAcrossRecentWorkouts, where crash B was reading"
        )

        let stop = LiveModelReproStopFlag()
        let exerciseId = saved.exerciseId
        let reads = Task.detached { () -> Int in
            var calls = 0
            while !stop.isSet {
                _ = try? await engine.estimateBaseE1RM(exerciseId: exerciseId, completedSessionSets: [])
                calls += 1
            }
            return calls
        }
        for round in 0..<Self.rounds {
            let setId = saved.setIds[round % saved.setIds.count]
            try? await setRepo.applyRestDuration(setId: setId, seconds: 60 + (round / saved.setIds.count) % 2)
        }
        stop.set()
        log("engine made \(await reads.value) estimateBaseE1RM calls")
        log("Bug 3 regression (LoadPrescriptionService snapshots) survived \(Self.rounds) saves")
    }

    /// **Control, crash A's shape.** The screen holds the workout `WorkoutService.startWorkout`
    /// saved and returned (`ActiveWorkoutViewModel.workout`) and reads it on main, the getter crash
    /// A faulted in (`excludedExerciseIdsFromProgressionHistory`, via
    /// `workoutProgressionHistorySignature`), while `WorkoutRepository` saves changes to it.
    /// Yields to the writer every few reads, as the real screen's work does. If the repository
    /// runs its saves on main too, the two can't overlap and this survives; crash A's swap ran on
    /// a background thread.
    @MainActor
    func testBug3Control_HeldWorkoutReadOnMainWhileOwnerSaves() async throws {
        try requireMarker(
            "RUN_BUG3_HELD_WORKOUT",
            "Bug 3 control (held workout on main): expected to crash the test runner on iOS 18."
        )
        let workoutRepo = WorkoutRepository(modelContainer: try Self.makeContainer())
        let held = Workout(
            date: Date(),
            startTime: Date(),
            status: .inProgress,
            excludedExerciseIdsFromProgressionHistory: [UUID()]
        )
        try await workoutRepo.save(held)
        let heldId = held.id
        let exerciseId = UUID()

        let stop = LiveModelReproStopFlag()
        let writes = Task.detached {
            for _ in 0..<Self.rounds {
                try? await workoutRepo.setHealthKitUUID(UUID(), forWorkoutId: heldId)
            }
            stop.set()
        }

        var passes = 0
        while !stop.isSet {
            _ = held.excludedExerciseIdsFromProgressionHistory
            _ = held.excludesEntireWorkoutFromProgressionHistory
            _ = held.excludesFromProgressionHistory(exerciseId: exerciseId)
            passes += 1
            if passes.isMultiple(of: 50) { await Task.yield() }
        }
        await writes.value
        log("held-workout reader made \(passes) passes on main")

        controlSurvived("Bug 3 control (held workout read on main while the owner saves)", bugRuntime: 18)
    }

    /// **Discriminator: live record or copy.** The minimal control's load, but the reader asks the
    /// repository for `ChartSetData` copies of the same sets on every pass and reads the same
    /// fields. A copy's contents can't be replaced, so if the crash is the live read this stays
    /// clean on iOS 18.6. The same run also holds a `WorkoutSnapshot` while its owner saves, which
    /// covers the active-workout cache-key path from crash A.
    @MainActor
    func testBug3Discriminator_SnapshotsReadWhileOwnerSaves() async throws {
        try requireMarker(
            "RUN_BUG3_SNAPSHOTS",
            "Bug 3 discriminator: the held-sets control's load with copies instead of live records."
        )
        let setRepo = SetRepository(modelContainer: try Self.makeContainer())
        let saved = try await Self.saveHeldSets(setRepo)

        let reader = LiveModelReproSetReader()
        let stop = LiveModelReproStopFlag()
        async let passes = reader.readSnapshotsUntilStopped(setRepo, workoutId: saved.workoutId, stop: stop)
        await Self.ownerSavesRepeatedly(setRepo, setIds: saved.setIds)
        stop.set()
        log("snapshot reader made \(await passes) passes")

        let workoutRepo = WorkoutRepository(modelContainer: try Self.makeContainer())
        let workout = Workout(date: Date(), startTime: Date(), status: .inProgress)
        try await workoutRepo.save(workout)
        let workoutId = workout.id
        let fetchedSnapshot = try await workoutRepo.fetchWorkoutSummary(byId: workoutId)
        let snapshot = try XCTUnwrap(fetchedSnapshot)
        let workoutStop = LiveModelReproStopFlag()
        let workoutReader = LiveModelReproWorkoutSnapshotReader()
        async let workoutPasses = workoutReader.readUntilStopped(snapshot, stop: workoutStop)
        for _ in 0..<Self.rounds {
            try await workoutRepo.setHealthKitUUID(UUID(), forWorkoutId: workoutId)
        }
        workoutStop.set()
        log("workout-snapshot reader made \(await workoutPasses) passes")
        log("Bug 3 discriminator (snapshots read off main while the owner saves) survived \(Self.rounds) rounds")
    }

    /// Deterministic and single-threaded: when does SwiftData replace a model's
    /// `persistentBackingData`? Prints a table and asserts nothing. The bug-3 controls are built
    /// on its answer, so rerun it if they stop crashing after an OS update.
    @MainActor
    func testBug3Mechanism_WhenIsBackingDataReplaced() async throws {
        try requireMarker("RUN_BUG3_MECHANISM", "Bug 3 mechanism probe: prints when backing data is replaced.")
        let probe = LiveModelReproBackingProbe(modelContainer: try Self.makeContainer())
        for line in try await probe.run() { log("MECHANISM \(line)") }
    }
}

/// Fast, deterministic guards for the value types used by the race regressions.
final class SwiftDataSnapshotBoundaryTests: XCTestCase {
    func testHealthProfileSnapshotCoversEveryStoredProperty() {
        let profile = HealthProfile()
        XCTAssertEqual(
            storedPropertyNames(of: profile),
            Set(Mirror(reflecting: HealthProfileSnapshot(from: profile)).children.compactMap(\.label))
        )
    }

    func testWorkoutSnapshotCoversEveryStoredProperty() {
        let workout = Workout()
        let modelNames = storedPropertyNames(of: workout)
        let snapshotNames = Set(Mirror(reflecting: WorkoutSnapshot(from: workout)).children.compactMap(\.label))
        let aliases: [String: String] = [
            "excludesEntireWorkoutFromProgressionHistory": "excludeFromProgressionHistory",
            "excludedExerciseIdsForProgressionHistory": "excludedExerciseIdsFromProgressionHistory",
        ]
        let covered = Set(snapshotNames.map { aliases[$0] ?? $0 })

        XCTAssertEqual(modelNames.subtracting(covered), [])
        XCTAssertEqual(covered.subtracting(modelNames), ["displayTitle"])
    }

    func testChartSetPerformanceRIRMatchesTheLiveModel() {
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: UUID(),
            reps: 8,
            leftReps: 8,
            rightReps: 8,
            rir: 4,
            leftRIR: 3,
            rightRIR: 1,
            orderInWorkout: 1,
            orderInExercise: 1
        )
        XCTAssertEqual(ChartSetData(from: set).performanceRIR, set.performanceRIR)
    }

    private func storedPropertyNames<T>(of model: T) -> Set<String> {
        Set(
            Mirror(reflecting: model).children
                .compactMap(\.label)
                .filter { !$0.hasPrefix("_$") }
                .map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        )
    }
}

// MARK: - Probes

/// Shared stop signal between a writer and a reader on different threads.
private final class LiveModelReproStopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isSet: Bool { lock.withLock { stopped } }
    func set() { lock.withLock { stopped = true } }
}

/// Owns its context and changes the profile inside it: the shape Phase 1 would give
/// `HealthProfileRepository`. Test-only.
@ModelActor
private actor LiveModelReproProfileOwner {
    private func profile() throws -> HealthProfile {
        if let existing = try modelContext.fetch(FetchDescriptor<HealthProfile>()).first {
            return existing
        }
        let created = HealthProfile()
        modelContext.insert(created)
        return created
    }

    func setTargetReps(_ reps: Int) throws {
        try profile().prescriptionDefaultTargetReps = reps
        try modelContext.save()
    }

    func setTargetRIR(_ rir: Int) throws {
        try profile().prescriptionDefaultTargetRIR = rir
        try modelContext.save()
    }

    func touch() throws {
        try profile().updatedAt = Date()
        try modelContext.save()
    }

    func targetRIR() throws -> Int? {
        try profile().prescriptionDefaultTargetRIR
    }
}

/// Keeps the pre-fix `SettingsService` behaviour as a positive control: fetch a model owned by
/// another actor, mutate it here, then hand it back to save.
private actor LiveModelReproUnsafeProfileWriter {
    func writeRepeatedly(_ repo: HealthProfileRepository, rounds: Int) async throws {
        for round in 0..<rounds {
            let profile = try await repo.fetchOrCreate()
            profile.prescriptionDefaultTargetReps = 5 + round % 8
            profile.prescriptionDefaultTargetRIR = round % 4
            profile.updatedAt = Date()
            try await repo.save(profile)
        }
    }
}

/// A plain actor reading sets, the way `LoadPrescriptionService` does.
private actor LiveModelReproSetReader {
    /// Reads the held live sets field by field until told to stop: the fields
    /// `peakAcrossRecentWorkouts` and `capacityE1RM` read.
    func readUntilStopped(_ sets: [WorkoutSet], stop: LiveModelReproStopFlag) -> Int {
        var passes = 0
        var total = 0.0
        while !stop.isSet {
            for set in sets {
                total += Double(set.prReps) * (set.effectiveWeight ?? set.weight ?? 0)
                total += (set.e1RM ?? 0) + (set.performanceRIR ?? 0)
                total += Double(set.restDurationSeconds ?? 0)
            }
            passes += 1
        }
        return total > 0 ? passes : -passes
    }

    /// The same fields from fresh copies of the same sets, until told to stop.
    func readSnapshotsUntilStopped(_ repo: SetRepository, workoutId: UUID, stop: LiveModelReproStopFlag) async -> Int {
        var passes = 0
        var total = 0.0
        while !stop.isSet {
            let sets = (try? await repo.fetchChartSets(for: workoutId)) ?? []
            for set in sets {
                total += Double(set.prReps) * (set.effectiveWeight ?? set.weight ?? 0)
                total += (set.e1RM ?? 0) + (set.performanceRIR ?? 0)
                total += Double(set.restDurationSeconds ?? 0)
            }
            passes += 1
        }
        return total > 0 ? passes : -passes
    }
}

/// Reads an immutable workout value while the repository repeatedly saves the live row.
private actor LiveModelReproWorkoutSnapshotReader {
    func readUntilStopped(_ workout: WorkoutSnapshot, stop: LiveModelReproStopFlag) -> Int {
        var passes = 0
        var checksum = 0
        while !stop.isSet {
            checksum ^= workout.id.hashValue
            checksum ^= workout.excludedExerciseIdsForProgressionHistory.count
            _ = workout.excludesFromProgressionHistory(exerciseId: UUID())
            passes += 1
        }
        return checksum == Int.min ? -passes : passes
    }
}

/// Runs inside the context it measures, one step at a time: nothing here can race.
@ModelActor
private actor LiveModelReproBackingProbe {
    private func backingId(_ set: WorkoutSet) -> ObjectIdentifier {
        ObjectIdentifier(set.persistentBackingData as AnyObject)
    }

    private func fetchByWorkout(_ workoutId: UUID) throws -> [WorkoutSet] {
        try modelContext.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.workoutId == workoutId },
            sortBy: [SortDescriptor(\.orderInWorkout)]
        ))
    }

    func run() throws -> [String] {
        var out: [String] = []
        let workoutId = UUID()
        let exerciseId = UUID()

        func step(_ label: String, _ set: WorkoutSet, since previous: inout ObjectIdentifier) {
            let now = backingId(set)
            out.append("\(label): backing \(now == previous ? "kept" : "REPLACED") "
                       + "(\(String(describing: type(of: set.persistentBackingData))))")
            previous = now
        }

        // Created in this context, as `SetRepository.create` and `startWorkout` do.
        let held = WorkoutSet(workoutId: workoutId, exerciseId: exerciseId, weight: 100, reps: 5,
                              orderInWorkout: 1, orderInExercise: 1, completed: true)
        var last = backingId(held)
        modelContext.insert(held)
        step("insert", held, since: &last)
        try modelContext.save()
        step("save after insert", held, since: &last)
        let first = try fetchByWorkout(workoutId).first!
        step("first fetch after that save (same instance: \(first === held))", held, since: &last)
        _ = try fetchByWorkout(workoutId)
        step("second fetch", held, since: &last)

        held.restDurationSeconds = 90
        step("change, not saved", held, since: &last)
        _ = try fetchByWorkout(workoutId)
        step("fetch with the change pending", held, since: &last)
        try modelContext.save()
        step("save of the change", held, since: &last)
        _ = try fetchByWorkout(workoutId)
        step("fetch after that save", held, since: &last)

        let other = ModelContext(modelContainer)
        let otherCopy = try other.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )).first!
        otherCopy.restDurationSeconds = 120
        try other.save()
        step("another context saves the row", held, since: &last)
        _ = try fetchByWorkout(workoutId)
        step("fetch after the other save", held, since: &last)

        let seededWorkout = UUID()
        let seeder = ModelContext(modelContainer)
        seeder.insert(WorkoutSet(workoutId: seededWorkout, exerciseId: exerciseId, weight: 50, reps: 5,
                                 orderInWorkout: 1, orderInExercise: 1, completed: true))
        try seeder.save()
        let seeded = try fetchByWorkout(seededWorkout).first!
        var seededLast = backingId(seeded)
        _ = try fetchByWorkout(seededWorkout)
        step("row made by another context, fetched again", seeded, since: &seededLast)
        return out
    }
}

/// Onboarding with no program picked never calls this; it exists to satisfy the initializer.
private struct LiveModelReproNoPrograms: ProgramCatalogServiceProtocol {
    func availablePrograms() throws -> [ProgramSeedDTO] { [] }

    func materialise(programId: String) async throws -> ProgramMaterialisationResult {
        throw CancellationError()
    }
}
