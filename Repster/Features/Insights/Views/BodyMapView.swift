// BodyMapView.swift
// Front and back body figures for the Sides card, shaded per muscle region and side.
//
// Artwork: react-native-body-highlighter (MIT) — see BodyMapPaths.swift.
//
// THE MIRROR TRAP: the library's "left" and "right" are the VIEWER's, in both
// views. On the front view its "left" paths are the figure's RIGHT side. Every
// lookup goes through `librarySide(for:in:)` / `anatomicalSide(forLibrarySide:in:)`,
// and `SidesAnalysisTests` pins both directions. The map itself no longer shades by
// side (D21), but anything that ever does must go through these.

import SwiftUI

enum BodyView: Sendable {
    case front
    case back
}

/// Parsed once, then shared. Immutable after init, hence the unchecked conformance.
struct BodyMapGeometry: @unchecked Sendable {
    struct Region {
        let region: String
        /// The figure's side. Nil for parts drawn once across the midline (head, hair).
        let side: SideLean?
        let path: Path
    }

    let viewBox: CGRect
    let regions: [Region]
    let outline: Path

    static let front = BodyMapGeometry(view: .front)
    static let back = BodyMapGeometry(view: .back)

    static func geometry(for view: BodyView) -> BodyMapGeometry {
        view == .front ? front : back
    }

    private init(view: BodyView) {
        let raw = view == .front ? BodyMapPaths.front : BodyMapPaths.back
        viewBox = view == .front ? BodyMapPaths.frontViewBox : BodyMapPaths.backViewBox
        outline = Self.path(from: view == .front ? BodyMapPaths.frontOutline : BodyMapPaths.backOutline)
        regions = raw.map {
            Region(
                region: $0.region,
                side: Self.anatomicalSide(forLibrarySide: $0.side, in: view),
                path: Self.path(from: $0.d)
            )
        }
    }

    /// The library side that draws a figure's anatomical side.
    static func librarySide(for side: SideLean, in view: BodyView) -> String {
        switch (view, side) {
        case (.front, .left):  return "right"
        case (.front, .right): return "left"
        case (.back, .left):   return "left"
        case (.back, .right):  return "right"
        }
    }

    /// The figure's side for a library side; nil for "common".
    static func anatomicalSide(forLibrarySide side: String, in view: BodyView) -> SideLean? {
        switch side {
        case "left":  return view == .front ? .right : .left
        case "right": return view == .front ? .left : .right
        default:      return nil
        }
    }

    /// Parses the absolute `M / L / C / Q / Z` strings the generator emits. Nothing else is supported.
    static func path(from d: String) -> Path {
        var path = Path()
        let tokens = d.split(separator: " ")
        var index = 0

        func number() -> CGFloat {
            defer { index += 1 }
            guard index < tokens.count, let value = Double(tokens[index]) else { return 0 }
            return CGFloat(value)
        }

        func point() -> CGPoint {
            let x = number()
            let y = number()
            return CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M":
                path.move(to: point())
            case "L":
                path.addLine(to: point())
            case "C":
                let control1 = point()
                let control2 = point()
                let end = point()
                path.addCurve(to: end, control1: control1, control2: control2)
            case "Q":
                let control = point()
                let end = point()
                path.addQuadCurve(to: end, control: control)
            case "Z":
                path.closeSubpath()
            default:
                continue
            }
        }
        return path
    }

    /// Repster muscle groups a region can show, most specific first: a custom "glutes"
    /// group wins over the catalog's broad "legs" for the glute region.
    static let regionGroups: [String: [String]] = [
        "chest": ["chest"],
        "trapezius": ["back"],
        "upper-back": ["back"],
        "lower-back": ["back"],
        "deltoids": ["shoulders"],
        "biceps": ["biceps"],
        "triceps": ["triceps"],
        "forearm": ["forearms"],
        "abs": ["abs"],
        "obliques": ["abs"],
        "quadriceps": ["quads", "quadriceps", "legs"],
        "adductors": ["legs"],
        "gluteal": ["glutes", "legs"],
        "hamstring": ["hamstrings", "legs"],
        "calves": ["calves"],
        "tibialis": ["calves"],
    ]

    /// Parts of the figure that aren't muscles, so never carry a group.
    static let nonMuscleRegions: Set<String> = ["head", "hair", "neck", "hands", "feet", "knees", "ankles"]
}

/// Colours for a region, from the analysis (D21): whether its muscle group shows an
/// imbalance — never which side. Direction lives on each exercise in the deep dive.
enum SidesBodyFill {
    /// `statuses` is keyed by normalised group. `only` limits colour to one group — the deep-dive thumbnail.
    static func color(region: String, statuses: [String: SideGroupStatus], only: String? = nil) -> Color {
        if region == "hair" { return .bodyHair }
        guard let candidates = BodyMapGeometry.regionGroups[region],
              let group = candidates.first(where: { statuses[$0] != nil }),
              only == nil || only == group,
              let status = statuses[group]
        else { return .bodyBase }

        switch status {
        case .imbalance:
            return .sidesImbalance
        case .even:
            return .sidesEven
        // Unconfirmed: dim until it's confirmed or gone (D24).
        case .possible, .collecting:
            return .sidesCollecting
        }
    }
}

/// One figure, sized to its width. `fill` colours every region per anatomical side.
struct BodyFigure: View {
    let view: BodyView
    let fill: (_ region: String, _ side: SideLean?) -> Color

    var body: some View {
        let geometry = BodyMapGeometry.geometry(for: view)
        let box = geometry.viewBox
        Canvas { context, size in
            let scale = min(size.width / box.width, size.height / box.height)
            context.translateBy(
                x: (size.width - box.width * scale) / 2 - box.minX * scale,
                y: (size.height - box.height * scale) / 2 - box.minY * scale
            )
            context.scaleBy(x: scale, y: scale)
            for region in geometry.regions {
                context.fill(region.path, with: .color(fill(region.region, region.side)))
            }
            // Five viewBox units is about one point at card size.
            context.stroke(geometry.outline, with: .color(.bodyOutline), lineWidth: 5)
        }
        .aspectRatio(box.width / box.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
