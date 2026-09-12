// WorkoutShareCardTests.swift
// Covers the two claims the share card makes that nothing else checks: that it renders at the
// specced 1080 × 1920, and that hiding weights removes every weight rather than most of them.

import XCTest
import SwiftUI
import UniformTypeIdentifiers
@testable import Repster

@MainActor
final class WorkoutShareCardTests: XCTestCase {

    // MARK: - Fixtures

    private func lift(_ name: String, detail: String, sets: String = "3 sets") -> WorkoutShareCardData.Lift {
        WorkoutShareCardData.Lift(id: UUID(), name: name, detail: detail, setCountLabel: sets)
    }

    private func data(prLift: WorkoutShareCardData.Lift? = nil) -> WorkoutShareCardData {
        let bench = lift("Barbell Bench Press", detail: "92.5 kg × 5", sets: "4 sets")
        return WorkoutShareCardData(
            title: "Push Day A",
            dateLabel: "Sat, Aug 30",
            durationLabel: "1h 4m",
            setCountLabel: "18",
            volumeLabel: "12,450 kg",
            liftCountLabel: "5",
            prLift: prLift ?? bench,
            lifts: [bench, lift("Overhead Press", detail: "55 kg × 8", sets: "4 sets")],
            extraLiftCount: 3
        )
    }

    // MARK: - Render size

    /// SHARE_CARD_FEATURE_DESIGN B3 settles on one layout, 9:16 at 1080 × 1920. The card is
    /// authored at 360 × 640 pt, so this only holds while the renderer stays at scale 3.
    func testRendersAtSpeccedStorySize() {
        let image = WorkoutShareCardRenderer.render(
            data: data(),
            hidesExerciseList: false,
            hidesWeights: false
        )

        let rendered = try? XCTUnwrap(image)
        XCTAssertNotNil(rendered, "The card must render; a nil image drops the share silently.")
        XCTAssertEqual(rendered?.size.width, 360)
        XCTAssertEqual(rendered?.size.height, 640)
        XCTAssertEqual(rendered?.scale, 3)

        guard let cgImage = rendered?.cgImage else {
            return XCTFail("Expected a backing CGImage to check pixel dimensions")
        }
        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertEqual(cgImage.height, 1920)
    }

    func testRendersWithBothPrivacyTogglesOn() {
        let image = WorkoutShareCardRenderer.render(
            data: data(),
            hidesExerciseList: true,
            hidesWeights: true
        )
        XCTAssertNotNil(image, "The redacted card still has to render — it is the one people post.")
    }

    /// A session with no records falls back to the workout as the subject rather than to an
    /// empty headline.
    func testRendersWithoutAPersonalRecord() {
        let noPR = WorkoutShareCardData(
            title: "Push Day A",
            dateLabel: "Sat, Aug 30",
            durationLabel: "1h 4m",
            setCountLabel: "18",
            volumeLabel: "12,450 kg",
            liftCountLabel: "5",
            prLift: nil,
            lifts: [lift("Overhead Press", detail: "55 kg × 8")],
            extraLiftCount: 0
        )

        XCTAssertNotNil(
            WorkoutShareCardRenderer.render(data: noPR, hidesExerciseList: false, hidesWeights: false)
        )
    }

    // MARK: - Privacy preferences

    func testPrivacyPreferencesRoundTrip() {
        let defaults = UserDefaults.standard
        let listKey = WorkoutShareCardPreferences.hideExerciseListKey
        let weightsKey = WorkoutShareCardPreferences.hideWeightsKey
        let originalList = defaults.object(forKey: listKey)
        let originalWeights = defaults.object(forKey: weightsKey)
        defer {
            defaults.set(originalList, forKey: listKey)
            defaults.set(originalWeights, forKey: weightsKey)
        }

        defaults.removeObject(forKey: listKey)
        defaults.removeObject(forKey: weightsKey)

        // B3: the exercise list is default-on, because it is the part other lifters find
        // interesting. Both toggles therefore start off.
        XCTAssertFalse(WorkoutShareCardPreferences.hidesExerciseList)
        XCTAssertFalse(WorkoutShareCardPreferences.hidesWeights)

        WorkoutShareCardPreferences.hidesWeights = true
        XCTAssertTrue(WorkoutShareCardPreferences.hidesWeights)
        XCTAssertFalse(WorkoutShareCardPreferences.hidesExerciseList, "Toggles must be independent")
    }

