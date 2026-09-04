// WorkoutShareCard.swift
// The shareable 9:16 workout card, its data, its privacy preferences and its renderer.
//
// Scope: SHARE_CARD_FEATURE_DESIGN.md B3 (contents), B4 (privacy toggles), C3 (purity).
// Design: design/summary-card/OptionO.dc.html and BrandGround.dc.html.
//
// The view is deliberately **pure** — plain values in, no services, no environment. That is
// C3's one rule, and it is what makes `ImageRenderer` produce a stable image: a view that
// reads the environment renders differently off-screen than it does on.

import Photos
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Style

/// Which story the card tells about the session. All four draw the same workout.
enum WorkoutShareCardStyle: String, CaseIterable, Identifiable, Equatable {
    case record
    case muscles
    case volume
    case trace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .record:  return "Record"
        case .muscles: return "Muscles"
        case .volume:  return "Volume"
        case .trace:   return "Session"
        }
    }
}

// MARK: - Data

/// Everything the card draws, pre-formatted. No model types, no services.
struct WorkoutShareCardData: Equatable {

    struct Lift: Equatable, Identifiable {
        let id: UUID
        let name: String
        /// Pre-formatted best set, e.g. "92.5 kg × 5". Dropped when weights are hidden.
        let detail: String
        /// Set count, shown in place of `detail` when weights are hidden.
        let setCountLabel: String
    }

    let title: String
    let dateLabel: String
    let durationLabel: String
    let setCountLabel: String
    /// Total volume, already unit-converted. Nil for distance/duration-style sessions.
    let volumeLabel: String?
    let liftCountLabel: String
    /// The single best record of the session, when there was one.
    let prLift: Lift?
    /// Top lifts by set count, capped by the caller.
    let lifts: [Lift]
    /// How many lifts did not fit in `lifts`.
    let extraLiftCount: Int

    /// Volume split by the exercise's primary muscle, largest first. Empty when nothing in the
    /// session resolves to a muscle group.
    var muscleSlices: [MuscleSlice] = []

    /// Every working set in the order it was performed.
    var traceBars: [TraceBar] = []

    /// A slice of the session's volume.
    struct MuscleSlice: Equatable, Identifiable {
        /// Normalised group, e.g. "chest" — the key `MuscleGroupColors` expects.
        let group: String
        let displayName: String
        /// 0...1 of the session's total volume.
        let fraction: Double
        var id: String { group }
    }

    /// One set, as a bar.
    struct TraceBar: Equatable, Identifiable {
        let id: UUID
        /// Normalised against the session's heaviest set, 0...1.
        let magnitude: Double
        /// Normalised muscle group, or nil when the lift has none.
        let group: String?
        let isPR: Bool
        /// True where a new exercise begins, so the trace can be grouped visually.
        let startsNewExercise: Bool
    }

    /// "12,450" out of "12,450 kg" — the unit rides in the caption instead of at 96 pt.
    var volumeHeadline: String {
        guard let volumeLabel else { return setCountLabel }
        return volumeLabel.split(separator: " ").first.map(String.init) ?? volumeLabel
    }

    /// "KILOS MOVED", or the unit the primary metric actually uses.
    var volumeCaption: String {
        guard let volumeLabel else { return "SETS LOGGED" }
        let unit = volumeLabel.split(separator: " ").dropFirst().joined(separator: " ")
        guard !unit.isEmpty else { return "TOTAL VOLUME" }
        return "\(unit) moved".uppercased()
    }

    /// Only offer a style the session can actually fill.
    var availableStyles: [WorkoutShareCardStyle] {
        WorkoutShareCardStyle.allCases.filter { style in
            switch style {
            case .record:  return prLift != nil
            case .muscles: return muscleSlices.count >= 2
            case .volume:  return volumeLabel != nil
            case .trace:   return traceBars.count >= 3
            }
        }
    }
}

// MARK: - Privacy

/// B4: weights are the sensitive part for a meaningful share of lifters. Both choices persist
/// so the decision is made once rather than at every share.
enum WorkoutShareCardPreferences {
    static let hideExerciseListKey = "shareCard.hidesExerciseList"
    static let hideWeightsKey = "shareCard.hidesWeights"

    static var hidesExerciseList: Bool {
        get { UserDefaults.standard.bool(forKey: hideExerciseListKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideExerciseListKey) }
    }

