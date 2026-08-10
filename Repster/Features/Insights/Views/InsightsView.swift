// InsightsView.swift
// The Insights feed: gated findings from the user's own training data.

import SwiftUI

struct InsightsView: View {
    @State private var viewModel: InsightsViewModel
    @Environment(ServiceContainer.self) private var services

    init(insightsService: any InsightsServiceProtocol) {
        _viewModel = State(initialValue: InsightsViewModel(insightsService: insightsService))
    }

    var body: some View {
        ScrollView {
            // Ordered weakest claim to strongest: status describes, the panel
            // ranks, findings interpret. The first two always render, so the
            // screen is never empty even when no rule fires.
            VStack(alignment: .leading, spacing: 20) {
                if let status = viewModel.status {
                    TrainingStatusCardView(status: status)

                    if !status.muscles.isEmpty {
                        MuscleVolumePanelView(
                            rows: status.muscles,
                            isExpanded: $viewModel.musclePanelExpanded
                        )
                        .onChange(of: viewModel.musclePanelExpanded) { _, expanded in
                            if expanded {
                                services.analyticsService.musclePanelExpanded(
                                    groupCount: status.muscles.count
                                )
                            }
                        }
                    }
                }

                findingsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .background(Color.bg)
        .navigationTitle("Training Insights")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load()
            // Reported after load so the empty state reflects "no findings yet"
            // rather than "hasn't finished loading". One event per open: the
            // screen view carries the finding counts.
            services.analyticsService.insightsViewed(
                findingCount: viewModel.insights.count,
                hasNew: !viewModel.newInsights.isEmpty,
                hasBaseline: viewModel.status?.baselineSets != nil
            )
        }
    }

    /// Hidden entirely during cold start — a user three days in shouldn't be
    /// told what they haven't earned yet. Once there's history, an empty feed
    /// gets one honest line rather than an icon and an apology.
    @ViewBuilder
    private var findingsSection: some View {
        if !viewModel.insights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(headerTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .kerning(0.8)

                ForEach(viewModel.insights) { insight in
                    InsightCardView(
                        insight: insight,
                        onSnooze: {
                            services.analyticsService.insightSnoozed(
                                ruleId: insight.ruleId, ageDays: viewModel.ageInDays(of: insight)
                            )
                            Task { await viewModel.snooze(insight) }
                        },
                        onExpand: {
                            services.analyticsService.insightExpanded(ruleId: insight.ruleId)
                        },
                        onRate: { useful in
                            services.analyticsService.insightRated(
                                ruleId: insight.ruleId,
                                useful: useful,
                                ageDays: viewModel.ageInDays(of: insight)
                            )
                        }
                    )
                }
            }
        } else if viewModel.hasLoaded, viewModel.status?.baselineSets != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("FINDINGS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .kerning(0.8)

                VStack(spacing: 5) {
                    Text("Nothing stands out this week")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text("Findings only appear when a pattern is strong enough to trust.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .padding(.horizontal, 16)
                .background(Color.bgCard)
                .cornerRadius(14)
            }
        }
    }

    private var headerTitle: String {
        let newCount = viewModel.newInsights.count
        return newCount > 0 ? "FINDINGS · \(newCount) NEW" : "FINDINGS"
    }
}
