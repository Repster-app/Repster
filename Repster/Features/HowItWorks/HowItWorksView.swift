// HowItWorksView.swift
// Seven pages explaining the app, opened on purpose rather than pushed.
//
// Reached from the Home banner on a new install, and from Settings → About forever after.
// Never auto-presented: an explanation nobody asked for is tapped through to be rid of,
// and the banner's tap rate is a real signal about whether one was wanted at all.
//
// The illustrations are purpose-built rather than the real components. `SetTableView`
// needs a live `SetTableDataSource`, so it can't be dropped into a static page. The one
// exception is the RIR page, which reads `Color.rirColor(for:)` directly — it's teaching a
// colour code, and a drifted copy of that would actively mislead.

import SwiftUI

struct HowItWorksView: View {

    let analyticsService: any AnalyticsServiceProtocol

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var reportedPages: Set<HowItWorksPage> = []

    private let pages = HowItWorksPage.allCases

    private var page: HowItWorksPage { pages[index] }
    private var isLast: Bool { index == pages.count - 1 }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    VStack(spacing: 0) {
                        illustration(for: page)
                            .frame(maxWidth: .infinity)
                            .frame(height: 210)
                            .padding(14)
                            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 16))

                        Text(page.caption)
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 18)
                            .padding(.horizontal, 4)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            dots

            Button {
                advance()
            } label: {
                Text(isLast ? "Start your first workout" : "Next")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accent)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color.bg)
        .onAppear { reportPage() }
        .onChange(of: index) { _, _ in reportPage() }
    }

    // MARK: - Chrome

    private var header: some View {
        ZStack {
            VStack(spacing: 3) {
                Text(page.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                Text("\(index + 1) of \(pages.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .kerning(1.2)
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 52)

            // Leaving is a corner action, so the bottom holds one button rather than a
            // back / next / skip cluster arguing over the same job.
            HStack {
                Spacer()
                Button {
                    finish(reachedLast: isLast)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.bgSubtle)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.trailing, 20)
        }
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                Button {
                    withAnimation { index = offset }
                } label: {
                    Capsule()
                        .fill(offset == index ? Color.accent : Color.bgSubtle)
                        .frame(width: offset == index ? 18 : 6, height: 6)
                }
                .accessibilityLabel("Page \(offset + 1): \(page.title)")
            }
        }
        .padding(.vertical, 18)
    }

    // MARK: - Actions

    private func advance() {
        if isLast {
            finish(reachedLast: true)
        } else {
            withAnimation { index += 1 }
        }
    }

    private func finish(reachedLast: Bool) {
        analyticsService.walkthroughCompleted(reachedLast: reachedLast, lastPage: page)
        dismiss()
    }

    private func reportPage() {
        guard reportedPages.insert(page).inserted else { return }
        analyticsService.walkthroughPageViewed(page)
    }

    // MARK: - Illustrations

    /// An image in the asset catalog named `page.assetName` wins over the drawn version,
    /// so a page can be replaced with a real picture without touching this file.
    @ViewBuilder
    private func illustration(for page: HowItWorksPage) -> some View {
        if UIImage(named: page.assetName) != nil {
            Image(page.assetName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            drawnIllustration(for: page)
        }
    }

    @ViewBuilder
    private func drawnIllustration(for page: HowItWorksPage) -> some View {
        switch page {
        case .startWorkout:
            VStack(spacing: 8) {
                illoRow("plus", .accent, "Empty Workout", "Start fresh and add exercises as you go", highlighted: true)
                illoRow("doc.on.doc", .accent, "Copy Previous", "Repeat a past workout with the same exercises")
                illoRow("doc.text", .accent, "Use Template", "Start from a saved workout routine")
            }

        case .logSet:
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    columnHeader("SET", width: 24)
                    columnHeader("WEIGHT", width: nil)
                    columnHeader("REPS", width: 36)
                    columnHeader("RIR", width: 30)
                    Spacer().frame(width: 22)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

                setRow(number: 1, weight: "60 kg", reps: "8", rir: "2", done: true)
                setRow(number: 2, weight: "60 kg", reps: "8", rir: "2", done: true)
                setRow(number: 3, weight: "62.5", reps: "8", rir: nil, done: false, highlighted: true)
            }

        case .suggestions:
            VStack(spacing: 8) {
                illoRow("sparkles", .accent, "Set 3: 62.5 kg × 8 @ RIR 2", "LAST TOP · 60 kg × 8", highlighted: true)
                illoRow("trophy", .gold, "Bench press", "Best e1RM 78 kg · 12 sessions")
            }

        case .rir:
            VStack(spacing: 12) {
                HStack(spacing: 5) {
                    ForEach(0..<6, id: \.self) { value in
                        Text(value == 5 ? "5+" : "\(value)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.bg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.rirColor(for: Double(value)))
                            .cornerRadius(9)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(value == 2 ? Color.gold : .clear, lineWidth: 2)
                            )
                    }
                }

                Text("left: nothing left in the tank · right: easy")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }

        case .personalRecords:
            VStack(spacing: 8) {
                illoRow("trophy", .gold, "Bench press · 62.5 kg × 8", "New 8-rep best · +2.5 kg", highlighted: true)
                illoRow("chart.line.uptrend.xyaxis", .gold, "Estimated 1RM", "78 kg · up from 74 kg")
            }

        case .weeklyVolume:
            VStack(spacing: 12) {
                illoRow("gauge.medium", .accent, "Tracking normally", "14 sets · 8-week avg 12")

                VStack(spacing: 8) {
                    volumeBar("Chest", fraction: 0.74, color: .accent)
                    volumeBar("Back", fraction: 0.88, color: .accent)
                    volumeBar("Legs", fraction: 0.31, color: .gold)
                }
            }

        case .charts:
            VStack(spacing: 10) {
                TrendSparkline(points: [0.18, 0.30, 0.26, 0.52, 0.64, 0.76, 0.94])
                    .frame(height: 110)

                Text("Bench press · estimated 1RM · 6 months")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private func illoRow(
        _ symbol: String,
        _ tint: Color,
        _ title: String,
        _ subtitle: String,
        highlighted: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.13))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Color.bg)
        .cornerRadius(11)
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(highlighted ? Color.gold : Color.border, lineWidth: highlighted ? 1.5 : 1)
        )
    }

    private func columnHeader(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .kerning(0.6)
            .foregroundColor(.textTertiary)
            .frame(width: width, alignment: width == nil ? .leading : .center)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func setRow(
        number: Int,
        weight: String,
        reps: String,
        rir: String?,
        done: Bool,
        highlighted: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
                .frame(width: 24)

            Text(weight)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(reps)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)
                .frame(width: 36)

            Text(rir ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(rir == nil ? .textTertiary : .textPrimary)
                .frame(width: 30)

            Image(systemName: done ? "checkmark" : "circle")
                .font(.system(size: 12, weight: done ? .bold : .regular))
                .foregroundColor(done ? .success : .textTertiary)
                .frame(width: 22)
        }
        .monospacedDigit()
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .background(Color.bg)
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(highlighted ? Color.gold : Color.border, lineWidth: highlighted ? 1.5 : 1)
        )
    }

    private func volumeBar(_ label: String, fraction: Double, color: Color) -> some View {
        HStack(spacing: 9) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .frame(width: 42, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.bgSubtle)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Sparkline

/// A filled trend line. Drawn rather than charted: this is an illustration of what the
/// Charts tab does, not a chart of anything real.
private struct TrendSparkline: View {
    let points: [Double]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : w
            let coords = points.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * step, y: h - (CGFloat(value) * h * 0.86) - h * 0.07)
            }

            ZStack {
                Path { path in
                    guard let first = coords.first else { return }
                    path.move(to: CGPoint(x: first.x, y: h))
                    path.addLine(to: first)
                    coords.dropFirst().forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: coords[coords.count - 1].x, y: h))
                    path.closeSubpath()
                }
                .fill(Color.accent.opacity(0.13))

                Path { path in
                    guard let first = coords.first else { return }
                    path.move(to: first)
                    coords.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                if let last = coords.last {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 8, height: 8)
                        .position(last)
                }
            }
        }
    }
}

// MARK: - Preview

/// Xcode canvas, so wording and illustrations can be iterated without a build-run cycle.
/// `NoopAnalyticsService` keeps preview renders out of the funnels.
#Preview("How it works") {
    HowItWorksView(analyticsService: NoopAnalyticsService())
        .preferredColorScheme(.dark)
}
