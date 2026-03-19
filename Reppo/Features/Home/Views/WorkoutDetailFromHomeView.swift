// WorkoutDetailFromHomeView.swift
// Lightweight wrapper that loads WorkoutDetail on demand for Recent card navigation.
// Reuses CalendarWorkoutDetailView for rendering.
// Includes toolbar menu for delete, edit (placeholder), save as template (placeholder).
// Spec: 013-home-screen, WP04 T020

import SwiftUI

struct WorkoutDetailFromHomeView: View {
    let workoutId: UUID
    let workoutService: any WorkoutServiceProtocol
    let setService: any SetServiceProtocol
    let exerciseService: any ExerciseServiceProtocol
    let statsService: any StatsServiceProtocol

    @State private var workoutDetails: [WorkoutDetail] = []
    @State private var isLoading = true
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showEditWorkout = false
    @State private var selectedExerciseId: UUID?
    @State private var saveAsTemplateController = SaveWorkoutAsTemplateController()
    @State private var templateFeedback: TemplateSaveFeedback? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(ServiceContainer.self) private var services

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                CalendarWorkoutDetailView(
                    workoutDetails: workoutDetails,
                    selectedDate: workoutDetails.first?.workout.date ?? Date(),
                    onSaveAsTemplate: nil,
                    onExerciseTapped: { exerciseId in
                        selectedExerciseId = exerciseId
                    }
                )
            }
        }
        .background(Color.bg)
        .navigationTitle(workoutDetails.first?.workout.displayTitle ?? "Workout Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Edit Workout
                    Button {
                        showEditWorkout = true
                    } label: {
                        Label("Edit Workout", systemImage: "pencil")
                    }

                    Button {
                        guard let workout = workoutDetails.first?.workout else { return }
                        saveAsTemplateController.begin(defaultName: workout.displayTitle)
                    } label: {
                        Label("Save as Template", systemImage: "doc.on.doc")
                    }

                    Divider()

                    // Delete Workout — functional
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
            }
        }
        .confirmationDialog(
            "Delete Workout",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteWorkout() }
            }
        } message: {
            Text("This will permanently delete this workout and all its sets. PRs and stats will be recalculated. This cannot be undone.")
        }
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.accent)
                        Text("Deleting…")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(24)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .task {
            await loadDetail()
        }
        .saveWorkoutAsTemplatePrompt(
            controller: saveAsTemplateController,
            workoutId: workoutDetails.first?.workout.id,
            onSaved: { savedName in
                templateFeedback = TemplateSaveFeedback(
                    title: "Template Saved",
                    message: "\"\(savedName)\" was created from this workout."
                )
            },
            onError: { error in
                templateFeedback = TemplateSaveFeedback(
                    title: "Save Failed",
                    message: error.localizedDescription
                )
            }
        )
        .alert(item: $templateFeedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .fullScreenCover(isPresented: $showEditWorkout) {
            EditWorkoutView(workoutId: workoutId, services: services)
        }
        .onChange(of: showEditWorkout) { _, isShowing in
            if !isShowing {
                Task {
                    await loadDetail()
                }
            }
        }
        .navigationDestination(item: $selectedExerciseId) { exerciseId in
            ExerciseDetailView(exerciseId: exerciseId, services: services)
        }
    }

    // MARK: - Delete

    private func deleteWorkout() async {
        isDeleting = true
        do {
            try await workoutService.deleteWorkout(workoutId)
            isDeleting = false
            dismiss()
        } catch {
            isDeleting = false
            print("[WorkoutDetailFromHomeView] Delete failed: \(error)")
        }
    }

    // MARK: - Load

    private func loadDetail() async {
        do {
            guard let workout = try await workoutService.fetchWorkout(workoutId) else {
                isLoading = false
                return
            }

            let sets = try await setService.fetchSets(for: workout.id)
            var exerciseSetMap: [UUID: [WorkoutSet]] = [:]
            for set in sets {
                exerciseSetMap[set.exerciseId, default: []].append(set)
            }

            var exerciseGroups: [ExerciseGroup] = []
            for (exerciseId, exerciseSets) in exerciseSetMap {
                let exercise = try await exerciseService.fetchExercise(exerciseId)
                guard let exercise else { continue }
                let sorted = exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise }
                let stats = try? await statsService.fetchStats(for: exerciseId)
                exerciseGroups.append(ExerciseGroup(exercise: exercise, sets: sorted, stats: stats))
            }

            exerciseGroups.sort { lhs, rhs in
                let l = lhs.sets.first?.orderInWorkout ?? Int.max
                let r = rhs.sets.first?.orderInWorkout ?? Int.max
                return l < r
            }

            let completedSets = sets.filter(\.hasData)
            let totalVolume = completedSets.compactMap(\.volume).reduce(0, +)

            workoutDetails = [WorkoutDetail(
                workout: workout,
                exerciseGroups: exerciseGroups,
                totalVolume: totalVolume,
                exerciseCount: Set(sets.map(\.exerciseId)).count,
                setCount: completedSets.count
            )]
            isLoading = false
        } catch {
            print("[WorkoutDetailFromHomeView] Failed: \(error)")
            isLoading = false
        }
    }
}
