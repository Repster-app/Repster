# Shareable workout card — scoping & growth case

Scopes item 1 of `FEATURE_SCOPING_BRIEF.md`. Written 2026-08-08 against branch `NewMain`,
shipped version 1.3 (build 3).

Everything under "verified state" was read out of the code. Where this document contradicts
the scoping brief, the contradiction is called out explicitly — there are two places where
the brief is optimistic about what already exists.

---

## Recommendation in one paragraph

Build it, at S size, in one phase of roughly a week — but build it for **retention and
optionality**, not for installs. At current scale the install math is noise (see the
arithmetic below), and anyone who promises you viral growth from a workout card is selling
something. What makes it worth shipping anyway: it is the cheapest feature on the roadmap,
it creates the only zero-cost distribution surface the app has, the same 3% share rate that
produces ~7 installs/month today produces ~700/month at 10k MAU, and the *act* of sharing
is a public commitment that plausibly lifts the sharer's own retention. Ship it free, always
branded, never gated. Then instrument it properly and let the share rate decide whether
phase 2 and 3 ever get built.

---

# Part A — The business case

## A1. What this actually buys you, ranked honestly

**1. Sharer retention (largest near-term effect, most measurable).**
Publicly posting "I trained today" is a commitment device. The user has told their friends
they're a person who lifts, and Repster is the app that proved it. This is the effect most
likely to show up in your PostHog data within a month. Caveat that matters: sharers are a
self-selecting engaged cohort, so a raw "sharers retain better" chart proves nothing. See
A6 for how to measure it without fooling yourself.

**2. Optionality on future scale (why to build it now rather than later).**
The loop compounds with MAU, and it costs a week. Building it at 100 MAU is buying a call
option cheaply. Building it at 10k MAU means a week of engineering you could have spent
elsewhere while a year of impressions went unshipped.

**3. Product identity in the wild.**
Every card is a piece of design that says "this is what Repster looks like." You have
exactly one visual identity asset in circulation right now (App Store screenshots). The card
becomes the second, and unlike screenshots it is distributed by other people. It also
becomes free App Store screenshot material — the ASO set in `marketing/generated/app-store-v2`
could gain a "share your session" frame.

**4. Installs (real, but small until scale).**
Genuinely targeted audience — a lifter's followers skew toward lifters — at zero marginal
CAC. Just don't build the business case on it.

## A2. The arithmetic, stated so it can be argued with

All assumptions, not benchmarks. Replace them with your own numbers once the events land.

```
100 MAU × 8 completed workouts/month        =    800 completed workouts
× 3% share rate                             =     24 shared cards
× ~30 impressions each (Story/iMessage mix) =    720 impressions
× 1% impression → install                   =    ~7 installs/month
```

Seven installs. That is the honest answer at current scale, and it is why the *reason* to
build this cannot be installs.

Now hold the rates fixed and change one number:

```
10,000 MAU → same rates → ~720 installs/month
```

Same code. That is the option you're buying. The rates in the middle are the ones you can
actually influence with product work, and A3 is about those.

**Cost side:** ~1 week engineering, no data-model change, no migration, no new third-party
dependency, no App Store privacy re-declaration (see C6). This is the lowest-risk item on
the entire roadmap — lower than HealthKit, far lower than supersets.

## A3. What actually moves the share rate

The card is not the lever. The moment is.

- **Offer it at the emotional peak, not in a settings-shaped sheet.** A PR is the peak.
  A finished workout is a plateau. If `prsHit > 0`, the share affordance should be visually
  promoted; otherwise it can be a quiet secondary button.
- **One tap from summary to system share sheet.** Every intermediate screen roughly halves
  completion. This is the single strongest argument for shipping **one** card layout in v1
  rather than a picker — see B3.
- **Achievement framing beats data framing.** "New bench PR — 100 kg × 5" is a milestone
  someone posts. "12,400 kg total volume" is a brag with a number nobody outside the app
  can calibrate. The brief already suspected this; the code work to support it is slightly
  larger than the brief assumed (see C4).
