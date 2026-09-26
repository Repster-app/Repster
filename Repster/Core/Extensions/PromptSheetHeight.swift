// PromptSheetHeight.swift
// Shared plumbing for the "ask before iOS asks" sheets (Apple Health, rest alarm).
//
// These sheets are one question with two answers, so they size themselves to their content
// instead of taking a fixed detent. A fixed `.medium` is what broke the rest-alarm prompt:
// the content was taller than the detent, so the one flexible view in the stack — the
// subtitle — absorbed the whole overflow and truncated, and the buttons were clipped away.
//
// The pattern: measure the scroll content and the button bar, sum them, and feed the total
// to `.presentationDetents([.height(...)])`, clamped by `promptDetentHeight`.

import SwiftUI

/// Sums the scroll content and the button bar, which together are the sheet's natural height.
struct PromptHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

extension View {
    /// Reports this view's height into `PromptHeightKey`. Apply to each stacked section.
    func measuringHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: PromptHeightKey.self, value: proxy.size.height)
            }
        )
    }
}

/// Floor keeps a short layout from looking like an error; ceiling keeps large Dynamic Type
/// from pinning the sheet to the top of the screen, and the ScrollView takes over from there.
func promptDetentHeight(for measured: CGFloat, minimum: CGFloat = 360, maximum: CGFloat = 640) -> CGFloat {
    min(max(measured + 16, minimum), maximum)
}
