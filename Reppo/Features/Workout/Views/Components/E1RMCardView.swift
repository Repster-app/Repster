// E1RMCardView.swift
// Hero card displaying estimated one-rep max with historical trend comparison.
// Feature: 014-exercise-info-active-workout, WP02-T004

import SwiftUI

struct E1RMCardView: View {
    let info: E1RMInfo
    let unitPreference: UnitPreference

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            header

            // Hero e1RM value
            Text(formatHeroWeight(info.currentE1RM))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            // Bottom row: best today + historical comparison
            bottomRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.open.with.lines.needle.33percent")
                .font(.system(size: 14))
                .foregroundStyle(Color.accent)
                .frame(width: 22, height: 22)
                .background(Color.accent.opacity(0.08))
                .cornerRadius(6)

            Text("Estimated 1RM")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 8) {
            // Producing set info
            if info.bestSetReps > 0 {
                Text("Best today: \(formatSetPerformance(weightKg: info.bestSetWeight, reps: info.bestSetReps))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            } else if info.bestSetWeight > 0 {
                Text("All-time best · \(formatWeight(info.bestSetWeight)) \(unitLabel) top weight")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("All-time best")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }

            // Historical comparison
            if let historicalWeeksAgo = info.historicalWeeksAgo,
               let delta = info.delta,
               let trend = info.trend {
                Rectangle()
                    .fill(Color.border)
                    .frame(width: 1)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text("vs \(historicalWeeksAgo)wk ago")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)

                    Text(formatDelta(delta, trend: trend))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(trendColor(trend))
                }
            }

            Spacer()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Formatting

    private func formatHeroWeight(_ kg: Double) -> String {
        let value = unitPreference == .imperial ? UnitConversion.kgToLbs(kg) : kg
        let unit = unitPreference == .imperial ? "lbs" : "kg"
        return String(format: "%.1f", value) + " " + unit
    }

    private func formatWeight(_ kg: Double) -> String {
        let value = unitPreference == .imperial ? UnitConversion.kgToLbs(kg) : kg
        if value == value.rounded() && value == Double(Int(value)) {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private func formatSetPerformance(weightKg: Double, reps: Int) -> String {
        "\(formatWeight(weightKg)) \(unitLabel) x \(reps) reps"
    }

    private var unitLabel: String {
        unitPreference == .imperial ? "lbs" : "kg"
    }

    private func formatDelta(_ delta: Double, trend: Trend) -> String {
        let value = unitPreference == .imperial ? UnitConversion.kgToLbs(delta) : delta
        let unit = unitPreference == .imperial ? "lbs" : "kg"
        let sign = value > 0 ? "+" : value < 0 ? "−" : ""
        let absValue = abs(value)
        let formatted: String
        if absValue == absValue.rounded() && absValue == Double(Int(absValue)) {
            formatted = "\(Int(absValue))"
        } else {
            formatted = String(format: "%.1f", absValue)
        }
        return "\(sign)\(formatted) \(unit)"
    }

    private func trendColor(_ trend: Trend) -> Color {
        switch trend {
        case .positive: return .success
        case .negative: return .danger
        case .neutral: return .textSecondary
        }
    }
}

// MARK: - Previews

#Preview("Full Data") {
    ZStack {
        Color.bg.ignoresSafeArea()
        E1RMCardView(
            info: E1RMInfo(
                currentE1RM: 105.5,
                bestSetWeight: 85,
                bestSetReps: 8,
                historicalE1RM: 103.2,
                historicalWeeksAgo: 4,
                delta: 2.3,
                trend: .positive
            ),
            unitPreference: .metric
        )
        .padding()
    }
}

#Preview("No History") {
    ZStack {
        Color.bg.ignoresSafeArea()
        E1RMCardView(
            info: E1RMInfo(
                currentE1RM: 100.0,
                bestSetWeight: 80,
                bestSetReps: 8,
                historicalE1RM: nil,
                historicalWeeksAgo: nil,
                delta: nil,
                trend: nil
            ),
            unitPreference: .metric
        )
        .padding()
    }
}

#Preview("Stats Fallback") {
    ZStack {
        Color.bg.ignoresSafeArea()
        E1RMCardView(
            info: E1RMInfo(
                currentE1RM: 120.0,
                bestSetWeight: 100,
                bestSetReps: 0,
                historicalE1RM: 115.0,
                historicalWeeksAgo: 5,
                delta: 5.0,
                trend: .positive
            ),
            unitPreference: .imperial
        )
        .padding()
    }
}
