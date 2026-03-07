// ImportView.swift
// CSV import flow: file picker → preview → progress → result.
// Spec: FR-001 through FR-009
// Feature: 011-csv-import-export WP03 T012-T016

import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {

    @State private var viewModel: ImportViewModel
    @Environment(\.dismiss) private var dismiss

    init(importService: any ImportServiceProtocol) {
        _viewModel = State(initialValue: ImportViewModel(importService: importService))
    }

    // MARK: - Body

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

    // MARK: - Idle State (T013)

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)

            Text("Import Training Data")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Text("Select a CSV file from another training app to import your workout history.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                viewModel.showFilePicker = true
            } label: {
                Label("Select CSV File", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Preview State (T014)

    private var previewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Preview")
                    .font(.title2.bold())
                    .foregroundStyle(Color.textPrimary)

                Text("\(viewModel.estimatedTotalRows) rows found")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                // Column mapping
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
                            Text(columnMapping(for: header))
                                .font(.caption)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
                .padding()
                .background(Color.bgCard)
                .cornerRadius(12)

                // Sample data
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample Data")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            // Header row
                            HStack(spacing: 0) {
                                ForEach(viewModel.previewHeaders, id: \.self) { header in
                                    Text(header)
                                        .font(.caption2.bold())
                                        .frame(width: 100, alignment: .leading)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }

                            Divider()

                            // Data rows
                            ForEach(Array(viewModel.previewRows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 0) {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, field in
                                        Text(field.isEmpty ? "—" : field)
                                            .font(.caption2)
                                            .frame(width: 100, alignment: .leading)
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

                // Action buttons
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

    // MARK: - Importing State (T015)

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

    // MARK: - Rebuilding State (T015)

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

    // MARK: - Completed State (T016)

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
                        resultRow(label: "Sets Imported", value: "\(result.setsImported)")
                        resultRow(label: "Workouts Created", value: "\(result.workoutsCreated)")
                        resultRow(label: "Exercises Created", value: "\(result.exercisesCreated)")

                        if result.rowsSkipped > 0 {
                            resultRow(label: "Rows Skipped", value: "\(result.rowsSkipped)")
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

    // MARK: - Failed State (T016)

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

    private func resultRow(label: String, value: String) -> some View {
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

    private func columnMapping(for header: String) -> String {
        switch header {
        case "Date": return "→ Workout date"
        case "Exercise": return "→ Exercise name"
        case "Category": return "→ Primary muscle"
        case "Weight (kg)": return "→ Set weight"
        case "Weight (lbs)": return "→ Ignored"
        case "Reps": return "→ Set reps"
        case "Distance": return "→ Distance (meters)"
        case "Distance Unit": return "→ Unit conversion"
        case "Time": return "→ Duration (seconds)"
        case "Notes": return "→ Set notes"
        case "Kind": return "→ Exercise type"
        default: return "→ Unknown"
        }
    }
}
