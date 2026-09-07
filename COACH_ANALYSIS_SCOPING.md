# Coach analysis — idea scoping

**Date:** 2026-09-06 · **Branch:** `NewMain` · **Status:** scoping only. Nothing here is built or agreed.

The `Analyse with Coach` teaser now ships on the summary sheet
([WorkoutSummarySheet.swift:842](Repster/Features/Workout/Views/WorkoutSummarySheet.swift#L842)),
non-interactive, behind `CoachPreferences.showsSummaryTeaser`. This doc is the menu of what could
sit behind that tap.

It deliberately does **not** narrow to the ten sketches in
`html prototype/prototype-coaching-tiles.html`. Those are eight coaching tiles plus two model-
transparency tiles, all framed as a *feed*. That is one shape out of about ten, and the shape
question is bigger than the tile list.

**Related:** [REPSTER_COACH_SCOPING.md](REPSTER_COACH_SCOPING.md) (§5.3 Review, §5.4 tiles) ·
[COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md) ·
[TRAINING_INSIGHTS_V2_DESIGN.md](TRAINING_INSIGHTS_V2_DESIGN.md) ·
[SUMMARY_SCREEN_IMPLEMENTATION_PLAN.md](SUMMARY_SCREEN_IMPLEMENTATION_PLAN.md) §W5

---

## 0. Two corrections to the existing scoping

Both were checked against the code today and both open work that the earlier docs marked blocked.

**1. The movement-pattern taxonomy exists and is seeded.** REPSTER_COACH §5.4 marks T7 (push:pull)
as needing "a movement-pattern taxonomy that does not exist on `Exercise`." It does:
[MovementPattern.swift](Repster/Data/Enums/MovementPattern.swift) has seven cases and
`Exercise.movementPattern` is populated from
[seed_exercises.json](Repster/Resources/seed_exercises.json) for all 69 seeded exercises —
20 pull, 14 press, 8 squat, 6 hinge, 1 carry, **20 `other`**. So pattern analysis is a query, not a
schema project. What remains is the 29% `other` bucket, `nil` on user-created exercises, and the
stance question — which was always the real blocker.

**2. Per-set completion timestamps are already written and nothing reads them.**
`SetRepository` stamps `completedAt` when a row is ticked
([SetRepository.swift:124](Repster/Core/Repositories/SetRepository.swift#L124)). Consecutive
deltas give **actual inter-set gaps for every user**, with no timer and no wand. That is a
different measurement from `restDurationSeconds`, which is nil unless the timer runs to zero and is
the subject of the rest-duration blind spot. It comes with three real caveats — see §2, seam 2.

`WorkoutSet.startedAt` exists on the model but **is never written by the app** (only by import).
Populating it on first keystroke is an XS change that turns every timing idea below from a proxy
into a measurement.

---

## 1. The shape question — decide this before any feature list

The teaser makes a promise in five words: **"What changed, and what's next."** That is a spine, and
it rules out about half of what a "workout analysis" screen usually is. It is retrospective *and*
forward, it is comparative, and it is not a stat dump — the sheet above it already does stats.

Ten candidate shapes. They are not mutually exclusive but they have very different centres of
gravity, and the choice decides the data model, the copy register and the build size.

| # | Shape | The idea | Why it might win | Why it might not |
|---|---|---|---|---|
| **S1** | **Tile feed** | Cards, like Insights, scoped to this session | Reuses `InsightCardView`, `InsightRule`, curation, everything | A feed about *one session* is thin. Session 40 reads like session 39, and the repetition is the failure mode |
| **S2** | **The debrief** | 4–6 sentences in a fixed order: what happened → what changed → what it means → what's next | Reads like a coach. Fixed skeleton means it is comparable session to session and cheap to scan | Prose is hard to get right 200 different ways, and hardest exactly when there is little to say |
| **S3** | **The diff** | Everything framed against the last comparable session. Deltas, not values | Serves "what changed" literally. Always has content after session two | Needs a definition of "comparable", which is a real problem (§4, B1) |
| **S4** | **Session replay** | The workout on a vertical time axis — sets, e1RM trace, rest gaps, where it turned | Genuinely novel. Nothing in the app is temporal *within* a session. Very screenshot-able | Depends on seam 2 timestamps and their caveats. Beautiful and possibly not actionable |
| **S5** | **The ledger entry** | What the coach expected, what happened, what it now believes | The most honest thing the app can show, and it is S3 substrate the whole Coach needs | Wand-only. Blank for the users with least data — the coverage rule in REPSTER_COACH §6 forbids it as a headline |
| **S6** | **The one question** | The screen leads with a single question that makes the coach better: *"Was that a deliberate light day?"* | This is T9 wearing a different hat. It is how intent gets acquired without a questionnaire | Asking before giving reads as work. Probably a component, not the shape |
| **S7** | **Forward brief** | 80% about next time. "Next chest day: bench 65×5, and squat goes first" | The half of the promise nobody else keeps. Most useful thing a coach does | Needs the write path (S4 in REPSTER_COACH) and progression, which is Wave 6 |
| **S8** | **Scorecard** | Grades per lift, per session | Immediately legible; people like scores | Violates the §5.3 tone rule outright. **Include only as the model-scored variant** — grade the prediction, never the lifter |
| **S9** | **Dossier / progressive disclosure** | One headline → three things → everything | Solves the tired-user problem and the enthusiast problem with one screen | Two designs in a trench coat unless the layering is disciplined |
| **S10** | **Ask-anything** | Tap-to-ask prompts with precomputed answers | Feels like a coach; no LLM required if the question set is fixed | Question set has to be short and always answerable, or it is a dead end |

**The combination worth arguing for first:** S9 as the container, S2 as the register, S3 as the
spine, closing on S7. One headline sentence, an expandable body of three to five findings, each one
comparative, and a forward line at the bottom. S5 folds in as a section for wand users only. S4 is
the strongest single *bet* in the list and could be the thing people screenshot — but it is a
second release, not the first.

---

## 2. Data seams — what is actually there

Twelve seams. Coverage marks follow REPSTER_COACH §5: **All** = computes from `WorkoutSet` for
every user; **Wand** = needs `FatigueObservation` / audits.

| # | Seam | Coverage | State | Notes |
|---|---|---|---|---|
| 1 | **This session's sets** | All | Used | `weight`, `effectiveWeight`, `reps`, `rir`, `e1RM`, `orderInWorkout`, `orderInExercise` |
| 2 | **Set completion times** | All | **Unexploited** | `completedAt` per row. Three caveats below |
| 3 | **Unilateral left/right** | All | **Unexploited** | `leftReps`/`rightReps`/`leftRIR`/`rightRIR` — read by export and `SetService` only. Nothing analyses them |
| 4 | **Set types** | All | **Unexploited** | 14 cases in [SetType.swift](Repster/Data/Enums/SetType.swift). Drop sets shipped 2026-09-03; nothing reports on them |
| 5 | **Supersets** | All | **Unexploited** | `supersetGroupId`. Built 2026-08-31; no analysis reads it |
| 6 | **Row targets** | All | Partly | `targetWeight`, `targetRepMin/Max`, `targetRIR` — adherence **without** the wand, for template users |
| 7 | **The fatigue model** | Wand | Used | `FatigueObservation`, `FatigueLearningSetAudit`, `diagnosticsExercises()`, `recentSessionSummaries()`, `suggestionAdherence()` |
| 8 | **PRs** | All | Used | `PerformanceRecord`, `prStatus` cached per set |
| 9 | **History & cadence** | All | Used | Workout dates × `primaryMuscle` × `movementPattern` |
| 10 | **Body & effort** | All | Partly | `perceivedEffort` (one reader), bodyweight, HealthKit energy |
| 11 | **Exclusion flags** | All | Used | `excludeFromPRs`, workout-level progression exclusion. Distorts everything silently |
| 12 | **Notes** | All | Unusable | Free text. No structure, no parsing. See F13 |

**Seam 2's three caveats, because several ideas below live or die on them:**

1. `startedAt` is never written, so a gap between two `completedAt` values is *rest + the set itself*,
   not rest. Fine for pacing, wrong if labelled "rest".
2. [EditWorkoutViewModel.swift:132](Repster/Features/Workout/ViewModels/EditWorkoutViewModel.swift#L132)
   stamps `completedAt = Date()` when a set is edited later, so retroactively edited sessions carry
   timestamps from the edit, not the gym. Any timing feature needs a sanity gate.
3. Rows created by Copy Previous and never ticked have no timestamp at all — and per the open
   unperformed-sets defect they still count as logged. Timing analysis will surface that bug, which
   is an argument for fixing it first, not for avoiding the feature.

---

## 3. Catalog A — what happened in this session

Everything here computes from the session alone. **Coverage: All.** These are the only ideas that
are guaranteed non-empty on a user's first ever workout.

| ID | Concept | The line it produces | Size | Notes |
|---|---|---|---|---|
| **A1** | **Session shape** | e1RM trace across the whole session, in order | S | The single best visual candidate. Needs no history |
| **A2** | **Order cost** | "Squat went fourth today and cost the most" | S | T1 from the tiles doc, scoped to one session |
| **A3** | **The turn** | "Output held for nine sets, then dropped 8% on the last three" | M | Change-point detection on A1. The most coach-sounding sentence in the catalog |
| **A4** | **Density & pacing** | "Median gap 2:10 — 40 seconds shorter than your usual" | S | Seam 2. New capability, real caveats |
| **A5** | **Time budget** | "68 minutes; your usual for this session is 54" | XS | Free, and pairs with A4 to explain *why* |
| **A6** | **Warm-up ramp** | "Three warm-ups, top one at 78% of your working weight" | S | Seam 4. Nobody analyses warm-ups; they are a third of many sessions |
| **A7** | **Effort curve** | "RIR went 3 → 3 → 1 → 0. You emptied the tank on the last two" | S | Needs RIR logged; degrade gracefully when absent |
| **A8** | **Target adherence** | "You hit the prescribed reps on 9 of 11 sets" | S | Seam 6 — works for template users with no wand. Distinct from `TargetAdherenceInsightRule` |
| **A9** | **Left/right asymmetry** | "Right side did 2 more reps on both unilateral lifts" | M | Seam 3. Genuinely differentiated. **Stance care: no injury or imbalance-is-bad framing** |
| **A10** | **Superset cost** | "Paired with rows, your press did 1 rep fewer than solo" | M | Seam 5. Answers the question supersets raise and cannot currently answer |
| **A11** | **Drop set yield** | "The drop added 14 reps and 320 kg of volume past failure" | S | Seam 4. Drop sets shipped with no reporting at all |
| **A12** | **Technique mix** | "Two drop sets, one AMRAP, the rest straight" | XS | Cheap session fingerprint; feeds F1 |
| **A13** | **Unfinished business** | "Three rows were added and never performed" | S | Depends on the unperformed-sets fix landing first |
| **A14** | **Rest discipline** | Timer-run vs actual gaps | S | Seams 2+6. Pairs with `restSweetSpot`, which already ships |
| **A15** | **Session muscle spread** | Sets per muscle group, this session | XS | Existing muscle colours; visual, no claim |
| **A16** | **The heaviest thing you did** | Top set, in context of your own history | XS | The one line that always works, even at session one |

---

## 4. Catalog B — this session against your history

**Coverage: All**, but each needs history, so each needs a cold-start answer.

| ID | Concept | The line | Size | Notes |
|---|---|---|---|---|
| **B1** | **The diff** | "Same session as 8 days ago: bench +2.5 kg, squat flat, one more set overall" | M | The spine of shape S3. **Needs a definition of "comparable session"** — see below |
| **B2** | **Near misses** | "One rep short of a rep PR on set 3" | S | Near-misses are more motivating than PRs and the app has never shown one |
| **B3** | **Rep-range drift** | "You have moved from 8–10 to 5–6 on bench over five sessions" | S | Descriptive only; T4's safe half |
| **B4** | **Jump size** | "That was a 5 kg jump; your usual step on this lift is 2.5" | XS | Cheap, and quietly educational |
| **B5** | **Recency** | "First legs session in 16 days; your usual gap is 5" | XS | P1 from REPSTER_COACH, session-scoped |
| **B6** | **Where this ranks** | "Third best bench session you have logged" | S | Percentile against your own sessions. No doctrine, and it feels good |
| **B7** | **The arc** | Last 5 sessions of each lift in this workout, sparkline | S | The chart the exercise detail already almost has |
| **B8** | **Volume vs median** | "22% more volume than your median chest day" | XS | Careful: volume is the metric that most rewards junk sets |
| **B9** | **New territory** | "First time you have logged incline press" | XS | Great cold-start filler and a natural probe-mode hook |
| **B10** | **The quiet PRs** | Rep PRs, volume PRs, e1RM PRs — not just 1RM | S | `PerformanceRecord.recordType` already carries kinds most users never see |

**On B1, the one that needs deciding.** "Same session as last time" needs a comparability rule.
Candidates: same template id · same exercise set (Jaccard over exercise ids) · same primary muscle ·
the last session containing this session's *heaviest* lift. Template id is cleanest and gets
better as the templates redesign lands, but it is nil for freestyle sessions — which are common.
A fallback of "most recent session sharing ≥60% of exercises" covers those. **This rule is
load-bearing for the whole S3 shape and should be settled before anything is built on it.**

---

## 5. Catalog C — the model's account of itself

**Coverage: Wand.** Per REPSTER_COACH §6 none of these may be a headline surface, but the analysis
screen is a tap down from the summary, which arguably makes it a fair home for a *section*.

| ID | Concept | Notes |
|---|---|---|
| **C1** | **Expected vs actual, per lift** | Mostly built — `diagnosticsExercises()` and `recentSessionSummaries()` roll it up today. The work is language ([FatigueLearningService.swift:545](Repster/Core/Services/FatigueLearningService.swift#L545)) |
| **C2** | **What the model changed** | "Bench's fatigue rate moved from 2.4% to 2.1% because of today." The single most coach-like thing in the app: it is the coach *learning in front of you* |
| **C3** | **Adherence** | `suggestionAdherence(workoutId:)` exists ([:378](Repster/Core/Services/FatigueLearningService.swift#L378)) and is unreleased. Took it / went heavier / went lighter |
| **C4** | **Confidence movement** | "Six sessions in — the app is now within 3% on this lift" |
| **C5** | **Where it stayed quiet** | `FatigueLearningSetAudit.suggestionUnavailableReason` already records *why* a set got no suggestion. Surfacing that is honest and it discharges part of the undisclosed-cap debt |

The §5.3 tone rule governs all five: **the subject of the sentence is the model, not the lifter.**

---

## 6. Catalog D — forward

The half of the promise the teaser makes that nothing in the app currently keeps.

| ID | Concept | Notes | Blocked by |
|---|---|---|---|
| **D1** | **What changed for next time** | "Bench goes to 65 next session" — the loads that moved *because of today* | Nothing. Read-only version is free |
| **D2** | **Next session's order** | "Put squat first next time" | Nothing (A2 is the input) |
| **D3** | **What to train next** | "Legs is freshest" | Nothing |
| **D4** | **The single next step** | One sentence, one action, no menu | Copy discipline, not code |
| **D5** | **Load it into next session** | Deep link that creates the session with these numbers | Write path (REPSTER_COACH S4) + template surface P0 |
| **D6** | **Recovery window** | "This much legs volume usually takes you 4 days" | **Stance.** Sits closest to the medical line — descriptive-only or not at all |
| **D7** | **Counterfactual** | "Squat first would likely have been ~4% heavier" | Fatigue model + a modelling decision. A bet, not a v1 |

---

## 7. Catalog E — bets and concepts, not tiles

This is the section the prototype does not cover. Some of these are better than anything above.

**E1 · The session's name.** Cluster the session's own numbers into an archetype and name it —
*heavy and short*, *high-volume push*, *technique day*. Free from A12+A15. It gives every session an
identity, makes history browsable, and makes the B1 comparability rule easier to explain.

**E2 · The coach's memory.** Last time, the app said X. Here is what happened. This is the S3 ledger
in REPSTER_COACH, and it is what separates a coach from a fact generator — the doc's own phrase.
Also fixes the findings-history gap where records vanish when they stop holding.

**E3 · Explain any number.** Long-press any figure anywhere in the analysis for its provenance:
inputs, window, formula version, how confident. Extends "Why this weight" from the wand to the
whole app, and it is the strongest possible answer to the technical positioning the marketing test
is already selling.

**E4 · Sufficiency on the face of it.** "Based on 6 sessions" printed next to every claim, always.
Turns the cold-start problem from an embarrassment into a visible mechanic, and pre-empts the
"so why trust it" reaction that the model-check tile invites.

**E5 · Nothing to report, designed.** A first-class state that says *today was ordinary and here is
the one number that proves it*. Most sessions are unremarkable and a coach that manufactures a
finding every time is a coach nobody believes by week three.

**E6 · What the app got wrong today.** An explicit self-critique block. Counter-intuitive, and it is
the highest-trust move available — especially while E1–E5 of the engine bill are outstanding.

**E7 · The analysis is the share card's source.** REPSTER_COACH R5 already says this. "Third best
bench session you have logged" travels; "12,400 kg" does not.

**E8 · Session tags.** Replace or augment free-text notes with a small structured vocabulary
(*travel*, *tired*, *rushed*, *deload*, *back after illness*). Cheap, and it is the only realistic
route to explaining outlier sessions — the thing every purely numerical analysis gets wrong.

**E9 · The analysis has a memory of you, not just your numbers.** One or two confirmed facts from
T9-style inference, shown at the top: *"3 days a week, mostly 8–12 reps, goal: strength."* Editable
in one tap. Every *Intent*-stance idea in this doc is downstream of it.

**E10 · A monthly analysis, not just a session one.** The same machinery, wider window, once a
month. Higher signal, lower repetition risk, and it is the natural home for everything in D.

**E11 · Cohort norms.** "Most lifters your training age progress bench 2–3 kg a month." **Almost
certainly out** — no backend, and it edges into the social/comparison territory that is a settled
no. Recorded so it is rejected deliberately rather than repeatedly re-proposed.

**E12 · A written narrative from a language model.** The one genuinely forking decision in this
document, so it gets stated plainly: everything above is deterministic, local, offline and free to
run. An LLM layer would write better prose and handle the long tail of odd sessions — at the cost
of a backend the app does not have, per-session inference cost, latency at exactly the moment the
user wants to leave, an offline hole in a gym basement, a new privacy posture for training data,
and non-reproducible output that cannot be unit tested. **Recommendation: build the deterministic
version first regardless.** It is the substrate either way, and a fixed-skeleton debrief (S2) is
most of the perceived value at none of the cost.

---

## 8. Mechanics — the questions that are not about content

**8.1 The workout is not saved when the teaser is tapped.** The teaser sits above `Save & Close`
on a sheet whose workout is still `.inProgress`. So either the analysis computes from live models,
or the tap saves first and then navigates, or the entry point moves to after the save. This is a
flow decision, not a detail, and it should be made before any analysis code is written.

**8.2 It must be re-openable.** REPSTER_COACH R1 already names workout history detail as the
primary home. If the analysis only exists in the eight seconds after Finish, it is not a feature —
it is an animation. Build it as an object attached to the workout, entered from at least two places.

**8.3 Does it persist, or recompute?** Recomputing is simpler and always current. Persisting is what
makes E2 (the coach's memory) and the S3 ledger possible, and what stops last March's analysis
silently rewriting itself when the model changes. They are different products.

**8.4 Cold start.** Session one has no history, no model and possibly no RIR. The catalog above is
sorted so that A1, A5, A12, A15, A16, B9 all work on day one. State what you *are* showing, never
what you cannot — Insights v2 §8 already has this rule.

**8.5 Free or paid.** The analysis is the most natural paywall boundary the app has. It is also the
one moment the coach has the user's attention and has to be credible. A defensible split: the
session-level analysis free, the depth (E10 monthly, E3 provenance, C-series model transparency)
paid. Deciding this late will distort the design; deciding it early risks building for the paywall.

**8.6 Cost at finish.** This runs at the tail of a session, on the main thread's watch, for a user
who wants to leave. Budget it, and precompute what can be precomputed while the workout is live.

**8.7 Repetition is the real failure mode.** Not blankness — the tiles doc already solved blankness
with curation. The risk here is that session 40's analysis reads exactly like session 39's. That
needs an explicit novelty rule: what was shown last time, what is allowed to repeat, how often, and
what earns a headline slot.

**8.8 Copy spelling.** The shipped teaser uses British "Analyse"
([:849](Repster/Features/Workout/Views/WorkoutSummarySheet.swift#L849)); the App Store listing and
the rest of the marketing copy should be checked to match, in one direction or the other.

---

## 9. What would make this bad

- **A grade.** The tone rule in REPSTER_COACH §5.3 is the whole ballgame and every idea above can be
  written in a way that violates it.
- **Diagnosing the user for the app's own defects.** "Your bench is stalled" while the wand is what
  is holding it flat. This applies to B3, B6 and every stalling idea, not only T2.
- **False precision.** "You will hit 200 kg on 14 October." Short windows and visible hedges.
- **Doctrine.** Naming the user's own pattern is safe; asserting what good training is, is not.
- **Medical adjacency.** A9 (asymmetry) and D6 (recovery) are the two that need watching.
- **Tuning it on one lifter's data.** Everything with a threshold in it — the change-point in A3,
  the "usual gap" in A4, the drift window in B3 — will be tempting to tune against a single backup.
  Repster has 200+ users.

---

## 10. Open decisions

1. **Which shape** (§1). Everything else is downstream.
2. **The comparability rule for B1** (§4) — the definition of "the same session as last time".
3. **Saved or unsaved at tap time** (§8.1), and where else the analysis is entered from.
4. **Persisted or recomputed** (§8.3) — decides whether the coach can have a memory.
5. **Free or paid** (§8.5).
6. **Is the model-transparency section (C) in v1**, given it is blank for non-wand users?
7. **Does the app take a stance** at all in this surface, or stay purely descriptive?
8. **LLM or deterministic** (E12) — and whether that is even a question this year.
9. **Novelty rule** (§8.7) — what stops session 40 reading like session 39.

## 11. If it were one release

Not a recommendation, a starting point to argue with: S9 container, S2 register, and the six
findings that need no history, no wand and no engine work — **A1, A5, A16, B1, B5, D1** — with E4
(sufficiency) visible on every one of them and E5 (nothing to report) designed rather than
discovered. That is a screen that works on session one, works for every user, keeps both halves of
the promise the teaser already made, and commits to none of the open decisions above.
