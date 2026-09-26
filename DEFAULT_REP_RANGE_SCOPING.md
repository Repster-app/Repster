# Default Rep Range — Scoping

**Date:** 2026-09-13
**Revised:** 2026-09-19 — every behaviour claim re-checked against the code. **Read §1.1 first:**
a rep range here is not double progression, and that is the single easiest thing to misread about
this change. Correction in §3.3 (the push option); additions in §3.2, §3.4, §5, §6, §8 and §11.
**Status:** Scoped, not built
**Target release:** 1.6
**Feature area:** Smart Suggestions
**Progression:** this change does **not** add a rep ladder — see §1.1. For the ladder, the cheaper
alternatives, and how they interact with this change, [PROGRESSION_LADDER_SCOPING.md](PROGRESSION_LADDER_SCOPING.md) is the source of truth.
Note the tension it records: its C3 argues the cheapest plateau fix is surfacing the range on the set
row, which is what Decision 5 here declined.
**Supersedes:** `DEFAULT_REP_RANGE_TECHNICAL_SCOPE.md` for the first release. That doc's double
progression, target materialization and engine-hardening sections are not part of this change.

## 1. Summary

When a set has no reps guidance, Smart Suggestions currently falls back to one number: **8 reps**.
This change makes the fallback a **range, 8–12**, and lets Settings offer either a **Range** or a
**Target**.

The range path already ships. Every template with a rep range uses it today. The only part of
Smart Suggestions that still assumes a single number is this fallback. So the change is to point the
fallback at the existing range path. It is not new engine work.

### 1.1 What a range is here — and what it is not

**A range is not a ladder.** The intuitive reading of "8–12" is double progression: you went to
failure at 9, so next time aim for 10, keep the weight, and add load once you clear 12. **That is not
what this engine does, and this change does not make it do that.**

What actually happens, from `repRangeCandidates` and `bestClosestMatchCandidate`
(`LoadPrescriptionServiceProtocol.swift:983` and `:1062`): for a range of 8–12 at RIR 2 the engine
builds five candidates — 8, 9, 10, 11, 12 reps — and prices each at the weight that would produce
*the same* effective e1RM. By the model all five are equally hard. They differ only in how much
rounding error the plate grid introduces, and the winner is the one with the smallest error.

Two consequences worth internalising before reading the rest of this doc:

- **The rep count is chosen by plate-grid rounding, not by training logic.** Whichever count lands
  nearest a real plate value wins. This is the actual reason F1's reps bounce 7, 8, 6, 7 (§3.3), and
  the reason a wide range looks broken (§5, Decision 7): across 30 candidates the pick is pure
  rounding noise, so consecutive sets can read 4 reps then 23.
- **Nothing remembers where you were in the range.** There is no stored rep position, so "failure at
  9 — so 10 next time" cannot happen. Progression comes only from e1RM moving up: hit 9 to failure
  and every candidate gets heavier next session, and the engine picks whichever now rounds cleanest
  — which may well be 8 reps at more weight, not 10 at the same weight. The only progression rule in
  the range path is `bestProgressedCandidate` (`:1076`), and it fires on **set 1 only**, picking the
  candidate that beats the recent peak by the *smallest* margin.

So the range buys two things: a cleaner landing on the weight grid, and a set-1 nudge above the
recent peak. It does not buy a rep ladder. This matters for copy (§8), for the push option (§3.3),
and for anyone reviewing the behaviour tables and expecting to see reps climb.

## 2. What already works

| Piece | Where | Status |
|---|---|---|
| Range candidate search (one candidate per rep count, pick best fit) | `SuggestionEngine.evaluate`, `LoadPrescriptionServiceProtocol.swift:856` | Shipped |
| First-set progression above recent peak | same, `:867` | Shipped, range-only |
| Card shows the concrete prescription ("58.75 kg for 9 reps") | `SetSuggestion.prescribedDisplayLabel` | Shipped (P1 fix, 2026-08-26) |
| Push option at the top of the range, RIR 0 | `pushOption`, `:963` | Shipped |
| Unilateral total-across-sides range normalization | `normalizedTargetRepRange`, `WeightSuggestionData.swift:684` | Shipped |
| Fixed target when both bounds are equal | `makeRepRange` requires `min < max` | Shipped |

