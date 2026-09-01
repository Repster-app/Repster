// TemplateFlowView.swift
// The templates screen: folder chips, search, grouped rows, and navigation into detail and the editor.
//
// Split out of TemplateListSheet.swift, which had grown to 1,271 lines holding four separate screens.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum TemplateFlowRoute: Hashable, Identifiable {
    case create(sessionId: UUID)
    case edit(templateId: UUID)
    case detail(templateId: UUID)

    var id: String {
        switch self {
        case .create(let sessionId):
            return "create-\(sessionId.uuidString)"
        case .edit(let templateId):
            return "edit-\(templateId.uuidString)"
        case .detail(let templateId):
            return "detail-\(templateId.uuidString)"
        }
    }

    var editingTemplateId: UUID? {
        switch self {
        case .create, .detail:
            return nil
        case .edit(let templateId):
            return templateId
        }
    }
}

struct TemplateFlowView: View {

    private let templateService: any TemplateServiceProtocol
    private let exerciseService: any ExerciseServiceProtocol
    @State private var viewModel: TemplateListViewModel
    @State private var navigationPath = NavigationPath()
    @State private var showImportPicker = false
    @State private var isImportingTemplate = false
    @State private var exportingTemplateId: UUID? = nil
    @State private var shareSheetItem: TemplateShareItem? = nil
    @State private var actionAlert: TemplateActionAlert? = nil
    @State private var pendingImportReview: PendingTemplateImportReview? = nil
    @Environment(\.dismiss) private var dismiss

    let beforeStartWorkout: () async -> Bool
    let onStartWorkout: () -> Void
    let workoutStartOptions: WorkoutStartOptions
    let analyticsService: any AnalyticsServiceProtocol

