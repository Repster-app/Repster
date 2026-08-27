import XCTest
@testable import Repster

/// User-POV behaviour scenarios for Smart Suggestions and the fatigue model.
///
/// These are not unit tests of the formulas — `ActiveWorkoutViewModelSuggestionRefreshTests`
/// already covers those. These drive `SuggestionEngine.evaluate` through whole sessions the
/// way a lifter would experience them and print the numbers that would appear on the card,
/// so the output can be read and judged for plausibility rather than only for correctness.
///
/// Run with:
///   xcodebuild test -scheme Repster -only-testing:RepsterTests/SmartSuggestionBehaviorScenarioTests
final class SmartSuggestionBehaviorScenarioTests: XCTestCase {

    // MARK: - Production defaults
    //
    // Mirrors LoadPrescriptionService.evaluate: rest 150 s (profile default), increment 2.5 kg,
    // fatigue on, freshness off, base rate 0.03 (FatigueLearningService.defaultGlobalFatigueRate),
    // tau 180 s, capability policy .observed, Epley.

    private func settings(
        rest: Double = 150,
        fatigueEnabled: Bool = true,
        baseFatigueRate: Double = 0.03,
        recoveryConstant: Double = 180,
        increment: Double = 2.5,
        freshnessEnabled: Bool = false,
        freshnessPercent: Double = 0.03,
        formula: E1RMFormula = .epley
    ) -> SuggestionSettingsSnapshot {
        SuggestionSettingsSnapshot(
            formula: formula,
            restTimerSeconds: rest,
            weightIncrement: increment,
            fatigueEnabled: fatigueEnabled,
            freshnessEnabled: freshnessEnabled,
            freshnessPercent: freshnessPercent,
            baseFatigueRate: baseFatigueRate,
            recoveryConstant: recoveryConstant,
            sessionCapabilityPolicy: .observed
        )
    }

    private func pendingSets(
        count: Int,
        reps: Int,
        rir: Double,
        type: SetType = .working,
        repRange: ClosedRange<Int>? = nil,
        startingIndex: Int = 0,
        startingNumber: Int = 1
    ) -> [SuggestionPendingSetInput] {
        (0..<count).map { offset in
            SuggestionPendingSetInput(
                setId: UUID(),
                setIndex: startingIndex + offset,
                setNumber: startingNumber + offset,
                target: SuggestionTarget(
                    reps: reps,
                    rir: rir,
                    repRange: repRange,
                    repsSource: .explicitSet,
                    rirSource: .explicitSet
                ),
                setType: type
            )
        }
    }

