# 1.5 Release Plan

**Originally written:** 2026-08-18 · **Revised against the tree:** 2026-09-01
**Live:** 1.4 (build 4), released 2026-08-20
**In the project right now:** `MARKETING_VERSION = 1.4.1`, build 5 — the number is
**not settled**; that decision lives in [PRE_1.5_CHECKLIST.md §0](PRE_1.5_CHECKLIST.md)
**Status:** no longer scope planning. Most of this release is built. The open work
is deciding what ships under one name.

## What this document is

Scope planning for 1.5 — what goes in, what doesn't, and what has to be decided
before the scope can lock.

It is deliberately **not** a launch checklist. [PRE_1.5_CHECKLIST.md](PRE_1.5_CHECKLIST.md)
is that, and it now exists. Launch mechanics (App Store Connect, privacy policy,
TestFlight verification) are out of scope here.

## What changed in the 2026-09-01 revision

The 2026-08-18 draft was written before 1.4 shipped and before two weeks of work
landed. Corrected here:

| Then | Now |
|---|---|
| "1.4 has not shipped" — a hard gate on everything below | 1.4 shipped 2026-08-20. Gate removed |
| Share card is a candidate needing ~1 week | Built and committed, as W7 of a wider summary-screen rebuild |
| Backup: templates undecided | Templates are **in** the archive (`archiveVersion 2`) |
| Two `performanceLabel` consumers disagree | The formatter is unified; only the *meaning* choice is left |
| Custom-exercise analytics: not built | Event exists, but without the properties that were its whole point |
| Part 6 "already in the tree, needs a home" | All three shipped in 1.4. Replaced with what is in the tree now |
| Part 7 lists replace/reorder as design only | Built. So are supersets and the templates redesign, neither of which this doc had heard of |
| "1.5 should be small, visible, and quick to follow" | It is now large and visible. The question flipped from what to add to what to cut |

---

# Part 1 — Carried over from 1.4 (decided, not candidates)

Two items were explicitly deferred to 1.5 on 2026-08-14. These are commitments.
**Neither is done.**

## 1.1 Backup scope — `BodyweightEntry` first · **partly resolved**

[PRE_1.4_CHECKLIST.md §8](PRE_1.4_CHECKLIST.md), with the full audit in
[BACKUP_EXPORT_SCOPING.md](BACKUP_EXPORT_SCOPING.md).

The gap was that "restore replaces workout history only" describes what restore
won't *overwrite*, not what the backup doesn't *contain*. Those two readings
coincide on the device you exported from and diverge completely on a new one,
which is the case where someone actually reaches for a backup.

- [x] **Decide on templates** — decided by building. `WorkoutHistoryArchive` is at
      `currentVersion = 2` and carries a nested `templates` array
      ([ExportServiceProtocol.swift:110](Repster/Core/Services/Protocols/ExportServiceProtocol.swift:110)),
      folders, superset pairings and all
- [ ] **Add `BodyweightEntry` to the archive** — still absent, and still the
      strongest candidate, since `effectiveWeight` for future bodyweight-style sets
      depends on the log
- [ ] **Programs** — still not covered, still not said out loud anywhere
- [ ] **Reword the export screen to describe *contents*.**
      [ExportView.swift:30](Repster/Features/Settings/Views/ExportView.swift:30) still
      reads "workout history, workout metadata, and set details" — which is now
      *understated* (templates ride along, silently) and still silent on the
      bodyweight log. Adding templates without touching the copy made this worse,
      not better

**Superseded note:** the old caveat about backup phases 2 and 4 being uncommitted
is gone — they shipped in 1.4.

## 1.2 Bodyweight-style set labels · **half the problem dissolved**

[PRE_1.4_CHECKLIST.md §9](PRE_1.4_CHECKLIST.md).

The original complaint had two halves: two formatter entry points with different
rules, and neither rule being right.

**The disagreement is gone.** Every overload in
[`WorkoutSetPerformanceFormatter`](Repster/Core/Formatting/WorkoutSetPerformanceFormatter.swift)
now funnels into one `display(weight:reps:…)` core and one
[`weightLabel`](Repster/Core/Formatting/WorkoutSetPerformanceFormatter.swift:408).
Fixing this is now a one-place change rather than a two-place one.

**The meaning is still wrong.** `weightLabel` returns `"BW"` only when
`weight <= 0`. A Pull Up at +10 kg still renders `10 kg`, which reads as a bare
weight.

- [ ] Pick one meaning: `BW+10 kg` or `90 kg`. The current `10 kg` is the one
      option not worth keeping
