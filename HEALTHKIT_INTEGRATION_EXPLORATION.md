# HealthKit integration — exploration

Expands item 2 of `FEATURE_SCOPING_BRIEF.md`. Written 2026-08-08 against branch `NewMain`.

Everything under "verified" was read in the code. This is an exploration, not a plan — it ends with decisions, not tasks.

> **Scope decision (2026-08-08):** the target is **direction A only** — a finished workout gets pushed to Apple Health. Directions B/C/D (bodyweight both ways, heart rate/energy read) are documented below for context but are **not in scope**. Read the "one-paragraph version", the constraint section, and Phases 0–1; the rest is background.

---

## The one-paragraph version

HealthKit is a **four-way integration**, and only one of the four directions is genuinely valuable on its own: writing finished workouts into Apple Health. That direction is small, self-contained, and can be built **without touching workout-logging code** by copying the lazy-refresh pattern the Insights engine already uses. The other three directions (read bodyweight, write bodyweight, read energy/heart rate) are each cheap in isolation but drag in sync state, conflict rules, and a permission surface. The real cost of this feature is not HealthKit API code — it's the **project-level plumbing** (first-ever entitlements file, App ID capability change on a live app, provisioning regeneration, privacy label update) and the **QA cost** of a device-only feature.

---

## What "integrating with Health" actually means, concretely

Four independent capabilities. They are worth scoping separately because they have different value, different risk, and different blockers.

| # | Direction | Data | Value | Cost |
|---|-----------|------|-------|------|
| A | Write | Finished workouts → `HKWorkout` | **High** — visibility in Health/Fitness, ecosystem credibility, Watch prerequisite | S–M |
| B | Read | Body mass ← Health | Medium — removes manual entry friction | S, but sync state |
| C | Write | Body mass → Health | Low on its own; completes B | S, but echo-loop risk |
| D | Read | Active energy / heart rate ← Health | Low without a Watch app | M, mostly wasted today |

**Recommendation: A alone is a shippable release.** B+C are a second, separable pass. D should wait for the Watch app — reading heart rate for a workout logged on the phone means reading someone *else's* Watch samples over the workout window, which is a guess dressed as data.

---

## Where the write hooks in

> **Update 2026-08-08:** the "don't change workout-logging code" constraint has been **lifted** — it was a guardrail against unrelated AI edits, not an architectural boundary. The hook below is chosen on merit, not to route around a restriction.

The place to write an `HKWorkout` is the moment a workout finishes. Verified, that path is:

- `Features/Workout/Views/WorkoutSummarySheet.swift:730` → `saveAndClose()`
- `Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1923` → `finishWorkout(title:notes:perceivedEffort:)`
- `Core/Services/WorkoutService.swift:54` → `finishWorkout(...)`

`ActiveWorkoutViewModel.finishWorkout` is **already the app's post-finish side-effect hub** — it fires analytics (`:1951`), records access-control state (`:1943`), triggers the review prompt (`:1970`), and runs `fatigueLearningService.processSessionEnd` (`:1973`). A HealthKit write would fit that pattern perfectly. It is also **exactly the file you've ruled off-limits**, and the file whose last modification got reverted.

### The hook: `WorkoutService.finishWorkout`

- It is the **single choke point**. `workout.status = .completed` is set in exactly one place for a real finish (`WorkoutService.swift:69`).
- It has a **single call site** (`ActiveWorkoutViewModel.swift:1935`), and the protocol signature doesn't change, so the diff stays small and contained in the service layer.
- It's a true at-finish push, not an approximation of one.

A lazy pass mirroring `InsightsService.refreshIfNeeded()` (`Core/Services/InsightsService.swift:103`) is still worth having, but as a **retry sweep** for writes that failed (offline, permission revoked mid-session, app killed) — not as the primary trigger.

### Two non-negotiable properties of the hook

**1. A HealthKit failure must never fail the finish.** `finishWorkout` currently throws, and `ActiveWorkoutViewModel` awaits it before clearing local state and dismissing. If a HealthKit error propagated, a Health problem would become a *lost workout*. The write must be fire-and-forget — spawned after the existing `workoutRepo.save(workout)` succeeds, errors swallowed and logged, never awaited on the finish path. It also keeps HealthKit latency out of the tap-to-dismiss path.

