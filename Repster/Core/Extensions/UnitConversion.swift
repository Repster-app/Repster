import Foundation

enum UnitConversion {
    typealias WeightIncrementOption = (display: Double, storedKg: Double)

    static let poundsPerKilogram = 2.20462
    static let feetPerMeter = 3.28084
    static let metersPerMile = 1609.344

    // MARK: - Weight

    static func kgToLbs(_ kg: Double) -> Double {
        kg * poundsPerKilogram
    }

    static func lbsToKg(_ lbs: Double) -> Double {
        lbs / poundsPerKilogram
    }

    static func toGrams(_ kg: Double) -> Int {
        Int(round(kg * 1000))
    }

    // MARK: - Distance

    static func metersToFeet(_ meters: Double) -> Double {
        meters * feetPerMeter
    }

    static func feetToMeters(_ feet: Double) -> Double {
        feet / feetPerMeter
    }

    static func metersToMiles(_ meters: Double) -> Double {
        meters / metersPerMile
    }

    static func milesToMeters(_ miles: Double) -> Double {
        miles * metersPerMile
    }

    // MARK: - Decimal Input Parsing

    /// Parse a decimal string that may use comma or period as decimal separator.
    /// Handles locales where "52,5" means 52.5.
    static func parseDecimal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Replace comma with period for consistent parsing
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    /// Format a display weight with stable decimal precision and whole-number cleanup.
    static func formatWeight(_ value: Double) -> String {
        if isEffectivelyWhole(value) {
            return String(format: "%.0f", value)
        }
        var formatted = String(format: "%.2f", value)
        while formatted.last == "0" {
            formatted.removeLast()
        }
        if formatted.last == "." {
            formatted.removeLast()
        }
        return formatted
    }

    static func displayedWeight(_ kg: Double, unitPreference: UnitPreference) -> Double {
        unitPreference == .imperial ? kgToLbs(kg) : kg
    }

    static func storedWeight(fromDisplayed value: Double, unitPreference: UnitPreference) -> Double {
        unitPreference == .imperial ? lbsToKg(value) : value
    }

    static func parseDisplayedWeight(_ text: String, unitPreference: UnitPreference) -> Double? {
        parseDecimal(text).map { storedWeight(fromDisplayed: $0, unitPreference: unitPreference) }
    }

    static func formatDisplayedWeight(_ kg: Double, unitPreference: UnitPreference) -> String {
        formatWeight(displayedWeight(kg, unitPreference: unitPreference))
    }

    static func weightUnitLabel(for unitPreference: UnitPreference) -> String {
        unitPreference == .imperial ? "lb" : "kg"
    }

    static func formatWeightLabel(_ kg: Double, unitPreference: UnitPreference) -> String {
        "\(formatDisplayedWeight(kg, unitPreference: unitPreference)) \(weightUnitLabel(for: unitPreference))"
    }

    static func displayedWeightIncrement(_ kgIncrement: Double, unitPreference: UnitPreference) -> Double {
        displayedWeight(kgIncrement, unitPreference: unitPreference)
    }

    static func storedWeightIncrement(fromDisplayed increment: Double, unitPreference: UnitPreference) -> Double {
        storedWeight(fromDisplayed: increment, unitPreference: unitPreference)
    }

    static func displayWeightIncrementOptions(for unitPreference: UnitPreference) -> [WeightIncrementOption] {
        switch unitPreference {
        case .metric:
            return [0.5, 1.0, 1.25, 2.0, 2.5, 5.0, 10.0].map { ($0, $0) }
        case .imperial:
            return [1.0, 2.5, 5.0, 10.0, 15.0, 20.0, 25.0].map {
                ($0, lbsToKg($0))
            }
        }
    }

    static func exerciseWeightIncrementOptions(for unitPreference: UnitPreference) -> [WeightIncrementOption] {
        switch unitPreference {
        case .metric:
            return [1.0, 1.25, 2.0, 2.5, 5.0, 10.0, 20.0].map { ($0, $0) }
        case .imperial:
            return [1.0, 2.0, 2.5, 5.0, 10.0, 15.0, 20.0, 25.0].map {
                ($0, lbsToKg($0))
            }
        }
    }

