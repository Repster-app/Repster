import SwiftUI

struct WorkoutProgressionSheet: View {
    let workout: Workout
    let exercises: [Exercise]
    let showsExerciseOverrides: Bool
    let onSave: @Sendable (Bool, Set<UUID>) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var excludeWorkout: Bool
    @State private var excludedExerciseIds: Set<UUID>
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        workout: Workout,
        exercises: [Exercise],
        showsExerciseOverrides: Bool = true,
        onSave: @escaping @Sendable (Bool, Set<UUID>) async throws -> Void
    ) {
        self.workout = workout
        self.exercises = exercises
        self.showsExerciseOverrides = showsExerciseOverrides
        self.onSave = onSave
        _excludeWorkout = State(initialValue: workout.excludesEntireWorkoutFromProgressionHistory)
        _excludedExerciseIds = State(initialValue: workout.excludedExerciseIdsForProgressionHistory)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Exclude entire workout from PRs & future suggestions", isOn: $excludeWorkout)
                        .foregroundStyle(Color.textPrimary)
                } footer: {
                    Text(wholeWorkoutFooterCopy)
                        .foregroundStyle(Color.textTertiary)
                }

                if showsExerciseOverrides {
                    Section {
                        if exercises.isEmpty {
                            Text("Add exercises to use per-exercise progression exclusions.")
                                .foregroundStyle(Color.textTertiary)
                        } else {
                            ForEach(exercises, id: \.id) { exercise in
                                Toggle(exercise.name, isOn: binding(for: exercise.id))
                                    .foregroundStyle(Color.textPrimary)
                                }
                        }
                    } header: {
                        Text("Exclude Exercises from Progression")
                    } footer: {
                        Text("Whole-workout exclusion overrides the list below, but your selections are kept for later.")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .disabled(excludeWorkout)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents(showsExerciseOverrides ? [.medium, .large] : [.medium])
        .alert("Unable to Save", isPresented: errorIsPresented) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private var wholeWorkoutFooterCopy: String {
        if showsExerciseOverrides {
            return "Use this for travel, hotel, or mismatched-equipment sessions. Live Smart Suggestions still work during the workout."
        }

        return "Historic edits only let you decide whether the full workout should count toward PRs and future Smart Suggestions."
    }

    private func binding(for exerciseId: UUID) -> Binding<Bool> {
        Binding(
            get: { excludedExerciseIds.contains(exerciseId) },
            set: { isExcluded in
                if isExcluded {
                    excludedExerciseIds.insert(exerciseId)
                } else {
                    excludedExerciseIds.remove(exerciseId)
                }
            }
        )
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let effectiveExcludedExerciseIds = showsExerciseOverrides ? excludedExerciseIds : []
            try await onSave(excludeWorkout, effectiveExcludedExerciseIds)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
