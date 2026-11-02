# Left vs Right Rethink — Scoping

**Date:** 2026-11-02
**Status:** Built 2026-11-02. 1,040 tests, 0 failures, 14 existing skips. Device pass outstanding
(section 9)
**Target release:** 1.6
**Feature area:** Insights → Sides (unilateral imbalance)
**Design:** "Left vs Right Rethink" canvas — https://claude.ai/artifact/AuJkXNR1V6Naq7A8Qbf75s
**Amends:** `UNILATERAL_IMBALANCE_EXPLORATION.md` (adds D25–D32) and replaces the screens scoped in
`SIDES_DETAIL_REDESIGN_SCOPING.md`. The analysis rules (D21–D24) and D13 (plain words, reps only on
the exercise screen) do not change.

## 1. Summary

Today Left vs Right is a card of about 350pt, second on Insights, that opens a sheet per muscle
group, which opens a long exercise screen with three charts. Nobody outside TestFlight has seen any
of it yet (no `sides_state` events from production in the 90 days to 2026-11-02), so changing it
costs no habits and loses no analytics.

After this change it is one small tile, one list and one simpler exercise page:

| Level | Today | After | Board on the canvas |
|---|---|---|---|
| Insights | `SidesCardView`: group rows and a coverage note, above the muscle panel | One tile, below the muscle panel, above Findings | **1 · Insights with the tile**, **The tile in each state** |
| List | `SideGroupDetailSheet`: one group at a time, in a sheet | One pushed page: every exercise as a tile under its muscle group | **List A · Stacked tiles** |
| Exercise | `SideExerciseDetailView`: beam, session ladder, best-set table | Pushed page: verdict tile, one line chart, and the best set from the last 3 sessions | **Exercise D · Line chart**, **Exercise D · Other states** |

Every other board on the canvas is a rejected option or an earlier draft. They are not the design.

## 2. Decisions

| # | Decision | Date |
|---|---|---|
| D25 | Left vs Right is a tile, not a card, placed below the muscle panel. Status and the panel both cover the last 7 days and the card split them. Above Findings, not below, because that list has no fixed length and the tile is the only way in. | 2026-11-02 |
| D26 | Pushed pages on the dark background replace the sheet. The group screen goes: muscle groups become section headings on one list. An exercise is still two taps from Insights. | 2026-11-02 |
| D27 | The exercise screen is a verdict tile, one chart of left and right over the sessions, and the best set from the last 3 sessions. The balance beam, session ladder and mini beam are removed. | 2026-11-02 |
| D28 | The by-weight best-set table is removed from the screen for now. Its code stays, with no call site. | 2026-11-02 |
| D29 | Under 3 sessions there is no chart, only the sets so far. No progress bar, matching how the status card treats early days. | 2026-11-02 |
| D30 | Every number printed on the exercise page is a real logged set. The chart plots session medians but prints none of them, and it isn't tappable. | 2026-11-02 |
| D31 | The page says plainly whether RIR counts, using the app's own word: a marker on the chart, and RIR beside the reps on each row. | 2026-11-02 |
| D32 | The body artwork stops compiling into the app. The code stays in the repo, and the app carries no notice. | 2026-11-02 |

Unchanged: no group-level direction (D21), never red, no cause or advice in copy, the sentence and
`SideStrengthMark` stay together on list rows, unconfirmed leans get no solid mark (D24).

## 3. Three catches

### 3.1 A pushed page re-runs Insights' `.task`

`InsightsView.swift:84` loads in `.task` and sends `insightsViewed` straight after. Under a sheet the
view never disappears, so this runs once. With a push, Insights disappears when the list opens and
reappears on the way back, so `.task` runs again: a second full `load()` and a second `$screen`
event for one visit. The code comment there says "One event per open", and `load()` re-derives from
the whole set history.

Fix: return early from `.task` when `viewModel.hasLoaded` is true. Marking an exercise Unilateral
still refreshes, because that path calls `load()` directly. Side effect: switching tabs and coming
back no longer reloads an open Insights screen or sends a second `$screen`, which it used to.

Related and harmless: `HomeView.swift:151` runs `refreshInsightBadge()` in `.onDisappear`, which now
also fires when the list opens. It repeats when the user really leaves.

### 3.2 The "not tracked" line needs exercises the model throws away

List A has one line at the bottom, "14 other exercises aren't tracked by side", across all groups.
`SidesAnalysis.status(from:)` cannot produce that today: a group with nothing tracked records only
its name and then `continue`s (`SidesAnalysis.swift:573`), dropping its exercises. Those names only
ever fed the coverage note on the card.

