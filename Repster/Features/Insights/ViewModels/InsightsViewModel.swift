// InsightsViewModel.swift
// State for the Insights feed.

import SwiftUI

@Observable
@MainActor
final class InsightsViewModel {

    var insights: [InsightItem] = []
    /// Nil only before the first load resolves. The status layer always has
    /// something to say once loaded, so the screen is never blank.
    var status: TrainingStatus?
    var isLoading = false
    var hasLoaded = false
    var musclePanelExpanded = false

    private let insightsService: any InsightsServiceProtocol

    init(insightsService: any InsightsServiceProtocol) {
        self.insightsService = insightsService
    }

    /// New insights stay visually marked from the captured snapshot even
    /// though they're flagged seen (and the badge cleared) right after load.
    var newInsights: [InsightItem] {
        insights.filter(\.isNew)
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            try await insightsService.refreshIfNeeded()
            status = try await insightsService.fetchTrainingStatus()
            insights = try await insightsService.fetchActiveInsights()
            try await insightsService.markAllSeen()
        } catch {
            dbg("[InsightsViewModel] Failed to load insights: \(error)")
        }
    }

    /// How long the user has had this finding in front of them — a thumbs-down
    /// on day one means something different from one after three weeks.
    func ageInDays(of insight: InsightItem) -> Int {
        max(0, Calendar.current.dateComponents(
            [.day], from: insight.generatedAt, to: Date()
        ).day ?? 0)
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
