import Foundation
import SwiftData

@Model
final class ProgramExercise {
    var id: UUID
    var programId: UUID
    var exerciseId: UUID
    var targetRepRange: String?
    var intensityRule: String?
    var minIncrement: Double?
    var maxIncrement: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        programId: UUID,
        exerciseId: UUID,
        targetRepRange: String? = nil,
        intensityRule: String? = nil,
        minIncrement: Double? = nil,
        maxIncrement: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.programId = programId
        self.exerciseId = exerciseId
        self.targetRepRange = targetRepRange
        self.intensityRule = intensityRule
        self.minIncrement = minIncrement
        self.maxIncrement = maxIncrement
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ProgramExercise: @unchecked Sendable {}
