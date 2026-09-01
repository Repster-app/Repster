// CreateEditTemplateView.swift
// Full-screen view for creating or editing a workout template.
// Shows template name, exercise list with expandable set editors,
// superset grouping, rest time, and notes per exercise.

import SwiftUI
import UniformTypeIdentifiers

struct CreateEditTemplateView: View {

    private let editingTemplateId: UUID?
    private let existingFolders: [String]
    private let onSaved: (() -> Void)?
    @State private var viewModel: CreateEditTemplateViewModel
    @State private var draggedExerciseId: UUID? = nil
    @State private var dropTargetExerciseId: UUID? = nil
    @State private var supersetSubjectIndex: Int? = nil
    @State private var showFolderPicker = false
    @Environment(\.dismiss) private var dismiss
    @Environment(ServiceContainer.self) private var services

    init(
        templateService: any TemplateServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        editingTemplateId: UUID? = nil,
        existingFolders: [String] = [],
        analyticsService: any AnalyticsServiceProtocol = NoopAnalyticsService(),
        onSaved: (() -> Void)? = nil
    ) {
        self.editingTemplateId = editingTemplateId
        self.existingFolders = existingFolders
        self.onSaved = onSaved
        _viewModel = State(initialValue: CreateEditTemplateViewModel(
            templateService: templateService,
            exerciseService: exerciseService,
            analyticsService: analyticsService
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Template name
                nameSection

                // Exercises header + list
                exercisesSection

                // Add exercise button
                addExerciseButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.bg)
        .navigationTitle(editingTemplateId != nil ? "Edit Template" : "New Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        do {
                            try await viewModel.save()
                            onSaved?()
                            dismiss()
                        } catch {
                            dbg("[CreateEditTemplateView] Save failed: \(error)")
                        }
                    }
                }
                .fontWeight(.semibold)
                .disabled(!viewModel.canSave || viewModel.isSaving)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: editingTemplateId) {
            await viewModel.prepareForPresentation(editingTemplateId: editingTemplateId)
        }
        .sheet(isPresented: $viewModel.showExercisePicker) {
            exercisePickerSheet
        }
        .sheet(isPresented: Binding(
            get: { supersetSubjectIndex != nil },
            set: { if !$0 { supersetSubjectIndex = nil } }
        )) {
            if let index = supersetSubjectIndex {
                SupersetPartnerSheet(
                    subjectName: viewModel.exercises[safe: index]?.exerciseName ?? "",
                    nextLetter: viewModel.nextSupersetLetter,
                    candidates: viewModel.supersetCandidates(for: index),
                    onPair: { partnerIndex in
                        viewModel.pairExercise(at: index, withExerciseAt: partnerIndex)
                        supersetSubjectIndex = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            TemplateFolderSheet(
                current: viewModel.templateFolder,
                existingFolders: existingFolders,
                onPick: { folder in
                    viewModel.templateFolder = folder
                    showFolderPicker = false
                }
            )
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEMPLATE NAME")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
                .kerning(0.8)

            TextField("e.g. Push Day, Upper Body A...", text: $viewModel.templateName)
                // Masked while typed; the saved name is content, shown in every list.
                .replayMasked()
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.textPrimary)
                .padding(14)
                .background(Color.bgInput)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.border, lineWidth: 1)
                )

            folderRow
        }
    }

    /// Filing is reachable while you are making the template, not only from a context menu you would
    /// have to know exists.
    private var folderRow: some View {
        Button {
            showFolderPicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text("Folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text(viewModel.templateFolder ?? "None")
                    .replayMasked()
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(viewModel.templateFolder == nil ? .textTertiary : .textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 13)
            .frame(height: 48)
            .background(Color.bgCard)
            .cornerRadius(11)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Exercises Section

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EXERCISES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .kerning(0.8)

                Spacer()

                if !viewModel.exercises.isEmpty {
                    Text("\(viewModel.exercises.count) exercises · \(viewModel.totalSetCount) sets")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.textTertiary)
                }
            }

            if viewModel.exercises.isEmpty {
                emptyExercisesState
            } else {
                ForEach(Array(viewModel.exercises.enumerated()), id: \.element.id) { index, exercise in
                    TemplateExerciseCard(
                        exercise: exercise,
                        exerciseIndex: index,
                        viewModel: viewModel,
                        draggedExerciseId: $draggedExerciseId,
                        dropTargetExerciseId: $dropTargetExerciseId,
                        onRequestSuperset: { supersetSubjectIndex = $0 }
                    )
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyExercisesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "dumbbell")
                .font(.system(size: 32))
                .foregroundColor(.textTertiary)

            Text("No exercises added")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)

            Text("Add exercises to build your template")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Add Exercise Button

    private var addExerciseButton: some View {
        Button {
            viewModel.showExercisePicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add Exercise")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.accentSoft)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Exercise Picker Sheet

    private var exercisePickerSheet: some View {
        NavigationStack {
            ExerciseListView(
                mode: .addToWorkout,
                onExercisesSelected: { selectedIds in
                    Task {
                        await viewModel.addExercises(selectedIds)
                        viewModel.showExercisePicker = false
                    }
                },
                services: services
            )
        }
    }
}

// MARK: - Template Exercise Card

/// A single exercise card in the template editor with expandable detail.
private struct TemplateExerciseCard: View {

    let exercise: EditorExercise
    let exerciseIndex: Int
    var viewModel: CreateEditTemplateViewModel
    @Binding var draggedExerciseId: UUID?
    @Binding var dropTargetExerciseId: UUID?
    let onRequestSuperset: (Int) -> Void

    private var isDraggedCard: Bool {
        draggedExerciseId == exercise.id
    }

    private var isDropTargetCard: Bool {
        dropTargetExerciseId == exercise.id && draggedExerciseId != exercise.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            headerRow

            // Expanded detail
            if exercise.isExpanded {
                Divider()
                    .background(Color.border)

                expandedContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
        }
        .background(isDropTargetCard ? Color.accentSoft.opacity(0.28) : Color.bgCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isDropTargetCard ? Color.accent : (isDraggedCard ? Color.accent.opacity(0.45) : Color.border),
                    lineWidth: isDropTargetCard ? 1.5 : 1
                )
        )
        .overlay(alignment: .topLeading) {
            if isDropTargetCard {
                Capsule()
                    .fill(Color.accent)
                    .frame(width: 44, height: 4)
                    .padding(.top, 10)
                    .padding(.leading, 14)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .scaleEffect(isDraggedCard ? 0.985 : (isDropTargetCard ? 1.01 : 1))
        .opacity(isDraggedCard ? 0.72 : 1)
        .shadow(
            color: isDropTargetCard ? Color.accent.opacity(0.18) : .clear,
            radius: isDropTargetCard ? 14 : 0,
            x: 0,
            y: isDropTargetCard ? 8 : 0
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: isDraggedCard)
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: isDropTargetCard)
        .onDrop(
            of: [UTType.text],
            delegate: TemplateExerciseDropDelegate(
                targetExerciseId: exercise.id,
                draggedExerciseId: $draggedExerciseId,
                dropTargetExerciseId: $dropTargetExerciseId,
                viewModel: viewModel
            )
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .onDrag {
                    draggedExerciseId = exercise.id
                    return NSItemProvider(object: exercise.id.uuidString as NSString)
                }
                .accessibilityLabel("Reorder exercise")

            Button {
                viewModel.toggleExpanded(at: exerciseIndex)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if let label = viewModel.supersetLabel(for: exercise.supersetGroupId) {
                                Text(label)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(viewModel.supersetColor(for: exercise.supersetGroupId))
                            }
                            Text(exercise.exerciseName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(exercise.supersetGroupId != nil
                                    ? viewModel.supersetColor(for: exercise.supersetGroupId)
                                    : .textPrimary)
                        }

                        Text(exerciseSummaryText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .rotationEffect(exercise.isExpanded ? .degrees(90) : .zero)
                        .animation(.easeInOut(duration: 0.2), value: exercise.isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        }
        .padding(14)
    }

    private var exerciseSummaryText: String {
        let warmups = exercise.sets.filter { $0.setType == .warmup }.count
        let working = exercise.sets.filter { $0.setType != .warmup }.count

        var parts: [String] = []
        if warmups > 0 { parts.append("\(warmups) warmup") }
        if working > 0 { parts.append("\(working) working") }

        // Rep range from first working set
        if let firstWorking = exercise.sets.first(where: { $0.setType != .warmup }) {
            if let min = firstWorking.targetRepMin, let max = firstWorking.targetRepMax {
                parts.append(min == max ? "\(min) reps" : "\(min)-\(max) reps")
            }
            if let rir = firstWorking.targetRIR {
                parts.append("RIR \(rir)")
            }
        }

        if let rest = exercise.restTimeSeconds {
            parts.append("\(rest)s rest")
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 12) {
            // Set list
            setList

            // Add set buttons
            addSetButtons

            // Rest time config
            restTimeRow

            // Notes (only shown if notes exist — added via context menu)
            if exercise.notes != nil {
                notesSection
            }
        }
    }

    // MARK: - Set List

    private var setList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("SET")
                    .frame(width: 30, alignment: .leading)
                Text("REP RANGE")
                    .frame(width: 98, alignment: .center)
                Text("RIR")
                    .frame(width: 46, alignment: .center)
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .bold))
            .kerning(0.6)
            .foregroundColor(.textTertiary)
            .padding(.horizontal, 2)
            .padding(.bottom, 6)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, editorSet in
                TemplateSetRow(
                    editorSet: editorSet,
                    setIndex: setIndex,
                    exerciseIndex: exerciseIndex,
                    isWarmup: editorSet.setType == .warmup,
                    displayNumber: displayNumber(for: setIndex),
                    viewModel: viewModel
                )
            }
        }
    }

    private func displayNumber(for setIndex: Int) -> String {
        let set = exercise.sets[setIndex]
        if set.setType == .warmup {
            let warmupIndex = exercise.sets.prefix(setIndex + 1).filter { $0.setType == .warmup }.count
            return "W\(warmupIndex)"
        } else {
            let workingIndex = exercise.sets.prefix(setIndex + 1).filter { $0.setType != .warmup }.count
            return "\(workingIndex)"
        }
    }

    // MARK: - Add Set Buttons

    /// Warm-up takes half the width of Working Set: most exercises have none, and it is the rarer of
    /// the two adds. `More` carries everything that used to sit behind an unlabelled ellipsis in the
    /// card header, so the mystery glyph is gone from every row.
    private var addSetButtons: some View {
        HStack(spacing: 7) {
            Button {
                viewModel.addWarmupSet(to: exerciseIndex)
            } label: {
                Text("＋ Warmup")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gold)
                    .frame(width: 84)
                    .frame(height: 38)
                    .background(Color.goldSoft)
                    .cornerRadius(9)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.addWorkingSet(to: exerciseIndex)
            } label: {
                Text("＋ Working Set")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.accentSoft)
                    .cornerRadius(9)
            }
            .buttonStyle(.plain)

            Menu {
                exerciseActions
            } label: {
                HStack(spacing: 5) {
                    Text("More").font(.system(size: 12.5, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.textPrimary)
                .frame(width: 78)
                .frame(height: 38)
                .background(Color.bgSubtle)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.border, lineWidth: 1))
            }
            .accessibilityLabel("More actions for \(exercise.exerciseName)")
        }
    }

    /// Named More rather than Special: in lifting apps "special set" means drop sets and myo-reps, so
    /// the word would promise set techniques and deliver superset, note and folder. See
    /// TEMPLATES_IMPLEMENTATION_PLAN.md P4.1.
    @ViewBuilder
    private var exerciseActions: some View {
        if exercise.supersetGroupId == nil {
            Button {
                onRequestSuperset(exerciseIndex)
            } label: {
                Label("Superset with…", systemImage: "link")
            }
        } else {
            Button {
                viewModel.removeFromSuperset(at: exerciseIndex)
            } label: {
                Label("Remove from superset", systemImage: "link.badge.plus")
            }
        }

        Button {
            viewModel.exercises[exerciseIndex].notes = exercise.notes ?? ""
            viewModel.exercises[exerciseIndex].isExpanded = true
        } label: {
            Label(exercise.notes != nil ? "Edit note" : "Add note", systemImage: "note.text")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.removeExercise(at: exerciseIndex)
        } label: {
            Label("Remove exercise", systemImage: "trash")
        }
    }

    // MARK: - Rest Time Row

    private var restTimeRow: some View {
        HStack {
            Text("Rest Time")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)

            Spacer()

            HStack(spacing: 8) {
                TextField("—", value: Binding(
                    get: { exercise.restTimeSeconds },
                    set: { viewModel.exercises[exerciseIndex].restTimeSeconds = $0 }
                ), format: .number)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
                .frame(width: 60)
                .padding(6)
                .background(Color.bgInput)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.border, lineWidth: 1)
                )
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)

                Text("sec")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Notes

    private var notesSection: some View {
        TextEditor(text: Binding(
            get: { exercise.notes ?? "" },
            set: { viewModel.exercises[exerciseIndex].notes = $0.isEmpty ? nil : $0 }
        ))
        .scrollContentBackground(.hidden)
        .font(.system(size: 13))
        .foregroundColor(.textPrimary)
        .frame(minHeight: 60)
        .padding(8)
        .background(Color.bgInput)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.border, lineWidth: 1)
        )
        // Free text: the same category as a workout note.
        .replayMasked()
        .overlay(alignment: .topLeading) {
            if exercise.notes == nil || exercise.notes?.isEmpty == true {
                Text("Exercise notes (e.g., use close grip, pause at bottom...)")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Template Set Row

/// A single set row in the template editor with rep range and RIR inputs.
private struct TemplateSetRow: View {

    let editorSet: EditorSet
    let setIndex: Int
    let exerciseIndex: Int
    let isWarmup: Bool
    let displayNumber: String
    var viewModel: CreateEditTemplateViewModel

    @State private var minText: String = ""
    @State private var maxText: String = ""
    @State private var rirText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(displayNumber)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isWarmup ? .gold : .textPrimary)
                .frame(width: 30, height: 32)
                .background(isWarmup ? Color.goldSoft : Color.bgSubtle)
                .cornerRadius(7)

            // Two fields, not one free-text box.
            //
            // The old single field parsed "8" into min == max — a fixed target, which the suggestion
            // engine cannot progress (SUGGESTION_PROGRESSION_DESIGN.md P2). Typing one number was the
            // easy path into a shape that silently opts out of the app's headline feature. Two fields
            // make a range the default and a fixed target something you type twice on purpose.
            HStack(spacing: 5) {
                repField(text: $minText, placeholder: "8", accessibilityLabel: "Minimum reps")
                Text("–")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
                repField(text: $maxText, placeholder: "10", accessibilityLabel: "Maximum reps")
            }
            .frame(width: 98)

            TextField("RIR", text: $rirText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(rirColor)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .frame(width: 46, height: 32)
                .background(Color.bgInput)
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.border, lineWidth: 1))
                .accessibilityLabel("Reps in reserve")
                .onChange(of: rirText) { _, newValue in
                    viewModel.exercises[exerciseIndex].sets[setIndex].targetRIR = Int(newValue)
                }

            Spacer(minLength: 0)

            Button {
                viewModel.duplicateSet(exerciseIndex: exerciseIndex, setIndex: setIndex)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(Color.bgSubtle)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Duplicate set")

            Button {
                viewModel.removeSet(exerciseIndex: exerciseIndex, setIndex: setIndex)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.danger)
                    .frame(width: 32, height: 32)
                    .background(Color.dangerSoft)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove set")
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .onAppear {
            if let min = editorSet.targetRepMin { minText = "\(min)" }
            if let max = editorSet.targetRepMax { maxText = "\(max)" }
            if let rir = editorSet.targetRIR { rirText = "\(rir)" }
        }
    }

    private func repField(
        text: Binding<String>,
        placeholder: String,
        accessibilityLabel: String
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.textPrimary)
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Color.bgInput)
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.border, lineWidth: 1))
            .accessibilityLabel(accessibilityLabel)
            .onChange(of: text.wrappedValue) { _, _ in applyRepBounds() }
    }

    private var rirColor: Color {
        guard let rir = editorSet.targetRIR else { return .textTertiary }
        return Color.rirColor(for: Double(rir))
    }

    /// Each field owns its own bound. Clearing one clears only that side, where the old parser threw
    /// away both — and silently kept the previous value on malformed input like "6-".
    private func applyRepBounds() {
        viewModel.exercises[exerciseIndex].sets[setIndex].targetRepMin = Int(minText.trimmingCharacters(in: .whitespaces))
        viewModel.exercises[exerciseIndex].sets[setIndex].targetRepMax = Int(maxText.trimmingCharacters(in: .whitespaces))
    }
}