**2. Import must not fire it.** `ImportService.swift:119` creates workouts with `status: .completed` directly, bypassing `finishWorkout`. This is why the trigger must be *"the user finished a workout"* and never *"a workout became completed"* — the latter would dump a user's entire restored backup into Apple Health on import. Hooking `finishWorkout` avoids this by construction.

---

## What has to exist that doesn't exist today

### 1. An entitlements file — there is currently none

Verified: `find . -name "*.entitlements"` returns **nothing**, and `CODE_SIGN_ENTITLEMENTS` appears nowhere in `project.pbxproj`. The app has shipped without ever needing one (Live Activities need only `NSSupportsLiveActivities`, which is in `Info.plist:66`).

HealthKit requires `com.apple.developer.healthkit`. So this feature introduces:

- A new `Repster.entitlements` file,
- A `CODE_SIGN_ENTITLEMENTS` build setting on the app target (both Debug and Release configs),
- **The HealthKit capability enabled on the App ID** in the developer portal,
- **Regenerated provisioning profiles** for a live, shipped app.

None of that is hard. All of it is the kind of thing that fails a release build at 11pm. Do it first, in its own commit, and push a build through TestFlight before writing a line of HealthKit code.

### 2. Info.plist usage descriptions

- `NSHealthUpdateUsageDescription` — required for A and C (write).
- `NSHealthShareUsageDescription` — required for B and D (read).

Only add the *share* key if you actually ship a read path. An unused permission string is a question at review time.

### 3. Sync state — the one schema change

You must be able to answer "has this workout already been written to Health?" without asking HealthKit every time.

**Recommendation:** add `var healthKitWorkoutUUID: UUID?` to `Data/Models/Workout.swift`. This is an additive optional property — a lightweight SwiftData migration, and it's **the pattern the model already uses**. `Workout.swift:18-23` carries two properties explicitly commented "Optional for lightweight migration compatibility", so there's precedent and the risk profile is understood.

Storing the UUID rather than a `Bool` buys you three things for free:

- Idempotency — never double-write.
- A delete path — `WorkoutService.deleteWorkout` (`:163`) can remove the mirrored sample. HealthKit only lets an app delete samples it saved, so the UUID is how you find yours.
- Debuggability when a user says "it's not in Health".

For the bodyweight read path (B), you additionally need a persisted `HKQueryAnchor` for `HKAnchoredObjectQuery`. That's `UserDefaults`, not the model — the codebase already has small `UserDefaults`-backed stores (e.g. `WorkoutStartContextStore`) to copy.

### 4. Hand-registration in `project.pbxproj`

Per the brief's standing constraint: new files don't compile until they're registered. Budget for ~4–6 new files (service, protocol, settings view, view model, sync state helper, tests).

---

## Direction A: writing workouts to Health

### What you'd write

`HKWorkoutBuilder` — note that on iOS 17 (your deployment target) the old `HKWorkout` initializers are deprecated, so `HKWorkoutBuilder` is the only forward-looking path. The flow is `beginCollection(withStart:)` → add samples → `endCollection(withEnd:)` → `finishWorkout()`, and it works fine for historical dates.

Available from `Workout` with no new data collection: `startTime`, `endTime`, `duration`, `title`. That's enough for a valid, useful `HKWorkout` with activity type `.traditionalStrengthTraining`.

### The energy question — this is the one users will actually care about

**A workout written without active-energy samples appears in Health and in the Fitness app's workout list, but contributes nothing to the Move ring.** The first support email will be "why didn't my rings close?"

You have three options:

1. **Ship without energy.** Honest, zero risk, and users will complain.
2. **MET-based estimate.** `kcal ≈ MET × bodyweight_kg × hours`. Traditional strength training sits around 3.5–6 METs. Crucially, **you already have the bodyweight input**: `BodyweightService.closestBodyweight(to: date)` (`Core/Services/BodyweightService.swift:55`) exists and does precisely this lookup. So the estimate is cheap and grounded in real user data rather than a constant.
3. **Wait for the Watch app** for measured energy.

**Decided: option 2 — MET-based estimate, behind its own toggle, defaulted off, labelled "estimated".** Estimated calories written to Health flow into other apps' "calories out" and into the user's rings. Silently inflating someone's energy balance is a bigger trust problem than an unmoved ring, so it's a deliberate opt-in and the UI says the word "estimated".

