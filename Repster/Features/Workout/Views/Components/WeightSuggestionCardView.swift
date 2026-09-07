// WeightSuggestionCardView.swift
// Per-set weight suggestion strips. Each pending suggestion is its own
// visually distinct strip with an accent rail, icon tile and a single line
// (set + weight + target reps). The engine's contextual sentence is no longer
// rendered here — `explanation.userSummary` is still produced, just not shown.
// Admin mode keeps the existing dense format with a per-row Details toggle.

import SwiftUI

struct WeightSuggestionCardView: View {
    let data: WeightSuggestionData
    let unitPreference: UnitPreference
    let isAdminModeEnabled: Bool
    /// Called when the explainer is opened, so the caller can record the tally.
    var onExplainerOpened: (() -> Void)? = nil

    /// Suggestion whose explainer sheet is open, if any.
    @State private var explainedSuggestion: SetSuggestion?

    /// Per-row Details toggle state (admin mode only). Indexed by `setId`.
    /// Replaces the previous global toggle.
    @State private var expandedSetIds: Set<UUID> = []

    /// True when the engine baseline is anchored on a workout outside the
    /// user's recency window. Drives the slate stale treatment (banner +
    /// rail/weight colour swap).
    private var isStale: Bool {
        data.e1RMSource.isOutsideRecencyWindow
    }

    /// Accent colour used by pending strips. Swaps to slate when stale.
    private var primaryAccent: Color {
        isStale ? .stale : .accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Stale banner sits above the strips. When shown, it replaces the
            // generic "Based on your recent performance..." copy that used to
            // live per-row; the explicit out-of-window warning is the only
            // contextual line in the stale state.
            if isStale {
                staleBanner
            }

            // Pending strips first — the user immediately sees what to lift.
            ForEach(Array(data.rowStates.enumerated()), id: \.element.id) { _, rowState in
                rowStateRow(rowState)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $explainedSuggestion) { suggestion in
            SuggestionExplainerSheet(
                suggestion: suggestion,
                data: data,
                unitPreference: unitPreference
            )
        }
    }

    // MARK: - Stale banner

