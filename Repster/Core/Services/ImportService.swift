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

    nonisolated func previewImport(
        data: Data,
        source: ImportSource,
        unitSystem: ImportUnitSystem?
    ) throws -> ImportPreview {
        try Self.adapter(for: source).preview(data: data, unitSystem: unitSystem)
    }

    nonisolated func importData(
        data: Data,
        source: ImportSource,
        unitSystem: ImportUnitSystem?
    ) -> AsyncStream<ImportProgress> {
        AsyncStream { continuation in
            Task {
                await self.performImport(
                    data: data,
                    source: source,
                    unitSystem: unitSystem,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Core Import Logic

    private func performImport(
        data: Data,
        source: ImportSource,
        unitSystem: ImportUnitSystem?,
        continuation: AsyncStream<ImportProgress>.Continuation
    ) async {
        let startedAt = Date()

        do {
            continuation.yield(.parsing)
            let document = try Self.adapter(for: source).parseDocument(data: data, unitSystem: unitSystem)
            continuation.yield(.validating(processed: document.totalRows, total: document.totalRows))

            let totalSets = document.workouts.reduce(0) { $0 + $1.sets.count }
            guard totalSets > 0 else {
                continuation.yield(.failed(.noValidRows))
                continuation.finish()
                return
            }

            var exerciseLookup = try await buildExerciseLookup()

            let healthProfile = try await healthProfileRepo.fetchOrCreate()
            let formula = E1RMFormula(rawValue: healthProfile.e1RMFormula) ?? .epley
            let closestBodyweight = try await fetchClosestBodyweight(healthProfileId: healthProfile.id)

            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false

            var setsInserted = 0
            var workoutsCreated = 0
            var exercisesCreated = 0

            var workoutsByKey = try await existingWorkoutLookup(for: document.workouts)

            continuation.yield(.importing(inserted: 0, total: totalSets))

            for workoutPayload in document.workouts {
                let workoutKey = lookupKey(for: workoutPayload)
                let workout: Workout
                if let existing = workoutsByKey[workoutKey] {
                    workout = existing
                } else {
                    let newWorkout = Workout(
                        date: workoutPayload.date,
                        title: workoutPayload.title,
                        startTime: workoutPayload.startTime,
                        endTime: workoutPayload.endTime,
                        duration: workoutPayload.durationSeconds,
                        notes: workoutPayload.notes,
                        status: .completed
                    )
                    context.insert(newWorkout)
                    workoutsByKey[workoutKey] = newWorkout
                    workoutsCreated += 1
                    workout = newWorkout
                }

                var orderInWorkout = 0
                var exerciseOrderCounters: [String: Int] = [:]

                for row in workoutPayload.sets {
                    let exerciseLookupKey = normalizedExerciseLookupKey(row.exerciseName)
                    let exercise: Exercise

                    if let existing = exerciseLookup[exerciseLookupKey] {
                        exercise = existing
                    } else {
                        let newExercise = Exercise(
                            name: row.exerciseName,
                            equipmentType: .other,
                            trackingType: row.trackingType,
                            primaryMuscle: row.category
                        )
                        context.insert(newExercise)
                        exerciseLookup[exerciseLookupKey] = newExercise
                        exercisesCreated += 1
                        exercise = newExercise
                    }

                    let effectiveWeight: Double?
                    if let weightKg = row.weightKg {
                        effectiveWeight = weightKg + (closestBodyweight * exercise.bodyweightFactor)
                    } else {
                        effectiveWeight = nil
                    }

                    let e1RM: Double?
                    if let effectiveWeight, effectiveWeight > 0, let reps = row.reps, reps > 0 {
                        e1RM = formula.calculate(weight: effectiveWeight, reps: reps)
                    } else {
                        e1RM = nil
                    }

                    let orderInExercise = exerciseOrderCounters[exerciseLookupKey, default: 0]
                    exerciseOrderCounters[exerciseLookupKey] = orderInExercise + 1

                    let workoutSet = WorkoutSet(
                        workoutId: workout.id,
                        exerciseId: exercise.id,
                        date: row.date,
                        weight: row.weightKg,
                        effectiveWeight: effectiveWeight,
                        reps: row.reps,
                        durationSeconds: row.durationSeconds,
                        distanceMeters: row.distanceMeters,
                        e1RM: e1RM,
                        e1RMFormulaVersion: healthProfile.e1RMFormula,
                        rpe: row.rpe,
                        setType: row.setType,
                        notes: row.notes,
                        orderInWorkout: orderInWorkout,
                        orderInExercise: orderInExercise,
                        completed: true
                    )
                    context.insert(workoutSet)
                    orderInWorkout += 1
                    setsInserted += 1

                    if setsInserted % batchSize == 0 {
                        try context.save()
                        continuation.yield(.importing(inserted: setsInserted, total: totalSets))
                    }
                }
            }

            try context.save()
            continuation.yield(.importing(inserted: setsInserted, total: totalSets))

            continuation.yield(.rebuilding(phase: .stats))
            try await statsService.rebuildAll()

            continuation.yield(.rebuilding(phase: .prs))
            try await prService.rebuildAll()

            let result = ImportResult(
                setsImported: setsInserted,
                workoutsCreated: workoutsCreated,
                exercisesCreated: exercisesCreated,
                rowsSkipped: document.errors.count,
                errors: document.errors,
                warnings: document.warnings,
                duration: Date().timeIntervalSince(startedAt)
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

    // MARK: - Exercise Matching

    private func buildExerciseLookup() async throws -> [String: Exercise] {
        let allExercises = try await exerciseRepo.fetchAll()
        return Dictionary(
            uniqueKeysWithValues: allExercises.map { (normalizedExerciseLookupKey($0.name), $0) }
        )
    }

    private nonisolated func normalizedExerciseLookupKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Existing Workout Matching

    private func existingWorkoutLookup(
        for workouts: [NormalizedWorkoutImport]
    ) async throws -> [ExistingWorkoutKey: Workout] {
        guard let range = dateRange(for: workouts) else { return [:] }

        let existingWorkouts = try await workoutRepo.fetchWorkouts(for: range)
        var lookup: [ExistingWorkoutKey: Workout] = [:]
        for workout in existingWorkouts {
            lookup[lookupKey(for: workout)] = workout
        }
        return lookup
    }

    private nonisolated func dateRange(
        for workouts: [NormalizedWorkoutImport]
    ) -> ClosedRange<Date>? {
        guard let minimum = workouts.map(\.date).min(),
              let maximum = workouts.map(\.date).max() else {
            return nil
        }
        return minimum...maximum
    }

    private nonisolated func lookupKey(for workout: Workout) -> ExistingWorkoutKey {
        if let startTime = workout.startTime {
            return .timed(startTime: startTime, title: workout.title, duration: workout.duration)
        }
        return .day(Calendar.current.startOfDay(for: workout.date))
    }

    private nonisolated func lookupKey(for workout: NormalizedWorkoutImport) -> ExistingWorkoutKey {
        if let startTime = workout.startTime {
            return .timed(startTime: startTime, title: workout.title, duration: workout.durationSeconds)
        }
        return .day(Calendar.current.startOfDay(for: workout.date))
    }

    // MARK: - Helpers

    private func fetchClosestBodyweight(healthProfileId: UUID) async throws -> Double {
        let entry = try await bodyweightRepo.fetchClosest(to: Date(), healthProfileId: healthProfileId)
        return entry?.bodyweightKg ?? 0.0
    }

    private nonisolated static func adapter(for source: ImportSource) -> any CSVImportAdapter {
        switch source {
        case .fitNotes:
            return FitNotesCSVImporter()
        case .strong:
            return StrongCSVImporter()
        case .hevy:
            return HevyCSVImporter()
        }
    }
}

// MARK: - Shared Import Models

private struct ParsedImportDocument {
    let workouts: [NormalizedWorkoutImport]
    let totalRows: Int
    let errors: [CSVParser.ValidationError]
    let warnings: [CSVParser.ValidationError]
}

private struct NormalizedWorkoutImport {
    let date: Date
    let title: String?
    let startTime: Date?
    let endTime: Date?
    let durationSeconds: Int?
    let notes: String?
    let sets: [NormalizedSetImport]
}

private struct NormalizedSetImport {
    let date: Date
    let exerciseName: String
    let category: String?
    let weightKg: Double?
    let reps: Int?
    let distanceMeters: Double?
    let durationSeconds: Int?
    let rpe: Double?
    let notes: String?
    let trackingType: TrackingType
    let setType: SetType
}

private enum ExistingWorkoutKey: Hashable {
    case timed(startTime: Date, title: String?, duration: Int?)
    case day(Date)
}

private protocol CSVImportAdapter {
    var source: ImportSource { get }
    func preview(data: Data, unitSystem: ImportUnitSystem?) throws -> ImportPreview
    func parseDocument(data: Data, unitSystem: ImportUnitSystem?) throws -> ParsedImportDocument
}

/// Removes emoji characters from imported workout titles and collapses any leftover whitespace.
/// Operates on grapheme clusters so multi-scalar emoji (skin-tone modifiers, ZWJ sequences, flags)
/// are dropped as a unit. ASCII digits/`*`/`#` are preserved by gating on scalar value > 0x238C.
private func stripEmojiAndNormalize(_ value: String) -> String {
    let withoutEmoji = value.filter { character in
        !character.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation ||
            (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }
    let parts = withoutEmoji.split(whereSeparator: { $0.isWhitespace })
    return parts.joined(separator: " ")
}

private extension CSVImportAdapter {
    func validateHeader(_ headers: [String], expected: [String]) throws {
        let normalized = headers.map { $0.trimmingCharacters(in: .whitespaces) }
        guard normalized.count == expected.count else {
            throw ImportError.invalidHeader(source: source, expected: expected, got: normalized)
        }

        for (expectedHeader, actualHeader) in zip(expected, normalized) {
            guard expectedHeader.lowercased() == actualHeader.lowercased() else {
                throw ImportError.invalidHeader(source: source, expected: expected, got: normalized)
            }
        }
    }

    func makePreview(from preview: CSVParser.PreviewResult) -> ImportPreview {
        ImportPreview(
            headers: preview.headers,
            sampleRows: preview.sampleRows,
            estimatedTotalRows: preview.estimatedTotalRows
        )
    }
}

// MARK: - FitNotes Importer

private struct FitNotesCSVImporter: CSVImportAdapter {
    let source: ImportSource = .fitNotes

    private static let headers = [
        "Date", "Exercise", "Category", "Weight (kg)", "Weight (lbs)",
        "Reps", "Distance", "Distance Unit", "Time", "Notes", "Kind"
    ]

    func preview(data: Data, unitSystem: ImportUnitSystem?) throws -> ImportPreview {
        let preview = try CSVParser.parsePreview(data: data)
        try validateHeader(preview.headers, expected: Self.headers)
        return makePreview(from: preview)
    }

    func parseDocument(data: Data, unitSystem: ImportUnitSystem?) throws -> ParsedImportDocument {
        let parseResult = try CSVParser.parse(data: data)
        try validateHeader(parseResult.headers, expected: Self.headers)

        var validRows: [ValidatedRow] = []
        var errors: [CSVParser.ValidationError] = []
        var warnings: [CSVParser.ValidationError] = []
        let preferredUnit = unitSystem ?? .metric

        for (index, row) in parseResult.rows.enumerated() {
            switch validateRow(row, rowNumber: index + 2, unitSystem: preferredUnit) {
            case .success(let result):
                validRows.append(result.row)
                if let warning = result.warning {
                    warnings.append(warning)
                }
            case .failure(let error):
                errors.append(error)
            }
        }

        let workouts = groupRowsByDay(validRows)
        return ParsedImportDocument(
            workouts: workouts,
            totalRows: parseResult.totalRows,
            errors: errors,
            warnings: warnings
        )
    }

    // MARK: Row Validation

    private struct ValidatedRow {
        let date: Date
        let exerciseName: String
        let category: String?
        let weightKg: Double?
        let reps: Int?
        let distanceMeters: Double?
        let durationSeconds: Int?
        let notes: String?
        let trackingType: TrackingType
    }

    private struct ValidationSuccess {
        let row: ValidatedRow
        let warning: CSVParser.ValidationError?
    }

    private struct WeightResolution {
        let weightKg: Double?
        let warning: CSVParser.ValidationError?
    }

    private func validateRow(
        _ fields: [String],
        rowNumber: Int,
        unitSystem: ImportUnitSystem
    ) -> Result<ValidationSuccess, CSVParser.ValidationError> {
        guard fields.count == Self.headers.count else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Expected \(Self.headers.count) columns, found \(fields.count)"
            ))
        }

        let dateText = fields[0].trimmingCharacters(in: .whitespaces)
        guard !dateText.isEmpty else {
            return .failure(.init(rowNumber: rowNumber, reason: "Missing date"))
        }

        let dateStyle = Date.ISO8601FormatStyle()
            .year()
            .month()
            .day()
            .dateSeparator(.dash)
        guard let date = try? dateStyle.parse(dateText) else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid date format: '\(dateText)'. Expected yyyy-MM-dd."
            ))
        }

        let exerciseName = fields[1].trimmingCharacters(in: .whitespaces)
        guard !exerciseName.isEmpty else {
            return .failure(.init(rowNumber: rowNumber, reason: "Missing exercise name"))
        }

        let category = fields[2].trimmingCharacters(in: .whitespaces)

        let weightResult: WeightResolution
        switch resolveWeight(
            kgText: fields[3],
            lbsText: fields[4],
            preferredUnit: unitSystem,
            rowNumber: rowNumber
        ) {
        case .success(let resolved):
            weightResult = resolved
        case .failure(let error):
            return .failure(error)
        }

        let repsText = fields[5].trimmingCharacters(in: .whitespaces)
        let reps = repsText.isEmpty ? nil : Int(repsText)

        let distanceText = fields[6].trimmingCharacters(in: .whitespaces)
        let rawDistance = distanceText.isEmpty ? nil : Double(distanceText)

        let distanceUnit = fields[7].trimmingCharacters(in: .whitespaces).lowercased()
        let distanceMeters: Double?
        if let rawDistance {
            if distanceUnit == "mi" || distanceUnit == "miles" {
                distanceMeters = rawDistance * 1609.34
            } else {
                distanceMeters = rawDistance
            }
        } else {
            distanceMeters = nil
        }

        let durationSeconds = parseFitNotesTime(fields[8].trimmingCharacters(in: .whitespaces))
        let notes = fields[9].trimmingCharacters(in: .whitespaces)
        let kind = fields[10].trimmingCharacters(in: .whitespaces)

        let hasData = weightResult.weightKg != nil || reps != nil || durationSeconds != nil || distanceMeters != nil
        guard hasData else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Row has no data values (need at least one of weight, reps, duration, or distance)"
            ))
        }

        return .success(ValidationSuccess(
            row: ValidatedRow(
                date: date,
                exerciseName: exerciseName,
                category: category.isEmpty ? nil : category,
                weightKg: weightResult.weightKg,
                reps: reps,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                notes: notes.isEmpty ? nil : notes,
                trackingType: inferTrackingType(from: kind)
            ),
            warning: weightResult.warning
        ))
    }

    private func resolveWeight(
        kgText: String,
        lbsText: String,
        preferredUnit: ImportUnitSystem,
        rowNumber: Int
    ) -> Result<WeightResolution, CSVParser.ValidationError> {
        let trimmedKg = kgText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLbs = lbsText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch preferredUnit {
        case .metric:
            if !trimmedKg.isEmpty {
                return parseWeight(trimmedKg, columnName: "Weight (kg)", rowNumber: rowNumber)
                    .map { WeightResolution(weightKg: $0, warning: nil) }
            }
            if !trimmedLbs.isEmpty {
                return parseWeight(trimmedLbs, columnName: "Weight (lbs)", rowNumber: rowNumber)
                    .map {
                        WeightResolution(
                            weightKg: UnitConversion.lbsToKg($0),
                            warning: .init(
                                rowNumber: rowNumber,
                                reason: "Preferred Weight (kg) was empty; imported Weight (lbs) instead."
                            )
                        )
                    }
            }
            return .success(WeightResolution(weightKg: nil, warning: nil))

        case .imperial:
            if !trimmedLbs.isEmpty {
                return parseWeight(trimmedLbs, columnName: "Weight (lbs)", rowNumber: rowNumber)
                    .map { WeightResolution(weightKg: UnitConversion.lbsToKg($0), warning: nil) }
            }
            if !trimmedKg.isEmpty {
                return parseWeight(trimmedKg, columnName: "Weight (kg)", rowNumber: rowNumber)
                    .map {
                        WeightResolution(
                            weightKg: $0,
                            warning: .init(
                                rowNumber: rowNumber,
                                reason: "Preferred Weight (lbs) was empty; imported Weight (kg) instead."
                            )
                        )
                    }
            }
            return .success(WeightResolution(weightKg: nil, warning: nil))
        }
    }

    private func parseWeight(
        _ value: String,
        columnName: String,
        rowNumber: Int
    ) -> Result<Double, CSVParser.ValidationError> {
        guard let weight = Double(value) else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid \(columnName) value: '\(value)'."
            ))
        }
        return .success(weight)
    }

    private func groupRowsByDay(_ rows: [ValidatedRow]) -> [NormalizedWorkoutImport] {
        let calendar = Calendar.current
        var groupedRows: [Date: [ValidatedRow]] = [:]

        for row in rows {
            let day = calendar.startOfDay(for: row.date)
            groupedRows[day, default: []].append(row)
        }

        return groupedRows.keys.sorted().compactMap { day in
            guard let rows = groupedRows[day], !rows.isEmpty else { return nil }
            return NormalizedWorkoutImport(
                date: day,
                title: nil,
                startTime: nil,
                endTime: nil,
                durationSeconds: nil,
                notes: nil,
                sets: rows.map {
                    NormalizedSetImport(
                        date: $0.date,
                        exerciseName: $0.exerciseName,
                        category: $0.category,
                        weightKg: $0.weightKg,
                        reps: $0.reps,
                        distanceMeters: $0.distanceMeters,
                        durationSeconds: $0.durationSeconds,
                        rpe: nil,
                        notes: $0.notes,
                        trackingType: $0.trackingType,
                        setType: .working
                    )
                }
            )
        }
    }

    private func inferTrackingType(from kind: String?) -> TrackingType {
        switch kind?.lowercased() {
        case "wr":
            return .weightReps
        case "d", "wt", "tr", "t":
            return .duration
        case "dt":
            return .durationDistance
        case "wd":
            return .weightDistance
        case "wrd":
            return .weightRepsDuration
        case "r", "w":
            return .weightReps
        default:
            return .weightReps
        }
    }

    private func parseFitNotesTime(_ value: String) -> Int? {
        guard !value.isEmpty else { return nil }
        let parts = value.split(separator: ":")
        if parts.count == 2,
           let minutes = Int(parts[0]),
           let seconds = Int(parts[1]) {
            return minutes * 60 + seconds
        }
        return Int(value)
    }
}