- **Destination mix decides everything downstream.** An iMessage share reaches ~1 person and
  converts well; a Story reaches ~30 and converts poorly. You can measure this for free —
  `UIActivityViewController`'s completion handler hands you the activity type. Instrument it
  from day one (D1).
- **Pre-fill the caption.** The share sheet accepts image + URL together. Free real estate.

## A4. The missing piece: you currently cannot attribute anything

Verified: there is no URL scheme in `Repster/Info.plist`, no `onOpenURL` anywhere, and the
only App Store URL in the codebase is the write-review link in
`ReviewPromptService.swift:111`. `marketing/website/README.md` still has `APP_STORE_URL` as
an unreplaced placeholder.

So if you ship the card as-is, every claim in A1 stays unfalsifiable forever. Fix it in the
same week — it is an afternoon, not a project:

1. **Campaign-tagged App Store link.** Use App Store Connect's campaign parameters:
   `https://apps.apple.com/app/id<APP_ID>?ct=share_card&pt=<PROVIDER_TOKEN>&mt=8`.
   App Analytics then reports installs by campaign. No SDK, no IDFA, no ATT prompt, no
   privacy-policy change — which is exactly right given the posture documented in
   `PRE_1.4_CHECKLIST.md` §5. This is the cheapest real attribution available to you.
2. **A short, human URL on the card face.** Images posted to Stories strip links, so the
   only thing that survives is what's rendered in the pixels. `repster-app.github.io/Repster`
   is not that. `PRE_1.4_CHECKLIST.md` §6 already contemplates a `repster.site` alias — if
   you own it, point it at the landing page and put it on the card.
3. **Smart App Banner on the landing page.** Already on the website to-do list; a share card
   is the reason to finally do it.

Without (1) you will never know if this feature worked. With (1) it costs nothing to know.

## A5. Free or gated — free, and don't get clever

The brief recommends free. Agreed, and stronger: **do not ship a "remove the watermark"
upgrade.** The watermark is the entire product rationale. Selling its removal converts a
distribution asset into perhaps €0.30/user of incremental revenue. That is a bad trade at
any subscriber count you will plausibly reach.

Two nuances:

- **The card is a paywall-adjacent delight, not a paywall trigger.** The finish-workout
  moment already carries the free-tier quota check (`AccessControlService.recordCompletedWorkoutIfNeeded()`
  in `ActiveWorkoutViewModel.finishWorkout`) and the rating prompt (`ReviewPromptService`
  milestones at 3/12/30 workouts). That moment is getting crowded. Sequencing rule: **share
  offer → save → rating prompt**, and never show a paywall and a share offer in the same
  session-end. `ReviewPromptService.suppressForThisSession()` already exists for the paywall
  collision; the same discipline applies here.
- **Insight cards inherit Insights' gating.** A card that shares an `InsightRecord` is
  sharing paid content, so it lives behind the entitlement like the rest of the feed. That's
  consistent, and it's phase 3 anyway.

## A6. How you'll know if it worked — and the kill criteria

Decide these now, before the data arrives, so you can't rationalise afterwards.

**Read after 4 weeks or 200 observed completed workouts, whichever is later.**

| Metric | Source | Bar |
|---|---|---|
| Share-sheet open rate | `share card opened` ÷ `workout completed` | — |
| Share completion rate | `share card shared` ÷ `share card opened` | ≥ 50% |
| Destination mix | `destination` property | informational |
| Installs attributed | App Store Connect, `ct=share_card` | informational at this scale |
| Sharer D7 retention | PostHog cohort | see below |

**Decision rule on open rate:**

- **≥ 8%** → the loop is real. Fund phase 2 (retroactive + PR-triggered cards) and phase 3
  (annual recap).
- **3–8%** → keep it, stop investing. Iterate copy and placement only; the code is done.
- **< 3%** → the moment or the card is wrong. Make exactly one change — promote the share
  affordance on PR sessions specifically — and if that doesn't move it, stop. A feature that
  cost one week and produced nothing is a fine outcome; a feature that costs one week per
  quarter forever is not.

