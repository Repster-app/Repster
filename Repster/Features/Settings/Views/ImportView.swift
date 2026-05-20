// ImportView.swift
// Source-aware CSV import flow: source selection → file picker → preview → progress → result.

import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {

    @State private var viewModel: ImportViewModel
    @Environment(\.dismiss) private var dismiss

    private let exerciseService: any ExerciseServiceProtocol

    init(
        importService: any ImportServiceProtocol,
        defaultUnitPreference: UnitPreference = .metric,
        analyticsService: any AnalyticsServiceProtocol = NoopAnalyticsService(),
        exerciseService: any ExerciseServiceProtocol
    ) {
        _viewModel = State(initialValue: ImportViewModel(
            importService: importService,
            defaultUnitPreference: defaultUnitPreference,
            analyticsService: analyticsService,
            exerciseService: exerciseService
        ))
        self.exerciseService = exerciseService
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .previewing:
                previewView
            case .importing:
                progressView
            case .rebuilding:
                rebuildingView
            case .completed:
                completedView
            case .failed:
                failedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
        .navigationTitle("Import Data")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.commaSeparatedText]
        ) { result in
            viewModel.handleFileSelected(result)
        }
        .sheet(isPresented: $viewModel.showAssignMuscleGroups) {
            AssignMuscleGroupsView(exerciseService: exerciseService)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.textSecondary)

                VStack(spacing: 6) {
                    Text("Import Training Data")
                        .font(.title2.bold())
                        .foregroundStyle(Color.textPrimary)

                    Text("Choose the workout app export you want to import.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Export Source")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 12) {
                        ForEach(ImportSource.allCases) { source in
                            compactSourceTile(source)
                        }
                    }
                }
                .padding(.horizontal, 20)

                if viewModel.selectedSource == .fitNotes {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FitNotes Weight Units")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        compactUnitPicker(
                            selected: viewModel.selectedFitNotesUnitSystem,
                            onSelect: { viewModel.chooseFitNotesUnitSystem($0) }
                        )
                    }
                    .padding(.horizontal, 20)
                } else if viewModel.selectedSource.requiresUnitSystem {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(viewModel.selectedSource.displayName) Export Units")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        compactUnitPicker(
                            selected: viewModel.unitSystem(for: viewModel.selectedSource),
                            onSelect: { viewModel.chooseUnitSystem($0, for: viewModel.selectedSource) }
                        )

                        Text(compactUnitHint(for: viewModel.selectedSource))
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 20)
                }

                Button {
                    viewModel.showFilePicker = true
                } label: {
                    Label(viewModel.selectedSource.fileSelectionTitle, systemImage: "doc.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSelectFile)
                .padding(.horizontal, 32)

                ImportSupportCallout(isCompact: true)
                    .padding(.horizontal, 32)

                Spacer(minLength: 16)
            }
            .padding(.top, 8)
        }
    }

    private func compactSourceTile(_ source: ImportSource) -> some View {
        let isSelected = viewModel.selectedSource == source
        return Button {
            viewModel.chooseSource(source)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: source.systemImageName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)

                Text(source.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func compactUnitPicker(
        selected: ImportUnitSystem?,
        onSelect: @escaping (ImportUnitSystem) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(ImportUnitSystem.allCases) { unitSystem in
                Button {
                    onSelect(unitSystem)
                } label: {
                    Text(unitSystem.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            selected == unitSystem ? Color.accent : Color.bgCard,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func compactUnitHint(for source: ImportSource) -> String {
        switch source {
        case .strong:
            return "Strong exports don't include units — pick the one used in your export."
        case .hevy:
            return "Hevy's column is labeled kg but uses your in-app unit — pick the one used in your export."
        case .fitNotes:
            return ""
        }
    }

    // MARK: - Preview

    private var previewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Preview")
                    .font(.title2.bold())
                    .foregroundStyle(Color.textPrimary)

                VStack(spacing: 10) {
                    summaryRow(label: "Source", value: viewModel.activeSourceSummary)
                    if let unitSummary = viewModel.activeUnitSummary {
                        summaryRow(label: "Units", value: unitSummary)
                    }
                    summaryRow(label: "Rows Found", value: "\(viewModel.estimatedTotalRows)")
                }
                .padding()
                .background(Color.bgCard)
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Column Mapping")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    ForEach(Array(viewModel.previewHeaders.enumerated()), id: \.offset) { _, header in
                        HStack {
                            Text(header)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(columnMapping(for: header, source: viewModel.activeSource))
                                .font(.caption)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
                .padding()
                .background(Color.bgCard)
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample Data")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 0) {
                                ForEach(viewModel.previewHeaders, id: \.self) { header in
                                    Text(header)
                                        .font(.caption2.bold())
                                        .frame(width: 120, alignment: .leading)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }

                            Divider()

                            ForEach(Array(viewModel.previewRows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 0) {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, field in
                                        Text(field.isEmpty ? "—" : field)
                                            .font(.caption2)
                                            .frame(width: 120, alignment: .leading)
                                            .foregroundStyle(Color.textPrimary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
                .background(Color.bgCard)
                .cornerRadius(12)

                HStack(spacing: 16) {
                    Button("Cancel") {
                        viewModel.reset()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Import \(viewModel.estimatedTotalRows) Rows") {
                        viewModel.confirmImport()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }

    // MARK: - Importing

    private var progressView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)
                .tint(Color.accent)
                .padding(.horizontal, 32)

            Text(viewModel.progressLabel)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            if viewModel.setsInserted > 0 {
                Text("\(viewModel.setsInserted) of \(viewModel.totalSets) sets processed")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Rebuilding

    private var rebuildingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.accent)

            Text(viewModel.progressLabel)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            Text("This may take a moment for large datasets.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)

            Spacer()
        }
    }

    // MARK: - Completed

    private var completedView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.success)

                Text("Import Complete")
                    .font(.title2.bold())
                    .foregroundStyle(Color.textPrimary)

                if let result = viewModel.result {
                    VStack(spacing: 12) {
                        summaryRow(label: "Sets Imported", value: "\(result.setsImported)")
                        summaryRow(label: "Workouts Created", value: "\(result.workoutsCreated)")
                        summaryRow(label: "Exercises Created", value: "\(result.exercisesCreated)")

                        if result.rowsSkipped > 0 {
                            summaryRow(label: "Rows Skipped", value: "\(result.rowsSkipped)")
                        }

                        if !result.warnings.isEmpty {
                            summaryRow(label: "Warnings", value: "\(result.warnings.count)")
                        }

                        Text(String(format: "Completed in %.1f seconds", result.duration))
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding()
                    .background(Color.bgCard)
                    .cornerRadius(12)

                    if !result.errors.isEmpty {
                        DisclosureGroup("Skipped Rows (\(result.errors.count))") {
                            ForEach(result.errors) { error in
                                Text("Row \(error.rowNumber): \(error.reason)")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            }
                        }
                        .foregroundStyle(Color.textPrimary)
                        .padding()
                        .background(Color.bgCard)
                        .cornerRadius(12)
                    }

                    if !result.warnings.isEmpty {
                        DisclosureGroup("Warnings (\(result.warnings.count))") {
                            ForEach(result.warnings) { warning in
                                Text("Row \(warning.rowNumber): \(warning.reason)")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            }
                        }
                        .foregroundStyle(Color.textPrimary)
                        .padding()
                        .background(Color.bgCard)
                        .cornerRadius(12)
                    }
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)

                Spacer(minLength: 40)
            }
            .padding()
        }
    }

    // MARK: - Failed

    private var failedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.danger)

            Text("Import Failed")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if viewModel.shouldShowSupportCTA {
                ImportSupportCallout()
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Try Again") {
                    viewModel.retry()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.body.bold())
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func columnMapping(for header: String, source: ImportSource) -> String {
        switch source {
        case .fitNotes:
            switch header {
            case "Date": return "→ Workout date"
            case "Exercise": return "→ Exercise name"
            case "Category": return "→ Primary muscle"
            case "Weight (kg)":
                return viewModel.activeUnitSystem == .metric ? "→ Preferred weight" : "→ Fallback weight"
            case "Weight (lbs)":
                return viewModel.activeUnitSystem == .imperial ? "→ Preferred weight" : "→ Fallback weight"
            case "Reps": return "→ Set reps"
            case "Distance": return "→ Distance"
            case "Distance Unit": return "→ Unit conversion"
            case "Time": return "→ Duration"
            case "Notes": return "→ Set notes"
            case "Kind": return "→ Exercise type"
            default: return "→ Unknown"
            }
        case .strong:
            switch header {
            case "Date": return "→ Workout start time"
            case "Workout Name": return "→ Workout title"
            case "Duration": return "→ Workout duration"
            case "Exercise Name": return "→ Exercise name"
            case "Set Order": return "→ Set tag/order"
            case "Weight": return "→ Set weight"
            case "Reps": return "→ Set reps"
            case "Distance": return "→ Distance"
            case "Seconds": return "→ Duration"
            case "RPE": return "→ Set RPE"
            default: return "→ Unknown"
            }
        case .hevy:
            switch header {
            case "title": return "→ Workout title"
            case "start_time": return "→ Workout start"
            case "end_time": return "→ Workout end"
            case "description": return "→ Workout notes"
            case "exercise_title": return "→ Exercise name"
            case "superset_id": return "→ Ignored"
            case "exercise_notes": return "→ Set notes (first set)"
            case "set_index": return "→ Set order"
            case "set_type": return "→ Set tag"
            case "weight_kg": return "→ Set weight (unit-converted)"
            case "reps": return "→ Set reps"
            case "distance_km": return "→ Distance (unit-converted)"
            case "duration_seconds": return "→ Duration"
            case "rpe": return "→ Set RPE"
            default: return "→ Unknown"
            }
        }
    }
}

struct ImportSupportCallout: View {
    var isCompact: Bool = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        if isCompact {
            Button {
                guard let url = SupportEmailComposer.importSupportURL() else { return }
                openURL(url)
            } label: {
                Label("Need another app? Email us", systemImage: "envelope")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            VStack(spacing: 10) {
                Text("Need support for another training app or export format? Email \(SupportEmailComposer.address) and tell us which export you use.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    guard let url = SupportEmailComposer.importSupportURL() else { return }
                    openURL(url)
                } label: {
                    Label("Email \(SupportEmailComposer.address)", systemImage: "envelope")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.bgCard)
            .cornerRadius(12)
        }
    }
}
