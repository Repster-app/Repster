import XCTest
import SwiftData
@testable import Repster

/// Before/after equivalence on a **real** training history.
///
/// Step 5 is meant to be a pure refactor: same behaviour, different types. The strongest
/// available check on that claim is to render every affected surface from a real store before
/// the conversion, do the conversion, render again, and diff.
///
/// Why real data rather than fixtures: all five misses in the 2026-08-12 mutation sweep were
/// cases the fixtures did not contain. A real history contains what it contains — bodyweight
/// exercises where `effectiveWeight != weight`, sets logged before a field existed, exercises
/// whose tracking type changed, unilateral sets, abandoned workouts, empty sets. Nobody thinks
/// to write those into a fixture; they are simply there.
///
/// **How to use it**
///
/// 1. Put a backup at `RepsterTests/Fixtures/Local/real-history.repsterbackup`. The directory
///    is gitignored — this repo is public and a backup is real personal training data. Without
///    it every test here skips, so a clean clone stays green.
/// 2. On the current code, run this. With no baseline present it writes one and skips.
/// 3. Make the change.
/// 4. Run it again. It fails on any difference and writes the actual output next to the
///    baseline for diffing.
///
/// **What it does not do:** it asserts *unchanged*, never *correct*. If today's behaviour is
/// wrong, this pins the wrong behaviour — that is what the journey tests are for. And it is
/// deliberately not a CI gate: the fixture is local and the history grows over time.
final class RealDataDifferentialTests: XCTestCase {

    private static let fixtureDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Local")

    private static var backupURL: URL {
        fixtureDirectory.appendingPathComponent("real-history.repsterbackup")
    }
    private static var baselineURL: URL {
        fixtureDirectory.appendingPathComponent("screen-baseline.txt")
    }
    private static var actualURL: URL {
        fixtureDirectory.appendingPathComponent("screen-actual.txt")
    }

    // MARK: - Stack

    private struct Stack {
        let container: ModelContainer
        let exerciseRepo: ExerciseRepository
        let workoutRepo: WorkoutRepository
        let setRepo: SetRepository
        let exerciseStatsRepo: ExerciseStatsRepository
        let backupService: WorkoutHistoryBackupService
    }

    private func makeStack() throws -> Stack {
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, WorkoutSet.self, ExerciseStats.self,
            PerformanceRecord.self, BodyweightEntry.self, HealthProfile.self,
            FatigueObservation.self, FatigueLearningSetAudit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let exerciseRepo = ExerciseRepository(modelContainer: container)
        let workoutRepo = WorkoutRepository(modelContainer: container)
        let setRepo = SetRepository(modelContainer: container)
        let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
        let performanceRecordRepo = PerformanceRecordRepository(modelContainer: container)
        let healthProfileRepo = HealthProfileRepository(modelContainer: container)

        let statsService = StatsService(
            exerciseStatsRepository: exerciseStatsRepo,
            setRepository: setRepo,
            exerciseRepository: exerciseRepo,
            healthProfileRepository: healthProfileRepo,
            performanceRecordRepository: performanceRecordRepo
        )
        let prService = PRService(
            performanceRecordRepository: performanceRecordRepo,
            setRepository: setRepo,
            workoutRepository: workoutRepo,
            healthProfileRepository: healthProfileRepo,
            exerciseRepository: exerciseRepo
        )
        return Stack(
            container: container,
            exerciseRepo: exerciseRepo,
            workoutRepo: workoutRepo,
            setRepo: setRepo,
            exerciseStatsRepo: exerciseStatsRepo,
            backupService: WorkoutHistoryBackupService(
                statsService: statsService,
                prService: prService,
                modelContainer: container
            )
        )
    }

    // MARK: - Rendering
    //
    // Everything below is deterministic and sorted, so a diff points at a behaviour change
    // rather than at iteration order.

