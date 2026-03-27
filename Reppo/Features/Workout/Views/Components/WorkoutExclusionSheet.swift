import SwiftUI

struct WorkoutExclusionSheet: View {
    let workout: Workout
    let exercises: [Exercise]
    let onSave: @Sendable (Bool, Set<UUID>) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var excludeWorkout: Bool
    @State private var excludedExerciseIds: Set<UUID>
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        workout: Workout,
        exercises: [Exercise],
        onSave: @escaping @Sendable (Bool, Set<UUID>) async throws -> Void
    ) {
        self.workout = workout
        self.exercises = exercises
        self.onSave = onSave
        _excludeWorkout = State(initialValue: workout.excludesEntireWorkoutFromPRsAndSuggestions)
        _excludedExerciseIds = State(initialValue: workout.excludedExerciseIdsForPRsAndSuggestions)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Exclude entire workout from PRs & Smart Suggestions", isOn: $excludeWorkout)
                        .foregroundStyle(Color.textPrimary)
                } footer: {
                    Text("Use this when equipment or plate loading differs, such as hotel or friend's gyms.")
                        .foregroundStyle(Color.textTertiary)
                }

                Section {
                    if exercises.isEmpty {
                        Text("Add exercises to use per-exercise exclusions.")
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        ForEach(exercises, id: \.id) { exercise in
                            Toggle(exercise.name, isOn: binding(for: exercise.id))
                                .foregroundStyle(Color.textPrimary)
                            }
                    }
                } header: {
                    Text("Exercises in This Workout")
                } footer: {
                    Text("Whole-workout exclusion overrides the list below, but your selections are kept.")
                        .foregroundStyle(Color.textTertiary)
                }
                .disabled(excludeWorkout)
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Workout Exclusions")
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
        .presentationDetents([.medium, .large])
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
            try await onSave(excludeWorkout, excludedExerciseIds)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
