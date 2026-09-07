# 1.5 Release Plan

**Originally written:** 2026-08-18 · **Revised against the tree:** 2026-09-01 ·
**Scope locked:** 2026-09-06
**Live:** 1.4 (build 4), released 2026-08-20
**In the project right now:** `MARKETING_VERSION = 1.4.1`, build 1 — the number is
**not settled**; that decision lives in [PRE_1.5_CHECKLIST.md §0](PRE_1.5_CHECKLIST.md)
**Status:** scope is locked. This document is now a record of what 1.5 contains, not
a plan for what it might.

## What this document is

**Everything below is in the build.** Anything that was considered for 1.5 and is not
in the build has moved to
[RELEASE_1_6_CONSIDERATIONS.md](RELEASE_1_6_CONSIDERATIONS.md) — including the items
this document used to carry as open bullets.

It is deliberately **not** a launch checklist. [PRE_1.5_CHECKLIST.md](PRE_1.5_CHECKLIST.md)
is that. Why things were *not* built is [1_5_DECISION_RECORD.md](1_5_DECISION_RECORD.md).

## What changed in the 2026-09-06 scope lock

| Then | Now |
|---|---|
| Seven-item "suggested shape", sized XS to one week | Items 1–3 built, 4 built and awaiting a device pass, 6 built. Items 5 and 7 moved to 1.6 |
| Part 3 muscle coverage, Part 4 unbuilt items, Part 5 decisions, Part 7 not-proposed | All moved wholesale to [RELEASE_1_6_CONSIDERATIONS.md](RELEASE_1_6_CONSIDERATIONS.md) |
| "Exercise replace is still open" | Wrong. Replace is built; so is the reorder sheet |
| Onboarding is not in this release | It is. Program picker, seed catalogue, Extras step and new welcome copy all landed 2026-09-04 |
| Release described as summary-screen-led | It is wider than that: onboarding, templates, supersets and the summary screen are four separate visible reworks |

---

# Part 1 — What is in the release

Committed on `NewMain` since the `1.4` commit (`4b8a0ae`, 2026-08-19). **46 commits**,
plus the uncommitted work in Part 2.

## 1.1 Onboarding, rebuilt around programs · **the release's real front door**

Landed 2026-09-04 in `22c9367`, scoped in
[ONBOARDING_REDESIGN_SCOPING.md](ONBOARDING_REDESIGN_SCOPING.md) (which still reads
`Status: scoped, not started` and needs re-baselining).

- `OnboardingStep` is now welcome → units and bodyweight → **program** → **extras**.
  The old `importPrompt` step is gone — it was the last thing between the user and the
  app, and five people stopped there for good without one recorded skip
- **A program is a rotation of templates in a folder**, not a new entity. The dormant
  `Program` / `ProgramExercise` / `PlannedWorkout` / `PlannedSet` models stay dormant
  by decision
- Four seeded programs in `Repster/Resources/seed_programs.json`: Full Body (3×),
  Upper / Lower (4×), Push / Pull / Legs (6×), 5×5 Strength (3×), behind
  `ProgramCatalogService` with an integrity test pinning every exercise name to
  `seed_exercises.json`
- **Apple Health leaves onboarding entirely.** The offer now fires once, after the
  first completed workout, gated on `shouldOfferConnection` and a completed-workout
  floor so a first-ever discard cannot spend it
  ([ContentView.swift:785](Repster/App/ContentView.swift:785))
- Welcome carries the three canonical value bullets. These are one asset with three
  surfaces — onboarding, the App Store listing and the paywall — and 1.5 changes only
  one of the three. See [PRE_1.5_CHECKLIST.md §7](PRE_1.5_CHECKLIST.md)

## 1.2 Templates, rebuilt · folders, a detail view, paired supersets

[TEMPLATES_IMPLEMENTATION_PLAN.md](TEMPLATES_IMPLEMENTATION_PLAN.md), landed
2026-09-01 across seven commits, 62 template tests.

Folders, a real detail view with unfolded sets, filing from the list, New and Import
merged into one entry point, superset pairings preserved — and **the AI template
helper deleted**. That last one is a removal users will notice and the website still
documents; see [PRE_1.5_CHECKLIST.md §6](PRE_1.5_CHECKLIST.md).

