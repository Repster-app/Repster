// SuggestionExplainerSheet.swift
// "Why this weight" — the explanation behind a single Smart Suggestion.
//
// Presented by tapping a pending suggestion strip. One rule governs what appears
// here: every line is an INPUT — a set the lifter performed, or a target they set.
// Derived quantities (e1RM, intensity factor, session capability) are deliberately
// absent. They cannot be corrected by the user, and an estimated one-rep max sitting
// beside a weight the user is about to load reads as a second weight to lift.
//
// The sheet has three shapes, chosen from the data rather than a mode flag:
//   · plain      — the baseline is recent and today's sets counted
//   · uncounted  — sets were logged too far from failure to move the estimate
//   · stale      — the baseline is outside the recency window
//
// The push ("go for N instead") is suppressed in both non-plain shapes. Encouraging
// someone to chase failure on evidence we have just described as weak is bad advice.

import SwiftUI

struct SuggestionExplainerSheet: View {
    let suggestion: SetSuggestion
    let data: WeightSuggestionData
    let unitPreference: UnitPreference

    @Environment(\.dismiss) private var dismiss

    // MARK: - Shape

    /// Sets logged this session that were too far from failure to count as capacity.
    private var ignoredCount: Int { data.sessionSetsIgnoredForCapability }

    private var isStale: Bool { data.e1RMSource.isOutsideRecencyWindow }

    private var hasUncountedSets: Bool { ignoredCount > 0 }

    private var accent: Color { isStale ? .stale : .accent }

    /// The push is only offered when the evidence behind the number is sound.
    private var pushOption: SuggestionPushOption? {
        guard !isStale, !hasUncountedSets else { return nil }
        return suggestion.pushOption
    }

    private var completedSets: [CompletedSetSnapshot] { data.completedInSessionSets }

