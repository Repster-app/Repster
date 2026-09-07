# Pre-1.5 Launch Checklist

**Currently live:** 1.4 (build 4), released 2026-08-20.
**This release:** numbered **1.4.1 build 1** in the project right now. Scope locked
2026-09-06; everything unbuilt moved to
[RELEASE_1_6_CONSIDERATIONS.md](RELEASE_1_6_CONSIDERATIONS.md). §0 is where the
version decision lands, and it is worth taking before anything else here.
**Branch:** `NewMain` — **47 commits ahead of `origin/NewMain`**, plus 23 uncommitted
paths. Nothing in this release is public yet, including the privacy policy.
**Build state:** `xcodebuild build -scheme Repster` succeeds with zero errors,
verified 2026-09-06 against the working tree.

This is the counterpart to [PRE_1.4_CHECKLIST.md](PRE_1.4_CHECKLIST.md) for the
next release. It does **not** repeat that file. 1.4 shipped, so the one-time setup
in it — App Privacy declarations, the HealthKit capability on the App ID, PostHog
project settings, attribution — is done and stays done. What follows is only what
is new, what recurs every release, and what this particular release can break.

## What is actually in this build

**This section was two releases out of date.** The full, verified inventory is now
[RELEASE_1_5_PLAN.md Part 1](RELEASE_1_5_PLAN.md). In one line each — 46 commits
since `4b8a0ae` (2026-08-19), plus 23 uncommitted paths:

- **Onboarding rebuilt around programs.** Welcome → units → **pick a program** →
  extras. Four seeded programs materialise as templates in a folder. Apple Health
  leaves onboarding and now offers itself after the first completed workout.
- **Templates rebuilt** — folders, a detail view, paired supersets, and the **AI
  template helper deleted**. Followed by a data-loss hardening pass.
- **Supersets**, marked-only, visible in the workout and afterwards.
- **The workout summary screen rebuilt, with a shareable card.** Notes and effort
  are reachable for the first time ever.
- **The epoch-2 suggestion engine** — the change that moves everyone's numbers (§2.2)
  — plus a kill switch, plus the new **"why this weight" explainer sheet**.
- **Drop sets made real** and visible in history; unbuilt set types hidden.
- **Exercise replace and reorder**, including the whole-workout reorder sheet.
- **Session replay masking inverted** (§1.1, §2.3), progression-exclusion visibility,
  backup restore hardening, export screen copy, and the set-keypad rebuild.

Uncommitted at the time of writing: the explainer sheet, the reorder sheet, the share
card analytics, and the export copy. See §4.

---

## 0. Settle the version number — three things hang off it

**The What's New sheet is the sharp edge.** `WhatsNewRelease.current` matches
`CFBundleShortVersionString` by **exact string equality**, and
`WhatsNewRelease.all` currently holds entries for `"1.4"` and `"1.5"` only.
Shipping as **1.4.1 shows no sheet to anyone** — silently, with no error. That
matters more than usual this release, because §2.2 is a change every existing user
will notice and the sheet is the only thing that explains it.

**The recommendation is 1.5, and it is not close.** This release rebuilds onboarding,
templates and the workout summary, adds supersets and a share card, and resets every
user's learned fatigue rates. Calling that a patch release costs the sheet and
understates the release everywhere it is named.

- [x] **Decided 2026-09-06: 1.5.**
- [x] `MARKETING_VERSION` bumped `1.4.1` → `1.5` on **both** the app target and the
      `WorkoutLiveActivity` extension, Debug and Release — four values in
      `project.pbxproj`. A mismatch between the two targets is rejected at upload, not
      at build, so all four move together. `RepsterTests` stays at `1.0`; it is not
      shipped
- [ ] Either way, settle the What's New copy — **§8**. The existing 1.5 entry is
      accurate but describes only the suggestion engine, which is the least visible
      part of a release that also rebuilt onboarding, templates and the summary
      screen
- [ ] Check `CURRENT_PROJECT_VERSION`. The app target is at **1**, down from 4 —
      fine for a fresh marketing version, rejected if App Store Connect already has
      a build with that number under the same version string

