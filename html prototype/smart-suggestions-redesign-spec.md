# Smart Suggestions — Redesign Implementation Spec

*Companion to the prototypes in this folder, most importantly
[`prototype-smart-suggestions-takeb-with-history.html`](./prototype-smart-suggestions-takeb-with-history.html)
(the "Putting it together" section is canonical).*

---

## 1 · What we're building

A reshape of the in-workout Smart Suggestions card so it's denser, more
honest about its inputs, and prioritises "what to lift now" above everything
else.

The card sits inside `WeightSuggestionModuleView` (Sets sub-tab), between
`SetTableView` and `ExerciseInfoSectionView`. The section is rendered only
when there's at least one pending suggestion — same trigger as today.

### Visual structure (top to bottom inside the section)

| Region | When shown | Contents |
| --- | --- | --- |
| **Section header** | always | `SMART SUGGESTIONS` (kerned tiny caps, existing) · count chip (`· 2 ready · 2 logged`) · refresh button. Admin mode adds an `Admin` pill + monospace `e1RM 64.2 · epley` meta. |
| **Stale banner** | when `e1RMSource.isOutsideRecencyWindow` | Single line: "Based on a workout from **Mar 1** — outside your recency window. Estimate may be optimistic." Slate tone (calm/archival, **not** warning-amber). |
| **Pending strips** | one per pending suggestion | Take B style: 3px indigo rail, 36×36 wand tile, line 1 `Set 3 · 54 kg for 6–8 reps` (weight in accent), line 2 short contextual copy or delta. `Use` button on the right. |
| **"Logged this session" divider** | template flow only, when there's ≥ 1 completed set in-session | Small kerned label between two thin rules. |
| **Done strips** | template flow only | Take 1: green rail, 22px check tile, single line `Set 1 · 52 kg × 8` with inline comparison on the right (`= suggested`, `+1 kg vs sug`, `−1 kg vs sug`). |
| **Last-top chip** | when `baselineTopSet` is populated | Quiet single-line footer (~28pt): history icon · `LAST TOP` label · `52 kg × 8 · RIR 1` (mono) · `8d ago`. Subtle bg, doesn't compete with strips. |

### State treatments

| State | Trigger | Treatment |
| --- | --- | --- |
| **Default** | `e1RMSource == .recentPerformance` | Indigo accent rail/icon, normal weight in accent. |
| **Stale** | `e1RMSource.isOutsideRecencyWindow == true` | Slate rail/icon/weight + slate banner above strips. Foot description suppressed. |
| **Admin** | `isAdminModeEnabled` | Blue rail/icon, monospace strip body, admin sub-line per strip, per-strip ▾ Details toggle expanding a structured drawer (4 groups: e1RM & readiness · Fatigue & calibration · Target & rounding · Alternatives). |
| **Unavailable** (per row) | `availability == .unavailable(reason)` | Muted rail, `reason.title` as line 1, `reason.message` as line 2, action label varies (`Set targets` for `.missingTarget`, etc.). |

### Flow assumptions

* **Default workout (no template) is the hero case.** Sets are added one at a
  time via `addSet()`, so the typical state is **1 pending strip + chip footer**.
* **Template workout** pre-populates sets, so the card shows N strips. Same
  render path, just iterates over `rowStates`.
* **Done strips** only appear in the template/mid-workout flow when at least
  one in-session set has been completed for the current exercise.

---

## 2 · What's supported in code today

References use file paths relative to `Repster/`.

### Already on `WeightSuggestionData`

```swift
struct WeightSuggestionData: Sendable {
    let rowStates: [SetSuggestionState]   // per-pending-set state
    let baseE1RM: Double?                  // for the admin header
    let e1RMSource: E1RMSource             // .recentPerformance / .staleRecentPerformance / .noData
    let availability: SuggestionAvailability
}

extension E1RMSource {
    var isOutsideRecencyWindow: Bool { /* exists */ }
}
```

`Features/Workout/Models/WeightSuggestionData.swift`

### Already on `SetSuggestion`