The one single-number path is `normalizedDefaultTargetReps` (`WeightSuggestionData.swift:652`). It
feeds the `.smartDefault` branch of `resolveTarget` and always leaves `displayRepRange` nil, which
sends every default-guided set down the fixed-target path.

## 3. Behaviour

### 3.1 Precedence — unchanged

```text
workout-local target > reps already on the set > template target > profile default
```

Only a set with none of the first three receives the default.

### 3.2 Which sets the default reaches

| Set | Gets the default? | Why |
|---|---|---|
| Added with Add Set in an ad-hoc workout | **Yes** | Created with `reps: nil` (`ActiveWorkoutViewModel.swift:819`) |
| Template set with no rep target | **Yes** | Nothing above the default in the precedence |
| Template set with a target | No | Template target wins, as today |
| Set where the user typed reps | No | Typed reps are an explicit target, as today |
| Row created by **Copy Previous** | **No** | Copies `reps` and `rir` from the source set (`ContentView.swift:710`), so both count as explicit |
| **Warmup** set | **No** | Warmups never reach the suggestion path at all (`WeightSuggestionData.swift:386`) |
| **Drop set, AMRAP, failure, partial, cluster, rest-pause, myo, back-off, tempo, isometric** | **Yes** | Only `.warmup` is filtered. Set type is changed on an existing row (`ActiveWorkoutViewModel.swift:949`), so a row added with `reps: nil` and then retyped still carries the default |

Copy Previous rows keep today's fixed-target behaviour. See §8.

**The non-working set types are in scope and get the range.** They already take today's fixed 8, so
this is not a new population — but it is a wider one than "ad-hoc working sets", and worth naming.
The interesting case is **AMRAP**: a range is a search space for *one* prescribed rep count, which is
exactly what an AMRAP row is not. Today it gets a fixed 8; after this change the card names a count
inside 8–12 chosen for best fit. No worse, no better. Decision 6 asks whether to leave it.

### 3.3 What users will notice

For a default-guided set, the range path now runs where the fixed path ran before:

- **Suggestions can move up.** At a fixed target the weight is the exact inverse of the formula that
  produced the e1RM, so it repeats the last performance indefinitely. With a range, set 1 can pick a
  rep count whose implied e1RM beats the recent peak. It only does this when the set has recent
  history and the closest-fit candidate doesn't already beat that peak.
- **Reps vary from set to set.** Golden master F1 (5–8): 77.5×7, 72.5×8, 75×6, 72.5×7. The
  2026-08-26 behaviour audit ruled this consistent (effective e1RM falls every set: 100 → 96.6 →
  95.1 → 94.4), not a bug. Today only template-range users see it. After this change, most ad-hoc
  users will.
- **The push option often disappears, or stops being heavier.** This one is a regression, not a
  win. `pushOption` (`LoadPrescriptionServiceProtocol.swift:954`) always takes the *top* of the range
  at RIR 0, and suppresses itself when the result would be lighter than what was prescribed — calling
  a lighter set a push would be a lie. Weight is priced off total reps (reps + RIR), so with the
  shipped default RIR of 2 and a range of 8–12, at 100 kg effective e1RM on a 2.5 kg grid:

  | Chosen reps | Prescribed | Push (12 @ RIR 0) | Result |
  |---|---|---|---|
  | today, fixed 8 | 8 @ RIR 2, total 10 → 75 kg | 8 @ RIR 0, total 8 → 80 kg | heavier, as today |
  | 8 | total 10 → 75 kg | total 12 → 72.5 kg | lighter, so **no push option at all** |
  | 10 | total 12 → 72.5 kg | total 12 → 72.5 kg | **same weight**, two more reps |
  | 11–12 | total 13–14 → 70 / 67.5 kg | total 12 → 72.5 kg | heavier, as intended |

  So the push is only the "12 reps at RIR 0, and heavier" offer this section originally claimed when
  the engine picks near the top of the range. Pick the bottom and the affordance vanishes; pick the
  middle and it offers the same weight for more reps. Template-range users already live with this,
  which is why it is not a blocker — but today *every* default-guided set has a heavier push, and
  after this change most will not. Decide before building: accept it, or have the push fall back to
  "chosen reps at RIR 0" when the top-of-range push would be lighter. The fallback is a few lines in
  `pushOption` and restores today's behaviour for the 8-reps case, but it changes template-range
  output too, so it belongs with the §9 fixes and the golden-master regeneration. Decision 10.

