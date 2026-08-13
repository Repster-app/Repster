# Step 5 — Where in-progress set edits live

**Date:** 2026-08-13
**Status:** design only, nothing implemented.
**Blocks:** §0.3 items 4–5 (`ActiveWorkoutViewModel` state, `SetTableView`/`SetRowView`).

Step 5 was scoped as "convert the active-workout set state from live models to value types."
That framing survived until the write path was actually read. It is wrong in one specific way,
and this document exists because the wrong version is cheap to start and expensive to abandon
halfway.

---

## 1. The problem

**The live `WorkoutSet` is the draft buffer.** `SetRowWrapper` (inside `SetTableView.swift`) has
**23 write sites**. Typing a character in the weight field parses it and assigns straight into the
model:

```swift
private func handleWeightChange(_ newValue: String) {
    handleFieldEdit(field: .weight) {
        set.weight = UnitConversion.parseDisplayedWeight(newValue, unitPreference: …)
    }
}
```

Nothing saves. The value sits on a repository-owned model until the user taps the checkmark.

Two consequences:

1. **It is a step-5 blocker.** A `ChartSetData` is immutable and disconnected; there is nowhere
   for a keystroke to go. The conversion cannot proceed until in-progress edits have a home.
2. **It is a live instance of the crash class, on the write side.** Every keystroke mutates a
   model owned by `SetRepository`'s background context, from the main actor, while that context
   may be mid-`save()`. Neither shipped crash was this shape — both were *reads* — but §5.5 of
   the crash analysis covers exactly this, and it is the highest-frequency unsafe write left in
   the app.

`SetRowView` is **not** implicated: it takes `let set: WorkoutSet` and only reads (38 sites).
The earlier claim that "the view never writes to the model" came from checking that file alone.

---

## 2. What actually depends on the drafts

This is the part that decides the design. The draft values are not write-only — four things read
them before a save happens.

| Consumer | What it reads | Why it matters |
|---|---|---|
| **Weight suggestions** | `SuggestionCoordinator.prepare(sets: currentSets, …)` takes the live sets, so drafted `reps`/`rir` feed straight into the prescription pipeline. `markSetDirty(_:field:)` exists solely to trigger a refresh on `.reps`/`.rir` edits | The headline behaviour: suggestions respond to what you are typing, before you commit |
| **Unilateral derivation** | `syncDerivedSetFields(for:)` runs `syncDerivedPerformanceFields` on the model mid-edit | Typing left/right reps updates `reps`, `rir` and `side` live, which the row then renders |
| **Auto-uncomplete** | `handleFieldEdit` captures `SetContributionSnapshot(set:)` **before** applying the edit, then hands it to `uncompleteSet` | Editing a completed row silently uncompletes it; the snapshot preserves the pre-edit contribution so stats decrement by the right amount |
| **Row rendering** | `hasData`, `prReps`, `totalReps` etc. are computed from the drafted fields | Checkmark enablement and the derived-value display |

Anything that keeps drafts out of the model has to keep all four working.

---

## 3. Options

### A. Draft dictionary on the ViewModel — recommended

`[UUID: SetDraft]` alongside `setsByExercise: [UUID: [ChartSetData]]`, where `SetDraft` carries
the same nine editable fields `SetCompletionInput` already carries. The row writes drafts through
the data source; the ViewModel merges draft over snapshot when it hands rows to the view and to
`SuggestionCoordinator`.

- **For:** all four consumers keep working with one mechanism. Drafts become inspectable state
  the existing test suite can assert on directly — today they are `@State` inside a private view
  struct and are untestable by construction. Clearing on commit is explicit and testable.
- **Against:** the merge has to happen everywhere rows are read, and a missed merge site is a
  silent bug (a row rendering stale values). Mitigated by making the merge the *only* public
  accessor — `currentSets` returns merged rows and the raw snapshot array stays private.
- **Note:** `SetCompletionInput` already is this type, minus a set id. `SetDraft` should be it,
  or `SetCompletionInput` should grow one, rather than a third near-identical struct.

### B. Drafts stay in `SetRowWrapper` `@State`, passed explicitly where needed

Keep the text state exactly where it is; stop writing to the model; pass a draft into the
suggestion call and the derivation.

- **For:** smallest diff, keeps per-row state per-row.
- **Against:** the suggestion pipeline needs *all* rows' drafts, not one — the row would have to
  push its draft up to the ViewModel anyway, which is option A with a worse shape. And drafts
  stay untestable.

### C. Write drafts through to the store

- **Against:** a save per keystroke on the app's hottest path, and it is the opposite of what
  the whole crash programme is for. Rejected.

**Recommendation: A.** B collapses into A as soon as the suggestion requirement is taken
seriously, and A is the only option that makes drafts testable.

---

## 4. What the conversion simplifies

Worth noting so it is not mistaken for scope creep:

- **The auto-uncomplete snapshot becomes unnecessary.** `handleFieldEdit` captures
  `SetContributionSnapshot(set:)` before the edit precisely because the edit is about to
  overwrite the persisted values on the shared instance. If drafts never touch the model, the
  model still holds the persisted contribution when `uncompleteSet` runs, and the repository can
  capture it itself — which is §3.3's "capture the contribution inside the actor".
- `markSetDirty` can carry the draft instead of being a bare "something changed" signal.

---

## 5. Test strategy — pin before converting

The journeys are the only net here: the real-data differential renders restored data and cannot
see write-path regressions at all (STEP5 §10.3). Before touching the view layer, pin these
against *current* behaviour, so they are a regression net rather than a description of whatever
the new code does:

- [ ] Typing reps into a pending row refreshes suggestions, and the refreshed suggestion reflects
      the typed value.
- [ ] Typing into a **completed** row auto-uncompletes it and decrements stats by the **pre-edit**
      contribution, not the drafted one. (The ordering trap.)
- [ ] Typing left/right reps on a unilateral exercise updates the derived `reps`/`side` the row
      renders, before any save.
- [ ] A draft that is never committed does **not** reach the store, and is gone after a relaunch.
- [ ] Switching exercise and back does not resurrect a stale draft.

The last two have no coverage today in either direction, and are exactly what a draft
dictionary makes possible to get wrong.

---

## 6. Recommended order

1. Land the journeys in §5 against current behaviour.
2. Introduce `SetDraft` + the ViewModel dictionary, still writing through to the model. Suite
   stays green; nothing changes yet.
3. Move the four consumers onto the merged accessor.
4. Stop writing to the model. **The journeys in §5 must still pass, unchanged** — this is the
   step where they earn their keep.
5. Only then convert `setsByExercise` to `[ChartSetData]`, which is now a type change rather than
   a redesign.

Step 4 is the one that removes the unsafe writes, and it is independently valuable even if the
snapshot conversion were abandoned.
