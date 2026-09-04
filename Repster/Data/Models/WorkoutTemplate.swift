import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var id: UUID
    var name: String
    var notes: String?
    /// User-named folder this template belongs to, or nil for "Not in a folder".
    ///
    /// Deliberately a nullable name rather than an entity: a folder exists because a template points
    /// at it and stops existing when the last one leaves. No lifecycle, no orphans, and nil is a
    /// first-class state the list renders as its own section. Optional so lightweight migration adds
    /// it to existing stores without a stage — see TEMPLATES_IMPLEMENTATION_PLAN.md P1.1 and D5.
    var folder: String?
    /// Position within `folder`, for programs whose sessions run in a fixed rotation.
    ///
    /// Optional for the same reason `folder` is: a nullable column is added by lightweight
    /// migration with no stage, and `RepsterMigrationPlan` still declares SchemaV1 alone.
    /// nil means "unordered" — templates the user made by hand keep sorting by the existing
    /// rules, and only a generated program fills this in.
    var orderInFolder: Int?
    var lastUsedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        notes: String? = nil,
        folder: String? = nil,
        orderInFolder: Int? = nil,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.folder = folder
        self.orderInFolder = orderInFolder
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension WorkoutTemplate: @unchecked Sendable {}
