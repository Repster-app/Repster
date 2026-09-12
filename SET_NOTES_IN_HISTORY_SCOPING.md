# Set notes in history — scoping

**Status:** scoped 2026-09-11, **built 2026-09-12**, uncommitted. Target: 1.6. D5 (accessibility)
is not built. The device pass (§7) is outstanding. See §10 for what the build added.
**Origin:** mid-workout, the History sub-tab shows an orange dot on sets that have a note
but never shows the note. The only way to read one is to open the note *editor* on an
editable set.
**Decided 2026-09-11:** option **B, tap to reveal** (D1); the Calendar card is in this build
(D2); several notes can be open at once (D3); no analytics counter (D4); the orange dot stays
next to the chevron (D6). Option C, last session's notes on the Sets tab, was rejected on
2026-09-10. Drawn at device scale on the design review page:
https://claude.ai/code/artifact/6672dcc0-7887-4b03-ae13-7de443a2ba9b

**Still open:** D5, accessibility (§9). Everything else here is a default the build follows
unless told otherwise. §3 records what option A would have changed.

---

## 1. What exists today

**The data is already there.** `ChartSetData.notes` is carried into every history snapshot
([ChartSetData.swift:44](Repster/Core/Services/ChartSetData.swift:44)), and
[ScreenDataGoldenMasterTests.swift:388](RepsterTests/ScreenDataGoldenMasterTests.swift:388)
already asserts that a history group carries both `hasNote` and the note text. This is a
display change only: no model, service or fetch work.

**Where a set note is drawn:**

| Surface | File | Today |
|---|---|---|
| Exercise history: History sub-tab in a workout, and exercise detail | [ExerciseHistoryView.swift:104](Repster/Features/Exercise/Views/ExerciseHistoryView.swift:104) | 5 pt orange dot, not tappable |
| Past workout detail (Calendar, Home, Workouts tab) | [CalendarExerciseCard.swift:115](Repster/Features/Calendar/Views/Components/CalendarExerciseCard.swift:115) | 5 pt orange dot, not tappable |
| Live set table | [SetRowView.swift:615](Repster/Features/Workout/Views/SetRowView.swift:615) | Badge with dot opens the Set Note alert |

Neither read-only dot has an accessibility label, so VoiceOver gets nothing.

**Notes are one line by construction.** They're typed into a `UIAlertController` text field
([SetTableView.swift:611](Repster/Features/Workout/Views/SetTableView.swift:611)), which
can't take a newline. Longer notes can only arrive by CSV import (FitNotes, Strong and Hevy
all map a Notes column to set notes).

**History refreshes after a note edit.** `updateSetNote` calls
`invalidateSetDerivedSubTabCaches()`
([ActiveWorkoutViewModel.swift:2764](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:2764)),
and the History tab reloads on appear, so a note written a minute ago shows up. No
freshness work is needed.

**Session replay already promises set notes are hidden.**
[docs/privacy.html:89](docs/privacy.html:89) says workout, set and template notes are hidden
before a recording is uploaded, and the App Review notes say the same. Today that's trivially
true because no screen displays a set note. Once history displays one, it has to be masked
or the policy becomes false. No policy wording changes; the code has to comply.

**The replay guard won't catch this.**
[ReplayMaskCoverageTests.swift:195](RepsterTests/ReplayMaskCoverageTests.swift:195) scans
only for `TextField(`, `TextEditor(` and `SecureField(`. A `Text(note)` passes silently.

---

## 2. Design: option B, tap to reveal

### 2.1 Behaviour

- A row with a note becomes a button. Tapping it opens the note in a strip directly under
  the row; tapping again closes it.
- Rows without a note are unchanged and not tappable.
- A small chevron at the trailing edge marks rows that can open. It points down when closed
  and up when open.
- The orange dot on the set badge stays. It's the note colour app-wide; the chevron is the
  affordance (D6).
- Several notes can be open at once (D3).
- Open state resets when you leave: switching exercise in a workout puts the sub-tab back
  on Sets, which removes the view, and exercise detail does the same on a tab switch.

### 2.2 Layout

- **Strip:** indented 32 pt (the 24 pt badge column plus 8 pt gap), so it lines up with the
  performance text. `bgSubtle` background, 6 pt radius, 8/10 pt padding. A 12 pt
  `note.text` icon in `.orange`, then the note in 12 pt `textPrimary` with **no line limit**,
  since imported notes can be long and the reader asked to see it.
- **Warm-ups:** the row's `.opacity(0.6)`
  ([ExerciseHistoryView.swift:138](Repster/Features/Exercise/Views/ExerciseHistoryView.swift:138))
  stays on the row's `HStack`. The strip sits outside it, so a warm-up's note isn't dimmed.
- **Chevron slot:** 14 pt wide, after `PRBadgeView`. Reserve the slot on every row of a
  session card that has **at least one** note, so PR badges stay in one column. Cards with
  no notes are pixel-identical to today.
