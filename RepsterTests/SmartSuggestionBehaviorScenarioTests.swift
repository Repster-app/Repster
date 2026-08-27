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

// MARK: - Golden master

/// Frozen numeric snapshot of `SuggestionEngine.evaluate`.
///
/// `SmartSuggestionBehaviorScenarioTests` above prints its numbers for a human to judge;
/// nothing stores them, so a change in the engine produces no reviewable artefact. This
/// class serialises a fixed scenario matrix to
/// `RepsterTests/Fixtures/SuggestionEngineGoldenMaster.txt` and fails on any difference.
///
/// Every PR in SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md is expected to either leave this
/// file byte-identical (PR1, PR2) or change it deliberately (PR3-PR7). When it changes on
/// purpose, regenerate and **read the diff** — that diff is the release note for the
/// suggestion engine:
///
///     REGENERATE_SUGGESTION_GOLDEN_MASTER=1 xcodebuild test -scheme Repster \
///       -only-testing:RepsterTests/SuggestionEngineGoldenMasterTests
final class SuggestionEngineGoldenMasterTests: XCTestCase {

    // MARK: Fixture location

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SuggestionEngineGoldenMaster.txt")
    }

    // MARK: Builders (self-contained — the class above keeps its helpers private)

    private func settings(
        rest: Double = 150,
        fatigueEnabled: Bool = true,
        baseFatigueRate: Double = 0.03,
        recoveryConstant: Double = 180,
        increment: Double = 2.5,
        freshnessEnabled: Bool = false,
        freshnessPercent: Double = 0.03,
        formula: E1RMFormula = .epley,
        policy: SessionCapabilityPolicy = .observed
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
            sessionCapabilityPolicy: policy
        )
    }

    private func pending(
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

    private func done(
        _ weight: Double,
        _ reps: Int,
        rir: Double?,
        type: SetType = .working,
        rest: Int? = 150,
        order: Int
    ) -> SessionSetContext {
        SessionSetContext(
            weight: weight,
            reps: reps,
            rir: rir,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(order) * 300),
            completed: true,
            setType: type,
            restDurationSeconds: rest
        )
    }

    private func evaluate(
        baseE1RM: Double = 100,
        baseSource: E1RMSource = .recentPerformance,
        completed: [SessionSetContext] = [],
        pending sets: [SuggestionPendingSetInput],
        settings s: SuggestionSettingsSnapshot
    ) -> [SuggestionDecision] {
        SuggestionEngine.evaluate(
            SuggestionEngineInput(
                baseE1RM: baseE1RM,
                baseSource: baseSource,
                completedSessionSets: completed,
                pendingSets: sets,
                settings: s,
                calibrationAdjustment: .neutral
            )
        )
    }

    // MARK: Serialisation

    /// Fixed-precision so a genuine behaviour change shows up and float noise does not.
    private func render(_ name: String, _ decisions: [SuggestionDecision]) -> String {
        var out = "## \(name)\n"
        for d in decisions {
            let reps = d.bestReps.map(String.init) ?? "-"
            out += String(
                format: "  set %d | w %8.4f | eff %9.4f | cap %9.4f | fat %.4f | disc %.4f | if %.4f | reps %@ | policy %@ | fresh %@\n",
                d.setNumber,
                d.prescribedWeight,
                d.effectiveE1RM,
                d.sessionCapabilityE1RM,
                d.projectedSessionFatigue,
                d.fatigueDiscount,
                d.intensityFactor,
                reps,
                d.selectionPolicy.label,
                d.freshnessApplied ? "y" : "n"
            )
        }
        return out
    }

    // MARK: The matrix
    //
    // Ordered by the PR expected to move each block, so a diff reads as a changelog.

    private func buildSnapshot() -> String {
        var out = """
        Smart Suggestions engine — golden master
        Generated by SuggestionEngineGoldenMasterTests. Do not hand-edit.
        See SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md §1 (PF1).


        """

        // --- Baseline behaviour: expected to survive every PR unchanged -------------

        out += render("A1 straight 4x8 @ RIR 2, defaults", evaluate(
            pending: pending(count: 4, reps: 8, rir: 2), settings: settings()))

        out += render("A2 same, 60 s rest", evaluate(
            pending: pending(count: 4, reps: 8, rir: 2), settings: settings(rest: 60)))

        out += render("A3 same, 420 s rest", evaluate(
            pending: pending(count: 4, reps: 8, rir: 2), settings: settings(rest: 420)))

        out += render("A4 fatigue disabled", evaluate(
            pending: pending(count: 4, reps: 8, rir: 2), settings: settings(fatigueEnabled: false)))

        out += render("A5 learned rate floor 0.01", evaluate(
            pending: pending(count: 4, reps: 8, rir: 2), settings: settings(baseFatigueRate: 0.01)))

        out += render("A6 learned rate ceiling 0.08", evaluate(
            pending: pending(count: 4, reps: 8, rir: 2), settings: settings(baseFatigueRate: 0.08)))

        out += render("A7 twelve sets — fatigue saturation", evaluate(
            pending: pending(count: 12, reps: 8, rir: 2), settings: settings()))

        out += render("A8 freshness bonus on", evaluate(
            pending: pending(count: 3, reps: 8, rir: 2), settings: settings(freshnessEnabled: true)))

        // --- PR3: baseline reads RIR ------------------------------------------------

        out += render("B1 fixed target 8 @ RIR 0, no history", evaluate(
            baseE1RM: 76.0, pending: pending(count: 3, reps: 8, rir: 0),
            settings: settings(increment: 1.25)))

        out += render("B2 fixed target 8 @ RIR 2, no history", evaluate(
            baseE1RM: 76.0, pending: pending(count: 3, reps: 8, rir: 2),
            settings: settings(increment: 1.25)))

        // --- PR4: capability crediting and the floor --------------------------------

        for rir in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0] {
            out += render("C1 one completed 75x8 @ RIR \(Int(rir)) — what set 2 prices", evaluate(
                completed: [done(75, 8, rir: rir, order: 0)],
                pending: pending(count: 2, reps: 8, rir: 2, startingIndex: 1, startingNumber: 2),
                settings: settings()))
        }

        out += render("C2 the 32.5 kg leg-extension case (20x8 then 35x8, both RIR 5)", evaluate(
            baseE1RM: 44.33,
            completed: [done(20, 8, rir: 5, order: 0), done(35, 8, rir: 5, order: 1)],
            pending: pending(count: 2, reps: 8, rir: 0, startingIndex: 2, startingNumber: 3),
            settings: settings()))

        out += render("C3 drop set craters capability (100x8 @ RIR 2, then 60x10 @ RIR 0)", evaluate(
            baseE1RM: 133,
            completed: [done(100, 8, rir: 2, order: 0),
                        done(60, 10, rir: 0, type: .dropset, rest: 0, order: 1)],
            pending: pending(count: 2, reps: 8, rir: 2, startingIndex: 2, startingNumber: 3),
            settings: settings()))

        out += render("C4 untagged light set craters capability (same numbers, type working)", evaluate(
            baseE1RM: 133,
            completed: [done(100, 8, rir: 2, order: 0),
                        done(60, 10, rir: 0, type: .working, rest: 0, order: 1)],
            pending: pending(count: 2, reps: 8, rir: 2, startingIndex: 2, startingNumber: 3),
            settings: settings()))

        out += render("C5 overperformance raises later sets (85x8 @ RIR 1 vs 75 suggested)", evaluate(
            completed: [done(85, 8, rir: 1, order: 0)],
            pending: pending(count: 3, reps: 8, rir: 2, startingIndex: 1, startingNumber: 2),
            settings: settings()))

        out += render("C6 underperformance lowers later sets (65x6 @ RIR 0)", evaluate(
            completed: [done(65, 6, rir: 0, order: 0)],
            pending: pending(count: 3, reps: 8, rir: 2, startingIndex: 1, startingNumber: 2),
            settings: settings()))

        out += render("C7 warm-ups are free", evaluate(
            completed: [done(40, 10, rir: 5, type: .warmup, order: 0),
                        done(60, 5, rir: 4, type: .warmup, order: 1)],
            pending: pending(count: 3, reps: 8, rir: 2, startingIndex: 2, startingNumber: 1),
            settings: settings()))

        // --- PR5: missing-RIR fallback ----------------------------------------------

        out += render("D1 four completed sets, no RIR recorded", evaluate(
            completed: (0..<4).map { done(75, 8, rir: nil, order: $0) },
            pending: pending(count: 2, reps: 8, rir: 2, startingIndex: 4, startingNumber: 5),
            settings: settings()))

        out += render("D2 same four sets at RIR 2", evaluate(
            completed: (0..<4).map { done(75, 8, rir: 2, order: $0) },
            pending: pending(count: 2, reps: 8, rir: 2, startingIndex: 4, startingNumber: 5),
            settings: settings()))

        // --- PR12: set-type multipliers ---------------------------------------------

        for type in [SetType.backoff, .working, .dropset, .amrap, .failure, .partial] {
            out += render("E1 one 75x8 @ RIR 1 logged as \(type.rawValue)", evaluate(
                completed: [done(75, 8, rir: 1, type: type, order: 0)],
                pending: pending(count: 2, reps: 8, rir: 2, startingIndex: 1, startingNumber: 2),
                settings: settings()))
        }

        // --- Rep ranges and rounding: guard rails for the progression work ----------

        out += render("F1 rep range 5-8 across four sets", evaluate(
            pending: pending(count: 4, reps: 8, rir: 2, repRange: 5...8), settings: settings()))

        out += render("F2 first-set range progression (the 58.75 / 9 reps case)", evaluate(
            baseE1RM: 76.0,
            pending: pending(count: 1, reps: 8, rir: 0, repRange: 6...10),
            settings: settings(increment: 1.25)))

        out += render("F3 beginner, 1 kg increment", evaluate(
            baseE1RM: 42.5, pending: pending(count: 3, reps: 10, rir: 2),
            settings: settings(increment: 1.0)))

        out += render("F4 beginner, 2.5 kg increment", evaluate(
            baseE1RM: 42.5, pending: pending(count: 3, reps: 10, rir: 2),
            settings: settings(increment: 2.5)))

        out += render("F5 beginner, 5 kg increment", evaluate(
            baseE1RM: 42.5, pending: pending(count: 3, reps: 10, rir: 2),
            settings: settings(increment: 5.0)))

        out += render("F6 high rep 4x20", evaluate(
            pending: pending(count: 4, reps: 20, rir: 2), settings: settings()))

        out += render("F7 low rep 4x3", evaluate(
            pending: pending(count: 4, reps: 3, rir: 2), settings: settings()))

        return out
    }

    // MARK: The test

    func testEngineOutputMatchesGoldenMaster() throws {
        let snapshot = buildSnapshot()
        let url = fixtureURL

        if ProcessInfo.processInfo.environment["REGENERATE_SUGGESTION_GOLDEN_MASTER"] == "1" {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try snapshot.write(to: url, atomically: true, encoding: .utf8)
            XCTFail("""
                Golden master regenerated at \(url.path).
                Review the diff, commit it, then re-run without the environment variable.
                """)
            return
        }

        guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try snapshot.write(to: url, atomically: true, encoding: .utf8)
            XCTFail("""
                No golden master existed; wrote one to \(url.path).
                Review it, commit it, then re-run.
                """)
            return
        }

        guard snapshot != expected else { return }

        let expectedLines = expected.components(separatedBy: "\n")
        let actualLines = snapshot.components(separatedBy: "\n")
        var diff: [String] = []
        for index in 0..<max(expectedLines.count, actualLines.count) {
            let old = index < expectedLines.count ? expectedLines[index] : "<missing>"
            let new = index < actualLines.count ? actualLines[index] : "<missing>"
            guard old != new else { continue }
            diff.append("line \(index + 1):\n  - \(old)\n  + \(new)")
            if diff.count >= 40 {
                diff.append("… further differences truncated")
                break
            }
        }

        XCTFail("""
            Smart Suggestions engine output changed.

            \(diff.joined(separator: "\n"))

            If this change is intended, regenerate and commit the diff:
              REGENERATE_SUGGESTION_GOLDEN_MASTER=1 xcodebuild test -scheme Repster \\
                -only-testing:RepsterTests/SuggestionEngineGoldenMasterTests
            """)
    }
}