Followed by a hardening pass the same day: every editor mutation addressed by identity
rather than array position, rep-field seeding no longer writes nil targets, and a
template export survives one dangling exercise instead of failing whole.

## 1.3 Supersets · marked-only

[SUPERSETS_IMPLEMENTATION_PLAN.md](SUPERSETS_IMPLEMENTATION_PLAN.md), landed
2026-08-31. PR1–PR9 and PR11: visible in the workout and afterwards, the prompt works
in both directions, and a finished partner no longer eats your rest. Only the Live
Activity line is unbuilt, and it is an open question rather than pending work.

## 1.4 Workout summary screen and shareable card

[SUMMARY_SCREEN_IMPLEMENTATION_PLAN.md](SUMMARY_SCREEN_IMPLEMENTATION_PLAN.md) W1–W7,
committed 2026-09-02 as "Give the finished workout a card worth sharing".

The 2026-08-18 draft scoped a card hanging off the existing sheet. What was built
rebuilds the sheet and makes the card one of seven work packages. The reasoning that
put it in the headline slot holds: 1.4 was a privacy-and-measurement release with
almost nothing a user could see.

**It also fixed a bug older than the plan.** Notes and effort were fully wired end to
end and unreachable from the sheet — `git log -S "effortSection"` returns one commit,
and in that commit the body already rendered only four other sections. `deloadReadiness`
is the sole reader of `perceivedEffort` and has therefore never had real input.

Since committed:

- **Analytics wired 2026-09-05.** `share card opened` / `shared` / `dismissed` /
  `failed`, plus the `Share Card` screen. The share button moved from `ShareLink` to a
  `UIActivityViewController` wrapper, because `ShareLink` has no completion handler —
  with it, "shared" could only ever have meant "tapped Share". Counts forward only:
  cards shared between 2026-09-02 and 2026-09-05 are not counted anywhere
- **`NSPhotoLibraryAddUsageDescription` added.** Save-to-photos would have crashed on
  first tap without it

## 1.5 Suggestion engine, epoch 2

[SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md](SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md),
landed 2026-08-27 across six commits. Reps in reserve credited as a floor, one set can
no longer crater the capability estimate, drop sets no longer grade the model,
unlabelled sets charged at their target, learned rates reset on the model change.
Golden master frozen, unilateral sets covered, plus a kill switch for the capacity
guards (`prescriptionCapacityGuardsEnabled`).

**This is the change that shifts every existing user's numbers on day one.** See
[PRE_1.5_CHECKLIST.md §2.2](PRE_1.5_CHECKLIST.md).

Joined 2026-09-06 by the **"why this weight" explainer sheet** (uncommitted) — tapping
a pending suggestion opens the inputs behind it. Every line is a set the lifter
performed or a target they set; derived quantities are deliberately absent, and the
"go for N instead" push is suppressed when the evidence behind the number is weak.

## 1.6 Drop sets, made real

Landed 2026-09-03. [DROP_SETS_SCOPING.md](DROP_SETS_SCOPING.md) phases 1–3: the set
types with no feature behind them are hidden, `dropset` is a real selectable type
**visible in history**, and the engine defects a visible drop set would expose are
fixed. Phase 4 — the 1.4× multiplier flatten — is 1.6.

## 1.7 Exercise replace and reorder

[EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md).
Replace in place with a confirmation, plus Move Left / Move Right, landed 2026-08-30
with four defects fixed. The whole-workout **reorder sheet** followed 2026-09-06
(uncommitted): a menu entry on the tab strip, supersets locked together, workout-only,
no Cancel.

## 1.8 Session replay masking, inverted

Landed 2026-08-30. 1.4 masked every screen and opted a handful back in, which left six
sections and 41 of the app's 45 sheets as solid black. From 1.5 the recording is
legible and a named list of values is masked instead.

**This is the change that requires a privacy policy deploy and a rewritten App Review
note before the build reaches users.** [PRE_1.5_CHECKLIST.md §1.1 and §1.2](PRE_1.5_CHECKLIST.md).

## 1.9 The rest

