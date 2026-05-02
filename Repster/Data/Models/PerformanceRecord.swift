import Foundation
import SwiftData

// iOS 18+: Add the following index macro at module scope when minimum target is raised:
// #Index<PerformanceRecord>([\.exerciseId, \.recordType, \.reps])

@Model
final class PerformanceRecord {
    var id: UUID
    var exerciseId: UUID
    var recordType: RecordType
    var reps: Int?
    var value: Double
    var setId: UUID
    var date: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        recordType: RecordType,
        reps: Int? = nil,
        value: Double,
        setId: UUID,
        date: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.recordType = recordType
        self.reps = reps
        self.value = value
        self.setId = setId
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PerformanceRecord: @unchecked Sendable {}