- **Hit target:** rows are about 30 pt tall (`.padding(.vertical, 6)` around 14 pt text,
  [ExerciseHistoryView.swift:137](Repster/Features/Exercise/Views/ExerciseHistoryView.swift:137)),
  below the 44 pt guideline. The button takes the full row width via
  `.contentShape(Rectangle())`, and only noted rows are tappable, so a near-miss lands on
  nothing. If the device pass shows missed taps, raise the vertical padding on all rows
  rather than only noted ones, so rows stay even.

### 2.3 State

`@State private var expandedSetIds: Set<UUID>` lives on `ExerciseHistoryView` itself, not
on the session cards. The cards sit in a `LazyVStack`
([ExerciseHistoryView.swift:22](Repster/Features/Exercise/Views/ExerciseHistoryView.swift:22)),
and state held on the parent survives cards scrolling in and out. Set ids are stable across
a reload, so an open note stays open if history reloads underneath it.

This is the same pattern `WeightSuggestionCardView` already uses for its admin drawer
(`expandedSetIds` toggled with `withAnimation(.easeInOut(duration: 0.18))`). Match that
timing. (Honouring Reduce Motion is part of D5; nothing in the app does it yet.)

### 2.4 One component for the note text

Add `SetNoteStrip(text:)` under `Features/Workout/Views/Components/`. It applies
`.replayMasked()` itself, so the mask lives in one place, and both history surfaces use it.
Nothing else in the app should render set-note text directly.

### 2.5 Accessibility (pending D5)

Built only if D5 is yes. See §9 for what the app does today.

- Every history row becomes one element (`.accessibilityElement(children: .combine)`) with a
  spoken label, e.g. "Set 2, 82.5 kilograms by 8, RIR 1".
- A noted row appends the note to its label whether or not it's open: "…, note: Right
  elbow drifting out". VoiceOver users get the note without a second action (D5).
- The button keeps a hint ("Shows the note on screen") and exposes open or closed as its
  value.
- Build the label in a pure helper so it can be unit-tested (§5).

### 2.6 Replay guard

Extend `ReplayMaskCoverageTests` with a second check alongside the input-field inventory:

- `SetNoteStrip.swift` must contain `replayMasked()`.
- No file under `Repster/Features` may pass a non-literal argument mentioning "note" to
  `Text(` (for example `Text(set.notes ?? "")` or `Text(note)`) unless it's listed in a small
  inventory. Literal strings such as `Text("Add a note to this set")` don't match.

That turns "someone displays a note next month and forgets the mask" into a failing build,
which is the same bargain the input-field inventory already makes.

### 2.7 Analytics

None (D4). No new `WorkoutInteraction` case, and `ExerciseHistoryView` gets no callback. The
existing `history_views` count is unchanged, and the uncommitted analytics edits from the
duplicate-exercise work aren't touched.

---

## 3. What option A would have changed

Kept for the record. A shows every note as an always-visible line under its row. Compared
with B it drops the button, the chevron and its slot, and the expanded state. It keeps
`SetNoteStrip` (restyled as a plain 12 pt `textSecondary` line with no background), the replay
mask and its guard. It would have added a line-limit decision for imported notes. It's
smaller to build; the cost moves to screen space.

---

## 4. Files

| File | Change |
|---|---|
| `Repster/Features/Workout/Views/Components/SetNoteStrip.swift` | **New.** Masked note strip |
| `Repster/Features/Exercise/Views/ExerciseHistoryView.swift` | Expanded state, noted-row button, chevron slot, strip |
| `Repster/Features/Calendar/Views/Components/CalendarExerciseCard.swift` | Same treatment (D2) |
| `RepsterTests/ReplayMaskCoverageTests.swift` | Displayed-note check (§2.6) |
| New test file for the accessibility label helper | Only if D5 is yes |

No model, schema, service, backup, migration or analytics changes. `ActiveWorkoutView` is
untouched: the History sub-tab and exercise detail both get B through `ExerciseHistoryView`.

---

## 5. Tests

- **Replay guard:** the new check passes with `SetNoteStrip` masked, and fails when a stub
  `Text(set.notes ?? "")` is added to a Features file. Verify the failure once by hand, as
  was done for the input-field inventory.
- **Data:** already covered by `ScreenDataGoldenMasterTests.swift:388`.
- **Accessibility label helper**, if D5: a working set, a warm-up, a drop set, a set with a
  PR, and the same with a note appended. Pure function, no view.

Run the suite once into a log, not concurrently.

---

## 6. Build order and estimate

1. `SetNoteStrip` and the replay guard, so the mask exists before any screen shows a note.
2. `ExerciseHistoryView`: state, button, chevron slot, strip. This covers the in-workout
   History tab and exercise detail at once.
3. `CalendarExerciseCard` (D2). Its cards sit in a plain `VStack`
   ([CalendarWorkoutDetailView.swift:49](Repster/Features/Calendar/Views/CalendarWorkoutDetailView.swift:49)),
   not a lazy one, so the expanded state can live on the card. Its rows are column-based
   with a 44 pt PR column, so the chevron needs its own slot there too.
4. Accessibility label and its tests, if D5.

