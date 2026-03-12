// CreateEditTemplateView.swift
// Full-screen view for creating or editing a workout template.
// Shows template name, exercise list with expandable set editors,
// superset grouping, rest time, and notes per exercise.

import SwiftUI

struct CreateEditTemplateView: View {

    private let editingTemplateId: UUID?
    @State private var viewModel: CreateEditTemplateViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(ServiceContainer.self) private var services

    init(
        templateService: any TemplateServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        editingTemplateId: UUID? = nil
    ) {
        self.editingTemplateId = editingTemplateId
        _viewModel = State(initialValue: CreateEditTemplateViewModel(
            templateService: templateService,
            exerciseService: exerciseService
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Template name
                    nameSection

                    // Exercises header + list
                    exercisesSection

                    // Add exercise button
                    addExerciseButton
                }
                .padding(.horizontal, 20)
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
                                dismiss()
                            } catch {
                                print("[CreateEditTemplateView] Save failed: \(error)")
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSave || viewModel.isSaving)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: editingTemplateId) {
            await viewModel.prepareForPresentation(editingTemplateId: editingTemplateId)
        }
        .sheet(isPresented: $viewModel.showExercisePicker) {
            exercisePickerSheet
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
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.textPrimary)
                .padding(14)
                .background(Color.bgInput)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.border, lineWidth: 1)
                )
        }
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
                        viewModel: viewModel
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

    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            headerRow

            // Expanded detail
            if exercise.isExpanded {
                Divider()
                    .background(Color.border)

                expandedContent
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
            }
        }
        .background(Color.bgCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        Button {
            viewModel.toggleExpanded(at: exerciseIndex)
        } label: {
            HStack(spacing: 10) {
                // Reorder buttons
                VStack(spacing: 2) {
                    Button {
                        if exerciseIndex > 0 {
                            viewModel.moveExercise(
                                from: IndexSet(integer: exerciseIndex),
                                to: exerciseIndex - 1
                            )
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(exerciseIndex > 0 ? .textSecondary : .textTertiary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(exerciseIndex <= 0)

                    Button {
                        if exerciseIndex < viewModel.exercises.count - 1 {
                            viewModel.moveExercise(
                                from: IndexSet(integer: exerciseIndex),
                                to: exerciseIndex + 2
                            )
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(exerciseIndex < viewModel.exercises.count - 1 ? .textSecondary : .textTertiary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(exerciseIndex >= viewModel.exercises.count - 1)
                }
                .frame(width: 16)

                // Exercise name with superset color
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

                // Expand arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .rotationEffect(exercise.isExpanded ? .degrees(90) : .zero)
                    .animation(.easeInOut(duration: 0.2), value: exercise.isExpanded)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            // Move Up (if not first)
            if exerciseIndex > 0 {
                Button {
                    viewModel.moveExercise(
                        from: IndexSet(integer: exerciseIndex),
                        to: exerciseIndex - 1
                    )
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
            }

            // Move Down (if not last)
            if exerciseIndex < viewModel.exercises.count - 1 {
                Button {
                    viewModel.moveExercise(
                        from: IndexSet(integer: exerciseIndex),
                        to: exerciseIndex + 2
                    )
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
            }

            Divider()

            // Superset group
            Menu("Superset Group") {
                ForEach(["A", "B", "C"], id: \.self) { label in
                    Button {
                        viewModel.setSupersetGroup(for: exerciseIndex, label: label)
                    } label: {
                        HStack {
                            Text("Group \(label)")
                            if viewModel.currentSupersetLabel(for: exerciseIndex) == label {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Button("None") {
                    viewModel.setSupersetGroup(for: exerciseIndex, label: nil)
                }
            }

            // Notes
            Button {
                // Toggle notes visibility — for now just set empty notes to trigger editing
                if exercise.notes == nil {
                    viewModel.exercises[exerciseIndex].notes = ""
                    viewModel.exercises[exerciseIndex].isExpanded = true
                }
            } label: {
                Label(exercise.notes != nil ? "Edit Note" : "Add Note", systemImage: "note.text")
            }

            Divider()

            // Remove exercise
            Button(role: .destructive) {
                viewModel.removeExercise(at: exerciseIndex)
            } label: {
                Label("Remove Exercise", systemImage: "trash")
            }
        }
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
            Text("SETS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
                .kerning(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

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

    private var addSetButtons: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.addWarmupSet(to: exerciseIndex)
            } label: {
                Text("＋ Warmup")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.goldSoft)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.addWorkingSet(to: exerciseIndex)
            } label: {
                Text("＋ Working Set")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.accentSoft)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
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

    @State private var repRangeText: String = ""
    @State private var rirText: String = ""

    var body: some View {
        HStack(spacing: 6) {
            // Set badge
            Text(displayNumber)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isWarmup ? .gold : .textPrimary)
                .frame(width: 26, height: 26)
                .background(isWarmup ? Color.goldSoft : Color.bgSubtle)
                .cornerRadius(7)

            // Set type label
            Text(isWarmup ? "W" : "Set")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
                .frame(width: 28, alignment: .leading)

            // Rep range input
            TextField("6-8", text: $repRangeText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 7)
                .padding(.horizontal, 4)
                .background(Color.bgInput)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.border, lineWidth: 1)
                )
                .frame(maxWidth: .infinity)
                .onChange(of: repRangeText) { _, newValue in
                    parseRepRange(newValue)
                }

            // RIR input
            TextField("RIR", text: $rirText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(rirColor)
                .multilineTextAlignment(.center)
                .padding(.vertical, 7)
                .padding(.horizontal, 4)
                .background(Color.bgInput)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.border, lineWidth: 1)
                )
                .frame(width: 44)
                .keyboardType(.numberPad)
                .onChange(of: rirText) { _, newValue in
                    viewModel.exercises[exerciseIndex].sets[setIndex].targetRIR = Int(newValue)
                }

            // Copy button
            Button {
                viewModel.duplicateSet(exerciseIndex: exerciseIndex, setIndex: setIndex)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(Color.bgSubtle)
                    .cornerRadius(7)
            }
            .buttonStyle(.plain)

            // Delete button
            Button {
                viewModel.removeSet(exerciseIndex: exerciseIndex, setIndex: setIndex)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.danger)
                    .frame(width: 26, height: 26)
                    .background(Color.dangerSoft)
                    .cornerRadius(7)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.bg)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.border, lineWidth: 1)
        )
        .padding(.bottom, 4)
        .onAppear {
            // Initialize text from model
            if let min = editorSet.targetRepMin, let max = editorSet.targetRepMax {
                repRangeText = min == max ? "\(min)" : "\(min)-\(max)"
            }
            if let rir = editorSet.targetRIR {
                rirText = "\(rir)"
            }
        }
    }

    private var rirColor: Color {
        guard let rir = editorSet.targetRIR else { return .textTertiary }
        return Color.rirColor(for: Double(rir))
    }

    /// Parse "6-8" → targetRepMin=6, targetRepMax=8
    /// Parse "8" → targetRepMin=8, targetRepMax=8
    private func parseRepRange(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("-") {
            let parts = trimmed.split(separator: "-")
            if parts.count == 2, let min = Int(parts[0]), let max = Int(parts[1]) {
                viewModel.exercises[exerciseIndex].sets[setIndex].targetRepMin = min
                viewModel.exercises[exerciseIndex].sets[setIndex].targetRepMax = max
            }
        } else if let single = Int(trimmed) {
            viewModel.exercises[exerciseIndex].sets[setIndex].targetRepMin = single
            viewModel.exercises[exerciseIndex].sets[setIndex].targetRepMax = single
        } else {
            viewModel.exercises[exerciseIndex].sets[setIndex].targetRepMin = nil
            viewModel.exercises[exerciseIndex].sets[setIndex].targetRepMax = nil
        }
    }
}
