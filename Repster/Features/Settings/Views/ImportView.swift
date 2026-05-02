// ImportView.swift
// Source-aware CSV import flow: source selection → file picker → preview → progress → result.

import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {

    @State private var viewModel: ImportViewModel
    @Environment(\.dismiss) private var dismiss

    init(importService: any ImportServiceProtocol) {
        _viewModel = State(initialValue: ImportViewModel(importService: importService))
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
    }

    // MARK: - Idle

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.textSecondary)

                VStack(spacing: 10) {
                    Text("Import Training Data")
                        .font(.title2.bold())
                        .foregroundStyle(Color.textPrimary)

                    Text("Choose the workout app export you want to import.")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Export Source")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    ForEach(ImportSource.allCases) { source in
                        ImportSourceOptionCard(
                            source: source,
                            isSelected: viewModel.selectedSource == source
                        ) {
                            viewModel.chooseSource(source)
                        }
                    }
                }
                .padding(.horizontal, 20)

                if viewModel.selectedSource.requiresUnitSystem {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Strong Export Units")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        Text("Strong CSV files do not declare their units, so choose the unit system used in the export before previewing it.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)

                        ImportUnitSystemChooser(
                            selectedUnitSystem: viewModel.selectedStrongUnitSystem
                        ) { unitSystem in
                            viewModel.chooseStrongUnitSystem(unitSystem)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Button {
                    viewModel.showFilePicker = true
                } label: {
                    Label(viewModel.selectedSource.fileSelectionTitle, systemImage: "doc.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSelectFile)
                .padding(.horizontal, 32)

                ImportSupportCallout()
                    .padding(.horizontal, 32)

                Spacer(minLength: 32)
            }
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
            case "Weight (kg)": return "→ Set weight"
            case "Weight (lbs)": return "→ Ignored"
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
        }
    }
}

struct ImportSourceOptionCard: View {
    let source: ImportSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: source.systemImageName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
                    .frame(width: 28, height: 28)

                Text(source.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
            }
            .padding()
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct ImportUnitSystemChooser: View {
    let selectedUnitSystem: ImportUnitSystem?
    let onSelect: (ImportUnitSystem) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ImportUnitSystem.allCases) { unitSystem in
                Button {
                    onSelect(unitSystem)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(unitSystem.displayName)
                                .font(.headline)
                                .foregroundStyle(Color.textPrimary)
                            Text(unitSystem.subtitle)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }

                        Spacer()

                        Image(systemName: selectedUnitSystem == unitSystem ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedUnitSystem == unitSystem ? Color.accent : Color.textSecondary)
                    }
                    .padding()
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
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
