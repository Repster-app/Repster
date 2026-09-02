// RestTimerView.swift
// Visual rest timer rendered as a full-width band with a hairline progress rule.
// Spec: FR-006 (Rest timer auto-starts after set completion)
// Contract: WP06 T029
//
// Displays one 45pt edge-to-edge band at the bottom of the active workout screen.
// States: idle (hidden), running/paused (countdown + controls), finished (completion message).
// Pure presentational — receives state and callbacks.

import SwiftUI

/// Displays the rest timer as a full-width band topped by a 2pt progress rule.
///
/// The rule doubles as the separator between the band and the set list: it is drawn in
/// `Color.border` across the full width, with the elapsed portion overpainted in accent.
/// Progress therefore reads as its own object rather than a tint washed behind the text,
/// which is what made an earlier draining-fill version illegible — a 10% accent fill over
/// `bgSubtle` is only a ~2% luminance step.
///
/// The band runs edge to edge and sits flush to the bottom so it reads as part of the screen
/// rather than a card floating on it. At 45pt it replaces a 108pt two-row layout.
///
/// Controls, left to right: the countdown (tap to set an exact duration), then −15s, +15s,
/// pause/resume and dismiss. ±30s is two taps of ±15s; the long-press alternative was rejected
/// as undiscoverable mid-set.
struct RestTimerView: View {

    /// Current timer state from the ViewModel.
    let state: RestTimerState

    /// Called when the user taps a positive time adjustment (+15s).
    let onAddTime: (Int) -> Void

    /// Called when the user taps a negative time adjustment (-15s).
    let onSubtractTime: (Int) -> Void

    /// Called when the user sets an exact duration by tapping the countdown.
    let onSetDuration: (Int) -> Void

    /// Called when the user toggles the rest timer between running and paused.
    let onTogglePause: () -> Void

    /// Called when the user dismisses the timer.
    let onDismiss: () -> Void

    /// Whether the exact time editor alert is showing.
    @State private var showTimeEditor = false

    /// Text for the exact time input.
    @State private var exactTimeText = ""

    /// Height of the progress rule along the top edge.
    private static let ruleHeight: CGFloat = 2

    /// Height of the control row beneath the rule.
    private static let rowHeight: CGFloat = 43

    var body: some View {
        switch state {
        case .idle:
            EmptyView()

        case .running(let remaining, let total):
            band(remaining: remaining, total: total, pauseSource: nil)

        case .paused(let remaining, let total, let source):
            band(remaining: remaining, total: total, pauseSource: source)

        case .finished:
            finishedBand
        }
    }

    // MARK: - Running / Paused

