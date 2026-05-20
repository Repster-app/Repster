// AssignMuscleGroupsView.swift
// Post-import triage screen. Imported exercises from Strong/Hevy have no muscle group;
// this view walks the user through them one at a time with large tap targets.

import SwiftUI

struct AssignMuscleGroupsView: View {
    let exerciseService: any ExerciseServiceProtocol

    @Environment(\.dismiss) private var dismiss

    @State private var orderedExercises: [Exercise] = []
    @State private var assignments: [UUID: String] = [:]
    @State private var currentIndex: Int = 0
    @State private var hasLoaded: Bool = false

    private var total: Int { orderedExercises.count }
    private var assignedCount: Int {
        assignments.values.filter { !$0.isEmpty }.count
    }
    private var currentExercise: Exercise? {
        guard currentIndex >= 0 && currentIndex < orderedExercises.count else { return nil }
        return orderedExercises[currentIndex]
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    loadingState
                } else if total == 0 {
                    emptyState
                } else {
                    contentView
                }
            }
            .background(Color.bg)
            .navigationTitle("Muscle Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            await loadExercises()
        }
    }

    private func loadExercises() async {
        let all = (try? await exerciseService.fetchAllExercises()) ?? []
        let unassigned = all
            .filter { exercise in
                let normalized = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle)
                return normalized == nil || normalized?.isEmpty == true
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        orderedExercises = unassigned
        currentIndex = 0
        hasLoaded = true
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 0) {
            progressHeader

            if let exercise = currentExercise {
                ScrollView {
                    VStack(spacing: 24) {
                        exerciseCard(for: exercise)
                        muscleButtonGrid(for: exercise)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                }
            } else {
                allDoneView
            }

            navigationBar
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(min(currentIndex + 1, total)) of \(total)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(assignedCount) assigned")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            ProgressView(value: Double(assignedCount), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
                .tint(Color.accent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func exerciseCard(for exercise: Exercise) -> some View {
        VStack(spacing: 12) {
            Text("Which muscle group?")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            Text(exercise.name)
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func muscleButtonGrid(for exercise: Exercise) -> some View {
        let entries = ExerciseMuscleGroupCatalog.supportedEntries
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(entries, id: \.value) { entry in
                MuscleAssignmentButton(
                    title: entry.displayName,
                    color: MuscleGroupColors.color(for: entry.value),
                    isSelected: assignments[exercise.id] == entry.value,
                    action: { select(muscle: entry.value, for: exercise) }
                )
            }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.bordered)
            .disabled(currentIndex <= 0)

            Button {
                advance()
            } label: {
                Label("Skip", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.bg)
    }

    private var allDoneView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.success)
            Text("All set!")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
            Text("You assigned a muscle group to every imported exercise.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Nothing to assign")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func select(muscle: String, for exercise: Exercise) {
        let previous = assignments[exercise.id]
        assignments[exercise.id] = muscle
        exercise.primaryMuscle = muscle

        Task {
            do {
                try await exerciseService.updateExercise(
                    exercise,
                    originalTrackingType: exercise.trackingType
                )
            } catch {
                await MainActor.run {
                    assignments[exercise.id] = previous
                    exercise.primaryMuscle = previous
                }
            }
        }

        advance()
    }

    private func advance() {
        guard currentIndex < total else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentIndex += 1
        }
    }

    private func goBack() {
        guard currentIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentIndex -= 1
        }
    }
}

// MARK: - Button

private struct MuscleAssignmentButton: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Text(title)
                    .font(.body.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? .white : Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isSelected ? Color.accent : Color.bgCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.clear : Color.textTertiary.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
