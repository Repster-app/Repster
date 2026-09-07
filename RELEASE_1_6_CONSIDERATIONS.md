# 1.6 Release Considerations

**Written:** 2026-09-06, at 1.5 scope lock.
**What this is:** everything that was on the table for 1.5 and **is not in the
build**. Nothing here is a commitment — it is the list 1.6 planning starts from, so
that "was this dropped or forgotten?" is never a question anyone has to reconstruct
from a diff.

**What this is not:** the 1.5 scope. That is [RELEASE_1_5_PLAN.md](RELEASE_1_5_PLAN.md).
The launch mechanics are [PRE_1.5_CHECKLIST.md](PRE_1.5_CHECKLIST.md).
Why things were *not* done, feature by feature, is [1_5_DECISION_RECORD.md](1_5_DECISION_RECORD.md).

Every item below was verified against the tree on 2026-09-06, not copied forward
from a plan. Where an item was previously described as unbuilt and turned out to be
built, it has been removed from this list and named in §7.

---

## 1. Commitments carried over — now carried twice

These were deferred from 1.4 to 1.5 on 2026-08-14 and did not make 1.5 either.
Deferring the same item a second time is worth doing deliberately.

### 1.1 `BodyweightEntry` is not in the backup archive · **size S**

`WorkoutHistoryArchive` is at `currentVersion = 2` and carries templates, folders and
superset pairings. It carries no bodyweight log — `grep BodyweightEntry` against
[ExportServiceProtocol.swift](Repster/Core/Services/Protocols/ExportServiceProtocol.swift)
returns nothing.

Why it keeps mattering: `effectiveWeight` for bodyweight-style sets is derived from
the log. Restore onto a new device and every Pull Up in the restored history has a
bodyweight basis the file never carried.

The export screen is now honest about this — [ExportView.swift:30](Repster/Features/Settings/Views/ExportView.swift:30)
names bodyweight logs, programs and settings as things the file does not contain —
so 1.5 ships a described gap rather than a silent one. That lowers the urgency; it
does not close it.

### 1.2 Programs are not in the backup archive · **size S, newly sharper**

Same gap, and 1.5 made it worse. Before this release a "program" was a dormant model
nothing constructed. Now onboarding writes a rotation of real `WorkoutTemplate`s into
a folder, so a program is a thing the user chose and can lose.

The templates themselves **do** ride the archive at v2, so the sessions survive a
restore. What does not survive is anything program-level beyond the folder name.
Worth confirming what is actually lost before sizing this — it may already be
adequate.

### 1.3 Bodyweight-style set labels still read as a bare weight · **size XS**

[`weightLabel`](Repster/Core/Formatting/WorkoutSetPerformanceFormatter.swift:408)
returns `"BW"` only when `weight <= 0`. A Pull Up at +10 kg renders `10 kg`, which
reads as a ten-kilo lift.

**The hard half is already done.** Every formatter overload now funnels into one
`display(weight:reps:…)` core and one `weightLabel`, so this is a one-place change —
it was a two-place change when it was deferred from 1.4.

- Pick one meaning: `BW+10 kg` or `90 kg`. The current `10 kg` is the one option not
  worth keeping
- `WorkoutJourneyTests.testHistorySubTabShowsPastSessionsNewestFirst` pins the
  current behaviour and moves with it

---

## 2. Unbuilt features that were proposed for 1.5

### 2.1 `equipmentType` on `exerciseCreated` · **size XS — do this first**

Verified 2026-09-06: [AnalyticsServiceProtocol.swift:569](Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift:569)
still reads `exerciseCreated(source:)` and tracks `source` alone.

The point of the event was to turn "our exercise library is too small" from an
unbounded content problem into a ranked list. A count of creations does not do that.

- `equipmentType` has no privacy question — add it
- The exercise **name** is a separate decision. Under the inverted replay-masking
  posture, user-authored strings are the category that gets masked, and a free-text
  exercise name is user-authored. Decide it deliberately, do not add it in passing

It goes first among the unbuilt items for the same reason it went first in the 1.5
list: the metric only counts forward, so every release it slips is a release of data
that does not exist.

### 2.2 `bilateralLoadFactor` wiring · **size S — blocked on §3.1**

The field is read and written across the model, services, export, templates, charts
and `CreateEditExerciseViewModel`, and referenced by **no view in the app**
(verified 2026-09-06: `grep -l` across `Repster/Features/` returns the view model and
nothing else). Two gaps, unchanged since August: a control in the exercise editor,
and one branch in `computeEffectiveWeight`.

Still the highest demand-to-effort ratio available — per-dumbbell weight entry was
the single most-repeated concrete complaint in a ~500-comment Hevy thread. Still
blocked on a decision rather than on engineering.

### 2.3 `Exercise.notes` · **size S**

Verified: no `notes` property on [Exercise.swift](Repster/Data/Models/Exercise.swift).
It exists on `WorkoutSet`, `TemplateExercise`, `Workout` and `WorkoutTemplate` — which
is exactly the "I paste the same setup note into every routine" complaint.
Lightweight SwiftData migration.