    /// How far under fresh this set is planned, as a positive percentage.
    private var fatiguePercent: Double {
        max(0, (1.0 - suggestion.diagnostics.fatigueDiscount) * 100.0)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    answerBox
                    trail
                    if let footer = footerCopy {
                        footerCard(footer, tint: isStale ? .stale : .orange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.bg)
            .navigationTitle("Why this weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - The answer

    private var answerBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(formatWeight(suggestion.suggestedWeight))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(accent)

                Text("× \(suggestion.prescribedDisplayLabel)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textSecondary)

                Spacer(minLength: 0)

                if isStale {
                    Text("ROUGH GUESS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.stale)
                        .kerning(0.5)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.staleSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.stale.opacity(0.30), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if let push = pushOption {
                Divider().overlay(Color.border)

                HStack(spacing: 9) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.gold)

                    Text("PUSH IT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.gold)
                        .kerning(0.5)

                    Text(pushLabel(for: push))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Spacer(minLength: 6)

                    Text(pushHint(for: push))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 11)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.border, lineWidth: 1)
        )
    }

    /// "× 8 reps" when only the reps change, "62.5 kg × 8" when the load moves too.
    private func pushLabel(for push: SuggestionPushOption) -> String {
        if abs(push.weight - suggestion.suggestedWeight) < 0.0001 {
            return "× \(push.displayReps) reps"
        }
        return "\(formatWeight(push.weight)) × \(push.displayReps)"
    }

    private func pushHint(for push: SuggestionPushOption) -> String {
        abs(push.weight - suggestion.suggestedWeight) < 0.0001
            ? "same bar, all out"
            : "all out"
    }

    // MARK: - The trail

    private var trail: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepRow(
                number: 1,
                title: "The set we're going on",
                detail: baselineDetail,
                body: baselineBody,
                flag: isStale ? .stale : nil,
                isLast: false
            )

            stepRow(
                number: 2,
                title: hasUncountedSets ? "Today hasn't counted" : todayTitle,
                detail: todayDetail,
                body: todayBody,
                flag: hasUncountedSets ? .orange : nil,
                isLast: false
            )

            stepRow(
                number: 3,
                title: "Your target for this lift",
                detail: targetDetail,
                body: targetBody,
                flag: nil,
                isLast: true
            )
        }
    }

    private func stepRow(
        number: Int,
        title: String,
        detail: String,
        body: String,
        flag: Color?,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(flag ?? Color.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(flag?.opacity(0.14) ?? Color.bgSubtle)
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(
                            flag?.opacity(0.35) ?? Color.clear,
                            lineWidth: 1
                        )
                    )

                if !isLast {
                    Rectangle()
                        .fill(Color.border)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Spacer(minLength: 0)

                    if let flag {
                        Text("CHECK THIS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(flag)
                            .kerning(0.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(flag.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(flag.opacity(0.30), lineWidth: 1)
                            )
                    }
                }

                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 2 : 14)
        }
    }

    // MARK: - Step copy

    private var baselineDetail: String {
        guard let top = suggestion.baselineTopSet else {
            return "your recent history for this exercise"
        }
        var parts = "\(formatWeight(top.weight)) × \(top.reps)"
        if let rir = top.rir {
            parts += " @ RIR \(formatSimpleNumber(rir))"
        }
        if let when = relativeDate(top.date) {
            parts += " · \(when)"
        }
        return parts
    }

    private var baselineBody: String {
        guard suggestion.baselineTopSet != nil else {
            return isStale
                ? "It is older than your recency window, so treat this number as a starting point rather than a fact."
                : "Everything below is measured against your best recent work on this lift."
        }
        return isStale
            ? "It is outside your recency window, so it is the best guess we have rather than a fair guide to where you are now."
            : "Your strongest recent set for this lift. Everything below is measured against it."
    }

    private var todayTitle: String {
        completedSets.isEmpty ? "Nothing from today yet" : "What today has cost"
    }

    private var todayDetail: String {
        guard !completedSets.isEmpty else {
            return "first working set of the session"
        }
        return completedSets
            .map { set in
                var text = "Set \(set.setNumber) · \(formatWeight(set.weight)) × \(set.reps)"
                if let rir = set.rir {
                    text += " @ RIR \(formatSimpleNumber(rir))"
                }
                return text
            }
            .joined(separator: "\n")
    }

    private var todayBody: String {
        if hasUncountedSets {
            let noun = ignoredCount == 1 ? "That set" : "Those sets"
            let verb = ignoredCount == 1 ? "stopped" : "stopped"
            return "\(noun) \(verb) well short of failure. We only read strength from sets taken near "
                + "failure, so nothing there raised your ceiling — but it all still counted toward fatigue."
        }
        if completedSets.isEmpty {
            return "No working sets logged, so there is nothing yet to adjust up or down."
        }
        if fatiguePercent < 0.5 {
            return "Logged and accounted for. Nothing has come off the top yet."
        }
        return "Logged and accounted for. \(completedSets.count == 1 ? "One set" : "\(completedSets.count) sets") in, "
            + "we plan for about \(formatPercent(fatiguePercent)) under fresh."
    }

    private var targetDetail: String {
        var text = "\(suggestion.targetDisplayLabel) @ RIR \(formatSimpleNumber(suggestion.targetRIR))"
        if !suggestion.explanation.targetSourceLabel.isEmpty {
            text += " · from \(suggestion.explanation.targetSourceLabel)"
        }
        return text
    }

    private var targetBody: String {
        let increment = formatWeight(suggestion.diagnostics.weightIncrement)
        var text = "\(suggestion.prescribedDisplayLabel.capitalizedFirst) leaving "
            + "\(formatSimpleNumber(suggestion.targetRIR)) in the tank comes to "
            + "\(formatWeight(suggestion.suggestedWeight)), rounded to your \(increment) steps."
        if let push = pushOption, abs(push.weight - suggestion.suggestedWeight) < 0.0001 {
            text += " \(push.displayReps) on the same bar spends that last rep."
        }
        return text
    }

    // MARK: - Footer

    private var footerCopy: String? {
        if hasUncountedSets {
            return "Take a set closer to failure and today starts counting. If those sets were harder "
                + "than you logged, correct the effort and this catches up straight away."
        }
        if isStale {
            return "Treat this as a test set. Log what it actually felt like and the rest of the "
                + "session follows today rather than your last workout."
        }
        return nil
    }

    private func footerCard(_ text: String, tint: Color) -> some View {
        HStack(spacing: 0) {
            tint.frame(width: 3)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.border, lineWidth: 1)
        )
    }

    // MARK: - Formatting

    private func formatWeight(_ kg: Double) -> String {
        UnitConversion.formatWeightLabel(kg, unitPreference: unitPreference)
    }

    private func formatSimpleNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func formatPercent(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))%" : String(format: "%.1f%%", value)
    }

    private func relativeDate(_ date: Date) -> String? {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private extension String {
    /// "seven reps" → "Seven reps", without lowercasing the rest of the string.
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
