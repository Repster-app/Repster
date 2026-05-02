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

    static func readOnlyFields(for trackingType: TrackingType) -> [WorkoutSetReadOnlyField] {
        trackingType.readOnlyHistoryFields
    }

    static func fieldDisplay(
        for field: WorkoutSetReadOnlyField,
        set: WorkoutSet,
        exercise: Exercise?
    ) -> WorkoutSetReadOnlyCellDisplay {
        let display = display(for: set, exercise: exercise)

        switch field {
        case .weight:
            let resolvedWeight = set.effectiveWeight ?? set.weight
            guard let resolvedWeight else { return .placeholder }
            if resolvedWeight > 0 || isBodyweightStyleExercise(exercise) {
                return WorkoutSetReadOnlyCellDisplay(text: weightLabel(for: resolvedWeight, exercise: exercise))
            }
            return .placeholder

        case .reps:
            if !display.sideRepsLabels.isEmpty {
                return WorkoutSetReadOnlyCellDisplay(text: "—", stackedLabels: display.sideRepsLabels)
            }
            return WorkoutSetReadOnlyCellDisplay(text: display.repsLabel ?? "—")

        case .distance:
            guard let distanceMeters = set.distanceMeters, distanceMeters > 0 else { return .placeholder }
            return WorkoutSetReadOnlyCellDisplay(text: formatDistance(distanceMeters))

        case .time:
            guard let durationSeconds = set.durationSeconds, durationSeconds > 0 else { return .placeholder }
            return WorkoutSetReadOnlyCellDisplay(text: UnitConversion.formatDuration(durationSeconds))

        case .rir:
            if !display.sideRIRLabels.isEmpty {
                return WorkoutSetReadOnlyCellDisplay(text: "—", stackedLabels: display.sideRIRLabels)
            }
            return WorkoutSetReadOnlyCellDisplay(
                text: display.rirLabel?.replacingOccurrences(of: "RIR ", with: "") ?? "—"
            )
        }
    }

    static func summaryDistanceLabel(for meters: Double) -> String {
        if meters >= 1000 {
            let kilometers = meters / 1000
            if kilometers >= 10 {
                return String(format: "%.1f km", kilometers)
            }
            return String(format: "%.2f km", kilometers)
        }
        if meters == meters.rounded() {
            return String(format: "%.0f m", meters)
        }
        return String(format: "%.1f m", meters)
    }

    static func summaryDurationLabel(for seconds: Int, style: WorkoutPrimaryMetricDisplayStyle) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }

        if minutes > 0 {
            if style == .detailed && remainingSeconds > 0 {
                return "\(minutes)m \(remainingSeconds)s"
            }
            return "\(minutes)m"
        }

        return "\(remainingSeconds)s"
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

enum WorkoutMetricFamily: CaseIterable, Sendable {
    case distance
    case duration
    case volume
}

enum WorkoutPrimaryMetricDisplayStyle: Sendable {
    case compact
    case detailed
}

enum WorkoutPrimaryMetric: Sendable, Equatable {
    case volume(Double)
    case distance(Double)
    case duration(Int)

    var label: String {
        switch self {
        case .volume:
            return "Volume"
        case .distance:
            return "Distance"
        case .duration:
            return "Duration"
        }
    }

    var systemImageName: String {
        switch self {
        case .volume:
            return "scalemass"
        case .distance:
            return "figure.run"
        case .duration:
            return "timer"
        }
    }

    func formattedValue(
        style: WorkoutPrimaryMetricDisplayStyle = .compact,
        unitPreference: UnitPreference = .metric
    ) -> String {
        switch self {
        case .volume(let totalVolume):
            let convertedVolume = unitPreference == .imperial ? UnitConversion.kgToLbs(totalVolume) : totalVolume
            let unitLabel = unitPreference == .imperial ? "lb" : "kg"
            if style == .compact {
                if convertedVolume >= 1000 {
                    return "\(Self.formatCompactNumber(convertedVolume)) \(unitLabel)"
                }
                return "\(Self.formatWholeNumber(convertedVolume)) \(unitLabel)"
            }
            return "\(Self.formatDetailedNumber(convertedVolume)) \(unitLabel)"

        case .distance(let meters):
            return WorkoutSetPerformanceFormatter.summaryDistanceLabel(for: meters)

        case .duration(let seconds):
            return WorkoutSetPerformanceFormatter.summaryDurationLabel(for: seconds, style: style)
        }
    }

    private static func formatCompactNumber(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        return String(format: "%.1fk", value / 1000)
    }

    private static func formatWholeNumber(_ value: Double) -> String {
        let rounded = value.rounded()
        return String(format: "%.0f", rounded)
    }

    private static func formatDetailedNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? formatWholeNumber(value)
    }
}

struct WorkoutAggregateSummary: Sendable, Equatable {
    let totalVolume: Double
    let totalDistanceMeters: Double
    let totalDurationSeconds: Int
    let volumeSetCount: Int
    let distanceSetCount: Int
    let durationSetCount: Int

    static let zero = WorkoutAggregateSummary(
        totalVolume: 0,
        totalDistanceMeters: 0,
        totalDurationSeconds: 0,
        volumeSetCount: 0,
        distanceSetCount: 0,
        durationSetCount: 0
    )