// MARK: - Completed-set target resolution (PR2)

/// Pins how a completed set's *prescribed* RIR is recovered.
///
/// The engine needs this for sets the lifter ticked complete without tapping the RIR chip. The
/// obvious source — `WorkoutSet.targetRIR` — is written **only** by `TemplateService`, so it is
/// nil on every ad-hoc set; sourcing the fallback from that field would make it a silent no-op
/// for anyone not running templates. These tests exist to keep that mistake from being
/// reintroduced: the resolution must survive a set that has no template behind it at all.
///
/// Background: SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md G1.
final class CompletedSetTargetResolutionTests: XCTestCase {

    private func makeExercise() -> Exercise {
        Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            weightIncrement: 2.5,
            defaultRestTime: 120
        )
    }

    private func makeSet(
        exerciseId: UUID,
        reps: Int = 8,
        rir: Double? = nil,
        targetRIR: Int? = nil,
        weight: Double = 75,
        type: SetType = .working
    ) -> WorkoutSet {
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseId,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            weight: weight,
            reps: reps,
            rir: rir,
            setType: type,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true,
            targetRIR: targetRIR
        )
        return set
    }

    private func contexts(
        _ sets: [WorkoutSet],
        exercise: Exercise,
        defaultTargetRIR: Int = 2
    ) -> [SessionSetContext] {
        let profile = HealthProfile()
        profile.prescriptionDefaultTargetRIR = defaultTargetRIR
        return SuggestionCoordinator.completedSessionSets(
            from: sets,
            exercise: ChartExerciseData(from: exercise),
            profile: profile
        )
    }

    /// The case the naive implementation would have missed: no template, no target on the set,
    /// no RIR logged. The profile default must still come through.
    func testAdHocSetWithNoRIRResolvesTheProfileDefaultTarget() {
        let exercise = makeExercise()
        let set = makeSet(exerciseId: exercise.id, rir: nil, targetRIR: nil)

        let resolved = contexts([set], exercise: exercise, defaultTargetRIR: 2)

        XCTAssertEqual(resolved.count, 1)
        XCTAssertNil(resolved[0].rir, "no RIR was logged")
        XCTAssertEqual(resolved[0].targetRIR, 2.0, "must fall back to the profile default target")
    }

    /// A template-driven set prefers its own target over the profile default.
    func testTemplateTargetBeatsTheProfileDefault() {
        let exercise = makeExercise()
        let set = makeSet(exerciseId: exercise.id, rir: nil, targetRIR: 4)

        let resolved = contexts([set], exercise: exercise, defaultTargetRIR: 2)

        XCTAssertEqual(resolved[0].targetRIR, 4.0)
    }

    /// When the lifter actually reported an RIR there is nothing to fall back to, and carrying a
    /// target as well would invite a later change to prefer the wrong one.
    func testLoggedRIRLeavesNoTargetFallback() {
        let exercise = makeExercise()
        let set = makeSet(exerciseId: exercise.id, rir: 1, targetRIR: 4)

        let resolved = contexts([set], exercise: exercise, defaultTargetRIR: 2)

        XCTAssertEqual(resolved[0].rir, 1.0)
        XCTAssertNil(resolved[0].targetRIR)
    }

    /// A profile with no default and no template target resolves nothing — the engine must keep
    /// its own last-resort constant rather than be handed a fabricated number.
    func testNoTargetAnywhereResolvesNil() {
        let exercise = makeExercise()
        let set = makeSet(exerciseId: exercise.id, rir: nil, targetRIR: nil)
        let profile = HealthProfile()
        profile.prescriptionDefaultTargetRIR = nil

        let resolved = SuggestionCoordinator.completedSessionSets(
            from: [set],
            exercise: ChartExerciseData(from: exercise),
            profile: profile
        )

        XCTAssertNil(resolved[0].targetRIR)
    }

    /// Warm-ups never reach the engine, so they must not appear here regardless of target.
    func testWarmupsAreStillExcluded() {
        let exercise = makeExercise()
        let warmup = makeSet(exerciseId: exercise.id, rir: nil, targetRIR: 3, type: .warmup)
        let working = makeSet(exerciseId: exercise.id, rir: nil, targetRIR: 3, type: .working)

        let resolved = contexts([warmup, working], exercise: exercise)

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].setType, .working)
    }

    /// Drop sets are not capacity evidence, but they are still completed work and must still be
    /// handed to the engine — they accrue fatigue.
    func testDropSetsAreStillPassedToTheEngine() {
        let exercise = makeExercise()
        let drop = makeSet(exerciseId: exercise.id, rir: 0, type: .dropset)

        let resolved = contexts([drop], exercise: exercise)

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].setType, .dropset)
    }

    /// Callers with no exercise or profile to hand still get contexts. Only the *profile default*
    /// tier of the fallback chain goes missing — a set carrying its own target still resolves it,
    /// because that tier reads the set, not the profile.
    func testCallersWithoutContextStillResolveASetsOwnTarget() {
        let exercise = makeExercise()
        let set = makeSet(exerciseId: exercise.id, rir: nil, targetRIR: 3)

        let resolved = SuggestionCoordinator.completedSessionSets(from: [set])

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].targetRIR, 3.0)
    }

    /// …but with no context *and* no target on the set, there is nothing to resolve, and the
    /// engine must fall back to its own constant rather than be handed a fabricated number.
    func testCallersWithoutContextAndNoSetTargetResolveNil() {
        let exercise = makeExercise()
        let set = makeSet(exerciseId: exercise.id, rir: nil, targetRIR: nil)

        let resolved = SuggestionCoordinator.completedSessionSets(from: [set])

        XCTAssertNil(resolved[0].targetRIR)
    }
}
