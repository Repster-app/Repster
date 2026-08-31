// SupersetPartnerPicker.swift
// Pick the other half of a superset, mid-workout.
// Spec: SUPERSETS_SCOPING.md §6 — reached from the exercise tab strip's long-press menu.

import SwiftUI

/// Choose which exercise to pair with, from the ones already in this workout.
///
/// Deliberately not the exercise *library*: a superset is a relationship between two things you are
/// already doing today, and offering the full catalogue here would conflate pairing with adding.
/// Add the exercise first, then pair it.
struct SupersetPartnerPicker: View {

    /// The exercise the pair is being built around.
    let anchor: ChartExerciseData?

    /// Every other exercise in the workout, in strip order.
    let candidates: [ChartExerciseData]

    /// Whether a candidate already sits next to the anchor.
    ///
    /// A group has to be contiguous — a container cannot wrap two tabs with a third between them —
    /// so picking a distant partner reorders the workout. The row says so rather than letting the
    /// strip rearrange itself unexplained.
    let isAdjacent: (UUID) -> Bool

    let onPick: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(candidates, id: \.id) { candidate in
                    Button {
                        onPick(candidate.id)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.textPrimary)

                                if !isAdjacent(candidate.id) {
                                    Text("Will move next to \(anchor?.name ?? "this exercise")")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.textTertiary)
                                }
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.left.chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.accent)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.bgCard)
                }
            } header: {
                Text("Alternate set for set. Rest runs after the last exercise in the pair.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Superset \(anchor?.name ?? "Exercise") with")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}