// MARK: - Strong Importer

private struct StrongCSVImporter: CSVImportAdapter {
    let source: ImportSource = .strong

    private static let headers = [
        "Date", "Workout Name", "Duration", "Exercise Name", "Set Order",
        "Weight", "Reps", "Distance", "Seconds", "RPE"
    ]

    func preview(data: Data, unitSystem: ImportUnitSystem?) throws -> ImportPreview {
        guard unitSystem != nil else {
            throw ImportError.missingUnitSystem(source: .strong)
        }

        let preview = try CSVParser.parsePreview(data: data)
        try validateHeader(preview.headers, expected: Self.headers)
        return makePreview(from: preview)
    }

    func parseDocument(data: Data, unitSystem: ImportUnitSystem?) throws -> ParsedImportDocument {
        guard let unitSystem else {
            throw ImportError.missingUnitSystem(source: .strong)
        }

        let parseResult = try CSVParser.parse(data: data)
        try validateHeader(parseResult.headers, expected: Self.headers)

        var groupedRows: [WorkoutGroupKey: [ValidatedRow]] = [:]
        var workoutOrder: [WorkoutGroupKey] = []
        var errors: [CSVParser.ValidationError] = []
        var warnings: [CSVParser.ValidationError] = []

        for (index, row) in parseResult.rows.enumerated() {
            switch validateRow(row, rowNumber: index + 2, unitSystem: unitSystem) {
            case .success(let result):
                if let warning = result.warning {
                    warnings.append(warning)
                }
                if groupedRows[result.key] == nil {
                    workoutOrder.append(result.key)
                }
                groupedRows[result.key, default: []].append(result.row)
            case .failure(let error):
                errors.append(error)
            }
        }

        let workouts: [NormalizedWorkoutImport] = workoutOrder.compactMap { key -> NormalizedWorkoutImport? in
            guard let rows = groupedRows[key], !rows.isEmpty else { return nil }
            return NormalizedWorkoutImport(
                date: key.startTime,
                title: key.workoutName.isEmpty ? nil : key.workoutName,
                startTime: key.startTime,
                endTime: key.durationSeconds.map { key.startTime.addingTimeInterval(TimeInterval($0)) },
                durationSeconds: key.durationSeconds,
                notes: nil,
                sets: rows.map {
                    NormalizedSetImport(
                        date: $0.date,
                        exerciseName: $0.exerciseName,
                        category: nil,
                        weightKg: $0.weightKg,
                        reps: $0.reps,
                        distanceMeters: $0.distanceMeters,
                        durationSeconds: $0.durationSeconds,
                        rpe: $0.rpe,
                        notes: nil,
                        trackingType: $0.trackingType,
                        setType: $0.setType
                    )
                }
            )
        }

        return ParsedImportDocument(
            workouts: workouts,
            totalRows: parseResult.totalRows,
            errors: errors,
            warnings: warnings
        )
    }