**On the retention claim, don't fool yourself.** Comparing sharers to non-sharers measures
selection, not effect. The cheap honest version: compare each sharer's D7 retention against
non-sharers *matched on completed-workout count at the time of the share*. The rigorous
version is a holdout (hide the button from a random 10%), which PostHog feature flags can
do — `preloadFeatureFlags` is currently off in `AnalyticsService.swift`, so that's a config
change if you want it. My recommendation: skip the holdout at this scale, use the matched
comparison, and treat the result as suggestive rather than proven.

## A7. Where the real upside actually is

Per-workout cards are a steady trickle. The step change in consumer apps is the **periodic
recap** — Wrapped-style. If phase 1 clears its bar, the highest-value follow-on is:

**"Your 2026 in lifting"** — total volume, workouts, biggest PRs, most-trained lift,
month-by-month bar. Shipped mid-December.

Why it's worth more than everything else in this doc: it is shared by users who would never
share a single workout, it produces a burst of concentrated impressions rather than a
trickle, and it lands immediately before January — the fitness category's peak install
season. The data all exists already (`StatsService`, `AnalyticsService`, `ChartDataService`),
and the card renderer built in phase 1 is the same renderer.

A monthly recap is the smaller, safer version of the same idea and can ship earlier as a
test of the format.

---

# Part B — Product scope

## B1. Verified state, and two corrections to the brief

| Brief says | Reality |
|---|---|
| `WorkoutSummaryData` "already computes everything a card needs" | **Not quite.** It has `prsHit` as a *count*, and `ExerciseSummary.bestWeight`/`bestReps` are the max weight and max reps across the exercise — not necessarily the PR set. A card headlining "Bench Press — 100 kg × 5" needs the actual PR set, which lives in `setsByExercise` on the view model (`ActiveWorkoutViewModel.swift:131`). Small extra mapping, read-only, no logging-path change. See C4. |
| Sharing retroactively from history is "ideal" | **It is, but PR counts will be wrong.** `PerformanceRecord` is a current-best table, mutated in place and deleted when beaten (`PRService.swift:676–682`), and `WorkoutSet.prStatus` decays `.current → .previous`. So an old workout's PR count shrinks over time. Sharing "0 PRs" for the session where you actually hit three is worse than not offering the button. See C5. |

Correct in the brief and confirmed: no `ImageRenderer` anywhere, no `ShareLink` anywhere,
the `ActivityShareSheet` wrapper is duplicated verbatim at `ExportView.swift:349` and
`TemplateListSheet.swift:989`, brand blue is `#5B8DEF` (`DesignTokens.swift:46`), and the app
is locked to dark (`Info.plist:162`) which means the card only ever needs one colour scheme.

## B2. The moment

**Primary (phase 1):** a Share button on `WorkoutSummarySheet`, before Save & Close.

This ordering is forced, not chosen: `finishWorkout()` sets `self.workout = nil`
(`ActiveWorkoutViewModel.swift:1980`) and the sheet dismisses on `isWorkoutFinished`. There
is no post-save moment to hang a share button on without restructuring the finish flow — and
restructuring the finish flow means touching workout-logging code, which is off-limits.

Visual weight follows the achievement:

- `prsHit > 0` → promoted button in the recap hero, next to the PR badge that's already there
  (`WorkoutSummarySheet.swift:203–211`).
- Otherwise → a third button in `secondaryActionsSection` alongside Save as Template.

**Secondary (phase 2):** the toolbar menu on `WorkoutDetailFromHomeView.swift:66` and the
workout header menu in `CalendarWorkoutDetailView`. Gated on solving C5.

**Later (phase 3):** Recent PRs card on Home, and Insights.

## B3. The card — resolved decisions

Answering the brief's open questions, with reasoning rather than a menu.

**Which stats?** Achievement-led hierarchy:

1. **Headline.** If PRs → `New PR` + the single best PR set (exercise, weight × reps). If
   not → the workout title (`Workout.displayTitle` already gives "Morning Workout" etc.).
2. **Three stats.** Duration · sets · primary metric. Reuse
   `WorkoutPrimaryMetric.formattedValue(style:unitPreference:)`
   (`WorkoutSetPerformanceFormatter.swift:379`) — it already respects metric/imperial and
   already handles the volume/distance/duration split for cardio-style tracking types. Do not
   reimplement this.
