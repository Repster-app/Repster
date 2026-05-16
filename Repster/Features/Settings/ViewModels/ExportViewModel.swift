import Foundation

struct WorkoutHistoryBackupShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

@Observable @MainActor
final class ExportViewModel {

    // MARK: - State

    var isExporting = false
    var shareItem: WorkoutHistoryBackupShareItem?
    var errorMessage: String?

    // MARK: - Dependencies

    private let workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol
    private let analyticsService: any AnalyticsServiceProtocol

    // MARK: - Init

    init(
        workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol,
        analyticsService: any AnalyticsServiceProtocol = NoopAnalyticsService()
    ) {
        self.workoutHistoryBackupService = workoutHistoryBackupService
        self.analyticsService = analyticsService
    }

    // MARK: - Actions

    func generateExport() {
        isExporting = true
        errorMessage = nil
        shareItem = nil

        Task {
            do {
                let data = try await workoutHistoryBackupService.exportBackup()
                let url = try temporaryShareURL(for: data)
                self.shareItem = WorkoutHistoryBackupShareItem(url: url)
                self.analyticsService.track(.backupExported)
                self.isExporting = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isExporting = false
            }
        }
    }

    func reset() {
        shareItem = nil
        errorMessage = nil
        isExporting = false
    }

    private func temporaryShareURL(for data: Data) throws -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let filename = "repster-workout-history-backup-\(formatter.string(from: Date()))"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension("repsterbackup")

        try data.write(to: url, options: .atomic)
        return url
    }
}

@Observable @MainActor
final class RestoreBackupViewModel {

    enum RestoreState: Equatable {
        case idle
        case previewing
        case restoring
        case completed
        case failed
    }

    // MARK: - State

    var state: RestoreState = .idle
    var showFilePicker = false
    var showReplaceConfirmation = false
    var preview: WorkoutHistoryBackupPreview?
    var result: WorkoutHistoryRestoreResult?
    var errorMessage: String?

    // MARK: - Dependencies

    private let workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol
    private var backupData: Data?

    // MARK: - Init

    init(workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol) {
        self.workoutHistoryBackupService = workoutHistoryBackupService
    }

    // MARK: - File Selection

    func handleFileSelected(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            state = .failed

        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let preview = try workoutHistoryBackupService.previewBackup(data: data)

                self.backupData = data
                self.preview = preview
                self.result = nil
                self.errorMessage = nil
                self.state = .previewing
            } catch {
                errorMessage = error.localizedDescription
                state = .failed
            }
        }
    }

    // MARK: - Restore

    func confirmRestore() {
        showReplaceConfirmation = true
    }

    func performRestore() {
        guard let backupData else { return }

        state = .restoring
        errorMessage = nil
        result = nil
        showReplaceConfirmation = false

        Task {
            do {
                let result = try await workoutHistoryBackupService.restoreBackup(data: backupData)
                self.result = result
                self.state = .completed
            } catch {
                self.errorMessage = error.localizedDescription
                self.state = .failed
            }
        }
    }

    // MARK: - Reset / Retry

    func reset() {
        state = .idle
        showFilePicker = false
        showReplaceConfirmation = false
        preview = nil
        result = nil
        errorMessage = nil
        backupData = nil
    }

    func retry() {
        errorMessage = nil
        state = .idle
        showFilePicker = true
    }
}
