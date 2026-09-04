// ProgramSeedDTO.swift
// Decodable mirror of seed_programs.json — the starter program catalogue.
//
// Unlike SeedExerciseDTO, nothing here is written at first launch. A program only becomes
// WorkoutTemplates when a user picks it, in onboarding or from the Templates screen, so this
// type is also what the picker renders from. See ONBOARDING_REDESIGN_SCOPING.md §4.2.

import Foundation

struct ProgramSeedFile: Decodable {
    let programs: [ProgramSeedDTO]
}

struct ProgramSeedDTO: Decodable, Identifiable, Sendable, Equatable {
    /// Stable catalogue key (`full_body_3d`). Used for analytics and for the idempotency
    /// guard on materialisation — never shown to the user.
    let id: String
    /// Doubles as the folder name the generated templates land in.
    let name: String
    let daysPerWeek: Int
    let summary: String
    let sessions: [ProgramSeedSessionDTO]

    var sessionCount: Int { sessions.count }

    var totalWorkingSets: Int {
        sessions.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets } }
    }
}

struct ProgramSeedSessionDTO: Decodable, Sendable, Equatable {
    /// Becomes the template name, so it is user-facing.
    let name: String
    let exercises: [ProgramSeedExerciseDTO]
}

struct ProgramSeedExerciseDTO: Decodable, Sendable, Equatable {
    /// Must match an `Exercise.name` from seed_exercises.json exactly.
    /// ProgramCatalogIntegrityTests fails the build if it does not.
    let exercise: String
    let sets: Int
    let repMin: Int
    let repMax: Int
    let rir: Int?
    let restSeconds: Int?
}
