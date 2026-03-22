import Foundation

extension SeedExerciseDTO {
    enum MappingError: Error {
        case invalidTrackingType(String)
        case invalidEquipmentType(String)
        case invalidMovementPattern(String)
    }

    /// Converts this DTO to an Exercise model instance.
    /// Throws MappingError if any enum value is unrecognized.
    func toExercise() throws -> Exercise {
        let mappedTrackingType = try Self.mapTrackingType(trackingType)
        let mappedEquipmentType = try Self.mapEquipmentType(equipmentType)
        let mappedMovementPattern = try movementPattern.map { try Self.mapMovementPattern($0) }

        return Exercise(
            name: name,
            equipmentType: mappedEquipmentType,
            trackingType: mappedTrackingType,
            primaryMuscle: primaryMuscle,
            secondaryMuscles: secondaryMuscles,
            movementPattern: mappedMovementPattern,
            unilateral: unilateral,
            bodyweightFactor: bodyweightFactor,
            weightIncrement: weightIncrement,
            defaultRestTime: defaultRestTime
        )
    }

    // MARK: - Enum Mapping

    private static func mapTrackingType(_ value: String) throws -> TrackingType {
        switch value {
        case "WEIGHT_REPS": return .weightReps
        case "DURATION": return .duration
        case "DURATION_DISTANCE": return .durationDistance
        case "WEIGHT_DISTANCE": return .weightDistance
        case "WEIGHT_REPS_DURATION": return .weightRepsDuration
        case "CUSTOM": return .custom
        default: throw MappingError.invalidTrackingType(value)
        }
    }

    private static func mapEquipmentType(_ value: String) throws -> EquipmentType {
        switch value {
        case "barbell": return .barbell
        case "dumbbell": return .dumbbell
        case "machine_plate": return .machinePlate
        case "machine_pin": return .machinePin
        case "bodyweight": return .bodyweight
        case "sled": return .sled
        case "cable": return .cable
        case "kettlebell": return .kettlebell
        case "band": return .band
        case "other": return .other
        default: throw MappingError.invalidEquipmentType(value)
        }
    }

    private static func mapMovementPattern(_ value: String) throws -> MovementPattern {
        switch value {
        case "hinge": return .hinge
        case "squat": return .squat
        case "press": return .press
        case "pull": return .pull
        case "carry": return .carry
        case "rotation": return .rotation
        case "other": return .other
        default: throw MappingError.invalidMovementPattern(value)
        }
    }
}
