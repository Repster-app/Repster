import Foundation

struct WorkoutSetDisplayText: Sendable {
    let performanceLabel: String?
    let repsLabel: String?
    let rirLabel: String?
    let sideRepsLabels: [String]
    let sideRIRLabels: [String]
    let isPerSide: Bool

    var perSideLabel: String? {
        isPerSide ? "Per side" : nil
    }
}

enum WorkoutSetPerformanceFormatter {
    static func display(for set: WorkoutSet, exercise: Exercise?) -> WorkoutSetDisplayText {
        display(
            weight: set.weight,
            reps: set.reps,
            leftReps: set.leftReps,
            rightReps: set.rightReps,
            durationSeconds: set.durationSeconds,
            distanceMeters: set.distanceMeters,
            rir: set.rir,
            leftRIR: set.leftRIR,
            rightRIR: set.rightRIR,
            isBodyweightStyle: exercise?.isBodyweightStyleExercise == true
        )
    }

    static func display(for set: ChartSetData, exercise: ChartExerciseData?) -> WorkoutSetDisplayText {
        display(
            weight: set.weight,
            reps: set.reps,
            leftReps: set.leftReps,
            rightReps: set.rightReps,
            durationSeconds: set.durationSeconds,
            distanceMeters: set.distanceMeters,
            rir: nil,
            leftRIR: nil,
            rightRIR: nil,
            isBodyweightStyle: exercise?.isBodyweightStyleExercise == true
        )
    }

    static func performanceLabel(for set: WorkoutSet, exercise: Exercise?) -> String? {
        display(for: set, exercise: exercise).performanceLabel
    }

    static func performanceLabel(for set: ChartSetData, exercise: ChartExerciseData?) -> String? {
        display(for: set, exercise: exercise).performanceLabel
    }

    static func repsLabel(for set: WorkoutSet) -> String? {
        display(for: set, exercise: nil).repsLabel
    }

    static func rirLabel(for set: WorkoutSet) -> String? {
        display(for: set, exercise: nil).rirLabel
    }

    static func weightLabel(for weight: Double, exercise: Exercise?) -> String {
        weightLabel(for: weight, isBodyweightStyle: exercise?.isBodyweightStyleExercise == true)
    }

    static func weightLabel(for weight: Double, exercise: ChartExerciseData?) -> String {
        weightLabel(for: weight, isBodyweightStyle: exercise?.isBodyweightStyleExercise == true)
    }

    static func isBodyweightStyleExercise(_ exercise: Exercise?) -> Bool {
        exercise?.isBodyweightStyleExercise == true
    }

    static func isBodyweightStyleExercise(_ exercise: ChartExerciseData?) -> Bool {
        exercise?.isBodyweightStyleExercise == true
    }

    private static func display(
        weight: Double?,
        reps: Int?,
        leftReps: Int?,
        rightReps: Int?,
        durationSeconds: Int?,
        distanceMeters: Double?,
        rir: Double?,
        leftRIR: Double?,
        rightRIR: Double?,
        isBodyweightStyle: Bool
    ) -> WorkoutSetDisplayText {
        let isPerSide = leftReps != nil || rightReps != nil || leftRIR != nil || rightRIR != nil
        let repsLabel = repsLabel(reps: reps, leftReps: leftReps, rightReps: rightReps)
        let rirLabel = rirLabel(rir: rir, leftRIR: leftRIR, rightRIR: rightRIR)
        let performanceLabel = performanceLabel(
            weight: weight,
            repsLabel: repsLabel,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            isBodyweightStyle: isBodyweightStyle
        )

        return WorkoutSetDisplayText(
            performanceLabel: performanceLabel,
            repsLabel: repsLabel,
            rirLabel: rirLabel,
            sideRepsLabels: sideRepsLabels(leftReps: leftReps, rightReps: rightReps),
            sideRIRLabels: sideRIRLabels(leftRIR: leftRIR, rightRIR: rightRIR),
            isPerSide: isPerSide
        )
    }

    private static func performanceLabel(
        weight: Double?,
        repsLabel: String?,
        durationSeconds: Int?,
        distanceMeters: Double?,
        isBodyweightStyle: Bool
    ) -> String? {
        if let repsLabel, let weight {
            return "\(weightLabel(for: weight, isBodyweightStyle: isBodyweightStyle)) × \(repsLabel)"
        }

        if let repsLabel {
            return repsLabel
        }

        if let weight, weight > 0, let distanceMeters, distanceMeters > 0 {
            return "\(formatWeight(weight)) • \(formatDistance(distanceMeters))"
        }

        if let durationSeconds, durationSeconds > 0, let distanceMeters, distanceMeters > 0 {
            return "\(UnitConversion.formatDuration(durationSeconds)) • \(formatDistance(distanceMeters))"
        }

        if let durationSeconds, durationSeconds > 0 {
            return UnitConversion.formatDuration(durationSeconds)
        }

        if let distanceMeters, distanceMeters > 0 {
            return formatDistance(distanceMeters)
        }

        return nil
    }

    private static func repsLabel(reps: Int?, leftReps: Int?, rightReps: Int?) -> String? {
        switch (leftReps, rightReps) {
        case let (.some(left), .some(right)):
            return "L: \(left)  R: \(right)"
        case let (.some(left), .none):
            return "L: \(left)"
        case let (.none, .some(right)):
            return "R: \(right)"
        case (.none, .none):
            break
        }

        if let reps, reps > 0 {
            return "\(reps)"
        }

        return nil
    }

    private static func rirLabel(rir: Double?, leftRIR: Double?, rightRIR: Double?) -> String? {
        let sideLabels = fullSideRIRLabels(leftRIR: leftRIR, rightRIR: rightRIR)
        if !sideLabels.isEmpty {
            return sideLabels.joined(separator: " • ")
        }

        guard let rir else { return nil }
        return "RIR \(displayRIR(rir))"
    }

    private static func sideRepsLabels(leftReps: Int?, rightReps: Int?) -> [String] {
        var labels: [String] = []

        if let leftReps {
            labels.append("L\(leftReps)")
        }
        if let rightReps {
            labels.append("R\(rightReps)")
        }

        return labels
    }

    private static func sideRIRLabels(leftRIR: Double?, rightRIR: Double?) -> [String] {
        var labels: [String] = []

        if let leftRIR {
            labels.append("L\(displayRIR(leftRIR))")
        }
        if let rightRIR {
            labels.append("R\(displayRIR(rightRIR))")
        }

        return labels
    }

    private static func fullSideRIRLabels(leftRIR: Double?, rightRIR: Double?) -> [String] {
        var labels: [String] = []

        if let leftRIR {
            labels.append("L RIR \(displayRIR(leftRIR))")
        }
        if let rightRIR {
            labels.append("R RIR \(displayRIR(rightRIR))")
        }

        return labels
    }

    private static func weightLabel(for weight: Double, isBodyweightStyle: Bool) -> String {
        if weight <= 0, isBodyweightStyle {
            return "BW"
        }

        return "\(formatWeight(weight)) kg"
    }

    private static func displayRIR(_ value: Double) -> String {
        value >= 5 ? "5+" : "\(Int(value))"
    }

    private static func formatWeight(_ weight: Double) -> String {
        UnitConversion.formatWeight(weight)
    }

    private static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        if meters == meters.rounded() {
            return String(format: "%.0f m", meters)
        }
        return String(format: "%.1f m", meters)
    }
}
