import Foundation
import SwiftData

@Model
final class TemplateSet {
    var id: UUID
    var templateExerciseId: UUID
    var setType: SetType
    var targetRepMin: Int?
    var targetRepMax: Int?
    var targetRIR: Int?
    var orderInExercise: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        templateExerciseId: UUID,
        setType: SetType = .working,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        targetRIR: Int? = nil,
        orderInExercise: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.templateExerciseId = templateExerciseId
        self.setType = setType
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.targetRIR = targetRIR
        self.orderInExercise = orderInExercise
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