3. **Exercise list.** Top 3 by set count, each with its best set, then "+N more". Off by
   default is tempting for privacy, but the exercise list is the part other lifters actually
   find interesting. **Default on, with a hide toggle** (B4).
4. **Footer.** Date · Repster wordmark · short URL. Always present, never removable.

**One layout or a picker?** **One: 9:16 story (1080 × 1920).** A picker adds a decision at
the exact moment where friction costs the most, and 9:16 renders acceptably in iMessage,
Stories, and Snap. Add square only if the destination mix (D1) shows real feed posting.
This decision alone removes roughly a third of the layout work.

**Does it include the exercise list?** Yes, by default, truncated — see above.

**Free or gated?** Free. See A5.

**Insights variant?** Phase 3, gated with Insights. `InsightRecord` already carries
`headline`, `detailText`, `chartLabels`, `chartValues` — a card variant is a layout, not a
data project. Worth doing only after phase 1 clears its bar.

## B4. Privacy controls on the card

Weights are the sensitive part for a meaningful share of lifters — this is exactly the
audience that will screenshot a card, notice their squat number is on it, and not post. Two
toggles on the preview sheet, both persisted in `UserDefaults` so the choice is made once:

- **Hide exercise list** — collapses to the three headline stats.
- **Hide weights** — exercise names and set counts stay, numbers drop.

This is cheap insurance and it converts a silent non-share into a share.

---

# Part C — Technical design

## C1. New files (all require hand-registration in `project.pbxproj`)

```
Repster/Features/Share/Models/ShareCardContent.swift      pure Sendable value type + mapping
Repster/Features/Share/Views/WorkoutShareCardView.swift   the 9:16 layout
Repster/Features/Share/Views/ShareCardSheet.swift         preview, toggles, share button
Repster/Features/Share/Services/ShareCardRenderer.swift   ImageRenderer wrapper
Repster/Core/Components/ActivityShareSheet.swift          lifted from the two duplicates
RepsterTests/ShareCardContentTests.swift                  mapping tests
```

Registration is per-file and easy to forget; the brief flags it correctly. Budget it.

## C2. Modified files

- `Repster/Features/Workout/Views/WorkoutSummarySheet.swift` — share entry point, promoted
  on PR sessions.
- `Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` — **one new read-only
  method**, `func shareCardContent(title: String) -> ShareCardContent?`, reading `exercises`
  and `setsByExercise`. No writes, no service calls, no touching the logging path. This is
  the only change to that file.
- `Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift` — events, keys, screen,
  one helper (D1).
- `Repster/Info.plist` — `NSPhotoLibraryAddUsageDescription` (C6 — this one is a crash, not
  a nicety).
- `ExportView.swift` / `TemplateListSheet.swift` — delete the two private `ActivityShareSheet`
  copies, use the shared one.

## C3. The one rule that decides whether this works: the card view must be pure

`ImageRenderer` rasterises a view outside the view hierarchy. Anything the view pulls from
its surroundings is simply absent, and the usual symptom is a card that renders blank or
half-styled with no error.

So `WorkoutShareCardView` takes **`ShareCardContent` and nothing else**:

- No `@Environment`, no `ServiceContainer`, no `@Query`, no SwiftData model objects.
- All formatting done at construction time, in `ShareCardContent`, where it is unit-testable.
- Explicit `.system(size:weight:design:)` fonts — never `.body`/`.caption`, which Dynamic
  Type would rescale and break the fixed layout.

Renderer specifics:

```swift
@MainActor
enum ShareCardRenderer {
    static func render(_ content: ShareCardContent) -> UIImage? {
        let card = WorkoutShareCardView(content: content)
            .frame(width: 360, height: 640)          // design canvas in points
            .environment(\.colorScheme, .dark)        // app is dark-locked; pin it anyway
            .environment(\.dynamicTypeSize, .large)   // pin so accessibility settings can't break layout
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3                            // → 1080 × 1920 px
        renderer.isOpaque = true                      // full-bleed dark card, no alpha needed
        return renderer.uiImage
    }
}
```