Shape depends on §3.3.

### 2.4 Muscle group coverage · **nothing built**

Scoped in [SECONDARY_MUSCLES_SCOPING.md](SECONDARY_MUSCLES_SCOPING.md). Verified
2026-09-06: no `MuscleAttribution` type exists anywhere in the tree, and
`Exercise.secondaryMuscles` is still persisted, seeded, exported and read by nothing
user-facing.

| Phase | Contents | Fit for 1.6 |
|---|---|---|
| 1 | Taxonomy rollup, `MuscleAttribution` helper, secondary picker in the editor, display on exercise detail | Good — small, self-contained, no arithmetic |
| 2 | Live coverage overview in the routine editor; muscle summary on the post-workout sheet | **The natural 1.6 headline.** Both surfaces now exist |
| 3 | Insights weighting, chart/list filters, `HealthProfile` toggle | Defer again |

**Blocking work regardless of phase:** the taxonomy mismatch. 42 of 96 seed secondary
tags (glutes, quads, hamstrings, calves) are not in the 10-value catalog. The
recommendation is a rollup to `legs` — cheap, but it has to happen first.

**What 1.5 changed underneath it:** Phase 2's two surfaces were both rebuilt this
release — the templates redesign shipped a new editor and detail view, and the summary
sheet was rebuilt around a recap card. Both are now clean places to hang a coverage
panel, and neither reserved a slot for one. Phase 2 got cheaper to build and slightly
more disruptive to insert.

Still 4th in [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md).

### 2.5 Drop sets — Phase 4, the multiplier flatten · **size S**