    // MARK: - Share payload

    /// `ShareLink(item: Image)` leans on SwiftUI's `Transferable` conformance, which offers
    /// PNG first and JPEG second — the destination picks. PNG is the right default here:
    /// the card is flat colour and type, so it encodes *smaller* than JPEG and stays lossless,
    /// which matters because story uploads recompress whatever they are given.
    ///
    /// This guards the payload rather than the exact byte count: a photographic background or
    /// a gradient would quietly multiply it.
    func testSharePayloadEncodesAsReasonablySizedPNG() {
        guard let image = WorkoutShareCardRenderer.render(
            data: data(),
            hidesExerciseList: false,
            hidesWeights: false
        ) else {
            return XCTFail("Expected the card to render")
        }

        guard let png = image.pngData() else {
            return XCTFail("The shared representation must encode as PNG")
        }

        // ~94 KB at the time of writing, against a 1080 × 1920 canvas.
        XCTAssertLessThan(
            png.count, 400_000,
            "Share payload ballooned — check for a photo or gradient behind the card"
        )

        // PNG magic number, so this fails loudly if the encoder ever changes under us.
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    // MARK: - Exported file

    func testWritesANamedPNGFile() throws {
        let image = try XCTUnwrap(
            WorkoutShareCardRenderer.render(data: data(), hidesExerciseList: false, hidesWeights: false)
        )

        let url = try WorkoutShareCardRenderer.writePNG(
            image, title: "Push Day A", dateLabel: "Sat, Aug 30"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertEqual(url.lastPathComponent, "Repster-Push-Day-A-Sat-Aug-30.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let written = try Data(contentsOf: url)
        XCTAssertEqual(Array(written.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    /// The title is user content and becomes a path component, so it has to be defanged.
    func testFileNameSanitisesTheWorkoutTitle() {
        let hostile = WorkoutShareCardRenderer.fileName(
            title: "../../etc/passwd\nLeg: Day?",
            dateLabel: "Sat, Aug 30"
        )
        XCTAssertFalse(hostile.contains("/"))
        XCTAssertFalse(hostile.contains(".."))
        XCTAssertFalse(hostile.contains(":"))
        XCTAssertFalse(hostile.contains("?"))
        XCTAssertFalse(hostile.contains("\n"))
        XCTAssertTrue(hostile.hasPrefix("Repster-"))
        XCTAssertTrue(hostile.hasSuffix(".png"))
    }

    func testFileNameSurvivesAnEmptyTitle() {
        XCTAssertEqual(
            WorkoutShareCardRenderer.fileName(title: "   ", dateLabel: ""),
            "Repster.png"
        )
    }

    /// A very long title must not produce a path component the file system rejects.
    func testFileNameIsCapped() {
        let name = WorkoutShareCardRenderer.fileName(
            title: String(repeating: "Bench", count: 60),
            dateLabel: "Sat, Aug 30"
        )
        XCTAssertLessThanOrEqual(name.count, 84)
        XCTAssertTrue(name.hasSuffix(".png"))
    }

    // MARK: - Share sheet destinations

    /// The card must advertise an *image* type, not a URL type.
    ///
    /// Sharing the file URL directly advertised only `public.url` / `public.file-url`, which
    /// silently removed Photos and every app target from the share sheet and left "Save to
    /// Files" as the only option. This is the assertion that would have caught it.
    func testAdvertisesAnImageTypeSoPhotosAndAppsAppear() throws {
        guard #available(iOS 18.2, *) else {
            throw XCTSkip("exportedContentTypes() needs iOS 18.2")
        }

        let types = WorkoutShareCardFile.exportedContentTypes()
        XCTAssertTrue(types.contains(.png), "Expected public.png, got \(types.map(\.identifier))")

        // The point of declaring PNG: it conforms to public.image, which is what Photos,
        // Instagram and the Messages image path filter on.
        XCTAssertTrue(
            types.contains { $0.conforms(to: .image) },
            "Nothing offered conforms to public.image — image destinations will not appear"
        )
        XCTAssertFalse(
            types.contains { $0.conforms(to: .url) },
            "A URL type here is what caused the Files-only regression"
        )
    }

    // MARK: - Save to Photos

    /// iOS terminates the app outright if it touches the photo library without this string, so
    /// a missing key is a crash on first tap rather than a degraded feature. Add-only, because
    /// the app never reads the library.
    func testPhotoLibraryAddUsageDescriptionIsDeclared() throws {
        // The tests run inside the host app, so its Info.plist is the main bundle's.
        let appBundle = Bundle.main
        let description = appBundle.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") as? String

        let value = try XCTUnwrap(
            description,
            "NSPhotoLibraryAddUsageDescription is missing — Save to Photos will crash on first tap"
        )
        XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty)

        // The read-access key would be a claim the app cannot justify; it never reads Photos.
        XCTAssertNil(
            appBundle.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription"),
            "Only add-only access is needed; requesting read access is a broader prompt than the feature warrants"
        )
    }

    // MARK: - Summary header

    /// The share control is a label now, not an icon, so it competes with the title for the
    /// header. 375 pt is the narrowest screen this app can run on — iPhone SE (2nd/3rd gen) —
    /// so that is the case worth pinning.
    func testShareWorkoutLabelFitsTheHeaderOnTheNarrowestSupportedScreen() {
        func width(_ text: String, size: CGFloat) -> CGFloat {
            (text as NSString)
                .size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: .semibold)])
                .width
        }

        let title = width("Workout complete", size: 16)
        let pill = width("Share workout", size: 14) + 13 + 5 + 22   // icon + gap + padding
        let closeButton: CGFloat = 32
        let gaps: CGFloat = 10 + 8
        let horizontalPadding: CGFloat = 32

        let needed = closeButton + gaps + title + pill
        let available = 375 - horizontalPadding

        XCTAssertLessThanOrEqual(
            needed, available,
            "Header overflows on a 375 pt screen — shorten the label or the title"
        )
    }

    // MARK: - Card styles

    private func slice(_ group: String, _ fraction: Double) -> WorkoutShareCardData.MuscleSlice {
        .init(group: group, displayName: group.capitalized, fraction: fraction)
    }

    private func bar(_ magnitude: Double, group: String = "chest", pr: Bool = false, new: Bool = false) -> WorkoutShareCardData.TraceBar {
        .init(id: UUID(), magnitude: magnitude, group: group, isPR: pr, startsNewExercise: new)
    }

    /// A style is only offered when the session can fill it — otherwise swiping lands on a
    /// blank card.
    func testOnlyOffersStylesTheSessionCanFill() {
        var full = data()
        full.muscleSlices = [slice("chest", 0.6), slice("triceps", 0.4)]
        full.traceBars = [bar(1), bar(0.8), bar(0.6)]
        XCTAssertEqual(full.availableStyles(), [.record, .muscles, .volume, .trace])

        // One muscle is not a breakdown, and two bars are not a session.
        var thin = data()
        thin.muscleSlices = [slice("chest", 1.0)]
        thin.traceBars = [bar(1), bar(0.5)]
        XCTAssertEqual(thin.availableStyles(), [.record, .volume])
    }

    /// The card falls back to the workout itself when there is no record, so the style has to
    /// stay on offer — otherwise a plain session can drop to one style and the picker, which
    /// hides itself below two, disappears entirely.
    func testRecordStaysAvailableWithoutAPersonalRecord() {
        var noPR = data(prLift: nil)
        noPR = WorkoutShareCardData(
            title: noPR.title, dateLabel: noPR.dateLabel, durationLabel: noPR.durationLabel,
            setCountLabel: noPR.setCountLabel, volumeLabel: noPR.volumeLabel,
            liftCountLabel: noPR.liftCountLabel, prLift: nil, lifts: noPR.lifts,
            extraLiftCount: noPR.extraLiftCount
        )
        XCTAssertTrue(noPR.availableStyles().contains(.record))
        XCTAssertGreaterThan(noPR.availableStyles().count, 1, "The picker hides itself below two styles")
    }

    /// Volume is a weight. Offering a card that prints the exact tonnage at 96 pt to someone who
    /// asked for weights to be hidden would undo the only control B4 provides.
    func testHidingWeightsWithdrawsTheVolumeCard() {
        var full = data()
        full.muscleSlices = [slice("chest", 0.6), slice("triceps", 0.4)]
        full.traceBars = [bar(1), bar(0.8), bar(0.6)]

        XCTAssertTrue(full.availableStyles(hidesWeights: false).contains(.volume))
        XCTAssertFalse(full.availableStyles(hidesWeights: true).contains(.volume))
        // The others survive — they can all be drawn without a weight on them.
        XCTAssertEqual(full.availableStyles(hidesWeights: true), [.record, .muscles, .trace])
    }

    func testAStyleIsAlwaysAvailableEvenForAnEmptySession() {
        let bare = WorkoutShareCardData(
            title: "Evening Workout", dateLabel: "Fri, 4 Sep", durationLabel: "52m",
            setCountLabel: "17", volumeLabel: nil, liftCountLabel: "6",
            prLift: nil, lifts: [], extraLiftCount: 0
        )
        // No record, no volume, no muscles, no trace — the picker must still have something.
        // .record is always on offer, so there is always something to show.
        XCTAssertEqual(bare.availableStyles(), [.record])
    }

    func testEveryStyleRenders() {
        var full = data()
        full.muscleSlices = [slice("chest", 0.46), slice("shoulders", 0.31), slice("triceps", 0.23)]
        full.traceBars = [bar(1, pr: true, new: true), bar(0.7), bar(0.5, new: true), bar(0.9)]

        for style in WorkoutShareCardStyle.allCases {
            XCTAssertNotNil(
                WorkoutShareCardRenderer.render(
                    data: full, style: style, hidesExerciseList: false, hidesWeights: false
                ),
                "\(style.displayName) card failed to render"
            )
        }
    }

    /// The unit belongs in the caption, not at 96 pt beside the number.
    func testVolumeHeadlineSplitsOffTheUnit() {
        let d = data()
        XCTAssertEqual(d.volumeHeadline, "12,450")
        XCTAssertEqual(d.volumeCaption, "KG MOVED")
    }

    func testStylePreferenceRoundTrips() {
        let defaults = UserDefaults.standard
        let key = WorkoutShareCardPreferences.styleKey
        let original = defaults.object(forKey: key)
        defer { defaults.set(original, forKey: key) }

        defaults.removeObject(forKey: key)
        XCTAssertEqual(WorkoutShareCardPreferences.style, .record)

        WorkoutShareCardPreferences.style = .muscles
        XCTAssertEqual(WorkoutShareCardPreferences.style, .muscles)

        // A style written by a future build must not crash an older one.
        defaults.set("somethingElse", forKey: key)
        XCTAssertEqual(WorkoutShareCardPreferences.style, .record)
    }

    // MARK: - Coach teaser flag

    /// The teaser advertises a feature that is not built, so it stays off until one exists.
    ///
    /// This assertion was inverted for 1.5. It previously pinned the default **on**, on the
    /// reasoning that the flag made the teaser removable without a release — but the key is
    /// local `UserDefaults` with no remote config behind it, so that only ever reached one
    /// device. Coach did not land, and a permanent "Soon" is a broken promise.
    func testCoachTeaserDefaultsOffAndCanBeTurnedOn() {
        let defaults = UserDefaults.standard
        let key = CoachPreferences.summaryTeaserKey
        let original = defaults.object(forKey: key)
        defer { defaults.set(original, forKey: key) }

        defaults.removeObject(forKey: key)
        XCTAssertFalse(CoachPreferences.showsSummaryTeaser, "Coach is unbuilt — the teaser must not ship on by default")

        defaults.set(true, forKey: key)
        XCTAssertTrue(CoachPreferences.showsSummaryTeaser, "The flag must still turn it on for the release Coach lands in")
    }
}

// MARK: - Builder

/// `WorkoutShareCardBuilder` is the one place the card's numbers come from, for the summary and
/// for saved workouts alike. SHARE_FROM_HISTORY_SCOPING.md §5.
@MainActor
final class WorkoutShareCardBuilderTests: XCTestCase {

