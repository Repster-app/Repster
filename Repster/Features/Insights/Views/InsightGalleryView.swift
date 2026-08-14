// InsightGalleryView.swift
// Every insight surface rendered from fixtures, behind the admin flag.
//
// Insights can only be seen when their rule fires, and the rules gate on 14- to
// 60-day windows — `deloadReadiness` alone needs six weeks of history, twelve
// sessions, regression across three exercises and corroboration. So the only way
// to look at a chart used to be to grow the data that produces it, which meant
// the extremes nobody had seen were exactly the ones that shipped broken: a
// meter that pinned above 1.35x baseline, a drought chart whose axis stopped
// before the drought.
//
// This renders all of it from fixtures, including those extremes. It is a
// diagnostic surface, not a demo: the point is the cases that are hard to reach,
// not the happy path.

import SwiftUI

struct InsightGalleryView: View {
    let unitPreference: UnitPreference

    @State private var metric: MuscleMetric = .sets
    @State private var panelExpanded = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                note

                section("Training status — every band") {
                    ForEach(Array(Fixtures.statuses.enumerated()), id: \.offset) { _, entry in
                        labelled(entry.label) {
                            TrainingStatusCardView(status: entry.status)
                        }
                    }
                }

                section("Muscle panel — switch the metric above") {
                    MuscleVolumePanelView(
                        rows: Fixtures.muscleRows,
                        isExpanded: $panelExpanded,
                        metric: $metric,
                        unitPreference: unitPreference
                    )
                    Text("Abs is bodyweight-only — volume should read “—”, not 0. Legs is a real skip.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }

                section("Findings — one per shipped rule") {
                    ForEach(Fixtures.insights) { insight in
                        InsightCardView(
                            insight: insight,
                            unitPreference: unitPreference,
                            onSnooze: {}
                        )
                    }
                }

                section("Chart kinds with no shipped rule") {
                    labelled("range — specified for repRangeDrift, never built") {
                        InsightCardView(
                            insight: Fixtures.rangeInsight,
                            unitPreference: unitPreference,
                            onSnooze: {}
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.bg)
        .navigationTitle("Insight Gallery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var note: some View {
        Text("Fixture data. Nothing here reads or writes your training — ratings and snooze do nothing.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.textTertiary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgSubtle)
            .cornerRadius(10)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.textTertiary)
            content()
        }
    }

    @ViewBuilder
    private func labelled<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            content()
        }
    }
}

// MARK: - Fixtures

private enum Fixtures {

    // MARK: Status

    /// Ratios chosen for the meter's failure range, not for realism: 4x is what
    /// the fixed-anchor version drew identically to 1.4x.
    static let statuses: [(label: String, status: TrainingStatus)] = [
        ("4.0× baseline — the old meter pinned here", status(24, 6)),
        ("2.0× baseline", status(24, 12)),
        ("1.0× — tracking normally", status(12, 12)),
        ("0.4× — lighter week", status(5, 12)),
        ("0 sets logged, baseline exists", status(0, 12)),
        ("No baseline yet — cold start", status(9, nil)),
        ("Nothing logged at all", TrainingStatus(currentSets: 0, baselineSets: nil, muscles: [], hasData: false)),
    ]

    private static func status(_ current: Int, _ baseline: Double?) -> TrainingStatus {
        TrainingStatus(
            currentSets: current,
            baselineSets: baseline,
            muscles: muscleRows,
            hasData: true
        )
    }

    static let muscleRows: [MuscleVolumeRow] = [
        MuscleVolumeRow(
            group: "chest", displayName: "Chest",
            currentSets: 24, baselineSets: 20,
            currentReps: 210, baselineReps: 180,
            currentVolume: 8_900, baselineVolume: 7_700
        ),
        MuscleVolumeRow(
            group: "back", displayName: "Back",
            currentSets: 18, baselineSets: 17,
            currentReps: 160, baselineReps: 158,
            currentVolume: 7_100, baselineVolume: 6_700
        ),
        MuscleVolumeRow(
            group: "abs", displayName: "Abs",
            currentSets: 9, baselineSets: 8,
            currentReps: 140, baselineReps: 120,
            currentVolume: 0, baselineVolume: 0
        ),
        MuscleVolumeRow(
            group: "shoulders", displayName: "Shoulders",
            currentSets: 6, baselineSets: 9,
            currentReps: 70, baselineReps: 96,
            currentVolume: 1_900, baselineVolume: 2_600
        ),
        MuscleVolumeRow(
            group: "legs", displayName: "Legs",
            currentSets: 0, baselineSets: 14,
            currentReps: 0, baselineReps: 120,
            currentVolume: 0, baselineVolume: 12_400
        ),
    ]

    // MARK: Findings

