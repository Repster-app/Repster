import Foundation

enum UnitPreference: String, Codable, CaseIterable {
    case metric
    case imperial

    /// What this device's region implies. Used only to preselect the onboarding choice —
    /// the user still picks, and can change it in Settings afterwards.
    ///
    /// `Locale.MeasurementSystem` has three cases: the UK's `.uk` is imperial for road
    /// distances but metric for weight, which is the only thing Repster measures. So only
    /// `.us` maps to pounds.
    static func fromCurrentLocale(_ locale: Locale = .current) -> UnitPreference {
        if #available(iOS 16.0, *) {
            return locale.measurementSystem == .us ? .imperial : .metric
        }
        return locale.usesMetricSystem ? .metric : .imperial
    }
}
