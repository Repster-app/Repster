import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {

    @State private var viewModel: ExportViewModel

    init(workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol) {
        _viewModel = State(initialValue: ExportViewModel(workoutHistoryBackupService: workoutHistoryBackupService))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "internaldrive.fill.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)

            Text("Export Backup")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Text("Create a Reppo backup file that preserves your workout history, workout metadata, and set details for full restore later.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if viewModel.isExporting {
                ProgressView("Preparing backup...")
                    .foregroundStyle(Color.textSecondary)
            } else {
                Button {
                    viewModel.generateExport()
                } label: {
                    Label("Prepare Backup", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
            }

            Text("The backup file is Reppo-specific and meant for full restore, not third-party CSV import.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
        .navigationTitle("Export Backup")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: shareItemBinding) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
    }

    private var shareItemBinding: Binding<WorkoutHistoryBackupShareItem?> {
        Binding(
            get: { viewModel.shareItem },
            set: { viewModel.shareItem = $0 }
        )
    }
}

struct RestoreBackupView: View {

    @State private var viewModel: RestoreBackupViewModel

    init(workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol) {
        _viewModel = State(initialValue: RestoreBackupViewModel(workoutHistoryBackupService: workoutHistoryBackupService))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .previewing:
                previewView
            case .restoring:
                restoringView
            case .completed:
                completedView
            case .failed:
                failedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
        .navigationTitle("Restore Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.reppoWorkoutHistoryBackup]
        ) { result in
            viewModel.handleFileSelected(result)
        }
        .alert("Replace Current Workout History?", isPresented: $viewModel.showReplaceConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Replace History", role: .destructive) {
                viewModel.performRestore()
            }
        } message: {
            Text("This deletes current workouts and sets before restoring the selected backup. Bodyweight logs, settings, templates, and programs are left untouched.")
        }
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)

            Text("Restore Backup")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Text("Select a Reppo backup file to replace the current workout history with the archived workouts, exercises, and sets.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                viewModel.showFilePicker = true
            } label: {
                Label("Select Backup File", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private var previewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Backup Preview")
                    .font(.title2.bold())
                    .foregroundStyle(Color.textPrimary)

                if let preview = viewModel.preview {
                    VStack(spacing: 12) {
                        summaryRow(label: "Archive Version", value: "\(preview.archiveVersion)")
                        summaryRow(label: "Exported", value: formattedDateTime(preview.exportedAt))
                        summaryRow(label: "Workouts", value: "\(preview.workoutCount)")
                        summaryRow(label: "Exercises", value: "\(preview.exerciseCount)")
                        summaryRow(label: "Sets", value: "\(preview.setCount)")
                        summaryRow(label: "Date Range", value: formattedDateRange(preview))
                    }
                    .padding()
                    .background(Color.bgCard)
                    .cornerRadius(12)
                }

                Text("Restoring will replace the current workout history only. Templates, programs, bodyweight logs, and settings stay as they are.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                HStack(spacing: 16) {
                    Button("Cancel") {
                        viewModel.reset()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Replace History") {
                        viewModel.confirmRestore()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.danger)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }

    private var restoringView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.accent)

            Text("Restoring backup...")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            Text("Derived stats and PRs will be rebuilt after the archive is restored.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)

            Spacer()
        }
    }

    private var completedView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.success)

                Text("Restore Complete")
                    .font(.title2.bold())
                    .foregroundStyle(Color.textPrimary)

                if let result = viewModel.result {
                    VStack(spacing: 12) {
                        summaryRow(label: "Workouts Restored", value: "\(result.workoutsRestored)")
                        summaryRow(label: "Exercises Upserted", value: "\(result.exercisesUpserted)")
                        summaryRow(label: "Sets Restored", value: "\(result.setsRestored)")
                        summaryRow(label: "Duration", value: String(format: "%.1f seconds", result.duration))
                    }
                    .padding()
                    .background(Color.bgCard)
                    .cornerRadius(12)
                }

                Button("Restore Another Backup") {
                    viewModel.reset()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding()
        }
    }

    private var failedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.danger)

            Text("Restore Failed")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Text(viewModel.errorMessage ?? "The backup could not be restored.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Choose Another File") {
                viewModel.retry()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedDateRange(_ preview: WorkoutHistoryBackupPreview) -> String {
        guard let start = preview.earliestWorkoutDate, let end = preview.latestWorkoutDate else {
            return "No workouts"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        }

        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension UTType {
    static let reppoWorkoutHistoryBackup = UTType(exportedAs: "com.magnusespensen.reppo.workout-history", conformingTo: .json)
}
