// ReplayPrivacy.swift
// Which screens session replay is allowed to record legibly, and which values stay black
// wherever they appear.
//
// Background: PostHog does not blur, it fills each masked rect with opaque black
// (`RRWireframe.maskImage`). Against Repster's `#111113` background that is black on
// near-black, so a fully masked recording of a SwiftUI app is not a redacted screen —
// it's an unreadable one. The 1.4 recordings were unusable for exactly this reason.
//
// The global config in `AnalyticsService.configureSessionReplay` still masks everything by
// default, and that is the property worth keeping: a screen added next year is masked
// until somebody opts it in here. These two modifiers are the only way out and the only
// way back in, so the whole exposure surface is `grep -r replayVisible`.
//
// KEEP IN SYNC when the set of `replayVisible()` screens changes:
//   1. docs/privacy.html — the live policy at repster-app.github.io
//   2. marketing/app-store/privacy-review-checklist.md — App Review Notes field
//   3. Repster/Core/Services/AnalyticsService.swift — the doc comment on the config
//
// iOS 26 caveat: PostHog's own documentation on `postHogNoMask()` warns that under the
// Xcode 26 SwiftUI rendering engine, views may no longer map reliably to a backing
// `UIView`, so the modifier can behave inconsistently. It fails safe — an unrecognised
// subtree stays masked rather than leaking — so the failure mode is a screen that is
// still black, not one that shows more than it should.

import SwiftUI
import PostHog

extension View {

    /// Record this screen legibly in session replay.
    ///
    /// Apply only at the root of a screen whose contents are either Repster's own fixed
    /// copy or the user's own training numbers — never to something holding free text the
    /// user typed, which is what `replayMasked()` is for. Applies to the entire subtree.
    func replayVisible() -> some View {
        postHogNoMask()
    }

    /// Keep this value masked even inside a `replayVisible()` screen.
    ///
    /// For free text, where the content cannot be predicted from the field's purpose: a
    /// workout note may hold an injury, a medication, or anything else the user felt like
    /// typing. An explicit mask always wins over an enclosing no-mask region, so nesting
    /// order does not matter.
    func replayMasked() -> some View {
        postHogMask()
    }
}
