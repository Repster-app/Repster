import Foundation
import SwiftData

@Model
final class TemplateExercise {
    var id: UUID
    var templateId: UUID
    var exerciseId: UUID
    var orderInTemplate: Int
    var supersetGroupId: UUID?
    var restTimeSeconds: Int?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        templateId: UUID,
        exerciseId: UUID,
        orderInTemplate: Int,
        supersetGroupId: UUID? = nil,
        restTimeSeconds: Int? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.templateId = templateId
        self.exerciseId = exerciseId
        self.orderInTemplate = orderInTemplate
        self.supersetGroupId = supersetGroupId
        self.restTimeSeconds = restTimeSeconds
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension TemplateExercise: @unchecked Sendable {}
