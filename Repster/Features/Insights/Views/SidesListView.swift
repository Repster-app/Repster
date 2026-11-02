// SidesListView.swift
// The pages behind the Left vs Right tile: every exercise under its muscle group, then one
// exercise with its chart and best sets. Spec: SIDES_RETHINK_SCOPING.md, D26, D27.
//
// Muscle groups are only headings here. Exercises in one group can lean different ways, so a group
// says nothing about direction (D21); each exercise does. D13: rep counts appear only on the
// exercise page.

import SwiftUI

enum SidesRoute: Hashable {
    case list
    /// By id because `SideExerciseSummary` isn't `Hashable`, and because the summary has to be
    /// looked up fresh: marking an exercise Unilateral rebuilds the comparison.
    case exercise(UUID)
    case untracked
}

/// Reads the view model inside `body`, so a pushed page follows a reload where a value handed over
/// at push time would go stale.
struct SidesDestination: View {
    let route: SidesRoute
    let viewModel: InsightsViewModel

    @Environment(ServiceContainer.self) private var services

    var body: some View {
        let status = viewModel.sides ?? .empty
        switch route {
        case .list:
            SidesListView(status: status) {
                services.analyticsService.sidesOpened(state: status.state)
            }
        case let .exercise(id):
            if let exercise = status.exercise(id: id) {
                SideExerciseDetailView(exercise: exercise, unitPreference: services.unitPreference) {
                    services.analyticsService.sidesExerciseOpened(status: exercise.status)
                }
            }
        case .untracked:
            SideUntrackedListView(exercises: status.untrackedExercises) {
                Task { await viewModel.load() }
            }
        }
    }
}

// MARK: - List

struct SidesListView: View {
    let status: SidesStatus
    var onFirstAppear: () -> Void = {}

    @State private var hasReportedOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if status.groups.isEmpty {
                    Text("Nothing here is tracked by side yet.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }

                ForEach(status.groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        SidesSectionLabel(text: group.displayName.uppercased())

                        ForEach(group.trackedExercises) { exercise in
                            row(exercise)
                        }
                    }
                }

                if !status.untrackedExercises.isEmpty {
                    untrackedRow
                }

                Text("Each exercise is judged on its last \(SidesAnalysis.sessionsConsidered) sessions, comparing both sides at the same weight.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.sidesCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .background(Color.bg)
        .navigationTitle("Left vs right")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            guard !hasReportedOpen else { return }
            hasReportedOpen = true
            onFirstAppear()
        }
    }

