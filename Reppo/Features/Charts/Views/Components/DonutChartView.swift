// DonutChartView.swift
// SectorMark donut chart with center metric overlay and tap-to-select slices.
// Feature: 016-charts-tab-v2 WP06 (T115)

import SwiftUI
import Charts

struct DonutChartView: View {
    let data: [BreakdownDataPoint]
    let centerValue: String
    let centerLabel: String
    var selectedSliceLabel: String?
    var onSelectSlice: ((BreakdownDataPoint?) -> Void)?

    var body: some View {
        ZStack {
            Chart(data) { item in
                SectorMark(
                    angle: .value(item.label, item.value),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .foregroundStyle(item.label == selectedSliceLabel ? item.color : item.color.opacity(selectedSliceLabel == nil ? 1.0 : 0.4))
                .cornerRadius(4)
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            handleTap(at: location, in: geo, proxy: proxy)
                        }
                }
            }
            .frame(height: 240)
            .chartLegend(.hidden)

            // Center text overlay
            VStack(spacing: 2) {
                Text(centerValue)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(centerLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 120)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint, in geo: GeometryProxy, proxy: ChartProxy) {
        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let radius = min(geo.size.width, geo.size.height) / 2

        // Only respond to taps on the donut ring (not the center hole)
        let innerRadius = radius * 0.62
        guard distance > innerRadius && distance < radius else {
            // Tapped center → deselect
            onSelectSlice?(nil)
            return
        }

        // Calculate angle from 12 o'clock position (clockwise)
        var angle = atan2(dx, -dy) // 0 = top, clockwise
        if angle < 0 { angle += 2 * .pi }
        let fraction = angle / (2 * .pi)

        // Find which slice this fraction falls into
        let total = data.reduce(0) { $0 + $1.value }
        guard total > 0 else { return }

        var cumulative: Double = 0
        for item in data {
            cumulative += item.value / total
            if fraction <= cumulative {
                if item.label == selectedSliceLabel {
                    onSelectSlice?(nil) // Toggle off
                } else {
                    onSelectSlice?(item) // Select
                }
                return
            }
        }
    }
}