Fix: add `SidesStatus.untrackedExercises`, filled from every group, sorted by name, and passed to
`SideUntrackedListView`. `untrackedGroupNames` has no reader once the card is gone, so it is removed.

### 3.3 The chart's values are not real sets

`SideSession.left` and `.right` are medians of reps + RIR across a workout's sets, and `SideSession`
holds nothing else. So a value like 8.5 or 10.5 is not something anyone lifted. Printing those beside
real sets would give two sets of numbers that disagree on one screen (Left 8.5 in a readout, 9 in the
row under it), which is the same kind of contradiction that made `bestTable` lose trust.

Fix: D30. The chart keeps plotting medians, because that is what the verdict runs on, but prints no
session values. The tap readout goes with them, which also removes the risk of a chart gesture
fighting the page's scroll. Rows need new data: see step 2.

## 4. Build order

Three steps. Each works without the next, so each is a safe checkpoint. Steps 1 and 2 ship together.
Step 3 is independent and must land before 1.6 ships.

### Step 1 — Tile and list

- **New shared view:** one tile component (icon box, title, subtitle, optional trailing mark or
  chevron) with the Insights status card's header measurements. The tile, list rows and the verdict
  in step 2 all use it, so they cannot drift.
- **`InsightsView.swift`:** tile replaces the card and moves below `MuscleVolumePanelView`. Remove
  `.sheet(item:)`. Apply 3.1. Update the "weakest claim to strongest" comment.
- **Routes:** `enum SidesRoute: Hashable { case list, exercise(UUID), untracked }`, registered once
  with `navigationDestination` on the `InsightsView` scroll view. Home's stack already uses
  `NavigationPath`. Destinations read `viewModel.sides` live, so the list updates after an edit
  rather than holding a copy, as the sheet did. Routes stay id-based because
  `SideExerciseSummary` isn't `Hashable`.
- **`InsightsViewModel.swift`:** remove `selectedSideGroup`.
- **List page:** large title "Left vs right", a section per group in `groupOrder`, tracked exercises
  only, then the "not tracked" row and the 6-session footnote. Keep the 100pt bottom padding for the
  floating button. If reloading leaves `.hidden` while the page is open, show one plain line.
- **`SideUntrackedListView`:** keep it, change the background to `.bg`.
- **`SidesAnalysis.swift`:** apply 3.2, shorten the possible sentence, remove `SideGroupStatus.sentence`
  (its only readers were the card row and its accessibility label).
- **Copy:** new functions in `SidesCopy` for the tile (section 5). Remove `statusLine(for: group)`.
- **Files:** rename `SidesCardView.swift` → `SidesTileView.swift` and `SideGroupDetailView.swift` →
  `SidesListView.swift`. Four `project.pbxproj` lines each (`SD0004`/`SD1004`, `SD0005`/`SD1005`).
- **Body map comment:** the header in `SidesCardView.swift` says restoring the map means putting
  `figures` back on the card. The card is gone, so rewrite it. The archive itself is untouched.

### Step 2 — Exercise page

- **`SidesAnalysis.swift`:** `Sample` gains weight, reps and RIR per side. `sessions(from:)` picks
  each workout's best set and stores it as `SideSession.bestSet: SideBestRow?`, reusing the row type
  D28 keeps. Heaviest set first, then the existing `BestAccumulator` order (capacity, then reps,
  then recency). A session can mix weights, and on capacity alone the lightest set would usually
  win, which isn't the set a lifter calls their best.
  `SideSession` also counts its sets and how many counted RIR, following `comparableRIR` exactly.
  `SideExerciseSummary` exposes that as all, some or none across its sessions.
- **`SideExerciseDetailView`:** rebuild as title, verdict tile, section label row, chart card,
  best-set rows, and the incomplete-sets note at the bottom only when it applies. The title is a
  28pt `Text` that can wrap, not a large nav title, because `Bulgarian Split Squat` does not fit
  at 34pt.
- **Chart:** new `SideLinesChart` in `SideExerciseCharts.swift` (section 6).
- **`SideExerciseCharts.swift`:** delete `SideBalanceBeam`, `SideSessionLadder` and `SideMiniBeam`.
  `SideEffortTable` stays, with no call site.
- **Tokens:** add one for the even line, `#6F93DD`, because `sidesEven` `#456AB5` is too dim for a
  2pt line. Nothing is removed: `sidesEven` and `sidesCollecting` stay for `BodyMapView`, and
  `sidesTrail` and `sidesReserve` stay with `SideEffortTable`.
