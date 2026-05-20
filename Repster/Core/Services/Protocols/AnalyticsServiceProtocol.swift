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

// MARK: - AnalyticsEvents helpers
//
// Single entry point per event so property names stay in sync across call sites.

enum PaywallSource: String {
    case paywall
    case settings
    case membershipSettings = "membership_settings"
}

enum WorkoutStartSource: String {
    case empty
    case exerciseList = "exercise_list"
    case template
    case copyPrevious = "copy_previous"
}

/// Tiny UserDefaults-backed stash so that `workout started` context (which is
/// known at the call site that starts the workout) can be re-emitted with
/// `workout completed` / `workout discarded` from the ViewModel that owns the
/// active session.
enum WorkoutStartContextStore {
    private static let sourceKey = "activeWorkoutStartSource"
    private static let templateUsedKey = "activeWorkoutStartTemplateUsed"

    static func remember(
        source: WorkoutStartSource,
        templateUsed: Bool,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(source.rawValue, forKey: sourceKey)
        userDefaults.set(templateUsed, forKey: templateUsedKey)
    }

    static func recall(
        userDefaults: UserDefaults = .standard
    ) -> (source: WorkoutStartSource?, templateUsed: Bool?) {
        let sourceRaw = userDefaults.string(forKey: sourceKey)
        let source = sourceRaw.flatMap { WorkoutStartSource(rawValue: $0) }
        let templateUsed = userDefaults.object(forKey: templateUsedKey) as? Bool
        return (source, templateUsed)
    }

    static func clear(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: sourceKey)
        userDefaults.removeObject(forKey: templateUsedKey)
    }
}

extension AnalyticsServiceProtocol {

    // Paywall + purchase

    func paywallShown(source: PaywallSource) {
        screen(.paywall, properties: [.source: .string(source.rawValue)])
        track(.paywallShown, properties: [.source: .string(source.rawValue)])
    }

    func paywallDismissed(source: PaywallSource) {
        track(.paywallDismissed, properties: [.source: .string(source.rawValue)])
    }

    func purchaseStarted(source: PaywallSource) {
        track(.purchaseStarted, properties: [.source: .string(source.rawValue)])
    }

    func purchaseCompleted(source: PaywallSource) {
        track(.purchaseCompleted, properties: [.source: .string(source.rawValue)])
    }

    func purchaseCancelled(source: PaywallSource) {
        track(.purchaseCancelled, properties: [.source: .string(source.rawValue)])
    }

    func restorePurchasesTapped(source: PaywallSource) {
        track(.restorePurchasesTapped, properties: [.source: .string(source.rawValue)])
    }

    // Workout

    func workoutStarted(
        source: WorkoutStartSource,
        templateUsed: Bool,
        copiedPrevious: Bool,
        countTowardProgression: Bool
    ) {
        track(.workoutStarted, properties: [
            .source: .string(source.rawValue),
            .templateUsed: .bool(templateUsed),
            .copiedPrevious: .bool(copiedPrevious),
            .countTowardProgression: .bool(countTowardProgression)
        ])
    }

    func workoutCompleted(
        durationSeconds: TimeInterval,
        completedSetCount: Int,
        exerciseCount: Int,
        totalReps: Int,
        prsHit: Int,
        date: Date,
        source: WorkoutStartSource?,
        templateUsed: Bool?,
        unitSystem: String?,
        perceivedEffortEntered: Bool,
        notesEntered: Bool,
        excludedFromProgression: Bool
    ) {
        var properties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [
            .durationBucket: .string(AnalyticsBuckets.duration(seconds: durationSeconds)),
            .setCountBucket: .string(AnalyticsBuckets.count(completedSetCount)),
            .exerciseCountBucket: .string(AnalyticsBuckets.count(exerciseCount)),
            .totalRepsBucket: .string(AnalyticsBuckets.wideCount(totalReps)),
            .prsHit: .int(prsHit),
            .timeOfDay: .string(AnalyticsBuckets.timeOfDay(date)),
            .dayOfWeek: .string(AnalyticsBuckets.dayOfWeek(date)),
            .perceivedEffortEntered: .bool(perceivedEffortEntered),
            .notesEntered: .bool(notesEntered),
            .excludedFromProgression: .bool(excludedFromProgression)
        ]
        if let source {
            properties[.source] = .string(source.rawValue)
        }
        if let templateUsed {
            properties[.templateUsed] = .bool(templateUsed)
        }
        if let unitSystem {
            properties[.unitSystem] = .string(unitSystem)
        }
        track(.workoutCompleted, properties: properties)
    }

