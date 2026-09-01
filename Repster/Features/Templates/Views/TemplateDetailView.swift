// TemplateDetailView.swift
// What a template prescribes, shown before you start it.
//
// Start stays the primary action, with Edit and Duplicate beside it — both labelled, because
// icon-only controls are the same discoverability trap as a menu nobody can find.

import SwiftUI

struct TemplateDetailView: View {

    @State private var viewModel: TemplateDetailViewModel
    private let template: TemplateSummary
    private let onStart: () -> Void
    private let onEdit: () -> Void
    private let onDuplicate: () -> Void
    private let onExport: () -> Void
    private let onDelete: () -> Void

    init(
        template: TemplateSummary,
        templateService: any TemplateServiceProtocol,
        onStart: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.template = template
        self.onStart = onStart
        self.onEdit = onEdit
        self.onDuplicate = onDuplicate
        self.onExport = onExport
        self.onDelete = onDelete
        _viewModel = State(initialValue: TemplateDetailViewModel(
            templateId: template.id,
            templateService: templateService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    statTiles
                    if let notes = viewModel.detail?.template.notes, !notes.isEmpty {
                        notesCard(notes)
                    }
                    exercisesSection
                }
                .padding(.bottom, 20)
            }

            actionBar
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { onExport() } label: {
                        Label("Export Template", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete Template", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name)
                // The name is content the user wrote, masked wherever it is shown.
                .replayMasked()
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let folder = viewModel.folder {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                    Text(folder)
                        .replayMasked()
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Stats

    /// Three tiles, all of them real.
    ///
    /// A "times done" tile is deliberately absent: nothing links a workout back to the template that
    /// produced it, so any count would be invented. `lastUsedAt` is stamped when a workout *starts*,
    /// which is why this says Last used rather than Last done.
    private var statTiles: some View {
        HStack(spacing: 7) {
            statTile(value: "\(viewModel.exerciseCount)", label: "EXERCISES")
            statTile(value: "\(viewModel.setCount)", label: "SETS")
            statTile(value: viewModel.lastUsedDescription, label: "LAST USED")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11).stroke(Color.border, lineWidth: 1)
        )
    }

    private func notesCard(_ notes: String) -> some View {
        Text(notes)
            .replayMasked()
            .font(.system(size: 13))
            .foregroundColor(.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.border, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 12)
    }

    // MARK: - Exercises

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("EXERCISES")
                .font(.system(size: 10, weight: .bold))
                .kerning(0.9)
                .foregroundColor(.textTertiary)
                .padding(.top, 18)
                .padding(.bottom, 1)

            if viewModel.isLoading {
                ProgressView().tint(Color.accent).frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if viewModel.rows.isEmpty {
                Text("This template has no exercises yet.")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ForEach(viewModel.rows) { row in
                    switch row {
                    case let .single(number, exercise):
                        exerciseCard(number: "\(number)", exercise: exercise, tint: .textTertiary)
                    case let .superset(_, letter, members):
                        supersetBlock(letter: letter, members: members)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func exerciseCard(number: String, exercise: TemplateExerciseDetail, tint: Color) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 18, alignment: .leading)

            exerciseBody(exercise)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 1))
    }

    private func supersetBlock(letter: String, members: [TemplateDetailSupersetMember]) -> some View {
        let tint = TemplateDetailLayout.color(forGroupIndex: TemplateDetailLayout.groupIndex(forLetter: letter))

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .bold))
                Text("SUPERSET \(letter)")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.7)
            }
            .foregroundStyle(tint)
            .padding(.leading, 2)

            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                if index > 0 {
                    Rectangle()
                        .fill(tint.opacity(0.20))
                        .frame(height: 1)
                        .padding(.leading, 30)
                }
                HStack(spacing: 12) {
                    Text(member.label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(tint)
                        .frame(width: 18, alignment: .leading)

                    exerciseBody(member.exercise)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(9)
        .background(tint.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.30), lineWidth: 1))
    }

    private func exerciseBody(_ exercise: TemplateExerciseDetail) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.exerciseName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(2)

            HStack(spacing: 6) {
                let warmups = TemplateDetailLayout.warmupCount(for: exercise.sets)
                if warmups > 0 {
                    Text("\(warmups) warmup")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gold)
                    dot
                }

                if let prescription = TemplateDetailLayout.prescription(for: exercise.sets) {
                    Text(prescription)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                }

                if let rir = exercise.sets.first(where: { $0.setType != .warmup })?.targetRIR {
                    dot
                    Text("RIR \(rir)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.rirColor(for: Double(rir)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dot: some View {
        Circle().fill(Color.textTertiary).frame(width: 3, height: 3)
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 9) {
            secondaryAction(title: "Edit", systemImage: "pencil", action: onEdit)
            secondaryAction(title: "Copy", systemImage: "doc.on.doc", action: onDuplicate)

            Button(action: onStart) {
                HStack(spacing: 9) {
                    Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                    Text("Start Workout").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            Color.bg.overlay(Rectangle().fill(Color.border).frame(height: 1), alignment: .top)
        )
    }

    private func secondaryAction(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .medium))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.textSecondary)
            .frame(width: 56, height: 50)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
