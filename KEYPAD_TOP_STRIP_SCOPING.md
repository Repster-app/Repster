# Set Keypad Top Strip — Scoping

**Date:** 2026-09-02
**Status:** **built** 2026-09-02 — `c1a6c52` (layout) and `84aad53` (`rirMode`). 788 tests pass.
Device pass still outstanding; checklist in §8.
**Origin:** with the set keypad open and a rep range being edited, the set list gets 114pt of an
844pt screen — two rows. Investigating that turned up a second, worse problem underneath it.

Two problems, one cause:

1. **Space.** The top strip renders a label row, a chip row *and* a two-row editor at the same
   time — 173pt above the keys. §1.
2. **Shift.** Because the editor stacks rather than replaces, opening it moves the whole set list
   down 88pt, while a thumb is on the keypad. §1.3.

Both fall out of one structural detail: the rep-range editor is a separate `if`, not part of the
`else if` chain it belongs in. The fix is §3.

Visual comparison of all four states: <https://claude.ai/code/artifact/0210f7c9-8b8b-43af-b6bb-0cfe779e3a9d>

---

## 1. What the strip is today

`topStrip` ([SetTableView.swift:1262](Repster/Features/Workout/Views/SetTableView.swift:1262)) is a
`VStack(spacing: 0)` of up to three blocks:

```swift
VStack(alignment: .leading, spacing: 0) {
    HStack { Text("Set"); Text("· \(fieldTitle(context.trackedField))"); Spacer() }
        .padding(.horizontal, 12).padding(.vertical, 10)          // 37pt, ALWAYS

    if showRIRChips(for: context) { … }                           // 48pt
    else if shouldShowWeightHelper(for: context) { … }            // ~24pt

    if repRangeEditMode { repRangeEditor(for: context) }          // 88pt, SEPARATE `if`
}
```

### 1.1 Measured heights

| Block | Anchor | Height |
|---|---|---|
| Label row | [:1264](Repster/Features/Workout/Views/SetTableView.swift:1264) | 37pt (17pt text + 10pt × 2) |
| RIR chips | [:1276](Repster/Features/Workout/Views/SetTableView.swift:1276) | 48pt (38pt circles + 10pt bottom) |
| Weight helper | [:1290](Repster/Features/Workout/Views/SetTableView.swift:1290) | ~24pt |
| Rep-range editor | [:1298](Repster/Features/Workout/Views/SetTableView.swift:1298) | 88pt (30 + 8 + 38 + 12 padding) |

Below the strip the keypad is fixed: 1pt divider, then 262pt of pad + rail + padding, then 4pt
outer padding. The overlay is a `safeAreaInset`
([ActiveWorkoutView.swift:134](Repster/Features/Workout/Views/ActiveWorkoutView.swift:134)), so the
set list is genuinely compressed, not covered.

### 1.2 Screen budget (iPhone 390×844, reps focused)

Top chrome is 211pt: 47 status + 44 header bar + 46 tab strip + 40 sub-tabs + 34 table header.
Bottom is 45pt rest-timer band + keypad + 34pt home indicator.

| State | Strip | Keypad | Set list | Rows |
|---|---|---|---|---|
| Chips only | 85pt | 352pt | **202pt** | 3 + part |
| Rep range open | 173pt | 440pt | **114pt** | 2 |

### 1.3 The 88pt shift

Those two rows are the same screen a tap apart. Opening the editor costs 88pt of list — most of
two rows — and it happens under the user's thumb at the moment they are reaching for a number.
This is the more serious of the two problems and it is invisible in any single screenshot.

---

## 2. The swap is exact, not approximate

The chips and the editor are relevant to **precisely the same fields**, so one can replace the
other with no state left uncovered:

```swift
// :1831
private func showRIRChips(for context:) -> Bool { context.canEditActiveRIR }   // reps | leftReps | rightReps

// :1838
private func supportsRepRangeEditing(for field:) -> Bool {
    switch field { case .reps, .leftReps, .rightReps: true; default: false }
}
```

Resulting slot contents:

| Focused field | Editor closed | Editor open |
|---|---|---|
| `reps` / `leftReps` / `rightReps` | RIR chips | Rep-range row |
| `weight`, barbell | plate helper | *unreachable* |
| `weight`, other equipment | empty | *unreachable* |
| `duration` / `distance` | empty | *unreachable* |

Transitions are already handled. Moving focus to a field that supports neither closes the editor
at [:1252](Repster/Features/Workout/Views/SetTableView.swift:1252):

```swift
.onChange(of: manager.context?.trackedField) { _, newField in
    guard !supportsRepRangeEditing(for: newField) else { return }
    repRangeEditMode = false
}
```

**No new state or logic is needed for the swap.** It is a change of layout only.

---

## 3. The changes

### C1 — One slot

Fold the editor into the existing chain so exactly one block renders.

```swift
if repRangeEditMode {
    repRangeEditor(for: context)          // takes precedence when open
} else if showRIRChips(for: context) {
    chips
} else if shouldShowWeightHelper(for: context) {
    weightHelper
}
```