    // MARK: Row Validation

    private struct WorkoutGroupKey: Hashable {
        let startTime: Date
        let workoutName: String
        let durationSeconds: Int?
    }

    private struct ValidatedRow {
        let date: Date
        let exerciseName: String
        let weightKg: Double?
        let reps: Int?
        let distanceMeters: Double?
        let durationSeconds: Int?
        let rpe: Double?
        let trackingType: TrackingType
        let setType: SetType
    }

    private struct ValidationSuccess {
        let key: WorkoutGroupKey
        let row: ValidatedRow
        let warning: CSVParser.ValidationError?
    }

    private func validateRow(
        _ fields: [String],
        rowNumber: Int,
        unitSystem: ImportUnitSystem
    ) -> Result<ValidationSuccess, CSVParser.ValidationError> {
        guard fields.count == Self.headers.count else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Expected \(Self.headers.count) columns, found \(fields.count)"
            ))
        }

        let dateText = fields[0].trimmingCharacters(in: .whitespaces)
        guard !dateText.isEmpty else {
            return .failure(.init(rowNumber: rowNumber, reason: "Missing workout timestamp"))
        }
        guard let startTime = parseStrongDate(dateText) else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid workout timestamp: '\(dateText)'. Expected yyyy-MM-dd HH:mm:ss."
            ))
        }

        let rawWorkoutName = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawWorkoutName.isEmpty else {
            return .failure(.init(rowNumber: rowNumber, reason: "Missing workout name"))
        }
        let workoutName = stripEmojiAndNormalize(rawWorkoutName)

        let durationText = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let workoutDuration = parseWorkoutDuration(durationText)
        if !durationText.isEmpty && workoutDuration == nil {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid workout duration: '\(durationText)'."
            ))
        }

        let exerciseName = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !exerciseName.isEmpty else {
            return .failure(.init(rowNumber: rowNumber, reason: "Missing exercise name"))
        }

        let setOrderText = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
        let setOrderResult = parseStrongSetType(setOrderText, rowNumber: rowNumber)

        guard let rawWeight = parseDecimalField(fields[5]) else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid weight value: '\(fields[5].trimmingCharacters(in: .whitespacesAndNewlines))'."
            ))
        }
        let weightKg = rawWeight.map { unitSystem == .imperial ? UnitConversion.lbsToKg($0) : $0 }

        switch parseWholeNumberField(fields[6], fieldName: "reps", rowNumber: rowNumber) {
        case .failure(let error):
            return .failure(error)
        case .success(let reps):
            switch parseDecimalField(fields[7]) {
            case nil:
                return .failure(.init(
                    rowNumber: rowNumber,
                    reason: "Invalid distance value: '\(fields[7].trimmingCharacters(in: .whitespacesAndNewlines))'."
                ))
            case .some(let rawDistance):
                switch parseWholeNumberField(fields[8], fieldName: "seconds", rowNumber: rowNumber) {
                case .failure(let error):
                    return .failure(error)
                case .success(let durationSeconds):
                    guard let rpe = parseDecimalField(fields[9]) else {
                        return .failure(.init(
                            rowNumber: rowNumber,
                            reason: "Invalid RPE value: '\(fields[9].trimmingCharacters(in: .whitespacesAndNewlines))'."
                        ))
                    }

                    let distanceMeters = rawDistance.map {
                        unitSystem == .imperial ? $0 * 1609.34 : $0 * 1000
                    }

                    let hasData = weightKg != nil || reps != nil || durationSeconds != nil || distanceMeters != nil
                    guard hasData else {
                        return .failure(.init(
                            rowNumber: rowNumber,
                            reason: "Row has no data values (need at least one of weight, reps, duration, or distance)"
                        ))
                    }

                    return .success(ValidationSuccess(
                        key: WorkoutGroupKey(
                            startTime: startTime,
                            workoutName: workoutName,
                            durationSeconds: workoutDuration
                        ),
                        row: ValidatedRow(
                            date: startTime,
                            exerciseName: exerciseName,
                            weightKg: weightKg,
                            reps: reps,
                            distanceMeters: distanceMeters,
                            durationSeconds: durationSeconds,
                            rpe: rpe,
                            trackingType: inferTrackingType(
                                weightKg: weightKg,
                                reps: reps,
                                distanceMeters: distanceMeters,
                                durationSeconds: durationSeconds
                            ),
                            setType: setOrderResult.setType
                        ),
                        warning: setOrderResult.warning
                    ))
                }
            }
        }
    }

    private func parseStrongDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }

    private func parseWorkoutDuration(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?\s*(?:(\d+)\s*s)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
              ) else {
            return nil
        }

        func component(at index: Int) -> Int {
            let nsRange = match.range(at: index)
            guard nsRange.location != NSNotFound,
                  let range = Range(nsRange, in: trimmed) else {
                return 0
            }
            return Int(trimmed[range]) ?? 0
        }

        let hours = component(at: 1)
        let minutes = component(at: 2)
        let seconds = component(at: 3)
        let total = (hours * 3600) + (minutes * 60) + seconds
        return total > 0 ? total : nil
    }

    private func parseWholeNumberField(
        _ value: String,
        fieldName: String,
        rowNumber: Int
    ) -> Result<Int?, CSVParser.ValidationError> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(nil) }
        guard let decimal = Double(trimmed) else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid \(fieldName) value: '\(trimmed)'."
            ))
        }

        let rounded = decimal.rounded()
        guard abs(decimal - rounded) < 0.000_001 else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid \(fieldName) value: '\(trimmed)'. Expected a whole number."
            ))
        }

        return .success(Int(rounded))
    }

    private func parseDecimalField(_ value: String) -> Double?? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .some(nil) }
        guard let decimal = Double(trimmed) else { return nil }
        return .some(decimal)
    }

    private func inferTrackingType(
        weightKg: Double?,
        reps: Int?,
        distanceMeters: Double?,
        durationSeconds: Int?
    ) -> TrackingType {
        let hasDistance = (distanceMeters ?? 0) > 0
        let hasDuration = (durationSeconds ?? 0) > 0
        let hasWeight = weightKg != nil
        let hasReps = reps != nil

        if hasDistance && hasDuration {
            return .durationDistance
        }
        if hasDuration && !hasWeight && !hasReps {
            return .duration
        }
        if hasDistance {
            return .durationDistance
        }
        return .weightReps
    }

    private func parseStrongSetType(
        _ value: String,
        rowNumber: Int
    ) -> (setType: SetType, warning: CSVParser.ValidationError?) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        switch normalized {
        case "W":
            return (.warmup, nil)
        case "D":
            return (.dropset, nil)
        case "F":
            return (.failure, nil)
        default:
            if Int(normalized) != nil {
                return (.working, nil)
            }
            return (
                .working,
                .init(
                    rowNumber: rowNumber,
                    reason: "Unknown set marker '\(value)'; imported as a working set."
                )
            )
        }
    }
}

