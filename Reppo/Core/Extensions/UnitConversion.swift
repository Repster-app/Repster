import Foundation

enum UnitConversion {
    // MARK: - Weight

    static func kgToLbs(_ kg: Double) -> Double {
        kg * 2.20462
    }

    static func lbsToKg(_ lbs: Double) -> Double {
        lbs / 2.20462
    }

    static func toGrams(_ kg: Double) -> Int {
        Int(round(kg * 1000))
    }

    // MARK: - Distance

    static func metersToFeet(_ meters: Double) -> Double {
        meters * 3.28084
    }

    static func feetToMeters(_ feet: Double) -> Double {
        feet / 3.28084
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

    /// Format a weight value for display, using the user's locale decimal separator.
    /// Drops trailing ".0" for whole numbers.
    static func formatWeight(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
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