### 3.4 Presentation — no change expected

The card already prints the concrete prescription ("60 kg for 10 reps"), not the range. The
explanation already labels the source "Smart Suggestions default". Template ranges already render
through this same path, so no card or explainer changes are planned. Confirm this during the device
pass.

Two caveats, both checked:

- **The admin diagnostics do change shape**, and they are gated behind
  `prescriptionAdminModeEnabled`, so no user sees them. The Alternatives table goes from four rows
  (`chosenReps ... +3`) to one row per rep in the range — five for 8–12 — and its header from
  "(x..x+3)" to "(8–12)" (`WeightSuggestionData.swift:980`, `WeightSuggestionCardView.swift:416`).
  On a total-across-sides exercise the admin summary's normalization line becomes "normalized to 4–6
  reps each side". Expect both in any admin-mode screenshot comparison.
- **No new user-facing copy, but newly reachable copy.** "Nudging up from your last workout's peak."
  (`WeightSuggestionData.swift:904`) fires on `.firstSetProgressionAboveRecentPeak`, which is exactly
  the §3.3 upside — so a line most ad-hoc users have never seen becomes common. The fallback line
  reads "Based on your recent performance for this rep target." (`:910`), singular, where the target
  is now sometimes a range. Neither needs a code change; both are worth reading on the device
  pass.

## 4. Data model

### 4.1 New fields

Add to `HealthProfile`, and mirror in `HealthProfileSnapshot` (`ChartSetData.swift`):

```swift
var prescriptionDefaultTargetRepMin: Int?
var prescriptionDefaultTargetRepMax: Int?
```

Both default to **nil**. A fixed target is stored as `min == max`. No mode field is needed, because
the engine already treats equal bounds as a fixed target.

Optional scalar fields go through the existing implicit lightweight migration. The container
deliberately has no `migrationPlan` (`ModelContainerSetup.swift:39`).

The snapshot drift guard `testHealthProfileSnapshotCoversEveryStoredProperty`
(`RepsterTests/LiveModelRaceReproTests.swift`) will fail until both fields are mirrored. That is
intended.

### 4.2 One resolver, read-time, no backfill

```swift
enum DefaultRepGuidance: Equatable {
    case range(ClosedRange<Int>)
    case fixed(Int)
}

extension HealthProfileSnapshot {
    static let appDefaultRepRange = 8...12

    var defaultRepGuidance: DefaultRepGuidance {
        // 1. Anything saved from the new Settings control wins.
        if let min = prescriptionDefaultTargetRepMin,
           let max = prescriptionDefaultTargetRepMax,
           1 <= min, min <= max, max <= 30 {
            return min == max ? .fixed(min) : .range(min...max)
        }
        // 2. A legacy value the user changed away from 8 is kept as a Target.
        if let legacy = prescriptionDefaultTargetReps, legacy != 8, (1...30).contains(legacy) {
            return .fixed(legacy)
        }
        // 3. Everyone else follows the app default.
        return .range(Self.appDefaultRepRange)
    }
}
```

Both Smart Suggestions and Settings use this function. Nothing else interprets the fields.

Why no backfill:

