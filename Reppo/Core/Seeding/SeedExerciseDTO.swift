import Foundation

/// DTO for deserializing exercises from seed_exercises.json.
/// Enum fields are kept as raw strings — mapping to Swift enums
/// happens in the SeedExerciseDTO+Mapping extension.
struct SeedExerciseDTO: Codable {
    let name: String
    let equipmentType: String
    let trackingType: String
    let primaryMuscle: String?
    let secondaryMuscles: [String]
    let movementPattern: String?
    let unilateral: Bool
    let unilateralRepTargetMode: String?
    let bodyweightFactor: Double
    let weightIncrement: Double?
    let defaultRestTime: Int?
}

/// Top-level container matching the seed_exercises.json structure.
struct SeedExerciseFile: Codable {
    let exercises: [SeedExerciseDTO]
}