private struct TemplateExerciseDropDelegate: DropDelegate {
    let targetExerciseId: UUID
    @Binding var draggedExerciseId: UUID?
    @Binding var dropTargetExerciseId: UUID?
    let viewModel: CreateEditTemplateViewModel

    func dropEntered(info: DropInfo) {
        guard let draggedExerciseId else { return }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            if draggedExerciseId == targetExerciseId {
                dropTargetExerciseId = nil
            } else {
                dropTargetExerciseId = targetExerciseId
                viewModel.moveExercise(
                    draggedExerciseId: draggedExerciseId,
                    toDropTargetExerciseId: targetExerciseId
                )
            }
        }
    }

    func dropExited(info: DropInfo) {
        guard dropTargetExerciseId == targetExerciseId else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            dropTargetExerciseId = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.easeOut(duration: 0.18)) {
            draggedExerciseId = nil
            dropTargetExerciseId = nil
        }
        return true
    }
}


// MARK: - Superset partner sheet

/// You pick a **partner**; the app assigns the letter.
///
/// The old flow asked for a letter, on one exercise at a time, with nothing saying a second step
/// existed — so people assigned Group A once and ended up with a superset of one. That state is not
/// reachable from here.
private struct SupersetPartnerSheet: View {

    let subjectName: String
    let nextLetter: String
    let candidates: [SupersetCandidate]
    let onPair: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pair \(subjectName) with one other exercise")
                        .replayMasked()
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                    ForEach(Array(candidates.enumerated()), id: \.element.id) { offset, candidate in
                        Button {
                            guard candidate.isSelectable else { return }
                            onPair(candidate.index)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.name)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Text(candidate.detailText)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(candidate.wouldMove && candidate.isSelectable ? .chart5 : .textTertiary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                            }
                            .frame(minHeight: 58)
                            .padding(.horizontal, 20)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!candidate.isSelectable)
                        // Grouped exercises stay visible rather than vanishing from the list.
                        .opacity(candidate.isSelectable ? 1 : 0.42)

