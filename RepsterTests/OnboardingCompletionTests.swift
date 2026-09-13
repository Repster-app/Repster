import XCTest
import SwiftData
@testable import Repster

/// "Start training" completes onboarding once, however often it is tapped.
///
/// When the screen failed to switch to Home (see `AppRootView` in RepsterApp.swift), people
/// tapped again, and every tap saved another bodyweight entry. A tap after a successful save
/// must still hand off to the app, because that retry is what gets a stuck screen moving.
@MainActor
final class OnboardingCompletionTests: XCTestCase {

    /// The real onboarding screen over the real services and an in-memory store.
    private func makeOnboarding() throws -> (viewModel: OnboardingViewModel, container: ModelContainer) {
        let container = try ModelContainer(
            for: Schema(ModelContainerSetup.modelTypes),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let healthProfileRepo = HealthProfileRepository(modelContainer: container)
        let setRepo = SetRepository(modelContainer: container)
        let exerciseRepo = ExerciseRepository(modelContainer: container)
        let performanceRecordRepo = PerformanceRecordRepository(modelContainer: container)
        let statsService = StatsService(
            exerciseStatsRepository: ExerciseStatsRepository(modelContainer: container),
            setRepository: setRepo,
            exerciseRepository: exerciseRepo,
            healthProfileRepository: healthProfileRepo,
            performanceRecordRepository: performanceRecordRepo
        )
        let prService = PRService(
            performanceRecordRepository: performanceRecordRepo,
            setRepository: setRepo,
            workoutRepository: WorkoutRepository(modelContainer: container),
            healthProfileRepository: healthProfileRepo,
            exerciseRepository: exerciseRepo
        )
        let settingsService = SettingsService(
            healthProfileRepository: healthProfileRepo,
            prService: prService,
            statsService: statsService,
            modelContainer: container,
            userDefaults: UserDefaults(suiteName: "onboarding-completion-\(UUID().uuidString)")!,
            seedExercises: { _ in }
        )
        let viewModel = OnboardingViewModel(
            settingsService: settingsService,
            bodyweightService: BodyweightService(
                bodyweightEntryRepository: BodyweightEntryRepository(modelContainer: container),
                healthProfileRepository: healthProfileRepo
            ),
            analyticsService: NoopAnalyticsService(),
            programCatalogService: OnboardingCompletionNoPrograms()
        )
        return (viewModel, container)
    }

    func testRepeatedTapsSaveOnceAndStillHandOff() async throws {
        let (viewModel, container) = try makeOnboarding()
        viewModel.selectedUnit = .imperial
        viewModel.bodyweightInput = "180"

        let firstTap = await viewModel.completeOnboarding()
        let retryTap = await viewModel.completeOnboarding()

        XCTAssertTrue(firstTap)
        XCTAssertTrue(retryTap, "a tap after saving must still hand off to the app")
        XCTAssertTrue(viewModel.hasFinished)

        let context = ModelContext(container)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<BodyweightEntry>()).count, 1,
            "the retry must not log a second bodyweight entry"
        )
        let profile = try XCTUnwrap(try context.fetch(FetchDescriptor<HealthProfile>()).first)
        XCTAssertEqual(profile.unitPreference, .imperial)
        XCTAssertEqual(profile.prescriptionDefaultTargetReps, 8)
        XCTAssertEqual(profile.prescriptionDefaultTargetRIR, 2)
    }

    func testTapWhileSavingLeavesTheHandOffToTheFirstTap() async throws {
        let (viewModel, container) = try makeOnboarding()
        viewModel.bodyweightInput = "80"

        async let firstTap = viewModel.completeOnboarding()
        async let secondTap = viewModel.completeOnboarding()
        let first = await firstTap
        let second = await secondTap

        XCTAssertEqual([first, second].filter { $0 }.count, 1, "exactly one tap hands off")
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<BodyweightEntry>()).count, 1)
    }
}

/// Onboarding with no program picked never calls this; it exists to satisfy the initializer.
private struct OnboardingCompletionNoPrograms: ProgramCatalogServiceProtocol {
    func availablePrograms() throws -> [ProgramSeedDTO] { [] }

    func materialise(programId: String) async throws -> ProgramMaterialisationResult {
        throw CancellationError()
    }
}
