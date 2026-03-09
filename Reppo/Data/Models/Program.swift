import Foundation
import SwiftData

@Model
final class Program {
    var id: UUID
    var name: String
    var progressionModel: String?
    var deloadRules: String?
    var autoRegulationEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        progressionModel: String? = nil,
        deloadRules: String? = nil,
        autoRegulationEnabled: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.progressionModel = progressionModel
        self.deloadRules = deloadRules
        self.autoRegulationEnabled = autoRegulationEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Program: @unchecked Sendable {}
