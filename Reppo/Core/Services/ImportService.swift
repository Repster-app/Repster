import Foundation
import SwiftData

actor ImportService: ImportServiceProtocol {

    // MARK: - Dependencies

    private let exerciseRepo: any ExerciseRepositoryProtocol
    private let workoutRepo: any WorkoutRepositoryProtocol
    private let bodyweightRepo: any BodyweightEntryRepositoryProtocol
    private let healthProfileRepo: any HealthProfileRepositoryProtocol
    private let prService: any PRServiceProtocol
    private let statsService: any StatsServiceProtocol
    private let modelContainer: ModelContainer

    // MARK: - Constants

    private let batchSize = 500
    private let expectedHeaders = [
        "Date", "Exercise", "Category", "Weight (kg)", "Weight (lbs)",
        "Reps", "Distance", "Distance Unit", "Time", "Notes", "Kind"
    ]

    // MARK: - Init

    init(
        exerciseRepo: any ExerciseRepositoryProtocol,
        workoutRepo: any WorkoutRepositoryProtocol,
        bodyweightRepo: any BodyweightEntryRepositoryProtocol,
        healthProfileRepo: any HealthProfileRepositoryProtocol,
        prService: any PRServiceProtocol,
        statsService: any StatsServiceProtocol,
        modelContainer: ModelContainer
    ) {
        self.exerciseRepo = exerciseRepo
        self.workoutRepo = workoutRepo
        self.bodyweightRepo = bodyweightRepo
        self.healthProfileRepo = healthProfileRepo
        self.prService = prService
        self.statsService = statsService
        self.modelContainer = modelContainer
    }

    // MARK: - ImportServiceProtocol

    nonisolated func previewCSV(data: Data) throws -> CSVParser.PreviewResult {
        try CSVParser.parsePreview(data: data)
    }

    nonisolated func importCSV(data: Data) -> AsyncStream<ImportProgress> {
        AsyncStream { continuation in
            Task {
                await self.performImport(data: data, continuation: continuation)
            }
        }
    }

    // MARK: - Validated Row

    private struct ValidatedRow {
        let date: Date
        let exerciseName: String
        let category: String?
        let weightKg: Double?
        let reps: Int?
        let distance: Double?
        let distanceUnit: String?
        let durationSeconds: Int?
        let notes: String?
        let kind: String?
    }

    // MARK: - Header Validation

    private func validateHeader(_ headers: [String]) throws {
        let normalized = headers.map { $0.trimmingCharacters(in: .whitespaces) }
        guard normalized.count == expectedHeaders.count else {
            throw ImportError.invalidHeader(expected: expectedHeaders, got: normalized)
        }
        for (expected, actual) in zip(expectedHeaders, normalized) {
            guard expected.lowercased() == actual.lowercased() else {
                throw ImportError.invalidHeader(expected: expectedHeaders, got: normalized)
            }
        }
    }

    // MARK: - Row Validation

    private func validateRow(_ fields: [String], rowNumber: Int) -> Result<ValidatedRow, CSVParser.ValidationError> {
        guard fields.count == expectedHeaders.count else {
            return .failure(.init(rowNumber: rowNumber, reason: "Expected \(expectedHeaders.count) columns, found \(fields.count)"))
        }

        // Column 0: Date (REQUIRED)
        let dateStr = fields[0].trimmingCharacters(in: .whitespaces)
        guard !dateStr.isEmpty else {
            return .failure(.init(rowNumber: rowNumber, reason: "Missing date"))
        }
        let dateStyle = Date.ISO8601FormatStyle()
            .year()
            .month()
            .day()
            .dateSeparator(.dash)
        guard let date = try? dateStyle.parse(dateStr) else {
            return .failure(.init(rowNumber: rowNumber, reason: "Invalid date format: '\(dateStr)'. Expected yyyy-MM-dd."))
        }

        // Column 1: Exercise (REQUIRED)
        let exerciseName = fields[1].trimmingCharacters(in: .whitespaces)
        guard !exerciseName.isEmpty else {
            return .failure(.init(rowNumber: rowNumber, reason: "Missing exercise name"))
        }

        // Column 2: Category (optional)
        let category = fields[2].trimmingCharacters(in: .whitespaces)

        // Column 3: Weight (kg) (optional)
        let weightStr = fields[3].trimmingCharacters(in: .whitespaces)
        let weightKg = weightStr.isEmpty ? nil : Double(weightStr)

        // Column 4: Weight (lbs) — IGNORED per FR-009

        // Column 5: Reps (optional)
        let repsStr = fields[5].trimmingCharacters(in: .whitespaces)
        let reps = repsStr.isEmpty ? nil : Int(repsStr)

        // Column 6: Distance (optional)
        let distStr = fields[6].trimmingCharacters(in: .whitespaces)
        let distance = distStr.isEmpty ? nil : Double(distStr)

        // Column 7: Distance Unit (optional)
        let distUnit = fields[7].trimmingCharacters(in: .whitespaces)

        // Column 8: Time (optional)
        let timeStr = fields[8].trimmingCharacters(in: .whitespaces)
        let duration = timeStr.isEmpty ? nil : Int(timeStr)

        // Column 9: Notes (optional)
        let notes = fields[9].trimmingCharacters(in: .whitespaces)

        // Column 10: Kind (optional)
        let kind = fields[10].trimmingCharacters(in: .whitespaces)

        // Must have at least one data value
        let hasWeight = weightKg != nil && weightKg! > 0
        let hasReps = reps != nil && reps! > 0
        let hasDuration = duration != nil && duration! > 0
        let hasDistance = distance != nil && distance! > 0
        let hasData = (hasWeight && hasReps) || hasDuration || hasDistance

        guard hasData else {
            return .failure(.init(rowNumber: rowNumber, reason: "Row has no data values (need weight+reps, duration, or distance)"))
        }

        return .success(ValidatedRow(
            date: date,
            exerciseName: exerciseName,
            category: category.isEmpty ? nil : category,
            weightKg: weightKg,
            reps: reps,
            distance: distance,
            distanceUnit: distUnit.isEmpty ? nil : distUnit,
            durationSeconds: duration,
            notes: notes.isEmpty ? nil : notes,
            kind: kind.isEmpty ? nil : kind
        ))
    }

    // MARK: - Kind → TrackingType Mapping

    private func inferTrackingType(from kind: String?) -> TrackingType {
        switch kind?.lowercased() {
        case "wr":  return .weightReps
        case "d":   return .duration
        case "wd":  return .weightDistance
        case "wrd": return .weightRepsDuration
        default:    return .weightReps
        }
    }

    // MARK: - Exercise Matching

    private func buildExerciseLookup() async throws -> [String: Exercise] {
        let allExercises = try await exerciseRepo.fetchAll()
        var lookup: [String: Exercise] = [:]
        for exercise in allExercises {
            lookup[exercise.name.lowercased()] = exercise
        }
        return lookup
    }

    // MARK: - Workout Grouping

    private func groupByDate(_ rows: [ValidatedRow]) -> [(date: Date, rows: [ValidatedRow])] {
        var groups: [Date: [ValidatedRow]] = [:]
        let calendar = Calendar.current
        for row in rows {
            let dayStart = calendar.startOfDay(for: row.date)
            groups[dayStart, default: []].append(row)
        }
        return groups.sorted { $0.key < $1.key }.map { (date: $0.key, rows: $0.value) }
    }

    // MARK: - Core Import Logic

    private func performImport(data: Data, continuation: AsyncStream<ImportProgress>.Continuation) async {
        let startTime = Date()

        do {
            // Phase 1: Parse
            continuation.yield(.parsing)
            let parseResult = try CSVParser.parse(data: data)
            try validateHeader(parseResult.headers)

            // Phase 2: Validate rows
            var validRows: [ValidatedRow] = []
            var errors: [CSVParser.ValidationError] = []

            for (index, row) in parseResult.rows.enumerated() {
                if (index + 1) % 1000 == 0 || index == 0 {
                    continuation.yield(.validating(processed: index + 1, total: parseResult.totalRows))
                }

                switch validateRow(row, rowNumber: index + 2) { // +2: 1-based + header row
                case .success(let validated):
                    validRows.append(validated)
                case .failure(let error):
                    errors.append(error)
                }
            }
            continuation.yield(.validating(processed: parseResult.totalRows, total: parseResult.totalRows))

            guard !validRows.isEmpty else {
                continuation.yield(.failed(.noValidRows))
                continuation.finish()
                return
            }

            // Phase 3: Group and prepare
            let dateGroups = groupByDate(validRows)
            var exerciseLookup = try await buildExerciseLookup()

            // Fetch health profile for e1RM formula
            let healthProfile = try await healthProfileRepo.fetchOrCreate()
            let formula = E1RMFormula(rawValue: healthProfile.e1RMFormula) ?? .epley

            // Fetch closest bodyweight (use latest as approximation for bulk import)
            let closestBodyweight = try await fetchClosestBodyweight(healthProfileId: healthProfile.id)

            // Create background context for batch inserts
            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false

            var setsInserted = 0
            var workoutsCreated = 0
            var exercisesCreated = 0
            let totalSets = validRows.count

            // Track existing workouts by date to avoid duplicates
            var workoutsByDate: [Date: Workout] = [:]

            // Pre-fetch existing workouts in the date range
            if let firstDate = dateGroups.first?.date, let lastDate = dateGroups.last?.date {
                let existingWorkouts = try await workoutRepo.fetchWorkouts(for: firstDate...lastDate)
                let calendar = Calendar.current
                for workout in existingWorkouts {
                    let day = calendar.startOfDay(for: workout.date)
                    workoutsByDate[day] = workout
                }
            }

            // Track which exercise names have been assigned a trackingType (first occurrence wins)
            var exerciseKindAssigned: Set<String> = Set(exerciseLookup.keys)

            continuation.yield(.importing(inserted: 0, total: totalSets))

            for group in dateGroups {
                // Find or create workout for this date
                let workout: Workout
                if let existing = workoutsByDate[group.date] {
                    workout = existing
                } else {
                    let newWorkout = Workout(
                        date: group.date,
                        status: .completed
                    )
                    context.insert(newWorkout)
                    workoutsByDate[group.date] = newWorkout
                    workoutsCreated += 1
                    workout = newWorkout
                }

                var orderInWorkout = 0
                var exerciseOrderCounters: [String: Int] = [:]

                for row in group.rows {
                    let lookupKey = row.exerciseName.lowercased()

                    // Match or create exercise
                    let exercise: Exercise
                    if let existing = exerciseLookup[lookupKey] {
                        exercise = existing
                    } else {
                        // Only use Kind from first occurrence for new exercise
                        let kind = exerciseKindAssigned.contains(lookupKey) ? nil : row.kind
                        let newExercise = Exercise(
                            name: row.exerciseName,
                            equipmentType: .other,
                            trackingType: inferTrackingType(from: kind),
                            primaryMuscle: row.category
                        )
                        context.insert(newExercise)
                        exerciseLookup[lookupKey] = newExercise
                        exerciseKindAssigned.insert(lookupKey)
                        exercisesCreated += 1
                        exercise = newExercise
                    }

                    // Compute effectiveWeight
                    let effectiveWeight: Double?
                    if let w = row.weightKg {
                        effectiveWeight = w + (closestBodyweight * exercise.bodyweightFactor)
                    } else {
                        effectiveWeight = nil
                    }

                    // Compute e1RM
                    let e1RM: Double?
                    if let ew = effectiveWeight, ew > 0, let r = row.reps, r > 0 {
                        e1RM = formula.calculate(weight: ew, reps: r)
                    } else {
                        e1RM = nil
                    }

                    // Handle distance unit conversion
                    var distanceMeters = row.distance
                    if let dist = distanceMeters, let unit = row.distanceUnit?.lowercased() {
                        if unit == "mi" || unit == "miles" {
                            distanceMeters = dist * 1609.34
                        }
                    }

                    // Track order within exercise
                    let exerciseKey = exercise.id.uuidString
                    let orderInExercise = exerciseOrderCounters[exerciseKey, default: 0]
                    exerciseOrderCounters[exerciseKey] = orderInExercise + 1

                    // Create WorkoutSet
                    let workoutSet = WorkoutSet(
                        workoutId: workout.id,
                        exerciseId: exercise.id,
                        date: row.date,
                        weight: row.weightKg,
                        effectiveWeight: effectiveWeight,
                        reps: row.reps,
                        durationSeconds: row.durationSeconds,
                        distanceMeters: distanceMeters,
                        e1RM: e1RM,
                        e1RMFormulaVersion: healthProfile.e1RMFormula,
                        setType: .working,
                        notes: row.notes,
                        orderInWorkout: orderInWorkout,
                        orderInExercise: orderInExercise,
                        completed: true
                    )
                    context.insert(workoutSet)
                    orderInWorkout += 1
                    setsInserted += 1

                    // Batch save every N sets
                    if setsInserted % batchSize == 0 {
                        try context.save()
                        continuation.yield(.importing(inserted: setsInserted, total: totalSets))
                    }
                }
            }

            // Final save for remaining records
            try context.save()
            continuation.yield(.importing(inserted: setsInserted, total: totalSets))

            // Phase 4: Rebuild stats and PRs
            continuation.yield(.rebuilding(phase: .stats))
            try await statsService.rebuildAll()

            continuation.yield(.rebuilding(phase: .prs))
            try await prService.rebuildAll()

            // Done
            let result = ImportResult(
                setsImported: setsInserted,
                workoutsCreated: workoutsCreated,
                exercisesCreated: exercisesCreated,
                rowsSkipped: errors.count,
                errors: errors,
                duration: Date().timeIntervalSince(startTime)
            )
            continuation.yield(.completed(result))
            continuation.finish()

        } catch let error as ImportError {
            continuation.yield(.failed(error))
            continuation.finish()
        } catch {
            continuation.yield(.failed(.insertFailed(error.localizedDescription)))
            continuation.finish()
        }
    }

    // MARK: - Helpers

    private func fetchClosestBodyweight(healthProfileId: UUID) async throws -> Double {
        // Use current date as reference for closest bodyweight
        let entry = try await bodyweightRepo.fetchClosest(to: Date(), healthProfileId: healthProfileId)
        return entry?.bodyweightKg ?? 0.0
    }
}
