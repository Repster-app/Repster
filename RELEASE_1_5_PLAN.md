# 1.5 Release Plan

**Date:** 2026-08-18
**Current version:** 1.4 (build 4) — **not yet shipped**
**Status:** scope planning. Nothing here is committed except Part 1.

## What this document is

Scope planning for 1.5 — what goes in, what doesn't, and what has to be decided
before the scope can lock.

It is deliberately **not** a launch checklist. [PRE_1.4_CHECKLIST.md](PRE_1.4_CHECKLIST.md)
is the model for that, and 1.5 gets its own once scope is settled. Launch
mechanics (App Store Connect, privacy policy, TestFlight verification) are out of
scope here.

## Standing constraint — 1.4 first

**1.4 has not shipped.** [PRE_1.4_CHECKLIST.md](PRE_1.4_CHECKLIST.md) still has
~138 open items, most of them outside Xcode: App Store Connect privacy
declarations, PostHog settings, and on-device HealthKit verification.

Nothing in Parts 2–4 below starts until 1.4 is out. The reason is in the 1.4 doc
itself: attribution is forward-only and cannot be backfilled, so delaying 1.4 to
add features to it costs measurement that can never be recovered.

---

# Part 1 — Carried over from 1.4 (decided, not candidates)

Two items were explicitly deferred to 1.5 on 2026-08-14. These are commitments.

## 1.1 Backup scope — `BodyweightEntry` first

[PRE_1.4_CHECKLIST.md §8](PRE_1.4_CHECKLIST.md), with the full audit in
[BACKUP_EXPORT_SCOPING.md](BACKUP_EXPORT_SCOPING.md).

A backup excludes `BodyweightEntry`, templates, programs, `InsightRecord`, and 21
of 24 `HealthProfile` fields. Not a regression — pre-existing, and the in-app copy
is technically accurate. The gap is that "restore replaces workout history only"
describes what restore won't *overwrite*, not what the backup doesn't *contain*.
Those two readings coincide on the device you exported from and diverge completely
on a new one, which is the case where someone actually reaches for a backup.

- [ ] Add `BodyweightEntry` to the archive — strongest candidate by far, since
      `effectiveWeight` for future bodyweight-style sets depends on the log
- [ ] Decide on templates and programs: include, or say plainly they aren't covered
- [ ] Reword the export screen to describe *contents* rather than restore semantics

**Note:** Phases 2 and 4 of `BACKUP_EXPORT_SCOPING.md` were implemented 2026-08-17
and are uncommitted on `NewMain`. Confirm whether those ride 1.4 or 1.5 before
planning around them.

## 1.2 Bodyweight-style set labels

[PRE_1.4_CHECKLIST.md §9](PRE_1.4_CHECKLIST.md).

A Pull Up logged at +10 kg renders as `10 kg` in the History tab and Exercise Info
card, but `90` on calendar/detail cards. Two entry points on the same formatter
with different rules. Cosmetic — no data is wrong — but `10 kg` on a Pull Up reads
as a bare weight.

- [ ] Pick one meaning: `BW+10 kg` or `90 kg`. The current `10 kg` is the one
      option not worth keeping
- [ ] Apply to **both** `performanceLabel` consumers, or the two active-workout
      surfaces still disagree with each other
- [ ] Update `WorkoutJourneyTests.testHistorySubTabShowsPastSessionsNewestFirst`,
      which pins the current behaviour

---

# Part 2 — The headline candidate: shareable workout card

**Recommended by its own design doc**, and the strongest claim on 1.5's headline
slot.

[SHARE_CARD_FEATURE_DESIGN.md](SHARE_CARD_FEATURE_DESIGN.md) makes the sequencing
call directly: don't bundle the card into 1.4, get the privacy work out, then ship
the card as 1.5 with its own release note — *"the first user-visible feature since
launch, and it deserves not to be buried under a privacy release."*

That reasoning holds. 1.4 is a privacy-and-measurement release with almost nothing
a user can see. 1.5 should be the opposite.

- **Phase 1 scope:** `ShareCardContent` + mapping, card view, renderer, preview
  sheet with two privacy toggles, summary-sheet entry point, shared
  `ActivityShareSheet`, Info.plist key, analytics, tests — plus the
  campaign-tagged App Store link and landing page
