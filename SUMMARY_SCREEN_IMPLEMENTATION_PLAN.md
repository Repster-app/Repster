# Workout summary screen — implementation plan

**Date:** 2026-09-01 · **Branch:** `NewMain` · **Status:** W1–W7 built, unreviewed on device.

Designs: [artifact](https://claude.ai/code/artifact/7c16dfee-a130-413c-a3c6-c5757a608416) ·
artboards in `design/summary-card/`.

**Built 2026-09-01: W1–W7.** App target builds clean; the five new tests pass. Open decision 1
is answered below. Remaining: decisions 2–6, and a device pass.

Covers the rebuild of `WorkoutSummarySheet` and the shareable card that hangs off it.
Related: [SHARE_CARD_FEATURE_DESIGN.md](SHARE_CARD_FEATURE_DESIGN.md) (share scope),
[REPSTER_COACH_SCOPING.md](REPSTER_COACH_SCOPING.md) (§5.3 R4, the tone rule),
[COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md).

---

## 1. The finding that reorders this work

**Notes and effort are dead UI on this screen today.** Both are fully wired end to end, and
neither is reachable.

- `notesSection` ([WorkoutSummarySheet.swift:331](Repster/Features/Workout/Views/WorkoutSummarySheet.swift#L331))
  and `effortSection` ([:372](Repster/Features/Workout/Views/WorkoutSummarySheet.swift#L372))
  are defined but never called. The body renders exactly four things
  ([:95–105](Repster/Features/Workout/Views/WorkoutSummarySheet.swift#L95)): `recapHero`,
  `exerciseRecapSection`, `suggestionFeedbackSection`, `secondaryActionsSection`.
- The save still passes both
  ([:763–767](Repster/Features/Workout/Views/WorkoutSummarySheet.swift#L763)) into
  `finishWorkout(title:notes:perceivedEffort:)`
  ([ActiveWorkoutViewModel.swift:2382](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift#L2382)).
  `.onAppear` loads existing values, so nothing is destroyed — they round-trip. They simply
  cannot be **entered or changed** from this sheet.

Two consequences:

1. **`deloadReadiness` is starved.** `InsightRules+Readiness` is the only reader of
   `perceivedEffort` ([:153, :156](Repster/Core/Services/InsightRules+Readiness.swift#L153)).
   If effort has been unreachable since the "layered single sheet" redesign, that rule has had
   no new input since. **Worth confirming against real data before anything else here** — it
   changes whether this is a restoration or a new feature.
   **Answered 2026-09-01: it is a bug, and an old one.** `git log -S "effortSection"` returns a
   single commit — the one that introduced the declaration — and in that commit
   (`045b10b`, 2026-05-02) the body already rendered only the four other sections. So the
   effort input has never been reachable in this design, and `deloadReadiness` has never had
   an input from this screen. Historical `perceivedEffort` values, if any, predate it.

2. **The count in REPSTER_COACH_SCOPING §5.3 is high.** It says the sheet asks for six things.
   As built it asks for three: title (inline in the hero), save-as-template and discard
   ([:636](Repster/Features/Workout/Views/WorkoutSummarySheet.swift#L636)) — plus suggestion
   feedback, which only renders for wand users with predictions. The doc's conclusion (*less,
   not more*) still holds; its arithmetic does not.

So "Add details" is not a decluttering exercise. It **restores two inputs that are currently
unreachable** and unblocks a shipping Insights rule. That is the strongest reason to build it,
and it should be said out loud in the PR.

---

## 2. Target screen

`design/summary-card/SumV4.dc.html`, with `ScreenDetails.dc.html` behind the row.

| Region | Contents |
|---|---|
| Header | Close · "Workout complete" · **Share** (gold-tinted when `prsHit > 0`) |
| Recap card | Date, editable title, three stat tiles (time / sets / volume), calorie line |
| Exercises card | One row per exercise, name + PR marker, **no weights or set counts** |
| Coach | "Analyse with Coach" — **unbuilt teaser**, `Soon` pill, not tappable |
| Add details | One row → notes, effort, suggestion feedback, save as template |
| Action bar | Discard (outlined, destructive) · Save & Close (primary) |

Layout clears the 780 pt frame by roughly 75 pt at five exercises, which is the headroom a
nine-exercise session needs. The earlier "everything visible" variant did not have it.

---

## 3. Work packages

Ordered so each lands independently.

### W1 — Recap card restructure · **S**

Replace `recapHero`'s three-tile row with the tile group plus calorie line. Drop the
`prominent:` flag from `compactSummaryMetric`; the accent tile on Time was the original
complaint and nothing replaces it.

- Keep `WorkoutPrimaryMetric.formattedValue(style:unitPreference:)` for the volume cell — it
  already handles metric/imperial and the volume/distance/duration split.
- Split value from unit in the volume tile so long figures stop hitting
  `minimumScaleFactor`.
- Title becomes tappable-to-edit; remove the separate pencil button from the top-right.

### W2 — Exercise list without amounts · **S**

`exerciseSummaryRow` currently renders name + set count + PR tag. Drop the set count, keep
name + PR marker. Row height goes ~35 → ~30 pt, which is what pays for W3 fitting on one
screen.

### W3 — Add details screen · **M**, the core of this plan

A push inside the existing sheet (`NavigationStack` inside the sheet) containing:

| Field | State | Note |
|---|---|---|
| Notes | `notesSection` exists at `:331` | Un-orphan it. No new code. |
| Effort 1–10 | `effortSection` exists at `:372` | Un-orphan it, but replace the popover with the inline 1–10 grid at 44 pt targets. |
| Suggestion feedback | `suggestionFeedbackSection` at `:519` | Move off the main sheet unchanged. |
| Save as template | In `secondaryActionsSection` at `:636` | Move; keep `SaveWorkoutAsTemplateController` as is. |

Discard does **not** move — it stays on the main sheet per the brief.

**Open decision:** push inside the sheet (drawn) or a second sheet. A push keeps one dismissal
gesture for the whole flow; a separate sheet reads as more optional. Push is the cheaper build.

### W4 — Action bar · **S**

`saveActionBar` ([:685](Repster/Features/Workout/Views/WorkoutSummarySheet.swift#L685)) gains a
Discard button beside Save. The confirmation alert already exists
([:131](Repster/Features/Workout/Views/WorkoutSummarySheet.swift#L131)) so a misfire is
recoverable — but adjacent destructive-plus-primary is the layout where a tired thumb picks
wrong. If that reads as too risky, the fallback is Discard as a text button *below* Save.

### W5 — Coach teaser · **XS**

Non-interactive card, dashed accent border, muted spark, `Soon` pill. No tap target, no
navigation, no placeholder screen behind it.

Copy: **Analyse with Coach** / *What changed, and what's next*.

Two things to hold to:

- It must not be tappable. A teaser that opens a "coming soon" screen is worse than one that
  plainly is not a button.
- Ship it behind a build flag or a remote kill so it can be pulled if Coach slips. A permanent
  "Soon" is a broken promise, and per §2.5 the coach cannot initiate — it has exactly one
  moment to be credible.

**This also resolves the R4 tension.** R4 caps the sheet at one positive-only line because a
verdict handed to a tired lifter reads as a grade. A button the user taps is not a verdict, so
the sharper coaching — a stall, a session-order cost, an honest projection — can live on the
screen the tap leads to while the sheet stays inside the rule.

### W6 — Calories · **XS**

`HealthKitService.estimatedKilocalories(bodyweightKg:start:end:)`
([:221](Repster/Core/Services/HealthKitService.swift#L221)) is `static` and pure. Call it
directly; do not reimplement.

Three constraints the design already accounts for:

- **It returns `nil` with no bodyweight logged**, and `writesEstimatedEnergy` defaults to
  `false` ([AppleHealthSettingsView.swift:12](Repster/Features/Settings/Views/AppleHealthSettingsView.swift#L12)).
  So it is absent for a large share of users — hence a quiet line under the tiles, not a fourth
  tile leaving a hole.
- **Do not substitute an average bodyweight.** That was considered and rejected at
  [:193–199](Repster/Core/Services/HealthKitService.swift#L193): *an absent number is better
  than a wrong one*. Same rule applies on screen.
- **It is duration wearing a different hat.** `MET × bodyweightKg × hours` with MET fixed at
  3.5 ([:67](Repster/Core/Services/HealthKitService.swift#L67)) means 64 minutes of heavy
  triples and 64 minutes of light curls give the same figure. Label it as an estimate. The fix
  is named in the file itself ([:64](Repster/Core/Services/HealthKitService.swift#L64)):
  scale by `perceivedEffort` between ~3.5 and ~6.0 — which W3 makes possible for the first
  time.

**Decided:** the on-screen figure is independent of `HealthKitPreferences.writesEstimatedEnergy`
and gated only on a logged bodyweight. Reasoning below, kept because it is the kind of choice
that gets silently reversed later.

**The question was:** whether the on-screen figure should respect the HealthKit *write*
toggle at all. They are different questions — "show me my estimate" and "put this in my Move
ring" — and reusing one flag for both means a user who declines the Health write also loses the
number on their own summary. Recommend a separate display default of on, gated only on
bodyweight.

### W7 — Share the card · **M–L**, mostly new code

Nothing exists yet: **no `ImageRenderer` and no `ShareLink` anywhere in the codebase.**

Per [SHARE_CARD_FEATURE_DESIGN.md](SHARE_CARD_FEATURE_DESIGN.md):

- **Placement (B2).** Share button on the summary sheet **before** Save & Close. This ordering
  is forced, not chosen: `finishWorkout()` sets `self.workout = nil` and the sheet dismisses on
  `isWorkoutFinished`, so there is no post-save moment to hang it on without restructuring the
  finish flow. The design puts it in the header, tinted gold when `prsHit > 0`, which satisfies
  B2's "visual weight follows the achievement" without a second competing button.
- **Card (B3).** One layout, 9:16, 1080×1920 — which is 360×640 pt at @3x, the size the
  artboards are drawn at. PR headline when there is one; three stats; footer with date,
  wordmark and URL, always present and never removable.
- **Privacy (B4).** Two toggles persisted in `UserDefaults`: hide exercise list, hide weights.
  `design/summary-card/OptionO.dc.html` is the hide-weights state drawn out — the achievement
  is carried by the lift name and type size, so nothing has a hole where a number used to be.
- **Purity (C3).** The card view must be pure — no service or environment dependencies — or
  `ImageRenderer` will not produce a stable image.

New work beyond the doc:

1. A `ShareCardView` taking a plain value type, no environment.
2. `ImageRenderer` at `scale: 3`, written to a **named PNG file** in a scratch directory and
   shared by URL.

   **Format decided: PNG, as a file, not an in-memory `Image`.** SwiftUI's `Image` advertises
   `["public.png", "public.jpeg"]`, so PNG is what destinations take either way — and PNG is
   the right call on the merits: the card is flat colour and type, so it encodes to ~94 KB
   against ~126 KB as JPEG at q0.9, and stays lossless for a destination that will recompress
   it anyway. Sharing the *file* rather than the image buys a readable filename
   (`Repster-Push-Day-A-Sat-Aug-30.png`) in Files and Mail, and better behaviour from share
   extensions that handle a URL more reliably than a SwiftUI `Image`. The workout title becomes
   a path component, so it is sanitised and capped.

   **Share the file through a `Transferable` that declares `.png`, never the bare `URL`.**
   A `URL` advertises `["public.url", "public.file-url"]` and nothing else, which silently
   removes Photos and every app target from the share sheet and leaves "Save to Files" as the
   only destination. `WorkoutShareCardFile` declares `FileRepresentation(exportedContentType:
   .png)` with a `suggestedFileName`, so it advertises `["public.png"]` — an image type — and
   keeps the filename. `testAdvertisesAnImageTypeSoPhotosAndAppsAppear` locks it.

   **Save to Photos built.** A dedicated button above Share, so the common destination is one
   tap. `WorkoutShareCardPhotoSaver` requests `.addOnly` authorisation — the lighter Photos
   prompt, and honest, since the app never reads the library —
   and `NSPhotoLibraryAddUsageDescription` is declared in `Repster/Info.plist`. A missing key is
   a hard crash on first tap rather than a degraded feature, so
   `testPhotoLibraryAddUsageDescriptionIsDeclared` asserts it is present *and* that the broader
   read-access key is not. Denial routes to an alert offering Settings, and Share still works.

   **Card styles built 2026-09-04.** Four: Record (the PR), Muscles (volume split as a ring),
   Volume (one number at 96 pt) and Session (every set as a bar, in order, coloured by muscle,
   gold diamond on a record). Swipeable in the preview sheet, with the choice remembered in
   `WorkoutShareCardPreferences.style` — which is how a picker stays compatible with B3's
   objection: it is browsed once, not answered every time. `availableStyles` hides any style the
   session cannot fill, so a swipe never lands on a blank card.

   Muscles and Session are computed in the sheet from `viewModel.exercises` and
   `setsByExercise` — no new service, no new storage. Warm-ups are excluded from both. The
   Session bars are **set volume, not effort**: RIR is the truer axis but it is optional, and a
   chart that treated "not logged" as "easy" would be inventing a session.

   A fifth card, **this lift over time**, was drawn and not built: it needs a per-session history
   series for one exercise, and `StatsServiceProtocol` exposes aggregates
   (`fetchStats`, `fetchStatsSnapshot`) rather than a series. That is the one that needs new
   data plumbing.

   Still open: an **Instagram Stories** hand-off via `instagram-stories://share` (one tap into
   the Stories composer, needs an `LSApplicationQueriesSchemes` entry). Worth doing if the card
   is meant for Stories — a 9:16 card that takes three taps to get there is aimed at a
   destination it does not reach.
3. Assets: `design/summary-card/repster-icon.png` and `repster-mark.png` are ready. The shipped
   `marketing/source/logo/repster-logo.png` carries an opaque `#1B1B1F` ground — the same value
   as `Color.bgCard` — so it shows as a lighter square on a darker card. `repster-mark.png` is
   the knocked-out version and is what the lockup should use.
4. `Info.plist` / entitlements per C6.

**Built with the footer lockup.** The bar remains a small change — swap the footer for a filled
band — if the screenshot-survival argument wins.

**Branding was undecided.** Two treatments are drawn: a footer lockup (date · mark · wordmark ·
URL) and a solid accent bar across the foot with the icon reversed onto it. The bar is the only
one that survives being screenshotted, cropped and reposted, which is how these actually
travel; it also most reads as an ad. Pick one before building — it is a five-minute change now
and a re-render later.

---

## 4. Sequencing

```
W1 ─ W2 ─┬─ W3 (Add details)  ← unblocks deloadReadiness; do first
         ├─ W4 (action bar)
         ├─ W5 (Coach teaser)   ← flag-gated, trivially revertible
         └─ W6 (calories)       ← depends on W3 only if MET scaling is in scope
W7 (share) is independent and can run in parallel
```

W1–W6 is roughly one focused pass. W7 is its own piece of work and should not be bundled with
it — it touches `project.pbxproj`, entitlements and a new render path.

---

## 5. Open decisions

1. **Has `perceivedEffort` been unreachable since the redesign?** Check real data. It decides
   whether §1 is a bug report or a feature.
2. **Push or second sheet for Add details** (W3).
3. **Discard beside Save, or below it** (W4).
4. **Does the calorie display follow the HealthKit write toggle** (W6).
5. **Footer lockup or brand bar** on the share card (W7).
6. **Does the effort question survive at all?** The honest version of this plan asks whether
   all four details earn their place. Effort has exactly one reader; suggestion feedback has
   one; notes and save-as-template have none but the user. That is the list to argue with.

---

## 6. What breaks first

- **The exercise list.** Five rows fit comfortably; the design was checked at five. A
  fifteen-exercise session pushes Add details under the fold. Either cap the list with a
  "+N more" row or accept the scroll — but decide, rather than discovering it.
- **The Coach teaser, if Coach slips.** Flag it.
- **The calorie line, if the toggle question in W6 is answered by accident** rather than
  deliberately. A user who declined the Health write and then sees no number on their own
  summary will read it as a bug.
