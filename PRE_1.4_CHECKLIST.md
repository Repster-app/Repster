# Pre-1.4 Launch Checklist

Current shipped version: **1.3 (build 3)**. This release adds expanded analytics,
masked session replay, in-app surveys, **crash and error tracking**, an App Store
rating prompt, **Apple Health integration** (finished workouts are written to
Health), and **Apple Search Ads attribution** (paid-vs-organic acquisition
measurement).

The analytics, HealthKit and attribution work is done and tested in the repo.
Most of what follows happens **outside** Xcode — in App Store Connect, GitHub
Pages, and PostHog — plus verification steps that must not be skipped.

⚠️ **HealthKit changes the shape of this release.** It is the first feature here
that needs a real device to verify at all, and the first that touches code
signing. Items 1.6–1.8, 2.5 and 3 exist because of it. If any of that slips, the
cleanest answer is to ship 1.4 without HealthKit rather than to ship it unverified
— the analytics work is independent and doesn't need it.

⚠️ **Attribution is the one thing not to cut.** 1.4 exists to justify higher ad
spend, and attribution is forward-only — it cannot be backfilled. Shipping 1.4
without it, scaling spend, then adding it in 1.5 makes the entire high-spend
window permanently unmeasurable: the most expensive cohort ever bought would be
the one cohort that can never be analysed. If something has to slip, slip
HealthKit (a feature that is exactly as good in 1.5) rather than this.

**Two changes in this release fail silently rather than loudly**, which is why
sections 2.3 and 1.11 exist:

- `setBeforeSend` intercepts *every* PostHog event. If the filter is wrong,
  nothing errors — events just stop arriving, and you find out weeks later. This
  already happened once: 1.2 and 1.3 shipped with no `Application Installed` at
  all, so every activation funnel ran on a denominator of zero for the whole
  live period.
- `app_version` / `build_number` were removed in favour of PostHog's own
  `$app_version` / `$app_build`. Saved insights still filtering on the old names
  will not error — they will quietly stop matching 1.4+ data.

---

## 1. Blocking — must happen BEFORE the build reaches users

### 1.1 Deploy the updated privacy policy

`docs/privacy.html` must be live at
<https://repster-app.github.io/Repster/privacy.html> **before** any build
containing session replay is released.

Why this is blocking, not housekeeping: the app now records (masked) session
replays. The currently live policy says Repster *does not* do that. Shipping the
build first means recording users under a policy that denies it.

**The content is done** (2026-08-17). All the section requirements below —
Session Recordings, In-App Surveys, Crash & Error Diagnostics, Apple Health
(§1.6), attribution (§1.9) — are already in `docs/privacy.html`, along with the
five sections the 2026-08-08 rewrite had dropped (Children's Privacy, Data
Deletion, Export/Backup/Sharing, Changes to This Policy, AI Template Feature).
**What is left is the deploy, which is now a Pages settings change.**

- [ ] Push `NewMain` with `docs/`
- [ ] Repo Settings → Pages → Source: **branch `NewMain`, folder `/docs`**
      (currently branch `main`, folder `/`)
- [ ] Confirm <https://repster-app.github.io/Repster/privacy.html> shows
      "Last updated: August 17, 2026"
- [ ] Confirm `/terms.html`, `/support.html`, `/docs.html` and `/` still resolve —
      the app links to privacy and terms from Settings, **including in versions
      already on the App Store**, so a 404 here breaks a shipped build
- [ ] Only then archive `main`. Leaving it intact means the rollback is one
      settings change.

### 1.2 App Store Connect — App Privacy

Add two new data types. Everything previously declared stays as it is.

- [ ] `Usage Data` → **`Other Usage Data`**
  - Purpose: `Analytics`
  - Linked to user: `No`
  - Used for tracking: `No`

This covers masked session recordings and multiple-choice survey answers, which
aren't cleanly covered by `Product Interaction`.

- [ ] `Identifiers` → **`Advertising Data`**
  - Purpose: `Analytics` — **not** `Third-Party Advertising`, and not
    `Developer's Advertising or Marketing`
  - Linked to user: `No`
  - Used for tracking: `No`

This covers the Apple Search Ads campaign / ad group / keyword IDs returned by
`AAAttribution`. Three things worth stating plainly so this doesn't get
re-argued at submission:

1. **No ATT prompt is required.** Apple's definition of tracking is linking
   user or device data with *third-party* data for ad targeting or measurement,
   or sharing with a data broker. AdServices is Apple's own first-party
   attribution, and PostHog / RevenueCat are processors. The fact that Apple
   designed `AAAttribution` to work without an ATT prompt is the tell.
2. **`Linked to user` stays `No`.** The campaign attaches to PostHog's random
   per-install `distinct_id` and to an anonymous RevenueCat customer. Nothing
   calls `Purchases.logIn`, and Repster has no accounts. **If a login is ever
   added, this answer changes.**
3. **RevenueCat will not declare this for you.** Its bundled manifest is static
   and only declares `Purchase History` / App Functionality — confirmed against
   the 2026-08-14 privacy report. Enabling
   `enableAdServicesAttributionTokenCollection()` does not change it, so the
   declaration has to come from `Repster/PrivacyInfo.xcprivacy` (already done).

