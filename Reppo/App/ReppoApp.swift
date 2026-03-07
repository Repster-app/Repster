import SwiftUI
import SwiftData

@main
struct ReppoApp: App {
    let modelContainer: ModelContainer
    let repositories: RepositoryContainer
    let services: ServiceContainer

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        do {
            let container = try ModelContainerSetup.createContainer()
            self.modelContainer = container

            // Seed exercise library on first launch
            let seedContext = ModelContext(container)
            SeedService.seedIfNeeded(modelContext: seedContext)

            let repoContainer = RepositoryContainer(modelContainer: container)
            self.repositories = repoContainer
            self.services = ServiceContainer(repositoryContainer: repoContainer)
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