    private func row(_ exercise: SideExerciseSummary) -> some View {
        NavigationLink(value: SidesRoute.exercise(exercise.id)) {
            SidesTile(
                mark: SidesTileMark(status: exercise.status),
                title: exercise.name,
                subtitle: exercise.status.sentence,
                subtitleColor: exercise.status.isStronger ? .textPrimary : .textSecondary
            ) {
                HStack(spacing: 12) {
                    if exercise.status.degree != nil {
                        SideStrengthMark(status: exercise.status)
                    }
                    SidesChevron()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows each session")
    }

    private var untrackedRow: some View {
        NavigationLink(value: SidesRoute.untracked) {
            HStack(spacing: 10) {
                Text(SidesCopy.untrackedLine(count: status.untrackedExercises.count))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Mark one")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accent)
                SidesChevron()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCard)
            .cornerRadius(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Not tracked by side

/// The exercises a group trains that log one number for both sides. Each opens its own editor,
/// where the Unilateral switch lives — the flag is the whole reach of the feature, and 6 of the 69
/// seeded exercises carry it, so this list is the only place the reach can grow.
struct SideUntrackedListView: View {
    let exercises: [SideExerciseSummary]
    var onChanged: () -> Void = {}

    @Environment(ServiceContainer.self) private var services
    @State private var editing: ChartExerciseData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("These log one number for both sides. Mark one Unilateral and Repster compares left against right from your next session.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sidesCaption)
                        .padding(.top, 2)
                    Text("Only worth it for movements you train one side at a time. A back squat logged per side would compare two numbers that never differ.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.sidesCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgInput)
                .cornerRadius(10)

                VStack(spacing: 0) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        row(exercise, isLast: index == exercises.count - 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .background(Color.bg)
        .navigationTitle("Not tracked by side")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { data in
            CreateEditExerciseSheet(exercise: data, services: services, onSave: onChanged)
        }
    }

    @ViewBuilder
    private func row(_ exercise: SideExerciseSummary, isLast: Bool) -> some View {
        if exercise.canTrackSides {
            Button {
                Task { editing = try? await services.exerciseService.fetchExerciseSnapshot(exercise.id) }
            } label: {
                HStack(spacing: 10) {
                    Text(exercise.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    SidesChevron()
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) { divider(isLast) }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this exercise to mark it Unilateral")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                Text("Doesn\u{2019}t log reps, so sides can\u{2019}t be compared")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { divider(isLast) }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func divider(_ isLast: Bool) -> some View {
        if !isLast {
            Rectangle().fill(Color.border).frame(height: 1)
        }
    }
}

/// Already carries `id`; `.sheet(item:)` needs the conformance spelled out.
extension ChartExerciseData: Identifiable {}

// MARK: - Exercise

struct SideExerciseDetailView: View {
    let exercise: SideExerciseSummary
    let unitPreference: UnitPreference
    var onFirstAppear: () -> Void = {}

    @State private var hasReportedOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Not a large nav title: those truncate, and "Bulgarian Split Squat" doesn't fit at 34pt.
                Text(exercise.name)
                    .font(.system(size: 28, weight: .bold))
                    .kerning(0.2)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 20) {
                    SidesTile(
                        mark: SidesTileMark(status: exercise.status),
                        title: SidesCopy.verdictTitle(for: exercise),
                        subtitle: SidesCopy.verdictSubtitle(for: exercise)
                    ) {
                        if exercise.status.degree != nil {
                            SideStrengthMark(status: exercise.status)
                        }
                    }

                    if exercise.status.isClassified {
                        chartSection
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SidesSectionLabel(text: exercise.status.isClassified ? "BEST SET EACH SESSION" : "SO FAR")
                        SideBestSetTable(sessions: exercise.sessions, unitPreference: unitPreference)
                    }

                    if let note = incompleteNote {
                        noteView(note)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 100)
        }
        .background(Color.bg)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasReportedOpen else { return }
            hasReportedOpen = true
            onFirstAppear()
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SidesSectionLabel(text: "LAST \(exercise.sessions.count) SESSIONS")
                Spacer(minLength: 8)
                if let lead = SidesCopy.leadLine(for: exercise) {
                    SidesSectionLabel(text: lead)
                }
            }

            SideLinesChart(
                sessions: exercise.sessions,
                status: exercise.status,
                coverage: exercise.rirCoverage
            )
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
    }

    /// Rows with a side missing: one-sided reps aren't compared at all; RIR on one side
    /// compares on reps alone, because a blank isn't failure.
    private var incompleteNote: String? {
        var parts: [String] = []
        let reps = exercise.oneSideOnlySets
        if reps > 0 {
            parts.append(reps == 1
                ? "1 set had only one side logged, so it isn’t counted."
                : "\(reps) sets had only one side logged, so they aren’t counted.")
        }
        let rir = exercise.rirOnOneSideSets
        if rir > 0 {
            parts.append(rir == 1
                ? "1 set had RIR on one side only, so it’s compared on reps."
                : "\(rir) sets had RIR on one side only, so they’re compared on reps.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func noteView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.sidesCaption)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }
}

// MARK: - Shared pieces

struct SidesSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(Color.sidesCaption)
    }
}

/// Copy for the tile, the list and the exercise page (D13, D21, D31).
enum SidesCopy {
    /// Names up to two groups. Past that the names stop fitting a tile, and the list has them.
    static func tileHeadline(for status: SidesStatus) -> String {
        switch status.state {
        case .building:
            return "Building your baseline"
        case .even:
            return "Both sides are even"
        case .possible:
            let names = status.groups.filter(\.status.isPossible).map(\.displayName)
            return names.count == 1
                ? "Possible imbalance in \(names[0])"
                : "Possible imbalances in \(names.count) muscle groups"
        case .imbalanced, .hidden:
            let names = status.groups.filter(\.status.isImbalance).map(\.displayName)
            switch names.count {
            case 1:  return "Imbalance in \(names[0])"
            case 2:  return "Imbalances in \(names[0]) and \(names[1])"
            default: return "Imbalances in \(names.count) muscle groups"
            }
        }
    }

    static func tileSubtitle(for status: SidesStatus) -> String {
        switch status.state {
        case .building:
            return "Each exercise needs \(SidesAnalysis.minSessions) sessions"
        case .possible:
            return "It needs a few more sessions to confirm"
        case .even, .imbalanced, .hidden:
            return "Last \(SidesAnalysis.sessionsConsidered) sessions of each exercise"
        }
    }

    static func untrackedLine(count: Int) -> String {
        count == 1
            ? "1 other exercise isn\u{2019}t tracked by side"
            : "\(count) other exercises aren\u{2019}t tracked by side"
    }

    static func verdictTitle(for exercise: SideExerciseSummary) -> String {
        switch exercise.status {
        case let .possible(lean):
            return "\(lean.word) seems stronger"
        case .even:
            return "Both sides are even"
        case .stronger, .collecting, .notTracked:
            return exercise.status.sentence
        }
    }

    /// The only numbers in the feature besides the logged sets (D13).
    static func verdictSubtitle(for exercise: SideExerciseSummary) -> String {
        let reps = max(1, Int(abs(exercise.averageGap).rounded()))
        let more = "About \(reps) more \(reps == 1 ? "rep" : "reps")"
        switch exercise.status {
        case .stronger:
            return "\(more) at the same weight"
        case .possible:
            return "\(more) so far, needs more sessions"
        case .even:
            return "Within a rep of each other, at the same weight"
        case .collecting:
            return "With both sides logged"
        case .notTracked(.notUnilateral):
            return "Not marked Unilateral, so both sides are logged as one"
        case .notTracked(.neverBothSides):
            return "No recent sets with both sides logged"
        }
    }

    /// Right of the chart's label: the consistency behind the verdict.
    static func leadLine(for exercise: SideExerciseSummary) -> String? {
        switch exercise.status {
        case .stronger, .possible:
            guard let lean = exercise.status.lean else { return nil }
            return "\(lean.word.uppercased()) AHEAD IN \(exercise.leadCount)"
        case .even:
            return exercise.differingCount == 0 ? "SIDES MATCHED" : "NO CONSISTENT GAP"
        case .collecting, .notTracked:
            return nil
        }
    }

    static func rirMarker(for coverage: SideRIRCoverage) -> String {
        switch coverage {
        case .all:      return "Reps + RIR"
        case .partial:  return "Reps + RIR where logged"
        case .repsOnly: return "Reps only"
        }
    }

    /// "5+" is a floor, not a value, so it never reads as exactly five.
    static func reserveText(_ reserve: Double) -> String {
        if reserve >= SidesAnalysis.censoredRIR { return "5+ RIR" }
        let figure = reserve == reserve.rounded() ? String(Int(reserve)) : String(format: "%.1f", reserve)
        return "\(figure) RIR"
    }
}

#if DEBUG
#Preview("List") {
    NavigationStack {
        SidesListView(status: SidesPreviewData.status)
    }
}

/// One per state, because the chart and the rows each read differently in all four and a device
/// pass on only the confirmed case would miss three of them.
#Preview("Exercise — stronger") {
    NavigationStack {
        SideExerciseDetailView(exercise: SidesPreviewData.legs.exercises[0], unitPreference: .metric)
    }
}

#Preview("Exercise — seems stronger") {
    NavigationStack {
        SideExerciseDetailView(exercise: SidesPreviewData.legs.exercises[3], unitPreference: .metric)
    }
}

#Preview("Exercise — even, reps only") {
    NavigationStack {
        SideExerciseDetailView(
            exercise: SidesPreviewData.exercise(
                "1 Leg Press", .even, [(10, 10), (9, 9.5), (11, 10.5), (10, 10), (9.5, 9.5), (12, 12)], rir: nil
            ),
            unitPreference: .metric
        )
    }
}

#Preview("Exercise — collecting") {
    NavigationStack {
        SideExerciseDetailView(exercise: SidesPreviewData.legs.exercises[4], unitPreference: .metric)
    }
}
#endif