- **nil means "app default".** Users who never touch Settings follow whatever the app default is. A
  future change to the default is then a one-line code change, with no data migration. Note that the
  *new* fields are the only ones ever nil in practice: `HealthProfile.init` defaults the legacy field
  to 8 (`HealthProfile.swift:105`) and `fetchOrCreate` backfills nil to 8
  (`HealthProfileRepository.swift:35`). So every real user reaches 8–12 through rule 3 by way of a
  legacy `8`, never through a nil legacy value. Rule 3's nil case is a belt, not the road.
- **Legacy 8 is treated as the default.** Onboarding writes 8 for every user
  (`OnboardingViewModel.swift:158`), and `HealthProfileRepository.fetchOrCreate` backfills nil to 8,
  so a deliberate 8 can't be told apart from the default. Both move to 8–12.
- **A customised legacy value is kept.** Someone who set 6 or 10 sees **Target: 6** or **Target: 10**
  in Settings and keeps fixed-target behaviour until they switch.
- **No writes happen on a read.** This keeps the change out of the SwiftData write paths that have a
  crash history.

`prescriptionDefaultTargetReps` stays as it is. It is not renamed, removed or rewritten.

An invalid legacy value (outside 1...30) currently resolves to no target, so Smart Suggestions shows
nothing. Under this rule it resolves to the app default instead. The service already clamps, so the
UI can't produce an invalid value.

## 5. Settings: Range or Target

Replace the "Default Reps" stepper in `SmartSuggestionsAdvancedSections`
(`PrescriptionSettingsView.swift:78`) with:

```text
Default Reps        [ Range | Target ]

Range:   Minimum   8   (−/+)      1 ... max−1
         Maximum  12   (−/+)      min+1 ... 30

Target:  Reps      8   (−/+)      1 ... 30
```

The bounds above are the loose version, which allows a 1–30 range. Decision 7 recommends also
capping the spread at 6, which lands here as `max(1, min − 6) ... max − 1` on the minimum and
`min + 1 ... min(30, min + 6)` on the maximum. Nothing service-side changes either way.

**Seeding the controls on open.** `SmartSuggestionsAdvancedSections.init` seeds its state from
`profile.prescriptionDefaultTargetReps ?? 8` (`PrescriptionSettingsView.swift:37`). That is wrong
under the new rule: a user with a nil or 8 legacy value would open Settings on **Target 8** while
Smart Suggestions is using **8–12**. The init must seed mode and both bounds from
`profile.defaultRepGuidance`, with a third `@State` for the mode.

**Seeding when switching mode**, so a round trip returns to where the user started:

- Target N → Range: lower = min(N, 26), upper = lower + 4. For example, 8 becomes 8–12.
- Range → Target: the lower bound. For example, 8–12 becomes 8.

**Saving:** one atomic call writes both bounds together:

```swift
func updatePrescriptionDefaultRepTarget(min: Int, max: Int) async throws -> HealthProfileSnapshot
```

- Accepts `1 <= min <= max <= 30`. `min == max` is a Target.
- Rejects anything else with a thrown error rather than clamping. Its neighbours in
  `SettingsService` clamp, but two bounds can't be clamped into a valid order without guessing. The
  controls can't produce an invalid pair anyway.
- Writing both bounds in one call means a half-updated pair is never stored. The resolver leans on
  this: rule 1 requires *both* new fields, so even a torn pair falls through to the legacy rule rather
  than resolving to something half-chosen.

**What throwing costs, and who catches it.** This needs deciding before the method is written, because
it cuts against the pattern in the file:

- No other `SettingsService` method throws a validation error — every neighbour clamps
  (`SettingsService.swift:87-107`). There is no `SettingsServiceError` type today, only
  `SettingsResetError`, so this introduces one.
- Every control in this section saves fire-and-forget: `Task { _ = try? await settingsService... }`
  on `onChange` (`PrescriptionSettingsView.swift:88`, `:101`). Under `try?` a thrown error is
  silently dropped and the local `@State` keeps a value the store never took, so the screen and the
  engine disagree until the view is rebuilt.
- `onChange` fires once per stepper tick, so walking the maximum from 8 to 12 is four writes. The
  call is atomic per write, not per gesture. That is fine — every intermediate pair is valid, because
  the stepper bounds keep `min < max` throughout — but "atomic" should not be read as "one write per
  edit session".