```swift
struct SetSuggestion: Identifiable, Sendable {
    let pendingSetId: UUID
    let setNumber: Int
    let suggestedWeight: Double
    let targetReps: Int
    let targetRIR: Double
    let targetRepMin: Int?
    let targetRepMax: Int?
    let targetDisplayLabel: String         // e.g. "6–8 reps"
    let normalizedTargetLabel: String?
    let explanation: SuggestionExplanation // .userSummary + .adminSummary
    let diagnostics: SetSuggestionDiagnostics
}
```

Same file as above. `explanation.adminSummary` already produces the dense
diagnostic text the admin sub-line will reuse verbatim.

### Already on `SetSuggestionDiagnostics`

Every value the admin diagnostics drawer renders is already on this struct:
`historicalBaseE1RM`, `sessionCapabilityE1RM`, `effectiveE1RM`,
`readinessPercent`, `fatigueDiscount`, `projectedSessionFatigue`,
`freshnessApplied`, `setTypeFatigueMultiplier`, `restSecondsUsed`,
`restSource`, `intensityFactor`, `rawWeight`, `roundedWeight`,
`weightIncrement`, `displayTargetReps`, `chosenReps`, `targetDisplayLabel`,
`targetSourceLabel`, `rirSourceLabel`, `calibrationLabel`, `selectionPolicy`,
`selectionReferenceE1RM`, `alternatives`.

`alternatives` already contains the `−1 inc / suggested / +1 inc`
candidates the drawer's alternatives section uses.

### Already on `SuggestionDecision` (engine output, not yet surfaced to view)

```swift
struct SuggestionDecision {
    // ...
    let e1RMSource: E1RMSource
    let e1RMSourceWorkoutDate: Date?       // 👈 anchor date for stale banner copy
    // ...
}
```

`Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift`

### Already in `SuggestionPreparation`

```swift
struct SuggestionPreparation {
    // ...
    let completedSessionSets: [SessionSetContext]   // 👈 in-session completed sets
}
```

So the done-strip data exists in the pipeline; it's just not threaded
through `WeightSuggestionData` yet.

### Already in the engine

`LoadPrescriptionService.peakAcrossRecentWorkouts` already locates the top
set behind the baseline e1RM and returns its workout date. It just discards
the actual `WorkoutSet`.

### Already in `ActiveWorkoutViewModel`

* `addSet(for:)` invalidates and refreshes suggestions (line ~566).
* `suggestedWeight(for: setId)` proxies to `WeightSuggestionData`.
* Cache key in `SuggestionCoordinator.cacheKey` already captures all relevant
  inputs; the refresh path is fine.

### Already in `SetTableView` (the keyboard action rail)

`SetTableView.swift` ~1530: when the weight field is focused, the action
rail shows a wand button labelled with the suggested weight (e.g. "54 kg")
and applies it on tap via `applySuggestedWeight(context)`. **This is the
primary apply path.** The `Use` button inside the suggestion card is a
secondary, visible affordance.

### Already in `WeightSuggestionCardView`

* Per-row rendering (`rowStates.forEach`).
* User vs admin row branching.
* Diagnostics expansion (global toggle today — needs to become per-row).
* Unavailable-row rendering with reason.

---

## 3 · What needs to be built

Grouped by area. Sized roughly: `S = a few lines`, `M = small file`,
`L = small feature with cross-cutting touches`.

### A. Engine — minimal

| # | Change | Size | Notes |
| --- | --- | --- | --- |
| A1 | Extend `peakAcrossRecentWorkouts` to also return the source `WorkoutSet` (or just `weight: Double`, `reps: Int`, `rir: Double?`). | **S** | Pure refactor of an existing internal helper. |
| A2 | Extend `BaseE1RMEstimate` and `SuggestionEngineInput` to carry the new "top set" snapshot through to `SuggestionDecision`. | **S** | Mirror the existing `sourceWorkoutDate` plumbing. |

### B. Data model — three new optional fields

All three are non-breaking optionals on existing structs.

