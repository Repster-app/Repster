import Foundation
import SwiftData

@Model
final class PlannedSet {
    var id: UUID
    var plannedWorkoutId: UUID
    var exerciseId: UUID
    var targetReps: Int?
    var targetWeight: Double?
    var targetRPE: Double?
    var orderInWorkout: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        plannedWorkoutId: UUID,
        exerciseId: UUID,
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        targetRPE: Double? = nil,
        orderInWorkout: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.plannedWorkoutId = plannedWorkoutId
        self.exerciseId = exerciseId
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetRPE = targetRPE
        self.orderInWorkout = orderInWorkout
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
