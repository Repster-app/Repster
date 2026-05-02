import Foundation

enum SeedDataLoader {
    enum SeedError: Error {
        case fileNotFound
        case decodingFailed(Error)
    }

    /// Loads and parses seed_exercises.json from the app bundle.
    static func loadExercises() throws -> [SeedExerciseDTO] {
        guard let url = Bundle.main.url(forResource: "seed_exercises", withExtension: "json") else {
            throw SeedError.fileNotFound
        }

        let data = try Data(contentsOf: url)

        do {
            let file = try JSONDecoder().decode(SeedExerciseFile.self, from: data)
            return file.exercises
        } catch {
            throw SeedError.decodingFailed(error)
        }
    }
}