### C2 — Editor flattens to one 44pt row

Rewrite `repRangeEditor` ([:1304](Repster/Features/Workout/Views/SetTableView.swift:1304)) from a
two-row `VStack` to a single `HStack` with `.frame(height: 44)` and `.padding(.horizontal, 12)`.
Contents left to right: target icon + "Range", min field, dash, max field, `Spacer()`, Apply.
Drops the inline Cancel — see §5.

### C3 — Delete the label row

Remove [:1264–1275](Repster/Features/Workout/Views/SetTableView.swift:1264). Field identity is
already carried by the table column headers, by the `L` / `R` labels beside each unilateral field
([SetRowView.swift:831](Repster/Features/Workout/Views/SetRowView.swift:831)), and by the accent
border on the focused field. `fieldTitle` has exactly one caller and goes with it — §6.

The slot then becomes the card's first child, against an 18pt corner radius
([:1242](Repster/Features/Workout/Views/SetTableView.swift:1242)), so **both** the chips and the
editor row must centre their content vertically in the 44pt band rather than sit flush to the top.
At 3pt inset the corner curve is clear of content starting at x = 12.

### C4 — Chips trim to the slot, 48 → 44pt

Replace `.padding(.bottom, 10)` at
[:1288](Repster/Features/Workout/Views/SetTableView.swift:1288) with a `.frame(height: 44)` on the
horizontal `ScrollView`, content centred. This is what makes the swap *visually* still — at 48 vs
44 every toggle would still nudge the list by 4pt.

### C5 — Divider follows the strip

With C3 applied, a `duration` or `distance` field renders an **empty** strip, leaving the divider
at [:1229](Repster/Features/Workout/Views/SetTableView.swift:1229) flush against the card's rounded
top edge. Make it conditional on the strip having content.

### Result

| State | Strip | Set list | Rows |
|---|---|---|---|
| Chips only | 44pt | **243pt** | 4 + part |
| Rep range open | 44pt | **243pt** | 4 + part |

114 → 243pt with the editor open (**+129pt**), and the shift on toggle goes from 88pt to **0**.

---

## 4. The one real design decision: the invalid draft

`repRangeDraftState` returns `.invalid` for e.g. `min > max`, and the editor currently appends a
fourth line ([:1348](Repster/Features/Workout/Views/SetTableView.swift:1348)):

```swift
if hasInvalidDraft {
    Text("Use one rep value or an ascending range.")
        .font(.system(size: 12, weight: .medium)).foregroundColor(.danger)
}
```

**That line does not fit a fixed 44pt row, and letting the row grow reintroduces the shift C4 just
removed.** Three options:

| | Approach | Cost |
|---|---|---|
| a | Drop the text. Fields already turn red (`showsError`) and Apply already disables. | Loses the *why* |
| b | Let the row grow when invalid | Reintroduces a jump, at the worst moment |
| c | **Swap the label for a short danger-coloured message** while invalid | Needs a shorter string |

**Recommended: (c).** The label slot is flexible and the row has ~74pt of slack at 390pt width, so
a string of up to ~13 characters fits without touching the fields or Apply. The full sentence has
nowhere to live in a one-line editor, and (a) leaves a red field with no explanation.

**As built:** (c), with two refinements the scope did not anticipate.

1. The message is **two strings, not one**. `.invalid` collapses two different failures, and a
   zero is reachable — `handleRepRangeKey` accepts `"0"` as a first digit. So `repRangeErrorText`
   returns `Reps must be 1+` for a non-positive value and `Min below max` otherwise. A single
   string would have been wrong for one of them.
2. Fitting is by **layout priority, not by counting characters**. The fields, dash and Apply carry
   `.layoutPriority(1)` and hold their widths; the label takes the remainder with `.lineLimit(1)`
   and `.minimumScaleFactor(0.75)`, so it shrinks ahead of them. That survives the longer error
   string on an SE and degrades sanely under Dynamic Type instead of clipping Apply.

---

## 5. Width budget

Measured at 390pt (card is 378pt after the 6pt inset each side; content box 354pt):

| Part | Width |
|---|---|
| "Rep Range" label | 85.6pt |
| min field | 56pt |
| dash | 14pt |
| max field | 56pt |
| Cancel | 62.5pt |
| Apply | 56.1pt |
| 6 gaps + padding | 72pt |
| **Total** | **402pt** |

**402pt does not fit 378pt, and an iPhone SE card is 363pt.** Two changes bring it to ~304pt:

- Label "Rep Range" → "Range" (−30pt).
- Drop the inline Cancel (−70pt). It is a **duplicate**: the rail's "Editing" button already calls
  `dismissRepRangeEditMode` ([:1455](Repster/Features/Workout/Views/SetTableView.swift:1455)), and
  the `onChange` at [:1252](Repster/Features/Workout/Views/SetTableView.swift:1252) closes it on
  focus change. Verified no overflow down to a 320pt card.

---

## 6. Provably inert code to remove