// MARK: - Hevy Importer

private struct HevyCSVImporter: CSVImportAdapter {
    let source: ImportSource = .hevy

    private static let headers = [
        "title", "start_time", "end_time", "description", "exercise_title",
        "superset_id", "exercise_notes", "set_index", "set_type", "weight_kg",
        "reps", "distance_km", "duration_seconds", "rpe"
    ]

    func preview(data: Data, unitSystem: ImportUnitSystem?) throws -> ImportPreview {
        guard unitSystem != nil else {
            throw ImportError.missingUnitSystem(source: .hevy)
        }

        let preview = try CSVParser.parsePreview(data: data)
        try validateHeader(preview.headers, expected: Self.headers)
        return makePreview(from: preview)
    }

    func parseDocument(data: Data, unitSystem: ImportUnitSystem?) throws -> ParsedImportDocument {
        guard let unitSystem else {
            throw ImportError.missingUnitSystem(source: .hevy)
        }

        let parseResult = try CSVParser.parse(data: data)
        try validateHeader(parseResult.headers, expected: Self.headers)

        var groupedRows: [WorkoutGroupKey: [ValidatedRow]] = [:]
        var workoutOrder: [WorkoutGroupKey] = []
        var errors: [CSVParser.ValidationError] = []
        var warnings: [CSVParser.ValidationError] = []

        for (index, row) in parseResult.rows.enumerated() {
            switch validateRow(row, rowNumber: index + 2, unitSystem: unitSystem) {
            case .success(let result):
                if let warning = result.warning {
                    warnings.append(warning)
                }
                if groupedRows[result.key] == nil {
                    workoutOrder.append(result.key)
                }
                groupedRows[result.key, default: []].append(result.row)
            case .failure(let error):
                errors.append(error)
            }
        }

        let workouts: [NormalizedWorkoutImport] = workoutOrder.compactMap { key -> NormalizedWorkoutImport? in
            guard let rows = groupedRows[key], !rows.isEmpty else { return nil }

            var seenExerciseNotes: Set<String> = []
            let normalizedSets: [NormalizedSetImport] = rows.map { row -> NormalizedSetImport in
                let noteForSet: String?
                if let note = row.exerciseNotes, !seenExerciseNotes.contains(row.exerciseName) {
                    seenExerciseNotes.insert(row.exerciseName)
                    noteForSet = note
                } else {
                    noteForSet = nil
                }
                return NormalizedSetImport(
                    date: row.date,
                    exerciseName: row.exerciseName,
                    category: nil,
                    weightKg: row.weightKg,
                    reps: row.reps,
                    distanceMeters: row.distanceMeters,
                    durationSeconds: row.durationSeconds,
                    rpe: row.rpe,
                    notes: noteForSet,
                    trackingType: row.trackingType,
                    setType: row.setType
                )
            }

            return NormalizedWorkoutImport(
                date: key.startTime,
                title: key.workoutName.isEmpty ? nil : key.workoutName,
                startTime: key.startTime,
                endTime: key.endTime,
                durationSeconds: key.durationSeconds,
                notes: key.description,
                sets: normalizedSets
            )
        }

        return ParsedImportDocument(
            workouts: workouts,
            totalRows: parseResult.totalRows,
            errors: errors,
            warnings: warnings
        )
    }

