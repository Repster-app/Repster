// InsightRuleDiagnosticsView.swift
// What every insight rule did against the user's real data, behind the admin flag.
//
// The feed shows only what survived curation, which hides the distinction that
// matters most when a rule never appears: whether it produced a finding and lost
// the ranking, or produced nothing at all. The first is a weight to change, the
// second a gate to loosen, and from the outside they look identical.
//
// Sibling to InsightGalleryView rather than part of it: the gallery's whole
// premise is that it renders fixtures and never touches real training data, and
// mixing live numbers into it would cost that guarantee.

import SwiftUI

struct InsightRuleDiagnosticsView: View {
    let insightsService: any InsightsServiceProtocol

    @State private var diagnostics: [RuleDiagnostic] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed {
                message(
                    title: "Couldn't run the rules",
                    detail: "The analysis threw while building its context. Check the console for the underlying error."
                )
            } else {
                diagnosticsList
            }
        }
        .background(Color.bg)
        .navigationTitle("Insight Rules")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - List

    private var diagnosticsList: some View {
        List {
            Section {
                Text("Every rule run against your real data, including the findings curation threw away. Nothing here is persisted — opening this screen does not change your feed.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
            .listRowBackground(Color.clear)

            ForEach(StatusGroup.allCases, id: \.self) { group in
                let rules = diagnostics.filter { $0.status == group.status }
                if !rules.isEmpty {
                    Section {
                        ForEach(rules) { RuleRow(diagnostic: $0) }
                            .listRowBackground(Color.bgCard)
                    } header: {
                        Text("\(group.title) (\(rules.count))")
                    } footer: {
                        Text(group.footer)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// Ordered by how actionable the group is, not by rule score: the rules that
    /// produce nothing are the ones worth reading first.
    private enum StatusGroup: CaseIterable {
        case silent, relaxedOnly, rankedOut, cooling, shown

        var status: RuleDiagnostic.Status {
            switch self {
            case .silent: return .silent
            case .relaxedOnly: return .relaxedOnly
            case .rankedOut: return .rankedOut
            case .cooling: return .cooling
            case .shown: return .shown
            }
        }

        var title: String {
            switch self {
            case .silent: return "Produced nothing"
            case .relaxedOnly: return "Relaxed pass only"
            case .rankedOut: return "Ranked out"
            case .cooling: return "Cooling down"
            case .shown: return "In the feed"
            }
        }

        var footer: String {
            switch self {
            case .silent:
                return "Gates never cleared for this data. Re-ranking cannot surface these — the rule has to change, or the data does."
            case .relaxedOnly:
                return "Only the lower-bar pass found anything, so these appear solely when the feed would otherwise be empty."
            case .rankedOut:
                return "These fired but lost their slot. A weighting problem, not a gate problem."
            case .cooling:
                return "Held back by a refire interval even though the finding still holds."
            case .shown:
                return "Currently on the Insights screen."
            }
        }
    }

    // MARK: - Row

    private struct RuleRow: View {
        let diagnostic: RuleDiagnostic

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(InsightCategory(ruleId: diagnostic.ruleId).displayName)
                        .foregroundStyle(Color.textPrimary)
                    Text(diagnostic.ruleId)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text(String(format: "weight %.2f", diagnostic.actionability))
                        .font(.system(size: 11))
                        .fontDesign(.monospaced)
                        .foregroundStyle(Color.textSecondary)
                }

                if let refireAvailableAt = diagnostic.refireAvailableAt {
                    Text("Refires \(refireAvailableAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                }

                ForEach(candidates) { candidate in
                    CandidateRow(candidate: candidate)
                }

                if candidates.isEmpty {
                    Text("No findings")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.vertical, 4)
        }

        /// The relaxed pass is only worth showing when the normal one found
        /// nothing, which is exactly when the engine would consult it too.
        private var candidates: [RuleDiagnostic.Candidate] {
            diagnostic.findings.isEmpty ? diagnostic.relaxedFindings : diagnostic.findings
        }
    }

    private struct CandidateRow: View {
        let candidate: RuleDiagnostic.Candidate

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.2f", candidate.score))
                    .font(.system(size: 12))
                    .fontDesign(.monospaced)
                    .foregroundStyle(Color.accent)
                    .frame(width: 34, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.headline)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        String(format: "effect %.2f · %@", candidate.effectSize,
                               candidate.isDiagnostic ? "diagnostic" : "non-diagnostic")
                    )
                    .font(.system(size: 10))
                    .fontDesign(.monospaced)
                    .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    private func message(title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        isLoading = true
        do {
            diagnostics = try await insightsService.ruleDiagnostics()
            loadFailed = false
        } catch {
            dbg("[InsightRuleDiagnosticsView] Failed to run diagnostics: \(error)")
            loadFailed = true
        }
        isLoading = false
    }
}
