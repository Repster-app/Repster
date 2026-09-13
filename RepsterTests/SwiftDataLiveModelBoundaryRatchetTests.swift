import Foundation
import XCTest

/// Prevents the remaining SwiftData live-model crossings from growing while the phased
/// migration in `SWIFTDATA_LIVE_MODEL_FIX_SCOPING.md` is completed.
///
/// The allowlist is intentionally grouped by the phase expected to remove each crossing.
/// A new crossing fails this test, and a crossing that vanishes also fails until its stale
/// allowlist entry is removed. This is a source-level ratchet, not a proof of runtime safety.
final class SwiftDataLiveModelBoundaryRatchetTests: XCTestCase {
    private static let modelTypes = [
        "Exercise",
        "Workout",
        "WorkoutSet",
        "ExerciseStats",
        "PerformanceRecord",
        "BodyweightEntry",
        "HealthProfile",
        "WorkoutTemplate",
        "TemplateExercise",
        "TemplateSet",
        "Program",
        "FatigueObservation",
        "FatigueLearningSetAudit"
    ]

    private static let allowlistByRemovalPhase: [String: Set<String>] = [
        "Phases 2–3 — service writes": [
            "Core/Repositories/Protocols/BodyweightEntryRepositoryProtocol.swift :: func fetch(byId id: UUID) async throws -> BodyweightEntry?",
            "Core/Repositories/Protocols/ExerciseRepositoryProtocol.swift :: func fetch(byId id: UUID) async throws -> Exercise?",
            "Core/Repositories/Protocols/ExerciseStatsRepositoryProtocol.swift :: func fetch(for exerciseId: UUID) async throws -> ExerciseStats?",
            "Core/Repositories/Protocols/ExerciseStatsRepositoryProtocol.swift :: func fetchAll() async throws -> [ExerciseStats]",
            "Core/Repositories/Protocols/PerformanceRecordRepositoryProtocol.swift :: func fetch(exerciseId: UUID, recordType: RecordType, reps: Int?) async throws -> PerformanceRecord?",
            "Core/Repositories/Protocols/PerformanceRecordRepositoryProtocol.swift :: func fetchAll(for exerciseId: UUID) async throws -> [PerformanceRecord]",
            "Core/Repositories/Protocols/PerformanceRecordRepositoryProtocol.swift :: func fetchAll(for exerciseId: UUID, recordType: RecordType) async throws -> [PerformanceRecord]",
            "Core/Repositories/Protocols/SetRepositoryProtocol.swift :: func create(workoutId: UUID, exerciseId: UUID, date: Date, setType: SetType, orderInWorkout: Int, orderInExercise: Int, weight: Double?, reps: Int?, leftReps: Int?, rightReps: Int?, rir: Double?, leftRIR: Double?, rightRIR: Double?, supersetGroupId: UUID?) async throws -> WorkoutSet",
            "Core/Repositories/Protocols/SetRepositoryProtocol.swift :: func fetch(byId id: UUID) async throws -> WorkoutSet?",
            "Core/Repositories/Protocols/SetRepositoryProtocol.swift :: func fetchSets(for exerciseId: UUID, reps: Int, orderedBy: SetSortOrder) async throws -> [WorkoutSet]",
            "Core/Repositories/Protocols/SetRepositoryProtocol.swift :: func fetchBestEligibleSet(for exerciseId: UUID, reps: Int, excludeWarmups: Bool, excludingSetId: UUID?, excludedWorkoutIds: Set<UUID>) async throws -> WorkoutSet?",
            "Core/Repositories/Protocols/TemplateRepositoryProtocol.swift :: func fetchTemplate(byId id: UUID) async throws -> WorkoutTemplate?",
            "Core/Repositories/Protocols/WorkoutRepositoryProtocol.swift :: func fetch(byId id: UUID) async throws -> Workout?"
        ],
        "Phase 5 — workout screens' sets": [
            "Features/Workout/ViewModels/ActiveWorkoutViewModel.swift :: var setsByExercise: [UUID: [WorkoutSet]]",
            "Features/Workout/ViewModels/EditWorkoutViewModel.swift :: var workout: Workout?",
            "Features/Workout/ViewModels/EditWorkoutViewModel.swift :: var setsByExercise: [UUID: [WorkoutSet]]",
            "Features/Workout/Views/SetRowView.swift :: let set: WorkoutSet",
            "Features/Workout/Views/SetTableView.swift :: let set: WorkoutSet",
            "Features/Workout/Views/SetTableView.swift :: let siblingsSets: [WorkoutSet]"
        ],
        "Phase 6 — long-tail reads": [
            "Core/Repositories/Protocols/BodyweightEntryRepositoryProtocol.swift :: func fetchAll(for healthProfileId: UUID) async throws -> [BodyweightEntry]",
            "Core/Repositories/Protocols/BodyweightEntryRepositoryProtocol.swift :: func fetchClosest(to date: Date, healthProfileId: UUID) async throws -> BodyweightEntry?",
            "Core/Repositories/Protocols/ExerciseRepositoryProtocol.swift :: func fetchAll() async throws -> [Exercise]",
            "Core/Repositories/Protocols/ExerciseRepositoryProtocol.swift :: func search(name: String) async throws -> [Exercise]",
            "Core/Repositories/Protocols/FatigueObservationRepositoryProtocol.swift :: func fetchObservations(for workoutId: UUID) async throws -> [FatigueObservation]",
            "Core/Repositories/Protocols/FatigueObservationRepositoryProtocol.swift :: func fetchObservations(exerciseId: UUID, limit: Int?) async throws -> [FatigueObservation]",
            "Core/Repositories/Protocols/FatigueObservationRepositoryProtocol.swift :: func fetchAudits(for workoutId: UUID) async throws -> [FatigueLearningSetAudit]",
            "Core/Repositories/Protocols/FatigueObservationRepositoryProtocol.swift :: func fetchAudits(workoutId: UUID, exerciseId: UUID) async throws -> [FatigueLearningSetAudit]",
            "Core/Repositories/Protocols/FatigueObservationRepositoryProtocol.swift :: func fetchAudits(exerciseId: UUID, limit: Int?) async throws -> [FatigueLearningSetAudit]",
            "Core/Repositories/Protocols/HealthProfileRepositoryProtocol.swift :: func fetch() async throws -> HealthProfile?",
            "Core/Repositories/Protocols/HealthProfileRepositoryProtocol.swift :: func fetchOrCreate() async throws -> HealthProfile",
            "Core/Repositories/Protocols/PerformanceRecordRepositoryProtocol.swift :: func fetchRecentRepMaxRecords(since: Date) async throws -> [PerformanceRecord]",
            "Core/Repositories/Protocols/ProgramRepositoryProtocol.swift :: func fetch(byId id: UUID) async throws -> Program?",
            "Core/Repositories/Protocols/ProgramRepositoryProtocol.swift :: func fetchAll() async throws -> [Program]",
            "Core/Repositories/Protocols/SetRepositoryProtocol.swift :: func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]",
            "Core/Repositories/Protocols/SetRepositoryProtocol.swift :: func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet]",
            "Core/Repositories/Protocols/SetRepositoryProtocol.swift :: func fetchSets(from startDate: Date, to endDate: Date) async throws -> [WorkoutSet]",
            "Core/Repositories/Protocols/SetRepositoryProtocol.swift :: func fetchSets(exerciseId: UUID, from startDate: Date?, to endDate: Date) async throws -> [WorkoutSet]",
            "Core/Repositories/Protocols/TemplateRepositoryProtocol.swift :: func fetchAllTemplates() async throws -> [WorkoutTemplate]",
            "Core/Repositories/Protocols/TemplateRepositoryProtocol.swift :: func fetchTemplateExercises(for templateId: UUID) async throws -> [TemplateExercise]",
            "Core/Repositories/Protocols/TemplateRepositoryProtocol.swift :: func fetchTemplateSets(for templateExerciseId: UUID) async throws -> [TemplateSet]",
            "Core/Repositories/Protocols/WorkoutRepositoryProtocol.swift :: func fetch(byIds ids: Set<UUID>) async throws -> [Workout]",
            "Core/Repositories/Protocols/WorkoutRepositoryProtocol.swift :: func fetchInProgress() async throws -> Workout?",
            "Core/Repositories/Protocols/WorkoutRepositoryProtocol.swift :: func fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout]",
            "Core/Repositories/Protocols/WorkoutRepositoryProtocol.swift :: func fetchAllWorkouts(limit: Int?, offset: Int?) async throws -> [Workout]",
            "Features/Exercise/ViewModels/ExerciseDetailViewModel.swift :: var exercise: Exercise?",
            "Features/Exercise/ViewModels/ExerciseDetailViewModel.swift :: var stats: ExerciseStats?",
            "Features/Exercise/ViewModels/ExerciseListViewModel.swift :: private(set) var allExercises: [Exercise]",
            "Features/Exercise/ViewModels/ExerciseListViewModel.swift :: var exercises: [Exercise]",
            "Features/Exercise/ViewModels/ExerciseListViewModel.swift :: var allExerciseStats: [UUID: ExerciseStats]",
            "Features/Exercise/Views/AssignMuscleGroupsView.swift :: @State private var orderedExercises: [Exercise]",
            "Features/Exercise/Views/ExerciseCardView.swift :: let exercise: Exercise",
            "Features/Exercise/Views/ExerciseCardView.swift :: let stats: ExerciseStats?",
            "Features/Settings/ViewModels/BodyweightLogViewModel.swift :: var entries: [BodyweightEntry]",
            "Features/Settings/Views/FatigueLearningAdminView.swift :: @State private var audits: [FatigueLearningSetAudit]",
            "Features/Templates/Views/TemplateImportReviewSheet.swift :: @State private var allExercises: [Exercise]",
            "Features/Workout/Views/ExercisePickerSheet.swift :: @State private var exercises: [Exercise]"
        ]
    ]

