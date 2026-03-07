import Foundation
import SwiftData

@Model
final class Workout {
    var id: UUID
    var date: Date
    var title: String?
    var startTime: Date?
    var endTime: Date?
    var duration: Int?
    var perceivedEffort: Double?
    var notes: String?
    var programId: UUID?
    var status: WorkoutStatus
    var createdAt: Date
    var updatedAt: Date

    /// Computed display title: returns user-set title or auto-generates
    /// "Morning/Afternoon/Evening Workout" based on startTime (Strava-style).
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        guard let startTime else { return "Workout" }
        let hour = Calendar.current.component(.hour, from: startTime)
        switch hour {
        case 0..<12: return "Morning Workout"
        case 12..<17: return "Afternoon Workout"
        default: return "Evening Workout"
        }
    }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        duration: Int? = nil,
        perceivedEffort: Double? = nil,
        notes: String? = nil,
        programId: UUID? = nil,
        status: WorkoutStatus = .inProgress,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.perceivedEffort = perceivedEffort
        self.notes = notes
        self.programId = programId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
