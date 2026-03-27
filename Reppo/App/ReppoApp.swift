import ActivityKit
import RevenueCat
import SwiftData
import SwiftUI
import UserNotifications

@main
struct ReppoApp: App {
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

            let repoContainer = RepositoryContainer(modelContainer: container)
            self.repositories = repoContainer
            self.services = ServiceContainer(repositoryContainer: repoContainer)

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
                    onComplete: {
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