    init(
        templateService: any TemplateServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        beforeStartWorkout: @escaping () async -> Bool,
        onStartWorkout: @escaping () -> Void,
        workoutStartOptions: WorkoutStartOptions = .default,
        analyticsService: any AnalyticsServiceProtocol = NoopAnalyticsService()
    ) {
        self.templateService = templateService
        self.exerciseService = exerciseService
        _viewModel = State(initialValue: TemplateListViewModel(templateService: templateService))
        self.beforeStartWorkout = beforeStartWorkout
        self.onStartWorkout = onStartWorkout
        self.workoutStartOptions = workoutStartOptions
        self.analyticsService = analyticsService
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading {
                    loadingState
                } else if viewModel.templates.isEmpty {
                    emptyState
                } else {
                    templateList
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 14) {
                        Button {
                            showImportPicker = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)
                        }
                        .accessibilityLabel("Import template")

                        Button {
                            navigationPath.append(TemplateFlowRoute.create(sessionId: UUID()))
                        } label: {
                            Text("New")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            }
            .navigationDestination(for: TemplateFlowRoute.self) { route in
                switch route {
                case .detail(let templateId):
                    if let template = viewModel.templates.first(where: { $0.id == templateId }) {
                        TemplateDetailView(
                            template: template,
                            templateService: templateService,
                            onStart: { startWorkout(from: template) },
                            onEdit: { navigationPath.append(TemplateFlowRoute.edit(templateId: templateId)) },
                            onDuplicate: { Task { await duplicateTemplate(template) } },
                            onExport: { Task { await exportTemplate(template) } },
                            onDelete: { viewModel.confirmDelete(templateId) }
                        )
                        .id(route.id)
                    }

                case .create, .edit:
                    CreateEditTemplateView(
                        templateService: templateService,
                        exerciseService: exerciseService,
                        editingTemplateId: route.editingTemplateId,
                        existingFolders: viewModel.folderChips.filter { !$0.isAll }.map(\.name),
                        analyticsService: analyticsService,
                        onSaved: {
                            Task { await viewModel.loadTemplates() }
                        }
                    )
                    .id(route.id)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: UTType.templateImportTypes
        ) { result in
            handleImportSelection(result)
        }
        .sheet(item: $shareSheetItem) { item in
            TemplateShareSheet(activityItems: [item.url])
        }
        .sheet(item: $pendingImportReview) { item in
            TemplateImportReviewSheet(
                preview: item.preview,
                viewModel: viewModel,
                exerciseService: exerciseService,
                onImported: handleImportedTemplate
            )
        }
        .task {
            await viewModel.loadTemplates()
            // The one emitter for this screen. It was defined in AnalyticsScreen and never sent, so
            // the whole templates flow was invisible — which is why nobody can say whether the AI
            // helper is used. See TEMPLATES_IMPLEMENTATION_PLAN.md P0.2.
            analyticsService.screen(.templates)
        }
        .alert("Delete Template?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.performDelete()
                    analyticsService.templateDeleted()
                    // The detail screen for a deleted template has nothing left to show.
                    if !navigationPath.isEmpty {
                        navigationPath = NavigationPath()
                    }
                }
            }
        } message: {
            Text("This will permanently delete this template. This action cannot be undone.")
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay {
            if isImportingTemplate || exportingTemplateId != nil {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.accent)
                        Text(isImportingTemplate ? "Preparing import..." : "Preparing export...")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(24)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(Color.accent)
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundColor(.textTertiary)

                    Text("No templates yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Text("Create your first template or save one after finishing a workout.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    Button {
                        navigationPath.append(TemplateFlowRoute.create(sessionId: UUID()))
                    } label: {
                        Label("Create Template", systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.accent)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .background(Color.bgCard)
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.border, lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }

    private var templateList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                if viewModel.showsSearchField {
                    searchField
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                }

                if viewModel.showsFolderChips {
                    folderChipRow
                        .padding(.bottom, 14)
                }

                if viewModel.hasNoMatches {
                    noMatchesState
                } else {
                    ForEach(viewModel.sections) { section in
                        if let title = section.title {
                            sectionHeader(title: title, count: section.count)
                        }

                        ForEach(Array(section.templates.enumerated()), id: \.element.id) { index, template in
                            TemplateRowView(
                                template: template,
                                showsDivider: index < section.templates.count - 1,
                                onTap: { openTemplate(template) }
                            )
                            .padding(.horizontal, 20)
                            .contextMenu { rowMenu(for: template) }
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.loadTemplates()
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textTertiary)

            TextField("Search templates", text: $viewModel.searchText)
                // A template name is content the user wrote, same category as the name field itself.
                .replayMasked()
                .font(.system(size: 15))
                .foregroundStyle(Color.textPrimary)
                .autocorrectionDisabled()

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(Color.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private var folderChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(viewModel.folderChips) { chip in
                    let isSelected = chip.isAll
                        ? (viewModel.selectedFolderID == nil || viewModel.selectedFolderID == TemplateFolderChip.allID)
                        : viewModel.selectedFolderID == chip.id

                    Button {
                        viewModel.selectedFolderID = chip.isAll ? nil : chip.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(chip.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text("\(chip.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .opacity(0.65)
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.textSecondary)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(isSelected ? Color.accent : Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(isSelected ? Color.clear : Color.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)

            Text(title.uppercased())
                // A full-width header, so a user-named folder has somewhere to go. This is why the
                // rows carry no folder tag: a 9pt pill cannot hold a name the app did not choose.
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) template\(count == 1 ? "" : "s")")
    }

    private var noMatchesState: some View {
        VStack(spacing: 8) {
            Text("No templates match")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textSecondary)
            Text("Try a different search, or pick another folder.")
                .font(.system(size: 13))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    @ViewBuilder
    private func rowMenu(for template: TemplateSummary) -> some View {
        Button {
            startWorkout(from: template)
        } label: {
            Label("Start Workout", systemImage: "play.fill")
        }

        Button {
            navigationPath.append(TemplateFlowRoute.edit(templateId: template.id))
        } label: {
            Label("Edit Template", systemImage: "pencil")
        }

        Button {
            Task { await duplicateTemplate(template) }
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button {
            Task { await exportTemplate(template) }
        } label: {
            Label("Export Template", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.confirmDelete(template.id)
        } label: {
            Label("Delete Template", systemImage: "trash")
        }
    }

    /// Tapping opens the template rather than starting a workout on the spot. Instant start read as
    /// abrupt rather than fast, and it left no way to see what was in a template before committing.
    private func openTemplate(_ template: TemplateSummary) {
        navigationPath.append(TemplateFlowRoute.detail(templateId: template.id))
    }

    private func duplicateTemplate(_ template: TemplateSummary) async {
        do {
            _ = try await viewModel.duplicateTemplate(template.id)
            analyticsService.templateDuplicated()
        } catch {
            actionAlert = TemplateActionAlert(
                title: "Couldn’t Duplicate",
                message: error.localizedDescription
            )
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            actionAlert = TemplateActionAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )

        case .success(let url):
            Task {
                await importTemplate(from: url)
            }
        }
    }

    private func importTemplate(from url: URL) async {
        isImportingTemplate = true
        defer { isImportingTemplate = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let preview = try await viewModel.previewTemplateImport(data: data)

            if preview.unresolvedExercises.isEmpty {
                let importedId = try await viewModel.finalizeTemplateImport(preview, resolutions: [])
                handleImportedTemplate(importedId)
            } else {
                pendingImportReview = PendingTemplateImportReview(preview: preview)
            }
        } catch {
            actionAlert = TemplateActionAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func exportTemplate(_ template: TemplateSummary) async {
        exportingTemplateId = template.id
        defer { exportingTemplateId = nil }

        do {
            let data = try await viewModel.exportTemplate(template.id)
            let url = try templateTemporaryShareURL(
                filename: sanitizedFilename(template.name),
                fileExtension: "repstertemplate",
                data: data
            )
            shareSheetItem = TemplateShareItem(url: url)
        } catch {
            actionAlert = TemplateActionAlert(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }

    private func handleImportedTemplate(_ importedId: UUID) {
        Task {
            await viewModel.loadTemplates()
            // Third of the three creation paths, previously uncounted.
            if let imported = viewModel.templates.first(where: { $0.id == importedId }) {
                analyticsService.templateCreated(
                    exerciseCount: imported.exerciseCount,
                    source: "import"
                )
            }
            let importedName = viewModel.templates.first(where: { $0.id == importedId })?.name ?? "Template"
            actionAlert = TemplateActionAlert(
                title: "Template Imported",
                message: "\"\(importedName)\" was added to your templates."
            )
        }
    }

    private func startWorkout(from template: TemplateSummary) {
        Task {
            do {
                guard await beforeStartWorkout() else { return }
                _ = try await viewModel.startWorkoutFromTemplate(
                    template.id,
                    options: workoutStartOptions
                )
                WorkoutStartContextStore.remember(source: .template, templateUsed: true)
                analyticsService.templateStarted(
                    exerciseCount: template.exerciseCount,
                    inFolder: template.folder != nil
                )
                analyticsService.workoutStarted(
                    source: .template,
                    templateUsed: true,
                    copiedPrevious: false,
                    countTowardProgression: workoutStartOptions.countTowardProgressionHistory
                )
                onStartWorkout()
            } catch {
                actionAlert = TemplateActionAlert(
                    title: "Couldn’t Start Workout",
                    message: error.localizedDescription
                )
            }
        }
    }
}
