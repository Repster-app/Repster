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
                        Text(context.state.exerciseName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        // Elapsed time — counts up from workout start
                        Text(
                            context.attributes.workoutStartTime,
                            style: .timer
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                        // Set progress
                        Text("Set \(context.state.currentSetNumber)/\(context.state.totalSets)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    restTimerSection(context: context)
                        .padding(.top, 4)
                }
            } compactLeading: {
                // MARK: - Compact Leading
                Image(systemName: "dumbbell.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            } compactTrailing: {
                // MARK: - Compact Trailing
                compactTrailingContent(context: context)
            } minimal: {
                // MARK: - Minimal (multiple Live Activities)
                Image(systemName: "dumbbell.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
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

                // Elapsed time — uses timer text style for zero-cost updates
                Text(context.attributes.workoutStartTime, style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
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
            restTimerSection(context: context)
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
        .legacyDarkScheme()
    }

    // MARK: - Rest Timer Section

    @ViewBuilder
    private func restTimerSection(
        context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> some View {
        if context.state.isRestTimerRunning, let endDate = context.state.restTimerEndDate {
            // Active rest timer — countdown only (no progress bar)
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.caption)
                    .foregroundStyle(.blue)

                Text(timerInterval: Date.now...endDate, countsDown: true)
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.leading)

                Spacer()

                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if context.state.isRestTimerFinished {
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
        } else {
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

    // MARK: - Compact Trailing

    @ViewBuilder
    private func compactTrailingContent(
        context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> some View {
        if context.state.isRestTimerRunning, let endDate = context.state.restTimerEndDate {
            // Show countdown
            Text(timerInterval: Date.now...endDate, countsDown: true)
                .font(.caption2.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(minWidth: 32)
        } else {
            // Show set progress
            Text("\(context.state.currentSetNumber)/\(context.state.totalSets)")
                .font(.caption2.monospacedDigit())
                .fontWeight(.semibold)
        }
    }

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