Since the controls cannot produce an invalid pair, the cheapest coherent answer is to treat the throw
as a programmer-error assertion and leave the view on `try?`. If it is meant to be recoverable, the
view has to reseed from the returned snapshot on failure. Decision 8.

**Footer copy** (draft): *"Used when a set has no reps or RIR of its own. With a range, Smart
Suggestions picks the rep count in the range that best fits today. With a target, it always plans
for that many reps."*

Two things about that footer. It is a **section** footer covering Default Reps *and* Default RIR, not
a row footer, so the draft still has to carry the RIR case: the shipped copy ends "Smart Suggestions
will fill only the missing piece", which is the point that a set missing only RIR keeps its own reps,
and dropping it loses real information. And it is **duplicated in both branches** of the
`if let firstSectionTitle` (`PrescriptionSettingsView.swift:62` and `:68`), so both copies change or
the two entry points disagree.

**Range width.** Each stepper allows 1...30 against the other bound, so `1–30` is reachable and
nothing downstream caps the spread: `makeRepRange` only requires `min < max`, and
`repRangeCandidates` builds one candidate per rep.

The reason to cap it is §1.1: every candidate in the range targets the same e1RM, so the pick is
decided by plate-grid rounding alone. Across 5 candidates that is a small, tolerable wobble — F1's
7, 8, 6, 7. Across 30 it is noise, and consecutive sets can read 4 reps then 23. Both are "correct"
by the model and both look broken on screen. A template range is authored per exercise, deliberately,
by someone who wants that spread; this one applies everywhere by default. Decision 7.

**Onboarding:** no change. It still writes legacy 8, which resolves to 8–12. The old
`updatePrescriptionDefaultTargetReps` method stays for that caller.

## 6. Suggestion resolution

All of these changes are in `WeightSuggestionData.swift`:

1. Replace `normalizedDefaultTargetReps` with `profile?.defaultRepGuidance`.
2. In `resolveTarget`, the `.smartDefault` branch:
   - `.range(r)`: `displayReps` = midpoint of `r` (10 for 8–12), source `.smartDefault`.
   - `.fixed(n)`: behaves exactly as today.
3. In the `displayRepRange` selection (`:471`), give `.smartDefault` its range the same way
   `.template` gets `templateRepRange`.
4. Cache key (`:580`): replace `defaultReps\(… ?? 8)` with the resolved guidance, for example
   `defaultReps8-12` or `defaultReps10`. Changing either bound must re-evaluate the suggestion.
   This is belt-and-braces: the per-set resolution signature (`:560`) already appends
   `displayRng<lo>-<hi>` whenever `displayRepRange` is non-nil, so a bound change already invalidates
   the key through that path. Do both anyway — the profile signature is the one that reads as
   deliberate. Nothing to invalidate on upgrade: the key lives in memory only
   (`suggestionsLoadedForKey`, `ActiveWorkoutViewModel.swift:2268`).

Default RIR resolution is untouched.

**Unilateral:** a total-across-sides exercise normalizes 8–12 to 4–6 per side. A narrow custom
range can collapse (9–10 total becomes 5–5 per side) and falls to the fixed path. Template ranges
already behave this way, and this change accepts the same behaviour.

## 7. Files

| File | Change |
|---|---|
| `Repster/Data/Models/HealthProfile.swift` | Two optional fields, default nil |
| `Repster/Core/Services/ChartSetData.swift` | Mirror in `HealthProfileSnapshot`; `defaultRepGuidance` |
| `Repster/Core/Services/Protocols/SettingsServiceProtocol.swift` | `updatePrescriptionDefaultRepTarget(min:max:)` |
| `Repster/Core/Services/SettingsService.swift` | Validate and persist both bounds atomically |
| `Repster/Features/Settings/Views/PrescriptionSettingsView.swift` | Range / Target control |
| `Repster/Features/Workout/Models/WeightSuggestionData.swift` | Resolver, range for `.smartDefault`, cache key |