    /// The countdown band: progress rule on top, controls beneath.
    private func band(
        remaining: Int,
        total: Int,
        pauseSource: RestTimerPauseSource?
    ) -> some View {
        let isPaused = pauseSource != nil
        let progress = total > 0
            ? max(0, min(1, CGFloat(remaining) / CGFloat(total)))
            : 0
        // The workout clock owning the pause means this timer cannot be resumed from here.
        let pauseButtonEnabled = pauseSource != .workout
        let pauseButtonIcon = pauseSource == .manual ? "play.fill" : "pause.fill"
        let pauseButtonLabel: String
        switch pauseSource {
        case .manual:
            pauseButtonLabel = "Resume rest timer"
        case .workout:
            pauseButtonLabel = "Rest timer paused with workout"
        case .none:
            pauseButtonLabel = "Pause rest timer"
        }

        return VStack(spacing: 0) {
            progressRule(progress: progress, color: isPaused ? .textSecondary : .accent)

            HStack(spacing: 8) {
                Button {
                    exactTimeText = "\(remaining)"
                    showTimeEditor = true
                } label: {
                    Text(formatTime(remaining))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(isPaused ? .textSecondary : .textPrimary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rest time remaining \(formatTime(remaining))")
                .accessibilityHint("Tap to set an exact rest time")

                Spacer(minLength: 4)

                adjustButton("-15s") { onSubtractTime(15) }
                adjustButton("+15s") { onAddTime(15) }

                Button(action: onTogglePause) {
                    Image(systemName: pauseButtonIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(pauseButtonEnabled ? .textSecondary : .textTertiary.opacity(0.45))
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!pauseButtonEnabled)
                .accessibilityLabel(pauseButtonLabel)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 26, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss rest timer")
            }
            .padding(.horizontal, 20)
            .frame(height: Self.rowHeight)
        }
        .frame(maxWidth: .infinity)
        .background(Color.bgCard)
        .alert("Set Rest Time", isPresented: $showTimeEditor) {
            TextField("Seconds", text: $exactTimeText)
                .keyboardType(.numberPad)
            Button("Set") {
                if let seconds = Int(exactTimeText), seconds > 0 {
                    onSetDuration(seconds)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter rest time in seconds")
        }
    }

    /// The 2pt rule along the top edge: full-width separator, overpainted to show progress.
    private func progressRule(progress: CGFloat, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.border)

                Rectangle()
                    .fill(color)
                    .frame(width: geometry.size.width * progress)
                    .animation(.linear(duration: 1), value: progress)
            }
        }
        .frame(height: Self.ruleHeight)
    }

    /// A time adjustment button sized to sit inside the band.
    private func adjustButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accent)
                .frame(width: 46, height: 30)
                .background(Color.bgSubtle)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Finished State

    /// "Rest complete" message in the same band, rule filled green.
    ///
    /// The base is `bgCard`, the same as the countdown band, with the green wash layered over it.
    /// `successSoft` is 8% green: alone it is not a background at all, and because the band is a
    /// bottom safe-area inset the set list scrolled straight through the words.
    ///
    /// Dismiss carries the same pill as the ±15s controls rather than sitting as bare text — it is
    /// the only control in this state, so it has to read as one and take a thumb-sized tap.
    private var finishedBand: some View {
        VStack(spacing: 0) {
            progressRule(progress: 1, color: .success)

            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundColor(.success)

                Text("Rest complete")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(height: 30)
                        .padding(.horizontal, 14)
                        .background(Color.bgSubtle)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss rest timer")
            }
            .padding(.horizontal, 20)
            .frame(height: Self.rowHeight)
        }
        .frame(maxWidth: .infinity)
        .background(Color.bgCard.overlay(Color.successSoft))
    }

    // MARK: - Formatting

    /// Format seconds as "M:SS".
    private func formatTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Previews

#Preview("Running - 1:30") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Spacer()
            RestTimerView(
                state: .running(remaining: 90, total: 120),
                onAddTime: { _ in },
                onSubtractTime: { _ in },
                onSetDuration: { _ in },
                onTogglePause: {},
                onDismiss: {}
            )
        }
    }
}

#Preview("Running - Nearly Done") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Spacer()
            RestTimerView(
                state: .running(remaining: 8, total: 120),
                onAddTime: { _ in },
                onSubtractTime: { _ in },
                onSetDuration: { _ in },
                onTogglePause: {},
                onDismiss: {}
            )
        }
    }
}

#Preview("Paused - Manual") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Spacer()
            RestTimerView(
                state: .paused(remaining: 45, total: 90, source: .manual),
                onAddTime: { _ in },
                onSubtractTime: { _ in },
                onSetDuration: { _ in },
                onTogglePause: {},
                onDismiss: {}
            )
        }
    }
}

#Preview("Paused - With Workout") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Spacer()
            RestTimerView(
                state: .paused(remaining: 45, total: 90, source: .workout),
                onAddTime: { _ in },
                onSubtractTime: { _ in },
                onSetDuration: { _ in },
                onTogglePause: {},
                onDismiss: {}
            )
        }
    }
}

#Preview("Finished") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Spacer()
            RestTimerView(
                state: .finished,
                onAddTime: { _ in },
                onSubtractTime: { _ in },
                onSetDuration: { _ in },
                onTogglePause: {},
                onDismiss: {}
            )
        }
    }
}