    static let insights: [InsightItem] = [
        item(
            ruleId: "strengthTrend",
            subject: "Bench Press",
            headline: "Your bench press is up 13% over 9 weeks",
            detail: "Estimated 1RM has climbed from 102 kg to 115 kg. Whatever you're doing on this lift is working.",
            methodology: "Daily best estimated 1RM, 8 sessions",
            kind: .series,
            labels: Array(repeating: "", count: 8),
            values: [102, 104, 103, 107, 106, 110, 112, 115],
            isNew: true
        ),
        item(
            ruleId: "deloadReadiness",
            headline: "Your sessions are landing under your usual output",
            detail: "5 exercises came in 3–6% below their recent norm over the last two weeks, while your effort ratings climbed. Your volume hasn't dropped, so this looks like accumulated fatigue rather than a lighter patch.",
            methodology: "5 exercises compared against the previous 4 weeks",
            kind: .series,
            labels: ["Bench Press", "Squat", "Row", "Press", "Deadlift", "Curl"],
            values: [1.5, -3.2, -4.8, -2.6, -6.1, -5.4]
        ),
        item(
            ruleId: "rirCalibration",
            subject: "Squat",
            headline: "You have more in the tank on Squat than you report",
            detail: "Across your recent sets you consistently beat the predicted output by ~8%. Your logged RIR is likely a rep or two higher in reality.",
            methodology: "24 predicted vs. actual set comparisons",
            kind: .series,
            labels: ["Jun 2", "Jun 9", "Jun 16", "Jun 23", "Jun 30", "Jul 7", "Jul 14", "Jul 21"],
            values: [4.1, -2.0, 5.2, -3.1, 6.4, 2.2, 7.1, 3.6]
        ),
        item(
            ruleId: "consistency",
            headline: "5 straight weeks at 4 sessions",
            detail: "Before that you were averaging about 3 a week. Frequency is the part of training that compounds quietest.",
            methodology: "Completed workouts per week, last 8 weeks",
            kind: .column,
            labels: Array(repeating: "", count: 8),
            values: [3, 3, 4, 3, 4, 4, 4, 5]
        ),
        item(
            ruleId: "volumeRamp",
            headline: "Your weekly sets are up 76%",
            detail: "From about 42 sets a week to 74. Fast ramps are where niggles usually start — holding here for a week before adding more is rarely wasted.",
            methodology: "Working sets per week, last 7 weeks",
            kind: .column,
            labels: Array(repeating: "", count: 7),
            values: [42, 45, 48, 52, 61, 68, 74]
        ),
        item(
            ruleId: "droppedExercise",
            subject: "Barbell Row",
            headline: "You've quietly stopped doing barbell row",
            detail: "You trained it 7 times, about every 14 days, then nothing for 94. Worth adding back — or dropping from your template so it stops looking like a gap.",
            methodology: "Last performed 94 days ago",
            kind: .timeline,
            labels: Array(repeating: "", count: 7),
            values: daysAgo([180, 166, 150, 137, 122, 108, 94]),
            typicalGapDays: 14
        ),
        item(
            ruleId: "prPace",
            headline: "You're setting PRs faster than usual",
            detail: "7 PRs in the last five weeks against a typical gap of about 18 days. Whatever you changed recently is working.",
            methodology: "Personal records, last 90 days",
            kind: .timeline,
            labels: Array(repeating: "", count: 7),
            values: daysAgo([64, 48, 33, 21, 12, 7, 4]),
            typicalGapDays: 18,
            isNew: true
        ),
        item(
            ruleId: "muscleBalance",
            subject: "legs",
            headline: "Legs has gone quiet",
            detail: "No legs sets in the last 14 days, while your other muscle groups got 7+ each. One focused session closes the gap.",
            methodology: "Working sets per muscle group, last 14 days",
            kind: .ranking,
            labels: ["chest", "back", "abs", "shoulders", "legs"],
            values: [12, 10, 7, 6, 0]
        ),
        item(
            ruleId: "targetAdherence",
            headline: "Most of your sets land in range",
            detail: "58% of your working sets finished inside their target rep range over the last 30 days, with the misses split fairly evenly either side.",
            methodology: "312 working sets with a target range, last 30 days",
            kind: .proportion,
            labels: ["Below", "In range", "Above"],
            values: [22, 58, 20]
        ),
        item(
            ruleId: "restSweetSpot",
            subject: "Squat",
            headline: "Longer rests are landing better on Squat",
            detail: "Sets after roughly two minutes' rest averaged 118 kg estimated 1RM against 94 kg after shorter breaks, across 40 logged sets.",
            methodology: "40 sets with a recorded rest, last 60 days",
            kind: .comparison,
            labels: ["Longer rest", "Shorter rest"],
            values: [118, 94]
        ),
    ]

    static let rangeInsight = item(
        ruleId: "repRangeDrift",
        subject: "Squat",
        headline: "Your working reps have crept down",
        detail: "Your median working set has moved from 8–12 reps to 5–8 over the last two months, with weights up to match.",
        methodology: "Median working reps, two 30-day windows",
        kind: .range,
        labels: ["Was", "Now"],
        values: [8, 12, 5, 8]
    )

    // MARK: Builders

    private static func daysAgo(_ days: [Double]) -> [Double] {
        days.map { Date().addingTimeInterval(-$0 * 86_400).timeIntervalSince1970 }
    }

    private static func item(
        ruleId: String,
        subject: String? = nil,
        headline: String,
        detail: String,
        methodology: String,
        kind: InsightChartKind,
        labels: [String],
        values: [Double],
        typicalGapDays: Double? = nil,
        isNew: Bool = false
    ) -> InsightItem {
        InsightItem(
            id: UUID(),
            ruleId: ruleId,
            subjectName: subject,
            headline: headline,
            detailText: detail,
            methodologyText: methodology,
            chartKind: kind,
            chartLabels: labels,
            chartValues: values,
            typicalGapDays: typicalGapDays,
            isNew: isNew,
            generatedAt: Date()
        )
    }
}

#Preview {
    NavigationStack {
        InsightGalleryView(unitPreference: .metric)
    }
}