**Estimate:** small. Roughly half a day for steps 1 to 3, plus the device pass. Step 4 adds
about an hour.

---

## 7. Device pass (tap steps)

1. In a workout, complete a set and add a note via the set badge (Set Note alert).
2. Open the History sub-tab. Today's session shows that set with a chevron. Tap the row: the
   note opens under it. Tap again: it closes.
3. Open two notes in one session card. Scroll the list down and back: both are still open.
4. Switch to another exercise and back, then open History: everything is closed.
5. A warm-up with a note: its strip is full brightness while the row stays dimmed.
6. A session with no notes: rows look exactly as before and PR badges line up.
7. A session mixing noted and plain rows: PR badges still line up.
8. Exercise detail, outside a workout: same behaviour.
9. A past workout in Calendar: same behaviour.
10. Import a CSV with a long note: the strip wraps to show all of it.
11. In a session recording, the open note appears masked.
12. If D5: VoiceOver on a noted row reads the note without opening it.

---

## 8. Out of scope

- **Editing a past note from history.** The view holds snapshots with no data source, and
  exercise detail reaches sessions months back; editing there is a bigger step than it looks.
- **The workout-level note** (written in `WorkoutSummarySheet`, shown nowhere afterwards).
  Same class of gap, different surface.
- **The exercise note** (`Exercise.notes`). **Paused 2026-09-11.** The "Exercise details"
  mockups stay on the review page, and the findings stand: templates' exercise notes are
  dropped when a workout starts
  ([TemplateService.swift:281](Repster/Core/Services/TemplateService.swift:281)).
- **Notes on sets that were never ticked.** History lists completed sets only, so a note on
  an unticked set never appears there. That's existing behaviour, tied to
  [UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md).
- **A session-footer roll-up** of notes. It breaks the link between a note and its set.
- **Counting note opens** (D4).

---

## 9. Decisions

| # | Decision | Answer |
|---|---|---|
| D1 | B (tap to reveal) or A (always visible)? | **B** |
| D2 | Give the Calendar card the same treatment in this build? | **Yes** |
| D3 | Several notes open at once, or one at a time? | **Several** |
| D4 | Count note opens? | **No.** Not important enough to add a counter. |
| D5 | Give history rows a VoiceOver label that includes the note, and honour Reduce Motion? | **Open** (below) |
| D6 | Keep the orange dot alongside the chevron? | **Keep** |

**D5: what the app does for accessibility today** (surveyed 2026-09-11):

- **VoiceOver:** some, added one control at a time rather than in a pass. 66
  `accessibilityLabel`s across 27 files, 11 hints and 24 element groupings, clustered where
  a custom control would otherwise read as nothing: the set row, exercise tab strip, rest
  timer, suggestion strips, the PR-exclusion and superset chips, and most of Insights.
  Exercise history and the Calendar card have none, so their dots are silent today.
- **Text size (Dynamic Type):** effectively unsupported. About 700 fixed
  `.font(.system(size:))` calls against about 150 text-style fonts, and no `@ScaledMetric`.
- **Reduce Motion:** not honoured anywhere.

So the choice is either to follow the neighbouring suggestion strips and chips, which is about
an hour, or to leave history rows as silent as they are now and treat accessibility as its
own pass later.

---

## 10. As built (2026-09-12)

- **`SetNoteStrip`**, new in `Repster/Features/Workout/Views/Components/`, is registered in the
  Xcode project by hand (`SN0001` / `SN1001`). The main target doesn't use synchronized folders.
  It masks the note text with `replayMasked()` itself.
- **`ExerciseHistoryView`**: `expandedSetIds` on the view, noted rows wrapped in a plain
  `Button`, strip inside the button label so a tap on the note also closes it. The chevron slot
  is reserved per card. The chevron is `accessibilityHidden`: it's decoration, and hiding it
  keeps VoiceOver from reading "Down" on rows where it's invisible. That isn't D5.
- **`CalendarExerciseCard`**: the same, with the state on the card. The card is itself a
  `Button` that opens the exercise, so a noted row is **a button inside a button**. SwiftUI
  gives the tap to the inner one, but check it on a device (§7 step 9): tapping a noted row
  should open the note, and tapping anywhere else on the card should still open the exercise.
- **`ReplayMaskCoverageTests`**: `testDisplayedNoteTextIsMasked` scans for `Text(` whose code
  (not string-literal text) mentions "note", and checks each against `displayedNoteInventory`.
  That inventory holds the three template-note displays that already existed, all masked
  on the line. `testSetNoteStripStillMasks` pins the strip's mask.
- **`ReplayPrivacy.swift`**: header comment now mentions the displayed-note guard.
- **Tests, 2026-09-12:** full suite on iPhone 17 Pro, iOS 26.3.1: **889 tests, 885 passed,
  4 skipped, 0 failed** (totals read from the `.xcresult`). The guard was verified to fail by
  hand: a stub file outside the target containing `Text(set.notes ?? "")` made
  `testDisplayedNoteTextIsMasked` fail and quote that line. The stub was then removed. Not run
  on iOS 17.5, where the suite has known, unrelated failures.