Unchanged, but worth re-confirming while you're in there:

- [ ] `Purchases → Purchase History` — App Functionality + Analytics, not linked, not tracking
- [ ] `Health & Fitness → Fitness` — Analytics, not linked, not tracking
- [ ] `Usage Data → Product Interaction` — Analytics, not linked, not tracking
- [ ] `Identifiers → Device ID` — Analytics, not linked, not tracking
- [ ] "Used for tracking" is still **No** overall — Repster has no IDFA, no ad
      targeting, and no data brokers. Attribution does not change this.

**Resolved 2026-08-14: crash capture is now deliberately ON, so this is no longer
an either/or.** The 2026-08-14 privacy report flagged `Crash Data` and `Other
Diagnostic Data` from PostHog's embedded `PHPLCrashReporter.bundle` while
Repster's own manifest declared neither. `configureErrorTracking` in
`AnalyticsService.swift` now sets `errorTrackingConfig.autoCapture = true`, so the
aggregate report is correct and the label has to match it.

- [ ] Tick `Diagnostics` → **`Crash Data`** — Purpose: `App Functionality`,
      linked to user: `No`, used for tracking: `No`
- [ ] Tick `Diagnostics` → **`Other Diagnostic Data`** — same three answers
Both are already declared in `Repster/PrivacyInfo.xcprivacy` (added with the
capture itself), so only the ASC label is outstanding.

### 1.3 App Store Connect — App Information

- [ ] Support email → `repsterworkout@gmail.com` (now matches the app and the privacy policy)
- [ ] Confirm the Privacy Policy URL still points at the GitHub Pages page

### 1.4 App Review Notes

Replace the existing notes with the version in
`marketing/app-store/privacy-review-checklist.md` (section "App Review Notes").

It now explicitly states three things a reviewer will otherwise ask about:

- [ ] Masked session recordings are described, including that masking happens on device
- [ ] Optional multiple-choice surveys are described
- [ ] Crash and error diagnostics are described, including that they carry no workout data
- [ ] The single Share Anonymous Analytics toggle disables events, recordings, surveys
      **and crash reports** together

### 1.5 PostHog project settings

The SDK flags in the app are necessary but **not sufficient** — each of these also
has to be enabled server-side or nothing will be captured. Checked against the
live project on 2026-08-14: `session_recording_opt_in` was `false` and
`surveys_opt_in` unset, so at that point a shipped 1.4 would have recorded nothing.

- [ ] Enable **Session Replay** ("Record user sessions") in project settings (EU cloud project)
- [ ] Enable **Surveys** in project settings
- [ ] Enable **exception autocapture** in error tracking settings. The iOS SDK reads
      this at startup and skips installing the crash handler when it's off, so a
      build with `errorTrackingConfig.autoCapture = true` can still capture nothing
- [ ] Confirm the project is still the EU instance (`https://eu.i.posthog.com`)

None of these can leak backwards into 1.3: the released binary has no replay,
survey or crash-handler code paths at all, so enabling them only ever affects
1.4+ installs. Flipping them early is safe.

### 1.5a Upload dSYMs, or crash reports are unreadable

Without symbol upload every `$exception` frame arrives as a hex address. This is
per-archive and easy to forget, which is the whole reason it's on the list.

- [ ] Create a **personal API key** with `error tracking: write` and
      `organization: read` scopes (PostHog → user API keys)
- [ ] Xcode → target → Build Settings → **Debug Information Format** =
      `DWARF with dSYM File` for Release
- [ ] Install `posthog-cli` (min 0.7.7) and authenticate against the **EU** host:
      `posthog-cli --host https://eu.posthog.com login`
- [ ] Upload the dSYMs after archiving — `posthog-cli --host https://eu.posthog.com dsym upload`,
      or wire posthog-ios's bundled `upload-symbols.sh` into a build phase
- [ ] Confirm in PostHog that a test exception shows Swift function names, not addresses

Not release-blocking in the strict sense — dSYMs can be uploaded after the fact
from the archive — but a crash you can't read is a crash you won't fix.

### 1.6 Privacy policy must describe Apple Health

Apple requires any app with the HealthKit entitlement to have a privacy policy
covering its health-data handling. `docs/privacy.html` was rewritten
on 2026-08-08 and predates the integration, so it doesn't mention Health at all.

Repster's story here is short and unusually clean, so say it plainly:

- [ ] Add an **Apple Health** section stating that Repster *writes* finished
      workouts to Health, and that the **only** read is looking up a workout
      Repster itself wrote so it can be deleted from Health again — no other
      health data is ever read
- [ ] State that the integration is off until the user enables it in Settings
- [ ] State that estimated calories are opt-in, off by default, and estimated
      rather than measured
