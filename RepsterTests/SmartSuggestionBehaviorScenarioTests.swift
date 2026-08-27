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
///     touch RepsterTests/Fixtures/Local/REGENERATE_GOLDEN_MASTER
///     xcodebuild test -scheme Repster -destination 'id=<sim>' \
///       -only-testing:RepsterTests/SuggestionEngineGoldenMasterTests
///
/// A marker file rather than an environment variable, matching `CrossContextRaceTests`: tests run
/// inside the simulator, so a shell variable never reaches them. The marker is consumed on use, so
/// a regeneration can't be left switched on by accident. `Fixtures/Local/` is gitignored.
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

        let marker = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Local/REGENERATE_GOLDEN_MASTER")
        if FileManager.default.fileExists(atPath: marker.path) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try snapshot.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: marker)
            XCTFail("""
                Golden master regenerated at \(url.path), and the marker consumed.
                Review `git diff` on the fixture, commit it, then re-run.
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
              touch RepsterTests/Fixtures/Local/REGENERATE_GOLDEN_MASTER
              xcodebuild test -scheme Repster -destination 'id=<sim>' \\
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

// MARK: - The suggestion floor (PR4)

/// The floor: never price below a weight already completed this session with reps to spare.
///
/// This is how RIR >= 3 sets are credited. The alternative — letting them raise the capability
/// point estimate at some damped weight — needs a constant nobody can justify: only 5.0% of
/// app-era logged RIR values are >= 3 (29 sets), which cannot separate 30% damping from 50%. The
/// floor needs no constant and cannot overshoot: it can never exceed one increment above a weight
/// the lifter actually completed.
///
/// Cases follow SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md D1-D9.
final class SuggestionFloorTests: XCTestCase {

    private func target(reps: Int, rir: Double) -> SuggestionTarget {
        SuggestionTarget(
            reps: reps, rir: rir, repRange: nil,
            repsSource: .explicitSet, rirSource: .explicitSet
        )
    }

    private func done(
        _ weight: Double, _ reps: Int, rir: Double?,
        type: SetType = .working, order: Int = 0
    ) -> SessionSetContext {
        SessionSetContext(
            weight: weight, reps: reps, rir: rir,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(order) * 300),
            completed: true, setType: type, restDurationSeconds: 150
        )
    }

    private func floor(
        _ completed: [SessionSetContext],
        reps: Int = 8, rir: Double = 0, increment: Double = 2.5
    ) -> SuggestionEngine.SuggestionFloor? {
        SuggestionEngine.suggestionFloor(
            target: target(reps: reps, rir: rir),
            completedSets: completed,
            increment: increment
        )
    }

    /// The reported regression: 20x8 then 35x8, both at the top-of-scale "5+" chip, against a
    /// target of 8 @ RIR 0. The app suggested 32.5 kg — below a weight just completed with five
    /// reps to spare. Real capacity that session was 45 x 10.
    func testTheReportedLegExtensionCaseIsFloored() {
        let result = floor([done(20, 8, rir: 5, order: 0), done(35, 8, rir: 5, order: 1)])

        XCTAssertEqual(result?.weight, 37.5, "one increment above the 35 kg that was demonstrably too light")
        XCTAssertEqual(result?.completedWeight, 35)
    }

    /// D2, lower edge: no reserve, no floor. The model may legitimately go lighter.
    func testNoSurplusMeansNoFloor() {
        XCTAssertNil(floor([done(35, 8, rir: 0)]))
    }

    /// D2: two reps of reserve is ~2.6% of load and does not clear the fatigue the model is
    /// entitled to claim between sets.
    func testSurplusBelowThresholdDoesNotFloor() {
        XCTAssertNil(floor([done(35, 8, rir: 2)]))
    }

    /// D2, exactly at the threshold.
    func testSurplusOfExactlyThreeFloors() {
        XCTAssertEqual(floor([done(35, 8, rir: 3)])?.weight, 37.5)
    }

    /// D1: the comparison is on *total* reps, so a harder target can outrun a demonstrated set
    /// even when the performed reps were fewer.
    func testTargetHarderThanDemonstratedDoesNotFloor() {
        // 35 x 8 @ RIR 5 demonstrates 13 total; a target of 15 @ RIR 0 asks for more.
        XCTAssertNil(floor([done(35, 8, rir: 5)], reps: 15, rir: 0))
    }

    /// D1: …and a target inside what was demonstrated still floors even when it asks for *more
    /// performed reps* than the set did — 10 > 8 — because the comparison is on totals.
    ///
    /// Note the interaction with D2, which the design doc's D1 example glosses over: 35 x 8 @ RIR 5
    /// demonstrates 13 total, so a target of 12 @ RIR 0 has a surplus of only 1 and does **not**
    /// floor. D2's threshold governs. A target of 10 @ RIR 0 clears it at surplus 3.
    func testTargetInsideWhatWasDemonstratedFloorsOnceTheSurplusClearsTheThreshold() {
        XCTAssertEqual(floor([done(35, 8, rir: 5)], reps: 10, rir: 0)?.weight, 37.5)
        XCTAssertNil(floor([done(35, 8, rir: 5)], reps: 12, rir: 0),
                     "surplus of 1 does not beat the fatigue the model may claim")
    }

    /// D4: every qualifying set contributes and the maximum wins — an earlier heavier set still
    /// bounds the answer when the most recent one was lighter.
    func testTheHighestQualifyingFloorWins() {
        let result = floor([done(40, 8, rir: 3, order: 0), done(35, 8, rir: 5, order: 1)])

        XCTAssertEqual(result?.weight, 42.5, "42.5 from the 40 kg set beats 37.5 from the 35 kg one")
    }

    /// D6: `missingRIRDefault` must not leak in here. Assuming a reserve nobody reported would
    /// invent a floor out of nothing.
    func testMissingRIRContributesNoFloor() {
        XCTAssertNil(floor([done(35, 8, rir: nil)]))
    }

    /// D3: expressed as "next grid value above", so an off-grid entry floors correctly.
    func testOffGridWeightFloorsToTheNextGridValue() {
        XCTAssertEqual(floor([done(33, 8, rir: 5)])?.weight, 35.0, "not 37.5")
    }

    /// D3: a weight already exactly on the grid still moves strictly up — the surplus proves that
    /// weight was too light.
    func testOnGridWeightFloorsStrictlyAbove() {
        XCTAssertEqual(floor([done(35, 8, rir: 5)])?.weight, 37.5)
    }

    /// D5: a drop set's trailing RIR does not describe its opening weight; a partial's reps are
    /// not comparable to a full-ROM target.
    func testExcludedSetTypesContributeNoFloor() {
        for type in [SetType.dropset, .partial, .myo, .restpause, .cluster, .warmup] {
            XCTAssertNil(
                floor([done(35, 8, rir: 5, type: type)]),
                "\(type.rawValue) must not establish a floor"
            )
        }
    }

    /// D5: back-off sets *do* qualify. A back-off at RIR 5 is a poor point estimate of capacity
    /// and a perfectly good lower bound — the distinction the two predicates exist to name.
    func testBackoffSetsDoEstablishAFloor() {
        XCTAssertEqual(floor([done(35, 8, rir: 5, type: .backoff)])?.weight, 37.5)
    }

    /// A set at RIR 5 on a 5 kg grid floors a whole increment, not a fractional one.
    func testFloorRespectsTheConfiguredIncrement() {
        XCTAssertEqual(floor([done(35, 8, rir: 5)], increment: 5.0)?.weight, 40.0)
        XCTAssertEqual(floor([done(35, 8, rir: 5)], increment: 1.0)?.weight, 36.0)
    }

    /// D9 + D7 end-to-end: the floor reaches the prescription and says so, rather than being
    /// applied silently behind the fatigue explanation.
    func testFloorReachesThePrescriptionAndIsNamed() {
        let pending = (0..<2).map { offset in
            SuggestionPendingSetInput(
                setId: UUID(), setIndex: 2 + offset, setNumber: 3 + offset,
                target: target(reps: 8, rir: 0), setType: .working
            )
        }
        let decisions = SuggestionEngine.evaluate(
            SuggestionEngineInput(
                baseE1RM: 44.33,
                baseSource: .recentPerformance,
                completedSessionSets: [done(20, 8, rir: 5, order: 0), done(35, 8, rir: 5, order: 1)],
                pendingSets: pending,
                settings: SuggestionSettingsSnapshot(
                    formula: .epley, restTimerSeconds: 150, weightIncrement: 2.5,
                    fatigueEnabled: true, freshnessEnabled: false, freshnessPercent: 0.03,
                    baseFatigueRate: 0.03, recoveryConstant: 180, sessionCapabilityPolicy: .observed
                ),
                calibrationAdjustment: .neutral
            )
        )

        XCTAssertEqual(decisions[0].prescribedWeight, 37.5, "was 32.5 — below a set just completed")
        XCTAssertEqual(decisions[0].selectionPolicy, .floorHeldAboveCompletedSet)
        XCTAssertEqual(decisions[0].appliedFloor?.completedWeight, 35)

        // D9: applies to every pending set, not only the next one.
        XCTAssertEqual(decisions[1].prescribedWeight, 37.5)
        XCTAssertEqual(decisions[1].selectionPolicy, .floorHeldAboveCompletedSet)
    }

    /// The floor must not fire when the model is already above it — it is a guardrail, not a
    /// target, and it must never *lower* an answer.
    func testFloorNeverLowersAnAnswerTheModelPutHigher() {
        let pending = [
            SuggestionPendingSetInput(
                setId: UUID(), setIndex: 1, setNumber: 2,
                target: target(reps: 8, rir: 0), setType: .working
            )
        ]
        let decisions = SuggestionEngine.evaluate(
            SuggestionEngineInput(
                baseE1RM: 150,
                baseSource: .recentPerformance,
                completedSessionSets: [done(35, 8, rir: 5, order: 0)],
                pendingSets: pending,
                settings: SuggestionSettingsSnapshot(
                    formula: .epley, restTimerSeconds: 150, weightIncrement: 2.5,
                    fatigueEnabled: true, freshnessEnabled: false, freshnessPercent: 0.03,
                    baseFatigueRate: 0.03, recoveryConstant: 180, sessionCapabilityPolicy: .observed
                ),
                calibrationAdjustment: .neutral
            )
        )

        XCTAssertGreaterThan(decisions[0].prescribedWeight, 37.5)
        XCTAssertNotEqual(decisions[0].selectionPolicy, .floorHeldAboveCompletedSet)
        XCTAssertNil(decisions[0].appliedFloor)
    }

    func testNoCompletedSetsMeansNoFloor() {
        XCTAssertNil(floor([]))
    }
}

// MARK: - Capability crediting (PR4)

/// What may *set* the session capability estimate, and how far one set may move it.
///
/// `.observed` replaces the estimate outright rather than blending, so a single unrepresentative
/// set becomes the capability figure for every remaining set of the exercise. Two guards: a type
/// allowlist for the labelled cases, and a downward clamp for the far commoner unlabelled ones.
final class SessionCapabilityCreditingTests: XCTestCase {

    private func settings(increment: Double = 2.5) -> SuggestionSettingsSnapshot {
        SuggestionSettingsSnapshot(
            formula: .epley, restTimerSeconds: 150, weightIncrement: increment,
            fatigueEnabled: true, freshnessEnabled: false, freshnessPercent: 0.03,
            baseFatigueRate: 0.03, recoveryConstant: 180, sessionCapabilityPolicy: .observed
        )
    }

    private func done(
        _ weight: Double, _ reps: Int, rir: Double?,
        type: SetType = .working, order: Int = 0
    ) -> SessionSetContext {
        SessionSetContext(
            weight: weight, reps: reps, rir: rir,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(order) * 300),
            completed: true, setType: type, restDurationSeconds: 150
        )
    }

    private func capability(after completed: [SessionSetContext], baseE1RM: Double = 133) -> Double {
        SuggestionEngine.evaluate(
            SuggestionEngineInput(
                baseE1RM: baseE1RM,
                baseSource: .recentPerformance,
                completedSessionSets: completed,
                pendingSets: [
                    SuggestionPendingSetInput(
                        setId: UUID(), setIndex: 9, setNumber: 10,
                        target: SuggestionTarget(
                            reps: 8, rir: 2, repRange: nil,
                            repsSource: .explicitSet, rirSource: .explicitSet
                        ),
                        setType: .working
                    )
                ],
                settings: settings(),
                calibrationAdjustment: .neutral
            )
        )[0].sessionCapabilityE1RM
    }

    /// A drop set is submaximal by definition; it must not become the capability figure. Before
    /// this, a 100 x 8 @ RIR 2 top set followed by a 60 x 10 drop had the engine concluding
    /// capacity fell ~38% mid-exercise.
    func testADropSetDoesNotReplaceTheCapabilityEstimate() {
        let withDrop = capability(after: [
            done(100, 8, rir: 2, order: 0),
            done(60, 10, rir: 0, type: .dropset, order: 1)
        ])
        let withoutDrop = capability(after: [done(100, 8, rir: 2, order: 0)])

        XCTAssertEqual(withDrop, withoutDrop, accuracy: 0.01,
                       "the drop set must leave the estimate exactly where the top set put it")
    }

    /// AMRAP and failure sets are the *best* capacity evidence available and must keep counting.
    func testAmrapAndFailureStillSetTheEstimate() {
        for type in [SetType.amrap, .failure] {
            let after = capability(after: [done(110, 8, rir: 0, type: type, order: 0)])
            XCTAssertGreaterThan(after, 133, "\(type.rawValue) must still raise capability")
        }
    }

    /// The same numbers logged as a plain working set — the unlabelled case the allowlist cannot
    /// catch — are held to the clamp instead of cratering the estimate.
    func testAnUntaggedLightSetIsClampedRatherThanReplacingTheEstimate() {
        let after = capability(after: [
            done(100, 8, rir: 2, order: 0),
            done(60, 10, rir: 0, type: .working, order: 1)
        ])

        // The 100 kg set puts capability at 133.3; the light set alone would imply ~80.
        XCTAssertGreaterThanOrEqual(after, 133.3 * 0.8 - 0.5,
                                    "one set may not pull capability down more than 20%")
        XCTAssertLessThan(after, 133.4, "it should still move down — the clamp bounds it, not blocks it")
    }

    /// Upward moves are deliberately uncapped: a set that beats the estimate is direct evidence
    /// the estimate was low. This is why no upward clamp exists.
    func testUpwardMovesAreNotClamped() {
        let after = capability(after: [done(150, 8, rir: 0, order: 0)], baseE1RM: 100)

        XCTAssertEqual(after, 190.0, accuracy: 1.0,
                       "Epley on 150 x 8 is 190 — a 90% jump, and it must pass through")
    }

    /// Sets at RIR >= 3 still do not move the point estimate. That is deliberate and unchanged:
    /// the floor covers them instead, which is the half of the signal that is trustworthy.
    func testHighRIRSetsStillDoNotMoveThePointEstimate() {
        let after = capability(after: [done(100, 8, rir: 4, order: 0)], baseE1RM: 100)

        XCTAssertEqual(after, 100, accuracy: 0.01)
    }

    /// The freshness bonus must not be re-armed by narrowing what counts as capacity evidence: a
    /// set *after* a drop set is not a first set, whatever the drop set contributed.
    func testADropSetStillCountsAsHavingStartedWorking() {
        let settings = SuggestionSettingsSnapshot(
            formula: .epley, restTimerSeconds: 150, weightIncrement: 2.5,
            fatigueEnabled: true, freshnessEnabled: true, freshnessPercent: 0.03,
            baseFatigueRate: 0.03, recoveryConstant: 180, sessionCapabilityPolicy: .observed
        )
        let decisions = SuggestionEngine.evaluate(
            SuggestionEngineInput(
                baseE1RM: 100,
                baseSource: .recentPerformance,
                completedSessionSets: [done(60, 10, rir: 0, type: .dropset, order: 0)],
                pendingSets: [
                    SuggestionPendingSetInput(
                        setId: UUID(), setIndex: 1, setNumber: 2,
                        target: SuggestionTarget(
                            reps: 8, rir: 2, repRange: nil,
                            repsSource: .explicitSet, rirSource: .explicitSet
                        ),
                        setType: .working
                    )
                ],
                settings: settings,
                calibrationAdjustment: .neutral
            )
        )

        XCTAssertFalse(decisions[0].freshnessApplied,
                       "a set after a drop set must not claim the first-set freshness bonus")
    }
}

// MARK: - Missing-RIR fallback (PR5)

/// What a set is charged when the lifter ticked it complete without tapping the RIR chip.
///
/// `missingRIRDefault = 1.0` modelled such a set as *harder* than one explicitly marked RIR 2
/// (effort scale 1.30 vs 1.15), so leaving the chip blank cost an increment on the next set. It
/// governs 21.4% of app-era sets. Assuming the RIR the set was *prescribed* at beats any global
/// constant: it adapts to whatever the lifter programmed and needs no tuning.
final class MissingRIRFallbackTests: XCTestCase {

    private func settings() -> SuggestionSettingsSnapshot {
        SuggestionSettingsSnapshot(
            formula: .epley, restTimerSeconds: 150, weightIncrement: 2.5,
            fatigueEnabled: true, freshnessEnabled: false, freshnessPercent: 0.03,
            baseFatigueRate: 0.03, recoveryConstant: 180, sessionCapabilityPolicy: .observed
        )
    }

    private func done(
        _ weight: Double, _ reps: Int, rir: Double?, targetRIR: Double? = nil, order: Int
    ) -> SessionSetContext {
        SessionSetContext(
            weight: weight, reps: reps, rir: rir,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(order) * 300),
            completed: true, setType: .working, restDurationSeconds: 150,
            targetRIR: targetRIR
        )
    }

    private func decision(after completed: [SessionSetContext]) -> SuggestionDecision {
        SuggestionEngine.evaluate(
            SuggestionEngineInput(
                baseE1RM: 100, baseSource: .recentPerformance,
                completedSessionSets: completed,
                pendingSets: [
                    SuggestionPendingSetInput(
                        setId: UUID(), setIndex: 4, setNumber: 5,
                        target: SuggestionTarget(
                            reps: 8, rir: 2, repRange: nil,
                            repsSource: .explicitSet, rirSource: .explicitSet
                        ),
                        setType: .working
                    )
                ],
                settings: settings(), calibrationAdjustment: .neutral
            )
        )[0]
    }

    /// Fatigue is the only thing this fallback touches, so it is the only thing compared here.
    ///
    /// Prescribed weight would be the wrong assertion: an unlabelled set also cannot update the
    /// capability estimate, so comparing weights measures two effects at once and the fatigue
    /// change disappears into the larger one.
    private func fatigue(after completed: [SessionSetContext]) -> Double {
        decision(after: completed).projectedSessionFatigue
    }

    /// The headline: four unlabelled sets prescribed at RIR 2 are charged exactly what four sets
    /// explicitly logged at RIR 2 are charged, rather than as if they were near failure.
    func testUnlabelledSetsAreChargedAtTheirPrescribedRIR() {
        let unlabelled = (0..<4).map { done(75, 8, rir: nil, targetRIR: 2, order: $0) }
        let explicit = (0..<4).map { done(75, 8, rir: 2, order: $0) }

        XCTAssertEqual(fatigue(after: unlabelled), fatigue(after: explicit), accuracy: 1e-9)
    }

    /// And that is strictly cheaper than the old constant, which is the defect: leaving the chip
    /// blank must not cost the lifter anything.
    func testThePrescribedTargetIsCheaperThanTheOldConstant() {
        let withTarget = (0..<4).map { done(75, 8, rir: nil, targetRIR: 2, order: $0) }
        let withoutTarget = (0..<4).map { done(75, 8, rir: nil, order: $0) }

        XCTAssertLessThan(
            fatigue(after: withTarget), fatigue(after: withoutTarget),
            "missingRIRDefault = 1.0 charges an unlabelled set as harder than an explicit RIR 2"
        )
    }

    /// A reported RIR always wins — the target describes what was asked for, not what happened.
    func testAReportedRIRBeatsTheTarget() {
        let reported = (0..<4).map { done(75, 8, rir: 0, targetRIR: 5, order: $0) }
        let matching = (0..<4).map { done(75, 8, rir: 0, order: $0) }

        XCTAssertEqual(fatigue(after: reported), fatigue(after: matching), accuracy: 1e-9)
        XCTAssertEqual(
            decision(after: reported).prescribedWeight,
            decision(after: matching).prescribedWeight
        )
    }

    /// With no RIR *and* no resolvable target, the engine keeps its own last-resort constant
    /// rather than assuming anything.
    func testNoRIRAndNoTargetFallsBackToTheConstant() {
        let neither = (0..<4).map { done(75, 8, rir: nil, order: $0) }
        let atRIR1 = (0..<4).map { done(75, 8, rir: 1, order: $0) }

        XCTAssertEqual(fatigue(after: neither), fatigue(after: atRIR1), accuracy: 1e-9,
                       "missingRIRDefault is 1.0, so the cost must match an explicit RIR 1")
    }

    /// The fallback is for fatigue *cost* only. Capability is evidence about the lifter, and a
    /// target is not evidence — crediting it would let the app invent capacity from its own
    /// programming.
    func testTheTargetNeverMovesTheCapabilityEstimate() {
        let decisions = SuggestionEngine.evaluate(
            SuggestionEngineInput(
                baseE1RM: 100, baseSource: .recentPerformance,
                completedSessionSets: [done(120, 8, rir: nil, targetRIR: 0, order: 0)],
                pendingSets: [
                    SuggestionPendingSetInput(
                        setId: UUID(), setIndex: 1, setNumber: 2,
                        target: SuggestionTarget(
                            reps: 8, rir: 2, repRange: nil,
                            repsSource: .explicitSet, rirSource: .explicitSet
                        ),
                        setType: .working
                    )
                ],
                settings: settings(), calibrationAdjustment: .neutral
            )
        )

        XCTAssertEqual(decisions[0].sessionCapabilityE1RM, 100, accuracy: 0.01,
                       "a 120 kg set with no reported RIR must not raise capability")
    }

    /// Nor may it establish a floor — same reasoning, and the floor design says so explicitly (D6).
    func testTheTargetNeverEstablishesAFloor() {
        XCTAssertNil(
            SuggestionEngine.suggestionFloor(
                target: SuggestionTarget(
                    reps: 8, rir: 0, repRange: nil,
                    repsSource: .explicitSet, rirSource: .explicitSet
                ),
                completedSets: [done(100, 8, rir: nil, targetRIR: 5, order: 0)],
                increment: 2.5
            )
        )
    }
}
