// SupersetPartnerPicker.swift
// Pick another exercise to superset with, mid-workout.
// Spec: SUPERSETS_SCOPING.md §6 — reached from the exercise tab strip's long-press menu.

import SwiftUI

/// Choose which exercise to pair with, from the ones already in this workout.
///
/// Deliberately not the exercise *library*: a superset is a relationship between two things you are
/// already doing today, and offering the full catalogue here would conflate pairing with adding.
/// Add the exercise first, then pair it.
struct SupersetPartnerPicker: View {

    /// A candidate's existing superset, when it already has one.
    ///
    /// The strip has no letters — a group is identified by its colour and by who is in it, nothing
    /// else — so a row that says only "will move" tells you nothing about the group you are about
    /// to join. Both halves are needed: `color` ties the row back to the container in the strip
    /// behind this sheet, and `partnerNames` says the same thing in words, because colour alone is
    /// no use to anyone reading this with VoiceOver or unable to tell chart5 from chart7.
    struct ExistingGroup: Equatable {
        /// The other members, excluding the candidate itself. Never empty: a group of one is not a
        /// group, and the caller returns nil for those.
        let partnerNames: [String]
        let color: Color
    }

    /// The exercise the superset is being built around.
    let anchor: ChartExerciseData?

    /// Every other exercise in the workout, in strip order.
    let candidates: [ChartExerciseData]

    /// Whether a candidate already sits next to the anchor.
    ///
    /// A group has to be contiguous — a container cannot wrap two tabs with a third between them —
    /// so picking a distant partner reorders the workout. The row says so rather than letting the
    /// strip rearrange itself unexplained. Only consulted for ungrouped candidates: joining an
    /// existing group moves the *anchor*, not the candidate.
    let isAdjacent: (UUID) -> Bool

    /// The group a candidate is already in, or nil when it is ungrouped.
    let existingGroup: (UUID) -> ExistingGroup?

    let onPick: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(candidates, id: \.id) { candidate in
                    Button {
                        onPick(candidate.id)
                    } label: {
                        row(for: candidate)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.bgCard)
                }
            } header: {
                Text("Alternate set for set. Rest runs after the last exercise in the group.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Superset \(anchorName) with")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    // MARK: - Rows

    private var anchorName: String { anchor?.name ?? "Exercise" }

    @ViewBuilder
    private func row(for candidate: ChartExerciseData) -> some View {
        let group = existingGroup(candidate.id)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textPrimary)

                if let group {
                    HStack(spacing: 5) {
                        // Full strength rather than the row's secondary tint: this dot is the only
                        // thing tying the row to a specific container in the strip, so dimming it
                        // to match the text would take the identification away.
                        Circle()
                            .fill(group.color)
                            .frame(width: 7, height: 7)

                        Text("Adds \(anchorName) to this superset")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.textTertiary)
                    }
                } else if !isAdjacent(candidate.id) {
                    Text("Will move next to \(anchorName)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.left.chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(group?.color ?? .accent)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: candidate, group: group))
    }

    /// Says in words what the dot says in colour.
    private func accessibilityLabel(for candidate: ChartExerciseData, group: ExistingGroup?) -> String {
        guard let group else {
            return isAdjacent(candidate.id)
                ? candidate.name
                : "\(candidate.name). Will move next to \(anchorName)"
        }
        let partners = ListFormatter.localizedString(byJoining: group.partnerNames)
        return "\(candidate.name). Already supersetted with \(partners). Adds \(anchorName) to this superset"
    }
}
