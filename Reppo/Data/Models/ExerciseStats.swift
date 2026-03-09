import Foundation
import SwiftData

@Model
final class ExerciseStats {
    var id: UUID
    var exerciseId: UUID
    var totalWorkouts: Int
    var totalSets: Int
    var totalReps: Int
    var totalVolume: Double
    var maxWeight: Double
    var bestE1RM: Double
    var averageIntensity: Double
    var estimated1RMTrendSlope: Double
    var lastPRDate: Date?
    var lastPerformedDate: Date?
    var maxSessionVolume: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        totalWorkouts: Int = 0,
        totalSets: Int = 0,
        totalReps: Int = 0,
        totalVolume: Double = 0,
        maxWeight: Double = 0,
        bestE1RM: Double = 0,
        averageIntensity: Double = 0,
        estimated1RMTrendSlope: Double = 0,
        lastPRDate: Date? = nil,
        lastPerformedDate: Date? = nil,
        maxSessionVolume: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.totalWorkouts = totalWorkouts
        self.totalSets = totalSets
        self.totalReps = totalReps
        self.totalVolume = totalVolume
        self.maxWeight = maxWeight
        self.bestE1RM = bestE1RM
        self.averageIntensity = averageIntensity
        self.estimated1RMTrendSlope = estimated1RMTrendSlope
        self.lastPRDate = lastPRDate
        self.lastPerformedDate = lastPerformedDate
        self.maxSessionVolume = maxSessionVolume
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ExerciseStats: @unchecked Sendable {}
