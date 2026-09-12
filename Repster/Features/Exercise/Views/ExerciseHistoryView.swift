// ExerciseHistoryView.swift
// Shows past sessions for an exercise, grouped by workout, newest first.
// Spec: FR-006, SC-002
// Contract: view-contracts.md ExerciseHistoryView
// Feature: 007-exercise-list-and-detail WP04 T018

import SwiftUI

struct ExerciseHistoryView: View {

    let historyWorkouts: [WorkoutHistoryGroup]
    let exercise: ChartExerciseData?
    let unitPreference: UnitPreference

    /// Sets whose note is open.
    ///
    /// Held here rather than on a session card: the cards sit in a `LazyVStack`, and state on
    /// the parent survives them scrolling out and back. Set ids are stable across a reload, so
    /// a note stays open if history refreshes underneath it. Several can be open at once —
    /// closing one above the row you tapped would shift that row under your finger.
    /// See SET_NOTES_IN_HISTORY_SCOPING.md §2.3.
    @State private var expandedSetIds: Set<UUID> = []

    // MARK: - Body

    var body: some View {
        if historyWorkouts.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(historyWorkouts) { group in
                        workoutSessionCard(group)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Session Card

    private func workoutSessionCard(_ group: WorkoutHistoryGroup) -> some View {
        // A card with any note reserves the chevron slot on every row, so PR badges stay in one
        // column. A card with none is drawn exactly as it was before notes could open.
        let reservesChevronSlot = group.sets.contains(where: \.hasNote)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(formatDate(group.date))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                // The set rows below are deliberately left alone — no dimming, no strike. They
                // are a true record of what was lifted, and those sets are still in the charts
                // and the volume total. Only the session header carries the exception.
                if !group.supersetPartnerNames.isEmpty {
                    SupersetChip(partnerNames: group.supersetPartnerNames)
                }

                if group.isExcludedFromProgression {
                    ProgressionExclusionChip()
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                let labels = SetBadgeLabel.assign(for: group.sets.map(\.setType))
                ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, set in
                    setRow(
                        set,
                        label: labels[index],
                        siblings: group.sets,
                        reservesChevronSlot: reservesChevronSlot
                    )
                    if index < group.sets.count - 1 {
                        Divider()
                            .background(Color.border)
                    }
                }
            }
            .padding(12)
            .background(Color.bgCard)
            .cornerRadius(10)
        }
    }

    // MARK: - Set Row

    /// A row with a note opens it on tap, in a strip directly beneath, and closes it on a second
    /// tap. Rows without a note are not tappable. See SET_NOTES_IN_HISTORY_SCOPING.md §2.
    @ViewBuilder
    private func setRow(
        _ set: ChartSetData,
        label: SetBadgeLabel,
        siblings: [ChartSetData],
        reservesChevronSlot: Bool
    ) -> some View {
        if let note = set.notes, set.hasNote {
            let isExpanded = expandedSetIds.contains(set.id)

            Button {
                toggleNote(for: set.id)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    setRowContent(
                        set,
                        label: label,
                        siblings: siblings,
                        reservesChevronSlot: reservesChevronSlot,
                        isExpanded: isExpanded
                    )

                    if isExpanded {
                        // Indented past the 24pt badge column and the 8pt gap, so the note
                        // lines up with the numbers. It sits outside the row's warm-up dimming.
                        SetNoteStrip(text: note)
                            .padding(.leading, 32)
                            .padding(.bottom, 6)
                            .transition(.opacity)
                    }
                }
                // Rows are ~30pt tall, so the whole width is the target. Only noted rows are
                // tappable, which means a near miss lands on nothing rather than the wrong row.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            setRowContent(
                set,
                label: label,
                siblings: siblings,
                reservesChevronSlot: reservesChevronSlot,
                isExpanded: false
            )
        }
    }

    private func setRowContent(
        _ set: ChartSetData,
        label: SetBadgeLabel,
        siblings: [ChartSetData],
        reservesChevronSlot: Bool,
        isExpanded: Bool
    ) -> some View {
        let hasNote = set.hasNote
        let isWarmup = set.setType == .warmup
        let display = WorkoutSetPerformanceFormatter.display(
            for: set,
            exercise: exercise,
            unitPreference: unitPreference
        )

        return HStack(spacing: 8) {
            // Set number with note indicator and set type badge
            ZStack(alignment: .topTrailing) {
                // Numbering comes from `SetBadgeLabel`, shared with the live set table. It
                // used to be `index + 1` across every set in the group, so two warm-ups made
                // the first working set read as "3" here while the workout screen said "1".
                switch label {
                case .warmup:
                    Text(label.text)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.warmup)
                case .dropset:
                    Text(label.text)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.chart5)
                case .working:
                    Text(label.text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }

                if hasNote {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .offset(x: 4, y: -2)
                }
            }
            .frame(width: 24)

            if let performanceLabel = display.performanceLabel {
                Text(performanceLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
            }

            if let rirLabel = display.rirLabel {
                Text(rirLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(display.isPerSide ? Color.textSecondary : Color.rirColor(for: set.rir))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        display.isPerSide
                            ? Color.bgInput
                            : Color.rirColor(for: set.rir).opacity(0.10)
                    )
                    .cornerRadius(4)
            }

            Spacer()

            PRBadgeView(status: CachedPRStatus.effectiveStatus(for: set, among: siblings))

            if reservesChevronSlot {
                // Present but invisible on a plain row in a noted card, so the PR column
                // doesn't shift between rows. Decorative either way: the row is the button.
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 14)
                    .opacity(hasNote ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .opacity(isWarmup ? 0.6 : 1.0)
    }

    /// Same timing as the admin drawer in `WeightSuggestionCardView`.
    private func toggleNote(for setId: UUID) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedSetIds.contains(setId) {
                expandedSetIds.remove(setId)
            } else {
                expandedSetIds.insert(setId)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("No history yet")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
