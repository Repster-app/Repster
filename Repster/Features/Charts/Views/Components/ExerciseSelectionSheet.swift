// ExerciseSelectionSheet.swift
// Modal sheet for selecting exercises for the Exercises tab chart.
// Features: Current/Presets tabs, add/remove/reorder, preset CRUD.
// Feature: 016-charts-tab-v2 WP09 (T130, T131, T132, T133, T134)

import SwiftUI

struct ExerciseSelectionSheet: View {
    @Binding var selectedExercises: [(id: UUID, name: String, category: String)]
    @Binding var isPresented: Bool
    let onApply: () -> Void
    let exerciseService: any ExerciseServiceProtocol

    @State private var activeTab: SelectionTab = .current
    @State private var presets: [ChartPreset] = []
    @State private var showAddExercise = false
    @State private var showSavePresetAlert = false
    @State private var presetName = ""
    @State private var showPresetEmptyAlert = false

    @Environment(ServiceContainer.self) private var services

    private let presetStore = ChartPresetStore()

    enum SelectionTab { case current, presets }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.bgSubtle)
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                // Title
                Text("Select Exercises")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("Choose up to 10 exercises")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 16)

                // Current / Presets tabs
                HStack(spacing: 4) {
                    tabButton("Current", tab: .current)
                    tabButton("Presets", tab: .presets)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Content
                ScrollView {
                    if activeTab == .current {
                        currentTabContent
                    } else {
                        presetsTabContent
                    }
                }

                // Footer
                footerButtons
            }
            .background(Color.bgCard)
            .onAppear { presets = presetStore.loadPresets() }
            .alert("Save Preset", isPresented: $showSavePresetAlert) {
                TextField("Preset name", text: $presetName)
                Button("Save") {
                    guard !presetName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let preset = ChartPreset(
                        name: presetName.trimmingCharacters(in: .whitespaces),
                        exerciseIds: selectedExercises.map { $0.id }
                    )
                    presetStore.savePreset(preset)
                    presets = presetStore.loadPresets()
                    presetName = ""
                }
                Button("Cancel", role: .cancel) { presetName = "" }
            }
            .alert("Preset Empty", isPresented: $showPresetEmptyAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("All exercises in this preset have been deleted.")
            }
            .sheet(isPresented: $showAddExercise) {
                NavigationStack {
                    ExerciseListView(
                        mode: .addToWorkout,
                        onExercisesSelected: { exerciseIds in
                            Task { await addExercises(exerciseIds) }
                            showAddExercise = false
                        },
                        services: services
                    )
                }
            }
        }
    }

    // MARK: - Tab Button

    private func tabButton(_ title: String, tab: SelectionTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(activeTab == tab ? .white : Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(activeTab == tab ? Color.accent : Color.bgSubtle)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Current Tab

    private var currentTabContent: some View {
        VStack(spacing: 0) {
            if selectedExercises.isEmpty {
                VStack(spacing: 8) {
                    Text("No exercises selected")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                    Text("Tap \"Add Exercise\" to get started")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.vertical, 32)
            } else {
                ForEach(Array(selectedExercises.enumerated()), id: \.element.id) { index, exercise in
                    exerciseRow(exercise: exercise, index: index)
                }
                .onMove { source, destination in
                    selectedExercises.move(fromOffsets: source, toOffset: destination)
                }
            }

            // Add Exercise row
            if selectedExercises.count < 10 {
                Button {
                    showAddExercise = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accent)
                        Text("Add Exercise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accent)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    Text("Maximum 10 exercises reached")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text("(10/10)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    private func exerciseRow(exercise: (id: UUID, name: String, category: String), index: Int) -> some View {
        HStack(spacing: 10) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)

            // Color indicator
            let palette = Color.chartPalette
            RoundedRectangle(cornerRadius: 3)
                .fill(palette[index % palette.count])
                .frame(width: 4, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if !exercise.category.isEmpty {
                    Text(exercise.category)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.bgSubtle)
                        .cornerRadius(4)
                }
            }

            Spacer()

            // Remove button
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedExercises.removeAll { $0.id == exercise.id }
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Presets Tab

    private var presetsTabContent: some View {
        VStack(spacing: 0) {
            if presets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.textTertiary)
                    Text("No saved presets")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                    Text("Save your current selection as a preset")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.vertical, 32)
            } else {
                ForEach(presets) { preset in
                    presetRow(preset)
                }
            }
        }
    }

    private func presetRow(_ preset: ChartPreset) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(preset.exerciseIds.count) exercises")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()

            Button {
                Task { await applyPreset(preset) }
            } label: {
                Text("Apply")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentSoft)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Delete button
            Button {
                presetStore.deletePreset(preset.id)
                presets = presetStore.loadPresets()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footerButtons: some View {
        VStack(spacing: 8) {
            Divider()
                .background(Color.border)

            // Primary action
            Button {
                isPresented = false
                onApply()
            } label: {
                Text("Apply to Graph")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accent)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            // Secondary actions
            HStack(spacing: 12) {
                Button {
                    guard !selectedExercises.isEmpty else { return }
                    showSavePresetAlert = true
                } label: {
                    Text("Save as Preset")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedExercises.isEmpty ? Color.textTertiary : Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.bgSubtle)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(selectedExercises.isEmpty)

                Button {
                    withAnimation { selectedExercises.removeAll() }
                } label: {
                    Text("Clear Selection")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedExercises.isEmpty ? Color.textTertiary : Color.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.bgSubtle)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(selectedExercises.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Actions

    private func addExercises(_ exerciseIds: [UUID]) async {
        for id in exerciseIds {
            // Prevent duplicates (T134)
            guard !selectedExercises.contains(where: { $0.id == id }) else { continue }
            // Enforce max 10 limit (T134)
            guard selectedExercises.count < 10 else { break }

            if let exercise = try? await exerciseService.fetchExercise(id) {
                selectedExercises.append((
                    id: exercise.id,
                    name: exercise.name,
                    category: exercise.primaryMuscle.map(ExercisePrimaryGroup.displayName(for:)) ?? ""
                ))
            }
        }
    }

    private func applyPreset(_ preset: ChartPreset) async {
        var newSelection: [(id: UUID, name: String, category: String)] = []
        for exerciseId in preset.exerciseIds {
            if let exercise = try? await exerciseService.fetchExercise(exerciseId) {
                newSelection.append((
                    id: exercise.id,
                    name: exercise.name,
                    category: exercise.primaryMuscle.map(ExercisePrimaryGroup.displayName(for:)) ?? ""
                ))
            }
        }

        if newSelection.isEmpty {
            showPresetEmptyAlert = true
        } else {
            selectedExercises = newSelection
            activeTab = .current
        }
    }
}