    static var hidesWeights: Bool {
        get { UserDefaults.standard.bool(forKey: hideWeightsKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideWeightsKey) }
    }

    static let styleKey = "shareCard.style"

    /// B3 rejected a picker because "a picker adds a decision at the exact moment where friction
    /// costs the most". Remembering the choice is what makes a picker compatible with that: it
    /// is browsed once, not answered every time.
    static var style: WorkoutShareCardStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: styleKey),
                  let style = WorkoutShareCardStyle(rawValue: raw) else { return .record }
            return style
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: styleKey) }
    }
}

// MARK: - Card

struct WorkoutShareCard: View {

    /// 9:16 at 360 pt, which renders to the specced 1080 × 1920 at `scale: 3`.
    static let size = CGSize(width: 360, height: 640)

    let data: WorkoutShareCardData
    var style: WorkoutShareCardStyle = .record
    var hidesExerciseList: Bool = false
    var hidesWeights: Bool = false

    var body: some View {
        Group {
            switch style {
            case .record:  recordBody
            case .muscles: musclesBody
            case .volume:  volumeBody
            case .trace:   traceBody
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 34)
        .padding(.bottom, 30)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.bg)
    }

    // MARK: Record (the original)

    private var recordBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Story chrome covers roughly the top and bottom sixth, so the block sits high-centre
            // rather than against the top edge.
            Spacer(minLength: 0)
                .frame(maxHeight: .infinity)

            headline

            Spacer().frame(height: 34)

            statRow

            if !hidesExerciseList && !data.lifts.isEmpty {
                Spacer().frame(height: 28)
                liftList
            }

            Spacer(minLength: 0)
                .frame(maxHeight: .infinity)

