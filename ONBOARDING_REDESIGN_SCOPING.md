# Onboarding Redesign — Technical Scoping

Status: scoped, not started. Design settled 2026-09-04.
Prototype: the five screens and welcome copy are in the published first-run prototype.
Companion: `design/onboarding-first-run/` (canvas sources, one iteration behind the prototype).

---

## 1. What we are building

Replace the live 1.4 onboarding (welcome → units → Apple Health → import prompt) with:

| Step | Screen | New? |
|------|--------|------|
| Intro | Welcome — headline + three canonical value bullets | Copy change only |
| 1 of 3 | Units and bodyweight | Unchanged |
| 2 of 3 | **Choose a program** — writes a rotation of templates | **New** |
| 3 of 3 | **Optional extras** — import, walkthrough, or start training | **New container**, both destinations exist |
| — | Import history (pushed sub-screen from step 3) | Re-presentation of existing view |

Apple Health leaves onboarding entirely (1.5 already moves the write prompt to the first
finished workout). Import stops being a terminal step and becomes an optional destination.

### Decisions already locked

- **Template is the catch-all concept.** No separate `Program` entity. A program is a named,
  ordered set of `WorkoutTemplate`s sharing a `folder`. This follows the precedent already set
  and documented on `WorkoutTemplate.folder`: *"deliberately a nullable name rather than an
  entity … No lifecycle, no orphans."*
- **The dead `Program` / `ProgramExercise` / `PlannedWorkout` / `PlannedSet` models stay
  dormant.** They are registered in `SchemaV1` and wiped by `SettingsService.resetAllData`, but
  nothing constructs them. Removing `@Model` types requires a new schema version and a migration
  stage; there is no user benefit to justify that risk. Leave them. Revisit only if program-wide
  progression or deload policy is ever built — that is the one thing they would buy.
- **Welcome copy: set 1** (`Repster learns what you can lift` + the three existing bullets).
  These are the canonical value proposition and must stay in sync with the App Store listing and
  the paywall.
- **No equipment step.** Considered and cut.

---

## 2. What already exists

Considerably more than expected. Roughly two thirds of this is assembly, not construction.

| Piece | Where | State |
|---|---|---|
| Welcome screen | `Features/Onboarding/Views/WelcomeStepView.swift` | Built; copy changes only |
| Units + bodyweight | `Features/Onboarding/Views/UnitsBodyweightStepView.swift` | Built; unchanged |
| Step machinery | `OnboardingContainerView` (TabView of `.tag(OnboardingStep…)`), `OnboardingViewModel`, `OnboardingStep` | Built; adding a step is an enum case + a tag + a view |
| Import, end to end | `ImportStepView`, `ImportViewModel`, `ImportService` + 3 CSV adapters (FitNotes, Strong, Hevy), file picker, preview / progress / completed / failed states, `AssignMuscleGroupsView` | **Fully built.** Needs re-presenting as a pushed sub-screen rather than a step |
| Walkthrough | `Features/HowItWorks/HowItWorksView.swift`, 6 pages in `HowItWorksPage.swift` | **Fully built.** Already presented from Settings and Home; step 3 is a third call site |
| Template models | `WorkoutTemplate`, `TemplateExercise`, `TemplateSet` | Built |
| Exercise library | `seed_exercises.json` (69 exercises), `SeedDataLoader`, `SeedService.seedIfNeeded` | Built |
| Onboarding analytics | `onboardingStepViewed/Skipped/Completed` with `step` + `step_index` | Built |

### Two facts that shape the whole design

**`TemplateSet` carries no weight.** Its fields are `setType`, `targetRepMin`, `targetRepMax`,
`targetRIR`, `orderInExercise`. A template prescribes *reps and RIR*; the working weight comes
from the suggestion engine at runtime. This resolves the "what does session one prescribe?"
question outright — there is nothing to invent, and no cold-start weight to fabricate. Programs
ship rep ranges and let the engine do its job from the first logged set.