    private func completedSet(
        weight: Double,
        reps: Int,
        rir: Double?,
        type: SetType = .working,
        restSeconds: Int? = nil,
        order: Int
    ) -> SessionSetContext {
        SessionSetContext(
            weight: weight,
            reps: reps,
            rir: rir,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(order) * 300),
            completed: true,
            setType: type,
            restDurationSeconds: restSeconds
        )
    }

    private func evaluate(
        baseE1RM: Double = 100,
        baseSource: E1RMSource = .recentPerformance,
        completed: [SessionSetContext] = [],
        pending: [SuggestionPendingSetInput],
        settings: SuggestionSettingsSnapshot
    ) -> [SuggestionDecision] {
        SuggestionEngine.evaluate(
            SuggestionEngineInput(
                baseE1RM: baseE1RM,
                baseSource: baseSource,
                completedSessionSets: completed,
                pendingSets: pending,
                settings: settings,
                calibrationAdjustment: .neutral
            )
        )
    }

    // MARK: - Reporting

    private func report(_ title: String, _ note: String, _ decisions: [SuggestionDecision]) {
        print("\n=== \(title) ===")
        print(note)
        print("set |  weight | vs set1 | fatigue | discount | effE1RM | reps")
        print("----+---------+---------+---------+----------+---------+-----")
        let first = decisions.first?.prescribedWeight ?? 0
        for d in decisions {
            let delta = first > 0 ? (d.prescribedWeight / first - 1.0) * 100 : 0
            print(String(
                format: "%3d | %6.1f  | %+6.1f%% | %6.1f%% |   %.3f  | %7.1f | %d",
                d.setNumber,
                d.prescribedWeight,
                delta,
                d.projectedSessionFatigue * 100,
                d.fatigueDiscount,
                d.effectiveE1RM,
                d.bestReps ?? d.targetReps
            ))
        }
    }

    private func weights(_ decisions: [SuggestionDecision]) -> [Double] {
        decisions.map(\.prescribedWeight)
    }

    // MARK: - A. Straight sets, the ordinary case

    func testA1_StraightSetsDefaultSettings() {
        let decisions = evaluate(
            pending: pendingSets(count: 4, reps: 8, rir: 2),
            settings: settings()
        )
        report(
            "A1 — 4×8 @ RIR 2, e1RM 100 kg, 150 s rest, defaults",
            "The single most common session shape. Set 1 should price ~8+2=10 reps off a 100 kg e1RM.",
            decisions
        )
        XCTAssertEqual(decisions.count, 4)
    }

    func testA2_RestLengthChangesTheDrop() {
        for rest in [60.0, 90.0, 150.0, 240.0, 420.0] {
            let decisions = evaluate(
                pending: pendingSets(count: 4, reps: 8, rir: 2),
                settings: settings(rest: rest)
            )
            report(
                "A2 — 4×8 @ RIR 2, rest \(Int(rest)) s",
                "Longer rest should recover more fatigue between sets and hold weight higher.",
                decisions
            )
        }
    }

    func testA3_FatigueOffIsFlat() {
        let decisions = evaluate(
            pending: pendingSets(count: 4, reps: 8, rir: 2),
            settings: settings(fatigueEnabled: false)
        )
        report(
            "A3 — same session, Fatigue toggle OFF",
            "Every set should price identically; this is the control line for A1.",
            decisions
        )
        XCTAssertEqual(Set(weights(decisions)).count, 1, "Fatigue off should produce one flat weight")
    }

    func testA4_LearnedRateBounds() {
        for rate in [0.01, 0.03, 0.05, 0.08] {
            let decisions = evaluate(
                pending: pendingSets(count: 4, reps: 8, rir: 2),
                settings: settings(baseFatigueRate: rate)
            )
            report(
                "A4 — 4×8 @ RIR 2, learned fatigue rate \(rate)",
                "0.01 and 0.08 are the bounds FatigueLearningService can learn to (fatigueRateBounds).",
                decisions
            )
        }
    }

    // MARK: - B. Does it listen to what I actually did?

    func testB1_OverperformanceRaisesLaterSets() {
        let completed = [
            completedSet(weight: 85, reps: 8, rir: 1, restSeconds: 150, order: 0)
        ]
        let decisions = evaluate(
            completed: completed,
            pending: pendingSets(count: 3, reps: 8, rir: 2, startingIndex: 1, startingNumber: 2),
            settings: settings()
        )
        report(
            "B1 — set 1 logged HEAVY: 85 kg × 8 @ RIR 1 (suggested was ~75)",
            "Lifter beat the suggestion. Sets 2-4 should climb toward the demonstrated capability.",
            decisions
        )
    }

    func testB2_UnderperformanceLowersLaterSets() {
        let completed = [
            completedSet(weight: 75, reps: 5, rir: 0, restSeconds: 150, order: 0)
        ]
        let decisions = evaluate(
            completed: completed,
            pending: pendingSets(count: 3, reps: 8, rir: 2, startingIndex: 1, startingNumber: 2),
            settings: settings()
        )
        report(
            "B2 — set 1 logged SHORT: 75 kg × 5 @ RIR 0 (target was 8 @ RIR 2)",
            "Lifter missed the target and hit failure. Sets 2-4 should back off.",
            decisions
        )
    }

    func testB3_EasySetAtHighRIRIsIgnored() {
        for rir in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0] {
            let completed = [
                completedSet(weight: 75, reps: 8, rir: rir, restSeconds: 150, order: 0)
            ]
            let decisions = evaluate(
                completed: completed,
                pending: pendingSets(count: 1, reps: 8, rir: 2, startingIndex: 1, startingNumber: 2),
                settings: settings()
            )
            report(
                "B3 — set 1 was 75 kg × 8 @ RIR \(Int(rir)), what does set 2 price?",
                "RIR < 3 updates session capability; RIR >= 3 does not (normalizedObservedCapability guard).",
                decisions
            )
        }
    }

    func testB4_MissingRIRSet() {
        let completed = [
            completedSet(weight: 75, reps: 8, rir: nil, restSeconds: 150, order: 0)
        ]
        let decisions = evaluate(
            completed: completed,
            pending: pendingSets(count: 3, reps: 8, rir: 2, startingIndex: 1, startingNumber: 2),
            settings: settings()
        )
        report(
            "B4 — set 1 logged with NO RIR (75 kg × 8)",
            "Most users never fill RIR. Capability can't update; fatigue assumes RIR 1 (missingRIRDefault).",
            decisions
        )
    }

    // MARK: - C. Set types

    func testC1_WarmupsAreFree() {
        let withWarmups = [
            completedSet(weight: 40, reps: 10, rir: 5, type: .warmup, restSeconds: 90, order: 0),
            completedSet(weight: 60, reps: 5, rir: 4, type: .warmup, restSeconds: 90, order: 1)
        ]
        let cold = evaluate(
            pending: pendingSets(count: 3, reps: 8, rir: 2),
            settings: settings()
        )
        let warm = evaluate(
            completed: withWarmups,
            pending: pendingSets(count: 3, reps: 8, rir: 2, startingIndex: 2),
            settings: settings()
        )
        report("C1a — no warmups, 3 working sets", "Control.", cold)
        report("C1b — two warmups first, then 3 working sets", "Warmups must not cost anything.", warm)
        XCTAssertEqual(weights(cold), weights(warm), "Warmups should not change working-set prescriptions")
    }

    func testC2_HardSetTypesCostMore() {
        for type in [SetType.backoff, .working, .dropset, .amrap, .failure] {
            let completed = [
                completedSet(weight: 75, reps: 8, rir: 1, type: type, restSeconds: 150, order: 0)
            ]
            let decisions = evaluate(
                completed: completed,
                pending: pendingSets(count: 1, reps: 8, rir: 2, startingIndex: 1, startingNumber: 2),
                settings: settings()
            )
            report(
                "C2 — set 1 was a \(type.rawValue) set (75 kg × 8 @ RIR 1), set 2 prices at:",
                "Multipliers: backoff 0.7, working 1.0, dropset 1.4, amrap 1.5, failure 1.5.",
                decisions
            )
        }
    }

    // MARK: - D. Long sessions and the clamp

    func testD1_TenSetSessionHitsTheFatigueCeiling() {
        let decisions = evaluate(
            pending: pendingSets(count: 10, reps: 8, rir: 2),
            settings: settings()
        )
        report(
            "D1 — 10 straight sets of 8 @ RIR 2",
            "maxFatigue clamps at 25%. Is a 25%-off final set believable for set 10?",
            decisions
        )
    }

    func testD2_HighRepAndLowRepSessions() {
        for (reps, rir) in [(20, 2), (12, 2), (8, 2), (5, 2), (3, 1)] {
            let decisions = evaluate(
                pending: pendingSets(count: 4, reps: reps, rir: Double(rir)),
                settings: settings()
            )
            report(
                "D2 — 4 sets of \(reps) @ RIR \(rir)",
                "repScale = clamp(reps/8, 0.6...1.5); effortScale = 1 + max(0, 3-RIR)*0.15.",
                decisions
            )
        }
    }

    func testD3_ShortRestHighRepMetconStyle() {
        let decisions = evaluate(
            pending: pendingSets(count: 6, reps: 15, rir: 1),
            settings: settings(rest: 60)
        )
        report(
            "D3 — 6×15 @ RIR 1 on 60 s rest (worst realistic case)",
            "Highest fatigue accrual the model can see from ordinary input.",
            decisions
        )
    }

    // MARK: - E. Rep ranges and first-set behaviour

    func testE1_RepRangeSession() {
        let decisions = evaluate(
            pending: pendingSets(count: 4, reps: 8, rir: 2, repRange: 6...10),
            settings: settings()
        )
        report(
            "E1 — 4 sets, rep range 6-10 @ RIR 2, e1RM 100",
            "Engine picks one rep count per set. Watch whether reps drift as fatigue builds.",
            decisions
        )
    }

    func testE2_FreshnessBonusOn() {
        let off = evaluate(pending: pendingSets(count: 4, reps: 8, rir: 2), settings: settings())
        let on = evaluate(
            pending: pendingSets(count: 4, reps: 8, rir: 2),
            settings: settings(freshnessEnabled: true)
        )
        report("E2a — freshness OFF (default)", "Control.", off)
        report("E2b — freshness ON at 3%", "Only set 1 should lift.", on)
    }

    // MARK: - F. Thin history

    func testF1_SingleDataPointBeginner() {
        let decisions = evaluate(
            baseE1RM: 42.5,
            baseSource: .recentPerformance,
            pending: pendingSets(count: 3, reps: 10, rir: 3),
            settings: settings(increment: 2.5)
        )
        report(
            "F1 — beginner, e1RM 42.5 kg, 3×10 @ RIR 3",
            "Small absolute loads: does 2.5 kg rounding swamp the fatigue signal?",
            decisions
        )
    }

    func testF2_RoundingGranularity() {
        for increment in [1.0, 2.5, 5.0] {
            let decisions = evaluate(
                pending: pendingSets(count: 4, reps: 8, rir: 2),
                settings: settings(increment: increment)
            )
            report(
                "F2 — 4×8 @ RIR 2, plate increment \(increment) kg",
                "Fatigue steps are small; coarse rounding may erase them entirely.",
                decisions
            )
        }
    }

    // MARK: - G. Confirmation probes

    func testG1_CanTheFatigueCeilingEverBeReached() {
        let cases: [(String, Double, Double, Int, Double)] = [
            ("defaults: rate .03, 150 s, 8 @ RIR 2", 0.03, 150, 8, 2),
            ("learned max rate .08, 150 s, 8 @ RIR 2", 0.08, 150, 8, 2),
            ("learned max rate .08, 60 s, 12 @ RIR 0", 0.08, 60, 12, 0),
            ("learned max rate .08, 45 s, 20 @ RIR 0", 0.08, 45, 20, 0)
        ]
        for (label, rate, rest, reps, rir) in cases {
            let decisions = evaluate(
                pending: pendingSets(count: 12, reps: reps, rir: rir),
                settings: settings(rest: rest, baseFatigueRate: rate)
            )
            let peak = decisions.map(\.projectedSessionFatigue).max() ?? 0
            print("\n=== G1 — \(label) ===")
            print(String(format: "12 sets. Peak projected fatigue: %.1f%% (ceiling is 25.0%%). Reached ceiling: %@",
                         peak * 100, peak >= 0.2499 ? "YES" : "no"))
            let unique = Array(Set(weights(decisions))).sorted(by: >)
            print("Distinct prescribed weights across 12 sets: \(unique)")
        }
    }

    func testG2_RepRangeStabilityAcrossSession() {
        for range in [6...10, 8...12, 5...8] {
            let decisions = evaluate(
                pending: pendingSets(count: 6, reps: (range.lowerBound + range.upperBound) / 2,
                                     rir: 2, repRange: range),
                settings: settings()
            )
            report(
                "G2 — 6 sets, rep range \(range.lowerBound)-\(range.upperBound) @ RIR 2",
                "Does the prescribed WEIGHT fall monotonically, or does it bounce as the rep pick flips?",
                decisions
            )
            let ws = weights(decisions)
            let bounces = zip(ws, ws.dropFirst()).filter { $1 > $0 }.count
            print("Upward weight jumps mid-session: \(bounces) (a lifter expects 0)")
            print("Rep picks in order: \(decisions.map { $0.bestReps ?? $0.targetReps })")
        }
    }

    func testG3_FixedRepsStayMonotonic() {
        let decisions = evaluate(
            pending: pendingSets(count: 6, reps: 8, rir: 2),
            settings: settings()
        )
        let ws = weights(decisions)
        let bounces = zip(ws, ws.dropFirst()).filter { $1 > $0 }.count
        print("\n=== G3 — fixed 8 reps, 6 sets: control for G2 ===")
        print("Weights: \(ws)")
        print("Upward weight jumps mid-session: \(bounces)")
        XCTAssertEqual(bounces, 0, "Fixed-rep sessions should never step the weight back up")
    }

    // MARK: - H. Follow-up probes

    /// The `missingRIRDefault = 1.0` question: what does a no-RIR history actually cost,
    /// versus the same sets logged at RIR 2?
    func testH1_NoRIRVersusRIR2History() {
        for (label, rir) in [("no RIR logged (current: treated as RIR 1)", Double?.none),
                             ("logged at RIR 2 (what the fix would assume)", Double?.some(2))] {
            let completed = (0..<4).map { i in
                completedSet(weight: 75, reps: 8, rir: rir, restSeconds: 150, order: i)
            }
            let decisions = evaluate(
                completed: completed,
                pending: pendingSets(count: 3, reps: 8, rir: 2, startingIndex: 4, startingNumber: 5),
                settings: settings()
            )
            report("H1 — 4 completed sets, \(label)", "Sets 5-7 price at:", decisions)
        }
    }

    /// Worry #2: rest defaults to the configured timer on ~98% of sets. What does assuming
    /// 150 s cost when the lifter actually rests 180 s or 240 s?
    func testH2_RestAssumptionCost() {
        for rest in [150.0, 180.0, 240.0] {
            let decisions = evaluate(
                pending: pendingSets(count: 4, reps: 8, rir: 2),
                settings: settings(rest: rest)
            )
            report("H2 — assumed rest \(Int(rest)) s", "150 s is the engine default; 180 s is the observed median.", decisions)
        }
    }
}