            footer
        }
    }

    // MARK: Muscles

    private var musclesBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow(data.title, color: .textTertiary)

            Spacer(minLength: 0).frame(maxHeight: .infinity)

            ZStack {
                MuscleDonut(slices: data.muscleSlices)
                    .frame(width: 210, height: 210)

                VStack(spacing: 2) {
                    Text(data.volumeLabel ?? data.setCountLabel)
                        .font(.system(size: 26, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(data.volumeLabel == nil ? "SETS" : "TOTAL")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(1.1)
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer().frame(height: 28)

            VStack(spacing: 11) {
                ForEach(data.muscleSlices.prefix(4)) { slice in
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(MuscleGroupColors.color(for: slice.group))
                            .frame(width: 9, height: 9)

                        Text(slice.displayName)
                            .font(.system(size: 14))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text("\(Int((slice.fraction * 100).rounded()))%")
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.textSecondary)
                    }
                }
            }

            Spacer(minLength: 0).frame(maxHeight: .infinity)

            metaRow([data.durationLabel, "\(data.setCountLabel) sets", "\(data.liftCountLabel) lifts"])

            Spacer().frame(height: 16)

            footer
        }
    }

    // MARK: Volume

    private var volumeBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow(data.title, color: .textTertiary)

            Spacer(minLength: 0).frame(maxHeight: .infinity)

            Text(data.volumeHeadline)
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Spacer().frame(height: 14)

            Text(data.volumeCaption)
                .font(.system(size: 15, weight: .bold))
                .kerning(3.2)
                .foregroundColor(.accent)

            Spacer().frame(height: 30)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accent)
                .frame(width: 56, height: 3)

            Spacer(minLength: 0).frame(maxHeight: .infinity)

            metaRow([data.durationLabel, "\(data.setCountLabel) sets", "\(data.liftCountLabel) lifts"])

            Spacer().frame(height: 16)

            footer
        }
    }

    // MARK: Trace

    private var traceBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(data.title)
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0).frame(maxHeight: .infinity)

            SessionTrace(bars: data.traceBars)
                .frame(height: 150)

            Spacer().frame(height: 16)

            HStack(spacing: 16) {
                ForEach(data.muscleSlices.prefix(3)) { slice in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(MuscleGroupColors.color(for: slice.group))
                            .frame(width: 9, height: 9)
                        Text(slice.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0).frame(maxHeight: .infinity)

            metaRow([data.durationLabel, "\(data.setCountLabel) sets", data.volumeLabel].compactMap { $0 })

            Spacer().frame(height: 16)

            footer
        }
    }

    // MARK: Shared pieces

    private func eyebrow(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .kerning(2.0)
            .textCase(.uppercase)
            .foregroundColor(color)
            .lineLimit(1)
    }

    private func metaRow(_ items: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Text("·").foregroundColor(.textTertiary)
                }
                Text(item)
            }
        }
        .font(.system(size: 13))
        .monospacedDigit()
        .foregroundColor(.textSecondary)
    }

    // MARK: Headline

    @ViewBuilder
    private var headline: some View {
        if let pr = data.prLift {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.gold)

                    Text("NEW PR")
                        .font(.system(size: 12, weight: .bold))
                        .kerning(2.2)
                        .foregroundColor(.gold)
                }

                Spacer().frame(height: 24)

                // With weights hidden the achievement has to be carried by the words and the
                // type size, so the lift name becomes the headline rather than leaving a hole
                // where a number used to be.
                if hidesWeights {
                    Text(pr.name)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer().frame(height: 10)

                    Text("Best set I've logged")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.gold)
                } else {
                    Text(pr.name)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)

                    Spacer().frame(height: 8)

                    Text(pr.detail)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        } else {
            // No record: the workout itself is the subject.
            //
            // Deliberately just the title. This carried a "6 · 17 · 52m" line, which was the
            // same three numbers as the stat row immediately below it, stripped of their labels
            // and their units — so it read as a meaningless string and then repeated itself.
            Text(data.title)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Stats

    private var statRow: some View {
        HStack(spacing: 10) {
            statCell(value: data.durationLabel, label: "TIME")
            statCell(value: data.setCountLabel, label: "SETS")

            // Volume is a weight, so it goes with the weights. A lift count keeps the row at
            // three rather than leaving a gap.
            if hidesWeights || data.volumeLabel == nil {
                statCell(value: data.liftCountLabel, label: "LIFTS")
            } else if let volume = data.volumeLabel {
                statCell(value: volume, label: "VOLUME")
            }
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.0)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Lifts

    private var liftList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(data.lifts) { lift in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(lift.name)
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(hidesWeights ? lift.setCountLabel : lift.detail)
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                }
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) {
                    if lift.id != data.lifts.last?.id {
                        Rectangle()
                            .fill(Color.border)
                            .frame(height: 1)
                    }
                }
            }

            if data.extraLiftCount > 0 {
                Text("+\(data.extraLiftCount) more")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .padding(.top, 11)
            }
        }
    }

    // MARK: Footer

    /// B3: date and wordmark. Always present, never removable.
    ///
    /// No URL on the face: `repster.app` was never a domain we own — it read back from the
    /// `com.repster.app` bundle id — and the Pages URL is too long to be typed off an image.
    /// B3 open decision 1 settles as "no short domain", so the mark carries the brand alone.
    private var footer: some View {
        HStack(spacing: 10) {
            Text(data.dateLabel)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundColor(.textTertiary)

            Spacer()

            HStack(spacing: 8) {
                Image("RepsterMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)

                Text("Repster")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
        }
        .padding(.top, 18)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
        }
    }
}

// MARK: - Drawings

/// Volume by muscle, as a ring. Segments are separated by a small gap so neighbouring colours
/// never touch.
private struct MuscleDonut: View {
    let slices: [WorkoutShareCardData.MuscleSlice]

    var body: some View {
        Canvas { context, size in
            let lineWidth: CGFloat = 26
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            // A gap in degrees, so thin slices still read as separate.
            let gap: Double = 2.5
            var start: Double = -90

            for slice in slices {
                let sweep = slice.fraction * 360
                guard sweep > gap else {
                    start += sweep
                    continue
                }

                var path = Path()
                path.addArc(
                    center: centre,
                    radius: radius,
                    startAngle: .degrees(start + gap / 2),
                    endAngle: .degrees(start + sweep - gap / 2),
                    clockwise: false
                )
                context.stroke(
                    path,
                    with: .color(MuscleGroupColors.color(for: slice.group)),
                    style: StrokeStyle(lineWidth: lineWidth)
                )
                start += sweep
            }
        }
    }
}

/// Every set of the session, in order, as a bar. Height is the set's volume against the
/// heaviest set of the session; a diamond marks a record.
private struct SessionTrace: View {
    let bars: [WorkoutShareCardData.TraceBar]

