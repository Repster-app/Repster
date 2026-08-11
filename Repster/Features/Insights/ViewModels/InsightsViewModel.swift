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

    /// `initialStatus` is the status Home already computed for the hook card.
    /// Handing it over means the screen the user just tapped into opens with
    /// its top half already drawn, instead of an empty scroll view.
    init(
        insightsService: any InsightsServiceProtocol,
        initialStatus: TrainingStatus? = nil
    ) {
        self.insightsService = insightsService
        self.status = initialStatus
    }

    /// New insights stay visually marked from the captured snapshot even
    /// though they're flagged seen (and the badge cleared) right after load.
    var newInsights: [InsightItem] {
        insights.filter(\.isNew)
    }

    /// Ordered so the screen is complete before the push animation finishes.
    ///
    /// Reading the persisted feed costs a couple of milliseconds; re-analysing
    /// and re-deriving the status cost hundreds, because both walk the entire
    /// set history. Doing the cheap reads first — and skipping the status
    /// entirely when Home already handed one over — is the difference between
    /// content appearing with the screen and appearing half a second into it.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let persisted = try await insightsService.fetchActiveInsights()
            let resolvedStatus: TrainingStatus
            if let status {
                resolvedStatus = status
            } else {
                resolvedStatus = try await insightsService.fetchTrainingStatus()
            }

            // One assignment pass, so the feed lands in a single layout rather
            // than popping in section by section.
            status = resolvedStatus
            insights = persisted
            hasLoaded = true

            // Only re-read what a re-analysis could actually have changed.
            if try await insightsService.refreshIfNeeded() {
                let freshStatus = try await insightsService.fetchTrainingStatus()
                let freshInsights = try await insightsService.fetchActiveInsights()
                withAnimation(.easeInOut(duration: 0.2)) {
                    status = freshStatus
                    insights = freshInsights
                }
            }

            // Last: marking seen clears `isNew` on the records, so anything
            // fetched after this point would lose its NEW marker mid-screen.
            try await insightsService.markAllSeen()
        } catch {
            dbg("[InsightsViewModel] Failed to load insights: \(error)")
            hasLoaded = true
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
