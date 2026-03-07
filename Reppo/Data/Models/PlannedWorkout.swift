import Foundation
import SwiftData

@Model
final class PlannedWorkout {
    var id: UUID
    var programId: UUID
    var scheduledDate: Date?
    var weekIndex: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        programId: UUID,
        scheduledDate: Date? = nil,
        weekIndex: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.programId = programId
        self.scheduledDate = scheduledDate
        self.weekIndex = weekIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
