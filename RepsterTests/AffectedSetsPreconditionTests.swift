import XCTest
import SwiftData
@testable import Repster

/// Pins the two facts `applyAffectedSets` currently rests on.
///
/// `ActiveWorkoutViewModel.applyAffectedSets` (:2086) exists to push PR badge changes onto sets
/// *other* than the one just saved. Disabling it entirely leaves every journey green, and the
/// recorded explanation is object identity: `PRService` writes `oldSet.prStatus` on a set it
/// fetched from `SetRepository` (:113, :348, :646), and because that repository is a single
/// `@ModelActor` with one context, it is the very instance the ViewModel holds. The badge
/// reaches the screen without the ViewModel doing anything.
///
/// That explanation was traced statically and believed. This project has a track record of
/// confident structural claims turning out half-true — a grep undercounted `SetService`'s
/// mutations 15 → 24, protocol-signature counting undercounted `Exercise`'s crossings 8 → 18 —
/// so it is measured here instead of argued.
///
/// Two separate questions, deliberately not conflated:
///
///  - **Precondition.** For every entry in `affectedSetIds`, does the set the caller holds
///    *already* carry the new status before `applyAffectedSets` runs? If yes, every assignment
///    in that function is a self-assignment today.
///  - **Suppression.** How often would the "completed sets receive demotions but never
///    promotions" rule actually suppress something, measured against the status each set held
///    *before* the save? The precondition question cannot answer this — by the time
///    `applyAffectedSets` runs the pre-write status is gone.
///
/// The second is what decides whether step 5 is a pure refactor here. Once sets are value
/// types the pre-write status is what the rule compares against, so a non-zero count means the
/// conversion changes what the user sees, and collides with `assertScreenMatchesStore`.
///
/// This test drives `SetService` directly rather than the ViewModel, holding sets exactly as
/// `setsByExercise` does — same instances, same actor, without needing to instrument
/// production code.
@MainActor
final class AffectedSetsPreconditionTests: XCTestCase {

    // MARK: - Harness