Test doubles that need the new protocol method: `SetServiceTests.swift:2169`,
`ActiveWorkoutViewModelSuggestionRefreshTests.swift:5024`, and
`WorkoutHistoryBackupTests.swift:2257`, `:2317`, `:2359`.

**Not touched:** the suggestion engine, `HealthProfileRepository`, `OnboardingViewModel`, the set and
template models, and the template, workout and backup archive formats.

## 8. Out of scope

- **Copy Previous rows.** They copy reps and RIR, so the default never applies to them. Treating
  copied reps as a softer hint than typed reps would be a separate change.
- **Stable reps across sets.** Reps can vary from set to set (§3.3). A "hold one rep count per
  exercise" rule is a separate change, and should be designed together with any future ladder.
- **Double progression.** The range is a search space, not a ladder. Don't describe it as double
  progression in copy or marketing.
- **Per-exercise defaults.**
- **Recording the default on completed sets.** Ad-hoc sets still won't feed `TargetAdherenceInsightRule`.
- **Backing up the setting.** The profile default isn't in the workout backup today, and still won't
  be. Confirmed: the archive carries only the three fatigue-learning fields
  (`WorkoutHistoryArchiveHealthProfileLearning`, `ExportServiceProtocol.swift:361`).
  `resetAllAppData` deletes the `HealthProfile` outright (`SettingsService.swift:153`), so the new
  fields reset to nil by construction and need no reset branch.
- **Instrumenting it.** Nothing in this Settings section emits an analytics event today, and this
  change adds none. So a shift §3.3 predicts will reach most users stays invisible in the PostHog
  dashboards: no way to see whether anyone moves off 8–12, or whether suggestion acceptance moves
  with it. Accepting that is fine — it should be a decision rather than an omission. Decision 9.

## 9. Optional: two midpoint fixes

These are two existing inconsistencies in the range path. Both already affect template-range users.
With this change they would affect most ad-hoc users too. Each is a few lines. The change ships
without them.

1. **Fatigue projection** (`LoadPrescriptionServiceProtocol.swift:831`). A later pending set's
   fatigue is projected from `prev.targetReps`, the range midpoint, rather than the reps the
   previous suggestion actually prescribed. Fix: `decisions[pendingIndex - 1].bestReps ?? prev.targetReps`.
2. **Suggestion floor** (`:891`, `:1245`). The floor compares completed-set capacity against
   `target.reps` (the midpoint), not the chosen reps. Fix: pass `bestReps ?? target.reps` into
   `suggestionFloor`.

Both fixes change engine output for range scenarios, including golden master F1. If they're
included, regenerate the golden master deliberately and diff the behaviour-harness tables. The
fixture is `RepsterTests/Fixtures/SuggestionEngineGoldenMaster.txt`, written by
`SuggestionEngineGoldenMasterTests` — a class inside
`RepsterTests/SmartSuggestionBehaviorScenarioTests.swift:500`, not a file of its own.

F1's current rows, for the diff: 77.5×7, 72.5×8, 75×6, 72.5×7, with effective e1RM 100 → 96.55 →
95.05 → 94.40.

## 10. Tests

**Resolver** (`defaultRepGuidance`):
- nil/nil with legacy 8 or nil → 8–12.
- Legacy 10 → fixed 10.
- Saved 6–10 → range. Saved 10–10 → fixed 10.
- Invalid saved pair → falls through to the legacy rule.
- Invalid legacy value → 8–12.

**Target resolution** (`resolveTarget`):
- No guidance → range 8–12, `displayReps` 10, source `.smartDefault`.
- Typed reps, a workout-local override, a template range and a template fixed target each beat the default.
- A fixed default takes the fixed path. A range default takes the range path (`bestReps` non-nil).
- Total-across-sides 8–12 → 4–6.
- Cache key changes when either bound changes.
- Update the existing test that sets the legacy field to 0 (`ActiveWorkoutViewModelSuggestionRefreshTests.swift:3281`) to the new rule.