---

## 1. Blocking — must happen before the build reaches users

### 1.1 Deploy the privacy policy before the build ships, not after

Session replay changed direction on 2026-08-29: recording is now legible by default
and a named list of values is masked, instead of everything being masked and a few
screens opted in. The reasoning is in
[ReplayPrivacy.swift](Repster/Core/Extensions/ReplayPrivacy.swift) and in
`AnalyticsService.configureSessionReplay`.

The live page at <https://repster-app.github.io/Repster/privacy.html> currently
reads "Anything you type in your own words is masked… Images are masked in the same
way." **That becomes false the moment this build reaches a user.**

**Status changed since this was written: the rewrite is committed, and still not
live.** `docs/privacy.html` reads "Last updated: August 29, 2026" on `NewMain`, but
it sits in one of **47 unpushed commits**. Pages serves `NewMain:/docs`, so the
deploy is a `git push` and nothing else — and until that push happens the live page
is the old one no matter how correct the file is.

Three separate site changes are stuck behind the same push (`ff37e37`, `d5d891e`,
`29601e0`): the privacy rewrite, the OG card and sitemap/robots work, and the
support-address fix.

- [x] Commit the `docs/privacy.html` change — done, in `d5d891e`
- [ ] **Push `NewMain`.** This is the deploy
- [ ] Reload the live URL and confirm it reads **"Last updated: September 6, 2026"**
      and the new Session Recordings section, before submitting the build
- [ ] If the live page does *not* update, Pages is serving something else — check
      the Pages source in repo settings before assuming the push failed

### 1.2 App Review Notes

`marketing/app-store/privacy-review-checklist.md` holds the rewritten note (the
block under "Use this in the App Review Notes field"). It now says recordings show
exercise, workout and template names, that there is no user-supplied imagery, and
that recording stops while a text-entry dialogue is open. The Apple Health paragraph
already describes the 1.5 behaviour — the offer after the first completed workout —
so that half needs nothing.

**Two things in that note are wrong and must be fixed before it is pasted.** It is a
statement to Apple, so an inaccuracy is worse here than in any other document.

- [ ] **The free-tier number is wrong.** The note says "The free tier allows up to 5
      completed workouts." The code says **10**
      ([MonetizationService.swift:31](Repster/Core/Services/MonetizationService.swift:31),
      `freeWorkoutLimit = 10`), and so do the website and the support page. Fix the
      note, not the code
- [ ] **The new Photos permission is not mentioned.** 1.5 adds
      `NSPhotoLibraryAddUsageDescription` for Save to Photos on the workout share
      card. Reviewers see a new permission string and no explanation. Add a
      paragraph: the app writes one image the user explicitly asked to save, requests
      add-only access, and never reads the photo library
- [ ] Paste the corrected note into App Store Connect for this version. The version
      on file describes the 1.4 behaviour

### 1.3 What does *not* need changing — recorded so it isn't re-litigated

- `Repster/PrivacyInfo.xcprivacy` — unchanged. `Other Usage Data` already covered
  replay, and this change does not add a data type
- App Privacy answers in App Store Connect — unchanged, same reason
- The event stream — untouched. Still bucketed (`set_count_bucket: "4-6"`,
  `notes_entered: true`). Nothing in this release widens what events carry
- **The Photos permission is not an App Privacy answer.** Add-only access to write
  an image the user asked to save collects nothing and sends nothing off device. It
  needs the Info.plist string and a line in the review note (§1.2), and no change to
  the App Privacy questionnaire

### 1.4 dSYMs — recurring, every archive

Without a symbol upload every `$exception` frame arrives as a hex address. Per
archive, and easy to forget. Full steps in [PRE_1.4_CHECKLIST.md](PRE_1.4_CHECKLIST.md) §1.5a.

- [ ] `posthog-cli --host https://eu.posthog.com dsym upload` after archiving
- [ ] Confirm one exception in PostHog shows Swift function names

---