| # | Field | On | Source | Size |
| --- | --- | --- | --- | --- |
| B1 | `e1RMSourceWorkoutDate: Date?` | `WeightSuggestionData` | Mirror from `evaluation.decisions.first?.e1RMSourceWorkoutDate` in `SuggestionExplainer.makeWeightSuggestionData`. | **S** |
| B2 | `baselineTopSet: HistoricalSetSnapshot?` (struct: `weight`, `reps`, `rir`, `date`) | `WeightSuggestionData` | Populated alongside B1 from the new engine output. | **S** |
| B3 | `completedInSessionSets: [CompletedSetSnapshot]` (struct: `setNumber`, `weight`, `reps`, `rir`, `suggestedWeight?`, `suggestedTargetLabel?`) | `WeightSuggestionData` | Built in `SuggestionExplainer.makeWeightSuggestionData` from `preparation.completedSessionSets`. | **M** |

> Decision: include the matching suggestion snapshot in `B3` so the done-row
> "vs suggested" comparison doesn't need a secondary VM cache for the
> common case. If the card is being looked at *after* the workout closes,
> the suggestion snapshot will be `nil` and the done strip drops the
> comparison gracefully — see also D1.

### C. Pure SwiftUI work in `WeightSuggestionCardView` & `WeightSuggestionModuleView`

| # | Change | Size |
| --- | --- | --- |
| C1 | Drop the in-card "Smart Suggestions" header. Section header (in `WeightSuggestionModuleView`) becomes the only title. | **S** |
| C2 | Move the count summary (`"4 ready"`, `"2 ready · 2 logged"`) into the section header as a quiet trailing fragment. | **S** |
| C3 | Replace the current row layout with the Take B 2-line strip (accent rail, 36px wand tile, line 1 weight + target, line 2 contextual / delta, `Use` button). | **M** |
| C4 | Implement the done strip (Take 1 single-line with inline comparison) and the "Logged this session" divider. Only rendered when `completedInSessionSets` is non-empty. | **M** |
| C5 | Implement the slate stale banner. Suppress the foot description while the banner is shown. | **S** |
| C6 | Move admin pill + `e1RM ## · formula` meta into the section header. | **S** |
| C7 | Admin strip styling: blue rail, mono body, admin sub-line consuming `explanation.adminSummary` verbatim. | **S** |
| C8 | **Move `@State showDetails` from card root to row body** so Details is per-strip rather than global. | **S** |
| C9 | Structured diagnostics drawer: 4 labeled groups (`e1RM & readiness`, `Fatigue & calibration`, `Target & rounding`, `Alternatives`) consuming the existing `SetSuggestionDiagnostics` fields. | **M** |
| C10 | Last-top chip footer: single-line, history icon, label, mono value, relative date. | **S** |
| C11 | New colour token: `--stale` slate (`#94a3b8` family) for the stale state. Add to `Color` extensions used by the card. | **S** |
| C12 | `Use` button wiring — calls the same code path as the keyboard rail's `applySuggestedWeight(context)`. | **S** |

### D. ViewModel & wiring

| # | Change | Size |
| --- | --- | --- |
| D1 | Capture the suggestion snapshot at the moment a set is logged so it can be shown in the done strip after completion. Two viable approaches: **(a)** read it from the last-known `WeightSuggestionData` for that set's row state *before* updating local state in the set-complete path, and persist it on `WorkoutSet` (extra column, durable post-reopen); **(b)** keep it in an in-memory `[UUID: SuggestionSnapshot]` on `ActiveWorkoutViewModel`, no persistence — comparison vanishes after the workout closes. **Recommend (b) for v1.** | **M** |
| D2 | Make `B3` (`completedInSessionSets`) include the snapshot from D1 when present. | **S** |
| D3 | Behaviour change: render completed-in-session sets in the suggestion card. Today they're filtered out before rendering. Touch point: `SuggestionExplainer.makeWeightSuggestionData`. | **S** |

### E. Stays as-is

* `LoadPrescriptionService.estimateCapacityBaseE1RM` — only the helper it
  calls (A1) changes.