    private func renderSurfaces(_ stack: Stack) async throws -> String {
        var lines: [String] = []

        let workouts = try await stack.workoutRepo.fetchAllWorkoutSummaries(limit: nil, offset: nil)
            .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
        let exercises = try await stack.exerciseRepo.fetchAllChartExercises()
        let exercisesById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        lines.append("# WORKOUT LIST (\(workouts.count))")
        for workout in workouts {
            lines.append(
                "workout \(Self.stableDate(workout.date)) status=\(workout.status) "
                    + "title=\(workout.displayTitle) duration=\(workout.duration.map(String.init) ?? "-")"
            )
        }

        lines.append("")
        lines.append("# WORKOUT DETAIL — every set, as the detail card renders it")
        for workout in workouts {
            let sets = try await stack.setRepo.fetchChartSets(for: workout.id)
                .sorted { ($0.orderInWorkout, $0.id.uuidString) < ($1.orderInWorkout, $1.id.uuidString) }
            guard !sets.isEmpty else { continue }
            lines.append("-- \(Self.stableDate(workout.date)) --")

            for set in sets {
                let exercise = exercisesById[set.exerciseId]
                let name = exercise?.name ?? "<missing exercise>"
                let fields = (exercise?.trackingType.readOnlyHistoryFields ?? []).map { field in
                    "\(field)=" + WorkoutSetPerformanceFormatter.fieldDisplay(
                        for: field,
                        set: set,
                        exercise: exercise,
                        unitPreference: .metric
                    ).text
                }
                lines.append(
                    "  [\(set.orderInExercise)] \(name) type=\(set.setType) "
                        + "completed=\(set.completed) note=\(set.hasNote) "
                        + fields.joined(separator: " ")
                )
            }

            // Badges are tallied per exercise rather than printed per set, deliberately.
            //
            // Among sets with identical weight and reps, *which* one holds the badge is not
            // stable across runs: `PRService.rebuildAll()` assigns it in fetch order, so two
            // recordings of the same untouched store disagree on 216 lines. Tallying keeps the
            // check meaningful — a badge that disappears, or a demotion that stops happening,
            // still changes the counts — while a swap between tied sets does not register.
            var badgeTallies: [String: [String: Int]] = [:]
            for set in sets {
                let name = exercisesById[set.exerciseId]?.name ?? "<missing exercise>"
                let badge = CachedPRStatus.effectiveStatus(for: set, among: sets)
                let key = badge.map(String.init(describing:)) ?? "none"
                badgeTallies[name, default: [:]][key, default: 0] += 1
            }
            for name in badgeTallies.keys.sorted() {
                let counts = badgeTallies[name]!
                let rendered = counts.keys.sorted().map { "\($0)=\(counts[$0]!)" }.joined(separator: " ")
                lines.append("  ~ badges \(name): \(rendered)")
            }

            let summary = WorkoutAggregateSummary.summarize(sets: sets, exercisesById: exercisesById)
            lines.append("  = summary \(summary)")
        }

        lines.append("")
        lines.append("# EXERCISE STATS")
        for exercise in exercises.sorted(by: { $0.name < $1.name }) {
            guard let stats = try await stack.exerciseStatsRepo.fetch(for: exercise.id) else { continue }
            lines.append(
                "\(exercise.name): workouts=\(stats.totalWorkouts) sets=\(stats.totalSets) "
                    + "reps=\(stats.totalReps) volume=\(Self.stableNumber(stats.totalVolume)) "
                    + "maxWeight=\(Self.stableNumber(stats.maxWeight)) "
                    + "bestE1RM=\(Self.stableNumber(stats.bestE1RM))"
            )
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Dates are rendered at day resolution: the archive stores absolute timestamps, so this
    /// stays stable across runs while still catching a reordering.
    private static func stableDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Fixed precision, so floating-point noise cannot masquerade as a behaviour change.
    private static func stableNumber(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    // MARK: - The differential

    func testRenderedSurfacesMatchTheRecordedBaseline() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: Self.backupURL.path),
            "No local history fixture. Drop a .repsterbackup at RepsterTests/Fixtures/Local/"
                + "real-history.repsterbackup to enable the differential (gitignored — the repo is public)."
        )

        let stack = try makeStack()
        let data = try Data(contentsOf: Self.backupURL)
        let restored = try await stack.backupService.restoreBackup(data: data)

        let rendered = try await renderSurfaces(stack)

        guard FileManager.default.fileExists(atPath: Self.baselineURL.path) else {
            try rendered.write(to: Self.baselineURL, atomically: true, encoding: .utf8)
            throw XCTSkip(
                "Baseline recorded from \(restored.setsRestored) sets across "
                    + "\(restored.workoutsRestored) workouts → \(Self.baselineURL.lastPathComponent). "
                    + "Make your change, then run this again to diff against it."
            )
        }

        let baseline = try String(contentsOf: Self.baselineURL, encoding: .utf8)
        guard rendered != baseline else { return }

        try? rendered.write(to: Self.actualURL, atomically: true, encoding: .utf8)

        let baselineLines = baseline.components(separatedBy: "\n")
        let renderedLines = rendered.components(separatedBy: "\n")
        var differences: [String] = []
        for index in 0..<max(baselineLines.count, renderedLines.count) {
            let before = index < baselineLines.count ? baselineLines[index] : "<missing>"
            let after = index < renderedLines.count ? renderedLines[index] : "<missing>"
            guard before != after else { continue }
            differences.append("line \(index + 1):\n  before: \(before)\n  after:  \(after)")
            if differences.count == 10 { break }
        }

        XCTFail(
            "Rendered output changed against the recorded baseline "
                + "(\(restored.setsRestored) sets). Full output written to "
                + "\(Self.actualURL.lastPathComponent).\n"
                + differences.joined(separator: "\n")
        )
    }

    /// Records a fresh baseline on demand, for when a change to the output *is* intended.
    ///
    /// Gated by a **marker file**, not an environment variable. This originally read
    /// `TEST_RUNNER_RECORD_BASELINE`, which cannot work in this project — see the note in
    /// `CrossContextRaceTests`: the `TEST_RUNNER_` prefix does not reach the test process, so
    /// this test silently skipped on every run while reporting success. That left the only
    /// documented way to accept an intended change permanently broken.
    ///
    /// ```
    /// touch RepsterTests/Fixtures/Local/RECORD_BASELINE
    /// xcodebuild test -project Repster.xcodeproj -scheme Repster \
    ///   -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    ///   -only-testing:RepsterTests/RealDataDifferentialTests/testRecordBaseline
    /// ```
    ///
    /// The marker is consumed, so a forgotten file cannot silently re-record a later run and
    /// erase the very regression the differential exists to catch.
    func testRecordBaseline() async throws {
        let marker = Self.fixtureDirectory.appendingPathComponent("RECORD_BASELINE")
        let requested = FileManager.default.fileExists(atPath: marker.path)
        if requested { try? FileManager.default.removeItem(at: marker) }

        try XCTSkipUnless(
            requested,
            "Overwrites the differential baseline. Run deliberately: "
                + "touch RepsterTests/Fixtures/Local/RECORD_BASELINE"
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: Self.backupURL.path),
            "No local history fixture."
        )

        let stack = try makeStack()
        let data = try Data(contentsOf: Self.backupURL)
        _ = try await stack.backupService.restoreBackup(data: data)
        let rendered = try await renderSurfaces(stack)
        try rendered.write(to: Self.baselineURL, atomically: true, encoding: .utf8)
        print("Baseline rewritten: \(Self.baselineURL.path)")
    }
}
