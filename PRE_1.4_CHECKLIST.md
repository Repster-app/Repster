# Pre-1.4 Launch Checklist

Current shipped version: **1.3 (build 3)**. This release adds expanded analytics,
masked session replay, in-app surveys, an App Store rating prompt, and **Apple
Health integration** (finished workouts are written to Health).

The analytics and HealthKit work is done and tested in the repo. Most of what
follows happens **outside** Xcode — in App Store Connect, GitHub Pages, and
PostHog — plus verification steps that must not be skipped.

⚠️ **HealthKit changes the shape of this release.** It is the first feature here
that needs a real device to verify at all, and the first that touches code
signing. Items 1.6–1.8, 2.5 and 3 exist because of it. If any of that slips, the
cleanest answer is to ship 1.4 without HealthKit rather than to ship it unverified
— the analytics work is independent and doesn't need it.

---

## 1. Blocking — must happen BEFORE the build reaches users

### 1.1 Deploy the updated privacy policy

`marketing/website/privacy.html` was rewritten on 2026-08-08 and must be live at
<https://repster-app.github.io/Repster/privacy.html> **before** any build
containing session replay is released.

Why this is blocking, not housekeeping: the app now records (masked) session
replays. The currently live policy says Repster *does not* do that. Shipping the
build first means recording users under a policy that denies it.

- [ ] Commit and push `marketing/website/privacy.html`
- [ ] Confirm the live URL shows "Last updated: August 8, 2026"
- [ ] Confirm the live page has the **Session Recordings** and **In-App Surveys** sections
- [ ] Confirm the contact address reads `repsterworkout@gmail.com`

### 1.2 App Store Connect — App Privacy

Add one new data type. Everything previously declared stays as it is.

- [ ] `Usage Data` → **`Other Usage Data`**
  - Purpose: `Analytics`
  - Linked to user: `No`
  - Used for tracking: `No`

This covers masked session recordings and multiple-choice survey answers, which
aren't cleanly covered by `Product Interaction`.

Unchanged, but worth re-confirming while you're in there:

- [ ] `Purchases → Purchase History` — App Functionality + Analytics, not linked, not tracking
- [ ] `Health & Fitness → Fitness` — Analytics, not linked, not tracking
- [ ] `Usage Data → Product Interaction` — Analytics, not linked, not tracking
- [ ] `Identifiers → Device ID` — Analytics, not linked, not tracking
- [ ] "Used for tracking" is still **No** overall — Repster has no IDFA, no ads, no data brokers

### 1.3 App Store Connect — App Information

- [ ] Support email → `repsterworkout@gmail.com` (now matches the app and the privacy policy)
- [ ] Confirm the Privacy Policy URL still points at the GitHub Pages page

### 1.4 App Review Notes

Replace the existing notes with the version in
`marketing/app-store/privacy-review-checklist.md` (section "App Review Notes").

It now explicitly states three things a reviewer will otherwise ask about:

- [ ] Masked session recordings are described, including that masking happens on device
- [ ] Optional multiple-choice surveys are described
- [ ] The single Share Anonymous Analytics toggle disables events, recordings, and surveys together

### 1.5 PostHog project settings

The SDK flags in the app are necessary but **not sufficient** — both features also
have to be enabled server-side or nothing will be captured.

- [ ] Enable **Session Replay** in project settings (EU cloud project)
- [ ] Enable **Surveys** in project settings
- [ ] Confirm the project is still the EU instance (`https://eu.i.posthog.com`)

### 1.6 Privacy policy must describe Apple Health

Apple requires any app with the HealthKit entitlement to have a privacy policy
covering its health-data handling. `marketing/website/privacy.html` was rewritten
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

- [ ] State that Repster requests **write access only** — `NSHealthUpdateUsageDescription`
      is present and there is deliberately no `NSHealthShareUsageDescription`
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

### 2.2 Prove the opt-out works

- [ ] Settings → Data & Backups → turn **Share Anonymous Analytics** off
- [ ] Force-quit and relaunch the app a few times, log a workout
- [ ] Confirm PostHog receives **nothing** — no events, no `Application Opened`, no recordings

The second half matters: PostHog fires lifecycle events inside SDK setup, so an
opted-out user used to leak one event per launch. That's fixed via
`startOptedOut`, and this is the check that it actually holds.

### 2.3 Sanity-check the new events

Log a couple of workouts on TestFlight and confirm these appear in PostHog:

- [ ] `Application Installed` / `Application Opened`
- [ ] `onboarding step viewed` for each step, and `onboarding completed`
- [ ] `workout started` → `first set logged` → `workout completed`
- [ ] `empty state shown` (fresh install, open Charts before logging anything)
- [ ] Persons tab shows one person with a coherent event timeline

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
- [ ] Archive and upload
- [ ] Write release notes — the rating prompt and analytics don't need mentioning,
      but **Apple Health does**: it's the one user-facing feature in 1.4 and the
      reason someone might update

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

**Caveat when reading install counts.** The PostHog identifier is an *install*
identity, not a person. It resets on delete-and-reinstall and on restoring to a
new phone from backup (the SDK excludes its storage from iCloud backups). So
`Application Installed` will run slightly ahead of true new users. Compare against
App Store Connect's first-time downloads, which deduplicate by Apple ID.

---

## 5. Keep in sync if privacy-facing settings ever change

These four files describe the same privacy posture. Changing one without the
others makes the published policy wrong:

1. `Repster/Core/Services/AnalyticsService.swift` — the SDK config
2. `marketing/website/privacy.html` — the live policy
3. `marketing/app-store/privacy-review-checklist.md` — ASC answers + review notes
4. `Repster/PrivacyInfo.xcprivacy` — the privacy manifest

The same applies to HealthKit, with one extra file. **If a read path is ever added**
— bodyweight from Health being the obvious candidate — all of these change together,
and `Health & Fitness → Health` becomes a required App Privacy declaration:

1. `Repster/Repster.entitlements` — the entitlement
2. `Repster/Info.plist` — usage descriptions (`NSHealthShareUsageDescription` would
   become necessary; today its absence is what proves write-only)
3. `marketing/website/privacy.html` — the Apple Health section from 1.6
4. `marketing/app-store/privacy-review-checklist.md` — ASC answers + review notes
5. `HEALTHKIT_INTEGRATION_EXPLORATION.md` — the design record, which currently
   documents the read path as explicitly out of scope

---

## 6. Optional, not blocking

- [ ] Consider a `contact@repster.site` alias forwarding to `repsterworkout@gmail.com`, so the address on the public policy page stays disposable if it gets scraped
- [ ] Write the first PostHog survey — one multiple-choice question, targeted at users who completed one workout and haven't returned in 5 days
- [ ] Line up 5 user interviews (r/fitness, r/weightroom, r/gainit, lifting Discords). At this stage these will teach you more than the dashboard will
- [ ] Screen views for the exercise list and templates screens are deliberately left untracked — revisit if the funnel points at browsing as the drop-off
