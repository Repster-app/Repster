#!/usr/bin/env swift

import AppKit
import Foundation

struct Shot {
    let number: Int
    let slug: String
    let title: String
    let subtitle: String
    let source: String
    let note: String?
}

struct VideoCover {
    let number: Int
    let hook: String
    let caption: String
    let source: String
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let sourceRoot = root.appendingPathComponent("marketing/source")
let outputRoot = root.appendingPathComponent("marketing/generated")

let shots: [Shot] = [
    Shot(
        number: 1,
        slug: "log-sets-without-slowing-down",
        title: "Log sets without slowing down",
        subtitle: "Weights, reps, RIR, warmups, and rest stay one tap away.",
        source: "screenshots/active-sets.png",
        note: nil
    ),
    Shot(
        number: 2,
        slug: "start-from-your-saved-routines",
        title: "Start from your saved routines",
        subtitle: "Templates keep recurring sessions ready to launch.",
        source: "screenshots/site-templates.png",
        note: nil
    ),
    Shot(
        number: 3,
        slug: "know-what-you-did-last-time",
        title: "Know what you did last time",
        subtitle: "Previous sets and PR context stay inside the workout.",
        source: "screenshots/active-history.png",
        note: nil
    ),
    Shot(
        number: 4,
        slug: "track-prs-automatically",
        title: "Track PRs automatically",
        subtitle: "Recent records surface without keeping a spreadsheet.",
        source: "screenshots/site-home.png",
        note: nil
    ),
    Shot(
        number: 5,
        slug: "see-progress-beyond-one-workout",
        title: "See progress beyond one workout",
        subtitle: "Volume, sets, reps, and category breakdowns at a glance.",
        source: "screenshots/site-charts.png",
        note: nil
    ),
    Shot(
        number: 6,
        slug: "import-history-and-keep-control",
        title: "Import history and keep control",
        subtitle: "Bring training data forward, then export backups when needed.",
        source: "screenshots/active-chart.png",
        note: "Draft frame: replace the source with an import or backup screen capture before App Store submission."
    )
]

let videoCovers: [VideoCover] = [
    VideoCover(number: 1, hook: "Your lifting log should remember this for you.", caption: "Previous sets, PRs, and rest timing stay in the workout.", source: "screenshots/active-history.png"),
    VideoCover(number: 2, hook: "Your lifting log should remember this for you.", caption: "Know what you lifted last time before the next set.", source: "screenshots/active-history.png"),
    VideoCover(number: 3, hook: "Your lifting log should remember this for you.", caption: "Stop rebuilding context between every session.", source: "screenshots/site-home.png"),
    VideoCover(number: 4, hook: "Start your next workout from a template in seconds.", caption: "Tap a saved routine and get back to training.", source: "screenshots/site-templates.png"),
    VideoCover(number: 5, hook: "Start your next workout from a template in seconds.", caption: "Push, pull, legs, full body, or your own split.", source: "screenshots/site-templates.png"),
    VideoCover(number: 6, hook: "Start your next workout from a template in seconds.", caption: "Less setup. More lifting.", source: "screenshots/site-templates.png"),
    VideoCover(number: 7, hook: "Stop guessing what you lifted last time.", caption: "See previous sets without leaving the active workout.", source: "screenshots/active-history.png"),
    VideoCover(number: 8, hook: "Stop guessing what you lifted last time.", caption: "PR context is available where you log the set.", source: "screenshots/active-sets.png"),
    VideoCover(number: 9, hook: "Stop guessing what you lifted last time.", caption: "History stays useful while you train.", source: "screenshots/active-history.png"),
    VideoCover(number: 10, hook: "PRs and charts without maintaining a spreadsheet.", caption: "Repster turns logged sets into records and progress views.", source: "screenshots/site-charts.png"),
    VideoCover(number: 11, hook: "PRs and charts without maintaining a spreadsheet.", caption: "See volume, reps, sets, and training distribution.", source: "screenshots/site-charts.png"),
    VideoCover(number: 12, hook: "PRs and charts without maintaining a spreadsheet.", caption: "Track progress beyond one workout.", source: "screenshots/active-chart.png")
]

let background = color(hex: "#0d0e12")
let card = color(hex: "#171820")
let accent = color(hex: "#5b8def")
let accentDark = color(hex: "#2354c9")
let text = color(hex: "#f5f6fb")
let muted = color(hex: "#a8a8ba")
let line = color(hex: "#2c2d37")

try ensureDirectory(outputRoot.appendingPathComponent("app-store"))
try ensureDirectory(outputRoot.appendingPathComponent("social/static"))
try ensureDirectory(outputRoot.appendingPathComponent("social/video-covers"))

for shot in shots {
    try renderAppStoreShot(shot)
    try renderStaticPost(shot)
}

for cover in videoCovers {
    try renderVideoCover(cover)
}

print("Rendered \(shots.count) App Store screenshots, \(shots.count) social static posts, and \(videoCovers.count) video cover frames.")

func renderAppStoreShot(_ shot: Shot) throws {
    let size = CGSize(width: 1320, height: 2868)
    let image = try render(size: size) { rect in
        drawBackground(rect)
        drawBrandMark(in: CGRect(x: 940, y: 104, width: 220, height: 64), compact: false)
        drawPill("iOS workout tracking", rect: CGRect(x: 140, y: 112, width: 360, height: 56), fill: color(hex: "#1d2332"))
        drawMultiline(
            shot.title,
            rect: CGRect(x: 140, y: 202, width: 1040, height: 190),
            font: .systemFont(ofSize: 76, weight: .bold),
            color: text,
            lineHeight: 84
        )
        drawMultiline(
            shot.subtitle,
            rect: CGRect(x: 140, y: 396, width: 980, height: 86),
            font: .systemFont(ofSize: 34, weight: .medium),
            color: muted,
            lineHeight: 42
        )

        let phoneRect = CGRect(x: 140, y: 572, width: 1040, height: 2260)
        drawDeviceImage(sourcePath: shot.source, in: phoneRect, cornerRadius: 72)
    }

    let output = outputRoot.appendingPathComponent("app-store/\(String(format: "%02d", shot.number))-\(shot.slug).png")
    try writePNG(image, to: output)
}

func renderStaticPost(_ shot: Shot) throws {
    let size = CGSize(width: 1080, height: 1350)
    let image = try render(size: size) { rect in
        drawBackground(rect)
        drawBrandMark(in: CGRect(x: 80, y: 84, width: 220, height: 64), compact: false)
        drawMultiline(
            shot.title,
            rect: CGRect(x: 80, y: 188, width: 920, height: 170),
            font: .systemFont(ofSize: 62, weight: .bold),
            color: text,
            lineHeight: 70
        )
        drawMultiline(
            shot.subtitle,
            rect: CGRect(x: 80, y: 364, width: 820, height: 82),
            font: .systemFont(ofSize: 29, weight: .medium),
            color: muted,
            lineHeight: 36
        )

        drawRoundedRect(CGRect(x: 80, y: 500, width: 920, height: 768), radius: 44, fill: card)
        drawDeviceImage(sourcePath: shot.source, in: CGRect(x: 250, y: 540, width: 580, height: 1260), cornerRadius: 48)
        drawPill("Workout Tracking for Lifters", rect: CGRect(x: 280, y: 1190, width: 520, height: 58), fill: color(hex: "#20283a"))
    }

    let output = outputRoot.appendingPathComponent("social/static/static-\(String(format: "%02d", shot.number))-\(shot.slug).png")
    try writePNG(image, to: output)
}

func renderVideoCover(_ cover: VideoCover) throws {
    let size = CGSize(width: 1080, height: 1920)
    let image = try render(size: size) { rect in
        drawBackground(rect)
        drawBrandMark(in: CGRect(x: 76, y: 86, width: 220, height: 64), compact: false)
        drawMultiline(
            cover.hook,
            rect: CGRect(x: 76, y: 220, width: 928, height: 270),
            font: .systemFont(ofSize: 66, weight: .bold),
            color: text,
            lineHeight: 74
        )
        drawMultiline(
            cover.caption,
            rect: CGRect(x: 76, y: 512, width: 840, height: 100),
            font: .systemFont(ofSize: 31, weight: .medium),
            color: muted,
            lineHeight: 39
        )

        drawRoundedRect(CGRect(x: 80, y: 680, width: 920, height: 1116), radius: 44, fill: card)
        drawDeviceImage(sourcePath: cover.source, in: CGRect(x: 238, y: 720, width: 604, height: 1314), cornerRadius: 52)
        drawPill("Repster", rect: CGRect(x: 378, y: 1728, width: 324, height: 62), fill: color(hex: "#20283a"))
    }

    let output = outputRoot.appendingPathComponent("social/video-covers/video-cover-\(String(format: "%02d", cover.number)).png")
    try writePNG(image, to: output)
}

func drawBackground(_ rect: CGRect) {
    background.setFill()
    NSBezierPath(rect: rect).fill()

    let glowPath = NSBezierPath(ovalIn: CGRect(x: rect.width - 560, y: -240, width: 720, height: 720))
    color(hex: "#14264d", alpha: 0.46).setFill()
    glowPath.fill()

    let glowPath2 = NSBezierPath(ovalIn: CGRect(x: -280, y: rect.height - 420, width: 560, height: 560))
    color(hex: "#1a253f", alpha: 0.34).setFill()
    glowPath2.fill()
}

func drawBrandMark(in rect: CGRect, compact: Bool) {
    guard let logo = loadImage("logo/repster-logo.png") else { return }
    let iconRect = CGRect(x: rect.minX, y: rect.minY, width: rect.height, height: rect.height)
    drawRoundedRect(iconRect, radius: 16, fill: color(hex: "#15171f"))
    logo.draw(in: iconRect.insetBy(dx: 8, dy: 8).flippedY(), from: .zero, operation: .sourceOver, fraction: 1)
    if !compact {
        drawText(
            "Repster",
            rect: CGRect(x: iconRect.maxX + 18, y: rect.minY + 9, width: rect.width - rect.height - 18, height: rect.height),
            font: .systemFont(ofSize: 34, weight: .bold),
            color: text,
            alignment: .left
        )
    }
}

func drawPill(_ value: String, rect: CGRect, fill: NSColor) {
    drawRoundedRect(rect, radius: rect.height / 2, fill: fill)
    drawText(
        value,
        rect: rect.insetBy(dx: 26, dy: 8),
        font: .systemFont(ofSize: min(28, rect.height * 0.42), weight: .semibold),
        color: text,
        alignment: .center
    )
}

func drawDeviceImage(sourcePath: String, in rect: CGRect, cornerRadius: CGFloat) {
    guard let image = loadImage(sourcePath) else {
        drawRoundedRect(rect, radius: cornerRadius, fill: color(hex: "#111217"))
        drawText(
            "Missing source:\n\(sourcePath)",
            rect: rect.insetBy(dx: 48, dy: 48),
            font: .systemFont(ofSize: 28, weight: .semibold),
            color: muted,
            alignment: .center
        )
        return
    }

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = 42
    shadow.shadowOffset = CGSize(width: 0, height: -18)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    drawRoundedRect(rect, radius: cornerRadius, fill: NSColor.black.withAlphaComponent(0.5))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    let targetRect = rect.flippedY()
    let path = NSBezierPath(roundedRect: targetRect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()
    image.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    drawRoundedStroke(rect, radius: cornerRadius, stroke: line, lineWidth: 2)
}

func drawText(_ value: String, rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    value.draw(in: rect.flippedY(), withAttributes: attributes)
}

func drawMultiline(_ value: String, rect: CGRect, font: NSFont, color: NSColor, lineHeight: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    value.draw(in: rect.flippedY(), withAttributes: attributes)
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
    let red = CGFloat((int >> 16) & 0xff) / 255
    let green = CGFloat((int >> 8) & 0xff) / 255
    let blue = CGFloat(int & 0xff) / 255
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
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
