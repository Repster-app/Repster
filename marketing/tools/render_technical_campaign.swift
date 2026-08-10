#!/usr/bin/env swift

// Technical-lifter campaign renderer.
//
// Separate from render_marketing_assets.swift on purpose: that script renders the
// launch kit ("fast lifting log"), this one renders the depth-positioning test
// ("the engine under Smart Suggestions"). They share the brand system and the same
// source screenshots but not the layout grammar.
//
// The layout difference is deliberate. The launch kit shows a whole phone; at
// Reddit/Instagram feed scale that makes every number on the screen illegible,
// which is fatal for creative whose entire argument is the numbers. Here each
// frame shows a magnified crop of the real UI instead.
//
// Run from the repository root:
//   mkdir -p .build/module-cache
//   CLANG_MODULE_CACHE_PATH=.build/module-cache swift marketing/tools/render_technical_campaign.swift

import AppKit
import Foundation

/// Normalized crop rect into a source screenshot, origin top-left, values 0...1.
struct Crop {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
}

struct Concept {
    let number: Int
    let slug: String
    let headline: String
    let subline: String
    /// Accent line under the crop. Names what the reader is looking at.
    let annotation: String
    let source: String
    let crop: Crop
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let sourceRoot = root.appendingPathComponent("marketing/source")
let outputRoot = root.appendingPathComponent("marketing/generated/campaigns/technical-lifter")

// Crops were measured against the 1206 x 2622 source captures. They are normalized,
// so re-capturing at a different device size keeps them roughly valid, but any
// re-capture should be spot-checked against the rendered output.
let concepts: [Concept] = [
    Concept(
        number: 1,
        slug: "what-set-three-cost-you",
        headline: "It knows what set three cost you.",
        subline: "Fatigue accumulates set by set and decays with the rest you actually took. The suggested load moves with it.",
        annotation: "Every set priced from its own rep and RIR target.",
        source: "screenshots/active-sets.png",
        crop: Crop(x: 0.03, y: 0.617, w: 0.94, h: 0.312)
    ),
    Concept(
        number: 2,
        slug: "rest-is-an-input",
        headline: "Your rest timer is an input, not a stopwatch.",
        subline: "Fatigue decays exponentially with the rest you actually take. Cut it short and the next target reflects it.",
        annotation: "Rest feeds the model that sets your next load.",
        source: "screenshots/active-history.png",
        crop: Crop(x: 0.02, y: 0.825, w: 0.96, h: 0.155)
    ),
    Concept(
        number: 3,
        slug: "rir-is-a-column",
        headline: "RIR is a column, not an afterthought.",
        subline: "Weight, reps, and RIR in one row. All three feed the load model, and warmups stay out of it.",
        annotation: "Warmup sets excluded from every estimate.",
        source: "screenshots/active-sets.png",
        crop: Crop(x: 0.03, y: 0.255, w: 0.94, h: 0.325)
    ),
    Concept(
        number: 4,
        slug: "e1rm-from-your-top-sets",
        headline: "e1RM from your top sets. Not a guess.",
        subline: "Capacity is estimated from peak sets across your recent workouts, so one bad session doesn't reset your numbers.",
        annotation: "Peak across recent sessions, not just the last one.",
        source: "screenshots/active-history.png",
        crop: Crop(x: 0.02, y: 0.262, w: 0.96, h: 0.262)
    )
]

let background = color(hex: "#0d0e12")
let card = color(hex: "#171820")
let accent = color(hex: "#5b8def")
let text = color(hex: "#f5f6fb")
let muted = color(hex: "#a8a8ba")
let line = color(hex: "#2c2d37")

try ensureDirectory(outputRoot.appendingPathComponent("feed-1080x1350"))
try ensureDirectory(outputRoot.appendingPathComponent("vertical-1080x1920"))
try ensureDirectory(outputRoot.appendingPathComponent("wide-1200x628"))

for concept in concepts {
    try renderFeed(concept)
    try renderVertical(concept)
    try renderWide(concept)
}

print("Rendered \(concepts.count) concepts x 3 formats = \(concepts.count * 3) frames into marketing/generated/campaigns/technical-lifter/")

// MARK: - Formats

/// 1080 x 1350 — Instagram feed, Reddit image post.
func renderFeed(_ concept: Concept) throws {
    let image = try render(size: CGSize(width: 1080, height: 1350)) { rect in
        drawBackground(rect)
        drawBrandMark(in: CGRect(x: 72, y: 76, width: 220, height: 60))
        drawPill("Smart Suggestions", rect: CGRect(x: 72, y: 172, width: 320, height: 52), fill: color(hex: "#1d2332"))

        let headlineFont = NSFont.systemFont(ofSize: 62, weight: .bold)
        let sublineFont = NSFont.systemFont(ofSize: 28, weight: .medium)
        let headlineHeight = textHeight(concept.headline, font: headlineFont, width: 936, lineHeight: 70)
        let sublineHeight = textHeight(concept.subline, font: sublineFont, width: 880, lineHeight: 37)

        drawMultiline(
            concept.headline,
            rect: CGRect(x: 72, y: 256, width: 936, height: headlineHeight),
            font: headlineFont,
            color: text,
            lineHeight: 70
        )
        let sublineTop = 256 + headlineHeight + 36
        drawMultiline(
            concept.subline,
            rect: CGRect(x: 72, y: sublineTop, width: 880, height: sublineHeight),
            font: sublineFont,
            color: muted,
            lineHeight: 37
        )

        // Card, annotation and footer travel together, centred in what's left.
        let blockTop = sublineTop + sublineHeight + 40
        let available = 1290 - blockTop
        let cardHeight = fittedCardHeight(concept, width: 936, maxHeight: available - 120)
        let cardTop = blockTop + max(0, (available - (cardHeight + 120)) / 2)

        drawCrop(concept, in: CGRect(x: 72, y: cardTop, width: 936, height: cardHeight))
        drawAnnotation(concept.annotation, at: CGRect(x: 72, y: cardTop + cardHeight + 34, width: 936, height: 40))
        drawFooter(rect: CGRect(x: 72, y: cardTop + cardHeight + 96, width: 936, height: 36))
    }
    try writePNG(image, to: outputRoot.appendingPathComponent("feed-1080x1350/\(name(concept)).png"))
}

/// 1080 x 1920 — TikTok / Reels / Stories cover frame.
func renderVertical(_ concept: Concept) throws {
    let image = try render(size: CGSize(width: 1080, height: 1920)) { rect in
        drawBackground(rect)
        drawBrandMark(in: CGRect(x: 76, y: 116, width: 220, height: 60))

        let headlineFont = NSFont.systemFont(ofSize: 68, weight: .bold)
        let sublineFont = NSFont.systemFont(ofSize: 30, weight: .medium)
        let headlineHeight = textHeight(concept.headline, font: headlineFont, width: 928, lineHeight: 78)
        let sublineHeight = textHeight(concept.subline, font: sublineFont, width: 880, lineHeight: 39)

        drawMultiline(
            concept.headline,
            rect: CGRect(x: 76, y: 252, width: 928, height: headlineHeight),
            font: headlineFont,
            color: text,
            lineHeight: 78
        )
        let sublineTop = 252 + headlineHeight + 44
        drawMultiline(
            concept.subline,
            rect: CGRect(x: 76, y: sublineTop, width: 880, height: sublineHeight),
            font: sublineFont,
            color: muted,
            lineHeight: 39
        )

        // Bottom third of a vertical frame is covered by platform UI, so the card
        // group is centred between the copy and y=1640 rather than the canvas edge.
        let blockTop = sublineTop + sublineHeight + 48
        let available = 1640 - blockTop
        let cardHeight = fittedCardHeight(concept, width: 928, maxHeight: available - 80)
        let cardTop = blockTop + max(0, (available - (cardHeight + 80)) / 2)

        drawCrop(concept, in: CGRect(x: 76, y: cardTop, width: 928, height: cardHeight))
        drawAnnotation(concept.annotation, at: CGRect(x: 76, y: cardTop + cardHeight + 36, width: 928, height: 44))
        drawPill("Repster — iOS", rect: CGRect(x: 378, y: 1732, width: 324, height: 64), fill: color(hex: "#20283a"))
    }
    try writePNG(image, to: outputRoot.appendingPathComponent("vertical-1080x1920/\(name(concept)).png"))
}

/// 1200 x 628 — Reddit link post / wide placements.
func renderWide(_ concept: Concept) throws {
    let image = try render(size: CGSize(width: 1200, height: 628)) { rect in
        drawBackground(rect)
        drawBrandMark(in: CGRect(x: 64, y: 54, width: 200, height: 52))

        let headlineFont = NSFont.systemFont(ofSize: 46, weight: .bold)
        let sublineFont = NSFont.systemFont(ofSize: 22, weight: .medium)
        let headlineHeight = textHeight(concept.headline, font: headlineFont, width: 540, lineHeight: 54)
        let sublineHeight = textHeight(concept.subline, font: sublineFont, width: 512, lineHeight: 30)

        // Both columns are centred in the band below the brand mark, so a short
        // headline or a short crop doesn't leave the banner top-heavy.
        let bandTop: CGFloat = 130
        let bandHeight: CGFloat = 430

        let copyHeight = headlineHeight + 28 + sublineHeight
        let copyTop = bandTop + max(0, (bandHeight - copyHeight) / 2)
        drawMultiline(
            concept.headline,
            rect: CGRect(x: 64, y: copyTop, width: 540, height: headlineHeight),
            font: headlineFont,
            color: text,
            lineHeight: 54
        )
        drawMultiline(
            concept.subline,
            rect: CGRect(x: 64, y: copyTop + headlineHeight + 28, width: 512, height: sublineHeight),
            font: sublineFont,
            color: muted,
            lineHeight: 30
        )

        let cardHeight = fittedCardHeight(concept, width: 500, maxHeight: bandHeight - 76)
        let cardTop = bandTop + max(0, (bandHeight - (cardHeight + 76)) / 2)
        drawCrop(concept, in: CGRect(x: 636, y: cardTop, width: 500, height: cardHeight))
        drawAnnotation(
            concept.annotation,
            at: CGRect(x: 636, y: cardTop + cardHeight + 26, width: 500, height: 72),
            fontSize: 20,
            wrap: true
        )
    }
    try writePNG(image, to: outputRoot.appendingPathComponent("wide-1200x628/\(name(concept)).png"))
}

/// Height the crop card needs so it hugs its contents at the given width.
/// Without this a short, wide crop (the rest timer) sits marooned in a tall card.
func fittedCardHeight(_ concept: Concept, width: CGFloat, maxHeight: CGFloat) -> CGFloat {
    guard let image = loadImage(concept.source) else { return min(200, maxHeight) }
    let sourceWidth = concept.crop.w * image.size.width
    let sourceHeight = concept.crop.h * image.size.height
    let innerWidth = width - 36
    return min(innerWidth * (sourceHeight / sourceWidth) + 36, maxHeight)
}

func name(_ concept: Concept) -> String {
    "\(String(format: "%02d", concept.number))-\(concept.slug)"
}

// MARK: - Components

/// Draws a magnified, aspect-preserved crop of the source screenshot inside `box`,
/// on a card with an accent hairline. This is the whole point of the format: the
/// reader can actually read the numbers.
func drawCrop(_ concept: Concept, in box: CGRect) {
    drawRoundedRect(box, radius: 28, fill: card)

    guard let image = loadImage(concept.source) else {
        drawText(
            "Missing source: \(concept.source)",
            rect: box.insetBy(dx: 24, dy: box.height / 2 - 20),
            font: .systemFont(ofSize: 22, weight: .semibold),
            color: muted,
            alignment: .center
        )
        drawRoundedStroke(box, radius: 28, stroke: line, lineWidth: 2)
        return
    }

    let imageWidth = image.size.width
    let imageHeight = image.size.height

    // NSImage sampling space has a bottom-left origin; Crop is expressed top-left.
    let src = CGRect(
        x: concept.crop.x * imageWidth,
        y: (1 - concept.crop.y - concept.crop.h) * imageHeight,
        width: concept.crop.w * imageWidth,
        height: concept.crop.h * imageHeight
    )

    let inner = box.insetBy(dx: 18, dy: 18)
    let scale = min(inner.width / src.width, inner.height / src.height)
    let drawWidth = src.width * scale
    let drawHeight = src.height * scale
    let target = CGRect(
        x: inner.minX + (inner.width - drawWidth) / 2,
        y: inner.minY + (inner.height - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight
    )

    NSGraphicsContext.saveGraphicsState()
    let flipped = target.flippedY()
    NSBezierPath(roundedRect: flipped, xRadius: 16, yRadius: 16).addClip()
    image.draw(in: flipped, from: src, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    drawRoundedStroke(target, radius: 16, stroke: line, lineWidth: 2)
    drawRoundedStroke(box, radius: 28, stroke: color(hex: "#232a3a"), lineWidth: 2)
}

func drawAnnotation(_ value: String, at rect: CGRect, fontSize: CGFloat = 24, wrap: Bool = false) {
    let bullet = CGRect(x: rect.minX, y: rect.minY + 6, width: 10, height: fontSize - 2)
    drawRoundedRect(bullet, radius: 3, fill: accent)

    let textRect = CGRect(x: rect.minX + 26, y: rect.minY, width: rect.width - 26, height: rect.height)
    if wrap {
        drawMultiline(
            value,
            rect: textRect,
            font: .systemFont(ofSize: fontSize, weight: .semibold),
            color: accent,
            lineHeight: fontSize + 8
        )
    } else {
        drawText(
            value,
            rect: textRect,
            font: .systemFont(ofSize: fontSize, weight: .semibold),
            color: accent,
            alignment: .left
        )
    }
}

func drawFooter(rect: CGRect) {
    drawText(
        "Repster — workout tracking for lifters. iOS.",
        rect: rect,
        font: .systemFont(ofSize: 24, weight: .medium),
        color: muted,
        alignment: .left
    )
}

func drawBackground(_ rect: CGRect) {
    background.setFill()
    NSBezierPath(rect: rect).fill()

    let glow = NSBezierPath(ovalIn: CGRect(x: rect.width - 520, y: -260, width: 760, height: 760))
    color(hex: "#14264d", alpha: 0.46).setFill()
    glow.fill()

    let glow2 = NSBezierPath(ovalIn: CGRect(x: -300, y: rect.height - 400, width: 580, height: 580))
    color(hex: "#1a253f", alpha: 0.34).setFill()
    glow2.fill()
}

func drawBrandMark(in rect: CGRect) {
    guard let logo = loadImage("logo/repster-logo.png") else { return }
    let iconRect = CGRect(x: rect.minX, y: rect.minY, width: rect.height, height: rect.height)
    drawRoundedRect(iconRect, radius: 15, fill: color(hex: "#15171f"))
    logo.draw(in: iconRect.insetBy(dx: 8, dy: 8).flippedY(), from: .zero, operation: .sourceOver, fraction: 1)
    drawText(
        "Repster",
        rect: CGRect(x: iconRect.maxX + 18, y: rect.minY + 8, width: rect.width - rect.height - 18, height: rect.height),
        font: .systemFont(ofSize: 32, weight: .bold),
        color: text,
        alignment: .left
    )
}

func drawPill(_ value: String, rect: CGRect, fill: NSColor) {
    drawRoundedRect(rect, radius: rect.height / 2, fill: fill)
    drawText(
        value,
        rect: rect.insetBy(dx: 24, dy: 9),
        font: .systemFont(ofSize: min(26, rect.height * 0.42), weight: .semibold),
        color: text,
        alignment: .center
    )
}

// MARK: - Primitives

func drawText(_ value: String, rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    value.draw(in: rect.flippedY(), withAttributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ])
}

/// Measured height of wrapped text, so layout below it can flow instead of
/// sitting at a fixed offset sized for the longest headline.
func textHeight(_ value: String, font: NSFont, width: CGFloat, lineHeight: CGFloat) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
    let attributed = NSAttributedString(string: value, attributes: [
        .font: font,
        .paragraphStyle: paragraph
    ])
    let bounds = attributed.boundingRect(
        with: CGSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    return ceil(bounds.height)
}

func drawMultiline(_ value: String, rect: CGRect, font: NSFont, color: NSColor, lineHeight: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
    value.draw(in: rect.flippedY(), withAttributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ])
}

func drawRoundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect.flippedY(), xRadius: radius, yRadius: radius).fill()
}