    func testLiveModelBoundariesMatchExplicitPhaseAllowlist() throws {
        let found = try Self.repositoryReturnSites().union(Self.featureStorageSites())
        let allowed = Self.allowlistByRemovalPhase.values.reduce(into: Set<String>()) {
            $0.formUnion($1)
        }
        let listedCount = Self.allowlistByRemovalPhase.values.reduce(0) { $0 + $1.count }

        XCTAssertEqual(
            listedCount,
            allowed.count,
            "The same live-model crossing is listed under more than one removal phase."
        )

        let newCrossings = found.subtracting(allowed).sorted()
        let staleEntries = allowed.subtracting(found).sorted()

        XCTAssertTrue(
            newCrossings.isEmpty && staleEntries.isEmpty,
            """
            SwiftData live-model boundary inventory changed.

            New crossings (remove them, or assign the phase that will):
              \(newCrossings.isEmpty ? "none" : newCrossings.joined(separator: "\n  "))

            Stale allowlist entries (remove them from the ratchet):
              \(staleEntries.isEmpty ? "none" : staleEntries.joined(separator: "\n  "))
            """
        )
    }

    // MARK: - Source scanning

    private static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Repster")
    }

    private static func repositoryReturnSites() throws -> Set<String> {
        let protocolsRoot = sourceRoot.appendingPathComponent("Core/Repositories/Protocols")
        var sites: Set<String> = []

        for url in try swiftFiles(under: protocolsRoot) where url.lastPathComponent.hasSuffix("RepositoryProtocol.swift") {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let relative = relativePath(for: url)

            for declaration in functionDeclarations(in: contents) {
                guard let arrow = declaration.range(of: "->", options: .backwards) else { continue }
                let returnType = String(declaration[arrow.upperBound...])
                guard containsModelType(returnType) else { continue }
                sites.insert("\(relative) :: \(declaration)")
            }
        }

        return sites
    }

    private static func featureStorageSites() throws -> Set<String> {
        let featuresRoot = sourceRoot.appendingPathComponent("Features")
        var sites: Set<String> = []

        for url in try swiftFiles(under: featuresRoot) {
            let relative = relativePath(for: url)
            guard relative.contains("/Views/") || relative.contains("/ViewModels/") else { continue }

            let contents = try String(contentsOf: url, encoding: .utf8)
            var braceDepth = 0
            var typeScopes: [(bodyDepth: Int, scansStorage: Bool)] = []

            for rawLine in contents.components(separatedBy: .newlines) {
                while let scope = typeScopes.last, scope.bodyDepth > braceDepth {
                    typeScopes.removeLast()
                }

                let code = String(rawLine.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false)[0])
                let line = code.trimmingCharacters(in: .whitespaces)

                if let typeMatch = line.range(
                    of: #"\b(?:class|struct)\s+[A-Za-z_][A-Za-z0-9_]*"#,
                    options: .regularExpression
                ), line.contains("{") {
                    let words = line[typeMatch].split(whereSeparator: { $0.isWhitespace })
                    let name = String(words.last ?? "")
                    let conformsToView = line.range(
                        of: #":\s*[^\{]*\bView\b"#,
                        options: .regularExpression
                    ) != nil
                    typeScopes.append((braceDepth + 1, name.hasSuffix("ViewModel") || conformsToView))
                }

                if let scope = typeScopes.last,
                   scope.scansStorage,
                   scope.bodyDepth == braceDepth,
                   let declaration = storedPropertyDeclaration(from: line) {
                    sites.insert("\(relative) :: \(declaration)")
                }

                braceDepth += code.filter { $0 == "{" }.count
                braceDepth -= code.filter { $0 == "}" }.count
            }
        }

        return sites
    }

    private static func functionDeclarations(in source: String) -> [String] {
        var declarations: [String] = []
        var pieces: [String] = []
        var parenthesisDepth = 0

        for rawLine in source.components(separatedBy: .newlines) {
            let code = String(rawLine.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false)[0])
                .trimmingCharacters(in: .whitespaces)

            if pieces.isEmpty {
                guard code.range(of: #"\bfunc\s+"#, options: .regularExpression) != nil else { continue }
            }

            pieces.append(code)
            parenthesisDepth += code.filter { $0 == "(" }.count
            parenthesisDepth -= code.filter { $0 == ")" }.count

            if parenthesisDepth == 0 {
                declarations.append(normalizeWhitespace(pieces.joined(separator: " ")))
                pieces.removeAll(keepingCapacity: true)
            }
        }

        return declarations
    }

    private static func storedPropertyDeclaration(from line: String) -> String? {
        guard let propertyKeyword = line.range(
            of: #"\b(?:let|var)\s+[A-Za-z_][A-Za-z0-9_]*\s*"#,
            options: .regularExpression
        ) else { return nil }

        let tail = line[propertyKeyword.upperBound...]
        if tail.first == ":" {
            let typedTail = tail.dropFirst()
            let equals = typedTail.firstIndex(of: "=")
            let brace = typedTail.firstIndex(of: "{")
            if let brace, equals == nil || brace < equals! {
                return nil
            }
            let typeEnd = equals ?? typedTail.endIndex
            let declaredType = String(typedTail[..<typeEnd])
            guard containsModelType(declaredType) else { return nil }

            let declarationEnd = line.firstIndex(of: "=") ?? line.endIndex
            return normalizeWhitespace(String(line[..<declarationEnd]))
        }

        // Cover the obvious inferred forms (`let exercise = Exercise(...)` and
        // `var sets = [WorkoutSet]()`), without treating static member references such as
        // `HealthProfile.defaultAlertMode` as stored live models.
        guard let equals = tail.firstIndex(of: "=") else { return nil }
        let initializer = tail[tail.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        let constructsModel = modelTypes.contains { model in
            initializer.range(of: "^\(model)\\s*\\(", options: .regularExpression) != nil
                || initializer.range(of: "^\\[\\s*\(model)\\s*\\]\\s*\\(", options: .regularExpression) != nil
        }
        guard constructsModel else { return nil }
        return normalizeWhitespace(String(line[..<equals]))
    }

    private static func containsModelType(_ text: String) -> Bool {
        modelTypes.contains { model in
            text.range(of: "\\b\(model)\\b", options: .regularExpression) != nil
        }
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .replacingOccurrences(of: "( ", with: "(")
            .replacingOccurrences(of: " )", with: ")")
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw XCTSkip("Source tree not readable at \(root.path)")
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private static func relativePath(for url: URL) -> String {
        url.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
    }
}
