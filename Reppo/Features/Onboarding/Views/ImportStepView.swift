// ImportStepView.swift
// CSV import step during onboarding — reuses the existing ImportViewModel.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T025

import SwiftUI
import UniformTypeIdentifiers

struct ImportStepView: View {
    @State private var viewModel: ImportViewModel
    let isSaving: Bool
    let onFinish: () -> Void
    let onSkip: () -> Void

    init(importService: any ImportServiceProtocol,
         isSaving: Bool,
         onFinish: @escaping () -> Void,
         onSkip: @escaping () -> Void) {
        _viewModel = State(initialValue: ImportViewModel(importService: importService))
        self.isSaving = isSaving
        self.onFinish = onFinish
        self.onSkip = onSkip
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .previewing:
                previewView
            case .importing, .rebuilding:
                progressView
            case .completed:
                completedView
            case .failed:
                failedView
            }
        }
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.commaSeparatedText]
        ) { result in
            viewModel.handleFileSelected(result)
        }
    }

    // MARK: - Idle (initial state)

    private var idleView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accent)

                Text("Migrating from Another App?")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("Reppo currently supports FitNotes CSV exports only. You can also start fresh.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                viewModel.showFilePicker = true
            } label: {
                Label("Select FitNotes CSV", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)

            ImportSupportCallout()
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button("Get Started") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSaving)

                Button("Skip") { onSkip() }
                    .foregroundStyle(Color.textSecondary)
                    .disabled(isSaving)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(spacing: 16) {
            Text("\(viewModel.estimatedTotalRows) rows found")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 24)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        ForEach(viewModel.previewHeaders, id: \.self) { header in
                            Text(header)
                                .font(.caption2.bold())
                                .frame(width: 100, alignment: .leading)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    Divider()
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
            .background(Color.bgCard)
            .cornerRadius(12)
            .padding(.horizontal, 16)

            Spacer()

            HStack(spacing: 16) {
                Button("Cancel") { viewModel.reset() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button("Import \(viewModel.estimatedTotalRows) Rows") {
                    viewModel.confirmImport()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Progress

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

            Spacer()
        }
    }

    // MARK: - Completed

    private var completedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.success)

            Text("Import Complete")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            if let result = viewModel.result {
                VStack(spacing: 8) {
                    Text("\(result.setsImported) sets imported")
                    Text("\(result.workoutsCreated) workouts created")
                    Text("\(result.exercisesCreated) exercises created")
                }
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Button("Get Started") { onFinish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
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

            Spacer()

            HStack(spacing: 16) {
                Button("Skip") { onSkip() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button("Try Again") { viewModel.retry() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
