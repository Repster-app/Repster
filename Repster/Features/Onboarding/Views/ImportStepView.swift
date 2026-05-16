// ImportStepView.swift
// Import step during onboarding — reuses the source-aware ImportViewModel.

import SwiftUI
import UniformTypeIdentifiers

struct ImportStepView: View {
    @State private var viewModel: ImportViewModel
    private let defaultUnitPreference: UnitPreference
    let isSaving: Bool
    let onFinish: () -> Void
    let onSkip: () -> Void

    init(
        importService: any ImportServiceProtocol,
        defaultUnitPreference: UnitPreference = .metric,
        isSaving: Bool,
        onFinish: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: ImportViewModel(
            importService: importService,
            defaultUnitPreference: defaultUnitPreference
        ))
        self.defaultUnitPreference = defaultUnitPreference
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
        .onAppear {
            let defaultUnitSystem: ImportUnitSystem = defaultUnitPreference == .imperial ? .imperial : .metric
            viewModel.chooseFitNotesUnitSystem(defaultUnitSystem)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 46, weight: .semibold))
                            .foregroundStyle(Color.accent)

                        Text("Import Workout History")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textPrimary)

                        Text("Bring over past workouts from FitNotes or Strong now, or start fresh and import later from Settings.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Source")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)

                        HStack(spacing: 12) {
                            ForEach(ImportSource.allCases) { source in
                                onboardingSourceTile(source)
                            }
                        }

                        Text("Units in CSV")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.top, 4)

                        onboardingUnitPicker
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.top, 24)
                .padding(.bottom, 12)
            }

            VStack(spacing: 10) {
                Button {
                    viewModel.showFilePicker = true
                } label: {
                    Label(viewModel.selectedSource.fileSelectionTitle, systemImage: "doc.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canSelectFile || isSaving)

                Button {
                    onSkip()
                } label: {
                    Label("Start Without Importing", systemImage: "arrow.right.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSaving)

                ImportSupportCallout(isCompact: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(Color.bg)
        }
    }

    private func onboardingSourceTile(_ source: ImportSource) -> some View {
        Button {
            viewModel.chooseSource(source)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: source.systemImageName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(viewModel.selectedSource == source ? Color.accent : Color.textSecondary)

                Text(source.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Image(systemName: viewModel.selectedSource == source ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(viewModel.selectedSource == source ? Color.accent : Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.selectedSource == source ? Color.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var onboardingUnitPicker: some View {
        HStack(spacing: 8) {
            ForEach(ImportUnitSystem.allCases) { unitSystem in
                Button {
                    selectUnitSystem(unitSystem)
                } label: {
                    Text(unitSystem.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            selectedUnitSystem == unitSystem
                                ? Color.accent
                                : Color.bgCard,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedUnitSystem: ImportUnitSystem? {
        switch viewModel.selectedSource {
        case .fitNotes:
            return viewModel.selectedFitNotesUnitSystem
        case .strong:
            return viewModel.selectedStrongUnitSystem
        }
    }

    private func selectUnitSystem(_ unitSystem: ImportUnitSystem) {
        switch viewModel.selectedSource {
        case .fitNotes:
            viewModel.chooseFitNotesUnitSystem(unitSystem)
        case .strong:
            viewModel.chooseStrongUnitSystem(unitSystem)
        }
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(viewModel.activeSourceSummary)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                if let unitSummary = viewModel.activeUnitSummary {
                    Text(unitSummary)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Text("\(viewModel.estimatedTotalRows) rows found")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.top, 24)

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
                    if !result.warnings.isEmpty {
                        Text("\(result.warnings.count) warnings to review later")
                    }
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
                Button("Start Without Importing") { onSkip() }
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