**`WorkoutTemplate` has no sort order.** Fields are `id, name, notes, folder, lastUsedAt,
createdAt, updatedAt`. A rotation needs an order, so this is the one schema change required.

---

## 3. Where the starter programs come from

This is a content question, and it has a legal edge worth stating plainly.

**Do not reproduce named, branded programs.** StrongLifts 5×5, Starting Strength, PHUL, GZCLP,
nSuns and similar are trademarked names attached to specific published works. Copying a named
program's exercise selection, progression scheme and naming is a real exposure, and "we found it
on a forum" is not a defence.

**Do use the generic structures.** "Train everything three times a week", "split upper from
lower", "push / pull / legs", "five sets of five" are standard training conventions, not anyone's
intellectual property. They are the vocabulary of the field, in the same way that "verse chorus
verse" is not owned by anyone.

**So the practical answer is: take the structural conventions from general knowledge, and author
the actual content yourself against our own library.** You have to do the second part regardless —
every `TemplateExercise` resolves to an `Exercise` record, so the exercise selection is
constrained to the 69 we seed. A scraped program that prescribes exercises we do not have is
useless without either substitution or new seed entries.

Naming follows the same rule: describe the structure (`Full Body`, `Upper / Lower`,
`Push / Pull / Legs`, `5×5 Strength`) rather than invoke a brand. "5×5" describes a set scheme and
is safe; "StrongLifts 5×5" is not.

**Quality control should be a knowledgeable lifter reviewing the output, not a web search.** The
bar is "does this produce sensible sessions from the exercises we actually have", which no source
outside the project can answer.

### Buildability check — all four programs work with the current library

Verified against `seed_exercises.json`. Every exercise these programs need already exists:

- **Full Body** — Barbell Back Squat, Barbell Bench Press, Barbell Row, Barbell Overhead Press,
  Romanian Deadlift, Lat Pulldown, Plank
- **Upper / Lower** — the above plus Dumbbell Shoulder Press, Leg Press, Leg Curl, Barbell Curl,
  Tricep Pushdown, Calf Raise
- **Push / Pull / Legs** — plus Incline Dumbbell Bench Press, Cable Row, Dumbbell Lateral Raise,
  Bulgarian Split Squat
- **5×5 Strength** — Barbell Back Squat, Barbell Bench Press, Barbell Row,
  Barbell Overhead Press, Conventional Deadlift

No new seed exercises are required for the first cut.

Separately, and recorded because it is true regardless of what asks the question: the library has
**no bodyweight leg exercises**. A user with no equipment cannot be served a lower-body session
today. That is a library gap, not an onboarding one.

---

## 4. Changes by layer

### 4.1 Data model

One field, on `Data/Models/WorkoutTemplate.swift`:

```swift
/// Position within `folder`, for programs whose sessions run in sequence.
/// Optional so lightweight migration adds it to existing stores without a stage —
/// same reasoning as `folder`.
var orderInFolder: Int?
```

Optional deliberately: the `folder` field's own comment records that optionality is what let it
land without a migration stage, and `RepsterMigrationPlan` currently declares `SchemaV1` with no
stages. Keep it that way.

Templates outside a program keep `nil` and sort by existing rules.

### 4.2 Program catalogue (new)

A bundled JSON, mirroring the shape and loading pattern of `seed_exercises.json`.

`Resources/seed_programs.json`:

```json
{
  "_meta": { "version": "1.0", "notes": "Exercise names must match seed_exercises.json exactly." },
  "programs": [
    {
      "id": "full_body_3d",
      "name": "Full Body",
      "daysPerWeek": 3,
      "summary": "Hits everything each session.",
      "sessions": [
        {
          "name": "Full Body A",
          "exercises": [
            { "exercise": "Barbell Back Squat", "sets": 3, "repMin": 5, "repMax": 8,  "rir": 2, "restSeconds": 180 },
            { "exercise": "Barbell Bench Press", "sets": 3, "repMin": 5, "repMax": 8, "rir": 2, "restSeconds": 180 }
          ]
        }
      ]
    }
  ]
}
```

New files:

