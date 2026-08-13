import XCTest
import SwiftData
@testable import Repster

/// Guards the latency budget the step 5 design depends on.
///
/// Step 5 replaces the live `WorkoutSet` the set table renders with a value type, which means
/// the row updates only *after* `SetService.save()` returns. That is only acceptable because
/// the pipeline is fast: measured against a real 579-workout / 11,785-set history on
/// 2026-08-13, `save()` ran at a **3.5 ms** median for a typical set and **15.7 ms** for one
/// that sets a new PR (see STEP5_SCOPE_AND_TEST_STRATEGY.md §1.2).
///
/// Nothing enforced that. Someone adding a fetch or a rebuild to the logging path would
/// silently spend the budget, and the design decision would quietly stop being true. So this
/// generates a store of realistic shape and asserts the pipeline stays in the same order of
/// magnitude.
///
/// The thresholds are deliberately loose — roughly 10x the measured medians. This is here to
/// catch "someone put a `rebuildAll` in the save path", not to police 20% drift, which on a
/// shared CI machine would only produce flakes.
///
/// The real history that calibrated these lives at `RepsterTests/Fixtures/Local/` and is
/// gitignored — the repo is public. `RealDataDifferentialTests` uses it when present.
final class PipelinePerformanceTests: XCTestCase {

    /// Loose enough to survive a noisy machine, tight enough to catch an order of magnitude.
    private static let typicalSaveBudgetSeconds: TimeInterval = 0.060
    private static let prSaveBudgetSeconds: TimeInterval = 0.150

    private struct Stack {
        let container: ModelContainer
        let setService: SetService
        let setRepo: SetRepository
        let workoutRepo: WorkoutRepository
        let statsService: StatsService
        let prService: PRService
    }

    @MainActor
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
        let bodyweightRepo = BodyweightEntryRepository(modelContainer: container)
        let healthProfileRepo = HealthProfileRepository(modelContainer: container)
        let fatigueObservationRepo = FatigueObservationRepository(modelContainer: container)
        let fatigueLearningAuditRepo = FatigueLearningSetAuditRepository(modelContainer: container)

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
        let setService = SetService(
            setRepository: setRepo,
            exerciseRepository: exerciseRepo,
            bodyweightEntryRepository: bodyweightRepo,
            healthProfileRepository: healthProfileRepo,
            prService: prService,
            statsService: statsService,
            fatigueLearningService: FatigueLearningService(
                observationRepo: fatigueObservationRepo,
                exerciseRepo: exerciseRepo,
                healthProfileRepo: healthProfileRepo,
                auditRepo: fatigueLearningAuditRepo
            )
        )
        return Stack(
            container: container,
            setService: setService,
            setRepo: setRepo,
            workoutRepo: workoutRepo,
            statsService: statsService,
            prService: prService
        )
    }

    /// Builds a store shaped like a real training history: many exercises, one of them heavily
    /// trained. Inserted directly through a context — going through the pipeline would take
    /// minutes and is not what is being measured.
    ///
    /// The number that matters is the **depth of the busiest exercise**, not the row total:
    /// PR evaluation and the stats delta both scan one exercise's history. The seed below gives
    /// the busiest exercise ~750 sets, against 732 in the real history that calibrated the
    /// thresholds — so the shape is faithful where it counts, at a fraction of the rows.
    private func seedHistory(
        _ stack: Stack,
        exerciseCount: Int,
        workoutCount: Int,
        setsPerExercisePerWorkout: Int,
        busiestExerciseExtraSets: Int
    ) throws -> (busiestExerciseId: UUID, totalSets: Int) {
        let context = ModelContext(stack.container)
        context.autosaveEnabled = false

        var exerciseIds: [UUID] = []
        for index in 0..<exerciseCount {
            let exercise = Exercise(
                name: "Exercise \(index)",
                equipmentType: .barbell,
                trackingType: .weightReps,
                primaryMuscle: "chest",
                weightIncrement: 2.5
            )
            context.insert(exercise)
            exerciseIds.append(exercise.id)
        }
        let busiest = exerciseIds[0]

        var totalSets = 0
        var order = 0
        for workoutIndex in 0..<workoutCount {
            let date = Date().addingTimeInterval(-Double(workoutIndex) * 86_400)
            let workout = Workout(date: date, status: .completed)
            context.insert(workout)

            // Every workout trains a slice of the library, plus the busiest exercise.
            var exercisesToday = [busiest]
            exercisesToday.append(contentsOf: exerciseIds.dropFirst().shuffled().prefix(3))

            for exerciseId in exercisesToday {
                let reps = setsPerExercisePerWorkout
                    + (exerciseId == busiest ? busiestExerciseExtraSets : 0)
                for setIndex in 0..<reps {
                    order += 1
                    let weight = Double(60 + (workoutIndex % 40) + setIndex)
                    let set = WorkoutSet(
                        workoutId: workout.id,
                        exerciseId: exerciseId,
                        date: date,
                        weight: weight,
                        effectiveWeight: weight,
                        reps: 5,
                        orderInWorkout: order,
                        orderInExercise: setIndex + 1,
                        completed: true
                    )
                    context.insert(set)
                    totalSets += 1
                }
            }
        }
        try context.save()
        return (busiest, totalSets)
    }

    private func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    @MainActor
    func testLoggingPipelineStaysWithinItsLatencyBudget() async throws {
        let stack = try makeStack()
        let seeded = try seedHistory(
            stack,
            exerciseCount: 20,
            workoutCount: 150,
            setsPerExercisePerWorkout: 3,
            busiestExerciseExtraSets: 2
        )
        // Derived state has to exist, or PR evaluation and the stats delta do no real work.
        try await stack.statsService.rebuildAll()
        try await stack.prService.rebuildAll()

        let workout = Workout(date: Date(), status: .inProgress)
        try await stack.workoutRepo.save(workout)

        func timedSave(weight: Double, order: Int) async throws -> TimeInterval {
            let set = WorkoutSet(
                workoutId: workout.id,
                exerciseId: seeded.busiestExerciseId,
                weight: weight,
                reps: 5,
                orderInWorkout: order,
                orderInExercise: order,
                completed: true
            )
            let start = Date()
            _ = try await stack.setService.save(set)
            return Date().timeIntervalSince(start)
        }

        _ = try await timedSave(weight: 60, order: 1)  // warm-up: first-call costs are not the budget

        var typical: [TimeInterval] = []
        for index in 2...8 {
            typical.append(try await timedSave(weight: 60, order: index))
        }

        var prSetting: [TimeInterval] = []
        for index in 9...13 {
            prSetting.append(try await timedSave(weight: 500 + Double(index), order: index))
        }

        let typicalMedian = median(typical)
        let prMedian = median(prSetting)

        // Printed so a regression run shows how far it drifted, not just that it failed.
        print("PERF typical save median: \(String(format: "%.1f", typicalMedian * 1000)) ms "
            + "(budget \(Int(Self.typicalSaveBudgetSeconds * 1000)) ms, \(seeded.totalSets) sets in store)")
        print("PERF new-PR save median:  \(String(format: "%.1f", prMedian * 1000)) ms "
            + "(budget \(Int(Self.prSaveBudgetSeconds * 1000)) ms)")

        XCTAssertLessThan(
            typicalMedian,
            Self.typicalSaveBudgetSeconds,
            "the logging pipeline got an order of magnitude slower — step 5 awaits this before "
                + "the row updates, so this is a latency budget, not a nicety"
        )
        XCTAssertLessThan(
            prMedian,
            Self.prSaveBudgetSeconds,
            "the PR path got an order of magnitude slower"
        )
    }
}