    var body: some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(bars.count - 1, 0)) * 4
            let groupGaps = CGFloat(bars.filter(\.startsNewExercise).count) * 8
            let barWidth = max(4, (proxy.size.width - gaps - groupGaps) / CGFloat(max(bars.count, 1)))
            let markerRoom: CGFloat = 16
            let usable = proxy.size.height - markerRoom

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                    let height = max(6, usable * CGFloat(bar.magnitude))

                    VStack(spacing: 5) {
                        if bar.isPR {
                            Diamond()
                                .fill(Color.gold)
                                .frame(width: 9, height: 9)
                        } else {
                            Color.clear.frame(width: 9, height: 9)
                        }

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(bar.group.map { MuscleGroupColors.color(for: $0) } ?? Color.textTertiary)
                            .frame(width: barWidth, height: height)
                    }
                    .padding(.leading, index > 0 && bar.startsNewExercise ? 8 : 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)
            }
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}


// MARK: - Renderer

/// The card as shareable PNG *content* that happens to be backed by a file.
///
/// Sharing a bare `URL` advertises `public.url` and `public.file-url` and nothing else, so every
/// image destination — Photos, Instagram, Messages' image path — drops out of the share sheet and
/// "Save to Files" is all that is left. Declaring `.png` puts them back, while `suggestedFileName`
/// keeps the readable filename that sharing a raw `Image` would have thrown away.
struct WorkoutShareCardFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { file in
            SentTransferredFile(file.url)
        }
        .suggestedFileName { $0.url.lastPathComponent }
    }
}

/// Saving the card straight to Photos, so the common destination is one tap rather than a
/// share sheet and a scroll.
///
/// Deliberately `.addOnly`: the app never reads the library, and add-only is the lighter of the
/// two Photos prompts — it does not ask for access to existing photos, which is a claim we
/// would not be able to justify.
enum WorkoutShareCardPhotoSaver {

    enum Outcome: Equatable {
        case saved
        /// The user said no, or Photos access is restricted. Recoverable only in Settings.
        case denied
        case failed
    }

    static func save(_ image: UIImage) async -> Outcome {
        let status = await requestAddOnlyAuthorization()

        guard status == .authorized || status == .limited else {
            return status == .denied || status == .restricted ? .denied : .failed
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return .saved
        } catch {
            return .failed
        }
    }

    private static func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }
}

enum WorkoutShareCardRenderError: Error {
    case pngEncodingFailed
}

enum WorkoutShareCardRenderer {

    /// Renders the card at `scale: 3`, giving the specced 1080 × 1920.
    ///
    /// `@MainActor` because `ImageRenderer` is main-actor-bound. Returns `nil` rather than
    /// throwing: a failed render should drop the share, not the workout.
    @MainActor
    static func render(
        data: WorkoutShareCardData,
        style: WorkoutShareCardStyle = .record,
        hidesExerciseList: Bool,
        hidesWeights: Bool
    ) -> UIImage? {
        let card = WorkoutShareCard(
            data: data,
            style: style,
            hidesExerciseList: hidesExerciseList,
            hidesWeights: hidesWeights
        )

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Writes the card as a PNG the recipient can actually read the name of.
    ///
    /// Sharing an in-memory `Image` works, but it arrives anonymous: saved to Files or attached
    /// to Mail it lands as a generic name, and a few share extensions are fussier about a
    /// SwiftUI `Image` than about a file URL. A real file costs one write and fixes both.
    ///
    /// PNG rather than JPEG on purpose — the card is flat colour and type, so it encodes
    /// *smaller* than JPEG and stays lossless, which matters when the destination is going to
    /// recompress it anyway.
    static func writePNG(_ image: UIImage, title: String, dateLabel: String) throws -> URL {
        guard let data = image.pngData() else {
            throw WorkoutShareCardRenderError.pngEncodingFailed
        }

        let directory = scratchDirectory
        // One export at a time: the previous file is dead the moment a new card is rendered,
        // and the share sheet that might still hold it is already gone.
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(fileName(title: title, dateLabel: dateLabel))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// "Repster-Push-Day-A-Sat-Aug-30.png".
    ///
    /// The title is user content, so it is stripped of anything that has meaning in a path and
    /// capped before it becomes one. An empty or hostile title degrades to plain "Repster".
    static func fileName(title: String, dateLabel: String) -> String {
        func slug(_ value: String) -> String {
            let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|,.")
                .union(.newlines)
                .union(.controlCharacters)
                .union(.whitespaces)
            return value
                .components(separatedBy: forbidden)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        }

        let parts = ["Repster", slug(title), slug(dateLabel)].filter { !$0.isEmpty }
        return String(parts.joined(separator: "-").prefix(80)) + ".png"
    }

    private static var scratchDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareCards", isDirectory: true)
    }
}

// MARK: - Previews

#Preview("PR") {
    WorkoutShareCard(data: .preview)
}