**Settings service:**
- A valid range persists; equal bounds persist as a Target.
- Reversed or out-of-domain pairs throw and leave both previous values intact.
- `updatedAt` moves on success.

**Settings view:**
- Target 8 → Range 8–12 → Target 8 round trip.
- A legacy 10 shows as Target 10; a legacy 8 and a legacy nil both open on **Range 8–12**, not
  Target 8. This is the seeding fix in §5 and the easiest thing to get wrong.
- If Decision 7 lands, the steppers cannot produce a spread wider than 6 from either direction.

**Regression:** snapshot drift guard (`testHealthProfileSnapshotCoversEveryStoredProperty`; a
computed `defaultRepGuidance` in an extension will not trip it, because `Mirror` reports only stored
properties); `SmartSuggestionBehaviorScenarioTests`; `SuggestionEngineGoldenMasterTests` and its
fixture; `OnboardingCompletionTests`.

Both harnesses are **expected unchanged unless §9 is included**, and that is structural rather than
lucky: the golden master builds engine inputs directly via `pending(count:reps:rir:repRange:)` and
never goes through `resolveTarget`, so the profile default cannot reach it. If either harness moves
without §9, something resolved differently than this doc predicts — investigate rather than
regenerate.

Run the suite once, into a log.

**Upgrade:** open a copied 1.5 store in the new build; confirm the new fields read as nil and the
profile resolves to 8–12.

**Device pass:**
- A fresh install gets 8–12.
- An upgrade with legacy 8 gets 8–12.
- An upgrade with a custom legacy value shows it as a Target.
- An ad-hoc workout with history shows a set-1 suggestion that can move up.
- Copy Previous is unchanged.

## 11. Decisions

| # | Decision | Recommendation |
|---|---|---|
| 1 | Default range | 8–12 |
| 2 | Settings control | Segmented Range / Target with steppers (matches the template editor's two bounds). A preset menu (5–8, 8–12, 12–15 …) is the alternative. |
| 3 | Mode-switch seeding | Target N → N…N+4; Range → lower bound |
| 4 | Include the §9 midpoint fixes | **Yes** (decided 2026-09-19). They ship with this change, so the golden master is regenerated once, deliberately. |
| 5 | Show "8–12" as the reps placeholder on default-guided sets | **No** (decided 2026-09-19). We don't surface the profile default on set rows today and shouldn't start. The placeholder stays set-and-template only, falling back to "0" (`SetTableView.swift:995`); `SetTableView` does not learn about the profile. |
| 6 | Let the range reach AMRAP and the other non-working set types (§3.2) | Yes. They already take today's fixed 8, and carving them out means a set-type list in the resolver that nothing else needs. Revisit if AMRAP ever gets real handling. |
| 7 | Cap the range width (§5) | **Yes** (decided 2026-09-19), spread capped at 6: 8–14 allowed, 1–30 not. Reason is §1.1 — the pick is plate-grid rounding, so a wide range is noise, not choice. Stepper bounds only, no service-side rule. |
| 8 | Recoverable throw, or programmer-error throw, on an invalid pair (§5) | Programmer-error. The controls cannot produce one, and the view's `try?` pattern cannot surface it anyway. Revisit only if the controls stop constraining each other. |
| 9 | Instrument the change (§8) | No event for 1.6. Accept that the shift is invisible in the dashboards; the behaviour harness is the evidence, not analytics. |
| 10 | Fall back to "chosen reps at RIR 0" when the top-of-range push would be lighter (§3.3) | Open, and the one decision with a user-visible downside either way. It restores today's push for the bottom-of-range case but changes template-range output, so it ships with §9 or not at all. |

## 12. Size and done

Roughly **1–2 days including tests**, plus the device pass. Add about half a day if §9 is included.

**Done means:**

- A fresh or default user gets 8–12.
- A customised legacy user keeps their number as a Target.
- Settings switches cleanly between Range and Target, and opens on whatever Smart Suggestions is
  actually using.
- The push option's behaviour on a default-guided set is a decision someone made, not a surprise.
- The suite is green.
- The copied-store upgrade and the device pass are done.
