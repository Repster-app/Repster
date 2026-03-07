// TemplateListSheet.swift
// Bottom sheet showing saved templates for the user to select and start a workout from.
// Presented from HomeView when "Use Template" is tapped in StartWorkoutSheet.
// Supports: template selection, create new, edit, delete (swipe).

import SwiftUI

struct TemplateListSheet: View {

    @State private var viewModel: TemplateListViewModel
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

                Button {
                    dismiss()
                    onCreateTemplate()
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
                        onEdit: {
                            dismiss()
                            onEditTemplate(template.id)
                        },
                        onDelete: {
                            viewModel.confirmDelete(template.id)
                        }
                    )
                }
            }
        }
    }
}