- `Core/Seeding/ProgramSeedDTO.swift` — `Codable` mirror of the above
- `Core/Seeding/ProgramSeedLoader.swift` — `loadPrograms() throws -> [ProgramSeedDTO]`, exactly
  parallel to `SeedDataLoader.loadExercises()`

**Do not extend `SeedService`.** It gates on `Exercise` count being zero and runs at launch and on
reset. Programs are materialised on user selection, not at first launch, and must not be created
for users who never pick one.

### 4.3 Program materialisation service (new)

`Core/Services/ProgramCatalogService.swift`, behind a protocol in `Core/Services/Protocols/`
per the existing service convention, registered in `ServiceContainer`.

```swift
protocol ProgramCatalogServiceProtocol {
    /// Catalogue for the picker. Pure read, no side effects.
    func availablePrograms() throws -> [ProgramSeedDTO]

    /// Writes one program's sessions as templates in a folder named after the program.
    /// Idempotent per program id. Returns the created templates in rotation order.
    @discardableResult
    func materialise(programId: String) throws -> [WorkoutTemplate]
}
```

Materialisation, per session, in order:

1. Resolve every `exercise` name to an `Exercise` **by name, case-insensitively**. Collect misses.
2. If any exercise is missing, skip that entry and log; do not fail the whole program. A program
   short one accessory is still useful; a hard failure at the end of onboarding is not.
3. Insert `WorkoutTemplate(name: session.name, folder: program.name, orderInFolder: index)`
4. Insert `TemplateExercise(templateId:, exerciseId:, orderInTemplate:, restTimeSeconds:)`
5. Insert `sets` × `TemplateSet(templateExerciseId:, setType: .working, targetRepMin:,
   targetRepMax:, targetRIR:, orderInExercise:)`
6. Single `save()` at the end, as `SeedService` does.

Access goes through repositories, not raw `ModelContext` — `SeedService`'s direct access is an
explicitly documented one-time-initialisation exception and this is not that.

### 4.4 Onboarding flow

`Features/Onboarding/OnboardingStep.swift`:

```swift
case welcome            = 0
case unitsAndBodyweight = 1
case program            = 2   // was importPrompt
case extras             = 3
```

- `importPrompt` is removed as a step. `analyticsName` gains `"program"` and `"extras"`.
- `isSkippable`: both new steps return `false`. Step 2 always resolves to a choice (including
  "build my own"); step 3's exit is the primary button, not a skip. **This removes the
  uninstrumented-skip ambiguity that made the old `import_prompt` unreadable** — there is no skip
  control left to fail to instrument.
- `OnboardingViewModel.isLastStep` currently hard-codes `== .importPrompt`; change to `.extras`.
- `visibleSteps` / `stepProgress` need no change — they count off `allCases`.

New state on `OnboardingViewModel`:

```swift
var selectedProgramId: String?      // nil until chosen; "own" for build-my-own
```

On finish, after existing preference writes, call
`programCatalogService.materialise(programId:)` when a real program is selected. Wrap in
`isSaving` as the existing save path does, and surface failure without blocking completion —
a user must never be trapped on the last screen because template writing failed.

### 4.5 New screens

- `Features/Programs/Views/ProgramPickerView.swift` — the picker, built standalone with **two
  call sites**: onboarding step 2, and a sheet from the Templates screen (see §5, Reset). Cards
  from `availablePrograms()`, rotation preview on selection, "build my own" as a de-emphasised
  link below the list, CTA disabled until a choice is made. The onboarding step is a thin wrapper
  supplying the step chrome; the view itself knows nothing about onboarding.
- `Features/Onboarding/Views/ExtrasStepView.swift` — confirmation line naming the chosen program,
  two option rows, primary "Start training".

`ImportStepView` is presented from `ExtrasStepView` as a pushed sub-screen (`NavigationLink` or
`.sheet`, matching the existing Settings presentation). Its `onFinish` / `onSkip` return to
extras rather than completing onboarding. `HowItWorksView(analyticsService:)` is presented the
same way it already is from `HomeView` and `SettingsView`.

### 4.6 Analytics