`ImageRenderer` is iOS 16+, so the 17.0 deployment target is fine and no availability gate
is needed. Render time for a static layout is a few milliseconds — synchronous on the main
actor is correct here; don't over-engineer it with a Task.

No charts in v1. Swift Charts does rasterise, but it's the kind of thing that turns a
one-week estimate into two.

## C4. Data mapping — the PR set

`WorkoutSummaryData` gives the aggregate stats. The PR headline needs the set itself:

```
for each exercise in exercises:
    prSet = setsByExercise[exercise.id]?.first { $0.prStatus == .current }
    → exercise.name + WorkoutSetPerformanceFormatter.weightLabel(for:exercise:unitPreference:)
      + reps
pick the highest-value one for the headline
```

Reuse `WorkoutSetPerformanceFormatter.weightLabel` (`:81`) rather than converting kg
yourself — it already handles unit preference *and* the bodyweight-style exercise cases where
a raw weight number would be meaningless.

`unitPreference` is available on the view model (`ActiveWorkoutViewModel.swift:179`) and on
`ServiceContainer`.

## C5. Retroactive sharing and the PR-decay trap

`WorkoutDetail` (`CalendarViewModel.swift:15`) carries `workout`, `exerciseGroups` (with
sets), `primaryMetric`, `exerciseCount`, `setCount` — everything except trustworthy
historical PRs, for the reason in B1.

Three options, in order of preference:

1. **Phase 1 ships summary-sheet only.** Fresh workouts have accurate `prStatus`. Clean, zero
   risk, and it gets the feature in front of users a week earlier.
