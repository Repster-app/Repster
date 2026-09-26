# Sides Exercise Detail — Redesign Scoping

**Date:** 2026-09-19
**Status:** Scoped, not built
**Target release:** 1.6
**Feature area:** Insights → Sides (unilateral imbalance)
**Design:** "Side Imbalance Visuals" canvas, board **Redesigned** — https://claude.ai/artifact/W3eqgXm6XoEVFjZ8D3tT47
**Amends:** `UNILATERAL_IMBALANCE_EXPLORATION.md` — replaces D18 (the C2 difference-columns chart).
D13 (plain words, reps only in the drill-down), D21–D23 (the rules) and D24 (unconfirmed leans) are
unchanged and this design honours all of them.

## 1. Summary

`SideExerciseDetailView` — the screen you reach by tapping an exercise in a muscle group's deep dive
— keeps the data it has but draws almost none of it. Its chart quantises the gap away, reserves half
its height for a side that never leads, and its table prints numbers that appear to contradict the
verdict directly above them.

This change replaces the two visual blocks on that screen:

| Block | Today | After |
|---|---|---|
| Chart | `SideDifferenceChart` — one column per session, 1–3 quantised steps up or down | `SideBalanceBeam` — average gap and each session on one shared reps scale, with the tie threshold drawn |
| Sessions | (none, beyond the chart) | `SideSessionLadder` — per session, how far each side got, with the leader's excess picked out |
| Table | `bestTable` — "BEST REPS PER SIDE", raw reps | `SideEffortTable` — "BEST SET AT EACH WEIGHT", reps **plus what was left in reserve** |

The first two are view-only and need no model change. The third needs one contained change in
`SidesAnalysis` and is the reason this is a scoping doc rather than a patch.

## 2. What is wrong today

### 2.1 The chart cannot show the number the headline promises

Bar height is `session.degree` — a 1–3 step enum — not the gap:

```swift
let height = CGFloat(session.degree?.rawValue ?? 0) * step - 1   // SideGroupDetailView.swift:350
```

`SideDegree` is a *relative* band (<12% / 12–25% / ≥25% of mean capacity, `SidesAnalysis.degree`).
So the headline says "About 1 more rep on your right" and the chart beside it cannot express one rep,
or distinguish a 0.5-rep gap from a 1.4-rep gap. Two sessions half a rep apart and two sessions a rep
and a half apart draw the same 10pt nub.

### 2.2 Half the plot is empty by construction

The chart always draws both halves — right-stronger above the baseline, left-stronger below. An
exercise only earns a verdict when the same side leads ≥75% of differing sessions (`minConsistency`),
so for every exercise that has something to say, roughly half the plot is guaranteed blank. At the
common case of three sessions that is three specks of ink in a 68pt-tall field, and the columns are
evenly spaced by `maxWidth: .infinity` while the axis labels underneath are real dates — so the bars
do not sit where their dates say.

### 2.3 The table contradicts the verdict — this is the one that costs trust

`bestTable` (`SideGroupDetailView.swift:204`) prints `SideBestRow.left` / `.right`, which are raw
rep counts. The verdict runs on **capacity = reps + RIR** (`SidesAnalysis.capacity`,
`SidesAnalysis.swift:323`). A lifter whose imbalance shows up as effort rather than reps — which the
spec explicitly commits to supporting — therefore reads:

> Your right side has been stronger in all of your last 3 sessions
> **30 kg — LEFT 6 · RIGHT 6**
> **25 kg — LEFT 10 · RIGHT 10**

Identical numbers, presented as the evidence, under a claim of difference. Nothing on the screen
explains that the right side had two reps in reserve where the left had one. This is not a styling
problem and no chart change fixes it.

### 2.4 Minor: the captions fail contrast