## 2. Know what you are shipping — the five changes that can actually hurt

### 2.1 Suggestions can now ask for *more* weight

This is the first change in the feature's history whose failure mode is "too
heavy". Every previous one failed towards "too light" — a disappointment. This one
fails towards a missed rep.

The lever is `prescriptionCapacityGuardsEnabled`, default on. Off restores 1.x
behaviour exactly (asserted in `SmartSuggestionBehaviorScenarioTests`, not assumed).

**Know before release: it is a per-user setting, not a remote flag.** A user hits
it via Settings → Smart Suggestions → **Admin Mode** on → **Capacity Guards** off.
There is no server-side switch, so a bad interaction found in the field still costs
an App Store release for everyone who doesn't do that by hand.

- [ ] Write the three-step Admin Mode instruction somewhere you can paste it into a
      support reply without going and reading the code
- [ ] Confirm Admin Mode is off by default on a fresh install — it exposes
      diagnostics screens that are not meant to be part of the product

### 2.2 Every existing user's learned fatigue rates are wiped on upgrade

The epoch-2 engine invalidates the old calibration, so the rates reset on first
launch after the update. Predictions and audit records survive; only the rates go.

Effect on the user: **suggestions shift on day one, for everybody, at once.** The
"Give it a week" What's New tile exists for exactly this — which is why §0's
version decision is not cosmetic. Shipping this change with no sheet is shipping a
week of unexplained numbers.

- [ ] Confirm the sheet actually appears on an upgrade install (§3.4)

### 2.3 Session replay stops redacting most of the app

From this build, recordings show exercise names, workout and template names, and
every screen and sheet legibly. Masked: workout/set/template notes, bodyweight
everywhere including the log, the CSV import preview, and the pasted-AI-JSON box.
Three text fields live inside `.alert` and cannot be masked at all — recording
**stops** while those are open.

The default now **fails open**: a text field added later is recorded unless someone
masks it. `RepsterTests/ReplayMaskCoverageTests.swift` is the guard and fails the
build on an unclassified field. Recordings already in PostHog stay as they were.

### 2.4 Backup archives cross versions in both directions

This build reads archives leniently (unknown enum cases cost a column, not the
file) and writes conservatively (new cases are downgraded to something 1.4 can
parse). Both halves matter: before the fix, one new diagnostic label in an archive
made a 1.4 restore report a perfectly good file as corrupt.

- [ ] Export a backup from this build, restore it on a **1.4** build, confirm the
      history arrives. This is the one test that cannot be done after release

---

### 2.5 The app ships a promise for a feature that does not exist

`WorkoutSummarySheet` renders an **"Analyse with Coach" teaser** on the summary
screen — the screen every user reaches at the end of every workout — and Coach is
not built. [COACH_ANALYSIS_SCOPING.md](COACH_ANALYSIS_SCOPING.md), written
2026-09-06, is still deciding what would sit behind the tap.

`CoachPreferences.showsSummaryTeaser` **defaults to `true`**
([WorkoutSummarySheet.swift:21](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:21)).
The comment says the teaser "can be pulled without a release if Coach slips" — but
the key is read from local `UserDefaults` with no remote config behind it, so that
is only true one device at a time. It has the same shape as §2.1's kill switch:
a lever that exists and cannot be reached from here.

The code's own reasoning is the argument: *"A permanent 'Soon' is a broken promise
… this is one of the few moments it has the user's attention, so it has to be
credible or absent."* Nothing about Coach is scheduled.

- [ ] Decide before archiving: ship the teaser on, or flip the default to `false`.
      A one-word change now; a release for everyone later

---

## 3. Verify before release — TestFlight and a real device

### 3.1 Prove the new masking works

This replaces [PRE_1.4_CHECKLIST.md](PRE_1.4_CHECKLIST.md) §2.1 and matters more
than it did there, because the default no longer protects you.

Record one session on TestFlight, then watch it in PostHog:

- [ ] A workout note is a black rect; the sets, reps and weights around it are readable
- [ ] The bodyweight log is black — chart and entries both — while its title and the
      add button are still visible
