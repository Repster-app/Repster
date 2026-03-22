import SwiftUI

struct FatigueLearningAdminView: View {
    let fatigueLearningService: FatigueLearningService

    @State private var globalSummary: GlobalFatigueLearningSummary?
    @State private var exercises: [FatigueLearningExerciseDiagnostics] = []
    @State private var isLoading = true
    @State private var showResetAllAlert = false

    private var hasData: Bool {
        (globalSummary?.sessionCount ?? 0) > 0 || !exercises.isEmpty
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasData {
                noDataView
            } else {
                diagnosticsList
            }
        }
        .background(Color.bg)
        .navigationTitle("Fatigue Learning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if hasData {
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
            Text("This clears the global fatigue baseline, all exercise overrides, observations, and troubleshooting audits.")
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
            Text("Complete workouts with Smart Suggestions enabled. The app starts a global fatigue baseline after the first workout with at least 2 tracked sets, and exercise-specific tuning begins after 5 qualifying sessions.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diagnosticsList: some View {
        List {
            if let globalSummary {
                Section("Global Baseline") {
                    summaryRow(
                        label: "Applied Rate",
                        value: String(format: "%.2f%%", globalSummary.appliedRate.rate * 100),
                        detail: globalSummary.appliedRate.source.displayTitle
                    )
                    summaryRow(
                        label: "Qualifying Workouts",
                        value: "\(globalSummary.sessionCount)",
                        detail: globalSummary.sessionCount == 0
                            ? "waiting for first qualifying workout"
                            : "global adjustments active for exercises without overrides"
                    )
                    summaryRow(
                        label: "Cumulative Error",
                        value: String(format: "%+.4f", globalSummary.cumulativeError),
                        detail: errorDescription(globalSummary.cumulativeError)
                    )
                }
                .listRowBackground(Color.bgCard)
            }

            Section {
                ForEach(exercises) { item in
                    NavigationLink {
                        FatigueLearningDetailView(
                            initialDiagnostics: item,
                            fatigueLearningService: fatigueLearningService,
                            onReset: { Task { await loadData() } }
                        )
                    } label: {
                        ExerciseLearningRow(item: item)
                    }
                    .listRowBackground(Color.bgCard)
                }
            } header: {
                Text("Exercise Diagnostics")
            } footer: {
                Text("Every completed set gets an audit row. Working set 1 is always the baseline, and only later sets with suggestion data, valid performance, RIR, and <=20% weight change are used.")
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func summaryRow(label: String, value: String, detail: String) -> some View {
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

    private func loadData() async {
        isLoading = true
        globalSummary = try? await fatigueLearningService.globalSummary()
        exercises = (try? await fatigueLearningService.diagnosticsExercises()) ?? []
        isLoading = false
    }

    private func errorDescription(_ error: Double) -> String {
        if abs(error) < 0.005 {
            return "model predictions are currently stable"
        } else if error < 0 {
            return "you tend to out-perform the model"
        } else {
            return "you tend to under-perform the model"
        }
    }
}

private struct ExerciseLearningRow: View {
    let item: FatigueLearningExerciseDiagnostics

    private var exercise: Exercise { item.exercise }
    private var localSessionCount: Int { exercise.fatigueLearningSessionCount ?? 0 }
    private var cumulativeError: Double { exercise.fatigueLearningCumulativeError ?? 0.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(exercise.name)
                    .foregroundStyle(Color.textPrimary)
                    .font(.body.weight(.medium))
                Spacer()
                sourceBadge(item.appliedRate.source)
                statusBadge
            }

            HStack(spacing: 12) {
                Label(String(format: "%.2f%%", item.appliedRate.rate * 100), systemImage: "flame")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

                Label(localSessionCount == 0 ? "0/5 local" : "\(localSessionCount)/5 local", systemImage: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

                if item.hasAuditHistory, let lastAuditDate = item.lastAuditDate {
                    Label(lastAuditDate.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            if abs(cumulativeError) > 0.005 {
                HStack(spacing: 4) {
                    Image(systemName: cumulativeError < 0 ? "arrow.down.right" : "arrow.up.right")
                    Text(cumulativeError < 0 ? "tending toward less fatigue than predicted" : "tending toward more fatigue than predicted")
                }
                .font(.caption)
                .foregroundStyle(cumulativeError < 0 ? Color.success : Color.orange)
            } else if item.hasAuditHistory && localSessionCount == 0 {
                Text("Audit history available even though exercise-specific learning has not started yet.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if localSessionCount >= FatigueLearningService.minimumSessionsForLearning {
            Text("Local override")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.success)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.success.opacity(0.15), in: Capsule())
        } else if localSessionCount > 0 {
            Text("\(localSessionCount)/\(FatigueLearningService.minimumSessionsForLearning)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accent.opacity(0.15), in: Capsule())
        } else if item.hasAuditHistory {
            Text("Audited")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.textSecondary.opacity(0.12), in: Capsule())
        }
    }

    private func sourceBadge(_ source: AppliedFatigueRateSource) -> some View {
        let color: Color = switch source {
        case .exerciseOverride: .success
        case .globalLearned: .accent
        case .defaultRate: .textSecondary
        }

        return Text(source.displayTitle)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct FatigueLearningDetailView: View {
    let initialDiagnostics: FatigueLearningExerciseDiagnostics
    let fatigueLearningService: FatigueLearningService
    let onReset: () -> Void

    @State private var diagnostics: FatigueLearningExerciseDiagnostics
    @State private var globalSummary: GlobalFatigueLearningSummary?
    @State private var sessions: [FatigueLearningWorkoutAuditSummary] = []
    @State private var isLoading = true
    @State private var showResetAlert = false
    @Environment(\.dismiss) private var dismiss

    init(
        initialDiagnostics: FatigueLearningExerciseDiagnostics,
        fatigueLearningService: FatigueLearningService,
        onReset: @escaping () -> Void
    ) {
        self.initialDiagnostics = initialDiagnostics
        self.fatigueLearningService = fatigueLearningService
        self.onReset = onReset
        _diagnostics = State(initialValue: initialDiagnostics)
    }

    private var exercise: Exercise { diagnostics.exercise }
    private var localSessionCount: Int { exercise.fatigueLearningSessionCount ?? 0 }
    private var cumulativeError: Double { exercise.fatigueLearningCumulativeError ?? 0.0 }

    var body: some View {
        List {
            appliedRateSection
            nudgeSection
            workoutHistorySection
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
            Text("This clears the exercise override, local learning history, observations, and troubleshooting audits for \(exercise.name). The global baseline stays intact.")
        }
        .task { await reload() }
    }

    private var appliedRateSection: some View {
        Section("Applied Rate") {
            parameterRow(
                label: "Current Rate",
                value: String(format: "%.2f%%", diagnostics.appliedRate.rate * 100),
                detail: diagnostics.appliedRate.source.displayTitle
            )

            parameterRow(
                label: "Local Sessions",
                value: "\(localSessionCount)",
                detail: localSessionCount >= FatigueLearningService.minimumSessionsForLearning
                    ? "exercise-specific override is active"
                    : "\(FatigueLearningService.minimumSessionsForLearning - localSessionCount) more qualifying sessions needed for local override"
            )

            parameterRow(
                label: "Local Error",
                value: String(format: "%+.4f", cumulativeError),
                detail: errorDescription(cumulativeError)
            )

            if let globalSummary, diagnostics.appliedRate.source != .defaultRate {
                parameterRow(
                    label: "Global Baseline",
                    value: String(format: "%.2f%%", globalSummary.appliedRate.rate * 100),
                    detail: globalSummary.appliedRate.source.displayTitle
                )
            }
        }
        .listRowBackground(Color.bgCard)
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

    private var nudgeSection: some View {
        Section {
            HStack(spacing: 12) {
                nudgeButton(title: "Less Fatigue", systemImage: "arrow.down.right", color: .success) {
                    Task {
                        try? await fatigueLearningService.applyManualNudge(exerciseId: exercise.id, nudge: .lessAggressive)
                        await reload()
                    }
                }
                nudgeButton(title: "More Fatigue", systemImage: "arrow.up.right", color: .orange) {
                    Task {
                        try? await fatigueLearningService.applyManualNudge(exerciseId: exercise.id, nudge: .moreAggressive)
                        await reload()
                    }
                }
            }
            .listRowBackground(Color.bgCard)
        } header: {
            Text("Manual Adjustment")
        } footer: {
            Text("This creates or updates an exercise-specific override. If the exercise had been using the global baseline, the nudge starts from that applied rate.")
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

    private var workoutHistorySection: some View {
        Section {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if sessions.isEmpty {
                Text("No workout diagnostics yet")
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionAuditDetailView(
                            session: session,
                            exerciseId: exercise.id,
                            fatigueLearningService: fatigueLearningService
                        )
                    } label: {
                        workoutSessionRow(session)
                    }
                }
            }
        } header: {
            Text("Recent Workout Diagnostics")
        } footer: {
            Text("Every completed set appears here. A workout only counts for local exercise learning when at least 2 sets were marked \"Used for learning\" for this exercise.")
                .foregroundStyle(Color.textTertiary)
        }
        .listRowBackground(Color.bgCard)
    }

    private func workoutSessionRow(_ session: FatigueLearningWorkoutAuditSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(Color.textPrimary)
                    .font(.subheadline)
                Spacer()
                qualificationBadge(session.qualifiesForExerciseLearning)
            }

            HStack(spacing: 8) {
                Text("\(session.usedSetCount) of \(session.totalAudits) sets used")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

                if let medianError = session.medianError {
                    Text("median \(String(format: "%+.3f", medianError))")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    Text("no tracked errors")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func qualificationBadge(_ qualifies: Bool) -> some View {
        let color: Color = qualifies ? .success : .textSecondary
        return Text(qualifies ? "Qualified" : "Not enough tracked sets")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("Reset \(exercise.name)", systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text("Resets the exercise override to use the current global baseline or default rate and deletes local observation/audit history for this exercise.")
                .foregroundStyle(Color.textTertiary)
        }
        .listRowBackground(Color.bgCard)
    }

    private func reload() async {
        isLoading = true
        globalSummary = try? await fatigueLearningService.globalSummary()
        sessions = (try? await fatigueLearningService.recentWorkoutAuditSummaries(exerciseId: exercise.id)) ?? []
        if let updated = try? await fatigueLearningService.diagnosticsExercises().first(where: { $0.exercise.id == exercise.id }) {
            diagnostics = updated
        }
        isLoading = false
    }

    private func errorDescription(_ error: Double) -> String {
        if abs(error) < 0.005 {
            return "exercise-specific predictions are currently stable"
        } else if error < 0 {
            return "you usually out-perform this exercise's predictions"
        } else {
            return "you usually under-perform this exercise's predictions"
        }
    }
}

struct SessionAuditDetailView: View {
    let session: FatigueLearningWorkoutAuditSummary
    let exerciseId: UUID
    let fatigueLearningService: FatigueLearningService

    @State private var audits: [FatigueLearningSetAudit] = []
    @State private var isLoading = true

    var body: some View {
        List {
            Section("Session Summary") {
                summaryRow("Date", value: session.date.formatted(date: .abbreviated, time: .shortened))
                summaryRow("Total Audits", value: "\(session.totalAudits)")
                summaryRow("Used Sets", value: "\(session.usedSetCount)")
                summaryRow("Qualified", value: session.qualifiesForExerciseLearning ? "Yes" : "No")
                if let medianError = session.medianError {
                    summaryRow("Median Error", value: String(format: "%+.4f", medianError))
                }
            }
            .listRowBackground(Color.bgCard)

            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if audits.isEmpty {
                    Text("No audit data available")
                        .foregroundStyle(Color.textTertiary)
                } else {
                    ForEach(audits, id: \.id) { audit in
                        auditRow(audit)
                    }
                }
            } header: {
                Text("Per-Set Diagnostics")
            } footer: {
                Text("These diagnostics explain exactly why each completed set did or did not feed the fatigue model.")
                    .foregroundStyle(Color.textTertiary)
            }
            .listRowBackground(Color.bgCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            audits = (try? await fatigueLearningService.audits(for: session.workoutId, exerciseId: exerciseId)) ?? []
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

    private func auditRow(_ audit: FatigueLearningSetAudit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Set \(audit.visibleSetNumber) • \(audit.setType.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                statusBadge(for: audit.status)
            }

            Text(audit.status.detail)
                .font(.caption)
                .foregroundStyle(color(for: audit.status))

            if let reason = audit.suggestionUnavailableReason {
                Text("\(reason.title): \(reason.message)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            if let prescribedWeight = audit.prescribedWeight, let actualWeight = audit.actualWeight {
                Text("Suggested \(String(format: "%.1f", prescribedWeight)) kg -> Used \(String(format: "%.1f", actualWeight)) kg")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            if let actualReps = audit.actualReps {
                let rirLabel = audit.actualRIR.map { " @ RIR \(String(format: "%.0f", $0))" } ?? ""
                Text("\(actualReps) reps\(rirLabel)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            if let deviationFraction = audit.deviationFraction {
                Text("Weight deviation \(String(format: "%.1f%%", deviationFraction * 100))")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            if let normalizedError = audit.normalizedError {
                HStack(spacing: 4) {
                    Text("Normalized error")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    errorBadge(normalizedError)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(for status: FatigueLearningAuditStatus) -> some View {
        Text(status.displayTitle)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color(for: status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color(for: status).opacity(0.12), in: Capsule())
    }

    private func color(for status: FatigueLearningAuditStatus) -> Color {
        switch status {
        case .used:
            return .success
        case .suggestionUnavailable, .missingRIR, .weightDeviationOver20Percent:
            return .orange
        case .invalidPerformance:
            return .danger
        case .warmupNotTracked, .baselineFirstWorkingSet:
            return .textSecondary
        }
    }

    private func errorBadge(_ error: Double) -> some View {
        let color: Color = error < -0.005 ? .success : (error > 0.005 ? .orange : .textSecondary)
        return Text(String(format: "%+.4f", error))
            .font(.caption.weight(.semibold).monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