func drawRoundedStroke(_ rect: CGRect, radius: CGFloat, stroke: NSColor, lineWidth: CGFloat) {
    stroke.setStroke()
    let path = NSBezierPath(roundedRect: rect.flippedY(), xRadius: radius, yRadius: radius)
    path.lineWidth = lineWidth
    path.stroke()
}

func loadImage(_ relativePath: String) -> NSImage? {
    NSImage(contentsOf: sourceRoot.appendingPathComponent(relativePath))
}

func render(size: CGSize, draw: (CGRect) throws -> Void) throws -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw RenderError.bitmapCreationFailed
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    try draw(CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ image: NSBitmapImageRep, to url: URL) throws {
    guard let data = image.representation(using: .png, properties: [:]) else {
        throw RenderError.pngEncodingFailed(url.path)
    }
    try data.write(to: url, options: .atomic)
}

func ensureDirectory(_ url: URL) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
}

func color(hex: String, alpha: CGFloat = 1) -> NSColor {
    let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    var int: UInt64 = 0
    Scanner(string: value).scanHexInt64(&int)
    return NSColor(
        calibratedRed: CGFloat((int >> 16) & 0xff) / 255,
        green: CGFloat((int >> 8) & 0xff) / 255,
        blue: CGFloat(int & 0xff) / 255,
        alpha: alpha
    )
}

extension CGRect {
    func flippedY() -> CGRect {
        guard let height = NSGraphicsContext.current?.cgContext.height else { return self }
        return CGRect(x: minX, y: CGFloat(height) - minY - self.height, width: width, height: self.height)
    }
}

enum RenderError: Error {
    case bitmapCreationFailed
    case pngEncodingFailed(String)
}