- [ ] Update `WorkoutJourneyTests.testHistorySubTabShowsPastSessionsNewestFirst`,
      which pins the current behaviour

The "apply to **both** consumers" bullet is retired — there is one consumer now.

---

# Part 2 — The headline: workout summary screen + shareable card · **built, committed 2026-09-02**

**This grew.** The 2026-08-18 draft scoped a share card hanging off the existing
summary sheet. What was actually built rebuilds the sheet itself and makes the card
one of seven work packages:
[SUMMARY_SCREEN_IMPLEMENTATION_PLAN.md](SUMMARY_SCREEN_IMPLEMENTATION_PLAN.md),
W1–W7, built 2026-09-01, app target clean, five new tests passing.

The reasoning that put it in the headline slot still holds: 1.4 was a
privacy-and-measurement release with almost nothing a user can see, and 1.5 should
be the opposite. It is now emphatically the opposite.

**Committed 2026-09-02 as "Give the finished workout a card worth sharing":**

- [`WorkoutShareCard.swift`](Repster/Features/Workout/Views/WorkoutShareCard.swift) — 502
  lines: pure card view, `ImageRenderer`, `WorkoutSharePreviewSheet`, the two privacy
  toggles (`hideWeights` and the exercise list)
- [`WorkoutSummarySheet.swift:168`](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:168) —
  entry point wired
- [`WorkoutShareCardTests.swift`](RepsterTests/WorkoutShareCardTests.swift) — 127 lines
- `RepsterMark.imageset` and the `design/summary-card/` artboards

**Still missing from the original Phase 1 scope:**

- [ ] **Analytics — nothing at all.** There is no share event anywhere in the card
      or the summary sheet. This is the piece that gates Phase 2: the design doc's
      "open rate ≥ 8% before building retroactive sharing" cannot be evaluated
      against a metric that isn't collected
- [ ] **`NSPhotoLibraryAddUsageDescription`** — not in the project. Save-to-photos
      will crash the moment someone taps it
- [ ] **Campaign-tagged App Store link and landing page** — the card prints a URL;
      nothing measures it
- [ ] **Device pass** — never run on hardware

**Open decisions inherited from the implementation plan:** footer lockup vs. brand
bar (built with the lockup — a five-minute change now, a re-render later), push vs.
sheet for Add details, and whether the effort question survives at all.

**Open decision still carried from the design doc:** whether a short domain exists
for the card's face. The GitHub Pages URL works but wastes the impression.

---

# Part 3 — Muscle group coverage · **unchanged, nothing built**

Scoped in **[SECONDARY_MUSCLES_SCOPING.md](SECONDARY_MUSCLES_SCOPING.md)**.

Verified 2026-09-01: no `MuscleAttribution` type exists, and
`Exercise.secondaryMuscles` is still persisted, seeded, exported and read by
nothing user-facing.

| Phase | Contents | Fit |
|---|---|---|
| 1 | Taxonomy rollup, `MuscleAttribution` helper, secondary picker in the exercise editor, display on exercise detail | Good — small, self-contained, no arithmetic |
| 2 | Live coverage overview in the routine editor; muscle summary on the post-workout sheet | The actual feature. Sizeable |
| 3 | Insights panel weighting, chart/list filters, `HealthProfile` toggle | **Defer** |

**What changed underneath it:** Phase 2's two surfaces both got rebuilt without it.
The templates redesign shipped a new editor and detail view; the summary sheet was
just rebuilt. Both are now places a coverage panel can hang off cleanly — but both
were designed without a slot reserved for one. Phase 2 got cheaper to build and
slightly more disruptive to insert.

**Blocking work regardless of phase:** the taxonomy mismatch. 42 of 96 seed
secondary tags (glutes, quads, hamstrings, calves) aren't in the 10-value catalog.
The recommendation is a rollup to `legs`, which is cheap but must happen first.

**Still 4th** in [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md).
That ranking is sound.

---

# Part 4 — Ahead of muscle coverage in the competitive ranking

From [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md) Part 3.

## 4.1 `bilateralLoadFactor` wiring — size S · **not started**

Verified: the field is read and written across the model, services, export,
templates, charts and
[`CreateEditExerciseViewModel`](Repster/Features/Exercise/ViewModels/CreateEditExerciseViewModel.swift) —
and referenced by **no view in the app**. Still exactly the two gaps named in
August: a control in the editor, and one branch in `computeEffectiveWeight`.

Highest demand-to-effort ratio available. Per-dumbbell weight entry was the single
most-repeated concrete complaint in a ~500-comment Hevy thread.