**MET value: 3.5** — the Compendium of Physical Activities figure for multi-exercise resistance training, which is calibrated for a whole session *including* rest periods. `Workout.duration` already excludes paused time (`durationSecondsOverride`), so total session duration is the right input. `Workout.perceivedEffort` is an obvious way to scale between ~3.5 and ~6.0 later; v1 stays fixed and conservative.

### What happens when the user has no bodyweight — decided

This is a **reachable state, not an edge case**: `Features/Onboarding/Views/BodyweightStepView.swift:54` has a Skip button.

**The codebase already sets the precedent — degrade silently, never guess.** `SetService.computeEffectiveWeight` (`Core/Services/SetService.swift:397`) needs the same input for bodyweight-factor exercises. With no entry it returns the raw weight: no default, no substituted average, no error. The doc comment states it as a rule — *"If no bodyweight entry -> effectiveWeight = weight"*.

Matching behaviour here:

- **No bodyweight → the workout is still written to Health, just with no energy sample.** Correct start, end, duration and title; it simply doesn't contribute to the Move ring. Nothing fails, nothing blocks, no prompt at finish time.
- **Do not substitute a population-average weight.** It breaks the codebase's own precedent, and a fabricated calorie figure is worse than an absent one — it reaches both the Move ring and any nutrition app reading "calories out". Being wrong by 40% on someone's energy balance beats an unmoved ring as a problem.
- **UI:** when bodyweight is missing, show an inline note under the energy toggle — "Add your bodyweight to include estimated calories" — pointing at the bodyweight log, which is already the adjacent row in Settings › Body. Leave the toggle enabled so future workouts pick it up automatically once weight exists.

Two consequences that fall out for free:

- **Historical accuracy.** `closestBodyweight(to: date)` is nearest-to-workout-date, so workouts across months of weight change each get a period-appropriate figure rather than today's.
- **Workouts written before bodyweight existed stay energy-less.** Backfilling would mean deleting and rewriting those HealthKit samples. Not worth it for v1.

### Activity type mapping

`Exercise.trackingType` (`Data/Enums/TrackingType.swift`) has `weightReps`, `duration`, `durationDistance`, `weightDistance`, `weightDuration`, `weightRepsDuration`, `custom`. Tempting to map these to different `HKWorkoutActivityType`s.

**Don't, in v1.** A Repster workout is one session containing mixed exercises; there is no coherent single activity type to derive. `.traditionalStrengthTraining` for everything is correct for a strength-training app and is what users expect to see in Health. Revisit only if cardio logging becomes a real use case.

### Backfill

The brief already flags this: writing history on first connect can dump hundreds of entries into Health at once. Concur with the brief's recommendation — **explicit one-time action, default off**, with a count shown before it runs ("Add 247 past workouts to Apple Health?").

One addition: the lazy sync pass makes accidental mass-backfill easy to write by mistake. If `syncPendingWorkouts()` naively means "every completed workout without a `healthKitWorkoutUUID`", then the first run after connecting *is* a full backfill. Gate the pass on a "synced from" date set at connect time, and treat backfill as a separate explicit operation over the older range.

---

## Directions B and C: bodyweight

### What exists

Clean and ready: `BodyweightEntry` (`Data/Models/BodyweightEntry.swift`) is a plain model — `date`, `bodyweightKg`, `healthProfileId`, timestamps. `BodyweightService` is a small actor with straightforward CRUD. `BodyweightLogView` + `BodyweightLogViewModel` are the existing manual UI, and `Features/Onboarding/Views/BodyweightStepView.swift` collects it at onboarding.

Nothing about that code resists a Health source.

### What makes it harder than it looks

`BodyweightEntry` has **no source field**. Once entries can come from two places, you need to know which is which — otherwise you cannot dedupe, cannot resolve conflicts, and cannot avoid an echo loop where a write to Health triggers a read that creates a duplicate local entry that triggers another write.

That means a second additive property (`sourceRawValue: String?` or an `healthKitSampleUUID: UUID?`), and a rule. The simplest rule that works:

