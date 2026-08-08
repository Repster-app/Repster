# Pre-1.4 Launch Checklist

Current shipped version: **1.3 (build 3)**. This release adds expanded analytics,
masked session replay, in-app surveys, and an App Store rating prompt.

The analytics work is done and tested in the repo. Everything below is work that
happens **outside** Xcode — in App Store Connect, GitHub Pages, and PostHog — plus
one verification step that must not be skipped.

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

---

## 3. Release mechanics

- [ ] Bump `MARKETING_VERSION` to `1.4` and `CURRENT_PROJECT_VERSION` to `4`
- [ ] Commit the analytics work (currently uncommitted on `NewMain`)
- [ ] Archive and upload
- [ ] Write release notes — the rating prompt and analytics don't need mentioning, but any user-facing changes shipping alongside do

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

## 5. Keep in sync if analytics settings ever change

These four files describe the same privacy posture. Changing one without the
others makes the published policy wrong:

1. `Repster/Core/Services/AnalyticsService.swift` — the SDK config
2. `marketing/website/privacy.html` — the live policy
3. `marketing/app-store/privacy-review-checklist.md` — ASC answers + review notes
4. `Repster/PrivacyInfo.xcprivacy` — the privacy manifest

---

## 6. Optional, not blocking

- [ ] Consider a `contact@repster.site` alias forwarding to `repsterworkout@gmail.com`, so the address on the public policy page stays disposable if it gets scraped
- [ ] Write the first PostHog survey — one multiple-choice question, targeted at users who completed one workout and haven't returned in 5 days
- [ ] Line up 5 user interviews (r/fitness, r/weightroom, r/gainit, lifting Discords). At this stage these will teach you more than the dashboard will
- [ ] Screen views for the exercise list and templates screens are deliberately left untracked — revisit if the funnel points at browsing as the drop-off