- [ ] The CSV import Sample Data block is black; the column mapping above it is not
- [ ] Open the **set note** dialogue, type, dismiss. Expect a **gap** in the
      recording, not a black rect. Same for Save as Template and Save Preset
- [ ] Sheets are legible — the exercise picker, exercise settings, the summary
      sheet. These were solid black in 1.4 and are the main reason this changed

### 3.2 The device passes that already exist

- [ ] [DEVICE_TEST_SUGGESTIONS_1_5.md](DEVICE_TEST_SUGGESTIONS_1_5.md) — nine
      checks, ~30 minutes, each naming the number to look at and what it used to be
- [ ] [DEVICE_TEST_PASS.md](DEVICE_TEST_PASS.md) — the set-completion path, which
      moved off the main actor. Highest-risk change in the release by volume of use

Both are real-device passes. The simulator is a lower bound on the two that are
about feel.

### 3.3 The upgrade path, not just a clean install

Most of §2 only exists for users who already have data.

- [ ] Install the live 1.4 build, log a few sessions, then upgrade to this build
- [ ] History intact, no crash on first launch, suggestions still produce a number
- [ ] A restored epoch-2 prediction is not mislabelled as 1.x (`modelEpoch` now
      round-trips through the archive)

### 3.4 What's New

- [ ] Sheet appears once after updating, does not return on the next launch
- [ ] It matches what shipped (§0)

### 3.5 Opt-out still kills everything together

- [ ] Settings → Data & Backups → Share Anonymous Analytics off: no events, no
      recording, no survey, no crash report. The single toggle is what the policy
      promises

---

## 4. Repo hygiene before archiving

- [ ] **23 uncommitted paths** on `NewMain` (down from 53 — the replay and exclusion
      work is committed). Commit in coherent chunks: the **suggestion explainer
      sheet**, the **reorder sheet**, the **share card analytics** and the **export
      screen copy** are four separate things, and reviewing them as one diff later is
      miserable
- [ ] **Push `NewMain`. It is 47 commits ahead** — not 12. Pushing is also what
      deploys the privacy policy and the rest of the website (§1.1, §6).
      **`origin/NewMain` is at `9b43a0e` (2026-08-18), which is one commit *before*
      the `1.4` release commit** — so the remote has never seen 1.4 either, and the
      live site is the 2026-08-18 state of `docs/`
- [ ] `CHANGELOG.md` is stale — its last entry is `0.1` from 2026-03-24, and it
      still claims the app uses `0.x` versioning. Either bring it up to date or
      delete it; a changelog that stops four releases back is worse than none
- [ ] The untracked `design/` directory is the Repster Coach design canvas
      (`design/coach/*.dc.html`, created 2026-08-29). **The repo is public**, so
      decide deliberately: commit it, or add it to `.gitignore`. Right now it is
      neither
- [ ] `DEVICE_TEST_PASS.md` points at "PRE_1.4_CHECKLIST.md §7.1", which does not
      exist (§7 is "Optional, not blocking"). Fix the reference or drop it
- [ ] `ONBOARDING_REDESIGN_SCOPING.md` still reads `Status: scoped, not started`. The
      program picker, the seed catalogue, `ProgramCatalogService` and the Extras step
      are all in the tree. Re-baseline it, or it will be read as a gap list and it
      is not one

---

## 5. Known defects this release ships with — decide, don't discover

None of these are regressions. They are all live on 1.4 today. The point of listing
them is that shipping them again is a choice, and it is cheaper to make it now than
in a review reply. They are carried forward in
[RELEASE_1_6_CONSIDERATIONS.md §4](RELEASE_1_6_CONSIDERATIONS.md), which adds three
this list did not have: CSV import creating parallel exercise records, the fatigue
model never measuring real rest, and the unexplained template set collapse.

- **Unperformed sets count as logged.** Copy Previous rows that were never ticked
  still count. Scoped in [UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md),
  unimplemented
- **Fixed rep targets cannot progress at all.** Separate from the undershoot fixes
  in this release, and not addressed by them
