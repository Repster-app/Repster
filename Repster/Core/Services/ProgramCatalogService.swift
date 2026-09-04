// ProgramCatalogService.swift
// Turns a catalogue entry into WorkoutTemplates. See ProgramCatalogServiceProtocol for the
// contract and ONBOARDING_REDESIGN_SCOPING.md §4.3 for why it works this way.

import Foundation

actor ProgramCatalogService: ProgramCatalogServiceProtocol {

    private let templateService: any TemplateServiceProtocol
    private let exerciseRepository: any ExerciseRepositoryProtocol
    private let bundle: Bundle

    /// Parsed once — the catalogue is bundled and cannot change while the app runs.
    private var cachedPrograms: [ProgramSeedDTO]?

    init(
        templateService: any TemplateServiceProtocol,
        exerciseRepository: any ExerciseRepositoryProtocol,
        bundle: Bundle = .main
    ) {
        self.templateService = templateService
        self.exerciseRepository = exerciseRepository
        self.bundle = bundle
    }

    // MARK: - Catalogue

    nonisolated func availablePrograms() throws -> [ProgramSeedDTO] {
        try ProgramSeedLoader.loadPrograms(from: bundle)
    }

    private func programs() throws -> [ProgramSeedDTO] {
        if let cachedPrograms { return cachedPrograms }
        let loaded = try ProgramSeedLoader.loadPrograms(from: bundle)
        cachedPrograms = loaded
        return loaded
    }

    // MARK: - Materialisation

    @discardableResult
    func materialise(programId: String) async throws -> ProgramMaterialisationResult {
        guard let program = try programs().first(where: { $0.id == programId }) else {
            throw ProgramCatalogError.unknownProgram(programId)
        }

        let existing = try await templateService.fetchAllTemplates()

        // Idempotency. If a folder already carries this program's name *and* holds one of its
        // sessions, it is ours — a double-tapped CTA or a retried save, not a second program.
        // Return what is there rather than writing a duplicate set.
        if let alreadyThere = existingTemplates(of: program, in: existing) {
            return ProgramMaterialisationResult(
                programId: program.id,
                folderName: alreadyThere.folder,
                templateIds: alreadyThere.ids,
                skippedExercises: []
            )
        }

        // A folder of the same name that is *not* ours belongs to the user. Never merge into it.
        let folderName = availableFolderName(for: program.name, in: existing)

        // One fetch, one map. Case-insensitive because the catalogue is hand-edited.
        let library = try await exerciseRepository.fetchAll()
        var idByName: [String: UUID] = [:]
        for exercise in library {
            idByName[exercise.name.lowercased()] = exercise.id
        }

        var templateIds: [UUID] = []
        var skipped: [String] = []

        for (index, session) in program.sessions.enumerated() {
            var saveExercises: [TemplateSaveExercise] = []

            for entry in session.exercises {
                guard let exerciseId = idByName[entry.exercise.lowercased()] else {
                    // Non-fatal on purpose: a program short one accessory is still useful, and
                    // failing at the end of onboarding is not.
                    skipped.append(entry.exercise)
                    continue
                }

                let sets = (0..<entry.sets).map { setIndex in
                    TemplateSaveSet(
                        setType: .working,
                        targetRepMin: entry.repMin,
                        targetRepMax: entry.repMax,
                        targetRIR: entry.rir,
                        orderInExercise: setIndex
                    )
                }

                saveExercises.append(
                    TemplateSaveExercise(
                        exerciseId: exerciseId,
                        orderInTemplate: saveExercises.count,
                        supersetGroupId: nil,
                        restTimeSeconds: entry.restSeconds,
                        notes: nil,
                        sets: sets
                    )
                )
            }

            // A session that resolved to nothing would be an empty template on the user's
            // Templates screen. Skip it rather than ship a shell.
            guard !saveExercises.isEmpty else { continue }

            let id = try await templateService.createTemplate(
                TemplateSaveData(
                    name: session.name,
                    notes: nil,
                    folder: folderName,
                    orderInFolder: index,
                    exercises: saveExercises
                )
            )
            templateIds.append(id)
        }

        guard !templateIds.isEmpty else {
            throw ProgramCatalogError.noResolvableExercises(program.id)
        }

        return ProgramMaterialisationResult(
            programId: program.id,
            folderName: folderName,
            templateIds: templateIds,
            skippedExercises: skipped
        )
    }

    // MARK: - Folder resolution

    /// Templates already stored for this program, if the folder looks like ours.
    private func existingTemplates(
        of program: ProgramSeedDTO,
        in templates: [TemplateSummary]
    ) -> (folder: String, ids: [UUID])? {
        let key = TemplateFolder.groupingKey(program.name)
        let inFolder = templates.filter { TemplateFolder.groupingKey($0.folder) == key }
        guard !inFolder.isEmpty else { return nil }

        let sessionNames = Set(program.sessions.map { $0.name.lowercased() })
        guard inFolder.contains(where: { sessionNames.contains($0.name.lowercased()) }) else {
            return nil
        }

        return (inFolder.first?.folder ?? program.name, inFolder.map(\.id))
    }

    /// `Full Body`, else `Full Body 2`, `Full Body 3`… Never returns a name already in use.
    private func availableFolderName(for name: String, in templates: [TemplateSummary]) -> String {
        let taken = Set(templates.compactMap { TemplateFolder.groupingKey($0.folder) })
        guard let base = TemplateFolder.groupingKey(name), taken.contains(base) else { return name }

        var suffix = 2
        while taken.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(name) \(suffix)"
    }
}