    func workoutDiscarded(
        durationSeconds: TimeInterval,
        setCount: Int,
        date: Date,
        source: WorkoutStartSource?,
        templateUsed: Bool?
    ) {
        var properties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [
            .durationBucket: .string(AnalyticsBuckets.duration(seconds: durationSeconds)),
            .setCountBucket: .string(AnalyticsBuckets.count(setCount)),
            .timeOfDay: .string(AnalyticsBuckets.timeOfDay(date)),
            .dayOfWeek: .string(AnalyticsBuckets.dayOfWeek(date))
        ]
        if let source {
            properties[.source] = .string(source.rawValue)
        }
        if let templateUsed {
            properties[.templateUsed] = .bool(templateUsed)
        }
        track(.workoutDiscarded, properties: properties)
    }

    // Import / backup

    func importStarted(sourceType: String, unitSystem: String?) {
        var properties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [
            .sourceType: .string(sourceType)
        ]
        if let unitSystem {
            properties[.unitSystem] = .string(unitSystem)
        }
        track(.importStarted, properties: properties)
    }

    func backupImported() {
        track(.backupImported)
    }

    func backupExported() {
        track(.backupExported)
    }

    // Settings

    func unitSystemToggled(unitSystem: String) {
        track(.unitSystemToggled, properties: [
            .unitSystem: .string(unitSystem)
        ])
    }

    /// Fire BEFORE flipping the collection preference when disabling, otherwise
    /// the event is dropped by the opt-out gate.
    func analyticsOptOutToggled(enabled: Bool) {
        track(.analyticsOptOutToggled, properties: [
            .enabled: .bool(enabled)
        ])
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
    case importStarted = "import started"
    case importCompleted = "import completed"
    case backupExported = "backup exported"
    case backupImported = "backup imported"
    case paywallShown = "paywall shown"
    case paywallDismissed = "paywall dismissed"
    case purchaseStarted = "purchase started"
    case purchaseCompleted = "purchase completed"
    case purchaseCancelled = "purchase cancelled"
    case restorePurchasesTapped = "restore purchases tapped"
    case unitSystemToggled = "unit system toggled"
    case analyticsOptOutToggled = "analytics opt-out toggled"
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
    case totalRepsBucket = "total_reps_bucket"
    case perceivedEffortEntered = "perceived_effort_entered"
    case notesEntered = "notes_entered"
    case excludedFromProgression = "excluded_from_progression"
    case prsHit = "prs_hit"
    case timeOfDay = "time_of_day"
    case dayOfWeek = "day_of_week"
    case result
    case unitSystem = "unit_system"
    case errorType = "error_type"
    case enabled
    case appVersion = "app_version"
    case buildNumber = "build_number"
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
        switch minutes {
        case ..<15:
            return "under_15m"
        case 15..<30:
            return "15-30m"
        case 30..<45:
            return "30-45m"
        case 45..<60:
            return "45-60m"
        case 60..<90:
            return "60-90m"
        default:
            return "90m_or_more"
        }
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

    /// Wider-range bucket for cumulative counts that commonly exceed 10
    /// (e.g. total reps across a workout). Use `count(_:)` for set counts and
    /// other small tallies where finer detail under 10 matters.
    static func wideCount(_ value: Int) -> String {
        switch max(0, value) {
        case 0:
            return "0"
        case 1...10:
            return "1-10"
        case 11...25:
            return "11-25"
        case 26...50:
            return "26-50"
        case 51...100:
            return "51-100"
        case 101...200:
            return "101-200"
        default:
            return "200+"
        }
    }

    static func timeOfDay(_ date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5...11:
            return "morning"
        case 12...16:
            return "afternoon"
        case 17...20:
            return "evening"
        default:
            return "night"
        }
    }

    static func dayOfWeek(_ date: Date, calendar: Calendar = .current) -> String {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 1: return "sun"
        case 2: return "mon"
        case 3: return "tue"
        case 4: return "wed"
        case 5: return "thu"
        case 6: return "fri"
        case 7: return "sat"
        default: return "unknown"
        }
    }
}