#Preview("Weights hidden") {
    WorkoutShareCard(data: .preview, hidesWeights: true)
}

extension WorkoutShareCardData {
    static var preview: WorkoutShareCardData {
        let bench = Lift(id: UUID(), name: "Barbell Bench Press", detail: "92.5 kg × 5", setCountLabel: "4 sets")
        return WorkoutShareCardData(
            title: "Push Day A",
            dateLabel: "Sat, Aug 30",
            durationLabel: "1h 4m",
            setCountLabel: "18",
            volumeLabel: "12,450 kg",
            liftCountLabel: "5",
            prLift: bench,
            lifts: [
                bench,
                Lift(id: UUID(), name: "Overhead Press", detail: "55 kg × 8", setCountLabel: "4 sets"),
                Lift(id: UUID(), name: "Incline Dumbbell Press", detail: "30 kg × 10", setCountLabel: "3 sets")
            ],
            extraLiftCount: 2
        )
    }
}

// MARK: - Preview sheet

/// The share flow: see the card, decide what it shows, then hand it to the system sheet.
///
/// The two toggles are B4's, and they persist — this is the audience that will notice their
/// squat number is on the card and quietly not post it, and the choice should be made once.
struct WorkoutSharePreviewSheet: View {

    let data: WorkoutShareCardData

    @Environment(\.dismiss) private var dismiss
    @State private var hidesExerciseList = WorkoutShareCardPreferences.hidesExerciseList
    @State private var hidesWeights = WorkoutShareCardPreferences.hidesWeights
    @State private var rendered: UIImage?
    @State private var fileURL: URL?
    @State private var style: WorkoutShareCardStyle = WorkoutShareCardPreferences.style
    @State private var saveState: SaveState = .idle
    @State private var showPhotosDeniedAlert = false

    private enum SaveState: Equatable {
        case idle, saving, saved
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // The card is a fixed 360 × 640 because that is what gets exported, so it is
            // scaled to whatever is left after the toggles rather than allowed to push them
            // off the bottom of the sheet.
            VStack(spacing: 16) {
                GeometryReader { proxy in
                    let scale = min(proxy.size.width / WorkoutShareCard.size.width,
                                    proxy.size.height / WorkoutShareCard.size.height)

                    if styles.count > 1 {
                        TabView(selection: $style) {
                            ForEach(styles) { candidate in
                                card(style: candidate, scale: scale)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .tag(candidate)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    } else {
                        card(style: style, scale: scale)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                if styles.count > 1 {
                    styleBar
                }

                toggles
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)

            shareBar
        }
        .background(Color.bg.ignoresSafeArea())
        .task(id: RenderKey(style: style, list: hidesExerciseList, weights: hidesWeights)) {
            await refreshRender()
        }
        .onAppear {
            // A remembered style the session cannot fill would leave the picker on a blank card.
            if !styles.contains(style) { style = styles[0] }
        }
        .onChange(of: style) { _, value in
            WorkoutShareCardPreferences.style = value
        }
    }

    /// Re-render only when something that affects the image changes.
    private struct RenderKey: Equatable {
        let style: WorkoutShareCardStyle
        let list: Bool
        let weights: Bool
    }

    private var header: some View {
        ZStack {
            Text("Share")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.bgInput)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.border).frame(height: 1)
        }
    }

    /// Styles this session can actually fill, with the remembered one guaranteed present.
    private var styles: [WorkoutShareCardStyle] {
        let available = data.availableStyles
        return available.isEmpty ? [.record] : available
    }