- **Health is the source of truth for anything Health knows about.** Repster-originated entries are written out (if C is enabled) and tagged with their HealthKit sample UUID.
- Entries arriving from Health that already carry a UUID Repster wrote are ignored on read — that breaks the echo loop.
- Same-day collisions from different sources: keep both, display the most recent. Bodyweight fluctuates within a day anyway; silently discarding a user's manual reading is worse than showing two.

### Onboarding interaction

`BodyweightStepView` asks for bodyweight during onboarding. If Health already has it, this step is friction. Tempting to offer "import from Health" there — **resist it**, because it puts a HealthKit permission prompt at first launch, which is exactly the mistake your own pre-launch list flags about notification permission. Onboarding stays manual; Health connects from Settings, later, deliberately.

---

## Permissions, privacy, and App Review

### Permission timing

Restating the brief's point because it's the single easiest way to get this wrong: **request authorization only when the user taps the connect toggle in Settings.** Never at launch, never at onboarding.

### HealthKit's authorization model is deliberately asymmetric

- For **write** types, `authorizationStatus(for:)` tells you the truth.
- For **read** types, it does not, and that's by design — an app must not be able to infer that a user is hiding data. `.notDetermined` and "denied" are indistinguishable from "authorized but empty".

Practical consequence for direction B: you can never show "Health has no weight data" with confidence. The honest UI is *"Nothing imported yet — check Settings › Privacy & Security › Health › Repster if you expected data here."*

### App Store rules that specifically bite

- **Guideline 5.1.3**: HealthKit data may not be used for advertising, marketing, or data mining, and may not be disclosed to third parties without explicit user consent.
- Apps with the HealthKit entitlement must have a privacy policy (you have one, served from Pages).
- HealthKit data must not be written to iCloud.

**The analytics interaction is worth a deliberate check, not an assumption.** Repster runs PostHog with session replay in screenshot mode (`Core/Services/AnalyticsService.swift:90-98`). The existing configuration is defensive — `maskAllTextInputs` masks every SwiftUI text layer (documented at `:82-88`), plus `maskAllImages` and `maskAllSandboxedViews`. On that reading, a bodyweight value read from Health and rendered on screen would be masked like any other text, and no Health data reaches PostHog.

That's almost certainly fine. Two things to do anyway:

1. **Verify it empirically** on a real recording of the bodyweight screen once Health data is flowing, rather than trusting the config comment. This is a 5.1.3 question, and 5.1.3 is not a guideline you want to be wrong about.
2. Make sure no analytics *event property* ever carries a Health-derived value. Nothing does today; it's the kind of thing that gets added casually later.

### Privacy label updates

`marketing/app-store/privacy-review-checklist.md` currently maps `Health & Fitness → Fitness`. Reading body mass adds the **Health** data type to that answer, and the checklist's per-data-type section plus the privacy policy copy both need a pass. The checklist already lists the repo files that must stay in sync — follow it.

---

## What this unlocks, and what it doesn't

**Unlocks:**

- The Watch app (item 4) — `HKWorkoutSession` is how a watch app stays alive during a session and gets heart rate. The brief is right that HealthKit should come first, and specifically that you want the *write* path settled before a second writer exists.
- Real energy and heart rate, later, via the Watch.
- Credibility. "Syncs with Apple Health" is a line on the product page and an objection removed at the point of download.

**Does not unlock, despite what people assume:**

- **Backup or cross-device sync.** Health is not a sync layer for your data. A user restoring to a new phone gets their `HKWorkout` shells back, not their sets, reps, PRs, templates, or fatigue history. Expect this misconception in reviews and be ready to say so plainly. The existing `WorkoutHistoryBackupService` remains the actual answer.
- **Importing other apps' strength workouts meaningfully.** Another app's `HKWorkout` is a duration and a calorie count. There are no sets or reps in it. Importing them would produce empty Repster workouts.

---

## Sizing

Assuming direction A only, no backfill:

| Piece | Size |
|-------|------|
| Entitlement + App ID + provisioning + TestFlight smoke build | S, but do it first and alone |
| `HealthKitService` (availability, auth request, write, delete) + protocol | S |
| `healthKitWorkoutUUID` on `Workout` + migration verification | S |
| Lazy sync pass + trigger points | S |
| Settings UI (Body section, connect state, not-connected state) | S–M |
| Energy estimate + its own toggle | S |
| Device QA | M — this is the underestimated one |