    private var staleBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.stale)
                .padding(.top, 1)

            Text(staleBannerCopy)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.staleSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.stale.opacity(0.30), lineWidth: 1)
        )
    }

    /// Banner copy. Anchor date formatted as `Mar 1` per the locked design
    /// decision (open decisions section 3 of the redesign spec).
    private var staleBannerCopy: String {
        guard let date = data.e1RMSourceWorkoutDate else {
            return "Baseline is outside your recency window. Estimate may be optimistic."
        }
        let formatted = date.formatted(.dateTime.month(.abbreviated).day())
        return "Based on a workout from \(formatted) — outside your recency window. Estimate may be optimistic."
    }

    // MARK: - Row dispatcher

    @ViewBuilder
    private func rowStateRow(_ rowState: SetSuggestionState) -> some View {
        switch rowState.availability {
        case let .available(suggestion):
            if isAdminModeEnabled {
                adminPendingStrip(suggestion)
            } else {
                userPendingStrip(suggestion)
            }
        case let .unavailable(reason):
            unavailableStrip(rowState, reason: reason)
        }
    }

    // MARK: - User pending strip (Take B)

    private func userPendingStrip(_ suggestion: SetSuggestion) -> some View {
        Button {
            onExplainerOpened?()
            explainedSuggestion = suggestion
        } label: {
            userPendingStripBody(suggestion)
        }
        .buttonStyle(SuggestionStripButtonStyle())
        .accessibilityLabel(
            "Set \(suggestion.setNumber), \(formatWeight(suggestion.suggestedWeight)) "
            + "for \(suggestion.prescribedDisplayLabel)"
        )
        .accessibilityHint("Shows why this weight was suggested")
    }

    private func userPendingStripBody(_ suggestion: SetSuggestion) -> some View {
        stripContainer(railColor: primaryAccent) {
            HStack(spacing: 10) {
                iconTile(systemName: "wand.and.stars", tint: primaryAccent)

                // The prescription is the whole row: "Set N · 54 kg for 7 reps".
                // Names the rep count the weight was priced for, not the target
                // range: at a range's lower bound the same weight would read as
                // a step backwards.
                HStack(spacing: 0) {
                    Text("Set \(suggestion.setNumber) · ")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(formatWeight(suggestion.suggestedWeight))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(primaryAccent)

                    Text(" for \(suggestion.prescribedDisplayLabel)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Admin pending strip

    private func adminPendingStrip(_ suggestion: SetSuggestion) -> some View {
        let isExpanded = expandedSetIds.contains(suggestion.id)
        return stripContainer(railColor: .info) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    iconTile(systemName: "chevron.left.forwardslash.chevron.right", tint: .info)

                    VStack(alignment: .leading, spacing: 2) {
                        // Mono "Set N: 54.0 kg × 6–8 @ RIR 1" with weight in info tint.
                        HStack(spacing: 0) {
                            Text("Set \(suggestion.setNumber): ")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                            Text(formatWeight(suggestion.suggestedWeight))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.info)
                            Text(" × \(suggestion.prescribedDisplayLabel) @ RIR \(formatSimpleNumber(suggestion.targetRIR))")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                        }

                        Text(suggestion.explanation.adminSummary)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if isExpanded {
                                expandedSetIds.remove(suggestion.id)
                            } else {
                                expandedSetIds.insert(suggestion.id)
                            }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.info)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.bgHover)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.info.opacity(0.32), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Hide diagnostics" : "Show diagnostics")
                }

                if isExpanded {
                    adminDiagnosticsDrawer(suggestion.diagnostics)
                }
            }
        }
    }

    // MARK: - Unavailable strip

    private func unavailableStrip(
        _ rowState: SetSuggestionState,
        reason: SuggestionUnavailableReason
    ) -> some View {
        let isExpanded = expandedSetIds.contains(rowState.id)
        return stripContainer(railColor: .textTertiary) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    iconTile(systemName: "exclamationmark.circle", tint: .textTertiary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Set \(rowState.setNumber)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)

                            Text("·")
                                .foregroundStyle(Color.textTertiary)

                            Text(reason.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                        }

                        Text(reason.message)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isAdminModeEnabled {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                if isExpanded {
                                    expandedSetIds.remove(rowState.id)
                                } else {
                                    expandedSetIds.insert(rowState.id)
                                }
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.bgHover)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isAdminModeEnabled, isExpanded {
                    legacyUnavailableDetails(rowState, reason: reason)
                }
            }
        }
    }

    // MARK: - Strip chrome

    @ViewBuilder
    private func stripContainer<Content: View>(
        railColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            railColor.frame(width: 3)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.border, lineWidth: 1)
        )
    }

    private func iconTile(systemName: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: 36, height: 36)
    }

    // MARK: - Structured admin diagnostics drawer (C9)

    private func adminDiagnosticsDrawer(_ diagnostics: SetSuggestionDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            diagGroup("e1RM & readiness", kvs: [
                ("historical", formatWeight(diagnostics.historicalBaseE1RM)),
                ("session cap", formatWeight(diagnostics.sessionCapabilityE1RM)),
                ("effective", formatWeight(diagnostics.effectiveE1RM)),
                ("readiness", formatSignedPercent(diagnostics.readinessPercent)),
                ("cap source", diagnostics.sessionCapabilitySourceLabel),
                ("baseline", diagnostics.baselineSourceLabel)
            ])

            diagGroup("Fatigue & calibration", kvs: [
                ("discount", String(format: "%.3f", diagnostics.fatigueDiscount)),
                ("projected", String(format: "%.3f", diagnostics.projectedSessionFatigue)),
                ("freshness", diagnostics.freshnessApplied ? "on" : "off"),
                ("type mult", String(format: "%.1f×", diagnostics.setTypeFatigueMultiplier)),
                ("rest", "\(Int(diagnostics.restSecondsUsed))s (\(diagnostics.restSource))"),
                ("calibration", diagnostics.calibrationLabel)
            ])

            diagGroup("Target & rounding", kvs: targetAndRoundingKVs(diagnostics))

            VStack(alignment: .leading, spacing: 5) {
                diagGroupHeader("Alternatives \(alternativesRangeLabel(diagnostics))")
                ForEach(diagnostics.alternatives) { alternative in
                    structuredAlternative(alternative, chosenReps: diagnostics.chosenReps)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.border, lineWidth: 1)
        )
    }

    private func diagGroup(_ title: String, kvs: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            diagGroupHeader(title)
            let columns = [
                GridItem(.flexible(), spacing: 12, alignment: .leading),
                GridItem(.flexible(), spacing: 12, alignment: .leading)
            ]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
                ForEach(Array(kvs.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(pair.0)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                        Spacer(minLength: 4)
                        Text(pair.1)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func diagGroupHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.info)
            .kerning(0.7)
    }

    private func targetAndRoundingKVs(_ d: SetSuggestionDiagnostics) -> [(String, String)] {
        var kvs: [(String, String)] = [
            ("display", d.targetDisplayLabel),
            ("chosen", "\(d.chosenReps)"),
            ("target src", d.targetSourceLabel),
            ("RIR src", d.rirSourceLabel),
            ("intensity", String(format: "%.3f", d.intensityFactor)),
            ("raw → rnd", "\(formatWeight(d.rawWeight)) → \(formatWeight(d.roundedWeight))")
        ]
        if let normalized = d.normalizedTargetLabel {
            kvs.append(("normalized", normalized))
        }
        if let defaultUsage = d.defaultUsageLabel {
            kvs.append(("default", defaultUsage))
        }
        if d.selectionPolicy == .firstSetProgressionAboveRecentPeak,
           let selectionRef = d.selectionReferenceE1RM {
            kvs.append(("policy ref", formatWeight(selectionRef)))
        }
        return kvs
    }

    private func alternativesRangeLabel(_ d: SetSuggestionDiagnostics) -> String {
        if let r = d.targetRepRange {
            return "(\(r.lowerBound)–\(r.upperBound))"
        }
        return "(x..x+3)"
    }

    private func structuredAlternative(_ alt: SuggestionRepAlternative, chosenReps: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(alt.reps) reps")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)

                if alt.reps == chosenReps {
                    Text("SELECTED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accent.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer(minLength: 0)

                Text("raw \(formatWeight(alt.rawWeight))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 4) {
                ForEach(alt.candidates) { candidate in
                    structuredCandidateCell(candidate)
                }
            }
        }
        .padding(8)
        .background(Color.bgHover)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func structuredCandidateCell(_ c: SuggestionWeightCandidate) -> some View {
        let kindLabel: String
        switch c.kind {
        case .downOneIncrement: kindLabel = "−inc"
        case .suggested: kindLabel = c.isRecommended ? "sug ✓" : "sug"
        case .upOneIncrement: kindLabel = "+inc"
        }
        let isSuggested = c.kind == .suggested
        return VStack(alignment: .leading, spacing: 1) {
            Text(kindLabel)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(c.isRecommended ? Color.success : Color.textTertiary)
            Text(formatWeight(c.weight))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSuggested ? Color.accent.opacity(0.28) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Legacy unavailable details (small block, kept as-is)

    private func legacyUnavailableDetails(
        _ rowState: SetSuggestionState,
        reason: SuggestionUnavailableReason
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("status \(reason.title)")

                if let target = rowState.target {
                    Text("resolved target \(targetDescription(target))")
                    Text("target source \(target.sourceLabel)")
                    Text("reps source \(target.repsSourceLabel)")
                    Text("RIR source \(target.rirSourceLabel)")
                    if let normalizedTargetLabel = target.normalizedTargetLabel {
                        Text(normalizedTargetLabel)
                    }
                    if let defaultUsageLabel = target.defaultUsageLabel {
                        Text(defaultUsageLabel)
                    }
                } else {
                    Text("no target could be resolved for this set")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.textTertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bg.opacity(0.45))
        .cornerRadius(10)
    }

    // MARK: - Formatting

    private func targetDescription(_ target: SuggestionTarget) -> String {
        return "\(target.displayTargetLabel) @ RIR \(formatSimpleNumber(target.rir))"
    }

    private func formatSignedPercent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : value < 0 ? "-" : ""
        return "\(sign)\(String(format: "%.1f", abs(value)))%"
    }

    private func formatSimpleNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private func formatWeight(_ kg: Double) -> String {
        UnitConversion.formatWeightLabel(kg, unitPreference: unitPreference)
    }
}

/// Press feedback for a suggestion strip.
///
/// The strip paints its own `bgCard` background, so the press reads as a light overlay
/// rather than a background swap — swapping it would fight the rail and the icon tile.
private struct SuggestionStripButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.05 : 0))
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