    // MARK: Row Validation

    private struct WorkoutGroupKey: Hashable {
        let startTime: Date
        let endTime: Date?
        let workoutName: String
        let description: String?

        var durationSeconds: Int? {
            guard let endTime else { return nil }
            let diff = Int(endTime.timeIntervalSince(startTime))
            return diff > 0 ? diff : nil
        }
    }

    private struct ValidatedRow {
        let date: Date
        let exerciseName: String
        let exerciseNotes: String?
        let weightKg: Double?
        let reps: Int?
        let distanceMeters: Double?
        let durationSeconds: Int?
        let rpe: Double?
        let trackingType: TrackingType
        let setType: SetType
    }

    private struct ValidationSuccess {
        let key: WorkoutGroupKey
        let row: ValidatedRow
        let warning: CSVParser.ValidationError?
    }

    private func validateRow(
        _ fields: [String],
        rowNumber: Int,
        unitSystem: ImportUnitSystem
    ) -> Result<ValidationSuccess, CSVParser.ValidationError> {
        guard fields.count == Self.headers.count else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Expected \(Self.headers.count) columns, found \(fields.count)"
            ))
        }

        let rawWorkoutName = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawWorkoutName.isEmpty else {
            return .failure(.init(rowNumber: rowNumber, reason: "Missing workout title"))
        }
        let workoutName = stripEmojiAndNormalize(rawWorkoutName)

        let startText = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !startText.isEmpty else {
            return .failure(.init(rowNumber: rowNumber, reason: "Missing workout start_time"))
        }
        guard let startTime = parseHevyDate(startText) else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid start_time: '\(startText)'. Expected format like '8 May 2026, 17:16'."
            ))
        }

        let endText = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let endTime: Date?
        if endText.isEmpty {
            endTime = nil
        } else if let parsed = parseHevyDate(endText) {
            endTime = parsed
        } else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid end_time: '\(endText)'. Expected format like '8 May 2026, 17:16'."
            ))
        }

        let descriptionText = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let description = descriptionText.isEmpty ? nil : descriptionText

        let exerciseName = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !exerciseName.isEmpty else {
            return .failure(.init(rowNumber: rowNumber, reason: "Missing exercise_title"))
        }

        let exerciseNotesText = fields[6].trimmingCharacters(in: .whitespacesAndNewlines)
        let exerciseNotes = exerciseNotesText.isEmpty ? nil : exerciseNotesText

        let setTypeResult = parseHevySetType(fields[8], rowNumber: rowNumber)

        guard let rawWeight = parseDecimalField(fields[9]) else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid weight value: '\(fields[9].trimmingCharacters(in: .whitespacesAndNewlines))'."
            ))
        }
        let weightKg = rawWeight.map { unitSystem == .imperial ? UnitConversion.lbsToKg($0) : $0 }

        let repsResult = parseWholeNumberField(fields[10], fieldName: "reps", rowNumber: rowNumber)
        let reps: Int?
        switch repsResult {
        case .failure(let error):
            return .failure(error)
        case .success(let value):
            reps = value
        }

        guard let rawDistance = parseDecimalField(fields[11]) else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid distance value: '\(fields[11].trimmingCharacters(in: .whitespacesAndNewlines))'."
            ))
        }
        let distanceMeters = rawDistance.map {
            unitSystem == .imperial ? $0 * 1609.34 : $0 * 1000
        }

        let durationResult = parseWholeNumberField(fields[12], fieldName: "duration_seconds", rowNumber: rowNumber)
        let durationSeconds: Int?
        switch durationResult {
        case .failure(let error):
            return .failure(error)
        case .success(let value):
            durationSeconds = (value ?? 0) > 0 ? value : nil
        }

        guard let rpe = parseDecimalField(fields[13]) else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid RPE value: '\(fields[13].trimmingCharacters(in: .whitespacesAndNewlines))'."
            ))
        }

        let hasData = weightKg != nil || reps != nil || durationSeconds != nil || distanceMeters != nil
        guard hasData else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Row has no data values (need at least one of weight, reps, duration, or distance)"
            ))
        }

        return .success(ValidationSuccess(
            key: WorkoutGroupKey(
                startTime: startTime,
                endTime: endTime,
                workoutName: workoutName,
                description: description
            ),
            row: ValidatedRow(
                date: startTime,
                exerciseName: exerciseName,
                exerciseNotes: exerciseNotes,
                weightKg: weightKg,
                reps: reps,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                rpe: rpe,
                trackingType: inferTrackingType(
                    weightKg: weightKg,
                    reps: reps,
                    distanceMeters: distanceMeters,
                    durationSeconds: durationSeconds
                ),
                setType: setTypeResult.setType
            ),
            warning: setTypeResult.warning
        ))
    }

    private func parseHevyDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.date(from: value)
    }

    private func parseDecimalField(_ value: String) -> Double?? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .some(nil) }
        guard let decimal = Double(trimmed) else { return nil }
        return .some(decimal)
    }

    private func parseWholeNumberField(
        _ value: String,
        fieldName: String,
        rowNumber: Int
    ) -> Result<Int?, CSVParser.ValidationError> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(nil) }
        guard let decimal = Double(trimmed) else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid \(fieldName) value: '\(trimmed)'."
            ))
        }

        let rounded = decimal.rounded()
        guard abs(decimal - rounded) < 0.000_001 else {
            return .failure(.init(
                rowNumber: rowNumber,
                reason: "Invalid \(fieldName) value: '\(trimmed)'. Expected a whole number."
            ))
        }

        return .success(Int(rounded))
    }

    private func inferTrackingType(
        weightKg: Double?,
        reps: Int?,
        distanceMeters: Double?,
        durationSeconds: Int?
    ) -> TrackingType {
        let hasDistance = (distanceMeters ?? 0) > 0
        let hasDuration = (durationSeconds ?? 0) > 0
        let hasWeight = weightKg != nil
        let hasReps = reps != nil

        if hasDistance && hasDuration {
            return .durationDistance
        }
        if hasDuration && !hasWeight && !hasReps {
            return .duration
        }
        if hasDistance {
            return .durationDistance
        }
        return .weightReps
    }

    private func parseHevySetType(
        _ value: String,
        rowNumber: Int
    ) -> (setType: SetType, warning: CSVParser.ValidationError?) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "warmup":
            return (.warmup, nil)
        case "normal", "":
            return (.working, nil)
        case "failure":
            return (.failure, nil)
        case "dropset":
            return (.dropset, nil)
        default:
            return (
                .working,
                .init(
                    rowNumber: rowNumber,
                    reason: "Unknown set_type '\(value)'; imported as a working set."
                )
            )
        }
    }
}