                        if offset < candidates.count - 1 {
                            Rectangle().fill(Color.border).frame(height: 1).padding(.leading, 20)
                        }
                    }

                    if candidates.isEmpty {
                        Text("Add another exercise first — a superset needs two.")
                            .font(.system(size: 13))
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        HStack(spacing: 9) {
                            Image(systemName: "link")
                                .font(.system(size: 12, weight: .bold))
                            Text("These two become Superset \(nextLetter)")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        .foregroundStyle(Color.chart5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(Color.chart5.opacity(0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.chart5.opacity(0.25), lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color.bg)
            .navigationTitle("Superset with")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Folder sheet

/// A folder exists because a template names it. Picking "None" and moving the last template out is
/// how one stops existing — there is no folder to delete separately.
private struct TemplateFolderSheet: View {

    let current: String?
    let existingFolders: [String]
    let onPick: (String?) -> Void

    @State private var newFolderName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        onPick(nil)
                    } label: {
                        HStack {
                            Text("Not in a folder").foregroundColor(.textPrimary)
                            Spacer()
                            if current == nil {
                                Image(systemName: "checkmark").foregroundStyle(Color.accent)
                            }
                        }
                    }

                    ForEach(existingFolders, id: \.self) { folder in
                        Button {
                            onPick(folder)
                        } label: {
                            HStack {
                                Text(folder).replayMasked().foregroundColor(.textPrimary)
                                Spacer()
                                if TemplateFolder.groupingKey(current) == TemplateFolder.groupingKey(folder) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accent)
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack(spacing: 10) {
                        TextField("New folder name", text: $newFolderName)
                            .replayMasked()
                            .autocorrectionDisabled()
                        Button("Add") {
                            onPick(newFolderName)
                        }
                        .disabled(TemplateFolder.normalized(newFolderName) == nil)
                        .fontWeight(.semibold)
                    }
                } footer: {
                    Text("Folders are just names. Move the last template out and the folder goes with it.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
