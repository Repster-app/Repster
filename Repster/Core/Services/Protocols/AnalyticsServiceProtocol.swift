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
        // Kept in lockstep with the start context so the two can never disagree
        // about whether a workout is in flight.
        ActiveWorkoutSessionMarker.markStarted(userDefaults: userDefaults)
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
        ActiveWorkoutSessionMarker.clear(userDefaults: userDefaults)
    }
}

/// Analytics-only bookkeeping for the in-flight workout. Lives in UserDefaults
/// rather than the model so that nothing here touches workout persistence.
///
/// Exists to answer two questions the event stream previously could not:
///   1. How long after starting a workout does someone log their first set?
///   2. How many workouts are simply walked away from? A user who starts a
///      session and never finishes or discards it produced no terminal event at
///      all, so they were invisible.
enum ActiveWorkoutSessionMarker {
    private static let startedAtKey = "analyticsActiveWorkoutStartedAt"
    private static let firstSetLoggedKey = "analyticsActiveWorkoutFirstSetLogged"
    private static let setCountKey = "analyticsActiveWorkoutSetCount"

    /// A workout still marked in-flight this long after starting is treated as
    /// abandoned. Long enough to survive a genuinely slow session plus a phone
    /// restart; short enough that the event lands the next day.
    static let abandonmentThreshold: TimeInterval = 12 * 60 * 60

    static func markStarted(at date: Date = Date(), userDefaults: UserDefaults = .standard) {
        userDefaults.set(date, forKey: startedAtKey)
        userDefaults.set(false, forKey: firstSetLoggedKey)
        userDefaults.set(0, forKey: setCountKey)
    }

    static func startedAt(userDefaults: UserDefaults = .standard) -> Date? {
        userDefaults.object(forKey: startedAtKey) as? Date
    }

    static func hasLoggedFirstSet(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: firstSetLoggedKey)
    }

    static func setCount(userDefaults: UserDefaults = .standard) -> Int {
        userDefaults.integer(forKey: setCountKey)
    }

    /// Returns true only the first time it's called for a given workout, so the
    /// caller can fire `first set logged` exactly once.
    static func markFirstSetLogged(userDefaults: UserDefaults = .standard) -> Bool {
        guard !hasLoggedFirstSet(userDefaults: userDefaults) else { return false }
        userDefaults.set(true, forKey: firstSetLoggedKey)
        return true
    }

    static func incrementSetCount(userDefaults: UserDefaults = .standard) {
        userDefaults.set(setCount(userDefaults: userDefaults) + 1, forKey: setCountKey)
    }

    static func isAbandoned(now: Date = Date(), userDefaults: UserDefaults = .standard) -> Bool {
        guard let startedAt = startedAt(userDefaults: userDefaults) else { return false }
        return now.timeIntervalSince(startedAt) > abandonmentThreshold
    }

    static func clear(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: startedAtKey)
        userDefaults.removeObject(forKey: firstSetLoggedKey)
        userDefaults.removeObject(forKey: setCountKey)
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
        excludedFromProgression: Bool,
        accessTier: String?,
        remainingFreeWorkouts: Int?,
        rirSetCount: Int,
        averageRIR: Double?
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
            .excludedFromProgression: .bool(excludedFromProgression),
            .rirSetCountBucket: .string(AnalyticsBuckets.count(rirSetCount)),
            .rirEntered: .bool(rirSetCount > 0)
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
        if let accessTier {
            properties[.accessTier] = .string(accessTier)
        }
        if let remainingFreeWorkouts {
            properties[.remainingFreeWorkouts] = .int(remainingFreeWorkouts)
        }
        if let averageRIR {
            properties[.averageRirBucket] = .string(AnalyticsBuckets.rir(averageRIR))
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

    // Onboarding
    //
    // Onboarding was previously untracked end to end, which made install ->
    // activation impossible to measure: a user who bounced on step 2 looked
    // identical to one who never opened the app.

    func onboardingStepViewed(_ step: OnboardingStep) {
        track(.onboardingStepViewed, properties: [
            .step: .string(step.analyticsName),
            .stepIndex: .int(step.rawValue)
        ])
    }

    func onboardingStepSkipped(_ step: OnboardingStep) {
        track(.onboardingStepSkipped, properties: [
            .step: .string(step.analyticsName),
            .stepIndex: .int(step.rawValue)
        ])
    }

    func onboardingCompleted(lastStep: OnboardingStep, unitSystem: String?) {
        var properties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [
            .step: .string(lastStep.analyticsName),
            .stepIndex: .int(lastStep.rawValue)
        ]
        if let unitSystem {
            properties[.unitSystem] = .string(unitSystem)
        }
        track(.onboardingCompleted, properties: properties)
    }

    // Activation

    func exerciseCreated(source: String) {
        track(.exerciseCreated, properties: [.source: .string(source)])
    }

    func templateCreated(exerciseCount: Int, source: String) {
        track(.templateCreated, properties: [
            .exerciseCountBucket: .string(AnalyticsBuckets.count(exerciseCount)),
            .source: .string(source)
        ])
    }

    /// Fired once per workout, on the first completed set. Separates "opened a
    /// workout and stared at it" from "actually logged something".
    func firstSetLogged(source: WorkoutStartSource?, secondsSinceStart: TimeInterval) {
        var properties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [
            .elapsedSecondsBucket: .string(AnalyticsBuckets.shortDuration(seconds: secondsSinceStart))
        ]
        if let source {
            properties[.source] = .string(source.rawValue)
        }
        track(.firstSetLogged, properties: properties)
    }

    func workoutResumed(setCount: Int) {
        track(.workoutResumed, properties: [
            .setCountBucket: .string(AnalyticsBuckets.count(setCount))
        ])
    }

    /// A workout that was started but never completed or discarded — the user
    /// left the app mid-session and never came back to it. Detected on next
    /// launch, so it always lags the actual abandonment by one app open.
    func workoutAbandoned(setCount: Int, source: WorkoutStartSource?, templateUsed: Bool?) {
        var properties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [
            .setCountBucket: .string(AnalyticsBuckets.count(setCount))
        ]
        if let source {
            properties[.source] = .string(source.rawValue)
        }
        if let templateUsed {
            properties[.templateUsed] = .bool(templateUsed)
        }
        track(.workoutAbandoned, properties: properties)
    }

    /// A screen that rendered with nothing in it. "Charts with no data" is a
    /// prime suspect for a silent first-session bounce.
    func emptyStateShown(screen: AnalyticsScreen) {
        track(.emptyStateShown, properties: [
            .screenName: .string(screen.rawValue),
            .hasData: .bool(false)
        ])
    }

    func screenViewed(_ screen: AnalyticsScreen, hasData: Bool) {
        self.screen(screen, properties: [.hasData: .bool(hasData)])
        if !hasData {
            emptyStateShown(screen: screen)
        }
    }

    func reviewPromptRequested(trigger: String, completedWorkoutCount: Int) {
        track(.reviewPromptRequested, properties: [
            .trigger: .string(trigger),
            .completedWorkoutCount: .string(AnalyticsBuckets.count(completedWorkoutCount))
        ])
    }
}