- **Copy:** `gapLine` loses "on your right" because the title now says it. `statusLine(for: exercise)`
  goes; the consistency count moves to the section label.

### Step 3 — Take the artwork out of the app

`BodyMapPaths.swift` is the MIT-derived data. It compiles into the app today (`SD0002`), though
nothing draws it, so the notice would be owed in 1.6. It has not shipped: it arrived after 1.5.

- **Flag:** wrap the artwork in `#if REPSTER_BODY_MAP`, a flag no build configuration defines. Files
  stay in the repo and the target, so no `project.pbxproj` change. Restoring it means defining the flag.
- **`scripts/generate_body_paths.py`:** emit the `#if` around the data, or regenerating undoes this.
- **`BodyMapView.swift`:** wrap `front`, `back`, `geometry(for:)`, the stored properties and `init`,
  and `BodyFigure`. `librarySide`, `anatomicalSide`, `regionGroups`, `nonMuscleRegions`, `path(from:)`
  and `SidesBodyFill` stay compiled, because they hold none of the artwork.
- **`SidesAnalysisTests.swift`:** wrap the three tests that parse real geometry. The mirror trap and
  fill tests keep running, because they use the pure functions.
- **Notice:** keep the header in `BodyMapPaths.swift` and `scripts/body-map/LICENSE`. The repo is
  public, so it is still distributing that data, and the licence goes with the copy.
- **Check:** build Release and confirm a distinctive path string from `BodyMapPaths.swift` is no
  longer in the binary with `strings`. Done 2026-11-02.

## 5. Copy

**Tile.** Counts come from `SidesAnalysis.sessionsConsidered` and `minSessions`, not literals. Long
group names wrap to two lines, as on the status card.

| State | Headline | Subtitle | Icon box |
|---|---|---|---|
| Imbalanced, 1 group | Imbalance in Legs | Last 6 sessions of each exercise | Arrows, accent |
| Imbalanced, 2 groups | Imbalances in Legs and Shoulders | Last 6 sessions of each exercise | Arrows, accent |
| Imbalanced, 3+ | Imbalances in 3 muscle groups | Last 6 sessions of each exercise | Arrows, accent |
| Possible, 1 group | Possible imbalance in Legs | It needs a few more sessions to confirm | Arrows, dashed |
| Possible, 2+ (not drawn) | Possible imbalances in 2 muscle groups | It needs a few more sessions to confirm | Arrows, dashed |
| Even | Both sides are even | Last 6 sessions of each exercise | Arrows, even blue |
| Building | Building your baseline | Each exercise needs 3 sessions | Dashed circle, `.stale` |
| Hidden | No tile, as today (D10) | | |

**List rows.** `status.sentence`, except possible, which shortens to "Left seems stronger — needs
more sessions" so it fits a tile on one line.

**Exercise verdict.**

| Status | Box | Title | Subtitle | Right of section label |
|---|---|---|---|---|
| Stronger | R or L | Right is clearly stronger | About 1 more rep at the same weight | RIGHT AHEAD IN 5 |
| Possible | R or L, dashed | Left seems stronger | About 1 more rep so far, needs more sessions | LEFT AHEAD IN 2 |
| Even | = | Both sides are even | Within a rep of each other, at the same weight | NO CONSISTENT GAP, or SIDES MATCHED if `differingCount == 0` |
| Collecting | Dashed circle | Needs 2 more sessions | With both sides logged | None; the section is labelled SO FAR |

**RIR marker,** on the chart's legend row. "Counted" follows `comparableRIR`: both sides have it, and
not both "5+".

| Sets where RIR counted | Marker | Style |
|---|---|---|
| All | Reps + RIR | Blue |
| Some | Reps + RIR where logged | Blue |
| None | Reps only | Grey |

**Best-set rows.** Newest first, up to 3, under BEST SET EACH SESSION (SO FAR when collecting):

- Date, with the weight beneath it (`Bodyweight` when there is none)
- Reps per side, with a pale blue `1 RIR` pill beside them when RIR counted. `5+ RIR` for the "5+" chip
- The side with more reps + RIR is bright, the other dim. A tie leaves both dim
- A row with no pill means that set was compared on reps alone

The mock brightens every grey label for contrast. In the build, Insights labels keep `textTertiary`
like their neighbours, and the Sides pages keep `sidesCaption` as they do today.

## 6. Chart