**Blocked on a decision, not on engineering** — see §5.1.

## 4.2 `Exercise.notes` — size S · **not started**

Verified against [Exercise.swift:81–117](Repster/Data/Models/Exercise.swift:81):
there is no `notes` property. It still exists on `WorkoutSet`, `TemplateExercise`,
`Workout` and `WorkoutTemplate` — which is exactly the "I paste the same setup note
into every routine" complaint. Lightweight SwiftData migration.

May want to be the same field as custom-exercise instructions — see §5.3.

## 4.3 Custom-exercise creation analytics — size XS · **built, but not the useful half**

The event exists and fires:
[`exerciseCreated(source:)`](Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift:535),
called from
[CreateEditExerciseViewModel.swift:173](Repster/Features/Exercise/ViewModels/CreateEditExerciseViewModel.swift:173).

**It carries only `source`.** The point of the item was name and equipment type —
turning "our library is too small" from an unbounded content problem into a ranked
list. A count of creations does not do that. What shipped answers "how often", which
was never the question.

- [ ] Add `equipmentType` — no privacy question, do it
- [ ] Decide on the exercise **name**. Under the inverted replay-masking posture
      ([PRE_1.5_CHECKLIST.md §2.3](PRE_1.5_CHECKLIST.md)), user-authored strings are
      the category that gets masked. A free-text exercise name is user-authored.
      This is now a deliberate decision, not a property you add in passing

Still **should go first** among the unbuilt items, because it starts collecting data
that informs later decisions.

---

# Part 5 — Decisions that block scope lock

Unchanged in substance. §5.4 has grown.

## 5.1 Backfill policy for `effectiveWeight` — blocking §4.1

`effectiveWeight` is persisted per set, not computed on read. Turning
`bilateralLoadFactor` on for an exercise with history does not retroactively fix
logged sets, and will produce a visible step change in that exercise's e1RM and
volume charts.

The same question applies to the machine starting-weight offset, so it needs **one
answer applied consistently to both**. Recommendation on file: an explicit, opt-in,
one-time backfill action with clear copy.

## 5.2 Should seeded dumbbell exercises default to `bilateralLoadFactor = 2.0`?

Recommendation on file is to ship the field off by default and let users opt in per
exercise.

## 5.3 One field or two for notes and instructions?

One is simpler; two allows a short cue in the workout versus a longer how-to on the
detail screen. Affects §4.2's shape.

## 5.4 Free vs. RevenueCat entitlement · **now overdue**

Reads as core logging correctness and should probably be free: `bilateralLoadFactor`,
`Exercise.notes`.

**Newly urgent:** supersets, the templates redesign and the share card all shipped
into the tree with no entitlement decision taken. Whatever the answer, it is cheaper
to decide before the release note than after users have had them free for a version.

## 5.5 Is 0.5 the right secondary-muscle credit?

**Not blocking** — Phase 3 only. Recorded so it isn't rediscovered as a surprise.

---

# Part 6 — What is actually in this release

Replaces the old "already in the tree, needs a home" table, whose three rows all
shipped in 1.4.

**Committed on `NewMain` since the 1.4 release:**

| Work | Doc | Landed |
|---|---|---|
| Epoch-2 suggestion engine — RIR floor, one set can't crater the estimate, drop sets don't grade the model, learned-rate reset | [SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md](SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md) | 2026-08-27 |
| Capacity-guard kill switch (`prescriptionCapacityGuardsEnabled`) | same | 2026-08-27 |
| Backup restore hardening — a new enum case can't fail a whole decode | [BACKUP_EXPORT_SCOPING.md](BACKUP_EXPORT_SCOPING.md) | 2026-08-27 |
| Exercise replace in place + reorder, 4 defects fixed | [EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md) | 2026-08-30 |
| Session replay masking **inverted** — legible by default, named values masked | [PRE_1.5_CHECKLIST.md §2.3](PRE_1.5_CHECKLIST.md) | 2026-08-30 |
| Progression exclusion visibility — history chip + workout-detail banner | [PROGRESSION_EXCLUSION_VISIBILITY_SCOPING.md](PROGRESSION_EXCLUSION_VISIBILITY_SCOPING.md) | 2026-08-30 |
| **Supersets** — marked-only, PR1–PR9 + PR11, both prompt directions, partner rest fixed | [SUPERSETS_IMPLEMENTATION_PLAN.md](SUPERSETS_IMPLEMENTATION_PLAN.md) | 2026-08-31 |
| **Templates redesign** — folders, detail view, paired supersets, AI helper deleted, 62 template tests | [TEMPLATES_IMPLEMENTATION_PLAN.md](TEMPLATES_IMPLEMENTATION_PLAN.md) | 2026-09-01 |
| Template data-loss hardening — identity-addressed edits, export survives a dangling exercise | [TEMPLATE_HARDENING_SCOPING.md](TEMPLATE_HARDENING_SCOPING.md) | 2026-09-01 |