extension OnboardingStep {
    var analyticsName: String {
        switch self {
        case .welcome: return "welcome"
        case .units: return "units"
        case .bodyweight: return "bodyweight"
        case .smartSuggestions: return "smart_suggestions"
        case .importPrompt: return "import_prompt"
        }
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
    case insights = "Insights"
    case exerciseList = "Exercise List"
    case templates = "Templates"
    case history = "History"
}

enum AnalyticsEvent: String, CaseIterable {
    case workoutStarted = "workout started"
    case workoutCompleted = "workout completed"
    case workoutDiscarded = "workout discarded"
    case workoutAbandoned = "workout abandoned"
    case workoutResumed = "workout resumed"
    case firstSetLogged = "first set logged"
    case onboardingStepViewed = "onboarding step viewed"
    case onboardingStepSkipped = "onboarding step skipped"
    case onboardingCompleted = "onboarding completed"
    case exerciseCreated = "exercise created"
    case templateCreated = "template created"
    case emptyStateShown = "empty state shown"
    case reviewPromptRequested = "review prompt requested"
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
    case accessTier = "access_tier"
    case remainingFreeWorkouts = "remaining_free_workouts"
    case rirEntered = "rir_entered"
    case rirSetCountBucket = "rir_set_count_bucket"
    case averageRirBucket = "average_rir_bucket"
    case step
    case stepIndex = "step_index"
    case hasData = "has_data"
    case screenName = "screen_name"
    case completedWorkoutCount = "completed_workout_count"
    case elapsedSecondsBucket = "elapsed_seconds_bucket"
    case trigger
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

    /// Sub-workout timescale, for "how long until they logged anything".
    /// `duration(seconds:)` starts at 15-minute granularity, which is far too
    /// coarse for time-to-first-set.
    static func shortDuration(seconds: TimeInterval) -> String {
        switch max(0, seconds) {
        case ..<30:
            return "under_30s"
        case 30..<60:
            return "30-60s"
        case 60..<180:
            return "1-3m"
        case 180..<600:
            return "3-10m"
        default:
            return "10m_or_more"
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

    /// Buckets a RIR value (typically 0–5+) into a low-cardinality string so
    /// PostHog can aggregate without exploding distinct values from per-set
    /// averages.
    static func rir(_ value: Double) -> String {
        switch value {
        case ..<0.5:
            return "0"
        case 0.5..<1.5:
            return "1"
        case 1.5..<2.5:
            return "2"
        case 2.5..<3.5:
            return "3"
        case 3.5..<4.5:
            return "4"
        default:
            return "5+"
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