| Work | Doc | Landed |
|---|---|---|
| Backup restore hardening — a new enum case cannot fail a whole decode | [BACKUP_EXPORT_SCOPING.md](BACKUP_EXPORT_SCOPING.md) | 2026-08-27 |
| Progression exclusion visibility — history chip + workout-detail banner | [PROGRESSION_EXCLUSION_VISIBILITY_SCOPING.md](PROGRESSION_EXCLUSION_VISIBILITY_SCOPING.md) | 2026-08-30 |
| Export screen copy — describes contents, and stops claiming restore leaves templates alone | [BACKUP_EXPORT_SCOPING.md](BACKUP_EXPORT_SCOPING.md) | 2026-09-05 |
| Set keypad — stops tearing itself down per keystroke, eager set rows, top strip | [KEYPAD_TOP_STRIP_SCOPING.md](KEYPAD_TOP_STRIP_SCOPING.md) | 2026-09-02 → 09-05 |
| Annotated sets no longer vanish from Copy Previous, Home and Insights | — | 2026-09-03 |
| A deleted rep target stays deleted | — | 2026-09-02 |
| Public site made shareable and crawlable — OG card, sitemap, robots | — | 2026-09-02 |

---

# Part 2 — Uncommitted on `NewMain` at scope lock

23 paths. All of it builds clean (`xcodebuild build -scheme Repster`, 2026-09-06, zero
errors).

| Work | Files |
|---|---|
| Suggestion explainer sheet | `SuggestionExplainerSheet.swift` (415 lines) + `SuggestionExplainerPushTests.swift`, and the `WeightSuggestionData` / `LoadPrescriptionServiceProtocol` changes feeding it |
| Reorder sheet | `ReorderExercisesSheet.swift` (194) + tests, `SupersetPalette.swift` (31) extracted so the sheet and the tab strip agree on colours |
| Share card analytics | `AnalyticsServiceProtocol.swift` (+139), `AnalyticsServiceTests.swift` (+232), `WorkoutShareCard.swift` (+203) |
| Export screen copy | `ExportView.swift`, `SettingsView.swift` |
| Doc updates | `POSTHOG_ANALYTICS_GUIDE.md`, this file, `PRE_1.5_CHECKLIST.md` |

**Commit these in coherent chunks before archiving** — the explainer, the reorder sheet
and the analytics work are three separate things. [PRE_1.5_CHECKLIST.md §4](PRE_1.5_CHECKLIST.md).

---

# Part 3 — Everything else

Moved out of this document on 2026-09-06 and now lives in one place:
**[RELEASE_1_6_CONSIDERATIONS.md](RELEASE_1_6_CONSIDERATIONS.md)**.

That covers the two commitments carried over from 1.4 for a second time
(`BodyweightEntry` and programs in the archive, bodyweight-style labels), the four
unbuilt features that were proposed for 1.5 (`equipmentType`, `bilateralLoadFactor`,
`Exercise.notes`, muscle coverage), the seven open decisions, the defects 1.5 ships
with, and what is blocked on Apple rather than on us.

**Muscle coverage Phase 2 remains the natural 1.6 headline**, and 1.5 built both
surfaces it needs to hang off.

## The one decision that belongs to 1.5, not 1.6

**Entitlements.** Supersets, the templates redesign, the share card, the rebuilt
summary screen and the onboarding program picker have all shipped into the tree with
no free-vs-paid answer taken. After 1.5 they are features users have had free for a
version, and taking one behind a paywall in 1.6 is a removal rather than a decision.
1.5 is the last cheap moment. See
[RELEASE_1_6_CONSIDERATIONS.md §3.4](RELEASE_1_6_CONSIDERATIONS.md).

## The version number

`WhatsNewRelease.current` matches `CFBundleShortVersionString` by **exact string
equality**, and `WhatsNewRelease.all` holds entries for `"1.4"` and `"1.5"` only. The
project reads `1.4.1`. **Shipping as 1.4.1 shows the What's New sheet to nobody,
silently** — for a release containing a rebuilt onboarding, supersets, a rebuilt
templates system, a new summary screen and an engine change that moves every user's
numbers. See [PRE_1.5_CHECKLIST.md §0](PRE_1.5_CHECKLIST.md), which is where the
decision belongs.
