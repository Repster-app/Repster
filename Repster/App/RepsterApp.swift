import ActivityKit
import RevenueCat
import SwiftData
import SwiftUI
import UserNotifications

@main
struct RepsterApp: App {
    let modelContainer: ModelContainer
    let repositories: RepositoryContainer
    let services: ServiceContainer

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfiguration.apiKey)

        do {
            let container = try ModelContainerSetup.createContainer()
            self.modelContainer = container

            // Seed exercise library on first launch
            let seedContext = ModelContext(container)
            SeedService.seedIfNeeded(modelContext: seedContext)

            // Recover sets persisted with reps=nil from the empty-checkmark bug (one-shot).
            GhostSetRepsBackfillMigration.runIfNeeded(modelContext: seedContext)

            // Runs here rather than in ContentView because HomeViewModel reads the section
            // config as it builds — a migration scheduled after that lands a launch late.
            InsightsSectionPromotionMigration.runIfNeeded()

            // Repair exercise workout counts left wrong by the old row-count rule (one-shot).
            ExerciseWorkoutCountBackfillMigration.runIfNeeded(modelContext: seedContext)

            let repoContainer = RepositoryContainer(modelContainer: container)
            self.repositories = repoContainer
            let analyticsService = AnalyticsServiceFactory.makeService()
            analyticsService.configure()
            self.services = ServiceContainer(
                repositoryContainer: repoContainer,
                analyticsService: analyticsService
            )

            // Apple Search Ads attribution. Both collectors are gated on the same
            // analytics preference the factory checks, because the privacy policy
            // promises one toggle covers everything — a second collection path
            // that ignored it would make the published policy wrong.
            //
            // Attribution cannot be backfilled, so a user who opts in later still
            // gets resolved: the stored state stays `pending` until it succeeds.
            if let attributionService = AttributionServiceFactory.makeService(
                analytics: analyticsService
            ) {
                // RevenueCat decodes the same token server-side, which is what
                // puts campaign data on the customer and lets revenue be split
                // by channel. One line, and it needs no other wiring.
                Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()

                Task.detached(priority: .utility) {
                    await attributionService.resolveIfNeeded()
                }
            }

            // Clean up any stale Live Activities from a previous app session
            // (e.g., user force-quit the app while a workout was active)
            LiveActivityManager().cleanupStaleActivities()

            // Request notification permission for rest timer background alerts
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingContainerView(
                    settingsService: services.settingsService,
                    bodyweightService: services.bodyweightService,
                    importService: services.importService,
                    analyticsService: services.analyticsService,
                    healthKitService: services.healthKitService,
                    onComplete: {
                        // A fresh install starts caught up, so What's New never greets
                        // someone with news about the only version they have ever run.
                        // This is also what makes an empty `lastSeenWhatsNewVersion`
                        // unambiguously mean "upgraded from a build before it existed".
                        WhatsNewPreferences.markSeen()
                        hasCompletedOnboarding = true
                    }
                )
            }
        }
        .modelContainer(modelContainer)
        .environment(repositories)
        .environment(services)
    }
}
