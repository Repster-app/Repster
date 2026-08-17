# Competitive feature analysis — Hevy feature-request megathread

**Source:** r/Hevy "Feature Request Megathread," posted by a Hevy cofounder. 167 upvotes, ~503 comments; this analysis covers ~150 of them, spanning roughly one year of replies through mid-August 2026.
**Date:** 2026-08-16
**Status:** analysis + recommendations. Nothing built.

Comment scores were not available, so demand is ranked by **number of distinct people raising an item**, plus the visible reply-count on top-level comments as an engagement proxy. Reply counts are noted where they were high.

Everything in Part 2 was verified by reading the Repster source on `NewMain`, not assumed. File paths and line numbers are accurate as of this date.

**Scope exclusion:** social features (DMs, feed filtering, follower management, profile sharing, member search, friend comparison) were a substantial cluster in the thread and are **deliberately omitted throughout**. They are not on Repster's roadmap and are not being considered. They are not mentioned again in this document.

---

# Part 1 — What Hevy users are asking for

## Tier 1 — the loudest clusters

| # | Cluster | Signal |
|---|---------|--------|
| 1 | Dumbbell / unilateral weight logging | ~18 people; top comment drew 15 replies |
| 2 | Machine identity & setup persistence | ~16 people; "gym metadata" comment drew 9 replies |
| 3 | Persistent per-exercise notes | ~16 people; top comment drew 13 replies |
| 4 | Programming / progressive overload / periodization | ~15 people; drew 14 replies — highest in the thread |
| 5 | Stats & graph fixes | ~30 discrete asks, fragmented across many commenters |

### 1. Dumbbell / unilateral weight logging

The most-repeated concrete complaint in the thread. Users want a per-exercise toggle to log the weight *per dumbbell* and have the app double it for volume math. One commenter called it "the one confusingly dumb thing about an otherwise 10/10 app," noting their volume swings session to session purely on whether they benched with dumbbells or a barbell.

Extends to unilateral work:
- Mark a set as single-side so it counts once per side instead of appearing as double the sets
- Denote side per set (1L, 2R, 3L)
- Cable machines showing weight per cable, requiring mental doubling
- Dumbbell-to-barbell weight translation

### 2. Machine identity & setup persistence

The underlying frustration: "Lat Pulldown" means different things at different gyms, and the app treats them as one exercise.

