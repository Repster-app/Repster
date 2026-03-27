// HomeSectionConfig.swift
// Model for home screen section visibility, ordering, and display preferences.

import Foundation

// MARK: - PR Display Mode

enum PRDisplayMode: String, Codable, CaseIterable, Equatable {
    case standard   // 3 full-width cards
    case compact    // 6 half-width cards in 2-column grid

    var displayName: String {
        switch self {
        case .standard: return "Standard (3)"
        case .compact: return "Compact (6)"
        }
    }

    var fetchLimit: Int {
        switch self {
        case .standard: return 3
        case .compact: return 6
        }
    }
}

// MARK: - Section ID

enum HomeSectionId: String, Codable, Hashable, Identifiable {
    case monthlyStats
    case recentPRs
    case recentWorkouts
    case legacyTrendingUp = "trendingUp"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthlyStats: return "Monthly Stats"
        case .recentPRs: return "Recent PRs"
        case .recentWorkouts: return "Recent Workouts"
        case .legacyTrendingUp: return "Trending Up"
        }
    }

    var isSupportedHomeSection: Bool {
        switch self {
        case .monthlyStats, .recentPRs, .recentWorkouts:
            return true
        case .legacyTrendingUp:
            return false
        }
    }
}

// MARK: - Section Entry

struct HomeSectionEntry: Codable, Equatable, Identifiable {
    let sectionId: HomeSectionId
    var visible: Bool

    var id: String { sectionId.rawValue }
}

// MARK: - Config

struct HomeSectionConfig: Equatable {
    var sections: [HomeSectionEntry]
    var recentWorkoutsCount: Int
    var prDisplayMode: PRDisplayMode

    static let `default` = HomeSectionConfig(
        sections: [
            HomeSectionEntry(sectionId: .monthlyStats, visible: true),
            HomeSectionEntry(sectionId: .recentPRs, visible: true),
            HomeSectionEntry(sectionId: .recentWorkouts, visible: true),
        ],
        recentWorkoutsCount: 5,
        prDisplayMode: .standard
    )

    var visibleSections: [HomeSectionEntry] {
        sections.filter(\.visible)
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "homeSectionConfig"

    static func load() -> HomeSectionConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(HomeSectionConfig.self, from: data) else {
            return .default
        }
        let sanitized = config.sanitized()
        if sanitized != config {
            sanitized.save()
        }
        return sanitized
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    private func sanitized() -> HomeSectionConfig {
        let supportedOrder: [HomeSectionId] = [.monthlyStats, .recentPRs, .recentWorkouts]
        var seen = Set<HomeSectionId>()
        var sanitizedSections: [HomeSectionEntry] = []

        for entry in sections where entry.sectionId.isSupportedHomeSection {
            guard seen.insert(entry.sectionId).inserted else { continue }
            sanitizedSections.append(entry)
        }

        for sectionId in supportedOrder where !seen.contains(sectionId) {
            sanitizedSections.append(HomeSectionEntry(sectionId: sectionId, visible: true))
        }

        return HomeSectionConfig(
            sections: sanitizedSections,
            recentWorkoutsCount: max(1, min(10, recentWorkoutsCount)),
            prDisplayMode: prDisplayMode
        )
    }
}

// MARK: - Codable (backwards-compatible)

extension HomeSectionConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case sections
        case recentWorkoutsCount
        case prDisplayMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decode([HomeSectionEntry].self, forKey: .sections)
        recentWorkoutsCount = try container.decodeIfPresent(Int.self, forKey: .recentWorkoutsCount) ?? 5
        prDisplayMode = try container.decodeIfPresent(PRDisplayMode.self, forKey: .prDisplayMode) ?? .standard
    }
}