| Symbol | Sites | Evidence |
|---|---|---|
| `fieldTitle` | [:1798](Repster/Features/Workout/Views/SetTableView.swift:1798) | One caller, at [:1268](Repster/Features/Workout/Views/SetTableView.swift:1268), which C3 deletes |
| `repMode` | [:1215](Repster/Features/Workout/Views/SetTableView.swift:1215), [:1248](Repster/Features/Workout/Views/SetTableView.swift:1248) | Declared, assigned `"F"`, **never read** |
| `rirMode` | 7 sites | Initialised `false` and only ever assigned `false`. The `if rirMode` branch at [:1832](Repster/Features/Workout/Views/SetTableView.swift:1832) returns the same value as its fallthrough, and the guard at [:1722](Repster/Features/Workout/Views/SetTableView.swift:1722) always passes |

`fieldTitle` and `repMode` belong in this change. **`rirMode` should be a separate commit** — it is
provably inert but touches seven sites across key handling, and mixing it in makes the layout
change harder to review and revert.

---

## 7. Explicitly out of scope

| Considered | Decision |
|---|---|
| Hiding the tab strip + sub-tab picker while typing (+86pt) | **Rejected** — user will not use it |
| Pinning the table column headers | **Rejected** — the residual "no field label while scrolled" risk is accepted |
| Rest-timer band → pill in the keypad header (+45pt) | **Blocked** by C3; the pill would need rehousing in the Range row's free stretch |
| `ScrollViewReader` on the set table | Separate. Nothing scrolls the focused row into view, which decides *which* rows occupy the space these changes win |
| Plate helper for `machinePlate` equipment | Separate task — the helper is gated on `.barbell` alone at [:1848](Repster/Features/Workout/Views/SetTableView.swift:1848) and `machinePlate` drives no behaviour anywhere |
| VoiceOver labels on `SetInputField` | Separate. `SetInputField` and all ~550 lines of the keypad carry **zero** accessibility modifiers today; custom-entry fields render as `Button`s labelled with only their value |

---

## 8. Test strategy

**There are no view-level tests for the keypad or `SetTableView`.** Nothing in `RepsterTests/`
references `fieldTitle`, the top strip, or the overlay, so this change breaks no existing test.

The write path is untouched: Apply calls `commitTargetRepRange`, which is the
`onCommitTargetRepRange` closure passed in from
[SetRowView.swift:768](Repster/Features/Workout/Views/SetRowView.swift:768). Target rep-range
persistence is already covered at the service and model layer (`SetServiceTests`,
`WorkoutSetTests`).

So: **no new automated tests are warranted** — this is layout. Run the existing suite once to
confirm nothing regressed (single run into a log; concurrent runs invent failures), then verify by
hand:

1. Reps focused, editor closed → chips, 44pt band.
2. Tap Range → editor replaces chips, **list does not move**.
3. Type `10` then `6` → invalid state renders inside 44pt, Apply disabled.
4. Apply → range commits, chips return.
5. Prev/Next from reps to weight, barbell → editor auto-closes, plate helper shows.
6. Prev/Next to a `duration` field → empty strip, **no orphan divider** (C5).
7. Unilateral exercise → `L` / `R` still identify the side with no label row.
8. iPhone SE → Range row does not clip Apply.

---

## 9. Sequencing

| Step | Change | Reviewable alone |
|---|---|---|
| 1 | C1 + C2 — one slot, editor flattened, Cancel dropped, §4 (c) | Yes — this alone is +92pt and kills the 88pt shift |
| 2 | C3 + C5 — label row deleted, divider conditional, `fieldTitle` + `repMode` removed | Yes — +37pt |
| 3 | C4 — chips 48 → 44 | Yes — +4pt, and makes the swap pixel-stable |
| 4 | `rirMode` removal | Separate, no behaviour change |

Step 1 carries the real user-visible win and is independently shippable. Steps 2–3 are what make
the two states identical, so if only part of this lands, land 1 and 3 together.

**As built:** steps 1–3 landed together in `c1a6c52` — they all rewrite `topStrip` and share the
`slotHeight` constant, so splitting them would have meant unpicking one edit into three. Step 4 is
`84aad53`, separate as planned.

---

## 10. Risks

- **Reduced redundancy while scrolled.** The table column headers scroll with the content
  ([ActiveWorkoutView.swift:249](Repster/Features/Workout/Views/ActiveWorkoutView.swift:249)), so
  after C3, a user scrolled down *and* moving focus with Prev/Next has no on-screen name for the
  focused field. Accepted (§7); column position disambiguates in practice.
- **`refreshTick` churn.** `.id(refreshTick)` on the overlay's root
  ([:1236](Repster/Features/Workout/Views/SetTableView.swift:1236)) rebuilds the whole keypad on
  every rep-range keystroke. Pre-existing, unchanged here, but worth knowing if the flattened row
  animates oddly.
- **Dynamic Type.** The width budget in §5 is measured at default type size. The Range row has
  ~74pt of slack at 390pt; large accessibility sizes will still overflow. Not currently handled
  anywhere in the keypad.
