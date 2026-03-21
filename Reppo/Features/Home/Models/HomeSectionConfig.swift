// HomeSectionConfig.swift
// Model for home screen section visibility and ordering.
// Only Monthly Stats and Recent PRs are customizable.
// Recent Workouts is always fixed at the bottom.

import Foundation

enum HomeSectionId: String, Codable, Hashable, Identifiable {
    case monthlyStats
    case recentPRs
    case legacyTrendingUp = "trendingUp"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthlyStats: return "Monthly Stats"
        case .recentPRs: return "Recent PRs"
        case .legacyTrendingUp: return "Trending Up"
        }
    }

    var isSupportedHomeSection: Bool {
        switch self {
        case .monthlyStats, .recentPRs:
            return true
        case .legacyTrendingUp:
            return false
        }
    }
}

struct HomeSectionEntry: Codable, Equatable, Identifiable {
    let sectionId: HomeSectionId
    var visible: Bool

    var id: String { sectionId.rawValue }
}

struct HomeSectionConfig: Codable, Equatable {
    var sections: [HomeSectionEntry]

    static let `default` = HomeSectionConfig(sections: [
        HomeSectionEntry(sectionId: .monthlyStats, visible: true),
        HomeSectionEntry(sectionId: .recentPRs, visible: true),
    ])

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
        let supportedOrder: [HomeSectionId] = [.monthlyStats, .recentPRs]
        var seen = Set<HomeSectionId>()
        var sanitizedSections: [HomeSectionEntry] = []

        for entry in sections where entry.sectionId.isSupportedHomeSection {
            guard seen.insert(entry.sectionId).inserted else { continue }
            sanitizedSections.append(entry)
        }

        for sectionId in supportedOrder where !seen.contains(sectionId) {
            sanitizedSections.append(HomeSectionEntry(sectionId: sectionId, visible: true))
        }

        return HomeSectionConfig(sections: sanitizedSections)
    }
}
