// InsightsView.swift
// The Insights feed: gated findings from the user's own training data.

import SwiftUI

struct InsightsView: View {
    @State private var viewModel: InsightsViewModel

    init(insightsService: any InsightsServiceProtocol) {
        _viewModel = State(initialValue: InsightsViewModel(insightsService: insightsService))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.hasLoaded && viewModel.insights.isEmpty {
                    emptyState
                } else {
                    if !viewModel.newInsights.isEmpty {
                        section(title: "NEW", insights: viewModel.newInsights)
                    }
                    if !viewModel.earlierInsights.isEmpty {
                        section(
                            title: viewModel.newInsights.isEmpty ? "FINDINGS" : "EARLIER",
                            insights: viewModel.earlierInsights
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .background(Color.bg)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load()
        }
    }

    private func section(title: String, insights: [InsightItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            ForEach(insights) { insight in
                InsightCardView(insight: insight) {
                    Task { await viewModel.snooze(insight) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.textTertiary)

            Text("No findings yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Insights come from your own training data and only appear once there's enough of it to trust. Keep logging — the next analysis runs after your next workout.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 12)
    }
}