`Color.textTertiary` (#5C5C6E) on `Color.bgCard` (#1B1B1F) is about **2.6:1** — under AA for body
text. It is used for the chart caption, the axis dates, the section labels and the table header. The
redesign moves those to #8A8A9C (**5.1:1**). This is a token-level choice worth deciding once for the
Sides feature rather than per view.

## 3. The screen after the change

### 3.1 Blocks, in order

1. **Verdict** — `SidesCopy.statusLine` and `SidesCopy.gapLine`, unchanged text, promoted to 19pt bold
   over 13pt secondary. The gap sentence leads; the consistency sentence supports it.
2. **Balance beam** — one horizontal track, centre = even.
   - Shaded centre band = `SidesAnalysis.tieBelow` (±0.5 rep). **The band is the rule, drawn.** A
     session inside it is a tie by definition, so "why doesn't this count?" answers itself.
   - Filled segment from centre = `summary.averageGap`, labelled.
   - One row per session below it, same scale, a dot at `session.gap`.
   - `Left` / `Even` / `Right` under the track.
3. **Session ladder** — one row per session: date, both sides as bars on a shared capacity scale, the
   leading side's length *beyond* the trailing side picked out in accent, and the gap as a number. A
   dotted rule at the trailing length makes "same up to here, then extra" literal.
4. **Best set at each weight** — per weight, per side: a solid segment for reps done and a pale
   segment for reps left in reserve, plus `6 reps · 2 left` in text.
5. **Note** — the existing `incompleteNote` (one-sided sets, one-sided RIR), unchanged.

### 3.2 State variants

All four states are drawn on the canvas board "The same block in every state". Behaviour:

| `SideStatus` | Beam | Ladder / dots |
|---|---|---|
| `.stronger` | Solid fill to `averageGap`, number chip | Full ladder |
| `.possible` (D24) | **Dashed outline, no solid fill, no number chip** — keeps D24's "no strength mark" | Dots only, muted |
| `.even` | Marker dot at centre, "Even" in place of a number | Dots only |
| `.collecting` | Empty track, centre line only, plus a dimmed "next" row | Dots for the sessions logged so far |
| `.notTracked` | Block is not drawn (as today) | — |

### 3.3 Not changed

Copy rules (D13), the classification rules (D21–D24), the Sides card, the body map, the group deep
dive rows, `SideStrengthMark`, and every threshold in `SidesAnalysis`. This is a presentation change
plus one accumulator fix.

## 4. Data model

### 4.1 `SideBestRow` has no effort, and its two halves can come from different sets

```swift
struct SideBestRow {                 // SidesAnalysis.swift:212
    let weight: Double?
    let left: Int
    let right: Int
}

private struct BestAccumulator {     // SidesAnalysis.swift:421
    let weight: Double?
    var left: Int
    var right: Int
}

best.left  = max(best.left,  left)   // SidesAnalysis.swift:480
best.right = max(best.right, right)  // :481
```

Two problems, and the second is the one that bites:

- **No RIR.** The reserve the whole verdict turns on is never carried to the row.
- **The two sides are maxed independently.** `best.left` may come from one set and `best.right` from
  another. Today that is invisible — both are honestly "the most reps at this weight". The moment a
  reserve figure appears beside each number, the row would be printing the RIR of two different sets
  side by side and inviting the reader to compare them. That is exactly the load-controlled,
  same-set comparison the feature is built on, broken in the one place it is shown.

### 4.2 Proposed: accumulate the best **set**, not the best per-side reps

```swift
struct SideBestRow {
    let weight: Double?
    let left: Int
    let right: Int
    let leftRIR: Double?      // new — nil when the set had no RIR, or only one side did
    let rightRIR: Double?     // new
}
```

`BestAccumulator` keeps the winning set rather than two maxima. Ranking, in order:

1. Highest total capacity (`cap.left + cap.right`) — the same ordering the verdict uses.
2. Then highest total reps.
3. Then most recent `set.date`.

`cap` is already computed in the loop (`SidesAnalysis.swift:472`) for the session samples, so this
costs nothing extra. RIR is stored only when `capacity()` would have used it — both sides usable, or
the censored "5+" case. When one side has RIR and the other does not, the row stores `nil` for both
and renders reps only; the existing `rirOnOneSideSets` note already explains why.

**This changes the numbers some rows show.** If your best left at 30 kg was 7 reps in one set and
your best right was 6 in another, today's row reads 7 / 6; after this it reads whatever the single
best set did, e.g. 6 / 6. The section is renamed from "BEST REPS PER SIDE" to "BEST SET AT EACH
WEIGHT" so the label matches the new meaning. See decision D1 if you would rather keep per-side
maxima.

### 4.3 Nothing else moves

`SideSession`, `SideExerciseSummary`, `SideStatus`, `SideGroupSummary`, every threshold and every
classification path are untouched. `SideBestRow` is referenced in exactly two places outside its own
declaration: the accumulator's `.map` (`SidesAnalysis.swift:503`) and `bestTable`. No persistence, no
migration — this is all computed from `eligibleWorkingSets` at read time.

## 5. Views

### 5.1 `SideDifferenceChart` → `SideBalanceBeam`

Delete `SideDifferenceChart` (`SideGroupDetailView.swift:290`–end of that struct), including its
`Canvas` guide lines. The new view takes `sessions: [SideSession]`, `averageGap: Double` and
`status: SideStatus`.

Scale: `max(3, ceil(largest absolute gap among sessions and the average))` reps either side of centre,
so nothing ever clips and the common case still reads on a familiar ±3. See D2.

### 5.2 New: `SideSessionLadder`

Takes `sessions: [SideSession]`. Bars share one maximum — the largest `max(left, right)` across the
shown sessions, rounded up. Reads only fields that already exist.

### 5.3 `bestTable` → `SideEffortTable`

Same rows, same order (heaviest first, bodyweight last), same `weightLabel` / `UnitConversion` call.
Adds the reserve segment and the `· n left` suffix. Renders reps only when RIR is nil.

### 5.4 Tokens

Two additions to `DesignTokens.swift`, in the existing Sides block:

- `sidesTrail` — the trailing side's bar, a slate around #3A4257.
- `sidesReserve` — `accent.opacity(0.30)`, the "left in the tank" segment.

Plus the caption contrast decision in §2.4. `sidesStronger`, `sidesEven`, `sidesCollecting` are
reused as they are.

### 5.5 File placement

`SideGroupDetailView.swift` is 508 lines and would reach roughly 750. Recommend moving the three new
views plus `SidesSectionLabel` / `SidesDivider` into `Repster/Features/Insights/Views/SideExerciseCharts.swift`,
registered in `project.pbxproj` with the SD00xx/SD10xx pattern the app target uses (explicit file
refs, not synchronized groups). See D5.

## 6. Accessibility

Today the whole chart is one element with a counts summary. Replacement labels:

- **Beam:** "Right side ahead by 1 rep on average, across 3 sessions. Differences under half a rep
  count as even."
- **Ladder:** one element per row — "29 August: right ahead by half a rep."
- **Effort table:** extend the existing per-row label (`:230`) with reserve — "30 kg: left 6 reps, 1
  in reserve; right 6 reps, 2 in reserve."

The excess segment is never the only carrier of meaning: every row prints its gap as a number.

**Known limitation, not fixed here:** the screen uses fixed `.system(size:)` type throughout, as the
rest of the Sides feature does, so it does not respond to Dynamic Type. Out of scope; worth its own
pass across Insights.

## 7. Analytics

No new events. `sidesExerciseOpened` (`AnalyticsServiceProtocol.swift:745`, fired from
`InsightsView.swift:74`) already records the status when the screen opens, and carries no names or
numbers. Nothing in the new blocks should be instrumented — per-block interaction on a read-only
screen is not worth the event volume.

## 8. Files

| File | Change |
|---|---|
| `Repster/Core/Services/SidesAnalysis.swift` | `SideBestRow` + 2 fields; `BestAccumulator` keeps the winning set; the accumulation at `:479`–`:482`; the `.map` at `:503` |
| `Repster/Features/Insights/Views/SideGroupDetailView.swift` | Delete `SideDifferenceChart`; replace `bestTable`; recompose `SideExerciseDetailView`'s body |
| `Repster/Features/Insights/Views/SideExerciseCharts.swift` | **New** — beam, ladder, effort table (D5) |
| `Repster/Core/Extensions/DesignTokens.swift` | `sidesTrail`, `sidesReserve`; caption contrast (§2.4) |
| `Repster.xcodeproj/project.pbxproj` | New file refs, if D5 |
| `RepsterTests/SidesAnalysisTests.swift` | Best-set tests (§9) |

## 9. Tests

`SidesAnalysisTests` is XCTest, 29 tests, in-memory `ModelContainer`. New cases:

1. Best set comes from **one** set — left 7 in set A, right 8 in set B at the same weight returns the
   single highest-capacity set, not 7/8.
2. Tie-break order — equal capacity resolves by total reps, then by most recent date.
3. RIR carried — both sides usable RIR stores both.
4. RIR on one side only — row stores `nil` / `nil`, and `rirOnOneSideSets` still counts it.
5. Censored "5+" — a 5+ side against a 0–4 side stores the floor, matching `capacity()`.
6. Bodyweight row — `weight == nil`, still sorted last.
7. Regression: the two existing `bestReps` asserts (`:378`–`:379`) still hold.

Run the suite **once** into a log — concurrent `xcodebuild test` runs invent failures and truncate
the count.

View side: extend the `#Preview` block with one preview per state in §3.2 (stronger, possible, even,
collecting) so the variants are inspectable without a device. A device pass is still outstanding for
the Sides feature generally.

## 10. Build order

1. **Beam + ladder.** View-only, no model change, no test churn. This alone fixes §2.1, §2.2 and
   §2.4, and is independently shippable.
2. **Effort table.** `SideBestRow`, `BestAccumulator`, the new view, the tests in §9. Fixes §2.3.
3. Previews, accessibility labels, device pass.

Step 1 is the smallest reversible version and can go in on its own if step 2 stalls on D1.

## 11. Decisions

| # | Question | Recommendation |
|---|---|---|
| D1 | Best **set** (one set, both sides) or best **reps per side** (today's independent maxima, each carrying its own set's RIR)? | Best set. The row is a side-by-side comparison; two sets in one row is the thing the feature exists to avoid. It does change some displayed reps (§4.2). |
| D2 | Beam scale: adaptive with a floor of ±3 reps, or fixed ±3 with clamping at the ends? | Adaptive. A 5-rep gap pinned at the end reads as "as bad as it gets" for every exercise above 3. |
| D3 | Effort table when the best set has no usable RIR? | Show reps only, no reserve segment. The existing note already explains one-sided RIR. |
| D4 | The beam's number chip: 1 decimal ("+1.4 rep") or whole reps to match `gapLine`'s "About 1 more rep"? | 1 decimal. The chip is the precise readout, the sentence is the plain-words one. If two numbers for one quantity reads badly on device, round the chip instead of changing D13 copy. |
| D5 | New `SideExerciseCharts.swift`, or grow `SideGroupDetailView.swift` to ~750 lines? | New file. |
| D6 | Ship step 1 alone, or hold both for one release? | Ship step 1 when it is ready; it is reversible and fixes three of the four problems. |

## 12. Out of scope

- The Sides card, the body map, and the group deep dive rows — all unchanged.
- Any change to thresholds or classification (D21–D24 stand).
- Dynamic Type across Insights (§6).
- The MIT body-artwork notice, which still needs a home in the app.
- Trend copy such as "the gap is smaller than it was". The canvas shows that line in the six-session
  state, but it needs a rule for what counts as closing, which is trend maths the feature deliberately
  does not have. Not in this change.

## 13. Size

Step 1 is roughly 250 lines of SwiftUI replacing 110, no model change, no migration, no new tests
required. Step 2 is about 60 lines of view, a 20-line accumulator change, and 6 new tests. Neither
touches persistence, and the whole screen is computed at read time, so there is nothing to back out
beyond the code itself.
