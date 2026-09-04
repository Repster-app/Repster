// WorkoutLiveActivityLiveActivity.swift
// Widget definition for the workout Live Activity.
//
// Renders three presentations:
//   1. Lock Screen / StandBy expanded view
//   2. Dynamic Island compact (leading + trailing)
//   3. Dynamic Island expanded (long press)
//
// Timer rendering uses ActivityKit's built-in text styles:
//   - Text(date:style:.timer) for elapsed workout time
//   - Text(timerInterval:countsDown:) for rest timer countdown
// This means zero per-second data pushes — the system handles the rendering.

import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // MARK: - Lock Screen / StandBy Expanded View
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded Dynamic Island (long press)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.workoutTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(context.state.exerciseName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, ExpandedIslandLayout.topInset)
                    .padding(.leading, ExpandedIslandLayout.outerHorizontalInset)
                    .padding(.trailing, ExpandedIslandLayout.innerHorizontalInset)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        elapsedWorkoutTimeText(context: context, font: .caption2)

                        // Set progress
                        Text("Set \(context.state.currentSetNumber)/\(context.state.totalSets)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, ExpandedIslandLayout.topInset)
                    .padding(.leading, ExpandedIslandLayout.innerHorizontalInset)
                    .padding(.trailing, ExpandedIslandLayout.outerHorizontalInset)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    restTimerSection(context: context)
                        .padding(.top, 4)
                }
            } compactLeading: {
                // MARK: - Compact Leading
                // Brand mark, not an exercise glyph: this slot's job is to say
                // which app the activity belongs to. Template asset, tinted here.
                Image("RepsterMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color.accent)
            } compactTrailing: {
                // MARK: - Compact Trailing
                compactTrailingContent(context: context)
            } minimal: {
                // MARK: - Minimal (multiple Live Activities)
                Image("RepsterMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color.accent)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(
        context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> some View {
        VStack(spacing: 8) {
            // Row 1: Workout title + elapsed time
            HStack {
                Text(context.attributes.workoutTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Spacer()

                elapsedWorkoutTimeText(context: context, font: .subheadline)
            }

            // Row 2: Exercise name + set progress
            HStack {
                Text(context.state.exerciseName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 4) {
                    Text("Set \(context.state.currentSetNumber)/\(context.state.totalSets)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("(\(context.state.setTypeLabel.lowercased()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Row 3: Rest timer or ready state
            lockScreenRestTimerSection(context: context)
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
        .legacyDarkScheme()
    }

    // MARK: - Rest Timer Section (Lock Screen)

    /// Wide, left-aligned rest timer row for the Lock Screen / StandBy view.
    ///
    /// Kept separate from `restTimerSection` because that one is tuned for the
    /// Dynamic Island's expanded bottom region, where the row is narrow and the
    /// content has to stay centered and short. Both switch over the same
    /// `ContentState.restDisplay()` so the two can only differ in chrome.
    @ViewBuilder
    private func lockScreenRestTimerSection(
        context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> some View {
        switch context.state.restDisplay() {
        case .workoutPaused:
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let remaining = context.state.restTimerRemainingSeconds {
                    Text("\(formatTime(remaining)) rest paused")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Workout paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

        case .restPaused:
            HStack(spacing: 8) {
                Image(systemName: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let remaining = context.state.restTimerRemainingSeconds {
                    Text("\(formatTime(remaining)) rest paused")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Rest paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

        case .counting(let endDate):
            // Active rest timer — countdown only (no progress bar)
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.caption)
                    .foregroundStyle(.blue)

                Text(timerInterval: countdownRange(to: endDate), countsDown: true)
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.leading)

                Spacer()

                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .complete:
            // Timer finished — prominent rest complete indicator
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                Text("REST COMPLETE")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                Spacer()
                Text("GO")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.green)
                    .cornerRadius(8)
            }

        case .ready:
            // No timer — ready for next set
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Ready for next set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Rest Timer Section (Dynamic Island expanded)

    @ViewBuilder
    private func restTimerSection(
        context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> some View {
        switch context.state.restDisplay() {
        case .workoutPaused:
            HStack(spacing: 6) {
                Image(systemName: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let remaining = context.state.restTimerRemainingSeconds {
                    Text("\(formatTime(remaining)) paused")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

        case .restPaused:
            HStack(spacing: 6) {
                Image(systemName: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let remaining = context.state.restTimerRemainingSeconds {
                    Text("\(formatTime(remaining)) paused")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Rest paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

        case .counting(let endDate):
            // Active rest timer — centered countdown
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.caption)
                    .foregroundStyle(.blue)

                Text(timerInterval: countdownRange(to: endDate), countsDown: true)
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.center)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)

        case .complete:
            // Timer finished — prominent rest complete indicator
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                Text("REST COMPLETE")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)

        case .ready:
            // No timer — ready for next set
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Ready for next set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Compact Trailing

    @ViewBuilder
    private func compactTrailingContent(
        context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> some View {
        switch context.state.restDisplay() {
        case .workoutPaused:
            Text(formatElapsed(context.state.pausedElapsedSeconds))
                .font(.caption2.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(minWidth: 32)

        case .restPaused:
            if let remaining = context.state.restTimerRemainingSeconds {
                Text(formatTime(remaining))
                    .font(.caption2.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32)
            } else {
                Text("\(context.state.currentSetNumber)/\(context.state.totalSets)")
                    .font(.caption2.monospacedDigit())
                    .fontWeight(.semibold)
            }

        case .counting(let endDate):
            Text(timerInterval: countdownRange(to: endDate), countsDown: true)
                .font(.caption2.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(minWidth: 32)

        case .complete:
            // Was falling through to set progress, which is indistinguishable from having no
            // timer at all — the one glanceable surface saying nothing at the moment it matters.
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .frame(minWidth: 32)

        case .ready:
            Text("\(context.state.currentSetNumber)/\(context.state.totalSets)")
                .font(.caption2.monospacedDigit())
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private func elapsedWorkoutTimeText(
        context: ActivityViewContext<WorkoutActivityAttributes>,
        font: Font
    ) -> some View {
        if context.state.isWorkoutPaused {
            HStack(spacing: 4) {
                Text(formatElapsed(context.state.pausedElapsedSeconds))
                Image(systemName: "pause.fill")
                    .font(.caption2)
            }
            .font(font.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        } else {
            Text(context.state.elapsedTimerReferenceDate, style: .timer)
                .font(font.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func formatTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Countdown range for a running rest timer, or nil once its end date has passed.
    ///
    /// `Text(timerInterval:)` traps on a range whose lowerBound exceeds its
    /// upperBound. WidgetKit re-archives the activity whenever it likes — including
    /// long after `restTimerEndDate` if the app was suspended and never pushed a
    /// state update — so the end date has to be re-checked at render time, and `now`
    /// captured once so the comparison and the range can't disagree.
    /// A range safe to hand `Text(timerInterval:)`.
    ///
    /// `restDisplay()` already guarantees `endDate` is in the future for `.counting`, but it
    /// samples `.now` a moment before this does. Clamping costs nothing and means a timer that
    /// expires between the two cannot produce an inverted range, which traps.
    private func countdownRange(to endDate: Date) -> ClosedRange<Date> {
        min(Date.now, endDate)...endDate
    }

}

private enum ExpandedIslandLayout {
    static let topInset: CGFloat = 6
    static let outerHorizontalInset: CGFloat = 12
    static let innerHorizontalInset: CGFloat = 4
}

// MARK: - Legacy Dark Scheme Modifier

/// Forces dark color scheme on pre-iOS 26 so semantic colors (.primary, .secondary)
/// resolve to white/light against the dark Live Activity background.
/// On iOS 26+, liquid glass handles text legibility automatically.
private struct LegacyDarkSchemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content.environment(\.colorScheme, .dark)
        }
    }
}

extension View {
    func legacyDarkScheme() -> some View {
        modifier(LegacyDarkSchemeModifier())
    }
}
