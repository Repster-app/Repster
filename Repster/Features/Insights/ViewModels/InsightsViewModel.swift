// InsightsViewModel.swift
// State for the Insights feed.

import SwiftUI

@Observable
@MainActor
final class InsightsViewModel {

    var insights: [InsightItem] = []
    var isLoading = false
    var hasLoaded = false

    private let insightsService: any InsightsServiceProtocol

    init(insightsService: any InsightsServiceProtocol) {
        self.insightsService = insightsService
    }

    /// New insights stay visually marked from the captured snapshot even
    /// though they're flagged seen (and the badge cleared) right after load.
    var newInsights: [InsightItem] {
        insights.filter(\.isNew)
    }

    var earlierInsights: [InsightItem] {
        insights.filter { !$0.isNew }
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            try await insightsService.refreshIfNeeded()
            insights = try await insightsService.fetchActiveInsights()
            try await insightsService.markAllSeen()
        } catch {
            dbg("[InsightsViewModel] Failed to load insights: \(error)")
        }
    }

    func snooze(_ insight: InsightItem) async {
        do {
            try await insightsService.snooze(insightId: insight.id)
            insights.removeAll { $0.id == insight.id }
        } catch {
            dbg("[InsightsViewModel] Failed to snooze insight: \(error)")
        }
    }
}