**Uncommitted on `NewMain`:**

| Work | Doc | State |
|---|---|---|
| Summary screen rebuild W1–W6 | [SUMMARY_SCREEN_IMPLEMENTATION_PLAN.md](SUMMARY_SCREEN_IMPLEMENTATION_PLAN.md) | Builds clean, no device pass |
| Share card W7 | same + [SHARE_CARD_FEATURE_DESIGN.md](SHARE_CARD_FEATURE_DESIGN.md) | See Part 2 — missing analytics and the Info.plist key |
| Coach artboards, superset and summary-card designs | [REPSTER_COACH_SCOPING.md](REPSTER_COACH_SCOPING.md) | Design only |

**Known open defect riding this release:**
[UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md) — Copy Previous rows never
ticked still count as logged. Live on shipped builds. Not fixed, not scheduled.

---

# Part 7 — Scoped but not proposed for 1.5

Open design docs, listed so they aren't forgotten. None are commitments.

- [REPSTER_COACH_SCOPING.md](REPSTER_COACH_SCOPING.md) — new since this doc was
  written. Collapses Smart Suggestions, Insights and coaching tiles under one name.
  W5 of the summary plan already ships a flag-gated Coach teaser, so a naming
  decision is closer than "scoping" suggests
- [SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md) — 12 of 13 `SetType` cases are labels
  attached to features that were never built
- [DROP_SETS_SCOPING.md](DROP_SETS_SCOPING.md) — partly overtaken: drop sets no
  longer grade the fatigue model as of 2026-08-27. The remaining defects are real
- [SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md) —
  design only
- Workout blocks — interaction design in progress, artifacts only, no doc yet
- [COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md) — parked 2026-08-11
- Machine setup as structured data — strongest differentiator in the competitive
  analysis, but size M and prone to multi-gym scope creep
- Programs UI / forward scheduling — models exist, `Features/Programs/Views/` is empty

**Removed from this list because they were built:** exercise replace & reorder,
supersets, templates redesign.

---

# Suggested shape for 1.5

The August version of this section proposed seven items to add, sized XS to
one week, and called the release "deliberately conservative." That is no longer the
situation. Supersets, a rebuilt templates system, a rebuilt summary screen and a
share card are all in the tree. The release is large and visible whether or not
anything else goes in.

**So the recommendation inverts: add almost nothing, and finish what is there.**

| Priority | Item | Size | Why now |
|---|---|---|---|
| 1 | `NSPhotoLibraryAddUsageDescription` | XS | Save-to-photos crashes without it. Not optional |
| 2 | Share analytics — open and share events | XS | Phase 2's gate is unmeasurable otherwise, and the metric only counts forward |
| 3 | `equipmentType` on `exerciseCreated` | XS | §4.3. Same forward-only argument |
| 4 | Commit and device-pass the summary screen | — | It is the release's face and has never run on hardware |
| 5 | Settle §5.4 entitlements | — | Three shipped features have no answer |
| 6 | Export screen copy | S | §1.1. Templates ride the archive silently today |
| 7 | Bodyweight label meaning | XS | §1.2. Now a one-place change |

**Deferred to 1.6, with no loss:** `bilateralLoadFactor` (§4.1, still blocked on
§5.1), `Exercise.notes` (§4.2), `BodyweightEntry` in the backup (§1.1), muscle
coverage Phase 1 (Part 3).

**Muscle coverage Phase 2 remains the natural 1.6 headline** — and its two surfaces
now exist to hang it on.

## Open question on the release itself

**The split question is settled by circumstance.** Items 1–4 are finishing work on
code that already exists; there is nothing coherent left to split off. What replaces
it is the version number, and it is sharper than a preference:

`WhatsNewRelease.current` matches `CFBundleShortVersionString` by **exact string
equality**, and `WhatsNewRelease.all` holds entries for `"1.4"` and `"1.5"` only.
The project currently reads `1.4.1`. **Shipping as 1.4.1 shows the What's New sheet
to nobody, silently.** For a release containing supersets, a rebuilt templates
system, a new summary screen and an inverted replay-masking posture, that is the
wrong outcome. See [PRE_1.5_CHECKLIST.md §0](PRE_1.5_CHECKLIST.md), which is where
the decision belongs.