    /// A row of names under the card, so the choice is visible rather than only discoverable
    /// by swiping.
    private var styleBar: some View {
        HStack(spacing: 8) {
            ForEach(styles) { candidate in
                let isSelected = candidate == style

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { style = candidate }
                } label: {
                    Text(candidate.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(isSelected ? Color.accent : Color.bgInput)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(candidate.displayName) card")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func card(style: WorkoutShareCardStyle, scale: CGFloat) -> some View {
        WorkoutShareCard(
            data: data,
            style: style,
            hidesExerciseList: hidesExerciseList,
            hidesWeights: hidesWeights
        )
        .scaleEffect(scale, anchor: .center)
        .frame(
            width: WorkoutShareCard.size.width * scale,
            height: WorkoutShareCard.size.height * scale
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityHidden(true)
    }

    private var toggles: some View {
        VStack(spacing: 0) {
            privacyRow(
                icon: "list.bullet",
                title: "Hide exercise list",
                subtitle: "Leave just the headline and the stats",
                isOn: $hidesExerciseList
            ) { WorkoutShareCardPreferences.hidesExerciseList = $0 }

            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
                .padding(.leading, 46)

            privacyRow(
                icon: "eye.slash",
                title: "Hide weights",
                subtitle: "Keep the lifts, drop the numbers",
                isOn: $hidesWeights
            ) { WorkoutShareCardPreferences.hidesWeights = $0 }
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }

    private func privacyRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isOn.wrappedValue ? .accent : .textTertiary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.accent)
                .onChange(of: isOn.wrappedValue) { _, value in onChange(value) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var shareBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.border).frame(height: 1)

            VStack(spacing: 10) {
                // Photos is where most of these end up, so it gets its own tap rather than
                // living three rows down someone else's share sheet.
                Button {
                    Task { await saveToPhotos() }
                } label: {
                    saveToPhotosLabel
                }
                .buttonStyle(.plain)
                .disabled(rendered == nil || saveState != .idle)

                Group {
                    if let fileURL, let rendered {
                        ShareLink(
                            item: WorkoutShareCardFile(url: fileURL),
                            preview: SharePreview(data.title, image: Image(uiImage: rendered))
                        ) {
                            shareLabel(enabled: true)
                        }
                    } else {
                        shareLabel(enabled: false)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.bg)
        .alert("Photos access is off", isPresented: $showPhotosDeniedAlert) {
            Button("Not now", role: .cancel) { }
            if let settings = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(settings) }
            }
        } message: {
            Text("Repster needs permission to add images to your photo library. You can still use Share to send the card anywhere else.")
        }
    }

    private var saveToPhotosLabel: some View {
        HStack(spacing: 8) {
            switch saveState {
            case .idle:
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                Text("Save to Photos")
                    .font(.system(size: 16, weight: .semibold))
            case .saving:
                ProgressView().tint(.accent)
                Text("Saving…")
                    .font(.system(size: 16, weight: .semibold))
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Saved to Photos")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundColor(saveState == .saved ? .success : .accent)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(saveState == .saved ? Color.successSoft : Color.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((saveState == .saved ? Color.success : Color.accent).opacity(0.30), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.18), value: saveState)
    }

    private func saveToPhotos() async {
        guard let rendered else { return }
        saveState = .saving

        switch await WorkoutShareCardPhotoSaver.save(rendered) {
        case .saved:
            saveState = .saved
            // Settle back so a second save is possible without reopening the sheet.
            try? await Task.sleep(for: .seconds(2))
            if saveState == .saved { saveState = .idle }
        case .denied:
            saveState = .idle
            showPhotosDeniedAlert = true
        case .failed:
            saveState = .idle
        }
    }

    private func shareLabel(enabled: Bool) -> some View {
        HStack(spacing: 8) {
            if !enabled {
                ProgressView().tint(.white)
            }
            Text(enabled ? "Share" : "Preparing…")
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(enabled ? Color.accent : Color.accent.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @MainActor
    private func refreshRender() async {
        let image = WorkoutShareCardRenderer.render(
            data: data,
            style: style,
            hidesExerciseList: hidesExerciseList,
            hidesWeights: hidesWeights
        )
        rendered = image

        guard let image else {
            fileURL = nil
            return
        }

        fileURL = try? WorkoutShareCardRenderer.writePNG(
            image,
            title: data.title,
            dateLabel: data.dateLabel
        )
    }
}