- **Bodyweight-style set labels disagree between screens.** A Pull Up at +10 kg
  reads `10 kg` in one place and `90` in another. Deferred from 1.4 (§9 there)
- **Backups exclude `BodyweightEntry` and programs.** Deferred from 1.4 (§8 there).
  Templates are no longer excluded — they have ridden the archive since
  `archiveVersion` 2, and restore deletes the device's templates and reinserts the
  file's. Until 2026-09-05 the in-app copy said the opposite in three places, so it
  was not merely misleading but false, in the direction that loses data. The copy is
  now accurate; what remains unsaid is that a v1 archive still leaves templates
  alone, so the same screen describes two different outcomes
- ~~**Exercise replace** is still open~~ — **wrong, and removed.** Replace is built
  and reachable from the exercise tab strip's context menu with a confirmation
  ([ExerciseTabStripView.swift:298](Repster/Features/Workout/Views/ExerciseTabStripView.swift:298)).
  So is the whole-workout reorder sheet
- **Rest timer alarm is silent under any Focus mode.** `.timeSensitive` needs an
  entitlement the app does not have. See
  [REST_TIMER_ALARM_SCOPING.md](REST_TIMER_ALARM_SCOPING.md)

---

## 6. The website — one push, then four factual fixes

The site is `docs/` on `NewMain`, served by GitHub Pages. **Everything here is
invisible until §1.1's push happens.**

### 6.1 Already written, waiting on the push

- `docs/privacy.html` — the replay rewrite (blocking, §1.1)
- `docs/index.html`, `styles.css`, `robots.txt`, `sitemap.xml`, `assets/og-card.png`
  — the shareable-and-crawlable work from `29601e0`
- The support-address fix

### 6.2 The site described features the app does not have · **fixed 2026-09-06**

The AI template helper was deleted from the app in the templates rebuild (`3cf55ed`)
and **four public pages still documented it**, including two that are quoted to
Apple. `grep -rn "ChatGPT" docs/` now returns nothing.

- [x] **`docs/docs.html` → Templates** — the "AI helper" bullet deleted
- [x] **`docs/support.html`** — the "How does the AI template helper work?" FAQ entry
      deleted
- [x] **`docs/privacy.html`** — the whole **"AI Template Feature"** section deleted,
      and the Session Recordings masking list corrected from **four things to three**.
      It promised to mask "text pasted into the AI template box", a field that no
      longer exists. This is the one that mattered: it is the operative privacy
      document and its wording is mirrored in the App Review note
- [x] **`docs/terms.html`** — the "AI Template Helper" section deleted
- [x] **`marketing/app-store/privacy-review-checklist.md`** — the same four-to-three
      correction in both the App Review note and the "commitments that must stay
      literally true" list
- [x] **`docs/docs.html` → Onboarding** — rewritten. Was "four short screens" ending
      in **Apple Health** and **Import**; now three steps ending in **Choose a
      Program** and **Optional Extras**, with the four seeded programs named and a
      line saying Apple Health is offered after the first completed workout instead
- [x] **"Every screen after the welcome can be skipped"** — removed.
      `OnboardingStep.isSkippable` returns `false` for every case, deliberately
- [x] `Last updated` bumped to **September 6, 2026** on both `privacy.html` and
      `terms.html` (terms had been sitting on May 16)

### 6.3 The site does not describe features the app now has

Lower priority than §6.2 — an omission, not a falsehood — but this is the release
where the feature guide stops matching the app if nothing is done.

- [ ] **Templates:** folders, the template detail view, New and Import merged
- [ ] **Supersets:** the Templates section calls them "grouped exercise ordering …
      where supported". They are now a real workout feature — pairing, both prompt
      directions, visible during and after the session
- [ ] **Workout summary and the share card:** the Active Workout → "Workout Summary"
      paragraph describes the old sheet. Notes and effort are reachable now, and the
      card is a new user-facing feature with a Photos permission behind it