- **Estimate:** ~1 week, design iteration being the larger half
- **Dependencies:** none. Doesn't block anything else
- **Phase 2 gate:** open rate ≥ 8% before building retroactive sharing

Also item 1 and "your top pick" in [FEATURE_SCOPING_BRIEF.md](FEATURE_SCOPING_BRIEF.md).

**Open decision carried from that doc:** whether a short domain exists for the
card's face. The GitHub Pages URL works but wastes the impression.

---

# Part 3 — Muscle group coverage

Scoped in **[SECONDARY_MUSCLES_SCOPING.md](SECONDARY_MUSCLES_SCOPING.md)**.

Users want to track which muscles they're training — while planning a routine,
right after a workout, and over time. Two of those three surfaces don't exist
today: `CreateEditTemplateView` shows no muscle overview while editing, and
`WorkoutSummarySheet` shows none at all. `Exercise.secondaryMuscles` is already
persisted, seeded, and exported, and read by nothing.

The scoping doc splits it into three phases. **Phases 1 and 2 are the feature**;
Phase 3 is refinement of an existing panel.

| Phase | Contents | Fit for 1.5 |
|---|---|---|
| 1 | Taxonomy rollup, `MuscleAttribution` helper, secondary picker in the exercise editor, display on exercise detail | Good — small, self-contained, no arithmetic |
| 2 | Live coverage overview in the routine editor; muscle summary on the post-workout sheet | The actual feature. Sizeable |
| 3 | Insights panel weighting, chart/list filters, `HealthProfile` toggle | **Defer.** Not needed for the feature to land |

**Why Phase 3 can wait:** coverage display answers "does this routine hit back?" —
no weighting, no baseline, no credit constant. The 0.5-credit question that
dominated the original scoping applies only to the insights panel and is not a
blocker for anything users asked for.

**Blocking work regardless of phase:** the taxonomy mismatch. Primary and
secondary are drawn from different vocabularies — 42 of 96 seed secondary tags
(glutes, quads, hamstrings, calves) aren't in the 10-value catalog. The
recommendation is a rollup to `legs`, which is cheap but must happen first.

**Ranking caveat:** [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md)
puts this **4th**, behind three smaller items with louder demand (Part 4 below).
That ranking is sound. Phase 1 is small enough to ride along with them; Phase 2 is
what earns a slot of its own.

---

# Part 4 — Ahead of muscle coverage in the competitive ranking

From [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md) Part 3.
All three are small, and items 1–3 there are independent enough to ship together.

## 4.1 `bilateralLoadFactor` wiring — size S

Highest demand-to-effort ratio available. Per-dumbbell weight entry was the single
most-repeated concrete complaint in a ~500-comment Hevy thread, and the field
already exists on `Exercise`, already round-trips through export/templates/charts,
and is already read and written by `CreateEditExerciseViewModel`. Missing: a
control in the editor, and one branch in `computeEffectiveWeight`.

**Blocked on a decision, not on engineering** — see §5.1.

## 4.2 `Exercise.notes` — size S

Smallest gap on the list with the largest matching demand. `notes` exists on
`WorkoutSet`, `TemplateExercise`, `Workout`, and `WorkoutTemplate` — but not on
`Exercise`, which is exactly the "I paste the same setup note into every routine"
complaint. Lightweight SwiftData migration.

May want to be the same field as custom-exercise instructions — see §5.3.

## 4.3 Custom-exercise creation analytics — size XS

One PostHog event capturing name and equipment type on custom-exercise create.
Turns "our library is too small" from an unbounded content problem into a ranked
list driven by real user data.

**Should go first regardless of everything else in this document**, because it
starts collecting data that informs later decisions. Given that post-install
activation is the current growth bottleneck, "the exercise I do isn't in the app"
during a first session is a plausible activation killer worth measuring directly.

---

# Part 5 — Decisions that block scope lock

## 5.1 Backfill policy for `effectiveWeight` — blocking §4.1

