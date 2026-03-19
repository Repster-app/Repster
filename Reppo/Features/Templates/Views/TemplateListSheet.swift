// TemplateListSheet.swift
// Bottom sheet showing saved templates for the user to select and start a workout from.
// Presented from HomeView when "Use Template" is tapped in StartWorkoutSheet.
// Supports: template selection, create new, edit, delete (swipe).

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TemplateListSheet: View {

    @State private var viewModel: TemplateListViewModel
    @State private var showImportPicker = false
    @State private var isImportingTemplate = false
    @State private var exportingTemplateId: UUID? = nil
    @State private var shareSheetItem: TemplateShareItem? = nil
    @State private var actionAlert: TemplateActionAlert? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(ServiceContainer.self) private var services

    let onStartWorkout: () -> Void
    let onCreateTemplate: () -> Void
    let onEditTemplate: (UUID) -> Void

    init(
        templateService: any TemplateServiceProtocol,
        onStartWorkout: @escaping () -> Void,
        onCreateTemplate: @escaping () -> Void,
        onEditTemplate: @escaping (UUID) -> Void
    ) {
        _viewModel = State(initialValue: TemplateListViewModel(templateService: templateService))
        self.onStartWorkout = onStartWorkout
        self.onCreateTemplate = onCreateTemplate
        self.onEditTemplate = onEditTemplate
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.bgSubtle)
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 16)

            // Header
            HStack {
                Text("Templates")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        showImportPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 12, weight: .bold))
                            Text("Import")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentSoft)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onCreateTemplate()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("New")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accent)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            Text("Select a template to start your workout")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            // Content
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if viewModel.templates.isEmpty {
                emptyState
            } else {
                templateList
            }

            // Cancel button
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.bg)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCard.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.bgCard)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.reppoTemplate]
        ) { result in
            handleImportSelection(result)
        }
        .sheet(item: $shareSheetItem) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
        .task {
            await viewModel.loadTemplates()
        }
        .alert("Delete Template?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            Button("Delete", role: .destructive) {
                Task { await viewModel.performDelete() }
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
                        Text(isImportingTemplate ? "Importing template…" : "Preparing export…")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(24)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundColor(.textTertiary)

            Text("No templates yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textSecondary)

            Text("Create your first template or save one after finishing a workout")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Template List

    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.templates) { template in
                    TemplateCardView(
                        template: template,
                        isExporting: exportingTemplateId == template.id,
                        onTap: {
                            Task {
                                do {
                                    _ = try await viewModel.startWorkoutFromTemplate(template.id)
                                    dismiss()
                                    onStartWorkout()
                                } catch {
                                    print("[TemplateListSheet] Start from template failed: \(error)")
                                }
                            }
                        },
                        onExport: {
                            Task { await exportTemplate(template) }
                        },
                        onEdit: {
                            onEditTemplate(template.id)
                            dismiss()
                        },
                        onDelete: {
                            viewModel.confirmDelete(template.id)
                        }
                    )
                }
            }
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
            let importedId = try await viewModel.importTemplate(data: data)
            await viewModel.loadTemplates()

            let importedName = viewModel.templates.first(where: { $0.id == importedId })?.name ?? "Template"
            actionAlert = TemplateActionAlert(
                title: "Template Imported",
                message: "\"\(importedName)\" was added to your templates."
            )
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
            let url = try temporaryShareURL(for: template.name, data: data)
            shareSheetItem = TemplateShareItem(url: url)
        } catch {
            actionAlert = TemplateActionAlert(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }

    private func temporaryShareURL(for templateName: String, data: Data) throws -> URL {
        let sanitizedName = sanitizedFilename(templateName)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedName).reppotemplate")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func sanitizedFilename(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "template" : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = fallback.components(separatedBy: invalidCharacters)
        return components.joined(separator: "-")
    }
}

private struct TemplateActionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct TemplateShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension UTType {
    static let reppoTemplate = UTType(exportedAs: "com.magnusespensen.reppo.template", conformingTo: .json)
}