- [ ] **Exercise replace and reorder**
- [ ] **The "why this weight" explainer** under Smart Suggestions
- [ ] **Set Types:** the guide lists all thirteen. 1.5 hides the ones with no feature
      behind them, so the list is now longer than the picker

### 6.4 Positioning — a decision, not a fix

`docs/index.html` sells "fast workout logging, reusable templates, useful personal
records". Onboarding now says **"Repster learns what you can lift"** over three
bullets: estimated 1RM from your first set, rest and fatigue tracked per muscle,
next-session targets not just a log.

Those three lines are one asset with three surfaces (§7.4). The website is a fourth,
and it is currently selling the older story. Aligning it is a positioning call — it
is not blocking, and it is cheap while the site is already being edited.

---

## 7. App Store Connect — what to tell Apple

Everything in this section happens in App Store Connect, not in the repo.

### 7.1 Version and build

- [ ] `MARKETING_VERSION` on the app target **and** `WorkoutLiveActivity` (§0). A
      mismatch is rejected at upload, not at build
- [ ] `CURRENT_PROJECT_VERSION` is **1**, down from 4. Fine under a fresh marketing
      version; rejected if App Store Connect already holds a build numbered 1 under
      the same version string

### 7.2 Blocking, and covered above

- [ ] App Review Notes, with the free-tier number and the Photos paragraph fixed (§1.2)
- [ ] Privacy policy live before submission (§1.1)
- [ ] App Privacy answers — **no change** (§1.3)

### 7.3 Screenshots — the live set is two releases old

The six live frames were transcribed from build **1.3**
(`marketing/app-store/live-screenshots-inventory.md`). 1.5 rebuilds the templates
screen and the workout summary, so at least the "start from your saved routines"
frame now shows a screen the app no longer has.

A replacement set already exists at `marketing/generated/app-store-v2/` — five frames
(`01-know-your-next-weight` … `05-analyze-years-of-progress`), brand blue `#5B8DEF`.

- [x] **Decided 2026-09-06: keep the live 1.3 set for 1.5.** Screenshots are a
      separate piece of work and are not gating this release
- [ ] **Carried to 1.6.** The "start from your saved routines" frame shows a templates
      screen the app no longer has, and the v2 set at
      `marketing/generated/app-store-v2/` predates the rebuild too, so shipping it
      would not have fixed that. Whichever set is used next needs frames re-captured
      against the rebuilt templates and summary screens

### 7.4 Listing copy

- [ ] **Promotional text** — the one field that can be changed without a new build.
      Currently: "Fast lifting logs, reusable templates, useful PRs, charts, rest
      timers, Live Activities, CSV import, and Smart Suggestions." Supersets and
      programs are the two 1.5 features a searcher might actually be looking for
- [ ] **Keyword field** — `superset` and `program` are not in it. Both are things
      people search
- [ ] **Subtitle and description** — the same positioning question as §6.4. The
      canonical three bullets live in
      [WelcomeStepView.swift:32](Repster/Features/Onboarding/Views/WelcomeStepView.swift:32)
      and the code comment there says they must be mirrored on the App Store listing
      and the paywall. Right now they are mirrored on neither
- [ ] **The paywall is not in this repo.** It is a RevenueCat-hosted `PaywallView()`,
      so its copy is edited in the RevenueCat dashboard. If the bullets change, that
      is a third place to change them

### 7.5 What's New — the App Store field

Separate from the in-app sheet, and not capped at three items. §8 has both drafts.

---

## 8. What's New copy

### 8.1 The in-app sheet — three items, and the cap is real

`WhatsNewRelease.all` originally held a `"1.5"` entry with **two** items, both about
suggestions. Verified 2026-09-06: the copy was accurate — drop sets genuinely no
longer drag the exercise down, and per-exercise tuning genuinely restarts — but it
described the least visible part of the release and said nothing about the four
reworked screens. Rewritten 2026-09-07; the three below are what ships.

The rule from [PRE_1.4_CHECKLIST.md §3.3](PRE_1.4_CHECKLIST.md): an item earns a slot
only if **the user can go and look at it in under ten seconds**. Three is the cap;
the fourth reliably fails the test.