**Direction A ≈ M**, matching the brief. Adding B+C pushes it to **M–L**, mostly on sync-rule and conflict work rather than API work. D is not worth scoping until the Watch exists.

The Settings surface has an obvious home: `SettingsView.swift` already has a **Body** section (`:276-293`) containing the bodyweight log. Health belongs there, not in General.

---

## Recommended phasing

**Phase 0 — plumbing.** Entitlements file, App ID capability, provisioning, one Info.plist key, a build that ships to TestFlight and does nothing. Separate commit, separate build. This is the only part that can break the release pipeline, so isolate it.

**Phase 0 — ✅ done 2026-08-09.** Entitlements file, `CODE_SIGN_ENTITLEMENTS` on both configs, `NSHealthUpdateUsageDescription`. **Not yet exercised against a real provisioning profile** — the first device build is what registers the capability on the App ID.

**Phase 1 — ✅ done 2026-08-09.** Connect toggle in Settings › Body, authorization on tap, write hooked into `WorkoutService.finishWorkout`, `healthKitWorkoutUUID` on `Workout`, delete mirroring. Estimated energy landed here too rather than waiting for Phase 2. Build green, 307 tests passing. **Device QA still outstanding.**

**Phase 2 — backfill.** Explicit one-time backfill with a confirmation count. (The energy half of this phase shipped early with Phase 1.)

**Phase 3 — bodyweight both directions.** Source tagging, anchored query, echo-loop prevention, conflict rule.

**Phase 4 — deferred.** Heart rate and measured energy, when the Watch app arrives.

Phases 1 and 3 are independently shippable and independently valuable. Don't bundle them.

---

## Free or gated?

**Free**, and it isn't close. Three reasons:

1. HealthKit sync is table stakes for a paid fitness app — gating it reads as hostile rather than premium.
2. It's a *prerequisite* for the Watch app, and gating the foundation complicates gating the thing built on top.
3. "Syncs with Apple Health" is worth more as an App Store bullet than as a paywall line item.

This matches the brief's recommendation (share card, widgets, HealthKit free; guidance and deload gated with Insights).

---

## Open decisions

1. ~~**Direction A only for v1, or A+B together?**~~ **Decided: A only.**
2. ~~**Is `WorkoutService.swift` covered by the workout-logging constraint?**~~ **Resolved: the constraint is lifted.** Hook `finishWorkout` directly.
3. **Estimated energy: ship it, and is it opt-in?** Recommendation: ship it, separate toggle, default off, labelled "estimated". Note this is the "will my rings close?" question — worth settling even in a minimal v1.
3. **Does deleting a workout in Repster delete it from Health?** Recommendation: yes, silently — a mirror that doesn't mirror deletions is worse than no mirror. But it's a user-expectation call, and the opposite (leave it in Health, it's their Health data) is defensible.
4. **What happens on disconnect?** Leave previously written workouts in Health, or offer to remove them? Recommendation: leave them, with an explicit separate "Remove Repster workouts from Health" action.
5. **Bodyweight conflict rule** — the same-day, two-sources case. Recommendation above is "keep both"; the alternative is last-write-wins, which loses user data.
6. **Is Phase 0 blocked on anything on the developer-portal side** — who has access to enable the capability on the App ID and regenerate profiles?

---

## Risks, ranked

1. **Device-only QA.** HealthKit in the simulator is unreliable; permission flows and real data behaviour need a physical device throughout. This is the biggest schedule risk and the easiest to under-budget.
2. **Provisioning on a live app.** Adding an entitlement to a shipped app is routine but is a build-time failure mode, not a compile-time one. Isolating it in Phase 0 is the mitigation.
3. **Opaque read authorization** producing a UI that can't distinguish "denied" from "empty". Design for it up front rather than patching it after the first confused review.
4. **Estimated energy inflating users' Move rings and calorie budgets.** Opt-in and clear labelling are the mitigation.
5. **Echo loops in bidirectional bodyweight sync** — Phase 3 only, and the reason it's Phase 3.
6. **The "it's my backup" misconception.** A support and review-response problem, not an engineering one, but it will happen.
7. **5.1.3 / analytics.** Low, given the existing masking posture — but verify rather than assume.
