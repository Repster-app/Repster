# Device test pass — Smart Suggestions 1.5

**Date:** 2026-08-27 · **Branch:** NewMain

Nine checks, roughly 30 minutes. Each names the **one thing to look at** and what it used to do,
so a wrong number is obvious rather than needing arithmetic.

**Setup, once:** Settings → Suggestions → turn **Admin Mode** on. It reveals the per-set diagnostics
under each suggestion, which is how you tell *why* a number came out, not just what it is.

Use kg. If you train in lbs the logic is identical but every number below shifts.

---

## 1 · The floor — the headline fix

The reported Leg Extension failure: the app suggested a weight *below* one you'd just lifted with
plenty left in the tank.

1. Start a workout, add an exercise you have **never logged before**
2. Set 1 — **20 kg × 8**, tap RIR **5+**, tick complete
3. Set 2 — **35 kg × 8**, tap RIR **5+**, tick complete
4. Look at the suggestion for set 3

| | |
|---|---|
| **Expect** | **37.5 kg** or higher |
| Explanation reads | *"Holding above your last set — you had 5 reps left in it."* |
| Before this release | 32.5 kg, explained as *"Easing off slightly to manage session fatigue"* |

The explanation line is the real check — it is the only place the floor announces itself. A correct
number with the old fatigue wording means the floor did **not** fire and something else produced 37.5.

**Note:** set 1 shows no suggestion at all on a brand-new exercise. That is correct and unchanged —
there is no history to price from yet.

---

## 2 · Reps in reserve stop pushing the weight down

Two sessions. The one users would never have reported as a bug, because it looks like the app is
just being cautious.

**Session A**
1. Pick a second unlogged exercise
2. One set — **60 kg × 8**, RIR **2**, complete
3. **Finish the workout**

**Session B** — start a new workout, same exercise, look at set 1's suggestion.

| | |
|---|---|
| **Expect** | **60 kg or above** |
| Before this release | **57.5 kg** — below what you just did, and dropping ~4% again every session |

---

## 3 · A drop set stops wrecking the rest of the exercise

1. New workout, an exercise with some history
2. Set 1 — **100 kg × 8**, RIR **2**, complete *(scale to something you can actually do; the ratio is what matters)*
3. Set 2 — **60 kg × 10**, RIR **0** — **long-press the row → Edit Set Type → Drop Set** — complete
4. Look at set 3

**Expect:** roughly what set 2 would have been suggested at — in the region of **90 kg**, not
collapsed to the 50s. Open the diagnostics: **session capability should still be ~133**, not ~81.

Before this release the app concluded your capacity had fallen 38% mid-exercise.

---

## 4 · An untagged light set is bounded, not ignored

Same as test 3, but leave set 2 as a normal **Working** set.

**Expect:** set 3 lands **between** the two behaviours — noticeably lower than test 3, clearly higher
than the old collapse. Diagnostics should show capability around **106**, which is exactly 20% below
133. That 20% is the clamp doing its job.

The distinction being tested: a *tagged* drop set is ignored for capacity entirely; an *untagged*
light set still counts but can only drag the estimate down so far.

---

## 5 · Leaving the RIR chip blank stops costing you

1. New workout, an exercise with history
2. Log **four sets at the same weight × 8 reps**, ticking each complete **without tapping any RIR chip**
3. Note the suggestion for set 5
4. Repeat the whole thing in a fresh workout, this time tapping **RIR 2** on every set

**Expect:** the two set-5 suggestions **match**.

Before this release the unlabelled version came out an increment lower — the app treated "didn't
say" as "went to failure".

---

## 6 · Your charts and PRs must not move

The change that would be worst to get wrong, because it would be silent.

1. **Before updating**, screenshot an exercise's e1RM chart and its PR list
2. Update, reopen the same exercise

**Expect:** byte-identical. Same chart shape, same PR weights, same dates.

The capacity maths changed, but only where suggestions read it. Stored values are untouched by
design, and if a chart moved, that assumption is wrong.

---

## 7 · Learned tuning resets, history survives

Settings → Suggestions → Fatigue → **Fatigue Learning**.

| Look at | Expect |
|---|---|
| Per-exercise fatigue rates | Back to **default** — the learned values are gone |
| Session / audit rows | **Still listed**, with their prescribed-vs-actual numbers intact |

Both halves matter. Rates clearing is intended — they were tuned for the old maths. The rows
surviving is the part that took a deliberate decision: they cannot be recomputed once deleted.

---

## 8 · The kill switch

Settings → Suggestions → **Capacity Guards** (Admin Mode only).

Turn it **off**, then repeat test 1.

**Expect:** 32.5 kg and the old fatigue wording — the pre-1.5 behaviour exactly.

Turn it back **on** and confirm 37.5 returns. This is the lever if anything above misbehaves for
real users, so it is worth knowing it works before you need it.

---

## 9 · Backup round trip

1. Settings → Export → save a backup
2. Restore it

**Expect:** completes without error, history intact.

This release changed how set types and audit statuses are written into the archive, and a mistake
there costs the whole file rather than one column.

---

## What "failed" looks like

| Symptom | Likely cause |
|---|---|
| Test 1 gives 37.5 but the old fatigue wording | Floor didn't fire; something else produced the number |
| Test 1 still gives 32.5 | Capacity Guards is off, or the build is stale |
| Test 2 gives 57.5 | The capacity baseline is still reading stored e1RM |
| Test 6 charts moved | Stored e1RM is being rewritten — stop and flag this one |
| Test 7 shows learned rates intact | The startup reset didn't run |
| Test 9 fails to restore | Archive compatibility — flag immediately, it costs user data |

Anything in the last two rows is worth stopping for. The rest are recoverable.
