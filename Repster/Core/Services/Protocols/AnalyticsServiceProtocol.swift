import Foundation

protocol AnalyticsServiceProtocol {
    var isCollectionEnabled: Bool { get }

    func configure()
    func setCollectionEnabled(_ enabled: Bool)
    func screen(_ screen: AnalyticsScreen, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue])
    func track(_ event: AnalyticsEvent, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue])
}

extension AnalyticsServiceProtocol {
    func screen(_ screen: AnalyticsScreen) {
        self.screen(screen, properties: [:])
    }

    func track(_ event: AnalyticsEvent) {
        self.track(event, properties: [:])
    }
}

enum AnalyticsScreen: String, CaseIterable {
    case home = "Home"
    case calendar = "Calendar"
    case charts = "Charts"
    case settings = "Settings"
    case activeWorkout = "Active Workout"
    case workoutSummary = "Workout Summary"
    case paywall = "Paywall"
}

enum AnalyticsEvent: String, CaseIterable {
    case workoutStarted = "workout started"
    case workoutCompleted = "workout completed"
    case workoutDiscarded = "workout discarded"
    case importCompleted = "import completed"
    case backupExported = "backup exported"
    case paywallShown = "paywall shown"
    case paywallDismissed = "paywall dismissed"
    case purchaseStarted = "purchase started"
    case purchaseCompleted = "purchase completed"
    case purchaseCancelled = "purchase cancelled"
    case restorePurchasesTapped = "restore purchases tapped"
}

enum AnalyticsPropertyKey: String, CaseIterable {
    case source
    case sourceType = "source_type"
    case templateUsed = "template_used"
    case copiedPrevious = "copied_previous"
    case countTowardProgression = "count_toward_progression"
    case durationBucket = "duration_bucket"
    case setCountBucket = "set_count_bucket"
    case exerciseCountBucket = "exercise_count_bucket"
    case workoutCountBucket = "workout_count_bucket"
    case rowCountBucket = "row_count_bucket"
    case perceivedEffortEntered = "perceived_effort_entered"
    case notesEntered = "notes_entered"
    case excludedFromProgression = "excluded_from_progression"
    case result
    case unitSystem = "unit_system"
    case errorType = "error_type"
}

enum AnalyticsPropertyValue: Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    var rawValue: Any {
        switch self {
        case .string(let value):
            return value
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        }
    }
}

enum AnalyticsBuckets {
    static func duration(seconds: TimeInterval) -> String {
        let minutes = max(0, seconds) / 60
        return minutes < 30 ? "under_30m" : "30m_or_more"
    }

    static func count(_ value: Int) -> String {
        switch max(0, value) {
        case 0:
            return "0"
        case 1:
            return "1"
        case 2...3:
            return "2-3"
        case 4...6:
            return "4-6"
        case 7...10:
            return "7-10"
        default:
            return "11+"
        }
    }
}
