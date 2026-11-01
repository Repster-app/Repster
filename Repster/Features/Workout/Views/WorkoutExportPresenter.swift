// WorkoutExportPresenter.swift
// Raises the system share sheet with a saved workout's JSON export. One modifier for both
// history surfaces, the same split as `.shareWorkoutCard`.
// Scoping: WORKOUT_EXPORT_SCOPING.md

import SwiftUI
import UIKit

/// Where the export was raised from. Same values as `ShareCardEntryPoint`'s history cases, so
/// the two events break down the same way in PostHog.
enum WorkoutExportEntryPoint: String {
    /// The "…" menu in a workout's header row in the Calendar day pane.
    case calendar
    /// The toolbar "…" menu on the workout detail screen — reached from Home, the Workouts tab
    /// and the Exercises tab.
    case workoutDetail = "workout_detail"
}

extension View {
    /// Exports `detail` and presents the share sheet whenever it is set, then clears it.
    func exportWorkout(
        item detail: Binding<WorkoutDetail?>,
        entryPoint: WorkoutExportEntryPoint
    ) -> some View {
        modifier(ExportWorkoutModifier(detail: detail, entryPoint: entryPoint))
    }
}

private struct WorkoutExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ExportWorkoutModifier: ViewModifier {
    @Binding var detail: WorkoutDetail?
    let entryPoint: WorkoutExportEntryPoint

    @Environment(ServiceContainer.self) private var services
    @State private var file: WorkoutExportFile?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            // Keyed on the id because `WorkoutDetail` is not `Equatable`. Cleared straight away so
            // exporting the same workout twice is a fresh nil -> id change each time.
            .onChange(of: detail?.workout.id) { _, workoutId in
                guard workoutId != nil, let detail else { return }
                self.detail = nil
                prepare(detail)
            }
            .sheet(item: $file) { file in
                WorkoutExportActivitySheet(activityItems: [file.url]) { activityType in
                    services.analyticsService.workoutExported(
                        entryPoint: entryPoint,
                        destination: activityType?.rawValue ?? ShareCardDestination.unknown
                    )
                }
            }
            .alert(
                "Export Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    /// Synchronous on purpose: one workout is a few dozen rows, already in memory as snapshots.
    private func prepare(_ detail: WorkoutDetail) {
        do {
            let export = WorkoutExportBuilder.make(detail: detail, unitPreference: services.unitPreference)
            let data = try WorkoutExportBuilder.encode(export)
            let url = try writeTemporaryFile(data, named: WorkoutExportBuilder.filename(for: detail))
            file = WorkoutExportFile(url: url)
        } catch {
            services.analyticsService.captureError(error, context: .workoutExport)
            errorMessage = error.localizedDescription
        }
    }

    /// Its own directory, cleared on every export so files never pile up in tmp — the same
    /// rule as the backup export, and the sweep can't touch anything else living there.
    private func writeTemporaryFile(_ data: Data, named filename: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("WorkoutExports", isDirectory: true)
        try? fileManager.removeItem(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// `UIActivityViewController` with a completion handler, so `workout exported` fires on a share
/// that happened rather than on the tap. Private rather than a promotion of the share card's
/// copy: consolidating the share-sheet wrappers is the separate job
/// [TemplateSharing.swift:6](Repster/Features/Templates/Views/TemplateSharing.swift:6) parks.
private struct WorkoutExportActivitySheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    /// Called only when the share completed. `activityType` is nil when the sheet reports
    /// success without naming an activity.
    let onComplete: (UIActivity.ActivityType?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            guard completed else { return }
            onComplete(activityType)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