Additions to `AnalyticsServiceProtocol`:

```swift
func programSelected(programId: String, sessionCount: Int)
func onboardingExtraTapped(extra: String)   // "import" | "walkthrough"
```

**The funnel will break at the release boundary, and that is unavoidable.** `step` values change
(`import_prompt` disappears, `program` and `extras` appear) and `step_index` shifts again — the
source already warns that `step_index` is unstable across releases and that `step` is the dimension
to funnel on. Now `step` moves too.

Mitigations:

- Keep `welcome` and `units_bodyweight` spelled exactly as they are, so the top of the funnel
  stays comparable across the boundary.
- Record the release and build number where the change lands, in this document, on merge.
**What survives the boundary, and what does not.** The two ends keep their names — `welcome` at
the top, `onboarding completed` at the bottom — and everything downstream (`workout started`,
`workout completed`, retention) is untouched. So "of people who saw the welcome screen, what
fraction finished a workout" is comparable before and after. Per-step drop-off is not, because the
steps are different screens.

**And the surviving comparison is underpowered.** Against the current 24.6% activation (14 of 57),
at 80% power and 5% significance:

| Detecting a move to | People needed per arm | At ~35 installs/week |
|---|---|---|
| 35% | ~303 | ~9 weeks each side |
| 40% | ~144 | ~4 weeks each side |
| 50% | ~56 | ~2 weeks each side |

57 people can only resolve roughly a doubling. **Ship this on the reasoning, not as an
experiment** — the evidence is the qualitative funnel (all 21 non-starters hit an empty Home,
26 of 27 first workouts started blank, 10 of 13 mid-workout quitters never logged a set). Watch
activation as a directional check over months, and do not read a null result at eight weeks as
"it did not work".

---

## 5. Migration and data safety

- **Schema.** Adding one optional `Int` to `WorkoutTemplate` is a lightweight migration.
  `RepsterMigrationPlan` stays at `SchemaV1` with no stages. Verify by launching a build over an
  existing store with templates present before merging.
- **Reset — resolved.** `SettingsService.resetAllAppData()` deletes `WorkoutTemplate`,
  `TemplateExercise` and `TemplateSet` (lines 191–193), re-seeds exercises, and leaves onboarding
  marked complete. A reset user therefore lands in exactly the empty app this project exists to
  remove, with no route back to a program.

  **Do not special-case reset.** Make program selection permanently available from the Templates
  screen instead, and the reset case handles itself — the user lands on an empty Templates screen
  whose primary action offers them a program.

  Re-running onboarding would be wrong: the user asked to wipe *data*, not to redo setup, and
  units and bodyweight are settings that survive the reset, so re-asking them is irritating. More
  importantly a non-onboarding entry point is needed regardless — anyone who picks "build my own"
  currently never gets a program and cannot change their mind; people finish a cycle or get injured
  and want a different one; and only 3 of 57 people ever found Templates, so that screen needs a
  strong primary action anyway. One affordance, three problems.

  **Scope impact:** build the picker as a standalone `ProgramPickerView` with two call sites
  (onboarding step 2, and a sheet from Templates) rather than an onboarding-specific view. See
  §4.5 and PR5.
- **Deleted exercises.** A user deleting an exercise a template references is the known
  "Unknown Exercise" class of defect, fixed on 2026-09-01 via the `deleteExercise` cascade.
  Generated templates are ordinary templates and inherit that fix — but add a regression test that
  deletes a seeded exercise referenced by a generated program.
- **Idempotency.** Guard `materialise` against double invocation (rapid double-tap on the CTA,
  or a retried save). Key the guard on program id plus an existing-folder check.

---

## 6. Edge cases

| Case | Handling |
|---|---|
| User already has a folder named "Full Body" | Suffix the new folder (`Full Body 2`) rather than merging into someone's existing work |
| Exercise name in catalogue not found | Skip that exercise, log, continue. Never fail the whole program |
| All exercises in a session missing | Skip the session; if every session is empty, treat as failure and fall through to "build my own" |
| `materialise` throws at the end of onboarding | Complete onboarding anyway; surface a retry from Templates. Never trap the user |
| "Build my own" selected | No templates written. Extras confirmation reads "Empty library ready" |
| Import run after a program is chosen | Both coexist — imported history and generated templates are independent |
| Re-running onboarding after reset | See "Reset" above; needs a decision |

