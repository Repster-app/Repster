// DesignTokens.swift
// Centralized design-system color tokens for the entire app.
// Source: design-system.md Section 2 (Colors), Section 5 (Corner Radii)
//
// All views reference these tokens instead of raw hex values.
// Naming follows design-system.md conventions: accent/success/gold/danger
// to avoid collisions with SwiftUI's built-in .blue/.green/.red.

import SwiftUI

// MARK: - Color Tokens

extension Color {

    // MARK: - Backgrounds (darkest -> lightest)

    /// #111113 — Screen background, root view
    static let bg = Color(red: 0.067, green: 0.067, blue: 0.075)

    /// #1B1B1F — Cards, table containers, nav items
    static let bgCard = Color(red: 0.106, green: 0.106, blue: 0.122)

    /// #222228 — Pressed/highlighted state for cards
    static let bgHover = Color(red: 0.133, green: 0.133, blue: 0.157)

    /// #262630 — Set number badges, progress bar tracks, tags
    static let bgSubtle = Color(red: 0.149, green: 0.149, blue: 0.188)

    /// #1F1F25 — Text input field backgrounds
    static let bgInput = Color(red: 0.122, green: 0.122, blue: 0.145)

    // MARK: - Text

    /// #EAEAEF — Primary text, headings, values
    static let textPrimary = Color(red: 0.918, green: 0.918, blue: 0.937)

    /// #9999A8 — Secondary text, descriptions
    static let textSecondary = Color(red: 0.600, green: 0.600, blue: 0.659)

    /// #5C5C6E — Tertiary text, labels, placeholders
    static let textTertiary = Color(red: 0.361, green: 0.361, blue: 0.431)

    // MARK: - Accent Colors

    /// #5B8DEF — Primary actions, active states, links
    static let accent = Color(red: 0.357, green: 0.553, blue: 0.937)

    /// Blue at 10% opacity — Match badge background
    static let accentSoft = accent.opacity(0.10)

    /// #5EC269 — Completed states, positive trends
    static let success = Color(red: 0.369, green: 0.761, blue: 0.412)

    /// Green at 8% opacity — Completed row background
    static let successSoft = success.opacity(0.08)

    /// #D4A23A — PR badges, warmup indicators
    static let gold = Color(red: 0.831, green: 0.635, blue: 0.227)

    /// Gold at 10% opacity — PR badge background
    static let goldSoft = gold.opacity(0.10)

    /// #E05555 — Negative trends, delete actions
    static let danger = Color(red: 0.878, green: 0.333, blue: 0.333)

    /// Red at 8% opacity — Destructive action background
    static let dangerSoft = danger.opacity(0.08)

    // MARK: - RIR Intensity Colors (red = hard → green = easy)

    /// #E89B3E — Warning / note indicators
    static let orange = Color(red: 0.910, green: 0.608, blue: 0.243)

    /// RIR 0 — Failure, hardest intensity
    static let rir0 = Color(red: 0.878, green: 0.333, blue: 0.333)   // #E05555

    /// RIR 1 — Very hard
    static let rir1 = Color(red: 0.878, green: 0.439, blue: 0.251)   // #E07040

    /// RIR 2 — Hard
    static let rir2 = Color(red: 0.910, green: 0.608, blue: 0.243)   // #E89B3E

    /// RIR 3 — Moderate
    static let rir3 = Color(red: 0.831, green: 0.635, blue: 0.227)   // #D4A23A

    /// RIR 4 — Comfortable
    static let rir4 = Color(red: 0.627, green: 0.722, blue: 0.235)   // #A0B83C

    /// RIR 5+ — Easy
    static let rir5 = Color(red: 0.369, green: 0.761, blue: 0.412)   // #5EC269

    /// Returns the RIR color for a given RIR value (0–5+).
    static func rirColor(for value: Double?) -> Color {
        guard let v = value else { return .textTertiary }
        switch v {
        case 0:         return .rir0
        case 1:         return .rir1
        case 2:         return .rir2
        case 3:         return .rir3
        case 4:         return .rir4
        default:        return .rir5  // 5+
        }
    }

    // MARK: - Chart Palette (charts-tab-v2)

    /// #A87EE6 — Chart color 5 (purple)
    static let chart5 = Color(red: 0.659, green: 0.494, blue: 0.902)

    /// #E89B3E — Chart color 6 (orange) — same hue as .orange token
    static let chart6 = Color(red: 0.910, green: 0.608, blue: 0.243)

    /// #4ECDC4 — Chart color 7 (teal)
    static let chart7 = Color(red: 0.306, green: 0.804, blue: 0.769)

    /// #FF6B9D — Chart color 8 (pink)
    static let chart8 = Color(red: 1.0, green: 0.420, blue: 0.616)

    /// Standard 8-color palette for charts: accent, success, gold, danger, purple, orange, teal, pink
    static let chartPalette: [Color] = [.accent, .success, .gold, .danger, .chart5, .chart6, .chart7, .chart8]

    // MARK: - Border

    /// White at 6% opacity — Input borders, dividers
    static let border = Color.white.opacity(0.06)
}