    static func defaultStoredWeightIncrement(for unitPreference: UnitPreference) -> Double {
        switch unitPreference {
        case .metric:
            return 2.5
        case .imperial:
            return lbsToKg(5)
        }
    }

    static func normalizedWeightIncrementOption(
        storedKg: Double,
        unitPreference: UnitPreference,
        options: [WeightIncrementOption]
    ) -> WeightIncrementOption {
        let displayed = displayedWeightIncrement(storedKg, unitPreference: unitPreference)

        guard storedKg.isFinite, storedKg > 0 else {
            return (displayed, storedKg)
        }

        guard let nearest = options.min(by: { lhs, rhs in
            let lhsDistance = abs(lhs.display - displayed)
            let rhsDistance = abs(rhs.display - displayed)
            if abs(lhsDistance - rhsDistance) < 0.000_001 {
                return lhs.display < rhs.display
            }
            return lhsDistance < rhsDistance
        }) else {
            return (displayed, storedKg)
        }

        return nearest
    }

    static func formatWeightIncrementLabel(
        storedKg: Double?,
        unitPreference: UnitPreference,
        options: [WeightIncrementOption]
    ) -> String {
        guard let storedKg else { return "Not Set" }
        let option = normalizedWeightIncrementOption(
            storedKg: storedKg,
            unitPreference: unitPreference,
            options: options
        )
        return formatWeightIncrementLabel(displayValue: option.display, unitPreference: unitPreference)
    }

    static func formatWeightIncrementLabel(displayValue: Double, unitPreference: UnitPreference) -> String {
        "\(formatWeight(displayValue)) \(weightUnitLabel(for: unitPreference))"
    }

    static func resolvedWeightIncrementOption(
        exerciseIncrement: Double?,
        defaultIncrement: Double?,
        unitPreference: UnitPreference
    ) -> WeightIncrementOption {
        if let exerciseIncrement {
            return normalizedWeightIncrementOption(
                storedKg: exerciseIncrement,
                unitPreference: unitPreference,
                options: exerciseWeightIncrementOptions(for: unitPreference)
            )
        }

        let fallback = defaultIncrement ?? defaultStoredWeightIncrement(for: unitPreference)
        return normalizedWeightIncrementOption(
            storedKg: fallback,
            unitPreference: unitPreference,
            options: displayWeightIncrementOptions(for: unitPreference)
        )
    }

    static func resolvedStoredWeightIncrement(
        exerciseIncrement: Double?,
        defaultIncrement: Double?,
        unitPreference: UnitPreference
    ) -> Double {
        resolvedWeightIncrementOption(
            exerciseIncrement: exerciseIncrement,
            defaultIncrement: defaultIncrement,
            unitPreference: unitPreference
        ).storedKg
    }

    static func formatDistanceLabel(_ meters: Double, unitPreference: UnitPreference) -> String {
        switch unitPreference {
        case .metric:
            if meters >= 1000 {
                return String(format: "%.2f km", meters / 1000)
            }
            if isEffectivelyWhole(meters) {
                return String(format: "%.0f m", meters)
            }
            return String(format: "%.1f m", meters)
        case .imperial:
            if meters >= metersPerMile {
                return String(format: "%.2f mi", metersToMiles(meters))
            }
            return String(format: "%.0f ft", metersToFeet(meters).rounded())
        }
    }

    static func displayedChartDistance(_ meters: Double, unitPreference: UnitPreference) -> Double {
        switch unitPreference {
        case .metric:
            return meters / 1000
        case .imperial:
            return metersToMiles(meters)
        }
    }

    static func chartDistanceUnitLabel(for unitPreference: UnitPreference) -> String {
        unitPreference == .imperial ? "mi" : "km"
    }

    static func isEffectivelyWhole(_ value: Double, epsilon: Double = 0.005) -> Bool {
        abs(value - value.rounded()) < epsilon
    }

    // MARK: - Duration Formatting

    static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 && remainingSeconds > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(remainingSeconds)s"
        }
    }
}