    private struct Stack {
        let container: ModelContainer
        let exerciseRepo: ExerciseRepository
        let workoutRepo: WorkoutRepository
        let setRepo: SetRepository
        let setService: SetService
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
            exerciseRepo: exerciseRepo,
            workoutRepo: workoutRepo,
            setRepo: setRepo,
            setService: setService
        )
    }

    /// Verbatim copy of `ActiveWorkoutViewModel.isStatusUpgrade` (:2111), which is private.
    /// Duplicated deliberately: the rule under measurement has to be stated here to be
    /// measured, and step 5 extracts it into one shared implementation anyway.
    private func isStatusUpgrade(from old: CachedPRStatus?, to new: CachedPRStatus?) -> Bool {
        func rank(_ status: CachedPRStatus?) -> Int {
            switch status {
            case .current: return 3
            case .matched: return 2
            case .dominated, .previous: return 1
            case nil: return 0
            }
        }
        return rank(new) > rank(old)
    }

    /// What the ViewModel holds: live sets for one workout, fetched from the repository.
    private func heldSets(_ stack: Stack, workoutId: UUID) async throws -> [WorkoutSet] {
        try await stack.setRepo.fetchSets(for: workoutId)
    }

    /// Accumulates both measurements across every scenario.
    private final class Findings {
        var entriesSeen = 0
        var preconditionMismatches: [String] = []
        var wouldSuppress: [String] = []
    }

    /// Run `action`, then measure the two properties against the sets the caller already holds.
    ///
    /// Takes a closure rather than a set so the paths that are *not* `save` can be measured —
    /// the promotion case the no-upgrade rule exists for is unreachable through `save`, because
    /// a rep bucket only returns to the frontier when a dominating record goes away.
    @discardableResult
    private func measure(
        _ stack: Stack,
        workoutId: UUID,
        into findings: Findings,
        scenario: String,
        action: () async throws -> [UUID: CachedPRStatus?]
    ) async throws -> [UUID: CachedPRStatus?] {
        let held = try await heldSets(stack, workoutId: workoutId)
        let statusBefore = Dictionary(uniqueKeysWithValues: held.map { ($0.id, $0.prStatus) })
        let completedBefore = Dictionary(uniqueKeysWithValues: held.map { ($0.id, $0.completed) })
        let heldById = Dictionary(uniqueKeysWithValues: held.map { ($0.id, $0) })

        let affected = try await action()

        for (setId, newStatus) in affected {
            guard let instance = heldById[setId] else { continue }
            findings.entriesSeen += 1

            if instance.prStatus != newStatus {
                findings.preconditionMismatches.append(
                    "\(scenario): set \(setId.uuidString.prefix(8)) held "
                        + "\(String(describing: instance.prStatus)) but the pipeline reported "
                        + "\(String(describing: newStatus))"
                )
            }

            if completedBefore[setId] == true,
               isStatusUpgrade(from: statusBefore[setId] ?? nil, to: newStatus) {
                findings.wouldSuppress.append(
                    "\(scenario): set \(setId.uuidString.prefix(8)) "
                        + "\(String(describing: statusBefore[setId] ?? nil)) -> "
                        + "\(String(describing: newStatus))"
                )
            }
        }
        return affected
    }

    /// Save `set`, then measure the two properties against the sets the caller already holds.
    private func saveAndMeasure(
        _ stack: Stack,
        set: WorkoutSet,
        workoutId: UUID,
        into findings: Findings,
        scenario: String
    ) async throws {
        try await measure(stack, workoutId: workoutId, into: findings, scenario: scenario) {
            try await stack.setService.save(set).prResult.affectedSetIds
        }
    }

    private func makeSet(
        workoutId: UUID,
        exerciseId: UUID,
        weight: Double,
        reps: Int,
        order: Int
    ) -> WorkoutSet {
        WorkoutSet(
            workoutId: workoutId,
            exerciseId: exerciseId,
            weight: weight,
            reps: reps,
            orderInWorkout: order,
            orderInExercise: order,
            completed: true
        )
    }

    // MARK: - The measurement

    /// Exercises each site in `PRService` that contributes to `affectedSetIds`, and measures
    /// both properties across all of them.
    func testAffectedSetEntriesArriveAlreadyAppliedToTheHeldInstances() async throws {
        let stack = try makeStack()
        let exercise = Exercise(
            name: "Flat Barbell Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            weightIncrement: 2.5
        )
        try await stack.exerciseRepo.save(exercise)

        let workout = Workout(date: Date(), status: .inProgress)
        try await stack.workoutRepo.save(workout)

        let findings = Findings()
        var order = 0
        func nextOrder() -> Int { order += 1; return order }

        // 1. First set at 5 reps — establishes a PR with no affected sets.
        try await saveAndMeasure(
            stack,
            set: makeSet(workoutId: workout.id, exerciseId: exercise.id, weight: 100, reps: 5, order: nextOrder()),
            workoutId: workout.id,
            into: findings,
            scenario: "first PR"
        )

        // 2. Heavier at the same reps — demotes the old owner (PRService :113/:115).
        try await saveAndMeasure(
            stack,
            set: makeSet(workoutId: workout.id, exerciseId: exercise.id, weight: 120, reps: 5, order: nextOrder()),
            workoutId: workout.id,
            into: findings,
            scenario: "beats existing PR"
        )

        // 3. A heavier set at *more* reps — the 5-rep record is no longer on the suffix-max
        //    frontier, so the frontier recompute demotes its owner (PRService :646/:648).
        try await saveAndMeasure(
            stack,
            set: makeSet(workoutId: workout.id, exerciseId: exercise.id, weight: 130, reps: 8, order: nextOrder()),
            workoutId: workout.id,
            into: findings,
            scenario: "higher-rep PR dominates the 5-rep bucket"
        )

        // 4. Now beat the 5-rep bucket hard enough to put it back on the frontier — the
        //    promotion path, and the one the no-upgrade rule is written for.
        try await saveAndMeasure(
            stack,
            set: makeSet(workoutId: workout.id, exerciseId: exercise.id, weight: 200, reps: 5, order: nextOrder()),
            workoutId: workout.id,
            into: findings,
            scenario: "5-rep bucket returns to the frontier"
        )

        // 5. A matching set in a different workout, so the `.matched` rank participates.
        let secondWorkout = Workout(date: Date().addingTimeInterval(3600), status: .inProgress)
        try await stack.workoutRepo.save(secondWorkout)
        try await saveAndMeasure(
            stack,
            set: makeSet(workoutId: secondWorkout.id, exerciseId: exercise.id, weight: 200, reps: 5, order: 1),
            workoutId: secondWorkout.id,
            into: findings,
            scenario: "matches the current PR from another workout"
        )

        // 6. The promotion path. `save` cannot reach it: a rep bucket only returns to the
        //    suffix-max frontier when a dominating record *goes away*, which needs an
        //    uncomplete, a delete or an edit downwards. Build a dominated bucket, then remove
        //    the record dominating it.
        let third = Workout(date: Date().addingTimeInterval(7200), status: .inProgress)
        try await stack.workoutRepo.save(third)

        let lowRep = makeSet(workoutId: third.id, exerciseId: exercise.id, weight: 300, reps: 3, order: 1)
        _ = try await stack.setService.save(lowRep)

        let dominating = makeSet(workoutId: third.id, exerciseId: exercise.id, weight: 400, reps: 6, order: 2)
        _ = try await stack.setService.save(dominating)

        // The 3-rep bucket should now be dominated by the heavier 6-rep record.
        let afterDomination = try await heldSets(stack, workoutId: third.id)
        XCTAssertEqual(
            afterDomination.first(where: { $0.id == lowRep.id })?.prStatus,
            .dominated,
            "setup did not produce a dominated bucket — scenario 6 measures nothing"
        )

        // Uncompleting the dominating set frees the 3-rep bucket, promoting a *completed* set.
        // This is exactly the case `isStatusUpgrade` was written to suppress.
        try await measure(
            stack,
            workoutId: third.id,
            into: findings,
            scenario: "uncomplete frees a dominated bucket"
        ) {
            try await stack.setService.uncomplete(dominating, previousContribution: nil)
                .prResult.affectedSetIds
        }

        // The measurement is worthless if no scenario produced an affected set.
        XCTAssertGreaterThan(
            findings.entriesSeen,
            0,
            "No affectedSetIds entries were produced — this test measured nothing. Either the "
                + "scenarios stopped exercising the PR pipeline or PRService changed shape."
        )

        XCTAssertEqual(
            findings.preconditionMismatches,
            [],
            "An affectedSetIds entry did NOT arrive already applied to the instance the caller "
                + "holds. The 'object identity carries the badge' model behind step 5's plan is "
                + "wrong, and applyAffectedSets is doing real work today:\n"
                + findings.preconditionMismatches.joined(separator: "\n")
        )

        // Recorded rather than asserted-to-zero: this is the number step 5 has to account for.
        // If it is 0, the no-promotion rule suppresses nothing today and converting sets to
        // value types is behaviour-preserving here. If it is not 0, the conversion changes what
        // the user sees and `assertScreenMatchesStore` will fire on those cases.
        print("PROBE affectedSetIds entries observed: \(findings.entriesSeen)")
        print("PROBE entries the no-promotion rule would suppress: \(findings.wouldSuppress.count)")
        for line in findings.wouldSuppress { print("PROBE   \(line)") }
    }

    /// Deleting a PR owner promotes another set with **no channel to the ViewModel at all**.
    ///
    /// `SetService.delete` computes `prService.handleDeletion(...)` and discards it (`_ =`,
    /// SetService.swift:338) — it returns `Void`. `ActiveWorkoutViewModel.deleteSet` (:670)
    /// consequently never calls `applyAffectedSets`. So the promoted set's badge reaches the
    /// screen *only* because `PRService` wrote it on the instance the ViewModel holds
    /// (`winner.prStatus = winnerStatus`, PRService.swift:720).
    ///
    /// This is a strictly worse case than `applyAffectedSets`: there the channel exists and is
    /// merely redundant, here it does not exist. Step 5 has to add one — `delete` must return
    /// its `PREvaluationResult` — or deleting a PR-owning set will leave a stale badge on
    /// screen until relaunch.
    func testDeletingAPROwnerPromotesAnotherSetThroughIdentityAlone() async throws {
        let stack = try makeStack()
        let exercise = Exercise(
            name: "Flat Barbell Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            weightIncrement: 2.5
        )
        try await stack.exerciseRepo.save(exercise)
        let workout = Workout(date: Date(), status: .inProgress)
        try await stack.workoutRepo.save(workout)

        let dominated = makeSet(workoutId: workout.id, exerciseId: exercise.id, weight: 300, reps: 3, order: 1)
        _ = try await stack.setService.save(dominated)
        let dominating = makeSet(workoutId: workout.id, exerciseId: exercise.id, weight: 400, reps: 6, order: 2)
        _ = try await stack.setService.save(dominating)

        let held = try await heldSets(stack, workoutId: workout.id)
        let watched = try XCTUnwrap(held.first(where: { $0.id == dominated.id }))
        XCTAssertEqual(watched.prStatus, .dominated, "setup did not produce a dominated bucket")
        XCTAssertTrue(watched.completed)

        // The ViewModel gets nothing back from this call — `delete` returns Void.
        try await stack.setService.delete(dominating)

        XCTAssertEqual(
            watched.prStatus,
            .current,
            "the held instance was promoted in place by PRService, with nothing returned to "
                + "the caller. If this ever stops being true the delete path silently loses "
                + "badge updates today, not just after step 5."
        )

        let committed = try await stack.setRepo.fetchChartSets(for: workout.id)
        XCTAssertEqual(
            committed.first(where: { $0.id == dominated.id })?.prStatus,
            .current,
            "the promotion is persisted, so a relaunch shows it — which is why this gap is "
                + "invisible today"
        )
    }
}
