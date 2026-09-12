# Unilateral imbalance — spec for technical scoping

**Date:** 2026-09-10, updated 2026-09-12 with the reframe (D21–D23) · **Branch:** `NewMain` · **Status:** building for 1.6 (D20). Code: `SidesAnalysis.swift`, `BodyMapView.swift`, `BodyMapPaths.swift` (generated), `SidesCardView.swift`, `SideGroupDetailView.swift`, `SidesAnalysisTests.swift`; generator `scripts/generate_body_paths.py`.

**Mockups:**
- [Muscle Map Bars](https://claude.ai/code/artifact/bd6927b5-0459-4f43-88a6-ef02a9b4a188) — **the current design**: the Sides card and the Legs deep dive with plain-words rows (D13, D14).
- [Muscle Map Directions](https://claude.ai/code/artifact/9334ca32-5a0a-44a4-92ca-9a71548b7918) — earlier card and deep-dive screens. Superseded where they differ: diverging bars, the Volume toggle, the wording.
- [Muscle Map Catalog](https://claude.ai/code/artifact/1c61c39e-5493-4881-892b-ee3a451a8190) — all 14 original versions; IDs such as E1, S1, U4 refer to it.

---

## 0. Summary

- A body map card on **Training Insights** shows which muscle groups have an imbalance on unilateral exercises. It never says which side — that belongs to each exercise (D21).
- Tapping a group opens a **deep dive**: the group's exercises ranked by imbalance, and from there each exercise's session-by-session detail. This is the only place per-exercise detail lives.
- One metric: **capacity per side = reps + reps in reserve**, compared *within the same set*, so load is controlled by construction.
- Plain words: each row says **"Right is clearly stronger"** — the degree is slightly, clearly or much. No numbers in the lists.
- Descriptive only. Blue for both sides, never red. No cause, injury or advice in the copy.
- **No schema change**, **no Coach dependency**, and no screen touched outside Insights.
- Reach is the constraint: only exercises flagged unilateral can report sides — 6 of the 69 seeded exercises today.

---

## 1. Problem and goals

Repster records left and right reps and RIR for unilateral exercises, then collapses them to the stronger side before anything reads them ([WorkoutSet.swift:173](Repster/Data/Models/WorkoutSet.swift#L173)). PRs, e1RM, charts and Smart Suggestions all see one side. Nothing surfaces the difference, though it is the most distinctive signal in the data ([COACH_ANALYSIS_SCOPING.md](COACH_ANALYSIS_SCOPING.md) A9).

**Goals**

1. See at a glance which muscle groups lean to one side.
2. Open a group and see which exercises cause it.
3. Tell a pattern from noise — consistency is always shown next to size.
4. Never imply injury, fault or a prescription.

**Non-goals:** per-side load, advice, muscle-level attribution (quads vs glutes), detecting which side went first, changing how PRs are computed, anything during a workout.

---

## 2. Decisions

| # | Decision | Chosen | Rejected | Date |
|---|---|---|---|---|
| D1 | Focus | Left/right imbalance is the headline. No volume view on the card for now (D15) | Volume-first body map | 2026-09-10 |
| D2 | Body artwork | react-native-body-highlighter 3.2.0 path data, MIT | Hand-drawn figures (tried twice) | 2026-09-10 |
| D3 | Card | **E1** — body, headline, group list (body shading superseded by D21) | E2 gap heat, E4 no body. E3 callouts kept as runner-up | 2026-09-10 |
| D4 | Stance | Descriptive; blue on both sides; no cause or advice | Red for the weaker side; "fix your imbalance" | 2026-09-09 |
| D5 | Deep dive | **Required**, and the only home for per-exercise detail: card → group → exercise | — | 2026-09-10 |
| D6 | Workout summary | **Nothing** — no sides content, no teaser subtitle | U2 as drawn; a Coach teaser subtitle | 2026-09-11 |
| D7 | Findings card | **Optional** — the first thing to cut | — | 2026-09-11 |
| D8 | Exercise editor prompt | Out (U5) | — | 2026-09-10 |
| D9 | Difference in list rows | Replace the diverging bars; they read as confusing. Replaced by D13 and D14 | Diverging bars | 2026-09-11 |
| D10 | Card states | **S1** building and **S2** even. With no both-sides data the card is hidden | S3 nothing tracked, S4 closing gap | 2026-09-11 |
| D11 | Exercise detail screen | Unchanged — no Sides tab, no per-side PR columns | U3 in that location | 2026-09-11 |
| D12 | During a workout | Nothing — no per-side recall, no Match sides for now | U1, U1b | 2026-09-11 |
| D13 | Wording | Plain sentences — "Right is clearly stronger", "Even". Degree in three words (slightly / clearly / much) with a three-step strength mark. No "R +2" or "7 of 8" in lists; reps only in the exercise drill-down | "Leans right", "R +2 · 7 of 8" | 2026-09-11 |
| D14 | Row design | **W1** — the sentence plus a three-step strength mark | W2 lean marker; B1–B4 bar designs | 2026-09-11 |
| D15 | Volume view | Not now — the shipped muscle panel stays untouched; the card shows sides only | Sides / Volume toggle | 2026-09-11 |
| D16 | Pricing | Free by default — nothing in Insights checks subscription status | Behind the paywall | 2026-09-11 |
| D17 | Gate values (superseded by D22) | §5.5 accepted as starting values, to be tuned on cohort data | — | 2026-09-11 |
| D18 | Deep-dive chart | **C2 difference columns** — one column per session, up for right, down for left, 1–3 steps tall; no axis numbers. Picked by default (the recommendation) when no choice was made; the chart is one view, easy to swap | C1 who-was-stronger, C3 quiet lines | 2026-09-11 |
| D19 | Coverage | Ship as is: **no changes to built-in or existing exercises**, no seed expansion, no migration | Flag more seed exercises; migrate existing users | 2026-09-11 |
| D20 | Release | **1.6** | Later | 2026-09-11 |
| D21 | Map and groups | **The map shows only whether a muscle group has an imbalance; each exercise carries the direction.** A group lights up when any of its exercises shows a stronger side; the deep dive lists every exercise with its own "Left is slightly stronger" | Lead & trail shading on the body (D3's body); a group-level stronger side; a "mixed" state; pooling a group into one chart; splitting Legs into quads/hamstrings by name | 2026-09-12 |
| D22 | Exercise rules | Last 6 sessions within 12 weeks; ≥ 3 sessions where the sides differed, same side ahead in ≥ 75% of them; average gap across all 6 (equal sessions count as zero) ≥ half a rep; "5+" is a floor against a measured side; once there are 3 sessions, few differences = Even, not "collecting" | 8-week window; 6-session minimum; median gap; ties counting against consistency | 2026-09-12 |
| D23 | Acceptance | The maintainer's pattern must show — right quad weaker on one-leg extension and left hamstring weaker on one-leg curl, logged as matched reps with different RIR; the same imbalance logged as different reps must read the same; evening out must reach Even within 4 sessions; a flip must pass through Even. Pinned in `SidesAnalysisTests` on synthetic data | — | 2026-09-12 |
| D24 | Unconfirmed lean | When the sessions that differed agree and the average is at least half a rep, but fewer than 3 sessions differed: "Left seems stronger — needs more sessions to confirm", no strength mark. Its group reads "Possible imbalance in N exercises" and stays dim on the map; the card headline says "Possible imbalance in N muscle groups" only when nothing is confirmed | Calling it Even — what 1 Legged Hip Thrust showed with left ahead by 1.5 and 2 reps in 2 of 3 sessions | 2026-09-12 |

**Gate values accepted as starting values (D17).** The capacity metric (§5.2) is proposed and has not been challenged.

### What these decisions add up to

- **The whole feature lives in Insights.** No Coach dependency, no change to the workout, summary, exercise or editor screens.
- **No trend maths.** S4 is out, so there is no weekly gap series to compute.
- **Discoverability drops.** With S3 out, anyone without a both-sides set in the window never sees the card, and nothing in the app tells them it exists. With coverage at 6 of 69 seeded exercises, that is most users today. See P10.
- **The findings rule can slip a release.** Nothing else depends on it.

---

## 3. Scope

### v1

| Item | Ref | Notes |
|---|---|---|
| Sides card on Training Insights | E1 | Rows per D13 and D14 |
| Card states: building, even; hidden when there's no data | S1, S2 | §4.2 |
| Group deep dive | Directions "Legs", extended per §4.3 | Required |
| Exercise drill-down, including best reps per side | §4.4 | Reached only from the deep dive |

### Optional in v1

| Item | Ref | Notes |
|---|---|---|
| Findings card, rule `lateralAsymmetry` | U4 | First to cut |

### Undecided

| Item | See |
|---|---|

**Later:** Match sides (U1b).
**Out:** U1, U2, U3 on exercise detail, U5, S3, S4, E2, E4; a volume view on the card, for now; per-side load, side order, secondary-muscle attribution, medical framing.

---

## 4. Experience

### 4.1 Where it lives

Training Insights ([InsightsView.swift](Repster/Features/Insights/Views/InsightsView.swift)) is a three-item stack today: training status card → muscle panel → findings. The Sides card is a fourth item, above the muscle panel. The muscle panel stays exactly as it is (D15).

When Coach ships, Insights moves one tap down inside the Coach destination ([REPSTER_COACH_SCOPING.md](REPSTER_COACH_SCOPING.md) §3.3) and the card moves with it unchanged. Coach is Wave 3 in its own sequencing, several releases out; nothing here waits for it.

### 4.2 The Sides card (D21)

Top to bottom: section header `LEFT VS RIGHT · RECENT SESSIONS` · headline and subtitle · front and back figures · legend · group list · coverage note.

The map shows **where** there is an imbalance, never which side. Direction lives on each exercise (§4.3), because exercises in one group can lean different ways: quads and hamstrings both sit in "legs", and one lifter's can disagree.

| Region | When | Fill |
|---|---|---|
| Imbalance found | ≥ 1 exercise in the group shows a stronger side | `sidesImbalance` (accent `#5B8DEF`) |
| Even | exercises have enough sessions and none shows a stronger side | `sidesEven` `#456AB5` |
| Collecting | a possible imbalance still being confirmed (D24), or no exercise with 3 sessions yet | `sidesCollecting` `#353D53` |
| Not tracked | nothing in the group logs both sides | `bodyBase` `#2A2B33` |

**Headline:** "Imbalance found in 1 muscle group" · "Imbalances found in {n} muscle groups" · "Possible imbalance in 1 muscle group" (nothing confirmed yet, D24) · "Both sides are even" (S2) · "Building your baseline" (S1).
**Subtitle:** "Your last 6 sessions of each exercise, compared at the same weight"; while building, "Each exercise needs 3 sessions with both sides logged".
**Group rows:** name · "Imbalance in 2 exercises" / "Possible imbalance in 1 exercise" / "Even" / "Needs 1 more session" · chevron. No strength mark on a group — degree belongs to an exercise.
**Coverage note:** names groups trained recently that nothing tracks by side.
**Hidden** when no unilateral exercise has a both-sides set in the lookback (D10).

### 4.3 Group deep dive

Opens as a sheet from a body region or a group row.

**Header** — thumbnail with this group lit · group name · status line ("An imbalance in 2 of the 4 exercises you track here" / "Even on every exercise with enough sessions" / "Needs 1 more session with both sides logged") · chip with the tracked-exercise count.

**EXERCISES** — every exercise with this primary group done in the lookback, one row each:

1. **Stronger side**, largest degree first — "Left is slightly stronger" plus the strength mark (D14)
2. **Seems stronger** — "Left seems stronger — needs more sessions to confirm" (D24)
3. **Even**
4. **Collecting** — "Needs 1 more session"
5. **Not tracked by side** — greyed, with the reason

Footnote: "Each exercise is judged on its last 6 sessions, comparing both sides at the same weight."

No group-level chart: averaging exercises that lean different ways would draw a line through a disagreement. Each exercise's own chart is one tap down.

### 4.4 Exercise drill-down

Only reachable from the deep dive (D11), and the only place numbers appear. Exercise name and status line ("Your right side has been stronger in 4 of your last 6 sessions" / "Your sides matched in all of your last 6 sessions" / "No consistent difference across your last 6 sessions") · the C2 chart of those sessions · the gap in reps ("About 2 more reps on your right, at the same weight") · capacity per side, session by session · **best reps per side at each weight** · a data-quality note counting one-side-only sets in the window (§5.6).

### 4.5 Findings card — optional (D7)

If kept: unchanged [InsightCardView.swift](Repster/Features/Insights/Views/InsightCardView.swift) anatomy, category pill **SIDES**, a two-bar Left/Right comparison, methodology on expand. Rule in §5.7.

### 4.6 Copy rules (D13)

- Say which side is stronger, in a sentence: "Right is clearly stronger". Never call the other side weak or weaker; never "imbalance to fix", "injury", "compensate".
- Degree in one of three words — slightly, clearly, much (§5.3) — backed by the strength mark.
- Sides are the lifter's own: "your right side". The front view mirrors, so every figure carries R/L markers.
- No numbers in the card or the deep-dive lists. Reps appear only in the exercise drill-down; never percentages.
- Consistency is a gate, not a label: a row only says "stronger" once the same side led in 6 of 8 sessions. The count is printed in the deep-dive header only.

---

## 5. Definitions and computation

Every constant here is a starting value chosen from one lifter's shape of data. Repster has 200+ users; check them against the cohort before release.

### 5.1 Eligibility

**Exercise** — `unilateral == true` and `trackingType.supportsUnilateralLogging` (`weightReps`, `weightRepsDuration`; [TrackingType.swift:33](Repster/Data/Enums/TrackingType.swift#L33)). Group is `ExercisePrimaryGroup.normalizedValue(primaryMuscle)`, excluding `cardio` and `full body` (`statusExcludedGroups`, [InsightsService.swift:491](Repster/Core/Services/InsightsService.swift#L491)). Primary muscle only, matching the volume panel.

**Set** — all of:

- completed. `InsightsService.buildContext` already fetches `completed == true` ([InsightsService.swift:689](Repster/Core/Services/InsightsService.swift#L689)), which also keeps the unperformed-rows defect out ([UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md)).
- in `InsightAnalysisContext.eligibleWorkingSets` ([InsightsService.swift:116](Repster/Core/Services/InsightsService.swift#L116)) — honours workout-level and per-exercise progression exclusions, drops warm-ups and partials.
- `setType.isCapacityPointEstimate` — working, AMRAP, failure ([SetType](Repster/Data/Enums/SetType.swift)). Excludes drop, back-off, myo, rest-pause, cluster, tempo, isometric, eccentric: all submaximal or fragmented.
- both `leftReps` and `rightReps` greater than 0.

**Weight is not required.** Both sides of a set share it, so the comparison is load-controlled by construction, and bodyweight unilateral work (weight nil) still qualifies.

### 5.2 Capacity per side (proposed)

```
if leftRIR and rightRIR are both in 0...4:
    cap(side) = reps(side) + RIR(side)
elif one side is 0...4 and the other is 5 ("5+"):
    cap(side) = reps(side) + RIR(side)   # 5+ as 5: direction certain, size a floor
else:
    cap(side) = reps(side)          # RIR missing on a side, or both 5+: reps alone

gap = cap(right) - cap(left)        # positive = right ahead
```

- RIR is stored as 5 for the "5+" chip ([SetRowView.swift:38](Repster/Features/Workout/Views/SetRowView.swift#L38)). It's a floor, not a value: against a side at 0–4 it counts as 5; against another 5+ it tells us nothing.
- This reads both ways people log: the same reps with different RIR (8 @ RIR 1 vs 8 @ RIR 3 → gap 2) and different reps (8 vs 10 at RIR 0 → gap 2).

### 5.3 Per exercise (D22)

- **Sessions:** the exercise's last 6 sessions with both sides logged, ignoring anything older than 12 weeks. A session is one workout: capacity per side is the median across its eligible sets; the session gap is right minus left; under half a rep is a tie.
- **Collecting** under 3 sessions.
- **Stronger** when both hold:
  - *direction* — at least 3 sessions where the sides differed, the same side ahead in ≥ 75% of them. Equal sessions don't count against it.
  - *size* — the average gap across all the sessions, equal ones counting as zero, is at least half a rep in that direction.
- **Seems stronger** (D24) when direction and size hold but fewer than 3 sessions differed: "Left seems stronger — needs more sessions to confirm", no strength mark. A lean on too few sessions is not evidence of evenness.
- **Even** otherwise — including an exercise that used to lean and has evened out.
- **Degree:** average gap ÷ mean capacity — under 12% *slightly*, 12–25% *clearly*, 25% and over *much*.

**Why this shape.** People show an imbalance two ways. Some do different reps; as it evens out, their gap gets *smaller*. Others match reps and let RIR carry it; as it evens out, their gap shows up *less often*, because RIR is a whole number. An average that counts equal sessions as zero falls in both cases; a median of only the sessions that differed would freeze for the second group. Users reliably know which side went to failure and which had more left, so matched-rep RIR differences are treated as real evidence.

### 5.4 Per muscle group (D21)

**Imbalance** if any of its tracked exercises is stronger on one side (the row counts them); else **Possible imbalance** if any seems stronger (D24); else **Even** if at least one has enough sessions and none leans; **Collecting** otherwise. Nothing is pooled across exercises.

### 5.5 Gate values (D22)

| Constant | Value | Why |
|---|---|---|
| `sessionsConsidered` | 6 | Recent whatever the frequency: twice a week is the last three weeks |
| `lookbackDays` | 84 | A lift you stopped doing drops out |
| `minSessions` | 3 | Below this, collecting |
| `minDifferingSessions` | 3 | A single odd session or set can't set a direction |
| `minConsistency` | 0.75 | Same side ahead in three of every four sessions that differed |
| `minAverageGap` | 0.5 rep | Evening out shows up as this falling |
| `usableRIR` / `censoredRIR` | 0…4 / 5 | "5+" is a floor against a measured side |
| `degreeClearly` / `degreeMuch` | 12% / 25% | Relative to the reps involved |
| `tieBelow` | 0.5 rep | Session gaps under this are a tie |

Starting values — check them on cohort data, not one lifter's.

### 5.6 One-side-only sets

Sets on a tracked exercise where exactly one of `leftReps` / `rightReps` is set are excluded and counted. Sets with RIR on one side only are compared on reps alone (a blank isn't failure) and counted. Both counts appear as a note in the exercise view.

### 5.7 Findings rule — only if D7 keeps it

- **ruleId** `lateralAsymmetry` — the name reserved in [TRAINING_INSIGHTS_V2_DESIGN.md](TRAINING_INSIGHTS_V2_DESIGN.md) §5, conforming to `InsightRule` ([InsightsService.swift:132](Repster/Core/Services/InsightsService.swift#L132)).
- **Fires** once per leaning group. **Subject:** see T7.
- **Tone** `.diagnostic`. **Chart** `.comparison`, labels `["Left", "Right"]`, values `[capL, capR]`. **effectSize** = |m| ÷ mean capacity.
- **Copy:** "Your {side} side has been stronger on {group} in {k} of your last {n} sessions" · "About {m} more reps at the same weight, across {exercises}" · "Capacity is reps plus reps in reserve at the same weight. {n} sessions with both sides logged."

### 5.8 Body map

**Artwork** — react-native-body-highlighter 3.2.0 (MIT, © 2022 ELABBASSI Hicham). Front 19 regions / 89 paths, back 16 / 70. ViewBoxes `0 0 724 1448` (front) and `724 0 724 1448` (back).

**The mirror trap** — the library's `left` and `right` are the **viewer's**, in both views. On the front view its `left` paths are the figure's *right* side.

| View | Figure's left | Figure's right |
|---|---|---|
| Front | library `right` | library `left` |
| Back | library `left` | library `right` |

**Region → group**

| Repster group | Front regions | Back regions |
|---|---|---|
| chest | chest | — |
| back | trapezius | trapezius, upper-back, lower-back |
| shoulders | deltoids | deltoids |
| biceps | biceps | — |
| triceps | triceps | triceps |
| forearms | forearm | forearm |
| abs | abs, obliques | — |
| legs | quadriceps, adductors | gluteal, hamstring, adductors |
| calves (custom group) | calves, tibialis | calves |
| not a muscle | head, hair, neck, hands, feet, knees, ankles | head, hair, neck, hands, feet, ankles |

Custom groups map where a region exists (`glutes` → gluteal, `hamstrings` → hamstring, `quads` → quadriceps); anything else is listed but not drawn.

**Fills** (D21) — by the group's status, the same on both sides of the figure:

| Group status | Fill |
|---|---|
| Imbalance | `sidesImbalance` `#5B8DEF` |
| Even | `sidesEven` `#456AB5` |
| Possible imbalance, or collecting | `sidesCollecting` `#353D53` |
| Not tracked, or not a muscle | `bodyBase` `#2A2B33`, hair `#202127` |

The mirror-trap mapping is still used for geometry and still pinned by tests, but the map no longer shades by side.

Outline stroke `#3A3C46`.

---

## 6. Constraints — what the data can't say

- **Load per side.** One `weight` per set; different dumbbells per side can't be logged.
- **Which side went first.** Not recorded. The second side works tired, so a one-rep gap can be order, not strength — hence the one-rep floor and the consistency gate.
- **Individual muscles.** The app knows `legs`, not quads against glutes. The figure can draw them; the data can't separate them.
- **Why.** No cause, injury or advice.

---

## 7. Dependencies

### 7.1 The engine reads the stronger side

The derivation rewrites `reps = max(left, right)` and `rir` = the RIR of the side that did more reps, or the lower RIR when reps tie ([WorkoutSet.swift:124](Repster/Data/Models/WorkoutSet.swift#L124), [:143](Repster/Data/Models/WorkoutSet.swift#L143)). e1RM is computed from the derived reps ([SetService.swift:158](Repster/Core/Services/SetService.swift#L158)). So when reps differ, Smart Suggestions prices load from the stronger side; when reps are matched, it already takes the harder side's RIR.

[SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md](SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md) G11 already flags the per-side trap. Not a blocker for this feature, which only describes history, but someone who reads "legs lean right" and then gets a weight priced off the right leg will notice. See T3.

### 7.2 Coverage

- 6 of 69 seeded exercises are flagged unilateral: Dumbbell Row, Dumbbell Curl, Hammer Curl, Dumbbell Lunge, Cable Lateral Raise, Bulgarian Split Squat.
- Seeding runs only when the exercise table is empty ([SeedService.swift](Repster/Core/Services/SeedService.swift)). Adding or re-flagging seed exercises reaches **new installs only**; existing users need a migration.
- CSV imports create fresh, unflagged records.
- Turning the flag on for an exercise with history only helps from then on; older sets have no sides.

### 7.3 Coach

None (D6, D11, D12).

### 7.4 Unperformed sets

Sides inherits protection from the Insights fetch (`completed == true`). Nothing in this feature reads history outside that path.

### 7.5 License notice

MIT requires the notice to ship with the app. There is no acknowledgements screen today (T5).

---

## 8. Technical touchpoints

Everything is inside Insights, plus analytics.

| Area | Files | Change |
|---|---|---|
| Computation | [InsightsService.swift](Repster/Core/Services/InsightsService.swift) | New pure `static func sidesStatus(from: InsightAnalysisContext)` beside `trainingStatus(from:)`; returns groups → exercises → sessions |
| Models | [InsightsServiceProtocol.swift](Repster/Core/Services/Protocols/InsightsServiceProtocol.swift) | `SidesStatus`, group and exercise summaries; `InsightCategory` gains a sides case only if D7 keeps the findings card |
| View model | [InsightsViewModel.swift](Repster/Features/Insights/ViewModels/InsightsViewModel.swift) | Load `sidesStatus` alongside `status` |
| Views | `Repster/Features/Insights/Views/` | `BodyMapView` (front/back, fills per region side), `SidesCardView`, the row component (sentence + strength mark), `SideGroupDetailSheet`, exercise drill-down |
| Body paths | new generated Swift file plus a script in `scripts/` | Convert the MIT path data to SwiftUI `Path` builders at build time, not runtime |
| Findings rule | `InsightRules*.swift` | `LateralAsymmetryInsightRule` — only if D7 keeps it |
| Analytics | [AnalyticsServiceProtocol.swift](Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift) | Events in §10 |

**Body artwork notes for estimating**

- The app has no SVG dependency (SPM: `posthog-ios`, `purchases-ios-spm` only), but already draws custom `Path`s in `InsightChartViews`, `HowItWorksView` and `WorkoutShareCard`. Generated `Path` code fits.
- The path data uses relative cubic, quadratic **and elliptical-arc** commands, with compact arc flags (`a5 5 0 013 4` is flags 0, 1 then x = 3). The converter must turn SVG arcs into cubics; SwiftUI has no direct equivalent.
- A throwaway Python converter and renderer already exists from the mockup work (`body.py`, scratch). It proves the parsing, arc flags and the anatomical side mapping, and could seed the build script.
- Deployment target is iOS 17.

---

## 9. Open questions

**Product**

| # | Question |
|---|---|
| P4 | Is E3 (callouts) used anywhere, or parked? |
| P10 | Discoverability with S3 out: accept that people without flagged exercises never learn the feature exists, or give them *something* (a one-line mention in the coverage note of another card, release notes, …)? |

**Technical**

| # | Question |
|---|---|
| T1 | SVG → SwiftUI conversion: build-time codegen (recommended) or a runtime parser — and how arcs are converted |
| T2 | Compute `sidesStatus` on every Insights load like `trainingStatus`, or cache it? Eight weeks of sets is small, but confirm on a heavy user's data |
| T3 | Engine: feed the weaker side's reps and RIR to capability and fatigue learning only (keeping `max` for PRs and charts), keep today's behaviour, or two capability tracks? Where it sits relative to PR2 / G11 |
| T4 | Seed expansion for new installs, and whether existing users get a migration (and how it avoids overriding their own edits) |
| T5 | Where the MIT notice lives — there is no acknowledgements screen |
| T6 | Reach measurement: set data is on-device only, so add a property to an existing event (for example a count of both-sides sets per finished workout) before building |
| T7 | Only if D7 keeps the findings card: identity for a group-level finding when `subjectId` is an exercise UUID |

---

## 10. Analytics and success

**Events** (named in the style of `insightsViewed`, `musclePanelExpanded`):

| Event | Properties |
|---|---|
| Insights `$screen` → `sides_state` | hidden / building / even / leaning — reach, without a separate event |
| `sidesGroupOpened` | group, status, exerciseCount |
| `sidesExerciseOpened` | status |
| Findings card | Existing `insightExpanded` / `insightRated` / `insightSnoozed` with `ruleId = lateralAsymmetry`, if kept |

**Success signals:** share of Insights viewers who see the card (reach); group-open rate from the card; exercise-open rate from the deep dive; reach growing after any coverage work.

---

## 11. Test plan hooks

- **Capacity:** matched reps with different RIR; different reps; RIR on one side only; RIR 5 ("5+"); half-filled row excluded; drop set, back-off and warm-up excluded; excluded workout and excluded exercise honoured; bodyweight unilateral with nil weight.
- **Acceptance (D23):** matched reps with different RIR shows the weaker side per exercise; different reps reads the same; evening out reaches Even within 4 sessions; a flip passes through Even.
- **Classification:** collecting under 3 sessions and Even (not collecting) at 3; ties don't count against direction; only the last 6 sessions and 12 weeks count; opposite directions in one group are two imbalances, not "mixed".
- **Mirror trap:** a unit test asserting the anatomical mapping for both views. This is the bug that ships silently.
- **States:** SwiftUI previews for S1, S2 and the E1 card, in the pattern `MuscleVolumePanelView` uses.
- **Cohort check:** run §5's gates over several backups before release, not one.

---

## Appendix A — the derivation, in one table

| Derived field | Rule | Line |
|---|---|---|
| `reps` | `max(leftReps, rightReps)` | [WorkoutSet.swift:124](Repster/Data/Models/WorkoutSet.swift#L124) |
| `rir` | RIR of the side that did more reps; ties take the lower RIR | [WorkoutSet.swift:143](Repster/Data/Models/WorkoutSet.swift#L143) |
| `side` | forced to `.both` | [WorkoutSet.swift:177](Repster/Data/Models/WorkoutSet.swift#L177) |
| `e1RM` | from the derived reps | [SetService.swift:158](Repster/Core/Services/SetService.swift#L158) |

## Appendix B — catalog IDs

| ID | Name | Status |
|---|---|---|
| E1 | Lead & trail | **Chosen** — list rows redesigned (D13, D14) |
| E2 | Gap heat | Rejected |
| E3 | Callouts | Runner-up (P4) |
| E4 | No body | Rejected |
| S1 | Building | **In** |
| S2 | Even | **In** |
| S3 | Nothing tracked | Out — the card is hidden instead |
| S4 | Closing gap | Out |
| U1 | In-workout recall | Out |
| U1b | Match sides | Later |
| U2 | Workout summary | Out |
| U3 | Exercise detail Sides tab | Out in that location; its content moved into the deep dive |
| U4 | Findings card | Optional |
| U5 | Exercise editor prompt | Out |
