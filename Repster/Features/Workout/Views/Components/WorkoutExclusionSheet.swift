import SwiftUI

struct WorkoutProgressionSheet: View {
    /// Snapshot, not the live model. The sheet only ever reads the two exclusion fields for its
    /// initial toggle state, and it is presented from Calendar and Home where no live `Workout`
    /// exists — handing one to a main-actor view is the EXC_BAD_ACCESS class this app already
    /// fought once.
    let workout: WorkoutSnapshot
    let exercises: [ChartExerciseData]
    let showsExerciseOverrides: Bool
    let onSave: @Sendable (Bool, Set<UUID>) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var excludeWorkout: Bool
    @State private var excludedExerciseIds: Set<UUID>
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        workout: WorkoutSnapshot,
        exercises: [ChartExerciseData],
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
        // Naming what exclusion does *not* touch matters: PRs, suggestions and insights honour
        // this flag, but charts and volume totals ignore it. Without this sentence the setting
        // reads as "erase this session", which would put people off using it correctly.
        let scope = "Excluded sessions still appear in your history, charts and volume totals — "
            + "they just don't set PRs or feed future Smart Suggestions."

        if showsExerciseOverrides {
            return "Use this for travel, hotel, or mismatched-equipment sessions. Live Smart "
                + "Suggestions still work during the workout. \(scope)"
        }

        return "Historic edits only let you decide whether the full workout should count. \(scope)"
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
