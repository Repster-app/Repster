# Device test pass — what changed and what to hammer

**For:** the build containing `c5b52e7` and the follow-up tail work.
**Why a new list:** `PRE_1.4_CHECKLIST.md` §7.1 is the general pre-release pass and still applies.
This one covers only what actually changed, ordered by risk.

Run on a **real device**, not the simulator. Two of the checks below are about *feel*, and the
simulator runs on Mac hardware — it is a lower bound, not a measurement.

---

## 1. Highest risk — the set-completion path

The twelve field writes that happen when you tap the checkmark moved from the main actor into the
repository actor. This is the app's most-performed interaction and the single change most likely
to have broken something.

- [ ] **Log a normal set.** Weight + reps → checkmark. Row completes, values stick.
- [ ] **Log a set with RIR.** Confirm the RIR value is still there after the row completes, and
      after leaving and re-entering the workout. *(A mutation deleting this write survived the
      whole test suite before today — it is the field most likely to silently vanish.)*
- [ ] **Log a set on a unilateral exercise** (Dumbbell Lunge). Enter left and right reps
      separately. Check: the row shows per-side values, the rep count derives correctly, and it
      survives leaving the screen.
- [ ] **Log a bodyweight-style set** (Pull Up) with added weight. The stored weight should be the
      added load; the workout-detail card afterwards should show load + bodyweight.
- [ ] **Duration or distance tracked exercise**, if you have one. Nothing in the automated suite
      covers these on the completion path.

**Feel check, and this is the one only you can do:** completing a set should feel instant. The
pipeline measured 3.5 ms typical / 15.7 ms worst case on simulator against a real 11,785-set
history, so there is roughly 10× headroom — but that was Mac hardware. If a tap ever feels like it
lags, that matters more than the numbers.

---

## 2. Adding and creating sets

Set creation moved inside the repository actor and no longer builds the model in the UI.

- [ ] Add a working set mid-exercise. Appears at the bottom, numbered correctly.
- [ ] Add a warmup set. Lands **first**, and the numbering of the others closes up.
- [ ] Force-quit and reopen mid-workout. Ordering is exactly as you left it.
- [ ] **Copy Previous** from Home. The copied sets carry weight and reps and are uncompleted.
- [ ] Start a workout from a template / with pre-picked exercises. One empty set per exercise.

---

## 3. Deleting, un-ticking, and PR badges

The badge rule changed here — this is a deliberate behaviour change you approved.

- [ ] Log a PR (heaviest yet at some rep count) → ★ appears.
- [ ] Log a heavier set at the same reps → ★ moves to the new one, the old row loses it.
- [ ] **Now delete the heavier set.** The ★ should come **straight back** to the earlier set,
      immediately, without leaving the screen. *(This is the changed behaviour: previously the
      rule would have suppressed it once sets became value types.)*
- [ ] **Un-tick a completed PR set.** Same expectation — the badge moves to whatever legitimately
      holds the record now.
- [ ] Delete a middle set. The remaining numbering closes the gap, and still has after a relaunch.

---

## 4. The History and PRs sub-tabs

Converted to snapshots, and their cache invalidation was broken.

- [ ] Open **History** on an exercise mid-workout. Past sessions show, newest first.
- [ ] Go back to **Sets**, delete a set, return to **History**. **The deleted set must be gone.**
      *(This was broken — it stayed listed until you switched exercise.)*
- [ ] Same for: add a set, add a warmup, change a set's type, edit a note. Each should be
      reflected when you return to History.
- [ ] Open the same exercise's History from the **Exercise detail** screen — same view, different
      entry point.

---

## 5. Editing an exercise mid-workout

This had two bugs, one fixed today.

- [ ] Exercise settings (gear) → change **rest time** → save. The next rest timer uses the new
      value without leaving the workout.
- [ ] Gear → **More Exercise Settings** → change something → save. The rest-time and increment
      rows should show the new values, not the pre-edit ones.
- [ ] While that sheet is open, **drag to reorder the exercise tabs**, then save. Nothing should
      land on the wrong exercise. *(This was the index-after-await bug — low probability, but it
      is the one that could corrupt which exercise you are looking at.)*
- [ ] Change a **calculation-critical** field (equipment type, unilateral, bodyweight factor) on
      an exercise with history. PRs and stats rebuild. Check the badges on that exercise still
      look right afterwards.

---

## 6. Notes and set types

Both moved off the main actor today.

- [ ] Add a note to a set → the orange dot appears, and is still there after a relaunch.
- [ ] Remove a note → dot goes.
- [ ] Change a set's type (working ↔ warmup ↔ dropset). Ordering and PR eligibility update.

---

## 7. Finishing, and the summary sheet

`computeSummary` now reads snapshots, and it runs *while* the workout is being saved.

- [ ] Finish a workout with several exercises. The summary shows the right set count, volume and
      PR count.
- [ ] Title and notes typed into the summary sheet survive to the saved workout.
- [ ] It appears on Home immediately, with the right numbers.
- [ ] **Finish ~10 workouts in rapid succession** (not spaced out). This is the original crash A
      repro — Home's reload debounce is defeated, so two loads interleave.

---

## Where it could be slow

Measured or reasoned, so you know what is normal and what is not.

| Action | Expectation | If it is slow |
|---|---|---|
| **Completing a set** | Imperceptible. 3.5 ms typical, 15.7 ms when it sets a new PR, on a real 11,785-set history | The one regression that would matter. A test enforces an order-of-magnitude budget, but only in-memory |
| **Restoring a backup** | **~10 s on simulator, plausibly 30 s+ on a phone**, including the stats and PR rebuild | Known and unaddressed. Worth checking the restore screen shows progress and cannot be mistaken for a hang — this is on the pre-1.4 list, not fixed |
| **Opening History on a heavily-trained exercise** | One fetch of every set for that exercise, then grouping. Should be fine at your data size | Would grow with history. It is cached per exercise until something changes |
| **Changing a calculation-critical exercise field** | Full PR + stats rebuild for that exercise. Seconds on a big exercise | Expected, not a regression |
| **First load of a workout** | One fetch plus per-exercise snapshots | — |

Nothing in today's work was expected to change performance except set completion, which is the
one to pay attention to.

---

## If something is wrong

The most valuable thing you can capture is **what you did in what order**, especially if a value
disappears or a badge looks wrong. Every bug found in this work has been an ordering or staleness
problem — "I did A then B and it showed the state from before A" — rather than an outright crash.
