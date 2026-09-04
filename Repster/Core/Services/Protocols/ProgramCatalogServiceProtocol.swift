// ProgramCatalogServiceProtocol.swift
// Reads the starter program catalogue, and turns one program into templates.
//
// A "program" is not an entity. It is a named, ordered set of WorkoutTemplates sharing a
// `folder` — the same call the codebase already made for folders themselves. See
// ONBOARDING_REDESIGN_SCOPING.md §1 for why the dormant `Program` model is not used.

import Foundation

enum ProgramCatalogError: Error, Equatable {
    /// No program in the catalogue has this id.
    case unknownProgram(String)
    /// Every session resolved to zero exercises — the catalogue and the exercise library
    /// have drifted far enough that there is nothing to build.
    case noResolvableExercises(String)
}

/// The outcome of materialising a program. Partial success is normal and expected: a missing
/// accessory should cost one exercise, not the whole program.
struct ProgramMaterialisationResult: Sendable, Equatable {
    let programId: String
    /// Folder the templates landed in. May be suffixed if the user already had that folder.
    let folderName: String
    let templateIds: [UUID]
    /// Exercise names in the catalogue that no longer exist in the library. Non-fatal.
    let skippedExercises: [String]

    var createdCount: Int { templateIds.count }
}

protocol ProgramCatalogServiceProtocol: Sendable {

    /// The catalogue, for the picker. Pure read, no side effects.
    func availablePrograms() throws -> [ProgramSeedDTO]

    /// Writes one program's sessions as templates in a folder named after the program.
    ///
    /// Idempotent by folder name: calling twice does not produce two copies. If the user already
    /// has an unrelated folder of the same name, the new one is suffixed rather than merged into
    /// their work.
    @discardableResult
    func materialise(programId: String) async throws -> ProgramMaterialisationResult
}