- Settable starting/empty weight for plate-loaded machines (one user's leg press starts at 136 lb)
- Machine settings as **structured data** — seat height, chest-support notch, pin position. Users explicitly say the free-text note field does not count, because it is not persistent
- A "gym" tag so previous-workout values don't bleed across locations
- Ability to reset PRs after switching gyms without deleting history
- Exclude a session from stats (travel/hotel gym)
- Pulley/block ratio per exercise (2:1, 4:1) with a toggle between raw and normalized weights in stats
- Manufacturer-specific machine variants in the library

### 3. Persistent per-exercise notes

Notes tied to the **exercise globally**, not to an exercise-within-a-routine. Several commenters name Strong as the app that gets this right, and one says they currently paste their notes into every new routine by hand.

Sub-asks: notes survive exercise replacement, notes visible on the watch, multiple pinned notes, a note that resurfaces next session as a cue.

### 4. Programming / progressive overload / periodization

Users want the app to tell them what to lift, not just record what they lifted.

- Automatic weight progression suggestions
- %-of-1RM programming (5/3/1, GZCLP) — one user says they switch to Liftosaur for this
- Training max as a settable concept
- Mesocycle planning with deload weeks and progress-vs-goal tracking
- Automated periodization: detect 6–8 weeks of consistent training, recommend a deload at ~70%
- RPE targets driving progression suggestions
- "Show me the target for overload" instead of "here's what you did last time"

### 5. Stats & graph fixes

The single most-cited item in the whole thread: **linear time scaling on graphs.** One commenter called it "one of the easiest to program and most requested features"; a second independently described the exact symptom — a 6-month gap in an exercise renders as one flat step, making it look like they got massively stronger between consecutive workouts.

Others:
- Show weight × reps behind a selected e1RM point, so you don't have to dig into the workout
- 5RM / 3RM / 1RM trend lines
- Disclose which 1RM formula is used, and let users choose
- Volume per muscle group, not just set count
- Weekly summaries, not just monthly; 7-day and 30-day chart scaling
- Sort muscle distribution by set count rather than alphabetically
- Exclude warm-ups and dropsets from volume and set counts
- Total volume across all sets counting as a PR, not just a single-set increase
- Migrate historical progress from one exercise to another

## Tier 2 — strong, well-defined clusters

**Heart rate and wearables (~17).** HR straps and Bluetooth/ANT+ monitors, Whoop, Polar, Oura, AirPods Pro 3, Fitbit. HR capture on Android (currently Apple Watch only). Read *from* Android Health Connect rather than only writing to it. HRV and sleep data shown alongside training data.

**Garmin specifically (~8).** Its own cluster, emphatic and repeated; one user would pay extra for it. A Hevy staffer posted roughly a month ago recruiting testers for a Connect IQ proof of concept, so this appears to be in flight.

**Rest timers (~15).** Separate timers for warm-up vs working sets (named as a Strong feature people miss). Rest between *exercises*, not just between sets. A 3-second countdown before a timed hold starts, so you can get into position. Haptics on the watch during timed exercises. Tabata/interval support. Timer changes persisting into the routine.

**Exercise swapping and alternates (~11).** Pre-configured alternates you can swipe to when a machine is busy or broken, carrying reps/sets/notes across the swap. The best-framed version: link variants like an Amazon product page, with "equipment" and "variant" toggles under a single base exercise, so Bench Press flips between barbell/dumbbell/cable and flat/incline/decline.

**Bigger exercise library (~17).** Cables, kettlebells, resistance bands, rings/TRX, sandbags, battle ropes, manufacturer-specific machines. One notably smart suggestion: mine the custom exercises users create and let that data prioritize what gets added next.

**Watch app quality (~14).** Apple Watch — lock the digital crown against false input mid-set, numeric entry instead of scrolling to 40 kg, search when replacing an exercise instead of scrolling the whole library, 2.5 kg crown increments. Wear OS — bigger text, upcoming sets visible during rest, weight increments matching the dumbbells the gym actually has, a pause button.

**Custom exercise parity (~12).** Instructions, multiple photos, video, ability to pick from existing exercise graphics, ability to duplicate a built-in exercise as a starting point, ability to change tracking type (reps → time) after creation.

**Import / export / API (~11).** CSV routine import for people who program in spreadsheets, richer API export including muscle groups, ability to write HR to workouts via API, import from Strava/Apple Fitness/Trainerize/Runna.

## Tier 3 — smaller but coherent

**Set-level editing (~8).** Insert a warm-up set *above* existing sets rather than only appending — described as "insert above, like Excel." Copy set 1's weight and reps to all remaining sets in one action.

**Advanced set types (~16).** Myoreps and myorep matching, auto-calculated dropsets, partials / half-reps, a "Deload" set label distinct from Normal and Warm Up, EMOM support (one user logs 90 rows for a 30-minute EMOM), time under tension, reusable superset blocks saved to a library, supersets across close muscle groups (currently blocked), 1a/1b paired superset rows with a single shared rest timer.

**Routine management (~13).** Sub-folders. Save-as-new-routine instead of overwrite. Merge two routines. A confirmation step before "Update routine." Shared master routines that stay in sync between training partners. Default rep ranges per routine and per exercise.

**Calendar (~5).** Schedule *future* workouts — the calendar is history-only, which drew a direct "whyyyyy." Color-code routines so you can see your split at a glance.

**AI — genuinely contested.** Roughly 7 people want it (photograph a machine to identify the exercise, AI progression recommendations, better GPT integration). Two push back hard: one explicitly says they would cancel if AI landed in the base subscription, another praises Hevy specifically for *not* pivoting to LLM features. Not a consensus ask.

**Roadmap transparency (6).** A changelog, a public roadmap, and the ability to +1 an existing request instead of filing duplicates. One comment is pointed: the cofounder opened the thread and then went quiet, and a later commenter asks directly whether it is still monitored. This is a goodwill signal independent of any feature.

## Two regressions worth noting

Useful as competitive intel, and as a warning about removing things:

- An update replaced type-in entry for timed exercises with a scroll widget. Users want the old behaviour back, calling it quicker and more precise.
- The muscle-distribution visual and the estimated routine time were both removed and are being asked for by name.

---

# Part 2 — Repster crossover

## 2.1 Already shipped — validation, and marketing material

Repster already answers a meaningful share of Tier 1 and Tier 2:

| Hevy request | Repster today |
|---|---|
| Separate warm-up vs working rest timers | `defaultWarmupRestTimeSeconds` ([HealthProfile.swift:15](Repster/Data/Models/HealthProfile.swift:15)) |
| Exclude warm-ups from volume and PRs | `includeWarmupsInVolume`, `includeWarmupsInPRs` ([HealthProfile.swift:8](Repster/Data/Models/HealthProfile.swift:8)) |
| Rest timer alert modes | `restTimerAlert` — off / vibration / sound / both |
| "Tell us which 1RM formula, and let us pick" | `e1RMFormula` ([HealthProfile.swift:10](Repster/Data/Models/HealthProfile.swift:10)) |
| Net load on assisted and weighted bodyweight lifts | `bodyweightFactor`, applied against the logged bodyweight *nearest that set's date* ([SetService.swift:520](Repster/Core/Services/SetService.swift:520)) |
| Side-per-set logging (1L, 2R) | `leftReps`, `rightReps`, `leftRIR`, `rightRIR`, `side` ([WorkoutSet.swift:20](Repster/Data/Models/WorkoutSet.swift:20)) |
| Per-side vs total rep targets | `UnilateralRepTargetMode` ([Exercise.swift:9](Repster/Data/Models/Exercise.swift:9)) |
| Linear time scaling on graphs | Charts plot `x: .value("Date", point.date)` — a continuous `Date` axis ([TimeSeriesBarChart.swift:22](Repster/Features/Charts/Views/Components/TimeSeriesBarChart.swift:22)) |
| Automatic progressive overload suggestions | `LoadPrescriptionService` + `FatigueLearningService` |

Two of these deserve emphasis.

**Bodyweight load.** Two separate Hevy users asked for net load on assisted and weighted bodyweight work — one wanting their changing bodyweight reflected during a cut, another pointing out pull-ups contribute zero volume. Repster does not merely support this; it interpolates against bodyweight history at the set's date.

**Linear graph axis.** This is the most-cited "easy fix" in a 500-comment thread, described by users as the thing that makes their progress charts lie to them. Repster already renders it correctly.

**Action:** these are claims, not builds. They belong in the technical-positioning material in `marketing/campaigns/technical-lifter`, which is already selling the fatigue/e1RM model rather than "fast log." "Your dumbbell volume is right, your bodyweight lifts count, and your chart doesn't lie about a six-month gap" is a concrete version of that same pitch.

## 2.2 Dormant fields — the cheapest wins available

### `Exercise.bilateralLoadFactor` — the field for the thread's #1 request already exists

**Sizing: S.** Almost certainly the highest demand-to-effort ratio on this list.

**What exists today:**
- The field is on the model ([Exercise.swift:90](Repster/Data/Models/Exercise.swift:90))
- It round-trips through `ExportService`, `TemplateService`, `ChartSetData`, and `ExerciseRepository`
- `CreateEditExerciseViewModel` already reads and writes it ([CreateEditExerciseViewModel.swift:32](Repster/Features/Exercise/ViewModels/CreateEditExerciseViewModel.swift:32), [:109](Repster/Features/Exercise/ViewModels/CreateEditExerciseViewModel.swift:109), [:161](Repster/Features/Exercise/ViewModels/CreateEditExerciseViewModel.swift:161))

**What's missing — and it is only two things:**
1. **No UI.** `CreateEditExerciseSheet.swift` does not reference the field. The view-model plumbing is done; this is purely a control.
2. **No arithmetic anywhere.** `computeEffectiveWeight` ([SetService.swift:520](Repster/Core/Services/SetService.swift:520)) handles `bodyweightFactor` only and returns raw weight otherwise. A grep for the field across `Core/` and `Features/` finds no multiplication, division, or addition using it. It is stored, carried, and ignored.

This is the same dormant-field situation as `secondaryMuscles`, and it lines up with the single most-repeated complaint in the entire thread.

**Scope:**
- A "Load entry" picker in the exercise editor: **Per dumbbell** / **Total**, mapping to `bilateralLoadFactor` of 2.0 / nil
- One branch in `computeEffectiveWeight` applying the factor before the bodyweight term
- Set-row subtitle showing the resolved load: enter 70, see "70 × 2 = 140 kg"

**Why the compute site is the right place:** `effectiveWeight` is already the single value every downstream consumer reads — `StatsService`, `PRService`, `ChartDataService`, `LoadPrescriptionService`, `ExportService`, and the fatigue snapshot. Wiring the factor once at computation means stats, PRs, charts, Smart Suggestions, and export all become correct simultaneously, with no per-surface work.

**Decisions to make:**

- **`effectiveWeight` is persisted, not computed on read.** Turning the factor on for an existing exercise does not retroactively fix logged sets, and it will produce a visible step change in that exercise's e1RM and volume charts. Options: (a) backfill existing sets for that exercise on toggle, (b) apply to future sets only with a clear note, (c) offer backfill as an explicit one-time action. Recommendation: **(c)**, matching the pattern already recommended for the HealthKit historical backfill — the destructive-looking option should be opt-in and explained.
- **Seed defaults.** Should dumbbell exercises in `seed_exercises.json` ship with `bilateralLoadFactor = 2.0`? Doing so changes numbers for existing users on update, which is the same trap as (a) above at larger scale. Recommendation: **ship the field off by default, default new/custom exercises off, and let users opt in per exercise.** Revisit once the backfill story is settled.
- **Is 2.0 the only useful value?** Cable machines with a 2:1 pulley are the same arithmetic, and the thread asks for that explicitly. A free-form multiplier is barely more work than a two-option picker and covers both. Recommendation: **picker with Per dumbbell / Total / Custom**, where Custom exposes the raw multiplier.

**Risks:** low engineering risk, moderate data risk. The whole risk sits in the backfill decision, not the code.

### `Exercise.secondaryMuscles`

Already scoped in [SECONDARY_MUSCLES_SCOPING.md](SECONDARY_MUSCLES_SCOPING.md). The thread validates it twice:

- One commenter asks for exactly the model in Decision 2 of that doc — count primary movers as 1.0 sets and secondary movers as 0.5, so a chest day shows true pec set volume against a weekly target.
- Another asks for a **live routine overview while editing a routine**, showing muscles worked (primary + secondary) and estimated duration, updating as exercises are added or sets change. Their framing: this information only appears *after* logging, but it is needed *while planning*.

That second use case is not currently in the scoping doc and is worth adding. Once the `MuscleAttribution` helper exists, a routine-editor summary panel is a straightforward consumer of it, and it addresses a planning need that the post-hoc insights panel does not.

Also relevant from the thread: users want set counts sorted by volume rather than alphabetically, and separate front/side/rear delt tracking. The latter is Option B in the scoping doc's Decision 1 — noted as further evidence that the fine-grained taxonomy has real demand, without changing the recommendation to ship Option A first.

## 2.3 Real gaps, ranked

### Gap 1 — Per-exercise persistent notes

**Sizing: S.** Smallest gap on this list with the largest matching demand.

**What exists today:** `notes: String?` on `WorkoutSet`, `TemplateExercise`, `Workout`, and `WorkoutTemplate`.

**What's missing:** nothing on `Exercise`.

This is precisely the shape Hevy users complain about. `TemplateExercise.notes` is notes-for-this-exercise-in-this-routine — the exact thing people say forces them to paste the same setup note into every routine they build.

**Scope:**
- `Exercise.notes: String?` — lightweight SwiftData migration
- Display on `ExerciseDetailView` alongside the muscle badges
- Collapsed, tappable row above the set table in the active workout
- Editable from both places

The two-level result is what the thread is actually describing: `Exercise.notes` means "always, everywhere," `TemplateExercise.notes` keeps its current meaning. Worth a line of UI copy distinguishing them, or users will not know which they are editing.

**Decisions to make:** does the global note surface on the Watch app when that exists? The thread asks for this specifically. Worth designing the field with that in mind even though the target does not exist yet.

### Gap 2 — Machine setup as structured data

**Sizing: M.** The strongest differentiation opportunity in this analysis.

**What exists today:** nothing. No machine, gym, or equipment-configuration concept anywhere in the model.

**Why structured rather than free text:** the thread is unusually explicit that a notes field does not solve this. Users want to update "chest support: 3" mid-workout when they realise the setting is wrong, and they want it to persist. A text blob is the workaround they are already unhappy with — which means shipping Gap 1 alone does *not* close Gap 2.

**Scope:**
- A `SetupSetting` value type (label + value) stored as an array on `Exercise`
- Rendered as a compact chip row in the active workout — "Seat 4 · Pin 7 · Pad 2" — editable inline with a tap
- Optionally a starting-weight offset for plate-loaded machines, which is the same idea expressed as a number and feeds `computeEffectiveWeight`

**Decisions to make:**
- **Does this need a gym concept, or is per-exercise enough?** The thread wants both — settings per machine *and* separation between gyms. Per-exercise settings alone break for anyone training at two locations, but a full multi-gym model (gym entity, per-gym exercise variants, per-gym previous values and PRs) is a much larger project touching stats and PR scoping. Recommendation: **ship per-exercise setup settings first**; treat multi-gym as a separate, later project and do not let it expand this one.
- **Does the starting-weight offset belong here or with `bilateralLoadFactor`?** Both modify effective load. Recommendation: put the offset in the same load section of the exercise editor as the load-entry picker, so all load math is configured in one place, even if the setup chips live elsewhere in the UI.

**Risks:** scope creep toward the multi-gym model is the main one. The offset touching `computeEffectiveWeight` inherits the same persisted-`effectiveWeight` backfill question as `bilateralLoadFactor` — settle that once and apply it to both.

### Gap 3 — Forward scheduling / Programs

**Sizing: M–L.** Better value than its roadmap position suggests.

**What exists today — more than expected:**
- `Program`, `ProgramExercise`, `PlannedWorkout`, `PlannedSet` models
- `PlannedWorkout` already carries `scheduledDate: Date?` and `weekIndex: Int?` ([PlannedWorkout.swift](Repster/Data/Models/PlannedWorkout.swift))
- `ProgramRepository` and `ProgramRepositoryProtocol`
- A working Calendar feature

**What's missing:** `Features/Programs/Views/` and `Features/Programs/ViewModels/` are **empty directories**. There is no UI at all.

This is the same half-built shape as supersets: data layer present, execution surface absent. The `weekIndex` field in particular means the model already anticipates multi-week programming — the Tier 1 periodization ask.

**Why it may be underrated:** Repster's calendar exists and Hevy's is history-only, which drew direct frustration in the thread. Combined with `LoadPrescriptionService` already handling progression, forward scheduling turns Repster's existing strengths into a programming story rather than a logging story — which is where the loudest demand is.

**Decisions to make:** how much of Tier 1 item 4 does this cover? Scheduling a routine to a date is the small version. Multi-week mesocycles with programmed deloads and %-of-training-max progression is the large version, and it is what the thread's most engaged commenters actually want. These should be scoped as separate phases, not one project.

### Gap 4 — Supersets (existing roadmap item 7)

Already scoped in [FEATURE_SCOPING_BRIEF.md](FEATURE_SCOPING_BRIEF.md) item 7. The thread adds three specifics worth folding into that scope:

1. **Reusable superset blocks.** One user has an abs superset they append to every workout and must redefine it each time; they want to save it and import it. Nobody serves this. It fits Repster's template model naturally.
2. **Supersets across close muscle groups.** Hevy actively blocks pairing exercises it considers too similar, and a user is annoyed enough to complain about being bounced back to the wrong exercise on their watch. Worth confirming Repster imposes no equivalent restriction.
3. **1a/1b paired rows with one shared rest timer.** This matches the brief's recommendation (option b, auto-advance) on the part users care about most — the rest behaviour — and adds a specific presentation idea for the tab strip grouping.

### Gap 5 — Exercise library breadth

**Sizing: S engineering, ongoing content.**

`seed_exercises.json` carries **69 exercises**. Hevy has thousands and *still* took ~17 complaints about missing ones — kettlebells, bands, rings, sandbags, machine variants. Library breadth is the gap most likely to cause silent churn and the least interesting to build.

**Recommendation:** adopt the thread's own best suggestion. Instrument custom-exercise creation in PostHog — capture the name and equipment type on create — and let real user data drive which exercises get seeded next. This is roughly one analytics event and turns an unbounded content problem into a ranked list. It fits the existing `analyticsService.capture` pattern and the dashboards already specified in `POSTHOG_ANALYTICS_GUIDE.md`.

Given the growth picture — paid installs healthy, post-install activation the bottleneck — "the exercise I do isn't in the app" during the first session is a plausible activation killer worth measuring directly.

### Gap 6 — Exercise instructions (existing roadmap item 5)

Confirmed absent: no `instructions`, `cues`, or `howTo` on `Exercise`.

One useful reframe from the thread: the loudest version of this request is about **custom** exercises, not built-ins. Users create an exercise from a YouTube video and want to attach the how-to, a photo, or a link so they remember the movement next week. That half is cheap — users author the content themselves — and sidesteps the authoring bottleneck flagged in the brief as the whole project. It also sidesteps the safety concern with shipping form advice, since the user is recording their own note rather than receiving guidance from the app.

**Recommendation:** treat "attach instructions/media to a custom exercise" as a separate, small item from "author a form-cue library," and ship it first. It overlaps heavily with Gap 1 and could reasonably be the same field.

## 2.4 Not pursuing

**AI features.** Contested in the thread, with one user threatening to cancel over it in the base tier and another praising the absence of it. Repster's fatigue and e1RM model already delivers the substance the pro-AI camp is asking for — "tell me what weight to use" — without the framing the anti-AI camp objects to. No change recommended.

**Multi-gym as a first-class model.** Real demand, but a large project touching PR scoping, stats, and previous-value resolution. Deliberately deferred behind per-exercise setup settings (Gap 2).

**Cardio / interval tracking.** Present in the thread but peripheral to Repster's positioning as a strength-training and progression tool.

---

# Part 3 — Suggested sequencing

| Priority | Item | Size | Notes |
|---|------|------|-------|
| 1 | `bilateralLoadFactor` wiring | S | Highest demand-to-effort ratio available. Settle the backfill question first. |
| 2 | `Exercise.notes` | S | Smallest gap, large matching demand. Possibly merged with Gap 6. |
| 3 | Custom-exercise creation analytics | XS | One event. Unblocks evidence-based library expansion. |
| 4 | Secondary muscles | M | Already scoped. Add the routine-planning overview use case. |
| 5 | Machine setup settings | M | Strongest differentiator. Resist multi-gym scope creep. |
| 6 | Programs UI / forward scheduling | M–L | Models exist, UI is empty. Phase scheduling separately from periodization. |
| 7 | Supersets | M | Existing roadmap item; fold in the three additions above. |

Items 1, 2, and 3 are mutually independent and small enough to ship together. Item 3 should go first regardless of the rest, since it starts collecting data that informs later decisions.

## Cross-cutting decision to settle once

**Backfilling `effectiveWeight`.** Both `bilateralLoadFactor` (item 1) and the machine starting-weight offset (item 5) change how effective load is computed for an exercise that already has logged history. `effectiveWeight` is persisted per set, so neither change is retroactive without an explicit backfill, and either will produce a visible step in that exercise's charts.

This needs one answer applied consistently to both, decided before item 1 is built. The recommendation above is an explicit, opt-in, one-time backfill action with clear copy — but the decision matters more than which option wins, because shipping the two features with different behaviours would be worse than either choice.

## Open questions

1. **Backfill policy for `effectiveWeight`** — see above. Blocking for item 1.
2. **Should seeded dumbbell exercises default to `bilateralLoadFactor = 2.0`?** Convenient, but changes existing users' numbers on update.
3. **Do `Exercise.notes` and custom-exercise instructions want to be one field or two?** One is simpler; two allows different presentation (a short cue in the workout vs. a longer how-to on the detail screen).
4. **Which of these are free vs. behind the RevenueCat entitlement?** Items 1, 2 and 5 read as core logging correctness and should probably be free. Item 6 is a plausible paid feature.
5. **Is per-exercise setup enough, or does the multi-gym problem need solving to make it useful?** Worth a round of user feedback before committing to item 5's scope.
