// HomeSectionConfig.swift
// Model for home screen section visibility and ordering.
// Only the new widget sections (Monthly Stats, Recent PRs, Trending Up) are customizable.
// Recent Workouts is always fixed at the bottom.

import Foundation

enum HomeSectionId: String, Codable, CaseIterable, Identifiable {
    case monthlyStats
    case recentPRs
    case trendingUp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthlyStats: return "Monthly Stats"
        case .recentPRs: return "Recent PRs"
        case .trendingUp: return "Trending Up"
        }
    }
}

struct HomeSectionEntry: Codable, Identifiable {
    let sectionId: HomeSectionId
    var visible: Bool

    var id: String { sectionId.rawValue }
}

struct HomeSectionConfig: Codable {
    var sections: [HomeSectionEntry]

    static let `default` = HomeSectionConfig(sections: [
        HomeSectionEntry(sectionId: .monthlyStats, visible: true),
        HomeSectionEntry(sectionId: .recentPRs, visible: true),
        HomeSectionEntry(sectionId: .trendingUp, visible: true),
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
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