**Decided 2026-09-06, copy rewritten 2026-09-07, and written into
`WhatsNewRelease.all`:**

| # | Title | Tint | Why it earns the slot |
|---|---|---|---|
| 1 | **Supersets** | accent | The only genuinely new capability, and the only one nobody finds by accident. Templates and the summary screen announce themselves by looking different |
| 2 | **Smarter suggestions** | gold | Effort and drop sets, **plus the recalibration warning** |
| 3 | **A fresh look** | green | The rebuilt summary and share card, redesigned templates, and the visual work generally |

**No before-and-after anywhere in this sheet.** Decided 2026-09-07: every row says
what the app does now, never what it used to do wrong. The earlier item 2 opened on
"telling the app you had reps left no longer makes it suggest less", which is
accurate and reads as a confession. Rewrite around the improvement, not the defect.

**Read this before trimming item 2.** The standalone "Give it a week" tile is gone —
the third slot went elsewhere — so its warning is now the **second sentence of item
2**, and it is not decoration. §2.2 resets every existing user's learned fatigue
rates on upgrade, so suggestions move for everybody on the same day, and this sheet
is the only place that is explained. It survives the no-dirty-laundry rule by
arriving as the engine starting fresh ("they're learning your numbers from today")
rather than as an apology. Cutting that sentence to tighten the copy ships a week of
unexplained numbers.

**Item 3 is deliberately broad, and that is the one row where broad is safe.**
Everything it names — the summary screen, the share card, the templates redesign — is
met unprompted after the next workout, so the ten-second test is satisfied by the
release rather than by the copy. It must not soften into "various improvements": a
row with nothing to go and look at is what teaches people to dismiss the sheet
unread, and once that habit sets in the sheet is worthless for the release that needs
it.

**What this cuts:** the four user-requested fixes that were item 3 until 2026-09-07 —
reorder/replace mid-workout, template folders as their own line, visible drop sets,
and tapping a suggestion for its source (all still in the App Store notes, §8.2) —
and programs in onboarding (the sheet's audience is upgraders, who never see
onboarding).

- [x] Three decided and written into `WhatsNewRelease.all`
- [x] The entry's version string is `"1.5"` and `CFBundleShortVersionString` is now
      `1.5` (§0), so the sheet will actually fire
- [ ] Confirm on an upgrade install that it appears once and does not return (§3.4)

### 8.2 The App Store "What's New" field — draft

No three-item cap here, and this audience includes people who have not installed the
app yet. Suggested text:

> **Supersets.** Pair two exercises and Repster keeps them together — during the
> workout, in your templates, and in your history.
>
> **Templates, rebuilt.** File routines into folders, open a template to see every
> set before you start, and save supersets as part of the routine.
>
> **A better finish to every workout.** A rebuilt summary screen with notes and
> effort, plus a shareable card of the session you just did.
>
> **Smarter weight suggestions.** Telling the app you had reps left no longer makes
> it suggest less, and drop sets no longer drag the rest of the exercise down. Tap
> any suggestion to see exactly which of your sets it came from.
>
> **New here?** Setup now offers a starting program — Full Body, Upper/Lower, Push
> Pull Legs or 5×5 — and writes it straight into your templates.
>
> Plus: reorder or replace exercises mid-workout, drop sets you can see in your
> history, and a faster set keypad.

- [ ] Trim to taste. Apple shows roughly the first three lines before "more"
- [ ] The last line is the honest place for "and a faster set keypad" — it is real
      work and nobody updates for it

---

## 9. After release

- [ ] Watch one full session recording end to end within a day of release. It is
      the first release where recordings are legible, and the first chance to find
      out whether they are actually useful for the activation question they exist
      to answer
- [ ] Check the suggestion numbers against complaints, not against the tests. §2.2
      guarantees they moved for everyone; the question is whether they moved the
      right way
- [ ] Confirm no `$exception` frames are arriving unsymbolicated (§1.4)
