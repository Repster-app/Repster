// RestTimerView.swift
// Visual rest timer with countdown, progress ring, and action buttons.
// Spec: FR-006 (Rest timer auto-starts after set completion)
// Contract: WP06 T029
//
// Displays a countdown bar at the bottom of the active workout screen.
// States: idle (hidden), running (countdown + controls), finished (completion message).
// Pure presentational — receives state and callbacks.

import SwiftUI

/// Displays the rest timer as a horizontal bar with progress ring, countdown, and controls.
///
/// Hidden when state is `.idle`. Shows countdown with +30s and dismiss buttons when
/// `.running`. Shows "Rest complete" message when `.finished`.
struct RestTimerView: View {

    /// Current timer state from the ViewModel.
    let state: RestTimerState

    /// Called when the user taps a positive time adjustment (+15s, +30s).
    let onAddTime: (Int) -> Void

    /// Called when the user taps a negative time adjustment (-15s, -30s).
    let onSubtractTime: (Int) -> Void

    /// Called when the user sets an exact duration via the edit button.
    let onSetDuration: (Int) -> Void

    /// Called when the user dismisses the timer.
    let onDismiss: () -> Void

    /// Whether the exact time editor alert is showing.
    @State private var showTimeEditor = false

    /// Text for the exact time input.
    @State private var exactTimeText = ""

    var body: some View {
        switch state {
        case .idle:
            EmptyView()

        case .running(let remaining, let total):
            timerContent(remaining: remaining, total: total)

        case .finished:
            finishedContent
        }
    }

    // MARK: - Running State

    /// Countdown display with progress ring, time, adjustment buttons, and dismiss.
    private func timerContent(remaining: Int, total: Int) -> some View {
        VStack(spacing: 8) {
            // Main timer row
            HStack(spacing: 16) {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.bgSubtle, lineWidth: 4)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: total > 0 ? CGFloat(remaining) / CGFloat(total) : 0)
                        .stroke(Color.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: remaining)
                }

                // Time remaining
                Text(formatTime(remaining))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.textPrimary)

                Spacer()

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 36, height: 36)
                }
            }

            // Time adjustment buttons row
            HStack(spacing: 6) {
                timerAdjustButton("-30s") { onSubtractTime(30) }
                timerAdjustButton("-15s") { onSubtractTime(15) }
                timerAdjustButton("+15s") { onAddTime(15) }
                timerAdjustButton("+30s") { onAddTime(30) }

                // Edit exact time button
                Button {
                    exactTimeText = "\(remaining)"
                    showTimeEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 36, height: 32)
                        .background(Color.bgSubtle)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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

    /// A small time adjustment button.
    private func timerAdjustButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Color.accentSoft)
            .cornerRadius(8)
            .buttonStyle(.plain)
    }

    // MARK: - Finished State

    /// "Rest complete" message with dismiss button.
    private var finishedContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.success)

            Text("Rest complete")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)

            Spacer()

            Button("Dismiss") { onDismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textSecondary)
                .frame(height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.bgCard)
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
                onDismiss: {}
            )
        }
    }
}

#Preview("Running - 0:05") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Spacer()
            RestTimerView(
                state: .running(remaining: 5, total: 90),
                onAddTime: { _ in },
                onSubtractTime: { _ in },
                onSetDuration: { _ in },
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
                onDismiss: {}
            )
        }
    }
}