---

## 7. Tests

Unit:

- `ProgramSeedLoader` decodes the bundled JSON; malformed entries are skipped, not fatal
- **Catalogue integrity: every exercise name in `seed_programs.json` resolves against
  `seed_exercises.json`.** This is the highest-value test in the set — it fails loudly the moment
  someone edits either file and breaks the join, which is the most likely regression here
- `materialise` writes the expected template / exercise / set counts, in order
- `materialise` is idempotent under double invocation
- Missing exercise → skipped, rest of program intact
- `orderInFolder` ascends and matches catalogue order

Integration:

- Full onboarding: welcome → units → program → extras → complete, with templates present after
- Deleting a seeded exercise referenced by a generated template does not crash (regression against
  the known delete-ordering class)
- Reset behaviour matches whatever is decided in §5

Analytics:

- `onboarding step viewed` fires once per step, with the new `step` values
- `programSelected` carries the right id and session count
- Existing `AnalyticsServiceTests` updated for the changed enum cases

Manual, on device:

- Lightweight migration over a store that already has templates and folders
- Import from a real Strong CSV, launched from extras rather than as a step

---

## 8. Build order

Sequential where noted; PR1 and PR2 are independent and can run in parallel.

| PR | Contents | Depends on |
|----|----------|-----------|
| **PR1** | `orderInFolder` on `WorkoutTemplate` + migration verification | — |
| **PR2** | Welcome copy change (three bullets, centred) | — |
| **PR3** | `seed_programs.json` content + DTOs + loader + catalogue integrity test | — |
| **PR4** | `ProgramCatalogService` + materialisation + unit tests | PR1, PR3 |
| **PR5** | `OnboardingStep` changes, `ProgramStepView`, view-model wiring | PR4 |
| **PR6** | `ExtrasStepView` + import and walkthrough presentation | PR5 |
| **PR7** | Analytics events + updated tests + record the release boundary here | PR5, PR6 |

PR3 is the long pole and it is **content, not code** — four programs, roughly fourteen sessions,
every exercise chosen and every rep range set. Budget real time for it and get it reviewed by
someone who trains.

---

## 9. Open questions

1. ~~**Reset behaviour**~~ — resolved in §5: program selection becomes permanently available from
   Templates, and reset needs no special handling.
2. ~~**Landing screen**~~ — decided 2026-09-04: **finish onboarding into Home, unchanged.**
   No example data, no straight-into-a-session, no reroute to Templates. Home gets its own pass
   later, separately from this work.
3. **Rotation state** — nothing yet decides which session in a program is "next". Templates in a
   folder with an order is enough to display a rotation; surfacing "today is Pull A" on Home is a
   further piece of work and is not scoped here.
4. **Apple Health read** — pulling bodyweight and history is a fill-the-app move that would sit
   naturally beside Import on the extras step. Verify first that HealthKit strength workouts carry
   per-set detail; if they do not, it populates Calendar and History but leaves Charts empty.

---

## Appendix — measurements this design responds to

From the 1.4 funnel analysis (10 Aug – 2 Sep 2026, 57 onboarding starters, all v1.4):

- 84% finished onboarding; **47% started a workout; 25% finished one**
- All 21 who finished onboarding without starting a workout saw the empty Home state
- Median time from onboarding complete to workout start: **0.0 minutes** (p90 3.2) — it is now or never
- 26 of 27 first workouts started from an empty session, no template
- 10 of the 13 who abandoned mid-workout never logged a single set
- Only 3 of 57 ever found Templates
- 5 people quit on the import prompt and never reopened the app; it recorded **zero** skips
- Retention by activation depth: never started 9.5% · started 23.1% · finished a workout 35.7%

Sample size is small; treat all of it as directional.
