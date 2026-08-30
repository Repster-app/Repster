# Pre-1.5 Launch Checklist

**Currently live:** 1.4 (build 4), released 2026-08-20.
**This release:** numbered **1.4.1 build 1** in the project right now, may end up
being called 1.5, with some of the planned 1.5 features pushed to 1.6. §0 is where
that decision lands, and it is worth taking before anything else here.
**Branch:** `NewMain` — 12 commits ahead of `origin/NewMain`, plus 53 uncommitted
paths.

This is the counterpart to [PRE_1.4_CHECKLIST.md](PRE_1.4_CHECKLIST.md) for the
next release. It does **not** repeat that file. 1.4 shipped, so the one-time setup
in it — App Privacy declarations, the HealthKit capability on the App ID, PostHog
project settings, attribution — is done and stays done. What follows is only what
is new, what recurs every release, and what this particular release can break.

## What is actually in this build

Committed since the `1.4` tag (11 commits):

- **The epoch-2 suggestion engine.** Reps in reserve are credited as a floor, one
  set can no longer crater the capability estimate, drop sets no longer grade the
  model, unlabelled sets are charged at their target, and learned rates reset on
  the model change. Golden master frozen, unilateral sets covered.
- **A kill switch** for the capacity guards (`prescriptionCapacityGuardsEnabled`).
- **Backup restore hardening** — a new enum case can no longer fail an entire
  archive decode.

Uncommitted on `NewMain`:

- **Session replay masking inverted** (this is new, 2026-08-29 — see §1.1 and §2.3).
- **Progression exclusion visibility** — the history chip and workout-detail banner
  that make the "count toward PRs" flag visible after the fact.
- **Exercise reorder** steps 1, 2 and 2a, with both live defects fixed.
- Insights service work, `InsightRuleDiagnosticsView`, and assorted test additions.

---

## 0. Settle the version number — three things hang off it

**The What's New sheet is the sharp edge.** `WhatsNewRelease.current` matches
`CFBundleShortVersionString` by **exact string equality**, and
`WhatsNewRelease.all` currently holds entries for `"1.4"` and `"1.5"` only.
Shipping as **1.4.1 shows no sheet to anyone** — silently, with no error. That
matters more than usual this release, because §2.2 is a change every existing user
will notice and the sheet is the only thing that explains it.

- [ ] Decide: **1.5**, or **1.4.1**
- [ ] If 1.5 — bump `MARKETING_VERSION` from `1.4.1` to `1.5` on **both** the app
      target and the `WorkoutLiveActivity` extension. A mismatch between them is
      rejected at upload, not at build
- [ ] If 1.4.1 — add a `"1.4.1"` entry to `WhatsNewRelease.all`, or accept that no
      sheet appears and say so out loud rather than finding out later
- [ ] Either way, re-read the existing 1.5 What's New copy against what actually
      ships. It currently promises "drop sets no longer drag the rest of the
      exercise down" and per-exercise recalibration. If suggestion work slips to
      1.6, that copy describes a release the user doesn't have
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
way." **That becomes false the moment this build reaches a user.** The rewritten
copy is already in `docs/privacy.html` (Last updated: August 29, 2026), uncommitted.

The live page matches `docs/privacy.html` on `NewMain`, **not** the copy at the root
of `main` — that one is still the May 16 page. So deploying is pushing `NewMain`,
not touching `main`.

- [ ] Commit and push the `docs/privacy.html` change
- [ ] Reload the live URL and confirm it reads "Last updated: August 29, 2026" and
      the new Session Recordings section, before submitting the build
- [ ] If the live page does *not* update, Pages is serving something else — check
      the Pages source in repo settings before assuming the push failed

### 1.2 App Review Notes

`marketing/app-store/privacy-review-checklist.md` holds the rewritten note (the
block under "Use this in the App Review Notes field"). It now says recordings show
exercise, workout and template names, that there is no user-supplied imagery, and
that recording stops while a text-entry dialogue is open.

- [ ] Paste the current note into App Store Connect for this version. It is a
      statement to Apple, and the version on file describes the 1.4 behaviour

### 1.3 What does *not* need changing — recorded so it isn't re-litigated

- `Repster/PrivacyInfo.xcprivacy` — unchanged. `Other Usage Data` already covered
  replay, and this change does not add a data type
- App Privacy answers in App Store Connect — unchanged, same reason
- The event stream — untouched. Still bucketed (`set_count_bucket: "4-6"`,
  `notes_entered: true`). Nothing in this release widens what events carry

### 1.4 dSYMs — recurring, every archive

Without a symbol upload every `$exception` frame arrives as a hex address. Per
archive, and easy to forget. Full steps in [PRE_1.4_CHECKLIST.md](PRE_1.4_CHECKLIST.md) §1.5a.

- [ ] `posthog-cli --host https://eu.posthog.com dsym upload` after archiving
- [ ] Confirm one exception in PostHog shows Swift function names

---

## 2. Know what you are shipping — the four changes that can actually hurt

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

- [ ] **53 uncommitted paths** on `NewMain`. Commit in coherent chunks — the replay
      change, the exclusion visibility work, and the exercise reorder work are three
      separate things and reviewing them as one diff later is miserable
- [ ] Push `NewMain`. It is 12 commits ahead, and pushing is also what deploys the
      privacy policy (§1.1)
- [ ] `CHANGELOG.md` is stale — its last entry is `0.1` from 2026-03-24, and it
      still claims the app uses `0.x` versioning. Either bring it up to date or
      delete it; a changelog that stops four releases back is worse than none
- [ ] The untracked `design/` directory is the Repster Coach design canvas
      (`design/coach/*.dc.html`, created 2026-08-29). **The repo is public**, so
      decide deliberately: commit it, or add it to `.gitignore`. Right now it is
      neither
- [ ] `DEVICE_TEST_PASS.md` points at "PRE_1.4_CHECKLIST.md §7.1", which does not
      exist (§7 is "Optional, not blocking"). Fix the reference or drop it

---

## 5. Known defects this release ships with — decide, don't discover

None of these are regressions. They are all live on 1.4 today. The point of listing
them is that shipping them again is a choice, and it is cheaper to make it now than
in a review reply.

- **Unperformed sets count as logged.** Copy Previous rows that were never ticked
  still count. Scoped in [UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md),
  unimplemented
- **Fixed rep targets cannot progress at all.** Separate from the undershoot fixes
  in this release, and not addressed by them
- **Bodyweight-style set labels disagree between screens.** A Pull Up at +10 kg
  reads `10 kg` in one place and `90` in another. Deferred from 1.4 (§9 there)
- **Backups exclude `BodyweightEntry`, templates and programs.** Deferred from 1.4
  (§8 there). The in-app copy is technically accurate and still misleading on a new
  device, which is the only case where anyone reaches for a backup
- **Exercise replace** is still open — reorder shipped, replace did not
- **Rest timer alarm is silent under any Focus mode.** `.timeSensitive` needs an
  entitlement the app does not have. See
  [REST_TIMER_ALARM_SCOPING.md](REST_TIMER_ALARM_SCOPING.md)

---

## 6. After release

- [ ] Watch one full session recording end to end within a day of release. It is
      the first release where recordings are legible, and the first chance to find
      out whether they are actually useful for the activation question they exist
      to answer
- [ ] Check the suggestion numbers against complaints, not against the tests. §2.2
      guarantees they moved for everyone; the question is whether they moved the
      right way
- [ ] Confirm no `$exception` frames are arriving unsymbolicated (§1.4)