* The cache-key signature in `SuggestionCoordinator`.
* The unavailable-row rendering path (cosmetic restyling only).
* The keyboard action rail in `SetTableView`. It remains the primary apply
  path; the in-card `Use` button is additive.

---

## 4 · Deferred to v1.1

| # | Item | Notes |
| --- | --- | --- |
| F1 | **Contextual per-row copy** for pending strips line 2 ("Adjusted up after previous set", "Backing off slightly for fatigue", "Slight bump from last workout's peak", "Working up to top", etc.). | Data exists on `SetSuggestionDiagnostics` (`fatigueDiscount`, `projectedSessionFatigue`, comparison to previous in-session set, freshness). Need a new explanation-generation pass with decision rules. For v1, line 2 falls back to either the Variation B delta (`↑ +2 kg vs last top (52 × 8)`) or a generic `Target RIR 1`. |
| F2 | Persist the captured suggestion snapshot onto `WorkoutSet` so done-strip comparison survives reopening a closed workout. | Currently scoped out of v1; D1 option (b) is in-session-only. |
| F3 | Tap-to-expand on a done strip to show a deeper compare with last workout's same-numbered set. | Requires the equivalent-set fetch path; not currently warranted. |

---

## 5 · Open decisions

These haven't been locked yet — flagged for a call before we cut the
implementation ticket.

1. **`Use` button on pending strips: keep or drop?**
   The keyboard action rail already applies the suggestion when the weight
   field is focused, so the in-card button is redundant by action — but it
   *is* the visible affordance that tells users the card is interactive at
   all. Default recommendation: **keep**, on the grounds of discoverability.

2. **Per-row vs global Details toggle in admin mode.**
   Today it's global. Per-row makes diff'ing two rows easier and stops a
   single tap from exploding the entire card. Default recommendation:
   **per-row** (C8 above).

3. **Stale state — banner copy.**
   Current: *"Based on a workout from Mar 1 — outside your recency window.
   Estimate may be optimistic."* Anchor date format ("Mar 1" vs "Mar 1,
   2026" vs "13w ago"): final call.

4. **Done strip cap.**
   In a long template (10+ sets), do done strips stack indefinitely, scroll
   internally, or collapse to a count? Default recommendation: **stack** — the
   card is inside the scroll view of the Sets sub-tab so the host already
   handles long content gracefully.

5. **B3 shape — embed snapshot or join externally.**
   Whether `completedInSessionSets[i].suggestedWeight` lives on the
   `CompletedSetSnapshot` directly or stays in a separate VM dict the view
   reads in parallel. Default recommendation: **embed** for one fewer
   lookup at render time.

---

## 6 · Estimated work, ordered

A rough implementation order that minimises blocked time:

1. **B1** + **B2** + **A1** + **A2** in one ticket — surfaces `baselineTopSet`
   and `e1RMSourceWorkoutDate`. Pure data plumbing; no UI changes yet.
2. **D1** + **B3** + **D3** — in-session suggestion snapshot cache and the
   `completedInSessionSets` data path.
3. **C1–C3** — restructure the user-mode card with Take B strips and the
   new section header. Drop the in-card title. (Visible win, biggest user
   impact.)
4. **C4** — done strips + divider.
5. **C5** + **C11** — stale state + slate colour token.
6. **C6** + **C7** + **C8** + **C9** — admin mode + structured diagnostics
   drawer + per-row Details state.
7. **C10** — last-top chip footer.
8. **C12** — `Use` button wiring (if kept per decision 1).

---

## 7 · Things explicitly **not** changing

* The suggestion engine (`SuggestionEngine.evaluate`) and its math.
* The cache-key shape and refresh triggers.
* The keyboard action rail's wand button (it stays as the primary apply
  path).
* `unavailableReason` semantics and copy.
* Sub-tab layout / placement of the module within `ActiveWorkoutView`.

---

*Implementation should land behind the same module wrapper, so no callers
outside of `WeightSuggestionCardView` / `WeightSuggestionModuleView` need
to be aware of the redesign.*
