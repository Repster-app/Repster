// FatigueLearningAdminView.swift
// Admin panel showing adaptive fatigue learning status per exercise.

import SwiftUI

// MARK: - List View

struct FatigueLearningAdminView: View {
    let fatigueLearningService: FatigueLearningService

    @State private var exercises: [Exercise] = []
    @State private var isLoading = true
    @State private var showResetAllAlert = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if exercises.isEmpty {
                noDataView
            } else {
                exerciseList
            }
        }
        .background(Color.bg)
        .navigationTitle("Fatigue Learning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !exercises.isEmpty {
                    Button(role: .destructive) {
                        showResetAllAlert = true
                    } label: {
                        Text("Reset All")
                            .foregroundStyle(Color.danger)
                    }
                }
            }
        }
        .alert("Reset All Learning?", isPresented: $showResetAllAlert) {
            Button("Reset All", role: .destructive) {
                Task {
                    try? await fatigueLearningService.resetAllLearning()
                    await loadData()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset learned fatigue rates for all exercises back to defaults. Observation history will be deleted.")
        }
        .task { await loadData() }
    }

    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No Learning Data Yet")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Complete workouts with Smart Suggestions enabled. The system will start collecting fatigue prediction data after your second set of each exercise.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var exerciseList: some View {
        List {
            Section {
                ForEach(exercises, id: \.id) { exercise in
                    NavigationLink {
                        FatigueLearningDetailView(
                            exercise: exercise,
                            fatigueLearningService: fatigueLearningService,
                            onReset: { Task { await loadData() } }
                        )
                    } label: {
                        ExerciseLearningRow(exercise: exercise)
                    }
                    .listRowBackground(Color.bgCard)
                }
            } header: {
                Text("Exercises with learning data")
            } footer: {
                Text("Fatigue rates adjust automatically after \(FatigueLearningService.minimumSessionsForLearning) qualifying sessions. Each session needs at least 2 completed working sets with RIR logged.")
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func loadData() async {
        isLoading = true
        exercises = (try? await fatigueLearningService.exercisesWithLearningData()) ?? []
        isLoading = false
    }
}

// MARK: - Exercise Row

private struct ExerciseLearningRow: View {
    let exercise: Exercise

    private var sessionCount: Int { exercise.fatigueLearningSessionCount ?? 0 }
    private var cumulativeError: Double { exercise.fatigueLearningCumulativeError ?? 0 }
    private var isPersonalized: Bool {
        sessionCount >= FatigueLearningService.minimumSessionsForLearning && exercise.fatigueRate != nil
    }
    private var isCollecting: Bool {
        sessionCount > 0 && sessionCount < FatigueLearningService.minimumSessionsForLearning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(exercise.name)
                    .foregroundStyle(Color.textPrimary)
                    .font(.body.weight(.medium))
                Spacer()
                statusBadge
            }

            HStack(spacing: 12) {
                Label("\(sessionCount) sessions", systemImage: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

                if let rate = exercise.fatigueRate {
                    Label(String(format: "%.1f%%", rate * 100), systemImage: "flame")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                trendIndicator
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isPersonalized {
            Text("Personalized")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.success)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.success.opacity(0.15), in: Capsule())
        } else if isCollecting {
            Text("\(sessionCount)/\(FatigueLearningService.minimumSessionsForLearning)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accent.opacity(0.15), in: Capsule())
        }
    }

    @ViewBuilder
    private var trendIndicator: some View {
        if abs(cumulativeError) > 0.005 {
            HStack(spacing: 2) {
                Image(systemName: cumulativeError < 0 ? "arrow.down.right" : "arrow.up.right")
                Text(cumulativeError < 0 ? "less fatigue" : "more fatigue")
            }
            .font(.caption)
            .foregroundStyle(cumulativeError < 0 ? Color.success : Color.orange)
        }
    }
}

// MARK: - Detail View

struct FatigueLearningDetailView: View {
    let initialExercise: Exercise
    let fatigueLearningService: FatigueLearningService
    let onReset: () -> Void

    @State private var exercise: Exercise
    @State private var sessions: [SessionErrorSummary] = []
    @State private var isLoading = true
    @State private var showResetAlert = false
    @Environment(\.dismiss) private var dismiss

    init(exercise: Exercise, fatigueLearningService: FatigueLearningService, onReset: @escaping () -> Void) {
        self.initialExercise = exercise
        self.fatigueLearningService = fatigueLearningService
        self.onReset = onReset
        _exercise = State(initialValue: exercise)
    }

    private var sessionCount: Int { exercise.fatigueLearningSessionCount ?? 0 }
    private var cumulativeError: Double { exercise.fatigueLearningCumulativeError ?? 0 }
    private var currentRate: Double { exercise.fatigueRate ?? 0.04 }
    private let defaultRate: Double = 0.04

    var body: some View {
        List {
            parametersSection
            nudgeSection
            sessionHistorySection
            resetSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset Learning?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                Task {
                    try? await fatigueLearningService.resetLearning(exerciseId: exercise.id)
                    onReset()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset the learned fatigue rate for \(exercise.name) back to the default (\(String(format: "%.1f%%", defaultRate * 100))). All observation history will be deleted.")
        }
        .task {
            sessions = (try? await fatigueLearningService.recentSessionSummaries(exerciseId: exercise.id)) ?? []
            isLoading = false
        }
    }

    // MARK: - Parameters Section

    private var parametersSection: some View {
        Section("Current Parameters") {
            parameterRow(
                label: "Fatigue Rate",
                value: String(format: "%.2f%%", currentRate * 100),
                detail: exercise.fatigueRate != nil
                    ? "default: \(String(format: "%.2f%%", defaultRate * 100))"
                    : "using default"
            )

            parameterRow(
                label: "Sessions",
                value: "\(sessionCount)",
                detail: sessionCount >= FatigueLearningService.minimumSessionsForLearning
                    ? "actively adjusting"
                    : "\(FatigueLearningService.minimumSessionsForLearning - sessionCount) more needed"
            )

            parameterRow(
                label: "Cumulative Error",
                value: String(format: "%+.4f", cumulativeError),
                detail: errorDescription
            )

            if exercise.fatigueRate != nil {
                let changePercent = ((currentRate - defaultRate) / defaultRate) * 100
                parameterRow(
                    label: "Change from Default",
                    value: String(format: "%+.1f%%", changePercent),
                    detail: currentRate < defaultRate ? "reduced fatigue prediction" : "increased fatigue prediction"
                )
            }
        }
        .listRowBackground(Color.bgCard)
    }

    private var errorDescription: String {
        if abs(cumulativeError) < 0.005 {
            return "model predictions are accurate"
        } else if cumulativeError < 0 {
            return "you tend to out-perform predictions"
        } else {
            return "you tend to under-perform predictions"
        }
    }

    private func parameterRow(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(value)
                    .foregroundStyle(Color.textPrimary)
                    .fontDesign(.monospaced)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Nudge Section

    private var nudgeSection: some View {
        Section {
            HStack(spacing: 12) {
                nudgeButton(
                    title: "Less Fatigue",
                    systemImage: "arrow.down.right",
                    color: .success
                ) {
                    Task { await applyNudge(.lessAggressive) }
                }

                nudgeButton(
                    title: "More Fatigue",
                    systemImage: "arrow.up.right",
                    color: .orange
                ) {
                    Task { await applyNudge(.moreAggressive) }
                }
            }
            .listRowBackground(Color.bgCard)
        } header: {
            Text("Manual Adjustment")
        } footer: {
            Text("Nudge the fatigue rate by \(String(format: "%.1f%%", FatigueLearningService.fatigueRateStep * 100)) per tap. \"Less Fatigue\" means you fatigue less than predicted.")
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func nudgeButton(title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func applyNudge(_ nudge: FatigueNudge) async {
        try? await fatigueLearningService.applyManualNudge(exerciseId: exercise.id, nudge: nudge)
        await reloadExercise()
    }

    private func reloadExercise() async {
        if let updated = try? await fatigueLearningService.exercisesWithLearningData().first(where: { $0.id == exercise.id }) {
            exercise = updated
        }
    }

    // MARK: - Session History Section

    private var sessionHistorySection: some View {
        Section {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if sessions.isEmpty {
                Text("No session data yet")
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionObservationDetailView(
                            session: session,
                            exerciseId: exercise.id,
                            fatigueLearningService: fatigueLearningService
                        )
                    } label: {
                        sessionRow(session)
                    }
                }
            }
        } header: {
            Text("Recent Sessions")
        } footer: {
            Text("Tap a session for per-set details. Only working sets 2+ with RIR logged are tracked — set 1 establishes the baseline.")
                .foregroundStyle(Color.textTertiary)
        }
        .listRowBackground(Color.bgCard)
    }

    private func sessionRow(_ session: SessionErrorSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(Color.textPrimary)
                    .font(.subheadline)
                Spacer()
                errorBadge(session.medianError)
            }

            HStack(spacing: 8) {
                Text("\(session.observationCount) sets observed")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

                Text("errors: \(session.errors.map { String(format: "%+.3f", $0) }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func errorBadge(_ error: Double) -> some View {
        let isNegative = error < -0.005
        let isPositive = error > 0.005
        let color: Color = isNegative ? .success : (isPositive ? .orange : .textSecondary)

        Text(String(format: "%+.3f", error))
            .font(.caption.weight(.semibold).monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("Reset Learning for \(exercise.name)", systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text("Resets the fatigue rate to the default value and deletes all observation history for this exercise.")
                .foregroundStyle(Color.textTertiary)
        }
        .listRowBackground(Color.bgCard)
    }
}

// MARK: - Session Observation Detail View

struct SessionObservationDetailView: View {
    let session: SessionErrorSummary
    let exerciseId: UUID
    let fatigueLearningService: FatigueLearningService

    @State private var observations: [FatigueObservation] = []
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                summaryRow("Date", value: session.date.formatted(date: .abbreviated, time: .shortened))
                summaryRow("Sets Observed", value: "\(session.observationCount)")
                summaryRow("Median Error", value: String(format: "%+.4f", session.medianError))
            } header: {
                Text("Session Summary")
            }
            .listRowBackground(Color.bgCard)

            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if observations.isEmpty {
                    Text("No observation data available")
                        .foregroundStyle(Color.textTertiary)
                } else {
                    ForEach(observations, id: \.id) { obs in
                        observationRow(obs)
                    }
                }
            } header: {
                Text("Per-Set Observations")
            } footer: {
                Text("Working set 1 establishes the fatigue-free baseline and is not tracked. Only sets 2+ with RIR logged and weight within 20% of suggested are observed.")
                    .foregroundStyle(Color.textTertiary)
            }
            .listRowBackground(Color.bgCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            observations = (try? await fatigueLearningService.observations(for: session.workoutId, exerciseId: exerciseId)) ?? []
            isLoading = false
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.textPrimary)
                .fontDesign(.monospaced)
        }
    }

    private func observationRow(_ obs: FatigueObservation) -> some View {
        let e1rmDelta = obs.actualE1RM - obs.predictedEffectiveE1RM
        let weightDelta = obs.actualWeight - obs.prescribedWeight

        return VStack(alignment: .leading, spacing: 8) {
            // Header: working set label + error badge
            HStack {
                Text("Working Set \(obs.setIndex + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                errorBadge(obs.normalizedError)
            }

            // Plain-language interpretation
            Text(interpretError(obs.normalizedError))
                .font(.caption)
                .foregroundStyle(interpretColor(obs.normalizedError))

            // Weight comparison
            HStack(spacing: 4) {
                Image(systemName: "scalemass")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text("Suggested \(String(format: "%.1f", obs.prescribedWeight)) kg → Used \(String(format: "%.1f", obs.actualWeight)) kg")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                if abs(weightDelta) > 0.05 {
                    Text("(\(String(format: "%+.1f", weightDelta)))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(weightDelta > 0 ? Color.success : Color.orange)
                }
            }

            // Performance: reps + RIR
            HStack(spacing: 4) {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text("\(obs.actualReps) reps @ RIR \(String(format: "%.0f", obs.actualRIR))")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            // e1RM comparison with delta
            HStack(spacing: 4) {
                Image(systemName: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text("e1RM: predicted \(String(format: "%.1f", obs.predictedEffectiveE1RM)) vs actual \(String(format: "%.1f", obs.actualE1RM))")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text("(\(String(format: "%+.1f", e1rmDelta)))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(e1rmDelta > 0 ? Color.success : Color.orange)
            }

            // Rest duration
            if let rest = obs.restDurationSeconds {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(rest / 60)m \(rest % 60)s rest")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func interpretError(_ error: Double) -> String {
        if error < -0.02 {
            return "You were stronger than predicted — model over-estimated fatigue"
        } else if error > 0.02 {
            return "You were weaker than predicted — model under-estimated fatigue"
        } else {
            return "Prediction was accurate"
        }
    }

    private func interpretColor(_ error: Double) -> Color {
        if error < -0.02 { return .success }
        if error > 0.02 { return .orange }
        return .textSecondary
    }

    @ViewBuilder
    private func errorBadge(_ error: Double) -> some View {
        let isNegative = error < -0.005
        let isPositive = error > 0.005
        let color: Color = isNegative ? .success : (isPositive ? .orange : .textSecondary)

        Text(String(format: "%+.4f", error))
            .font(.caption.weight(.semibold).monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