`effectiveWeight` is persisted per set, not computed on read. Turning
`bilateralLoadFactor` on for an exercise with history does not retroactively fix
logged sets, and will produce a visible step change in that exercise's e1RM and
volume charts.

The same question applies to the machine starting-weight offset (a later item), so
it needs **one answer applied consistently to both**. Shipping the two with
different behaviours would be worse than either choice.

Recommendation on file: an explicit, opt-in, one-time backfill action with clear
copy — matching the pattern already recommended for the HealthKit historical
backfill.

## 5.2 Should seeded dumbbell exercises default to `bilateralLoadFactor = 2.0`?

Convenient, but changes existing users' numbers on update. Recommendation on file
is to ship the field off by default and let users opt in per exercise.

## 5.3 One field or two for notes and instructions?

One is simpler; two allows a short cue in the workout versus a longer how-to on
the detail screen. Affects §4.2's shape.

## 5.4 Free vs. RevenueCat entitlement

Reads as core logging correctness and should probably be free: `bilateralLoadFactor`,
`Exercise.notes`. Less obvious: muscle coverage. Worth settling before the release
note is written.

## 5.5 Is 0.5 the right secondary-muscle credit?

**Not blocking** — it applies only to Phase 3 of the muscle work, which is deferred.
Recorded here so it isn't rediscovered as a surprise later.

---

# Part 6 — Already in the tree, needs a home

Implemented but not yet attached to a release. **Confirm whether these ride 1.4 or
1.5** before planning around them.

| Work | Doc | State |
|---|---|---|
| Rest timer alarm D1–D6 | [REST_TIMER_ALARM_SCOPING.md](REST_TIMER_ALARM_SCOPING.md) | Implemented 2026-08-18. D3 needs provisioning work; D7 instrumentation deliberately not done — it turns on an unanswered privacy decision |
| Discard use-after-delete crash fix | [DISCARD_USE_AFTER_DELETE_SCOPING.md](DISCARD_USE_AFTER_DELETE_SCOPING.md) | Implemented 2026-08-17, reproduced and controlled 2026-08-18 |
| Backup export phases 2 and 4 | [BACKUP_EXPORT_SCOPING.md](BACKUP_EXPORT_SCOPING.md) | Implemented 2026-08-17, uncommitted on `NewMain` |

---

# Part 7 — Scoped but not proposed for 1.5

Open design docs, listed so they aren't forgotten. None are commitments.

- [SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md) — 12 of 13 `SetType` cases are
  labels attached to features that were never built. Includes undocumented fatigue
  multipliers worth writing down regardless
- [UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md) — never-started
  exercises appear in history as if logged
- [EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md) — design only
- [COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md) — parked 2026-08-11
- Machine setup as structured data — strongest differentiator in the competitive
  analysis, but size M and prone to multi-gym scope creep
- Programs UI / forward scheduling — models exist, `Features/Programs/Views/` is empty

---

# Suggested shape for 1.5

Deliberately conservative. 1.4 is a large, unshipped, mostly invisible release;
1.5 should be small, visible, and quick to follow.

| Priority | Item | Size | Source |
|---|---|---|---|
| 1 | Custom-exercise creation analytics | XS | §4.3 — do first, independent of everything |
| 2 | Share card Phase 1 | ~1 week | Part 2 — the headline |
| 3 | `bilateralLoadFactor` wiring | S | §4.1 — settle §5.1 first |
| 4 | `Exercise.notes` | S | §4.2 |
| 5 | Backup `BodyweightEntry` + copy fix | S | §1.1 — carried from 1.4 |
| 6 | Bodyweight label consistency | XS | §1.2 — carried from 1.4 |
| 7 | Muscle coverage Phase 1 | S | Part 3 — rides along if convenient |

**Muscle coverage Phase 2 is the natural headline for 1.6**, once Phase 1's
foundation is in and the seed tags have been seen in a real UI — which is itself
the cheapest way to find the wrong ones.

## Open question on the release itself

Is 1.5 one release or two? Items 1–4 are a coherent "logging correctness +
sharing" release that could ship quickly. Items 5–7 are a tidier second pass.
Splitting keeps the visible feature from waiting on the carried-over work; not
splitting means one release note instead of two.
