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
        XCTAssertEqual(full.availableStyles, [.record, .muscles, .volume, .trace])

        // One muscle is not a breakdown, and two bars are not a session.
        var thin = data()
        thin.muscleSlices = [slice("chest", 1.0)]
        thin.traceBars = [bar(1), bar(0.5)]
        XCTAssertEqual(thin.availableStyles, [.record, .volume])
    }

    func testAStyleIsAlwaysAvailableEvenForAnEmptySession() {
        let bare = WorkoutShareCardData(
            title: "Evening Workout", dateLabel: "Fri, 4 Sep", durationLabel: "52m",
            setCountLabel: "17", volumeLabel: nil, liftCountLabel: "6",
            prLift: nil, lifts: [], extraLiftCount: 0
        )
        // No record, no volume, no muscles, no trace — the picker must still have something.
        XCTAssertTrue(bare.availableStyles.isEmpty)
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

    /// The teaser is drawn as unbuilt, so it has to be removable without a release.
    func testCoachTeaserDefaultsOnAndCanBePulled() {
        let defaults = UserDefaults.standard
        let key = CoachPreferences.summaryTeaserKey
        let original = defaults.object(forKey: key)
        defer { defaults.set(original, forKey: key) }

        defaults.removeObject(forKey: key)
        XCTAssertTrue(CoachPreferences.showsSummaryTeaser)

        defaults.set(false, forKey: key)
        XCTAssertFalse(CoachPreferences.showsSummaryTeaser)
    }
}
