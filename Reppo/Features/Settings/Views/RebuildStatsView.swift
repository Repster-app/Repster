// RebuildStatsView.swift
// Rebuild screen with explanation, 3 rebuild buttons, confirmation alerts, and progress overlay.
// Spec: FR-010, User Story 4
// Feature: 010-settings-and-onboarding WP03 T013

import SwiftUI

struct RebuildStatsView: View {
    let settingsService: any SettingsServiceProtocol

    @State private var isRebuilding = false
    @State private var rebuildStatusMessage = ""
    @State private var showConfirmation = false
    @State private var confirmationMessage = ""
    @State private var pendingRebuildAction: RebuildAction?
    @State private var showCompletion = false
    @State private var completionMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""

    enum RebuildAction {
        case prs, stats, all
    }

    var body: some View {
        List {
            Section {
                Text("Rebuild recomputes all stats and PRs from your raw workout data. Use this after importing data or if you notice any discrepancies.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Button("Rebuild PRs") {
                    pendingRebuildAction = .prs
                    confirmationMessage = "This will recompute all personal records from raw set data."
                    showConfirmation = true
                }
                .foregroundStyle(Color.textPrimary)

                Button("Rebuild Stats") {
                    pendingRebuildAction = .stats
                    confirmationMessage = "This will recompute all exercise statistics from raw set data."
                    showConfirmation = true
                }
                .foregroundStyle(Color.textPrimary)

                Button("Rebuild All") {
                    pendingRebuildAction = .all
                    confirmationMessage = "This will recompute all personal records and exercise statistics from raw set data."
                    showConfirmation = true
                }
                .foregroundStyle(Color.accent)
            }
        }
        .navigationTitle("Rebuild Stats")
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .overlay {
            if isRebuilding {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(Color.accent)
                        Text(rebuildStatusMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(32)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert("Confirm Rebuild", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Rebuild") { executeRebuild() }
        } message: {
            Text(confirmationMessage)
        }
        .alert("Rebuild Complete", isPresented: $showCompletion) {
            Button("OK") {}
        } message: {
            Text(completionMessage)
        }
        .alert("Rebuild Failed", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func executeRebuild() {
        guard let action = pendingRebuildAction else { return }
        Task {
            isRebuilding = true
            rebuildStatusMessage = "Rebuilding…"
            do {
                switch action {
                case .prs:
                    try await settingsService.rebuildPRs()
                    completionMessage = "All personal records have been recomputed."
                case .stats:
                    try await settingsService.rebuildStats()
                    completionMessage = "All exercise statistics have been recomputed."
                case .all:
                    try await settingsService.rebuildAll()
                    completionMessage = "All personal records and statistics have been recomputed."
                }
                isRebuilding = false
                showCompletion = true
            } catch {
                isRebuilding = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
