// ProgramSeedLoader.swift
// Loads seed_programs.json from the bundle. Parallel to SeedDataLoader, deliberately.

import Foundation

enum ProgramSeedLoader {
    enum LoadError: Error {
        case fileNotFound
        case decodingFailed(Error)
    }

    /// Parses the bundled program catalogue.
    ///
    /// `bundle` is injectable so tests can point at a fixture without relying on the catalogue
    /// being a member of the test target.
    static func loadPrograms(from bundle: Bundle = .main) throws -> [ProgramSeedDTO] {
        guard let url = bundle.url(forResource: "seed_programs", withExtension: "json") else {
            throw LoadError.fileNotFound
        }

        let data = try Data(contentsOf: url)

        do {
            return try JSONDecoder().decode(ProgramSeedFile.self, from: data).programs
        } catch {
            throw LoadError.decodingFailed(error)
        }
    }
}