Phases 1–3 shipped 2026-09-03 ("Make drop sets a real set type you can see
afterwards"). [DROP_SETS_SCOPING.md](DROP_SETS_SCOPING.md) Phase 4 — flattening the
1.4× multiplier — did not, and the drop-set rest-timer question is still open.

This one is now more urgent than its size suggests: 1.5 makes "Drop Set" a real choice
in the picker. Before this release drop sets arrived almost exclusively from
Strong/Hevy import, and the remaining defects were largely invisible. From 1.5 people
will select the type on purpose.

### 2.6 Onboarding redesign — the parts that did not land

The redesign is **substantially built** (see §7). What the scoping doc lists that the
tree does not have should be re-audited against
[ONBOARDING_REDESIGN_SCOPING.md](ONBOARDING_REDESIGN_SCOPING.md) before 1.6 planning —
that document still carries `Status: scoped, not started`, which is no longer true and
makes it an unreliable gap list until it is re-baselined.

---

## 3. Open decisions that block the above

None of these are engineering work. All of them are cheaper to answer now than after
someone has started building against an assumption.

### 3.1 Backfill policy for `effectiveWeight` — blocks §2.2

`effectiveWeight` is persisted per set, not computed on read. Turning
`bilateralLoadFactor` on for an exercise with history does not retroactively fix
logged sets, and produces a visible step change in that exercise's e1RM and volume
charts.

The same question applies to the machine starting-weight offset, so it needs **one
answer applied to both**. Recommendation on file: an explicit, opt-in, one-time
backfill action with clear copy.

### 3.2 Should seeded dumbbell exercises default to `bilateralLoadFactor = 2.0`?

Recommendation on file: ship the field off by default, let users opt in per exercise.

### 3.3 One field or two for notes and instructions? — shapes §2.3

One is simpler. Two allows a short cue in the workout versus a longer how-to on the
detail screen.

### 3.4 Free vs. paid entitlement · **overdue, and now more so**

Reads as core logging correctness and should probably be free: `bilateralLoadFactor`,
`Exercise.notes`.

**The 1.5 problem is bigger than the 1.6 one.** Supersets, the templates redesign, the
share card, the rebuilt summary screen and the onboarding program picker have all
shipped into the tree with no entitlement decision taken. After 1.5 they are free
features users have had for a version, and taking one behind a paywall in 1.6 is a
removal rather than a decision.

If this is to be decided at all, 1.5 is the last cheap moment. It is listed here
because it was not taken; it belongs on the 1.5 checklist, not this document.

### 3.5 Is 0.5 the right secondary-muscle credit?

Not blocking — Phase 3 only. Recorded so it is not rediscovered as a surprise.

### 3.6 App Store screenshots — carried from 1.5 by decision

**Decided 2026-09-06: 1.5 ships with the live 1.3 screenshot set**, unchanged.
Screenshots were ruled a separate piece of work rather than a release gate.

What that leaves for 1.6: the live "start from your saved routines" frame shows a
templates screen the app no longer has, and 1.5 also rebuilt the workout summary. The
v2 set at `marketing/generated/app-store-v2/` is **not** the fix on its own — it
predates the same rebuilds. Whichever set goes up next needs its device art
re-captured against the current app.

### 3.7 Share card — the two open marketing decisions

- **Campaign-tagged App Store link and landing page.** The card prints a URL and
  nothing measures it. Until this exists, the share feature's whole acquisition
  argument is unfalsifiable
- **A short domain for the card's face.** The GitHub Pages URL works and wastes the
  impression

### 3.8 Share card — the three open design decisions

Inherited from [SUMMARY_SCREEN_IMPLEMENTATION_PLAN.md](SUMMARY_SCREEN_IMPLEMENTATION_PLAN.md),
none blocking:

- Footer lockup vs. brand bar — built with the lockup. A five-minute change now, a
  re-render of every artboard later
- Push vs. sheet for Add details
- Whether the effort question survives at all

---

## 4. Defects 1.5 ships with

Listed so that shipping them a third time is a choice. None are regressions; all are
live on 1.4 today. Full list and reasoning in [PRE_1.5_CHECKLIST.md §5](PRE_1.5_CHECKLIST.md).

| Defect | Doc | Note |
|---|---|---|
| Unperformed sets count as logged — Copy Previous rows never ticked | [UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md) | Scoped, unimplemented. Data defect, not cosmetic |
| Fixed rep targets cannot progress at all | [SUGGESTION_PROGRESSION_DESIGN.md](SUGGESTION_PROGRESSION_DESIGN.md) | Untouched by the epoch-2 work |
| Rest timer is silent under any Focus mode | [REST_TIMER_ALARM_SCOPING.md](REST_TIMER_ALARM_SCOPING.md) | Needs a `.timeSensitive` entitlement the App ID does not have — see §5 |
| CSV import creates parallel exercise records | — | Import matches on exact name only, so an imported "Bench Press" never joins the seeded one. Likely cause of "imported exercises never count" |
| Fatigue model never measures real rest | — | `restDuration` is nil unless the timer runs to zero, so a rushed set silently assumes full recovery |
| Template set collapse | [TEMPLATE_SET_COLLAPSE_HANDOVER.md](TEMPLATE_SET_COLLAPSE_HANDOVER.md) | Half solved. The Unknown Exercise row is fixed; the set distribution is still unexplained |
| Prewarm launches hit the `ModelContainer` fatalError | [1_5_DECISION_RECORD.md](1_5_DECISION_RECORD.md) | Both 1.4 Organizer crashes. One device, no observed user impact |

---

## 5. Blocked on Apple, not on us

- **Rest timer under Focus.** `.timeSensitive` interruption level requires the
  Time Sensitive Notifications entitlement, which requires App ID capability work.
  The silence bugs D1–D6 were fixed 2026-08-18; this case was not, and cannot be from
  the app side alone
- **HealthKit device QA.** Write-on-finish shipped 2026-08-09 and the App ID
  capability plus a real-device pass are still outstanding

---

## 6. Scoped, not proposed for anything yet

Open design docs, listed so they are not forgotten. None are commitments.

- [REPSTER_COACH_SCOPING.md](REPSTER_COACH_SCOPING.md) — collapses Smart Suggestions,
  Insights and coaching tiles under one name. 1.5 ships a flag-gated Coach teaser on
  the summary screen, so the naming decision is closer than "scoping" suggests
- [COACH_ANALYSIS_SCOPING.md](COACH_ANALYSIS_SCOPING.md) — written 2026-09-06, the
  menu of what could sit behind the teaser's tap. Scoping only, nothing agreed.
  **The "Analyse with Coach" teaser was switched off for 1.5** —
  `CoachPreferences.showsSummaryTeaser` now defaults to `false`, and
  `testCoachTeaserDefaultsOffAndCanBeTurnedOn` pins it. The flag still turns it on, so
  the release Coach actually lands in flips one word
- [SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md) — 12 of 13 `SetType` cases are labels
  attached to features that were never built. Partly superseded by the drop-set work
- [SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md) — design only
- [COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md) — parked 2026-08-11
- Workout blocks — interaction design in progress, artifacts only, no doc
- Machine setup as structured data — strongest differentiator in the competitive
  analysis, size M, prone to multi-gym scope creep
- Programs UI and forward scheduling — the models exist and stay dormant by decision;
  `Features/Programs/Views/` now holds `ProgramPickerView` and nothing else
- Supersets on the Live Activity — the one line of the superset scope not built, and
  it is an open question rather than pending work

---

## 7. Removed from this list because they were built

Recorded so nobody re-adds them from an older plan. All verified in the tree
2026-09-06.

| Previously listed as unbuilt | Actually |
|---|---|
| `NSPhotoLibraryAddUsageDescription` missing | Present in [Info.plist](Repster/Info.plist), with copy |
| Share card analytics | All four events wired 2026-09-05, plus the `Share Card` screen |
| Export screen describes restore, not contents | Rewritten 2026-09-05; three false "templates are untouched" strings fixed with it |
| Exercise **replace** still open | Built — `Replace Exercise…` in the tab strip context menu, with confirmation |
| Exercise reorder sheet deferred | Built 2026-09-06, uncommitted |
| Onboarding redesign not started | Program picker, seed catalogue, `ProgramCatalogService`, Extras step and welcome copy all built |
| Apple Health lives in onboarding | Moved — the offer now fires after the first completed workout |