- [ ] State that health data is never sent to Repster's servers or to any third
      party (it goes only to the user's own Health store on device)
- [ ] Redeploy and re-confirm the live URL, as in 1.1

Same reasoning as 1.1: shipping the build first means writing to a user's Health
store under a policy that never mentions it.

### 1.7 App Review Notes — HealthKit

Reviewers check that HealthKit behaviour matches the usage description, and
write-only integrations get asked about because they're less common than read.

- [x] State that Repster requests **write access only** — `requestAuthorization` is
      called with an empty read set (`HealthKitService.swift:101`), which is what
      makes this true. ⚠️ **`NSHealthShareUsageDescription` *is* present**
      (`Info.plist:66`) — an earlier version of this checklist said it was absent
      and that its absence proved write-only. That is wrong and must not be said to
      review. The key is there so `deleteWorkout` can locate the workout Repster
      itself wrote (`HealthKitService.swift:227`); explain it that way instead
- [ ] State where the permission prompt appears: **Settings → Body → Apple Health**,
      on an explicit toggle. Never at launch, never during onboarding
- [ ] Note that reviewers must enable the toggle themselves to see anything happen
- [ ] Note that active energy is a **separate opt-in**, default off, and is a
      MET-based estimate rather than a measurement

That last point is worth stating before a reviewer infers Repster is claiming to
measure calories.

### 1.8 App Store Connect — App Privacy (HealthKit changes nothing)

Deliberately a no-op, recorded so it doesn't get re-litigated at submission.

The App Privacy answers describe data the app **collects**. Repster writes to the
user's Health store and reads nothing back, so no data is collected and no new
declaration is required. The existing `Health & Fitness → Fitness` entry covers
analytics about in-app workout activity and is unrelated to HealthKit.

- [ ] Confirm no new App Privacy data type was added for HealthKit
- [ ] Confirm `Repster/PrivacyInfo.xcprivacy` needs no change — writing to
      HealthKit is not a required-reason API and collects nothing

If a read path is ever added (bodyweight from Health is the obvious candidate),
**this stops being true** and `Health & Fitness → Health` has to be declared.

### 1.9 Privacy policy must describe Apple Search Ads attribution

Same reasoning as 1.1 and 1.6: the policy currently says nothing about ad
attribution, and shipping the build first means collecting campaign data under a
policy that doesn't mention it.

Repster's story here is short, so say it plainly:

- [ ] Add an **Advertising & Attribution** section to
      `docs/privacy.html` stating that Repster asks Apple whether an
      install came from one of its Apple Search Ads campaigns
- [ ] State what is received: a campaign, ad group and keyword identifier, plus
      the country and whether it was a first download or a reinstall
- [ ] State plainly that **no advertising identifier (IDFA) is read**, no profile
      is built, and the data is never linked with anything from a third party —
      which is why no tracking permission prompt appears
- [ ] State that it is covered by the same **Share Anonymous Analytics** toggle
      as everything else, and that turning it off stops it entirely
- [ ] Redeploy and re-confirm the live URL, as in 1.1

That fourth point is a promise the code has to keep — see 2.6.

### 1.10 App Review Notes — attribution

- [ ] State that Repster uses `AdServices` / `AAAttribution` for first-party
      Apple Search Ads attribution only
- [ ] State that there is no ATT prompt because no IDFA is requested and no data
      is shared with third parties for tracking
- [ ] Note that the App Privacy answer is `Advertising Data`, Analytics purpose,
      not linked, not used for tracking

### 1.11 PostHog — migrate saved insights off the removed properties

**This is the silent one.** `app_version` and `build_number` no longer exist as
app-stamped properties. Any *saved* insight, dashboard tile, cohort or survey
targeting rule still filtering or breaking down by them will not error — it will
quietly stop matching 1.4+ data and read as a cliff that never happened.

- [ ] Search saved insights and dashboards for `app_version` and `build_number`,
      and switch each to `$app_version` / `$app_build`
- [ ] Check **cohort** definitions and **survey targeting** rules for the same
- [ ] Data Management → Properties: mark `app_version` and `build_number`
      deprecated so they stop appearing in autocomplete
- [ ] Re-check the section 5 dashboard list in `POSTHOG_ANALYTICS_GUIDE.md` —
      insight 5 (version mix) changed event *and* breakdown, so rebuilding it is
      not just a property swap

Note `$app_build` is an integer and sorts properly; `build_number` was a string
and did not.

### 1.12 Privacy policy must describe crash & error diagnostics

Same reasoning as 1.1, 1.6 and 1.9: 1.4 starts collecting a category of data the
live policy doesn't mention. Crash capture is the newest of the three and the one
most likely to be forgotten, because unlike Health and attribution it has no
visible feature attached to it.

Draft copy lives in `marketing/app-store/privacy-review-checklist.md` under
"Privacy Policy Copy To Include". The points it has to make:

- [ ] Add a **Crash & Error Diagnostics** section to `docs/privacy.html`
- [ ] State what triggers a report: a crash, or an error Repster recovers from
      silently (an Apple Health write, a subscription refresh, a backup export or
      restore)
- [ ] State what a report contains: the error and where in the app it happened,
      plus device model, iOS version and app version
- [ ] State plainly what it never contains — workouts, exercise names, weights,
      reps, notes, bodyweight. This is a checkable promise, and 2.1a is the check
- [ ] State that crash reports are stored on device and sent on the **next launch**,
      so a report can outlive the session that produced it
- [ ] State that **Share Anonymous Analytics** turns these off with everything else
- [ ] Bump "Last updated" and redeploy, then re-confirm the live URL as in 1.1

That last-but-one point is a promise the code has to keep — `captureError` checks
`isCollectionEnabled` and `config.optOut` suppresses autocaptured crashes. 2.2 is
the check.

---

## 2. Verification — do this on TestFlight, before the App Store release

### 2.1 Prove the masking works

**Do not skip this.** The privacy policy now makes a specific, checkable promise
that no workout content appears in recordings. Verify it rather than trusting it.

- [ ] Install the TestFlight build
- [ ] Log a full workout: several exercises, real weights and reps, a note, a bodyweight entry
- [ ] Wait a few minutes, then open the recording in PostHog
- [ ] Confirm **no** readable text anywhere — no exercise names, no numbers, no notes
- [ ] Confirm images are masked too

If any text is readable, stop the release and fix it before shipping.

### 2.1a Prove crash capture works

Crashes are written to disk and uploaded on the **next** launch, so this needs two
launches and is easy to conclude has failed when it merely hasn't happened yet.

- [ ] Force a crash in a TestFlight build (a deliberate `fatalError` behind a debug
      gesture, or `PostHogSDK.shared.captureException` for the handled path)
- [ ] Relaunch the app, wait a few minutes
- [ ] Confirm the `$exception` issue appears in PostHog Error Tracking
- [ ] Confirm the stack trace shows Swift function names — if it's hex addresses,
      the dSYM upload in 1.5a didn't happen for this archive
- [ ] Confirm `error_context` is set on the handled-error path (`healthkit_workout_write`,
      `subscription_refresh`, `backup_export`, …)

### 2.2 Prove the opt-out works

- [ ] Settings → Data & Backups → turn **Share Anonymous Analytics** off
- [ ] Force-quit and relaunch the app a few times, log a workout
- [ ] Confirm PostHog receives **nothing** — no events, no `Application Opened`, no recordings
- [ ] Force a crash while opted out, relaunch, and confirm **no** `$exception` arrives

The second half matters: PostHog fires lifecycle events inside SDK setup, so an
opted-out user used to leak one event per launch. That's fixed via
`startOptedOut`, and this is the check that it actually holds.

### 2.3 Sanity-check the events — and prove the lifecycle filter didn't eat them

**The order here matters.** `setBeforeSend` runs on *every* event, not just
lifecycle ones, so the first thing to establish is that ordinary events still
arrive at all. A filter bug produces silence, not an error, and 1.2/1.3 are the
proof that silence goes unnoticed for a whole release cycle.

Log a couple of workouts on TestFlight, then confirm — **in this order**:

- [ ] **Ordinary events still arrive.** `workout started` → `first set logged` →
      `workout completed`. If these are missing, stop: `LifecycleEventFilter` is
      dropping everything and nothing else on this list is worth checking.
- [ ] `onboarding step viewed` for each step, and `onboarding completed`
- [ ] `empty state shown` (fresh install, open Charts before logging anything)
- [ ] `$screen` events for the curated screen names
- [ ] Persons tab shows one person with a coherent event timeline

Then the filter's *intended* behaviour, which is what 1.4 actually changed:

- [ ] `Application Installed` appears **once**, on the fresh install
- [ ] `Application Opened` appears on a **cold launch** and carries `version` /
      `build`
- [ ] Background the app and return to it several times — `Application Opened`
      must **not** fire again for those resumes
- [ ] `Application Backgrounded` does **not** appear at all, ever
- [ ] `Application Updated` appears when upgrading over an older build (needs a
      1.3 install first, then the TestFlight update on top)

- [ ] Every event carries `$app_version` and `$app_build`, and **no** event
      carries `app_version` or `build_number`

### 2.4 Rating prompt

- [ ] Complete 3 workouts on a fresh install and confirm the prompt appears
- [ ] Confirm it does **not** appear right after the paywall is shown

Note StoreKit only shows the real prompt a limited number of times per year and
suppresses it in some builds, so absence isn't proof of a bug — check that
`review prompt requested` fired in PostHog instead.

### 2.5 Apple Health — **must be done on a physical device**

HealthKit in the simulator is unreliable, so none of this counts if it's only been
seen on a simulator. This is the one part of 1.4 that cannot be verified at a desk.

**Permission behaviour**

- [ ] Fresh install, complete onboarding, log a workout — confirm **no** Health
      permission prompt appears anywhere in that flow
- [ ] Settings → Body → toggle **Apple Health** on — confirm the prompt appears
      *now*, and lists workouts (and active energy) as write-only
- [ ] Decline the prompt — confirm the toggle returns to off and the alert points
      at the Health app rather than silently failing

**The actual write**

- [ ] With the toggle on, finish a workout, then open Apple Health → Browse →
      Activity → Workouts and confirm it's there
- [ ] Confirm the type reads **Traditional Strength Training** and the duration
      matches what Repster showed (paused time should be excluded)
- [ ] Confirm workouts finished *before* the toggle was enabled did **not**
      appear — there is deliberately no backfill

**Energy**

- [ ] Confirm **Estimated Calories** is off by default
- [ ] With it off, confirm the workout in Health shows no active energy
- [ ] Turn it on with a bodyweight logged, finish a workout, confirm calories
      appear and are in a sane range (roughly 3.5 × bodyweight-kg × hours)
- [ ] With **no** bodyweight ever logged, confirm the workout still syncs, just
      with no energy — and that the "Add your bodyweight" hint shows in Settings

**Deletion and restore — the two that can embarrass you**

- [ ] Delete a synced workout in Repster, confirm it disappears from Health too
- [ ] Restore a backup containing completed workouts and confirm **nothing** is
      pushed to Health. Import creates completed workouts directly, so a
      regression here would dump a user's entire history into their Health app

If the restore check fails, stop — that one is far more damaging than a missing
workout.

### 2.6 Attribution — what *can* be checked before release

Most of attribution genuinely cannot be verified until it is live: the simulator
throws on `AAAttribution.attributionToken()`, and TestFlight installs come back
`attribution: false` because they did not come from an ad. **Do not burn a day
trying to make a real campaign resolve on TestFlight — it will not.** The live
check is 3.4.

What *is* checkable now:

- [ ] Regenerate the privacy report (Xcode → Archive → Organizer → right-click
      the archive → **Generate Privacy Report**) and diff it against
      `Repster-PrivacyReport 2026-08-14 12-23-52.pdf`
- [ ] Exactly **one** new section appears: `Advertising Data`
- [ ] Every existing `Tracking` and `Linked` column still reads `NO`. If
      `Tracking` flips to `YES` anywhere, stop — that means an ATT prompt is now
      required and the App Privacy answers in 1.2 are wrong
- [ ] The build links `AdServices.framework` without a linker error
- [ ] **Prove the opt-out covers attribution.** Turn Share Anonymous Analytics
      off on a fresh install, relaunch, and confirm no request to
      `api-adservices.apple.com` is made and no `attribution resolved` event is
      sent. This is the promise 1.9 puts in the published privacy policy;
      `AttributionServiceFactory.makeService` returning `nil` is what keeps it,
      and it also suppresses RevenueCat's collector
- [ ] Turn the toggle back on, relaunch, and confirm attribution *does* then
      attempt to resolve — the stored state stays `pending`, so a user who opts
      in later is not permanently lost

---

## 3. Release mechanics

### 3.1 HealthKit capability on the App ID — do this first, on its own

Repster had **no entitlements file at all** before this release. 1.4 introduces
`Repster/Repster.entitlements` and sets `CODE_SIGN_ENTITLEMENTS` on both app-target
configs. Signing is `Automatic` on team `8HPA5639FW`, so Xcode should register the
HealthKit capability on the App ID and refresh provisioning by itself — but that
has only ever been compiled against a **simulator**, never a real profile.

This is a build-time failure mode, not a compile-time one, which is exactly the
kind that surfaces at 11pm during an archive.

- [ ] Build to a physical device and confirm signing succeeds
- [ ] Confirm HealthKit now appears as a capability on the App ID in the developer portal
- [ ] Do this **before** bundling it with the rest of the release, so a signing
      problem is isolated from everything else

### 3.2 The rest

- [ ] Bump `MARKETING_VERSION` to `1.4` and `CURRENT_PROJECT_VERSION` to `4`
- [ ] Commit the analytics work (currently uncommitted on `NewMain`)
- [ ] Commit the HealthKit work (also uncommitted on `NewMain`) — worth keeping as
      its own commit, separate from analytics and from the Insights work in the
      same tree
- [ ] Commit the attribution work (`AttributionService.swift`,
      `AttributionServiceProtocol.swift`, `AttributionServiceTests.swift`, the
      `PrivacyInfo.xcprivacy` entry and the `RepsterApp` wiring) — again worth
      its own commit
- [ ] Archive and upload
- [ ] Write release notes — the rating prompt, analytics and attribution don't
      need mentioning, but **Apple Health does**: it's the one user-facing
      feature in 1.4 and the reason someone might update

### 3.4 Attribution — verify on live traffic BEFORE scaling ad spend

**Do not raise the ASA budget on release day.** Attribution cannot be verified
before release (2.6), so the first real evidence that it works arrives only once
1.4 is live. Scaling spend at the same moment means that if resolution is broken,
the entire increased budget is spent blind — which is precisely the failure this
release exists to prevent.

Leave spend where it is, then:

- [ ] Wait for organic 1.4 installs and confirm `attribution resolved` events are
      arriving in PostHog at all
- [ ] Confirm organic installs resolve with `acquisition_channel = organic`
- [ ] Confirm at least one **ASA-attributed** install resolves with
      `acquisition_channel = apple_search_ads` and a non-null `asa_campaign_id`
- [ ] Cross-check that campaign ID against the campaign in the Apple Search Ads
      console — they are the same identifier space
- [ ] Confirm RevenueCat is showing campaign data on new customers
- [ ] Spot-check `asa_conversion_type` — a high `redownload` share means your
      "new user" funnels are partly returning users, and your cost-per-install
      maths is counting reinstalls

Only once `apple_search_ads` installs are actually resolving:

- [ ] **Then** raise the budget

Rough expectation: resolution should land within minutes of install for most
users. A meaningful share of installs never resolving (state stuck `pending`
through the 8-launch budget) means something is wrong with the endpoint call, not
with Apple.

### 3.3 What's New sheet — only when there's something worth showing

If the What's New sheet ships in this build, what it says is a decision to make
here, not at archive time.

The sheet is built to stay silent. `WhatsNewRelease.current` returning `nil` means
no sheet appears at all, and for most releases that's the correct outcome rather
than a failure to fill it in.

The test for an item is whether **the user can go and look at it in under ten
seconds**. Apple Health passes: open Settings, connect, see it. "Findings repeat
less often" doesn't — it's true, it's an improvement, and there's nothing to go
and check. Unverifiable items are what teach people to dismiss the sheet unread,
and once that habit sets in the sheet is worthless for the release that actually
needs it.

Three items is the cap. The fourth is reliably the one that fails the test.

For 1.4 that means Apple Health, plus the Training Insights v2 work only if it
ships in the same build. Analytics, session replay and the rating prompt are not
items, for the same reason they're not release notes.

- [ ] Confirm which 1.4 changes pass the ten-second test
- [ ] Write at most three items, each naming something the user can open and see
- [ ] If nothing passes, ship with `WhatsNewRelease.current == nil` and confirm no
      sheet appears on first launch after updating
- [ ] On TestFlight, confirm the sheet appears once and does not return on the
      next launch

#### Offering Apple Health from the sheet

Existing users never see onboarding, so the sheet is the only thing that reaches
them — without it, Health is switched on by whoever happens to open Settings and
scroll to Body. That is close to nobody.

`AppleHealthPromptView` is built to be presented as-is. The host owns the model
and reports the impression:

```swift
let connection = AppleHealthConnectionModel(
    healthKitService: services.healthKitService,
    analyticsService: services.analyticsService,
    source: .whatsNew
)
// gate on this, not on `isAvailable` — it's false once the user has already
// answered anywhere, so a fresh 1.4 install that saw the onboarding step
// doesn't get asked twice
if services.healthKitService.shouldOfferConnection { … }
// then call connection.promptShown() when it's actually on screen
```

- [ ] Decide whether the offer is one of the three items or a step after them
- [ ] Confirm a user who answered during onboarding is not asked again
      (`shouldOfferConnection` is false once `healthkit.hasBeenOffered` is set)
- [ ] Check `apple health prompt shown` / `answered` arrive with `source: whats_new`

---

## 4. After release — reading the data

Give it **1–2 weeks** before drawing conclusions. Two things lag by design:

- `workout abandoned` only fires on the *next* app open after a 12-hour staleness
  threshold, so it trails real behaviour by a day or more.
- Retention curves need the cohort to actually age.

The funnel to build first:

```
Application Installed
  → onboarding completed
  → workout started
  → first set logged
  → workout completed
  → workout completed (2nd, within 7 days)
```

Wherever the biggest cliff is, that's the problem worth fixing. Best guess going
in: between the first completed workout and the second.

**Now split that funnel by `acquisition_channel`.** This is the payoff of 1.4 and
the reason attribution was worth shipping. `acquisition_channel` is a *person*
property, so it segments every event a user ever fired, including the
first-session events that happened before attribution resolved. Build the funnel
above twice — once filtered to `apple_search_ads`, once to `organic` — and the
question that has been unanswerable until now finally has an answer:

- **Both channels drop at the same step:** activation is genuinely broken for
  everyone. Fix the product, and higher spend will not help until you do.
- **Only paid drops:** the product is fine and the targeting is buying
  low-intent installs. Fix keywords and the product page, not the app.

These need completely different work, and averaging them together — which is all
that was possible before 1.4 — hides both.

Break `asa_keyword_id` down the same way once volume allows. Keywords with high
install volume and near-zero activation are costing you twice: once in spend, and
again by dragging every average in this document downward.

⚠️ **Three instrumentation regimes now exist. Do not read any all-time trend
without accounting for them:**

| Versions | Lifecycle events |
|---|---|
| 1.1 | all four, unfiltered |
| 1.2, 1.3 | **none** — no `Application Installed` at all |
| 1.4+ | `Installed` / `Updated` / cold `Opened` only |

A plain all-time trend on `Application Opened` therefore shows volume, then zero,
then differently-shaped volume — an instrumentation artifact that looks exactly
like a product collapse and a recovery. See gap 8 in `POSTHOG_ANALYTICS_GUIDE.md`.
Anything captured from a debug build before 2026-08-10 is separately contaminated
(gap 6). `acquisition_channel` exists only from 1.4 onward, so paid-vs-organic
comparisons cannot reach back before this release.

**Caveat when reading install counts.** The PostHog identifier is an *install*
identity, not a person. It resets on delete-and-reinstall and on restoring to a
new phone from backup (the SDK excludes its storage from iCloud backups). So
`Application Installed` will run slightly ahead of true new users. Compare against
App Store Connect's first-time downloads, which deduplicate by Apple ID. Apple's
own `conversionType` gives you the other half of this: `asa_conversion_type =
redownload` marks the reinstalls explicitly, for ASA installs at least.

---

## 5. Keep in sync if privacy-facing settings ever change

These five files describe the same privacy posture. Changing one without the
others makes the published policy wrong:

1. `Repster/Core/Services/AnalyticsService.swift` — the SDK config
2. `Repster/Core/Services/AttributionService.swift` — what attribution collects,
   and the opt-out gate in `AttributionServiceFactory` that keeps the single
   toggle honest
3. `docs/privacy.html` — the live policy
4. `marketing/app-store/privacy-review-checklist.md` — ASC answers + review notes
5. `Repster/PrivacyInfo.xcprivacy` — the privacy manifest

Crash and error capture (`configureErrorTracking`, added 2026-08-14) is on this
list — it *widens* what is collected, which is why 1.1 gains a policy section and
1.2 gains two `Diagnostics` declarations. The opt-out gate is what keeps it
consistent with the rest: `AnalyticsService.captureError` checks
`isCollectionEnabled`, and `config.optOut` suppresses autocaptured crashes.

The lifecycle-filter and version-property changes in 1.4 are deliberately **not**
on this list: both only *reduce* what is collected, so no policy, label or
manifest change follows from them. Recorded here so it isn't re-litigated at
submission.

Attribution is on the list. Anything that widens it — a new field kept from
Apple's response, sending campaign data anywhere new, or adding a login that
would make `Linked to user` become `Yes` — changes all five together.

The same applies to HealthKit, with one extra file. **If a read path is ever added**
— bodyweight from Health being the obvious candidate — all of these change together,
and `Health & Fitness → Health` becomes a required App Privacy declaration:

1. `Repster/Repster.entitlements` — the entitlement
2. `Repster/Info.plist` — usage descriptions. Both keys are already present; what
   proves write-only is the empty read set passed to `requestAuthorization`, not
   the absence of the share key. A read path would change the call, not the plist
3. `docs/privacy.html` — the Apple Health section from 1.6
4. `marketing/app-store/privacy-review-checklist.md` — ASC answers + review notes
5. `HEALTHKIT_INTEGRATION_EXPLORATION.md` — the design record, which currently
   documents the read path as explicitly out of scope

---

## 6. Ad-side work with no build dependency — start now, don't wait for 1.4

None of this ships in the binary, so none of it is gated on the release. All of
it multiplies whatever the increased ad spend buys.

**Custom Product Pages — the message-match problem.** ASA generates ads against
the default product page, which still opens with the "fast lifting log" line,
while the current ad test sells the fatigue / e1RM model. Every paid click
currently lands on a page arguing something other than the ad that earned it.
CPPs are free, you get up to 35, ASA campaigns can target one directly, and they
report separately in App Store Connect.

- [ ] Build a Custom Product Page whose first screenshot and opening line match
      the technical-positioning ad copy in `marketing/campaigns/technical-lifter`
- [ ] Point the technical-positioning campaign at it
- [ ] Compare its conversion against the default page before drawing conclusions
      about the ads themselves

**Campaign links, so "organic" stops being a garbage bucket.** AdServices only
knows about Apple Search Ads. Every off-store link — Reddit, a landing page, a
bio — resolves as `organic`, indistinguishable from genuine App Store search.
Apple's answer is campaign link tokens, which surface in App Store Connect.

- [ ] Append `ct=` (plus `pt=` / `mt=`) to every App Store URL posted anywhere
- [ ] Agree a naming convention now, before there are twenty untagged links
- [ ] Note this is App Store Connect data, **not** PostHog — it will not appear
      in `acquisition_channel`

**Store conversion rate.** Upstream of everything in section 4: if the product
page converts badly, every in-app funnel is being fed pre-filtered traffic.

- [ ] Check product page views → downloads in App Store Connect, and treat it as
      the first step of the activation funnel rather than a separate number

---

## 7. Optional, not blocking

- [ ] Consider a `contact@repster.site` alias forwarding to `repsterworkout@gmail.com`, so the address on the public policy page stays disposable if it gets scraped
- [ ] Write the first PostHog survey — one multiple-choice question, targeted at users who completed one workout and haven't returned in 5 days
- [ ] Line up 5 user interviews (r/fitness, r/weightroom, r/gainit, lifting Discords). At this stage these will teach you more than the dashboard will
- [ ] Screen views for the exercise list and templates screens are deliberately left untracked — revisit if the funnel points at browsing as the drop-off

---

## 8. Reconsider the backup's scope — DEFERRED TO 1.5 (decided 2026-08-14)

> **Deferred.** Not blocking for 1.4 and explicitly postponed to get 1.4 out. The
> `BodyweightEntry` gap is the one to do first when this is picked up. Nothing here
> is a regression — it is all pre-existing behaviour.


Raised 2026-08-13, after auditing a real 11,785-set export against the model layer.

**Sets themselves are complete.** `WorkoutHistoryArchiveSet` carries all 39 stored
properties of `WorkoutSet` — including `rir`, `leftRIR`/`rightRIR`, `side`,
`restDurationSeconds`, the target and override fields. Nothing is silently dropped at
the set level. (Checked because RIR looked missing; it isn't — 454 sets in the sample
carry one.)

**What a backup does not contain:**

| Excluded | Consequence on restore to a new device |
|---|---|
| `BodyweightEntry` | the bodyweight log is gone |
| `WorkoutTemplate` / `TemplateExercise` / `TemplateSet` | templates gone |
| `Program` / `ProgramExercise` / `PlannedWorkout` / `PlannedSet` | programs gone |
| `InsightRecord` | insight history gone |
| `HealthProfile` | only 3 of 24 fields survive (the fatigue-learning ones) |
| `ExerciseStats`, `PerformanceRecord` | **fine** — deliberately rebuilt on restore |

**This is not a bug, and the in-app copy is not wrong.** `SettingsView.swift:979` says
*"Restoring replaces workout history only. Templates, programs, bodyweight logs, and
settings stay untouched."* That is accurate.

**The gap is what it describes.** That sentence covers what restore will not
*overwrite*, not what the backup does not *contain*. The two readings coincide on the
device you exported from and diverge completely on a new one — which is the case that
matters, because it is the case where someone reaches for a backup. `ExportView.swift:52`
saying the file is *"meant for full restore"* pulls in the same wrong direction.

**The decision:**

- [ ] **Add `BodyweightEntry` to the archive.** The strongest candidate by far: the rows
      are tiny, and `effectiveWeight` for every bodyweight-style exercise depends on the
      bodyweight log for *future* sets. Historical sets are safe (their `effectiveWeight`
      is stored), so this is about the app still working correctly after a restore, not
      about recovering old numbers.
- [ ] **Decide on templates and programs** — either include them or say plainly on the
      export screen that they are not covered.
- [ ] **Reword the export screen** to describe contents rather than restore semantics,
      whatever is decided above. "Workout history, exercises and set details" is honest;
      "full restore" currently is not.

**Unrelated detail found in the same audit, worth knowing:** restore ends with
`prService.rebuildAll()`, which discards the PR badges the archive did export and
recomputes them. Among sets with identical weight and reps, which one gets the badge is
decided by fetch order, so restoring the same backup twice can put the star on a
different row. Cosmetic — counts and numbers are identical — and it is why
`RealDataDifferentialTests` tallies badges per exercise rather than per set.

---

## 9. Bodyweight-style sets read differently on different screens — DEFERRED TO 1.5 (decided 2026-08-14)

> **Deferred.** Cosmetic, pre-existing, and shipping in 1.3 already. Postponed to
> get 1.4 out. `WorkoutJourneyTests` still pins the current `10 kg` behaviour, so
> nothing silently drifts in the meantime.


Found 2026-08-13 while converting `ExerciseHistoryView` to snapshots. **Not caused by that
work** — it is pre-existing, and the conversion deliberately preserved it rather than quietly
changing what a screen shows during a type refactor.

### What happens

Take a Pull Up (bodyweight-style, `bodyweightFactor` 1.0) logged at **+10 kg for 6 reps** with a
bodyweight of 80 kg. The set stores `weight = 10` and `effectiveWeight = 90`. Those are both
correct. But the read-only surfaces disagree about which one to show:

| Surface | Renders | Via |
|---|---|---|
| History tab — active workout **and** exercise detail | `10 kg × 6` | `ExerciseHistoryView` → `display(...)` |
| Exercise Info top-set card, active workout screen | `10 kg × 6` | `ExerciseInfoProvider.formatTopSetLabel` → `performanceLabel(...)` |
| Calendar / workout-detail cards | `90` | `CalendarExerciseCard` → `fieldDisplay(...)` |

Two entry points on the same formatter with different rules:
`performanceLabel` builds from the raw `weight` (`WorkoutSetPerformanceFormatter:314`), while
`fieldDisplay` resolves `effectiveWeight ?? weight` (`:171`).

### Why this is a judgement call, not an obvious bug

The raw-weight path is not an oversight — it takes an `isBodyweightStyle` flag and uses it, but
only for one case: `weight <= 0` renders **`BW`** (`:413`). So the intent was clearly "say BW when
there is no added load."

What is missing is the other half of that intent. With added load it prints `10 kg` with nothing
marking it as *additional*, so on a Pull Up it reads as though 10 kg was lifted. `BW` and `10 kg`
are inconsistent renderings of the same idea — one names the bodyweight, the other silently omits
it.

Scope: bodyweight-style exercises with added load only. Pure bodyweight sets (`weight = 0`) show
`BW` and are fine. Non-bodyweight exercises have `effectiveWeight == weight`, so nothing differs.
Cosmetic — no data is wrong, no calculation uses these labels.

### The decision

- [ ] **Pick one meaning for these labels.** Either `BW+10 kg` (added load, made explicit — most
      consistent with the existing `BW` case and with what the user typed) or `90 kg` (total load —
      consistent with the detail cards). The one thing not worth keeping is the current `10 kg`,
      which reads as a bare weight.
- [ ] **Apply it to both `performanceLabel` consumers** — the History tab and the Exercise Info
      top-set card — or the two active-workout surfaces will still disagree with each other.

**Pinned by a test.** `WorkoutJourneyTests.testHistorySubTabShowsPastSessionsNewestFirst` asserts
the current `10 kg` behaviour, so changing it fails the suite and registers as a deliberate
behaviour change rather than a tidy-up. Update that assertion as part of whichever option is
chosen.