    var primaryMetric: WorkoutPrimaryMetric? {
        let prioritizedFamilies = WorkoutMetricFamily.allCases.sorted { lhs, rhs in
            let lhsCount = setCount(for: lhs)
            let rhsCount = setCount(for: rhs)
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            return priority(for: lhs) < priority(for: rhs)
        }

        for family in prioritizedFamilies where setCount(for: family) > 0 {
            if let metric = metric(for: family) {
                return metric
            }
        }

        for family in WorkoutMetricFamily.allCases {
            if let metric = metric(for: family) {
                return metric
            }
        }

        return nil
    }

    static func summarize(
        sets: [WorkoutSet],
        exercisesById: [UUID: Exercise]
    ) -> WorkoutAggregateSummary {
        summarize(
            sets: sets,
            exerciseId: { $0.exerciseId },
            exerciseLookup: { exercisesById[$0]?.trackingType },
            volumeValue: { $0.volume ?? 0 },
            distanceValue: { $0.distanceMeters ?? 0 },
            durationValue: { $0.durationSeconds ?? 0 }
        )
    }

    static func summarize(
        sets: [ChartSetData],
        exercisesById: [UUID: ChartExerciseData]
    ) -> WorkoutAggregateSummary {
        summarize(
            sets: sets,
            exerciseId: { $0.exerciseId },
            exerciseLookup: { exercisesById[$0]?.trackingType },
            volumeValue: { $0.volume ?? 0 },
            distanceValue: { $0.distanceMeters ?? 0 },
            durationValue: { $0.durationSeconds ?? 0 }
        )
    }

    private var hasVolume: Bool {
        totalVolume > 0
    }

    private var hasDistance: Bool {
        totalDistanceMeters > 0
    }

    private var hasDuration: Bool {
        totalDurationSeconds > 0
    }

    private func setCount(for family: WorkoutMetricFamily) -> Int {
        switch family {
        case .distance:
            return distanceSetCount
        case .duration:
            return durationSetCount
        case .volume:
            return volumeSetCount
        }
    }

    private func metric(for family: WorkoutMetricFamily) -> WorkoutPrimaryMetric? {
        switch family {
        case .distance:
            return hasDistance ? .distance(totalDistanceMeters) : nil
        case .duration:
            return hasDuration ? .duration(totalDurationSeconds) : nil
        case .volume:
            return hasVolume ? .volume(totalVolume) : nil
        }
    }

    private func priority(for family: WorkoutMetricFamily) -> Int {
        switch family {
        case .distance:
            return 0
        case .duration:
            return 1
        case .volume:
            return 2
        }
    }

    private static func summarize<SetType>(
        sets: [SetType],
        exerciseId: (SetType) -> UUID,
        exerciseLookup: (UUID) -> TrackingType?,
        volumeValue: (SetType) -> Double,
        distanceValue: (SetType) -> Double,
        durationValue: (SetType) -> Int
    ) -> WorkoutAggregateSummary where SetType: Sendable {
        var totalVolume: Double = 0
        var totalDistanceMeters: Double = 0
        var totalDurationSeconds: Int = 0
        var volumeSetCount = 0
        var distanceSetCount = 0
        var durationSetCount = 0

        for set in sets {
            totalVolume += volumeValue(set)
            totalDistanceMeters += distanceValue(set)
            totalDurationSeconds += max(0, durationValue(set))

            guard let trackingType = exerciseLookup(exerciseId(set)) else { continue }
            switch trackingType.summaryMetricFamily {
            case .distance:
                distanceSetCount += 1
            case .duration:
                durationSetCount += 1
            case .volume:
                volumeSetCount += 1
            }
        }

        return WorkoutAggregateSummary(
            totalVolume: totalVolume,
            totalDistanceMeters: totalDistanceMeters,
            totalDurationSeconds: totalDurationSeconds,
            volumeSetCount: volumeSetCount,
            distanceSetCount: distanceSetCount,
            durationSetCount: durationSetCount
        )
    }
}

enum WorkoutSetReadOnlyField: String, CaseIterable, Identifiable, Sendable {
    case weight
    case reps
    case distance
    case time
    case rir

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight:
            return "WEIGHT"
        case .reps:
            return "REPS"
        case .distance:
            return "DIST"
        case .time:
            return "TIME"
        case .rir:
            return "RIR"
        }
    }
}

struct WorkoutSetReadOnlyCellDisplay: Sendable, Equatable {
    let text: String
    let stackedLabels: [String]

    init(text: String, stackedLabels: [String] = []) {
        self.text = text
        self.stackedLabels = stackedLabels
    }

    static let placeholder = WorkoutSetReadOnlyCellDisplay(text: "—")
}

extension TrackingType {
    var readOnlyHistoryFields: [WorkoutSetReadOnlyField] {
        switch self {
        case .weightReps, .custom:
            return [.weight, .reps, .rir]
        case .duration:
            return [.time]
        case .durationDistance:
            return [.distance, .time]
        case .weightDistance:
            return [.weight, .distance]
        case .weightDuration:
            return [.weight, .time]
        case .weightRepsDuration:
            return [.weight, .reps, .time, .rir]
        }
    }

    var summaryMetricFamily: WorkoutMetricFamily {
        switch self {
        case .durationDistance, .weightDistance:
            return .distance
        case .duration, .weightDuration:
            return .duration
        case .weightReps, .weightRepsDuration, .custom:
            return .volume
        }
    }
}