2. **Phase 2 shows PRs only when still `.current`,** labelled honestly ("PRs still standing
   from this session"). Slightly odd copy, but never wrong.
3. **Persist `wasPRWhenLogged` on `WorkoutSet`.** The correct long-term fix, but it is a
   SwiftData migration *and* it requires writing during set completion — i.e. the workout-
   logging path, which is off-limits. Out of scope unless that constraint lifts (in which
   case it pairs naturally with the dormant `WorkoutSet.startedAt` work the brief mentions).

Recommended: 1, then 2.

## C6. Info.plist, entitlements, privacy

- **`NSPhotoLibraryAddUsageDescription` is required.** The share sheet's "Save Image" action
  writes to the photo library, and without the key iOS terminates the app. There is no photo
  key in `Info.plist` today. This is the single most likely way to ship a crash with this
  feature — and it only reproduces if the tester taps Save Image, so it's easy to miss in QA.
  Suggested string: *"Repster saves your workout share card to your photo library."*
- **No new entitlement.** `UIActivityViewController` needs nothing.
- **Privacy manifest unchanged.** `PrivacyInfo.xcprivacy` needs no new `NSPrivacyAccessedAPIType`
  — `ImageRenderer` and the share sheet aren't in the required-reason API list.
- **App Store privacy answers unchanged.** The new analytics events (D1) are Product
  Interaction, already declared. Recording the destination app type is app-usage data with no
  identifier attached — still `Product Interaction`, not linked, not tracking.
- **Instagram Stories direct-share** (`instagram-stories://share` + `LSApplicationQueriesSchemes`)
  is a real conversion improvement but is a separate decision with its own review surface.
  Out of scope for v1; revisit if the destination mix shows Stories dominating.

## C7. Tests

The view isn't unit-testable and shouldn't be; the logic isn't in the view. Cover
`ShareCardContent` construction in `RepsterTests/ShareCardContentTests.swift`:

- Metric vs imperial rendering of the PR line and the primary metric.
- PR-set selection picks the actual `.current` set, not `bestWeight`.
- Zero-PR workout falls back to the title headline.
- Exercise list truncation and the "+N more" count.
- Bodyweight-style exercise produces a sensible label rather than "0 kg".
- Empty/degenerate workout returns `nil` rather than an empty card.

Manual QA checklist: metric and imperial; a PR session and a non-PR session; a 1-exercise
session and a 12-exercise session; a very long custom exercise name; a very long workout
title; **tap Save Image** (the `NSPhotoLibraryAddUsageDescription` check); share to Messages,
Instagram, and Photos; largest Dynamic Type setting (card must be unaffected).

---

# Part D — Instrumentation

## D1. Events

Follow the existing pattern in `AnalyticsServiceProtocol.swift` — one helper method per
event so property names stay in sync (`AnalyticsEvent` at `:419`, keys at `:447`, screens at
`:405`).

```
share card opened     { entry_point, variant, prs_hit, access_tier, exercise_list_shown, weights_shown }
share card shared     { entry_point, variant, destination, prs_hit }
share card dismissed  { entry_point, variant }
share card failed     { entry_point, error_type }        // render returned nil
```

New property keys: `entry_point` (`summary` | `history` | `pr_card` | `insight`), `variant`,
`destination`, `exercise_list_shown`, `weights_shown`.
New screen: `AnalyticsScreen.shareCard = "Share Card"`.

`destination` comes free from `UIActivityViewController.completionWithItemsHandler` — the
`UIActivity.ActivityType.rawValue`. Capture it; it is the only way to learn whether you're
building a Stories feature or an iMessage feature, and those want different cards.

Include `share card failed`. A silent render failure is invisible otherwise, and "the button
does nothing" is the kind of bug that survives for months.

## D2. The funnel to build in PostHog

```
workout completed
  → share card opened          (open rate — the headline number)
  → share card shared          (completion rate)
  → [App Store Connect] installs where ct=share_card
```

Break the first two by `prs_hit > 0` versus `= 0`. That single split tells you whether the
achievement-framing hypothesis in A3 is right, and it's the input to every phase-2 decision.

Note the same reading caveat as `PRE_1.4_CHECKLIST.md` §4: give it 1–2 weeks and remember the
PostHog identity is an install, not a person.

---

# Part E — Phasing and estimate

| Phase | Contents | Estimate | Gate |
|---|---|---|---|
| **1** | `ShareCardContent` + mapping, card view, renderer, preview sheet with 2 privacy toggles, summary-sheet entry point, shared `ActivityShareSheet`, Info.plist key, analytics, tests. Plus the campaign-tagged App Store link and landing page (A4). | **~1 week**, of which design iteration is the larger half | — |
| **2** | Retroactive sharing from history/calendar (with the PR-decay handling from C5), PR-triggered share offer, square variant if the destination mix warrants it | ~3 days | Open rate ≥ 8% |
| **3** | Annual/monthly recap card (A7), Insights card variant | ~1 week | Phase 2 shipped; time it for mid-December |

Phase 1 has no dependency on any other roadmap item and doesn't block any of them. It can run
concurrently with HealthKit or widget work.

**Sequencing note against `PRE_1.4_CHECKLIST.md`:** 1.4 is currently blocked on the privacy
policy deploy and App Store Connect work, and its analytics changes are uncommitted on
`NewMain`. Don't bundle the share card into 1.4 — get the privacy work out the door, then
ship the card as 1.5 with its own release note. It's the first user-visible feature since
launch and deserves not to be buried under a privacy release.

---

# Open decisions — yours to make

1. **Do you own a short domain?** (`repster.site` appears in `PRE_1.4_CHECKLIST.md` §6.) The
   card needs a URL on its face that a person could plausibly type. If not, the GitHub Pages
   URL works but wastes the impression.
2. **Set up the App Store Connect campaign link before or after shipping?** Before, ideally —
   retrofitting attribution means the first weeks of data are unattributable.
3. **Exercise list on by default?** I recommend yes with a hide toggle (B3/B4); the counter-
   argument is that a leaked squat number is a silent non-share you'll never see in the data.
4. **Does the PR-decay handling (C5) bother you enough to want the model field?** If you're
   ever going to lift the workout-logging constraint for supersets, `wasPRWhenLogged` and
   `startedAt` are cheap to add in the same pass.
5. **Annual recap for December 2026 — commit now or decide later?** It's the highest-upside
   item in this document and it has a hard date. If it's a yes, phase 1's renderer should be
   written with a second card size in mind rather than hard-coded to 9:16.