A `Canvas`, like the other Sides charts, not Swift Charts as first scoped. With no selection left
(D30) Swift Charts offered little, and a Canvas draws the board exactly: every position is ours,
with no axis layout to fight. VoiceOver gets its per-session labels through `accessibilityChildren`.

- **X:** session index, evenly spaced, labelled with dates. Not real time: an irregular week would
  bunch the points, and two workouts on one day would collapse.
- **Y:** `SideSession.left` and `.right`, which are reps plus reserve. Minimum span 3.5 reps, so a
  half-rep gap doesn't fill the chart. Two quiet gridlines with labels. No session values are
  printed (D30).
- **Band:** a filled shape between the two lines, accent at 14%, 8% when possible, none when even.
- **Lines:** 2pt. Leading side `sidesStronger`, other side `sidesNeutralMark`. Possible: leading
  line dashed. Even: both the new even token.
- **Points:** Right always filled, Left always hollow, so the sides differ by more than colour.
- **Legend row:** Left and Right with their point styles, and the RIR marker on the right.
- **End labels:** R and L beside the last points, pushed apart when those points nearly touch.
- **Accessibility:** one spoken label per session saying who led, without figures. The rows below
  carry the numbers.
- **Testable part:** Y domain and label separation go in a small pure struct, so they can be pinned
  without rendering.

## 7. Analytics

No production data exists on these events, so there is nothing to keep continuous.

| Event | Change |
|---|---|
| `$screen` → `sides_state` | Unchanged |
| `sides group opened` | Removed. Remove `.muscleGroup` too, nothing else uses it. |
| `sides opened` | New. Tile tapped, with `sides_state`. |
| `sides exercise opened` | Unchanged |

Update `POSTHOG_ANALYTICS_GUIDE.md:243-245`.

## 8. Tests

**Re-pin in `SidesAnalysisTests.swift`:**

- `:136`, `:278`, `:282-283` — group `sentence`, removed
- `:218` — `gapLine` wording
- `:276` — shortened possible sentence
- `:552` — `untrackedGroupNames` becomes `untrackedExercises`
- `:639` — event names

**Add:** every row of the tile table; `untrackedExercises` includes groups with nothing tracked;
verdict copy for all four statuses; a session's best set is the heaviest, then follows capacity; the
RIR marker is all, some or none, and two "5+" sides count as none; Y-domain floor and end-label
separation.

**Change:** the three geometry tests compile only with `REPSTER_BODY_MAP` (step 3).

**Unaffected:** the `bestReps` tests (`:378-488`), and `ReplayMaskCoverageTests`, because no text
fields are added.

Run the full suite once, into a log, after each step.

## 9. Device pass

1. Insights: the tile sits under the muscle panel. Open it, go back: no reload flicker, scroll
   position kept, and only one `$screen` event in the debug log.
2. Tap "Mark one", mark an exercise Unilateral, save: the list updates while still open.
3. An exercise with RIR logged on both sides: the marker says Reps + RIR, and the rows match the
   sets in your history.
4. An exercise with no RIR logged: the marker says Reps only, with no pills on the rows.
5. An exercise with 1–2 sessions: rows, no chart.
6. A long exercise name and a long group name: both wrap cleanly.
7. Tap the Home tab from the exercise page: returns to Home.
8. VoiceOver through the tile, one list row, the chart and a best-set row.

## 10. Not in this change

- The by-weight best-set table, and any change to the analysis rules
- The body map, which stays archived
- Reach: only 6 of 69 seeded exercises are unilateral, so most people never see the tile
- Discoverability when `.hidden`: no tile means no route to "Mark one", as today
- `SideUntrackedListView` calling already-unilateral exercises "not tracked" when they have no
  both-sides sets. It does that today, and the header copy is slightly wrong for them

## 11. Questions answered 2026-11-02

| # | Question | Answer |
|---|---|---|
| 1 | With best sets gone, is a caption enough to explain that the chart counts RIR? | No. Show the best set from the last 3 sessions under the chart, and make it obvious whether RIR is included (D30, D31). |
| 2 | Keep the best-sets code or delete it? | Keep it (D28). `SideSession.bestSet` now reuses `SideBestRow`. |
| 3 | The MIT notice for the body artwork? | Keep the code, no reference in the app (D32). This only works if the artwork leaves the binary: shipping it compiled in with no notice would break the licence. |

Spec question T5 (where the MIT notice lives) is closed by D32. A Release build confirms it: neither
the path data nor `BodyMapPaths` appears in the binary.
