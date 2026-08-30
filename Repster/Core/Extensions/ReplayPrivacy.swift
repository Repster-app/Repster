// ReplayPrivacy.swift
// The values session replay is not allowed to record, wherever they appear.
//
// Background: PostHog does not blur, it fills each masked rect with opaque black
// (`RRWireframe.maskImage`). Against Repster's `#111113` background that is black on
// near-black, so a masked SwiftUI screen is not a redacted screen — it's an unreadable
// one. That is why 1.4's fully masked recordings were useless.
//
// 1.4.x tried to fix that by masking everything and opting screens in one at a time.
// It did not work, and the reason is structural rather than a missing call: a `.sheet`
// is a separate presentation hierarchy, and `postHogNoMask()` returns early on a *view
// subtree*, so an unmasked screen never covers the sheets it raises. 41 of the app's 45
// sheets stayed black, along with Calendar, Charts, Exercises, Insights, Settings and
// Templates, which had never been opted in at all.
//
// So 1.5 inverts it. The global config records the app legibly
// (`AnalyticsService.configureSessionReplay`) and the short list of values that must
// never leave the device is masked here, at the field. Two categories qualify:
//
//   1. **Free text.** What the user typed cannot be predicted from the field's purpose —
//      a workout note may hold an injury, a medication, or anything else.
//   2. **Bodyweight.** A health figure, and the privacy policy promises it is masked
//      wherever it appears.
//
// Everything else a recording can show — Repster's own copy, and the training figures
// the event stream already carries in bucketed form — is the point of recording at all.
//
// `grep -rE "replayMasked|replayPaused"` is the complete inventory of what recordings
// hide, and `RepsterTests/ReplayMaskCoverageTests.swift` fails the build when any new
// `TextField` or `TextEditor` appears without a decision recorded against it. The
// inverted default fails open, so that test is the thing standing between a new text
// field and a recording of what gets typed into it.
//
// KEEP IN SYNC when the masked set changes:
//   1. docs/privacy.html — the live policy at repster-app.github.io
//   2. marketing/app-store/privacy-review-checklist.md — App Review Notes field
//   3. Repster/Core/Services/AnalyticsService.swift — the doc comment on the config

import SwiftUI
import PostHog

extension View {

    /// Keep this value out of session replay recordings.
    ///
    /// Apply to the field itself, or to the smallest container holding the value — the
    /// mask is an opaque black rect at its frame, so masking a whole screen makes the
    /// recording useless rather than merely redacted.
    ///
    /// Masked rects are collected from a registry that is independent of the view walk,
    /// so an explicit mask always wins regardless of what encloses it, and a frame whose
    /// masked view has not been laid out yet is dropped rather than captured unmasked.
    func replayMasked() -> some View {
        postHogMask()
    }

    /// Stop recording entirely while `isPaused` is true, and resume after.
    ///
    /// For free text typed inside a `.alert`. An alert's content is built by
    /// `UIAlertController`, not by SwiftUI, so the `UITextField` the user types into is
    /// never the view `replayMasked()` was applied to and the mask silently does not
    /// land. There are three of them — the set note, Save as Template, and Save Preset —
    /// and the set note is real free text, so guessing was not good enough.
    ///
    /// The cost is a gap in the recording rather than a black rect in it, which for a
    /// modal that is up for a few seconds is the better trade. `startSessionRecording()`
    /// resumes the same session, is a no-op when replay is already active, and honours
    /// opt-out on its own.
    func replayPaused(while isPaused: Bool) -> some View {
        modifier(ReplayPauseModifier(isPaused: isPaused))
    }
}

private struct ReplayPauseModifier: ViewModifier {
    let isPaused: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isPaused) { _, paused in
                if paused {
                    PostHogSDK.shared.stopSessionRecording()
                } else {
                    PostHogSDK.shared.startSessionRecording()
                }
            }
            // A screen torn down while its alert is up would otherwise leave replay
            // stopped for the rest of the session.
            .onDisappear {
                if isPaused {
                    PostHogSDK.shared.startSessionRecording()
                }
            }
    }
}