    private let workoutId = UUID()
    /// Pinned so the year rule and `daysSince` are deterministic.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 12))!
    private let workoutDate = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 18))!

    // MARK: Fixtures

    private func exercise(_ name: String, muscle: String) -> ChartExerciseData {
        let exercise = Exercise(name: name, equipmentType: .barbell, trackingType: .weightReps)
        exercise.primaryMuscle = muscle
        return ChartExerciseData(from: exercise)
    }

    private func set(
        _ exercise: ChartExerciseData,
        order: Int,
        _ weight: Double,
        _ reps: Int,
        completed: Bool = true,
        type: SetType = .working,
        pr: CachedPRStatus? = nil
    ) -> ChartSetData {
        let set = WorkoutSet(
            workoutId: workoutId,
            exerciseId: exercise.id,
            weight: weight,
            effectiveWeight: weight,
            reps: reps,
            setType: type,
            orderInWorkout: order,
            orderInExercise: order,
            completed: completed
        )
        set.prStatus = pr
        return ChartSetData(from: set)
    }

    private struct Session {
        let bench: ChartExerciseData
        let press: ChartExerciseData
        let pushdown: ChartExerciseData
        let entries: [WorkoutShareCardBuilder.Entry]

        var exercisesById: [UUID: ChartExerciseData] {
            Dictionary(uniqueKeysWithValues: entries.map { ($0.exercise.id, $0.exercise) })
        }
    }

    /// Bench with a warm-up and a record on its first working set; a press with one row nobody
    /// ticked; three pushdowns; and a lateral raise that was added and never done.
    private func session(benchRecord: CachedPRStatus? = .current) -> Session {
        let bench = exercise("Barbell Bench Press", muscle: "chest")
        let press = exercise("Overhead Press", muscle: "shoulders")
        let pushdown = exercise("Triceps Pushdown", muscle: "triceps")
        let raise = exercise("Lateral Raise", muscle: "shoulders")

        return Session(bench: bench, press: press, pushdown: pushdown, entries: [
            .init(exercise: bench, sets: [
                set(bench, order: 1, 60, 5, type: .warmup),
                set(bench, order: 2, 100, 5, pr: benchRecord),
                set(bench, order: 3, 100, 5),
                set(bench, order: 4, 90, 5)
            ]),
            .init(exercise: press, sets: [
                set(press, order: 5, 50, 8),
                set(press, order: 6, 50, 8),
                set(press, order: 7, 50, 7, completed: false)
            ]),
            .init(exercise: pushdown, sets: [
                set(pushdown, order: 8, 30, 12),
                set(pushdown, order: 9, 30, 12),
                set(pushdown, order: 10, 30, 12)
            ]),
            .init(exercise: raise, sets: [
                set(raise, order: 11, 10, 15, completed: false)
            ])
        ])
    }

    private func summaryCard(
        _ session: Session,
        duration: TimeInterval? = 3840,
        context: WorkoutShareCardContext = .summary
    ) -> WorkoutShareCardData {
        WorkoutShareCardBuilder.make(
            title: "Push Day A",
            date: workoutDate,
            duration: duration,
            entries: session.entries,
            unitPreference: .metric,
            context: context,
            now: now
        )
    }

    /// A saved workout as the history screens load it: every set in one pile, grouped and
    /// ordered by `ExerciseGroup.build`.
    private func detail(
        sets: [ChartSetData],
        exercisesById: [UUID: ChartExerciseData],
        status: WorkoutStatus = .completed,
        duration: Int? = 3840
    ) -> WorkoutDetail {
        let workout = Workout(
            date: workoutDate,
            title: "Push Day A",
            startTime: workoutDate,
            duration: duration,
            status: status
        )
        return WorkoutDetail(
            workout: WorkoutSnapshot(from: workout),
            exerciseGroups: ExerciseGroup.build(sets: sets, exercisesById: exercisesById, statsById: [:]),
            primaryMetric: nil,
            exerciseCount: 0,
            setCount: 0
        )
    }

    private func group(_ raw: String) -> String {
        ExercisePrimaryGroup.normalizedValue(raw) ?? raw
    }

    // MARK: Golden

    /// The card this session produced from the summary before the builder existed, worked by
    /// hand from that code, with the two differences the builder makes on purpose:
    ///
    /// - "Lateral Raise" has no ticked set, so it is no longer a fourth "0 sets" lift
    ///   (`liftCountLabel` was "4", `extraLiftCount` 1).
    /// - The record's trace bar is marked. The summary read `WorkoutSet.cachedPRStatus`, a
    ///   legacy field the initialiser always sets to nil, so the diamond was never drawn.
    func testGoldenSessionProducesTheSummaryCard() {
        let s = session()
        func kg(_ value: Double) -> String { UnitConversion.formatWeightLabel(value, unitPreference: .metric) }

        let benchLift = WorkoutShareCardData.Lift(id: s.bench.id, name: "Barbell Bench Press", detail: "\(kg(100)) × 5", setCountLabel: "4 sets")
        let pushdownLift = WorkoutShareCardData.Lift(id: s.pushdown.id, name: "Triceps Pushdown", detail: "\(kg(30)) × 12", setCountLabel: "3 sets")
        let pressLift = WorkoutShareCardData.Lift(id: s.press.id, name: "Overhead Press", detail: "\(kg(50)) × 8", setCountLabel: "2 sets")

        // Working sets only, raw weight × reps.
        let chest = 500.0 + 500 + 450, triceps = 360.0 * 3, shoulders = 400.0 * 2
        let muscleTotal = chest + triceps + shoulders

        let benchSets = s.entries[0].sets, pressSets = s.entries[1].sets, pushdownSets = s.entries[2].sets
        func bar(_ set: ChartSetData, _ magnitude: Double, _ muscle: String, pr: Bool = false, new: Bool = false) -> WorkoutShareCardData.TraceBar {
            .init(id: set.id, magnitude: magnitude, group: group(muscle), isPR: pr, startsNewExercise: new)
        }

        let expected = WorkoutShareCardData(
            title: "Push Day A",
            dateLabel: workoutDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
            durationLabel: "1h 4m",
            // Warm-up included; the unticked press row is not.
            setCountLabel: "9",
            // Effective weight × reps over every ticked set, warm-up included.
            volumeLabel: WorkoutPrimaryMetric.volume(1750 + 800 + 1080)
                .formattedValue(style: .detailed, unitPreference: .metric),
            liftCountLabel: "3",
            prLift: benchLift,
            lifts: [benchLift, pushdownLift, pressLift],
            extraLiftCount: 0,
            muscleSlices: [
                .init(group: group("chest"), displayName: ExercisePrimaryGroup.displayName(for: group("chest")), fraction: chest / muscleTotal),
                .init(group: group("triceps"), displayName: ExercisePrimaryGroup.displayName(for: group("triceps")), fraction: triceps / muscleTotal),
                .init(group: group("shoulders"), displayName: ExercisePrimaryGroup.displayName(for: group("shoulders")), fraction: shoulders / muscleTotal)
            ],
            traceBars: [
                bar(benchSets[1], 1, "chest", pr: true, new: true),
                bar(benchSets[2], 1, "chest"),
                bar(benchSets[3], 0.9, "chest"),
                bar(pressSets[0], 0.8, "shoulders", new: true),
                bar(pressSets[1], 0.8, "shoulders"),
                bar(pushdownSets[0], 0.72, "triceps", new: true),
                bar(pushdownSets[1], 0.72, "triceps"),
                bar(pushdownSets[2], 0.72, "triceps")
            ],
            prLabel: "NEW PR"
        )

        XCTAssertEqual(summaryCard(s), expected)
    }

    // MARK: What counts

    /// The Copy Previous row nobody ticked is not a set, not volume and not a bar — a card is a
    /// public claim about what was done.
    func testUntickedRowsCountForNothing() {
        var s = session()
        let card = summaryCard(s)

        let ticked = s.entries[1]
        s = Session(bench: s.bench, press: s.press, pushdown: s.pushdown, entries: [
            s.entries[0],
            .init(exercise: ticked.exercise, sets: ticked.sets.filter(\.completed)),
            s.entries[2],
            s.entries[3]
        ])

        XCTAssertEqual(card, summaryCard(s), "Dropping the unticked row must change nothing")
        XCTAssertEqual(card.setCountLabel, "9")
        XCTAssertFalse(card.traceBars.contains { $0.id == ticked.sets[2].id })
    }

    /// It used to show as a "0 sets" row and count toward "N lifts".
    func testAnExerciseNeverDoneIsNotALift() {
        let card = summaryCard(session())

        XCTAssertFalse(card.lifts.contains { $0.name == "Lateral Raise" })
        XCTAssertEqual(card.liftCountLabel, "3")
        XCTAssertEqual(card.extraLiftCount, 0)
    }

    // MARK: Records (option A)

    /// `prStatus` decays once a record is beaten, and a beaten record is not on the card —
    /// neither as the headline nor as a marked bar. Equalling one is not a record either.
    func testOnlyAStandingRecordIsAPR() {
        XCTAssertNotNil(summaryCard(session(benchRecord: .current)).prLift)
        XCTAssertEqual(summaryCard(session(benchRecord: .current)).traceBars.filter(\.isPR).count, 1)

        for status: CachedPRStatus? in [.previous, .matched, .dominated, nil] {
            let card = summaryCard(session(benchRecord: status))
            XCTAssertNil(card.prLift, "\(String(describing: status)) must not headline the card")
            XCTAssertFalse(card.traceBars.contains(where: \.isPR), "\(String(describing: status)) must not mark a bar")
        }
    }

    func testHistoryCardsSayPersonalBestRatherThanNew() {
        XCTAssertEqual(summaryCard(session(), context: .summary).prLabel, "NEW PR")
        XCTAssertEqual(summaryCard(session(), context: .history).prLabel, "PERSONAL BEST")
    }

    func testStandingPRCountIsTickedCurrentRecordsOnly() {
        let bench = exercise("Barbell Bench Press", muscle: "chest")
        let saved = detail(
            sets: [
                set(bench, order: 1, 100, 5, pr: .current),
                set(bench, order: 2, 100, 6, completed: false, pr: .current),
                set(bench, order: 3, 95, 5, pr: .previous)
            ],
            exercisesById: [bench.id: bench]
        )
        XCTAssertEqual(WorkoutShareCardBuilder.standingPRCount(in: saved), 1)
    }

    // MARK: Labels

    /// Some imported workouts have no duration. "0m" would read as a claim.
    func testMissingDurationIsLeftOffRatherThanZero() {
        let s = session()
        XCTAssertNil(summaryCard(s, duration: nil).durationLabel)

        let sets = s.entries.flatMap(\.sets)
        for missing: Int? in [nil, 0] {
            let saved = detail(sets: sets, exercisesById: s.exercisesById, duration: missing)
            XCTAssertNil(WorkoutShareCardBuilder.make(detail: saved, unitPreference: .metric, now: now).durationLabel)
        }
        let timed = detail(sets: sets, exercisesById: s.exercisesById, duration: 3840)
        XCTAssertEqual(WorkoutShareCardBuilder.make(detail: timed, unitPreference: .metric, now: now).durationLabel, "1h 4m")
    }

    /// A card from last year without its year would pass itself off as recent.
    func testDateCarriesTheYearOnlyWhenItIsNotThisOne() {
        let lastYear = Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 30, hour: 9))!
        XCTAssertTrue(WorkoutShareCardBuilder.dateLabel(lastYear, now: now).contains("2025"))
        XCTAssertFalse(WorkoutShareCardBuilder.dateLabel(workoutDate, now: now).contains("2026"))
    }

    func testDaysSinceCountsCalendarDaysAndNeverGoesNegative() {
        XCTAssertEqual(WorkoutShareCardBuilder.daysSince(now, now: now), 0)
        // 18:00 yesterday to noon today is under 24 hours and still one calendar day.
        XCTAssertEqual(WorkoutShareCardBuilder.daysSince(workoutDate, now: now), 1)
        let later = Calendar.current.date(byAdding: .day, value: 3, to: now)!
        XCTAssertEqual(WorkoutShareCardBuilder.daysSince(later, now: now), 0)
    }

    // MARK: Summary and history agree

    /// The point of one builder: a workout shared from the summary and again from history is
    /// the same card, even though history hands the sets over in one unordered pile and lets
    /// `ExerciseGroup.build` put them back together. Only the PR wording differs.
    func testASavedWorkoutSharesTheSameCardAsItsSummary() {
        let s = session()
        let saved = detail(sets: s.entries.flatMap(\.sets).reversed(), exercisesById: s.exercisesById)

        var expected = summaryCard(s)
        expected.prLabel = "PERSONAL BEST"

        XCTAssertEqual(WorkoutShareCardBuilder.make(detail: saved, unitPreference: .metric, now: now), expected)
    }

    // MARK: Who gets a button

    func testOnlyAFinishedWorkoutWithSomethingTickedCanBeShared() {
        let s = session()
        let sets = s.entries.flatMap(\.sets)

        XCTAssertTrue(WorkoutShareCardBuilder.canShare(detail(sets: sets, exercisesById: s.exercisesById)))
        XCTAssertFalse(
            WorkoutShareCardBuilder.canShare(detail(sets: sets, exercisesById: s.exercisesById, status: .inProgress)),
            "Calendar lists today's in-progress workout; it is not a card yet"
        )

        let nothingTicked = sets.filter { !$0.completed }
        XCTAssertFalse(
            WorkoutShareCardBuilder.canShare(detail(sets: nothingTicked, exercisesById: s.exercisesById)),
            "A workout with nothing ticked would share as an empty card"
        )
    }
}
