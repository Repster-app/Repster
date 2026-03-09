import Foundation
import SwiftData

@Model
final class BodyweightEntry {
    var id: UUID
    var healthProfileId: UUID
    var date: Date
    var bodyweightKg: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        healthProfileId: UUID,
        date: Date = Date(),
        bodyweightKg: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.healthProfileId = healthProfileId
        self.date = date
        self.bodyweightKg = bodyweightKg
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension BodyweightEntry: @unchecked Sendable {}
