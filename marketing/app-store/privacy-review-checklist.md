# App Privacy and Review Checklist

Last checked: August 14, 2026

> **Changed in the analytics expansion (August 2026):** PostHog person profiles,
> application lifecycle events, masked session replay, and multiple-choice surveys
> are now enabled. Previous versions of this document and the privacy policy stated
> that replay, surveys, and person profiles were disabled — that is no longer true,
> and both the live policy and the App Review notes below were updated together.
> If any of these are turned back off, update all three in the same change.
>
> **Changed again on August 14, 2026:** crash and error capture is now enabled
> (`errorTrackingConfig.autoCapture`), adding two `Diagnostics` data types, and
> Apple Search Ads attribution was added, adding `Identifiers -> Advertising Data`.
> Both now have policy copy in `docs/privacy.html` and paragraphs in
> the App Review Notes below. **Neither is live yet** — the deployed page is still
> the May 16, 2026 one. See `PRE_1.4_CHECKLIST.md` §1.1.

## App Store Connect Privacy Answers

In App Store Connect, go to `App Privacy` and answer that Repster collects data.

Data types to select:

- `Purchases` -> `Purchase History`
- `Health & Fitness` -> `Fitness`
- `Usage Data` -> `Product Interaction`
- `Identifiers` -> `Device ID`

Also select:

- `Usage Data` -> `Other Usage Data`
- `Diagnostics` -> `Crash Data`
- `Diagnostics` -> `Other Diagnostic Data`

`Other Usage Data` is now required because session replay captures screen imagery
(masked) and surveys capture multiple-choice answers, neither of which is cleanly
covered by `Product Interaction`.

The two `Diagnostics` types are required as of 1.4, which enables PostHog's crash
and exception capture (`errorTrackingConfig.autoCapture`). They were already
appearing in the aggregate privacy report via PostHog's embedded
`PHPLCrashReporter.bundle` while the app declared neither.

Also select, as of 1.4:

- `Identifiers` -> `Advertising Data`

This covers the Apple Search Ads campaign, ad group and keyword identifiers
returned by `AAAttribution`. Note RevenueCat will not declare this for you — its
bundled manifest is static and only declares `Purchase History`, so the
declaration has to come from `Repster/PrivacyInfo.xcprivacy` (already done).

## Per-Data-Type Answers

`Purchase History`

- Purpose: `App Functionality`, `Analytics`
- Linked to user: `No` if RevenueCat remains anonymous and Repster has no accounts/email-linked user IDs. Revisit this if support, accounts, or custom RevenueCat app user IDs become identity-linked.
- Used for tracking: `No`

`Fitness`

- Purpose: `Analytics`
- Linked to user: `No`
- Used for tracking: `No`
- Reason: workout started/completed/discarded and workout duration bucket are exercise-related, even though they are coarse.

`Product Interaction`

- Purpose: `Analytics`
- Linked to user: `No`
- Used for tracking: `No`
- Reason: screen views, app/session lifecycle, onboarding step progression, exercise and template creation, empty-state impressions, paywall actions, import completed, and backup exported.

`Other Usage Data`

- Purpose: `Analytics`
- Linked to user: `No`
- Used for tracking: `No`
- Reason: masked session recordings (screen imagery with all text and images obscured on device before upload) and multiple-choice in-app survey responses.

`Crash Data`

- Purpose: `App Functionality`
- Linked to user: `No`
- Used for tracking: `No`
- Reason: crash reports (exception type, message, and stack trace) captured on device and uploaded on the next launch, used to find and fix crashes.

`Other Diagnostic Data`

- Purpose: `App Functionality`
- Linked to user: `No`
- Used for tracking: `No`
- Reason: handled errors the app recovers from silently — a failed Apple Health write, a failed subscription refresh, a failed backup export or restore. The error type and a fixed `error_context` label, never the data being operated on.

`Advertising Data`

- Purpose: `Analytics` — **not** `Third-Party Advertising`, and not `Developer's
  Advertising or Marketing`
- Linked to user: `No`
- Used for tracking: `No`
- Reason: Apple Search Ads campaign, ad group and keyword identifiers, plus country
  and conversion type, from Apple's first-party `AAAttribution`. No IDFA is read.
  The campaign attaches to PostHog's random per-install `distinct_id` and to an
  anonymous RevenueCat customer — nothing calls `Purchases.logIn`, and Repster has
  no accounts. **If a login is ever added, `Linked to user` becomes `Yes`.**

`Device ID`

- Purpose: `Analytics`
- Linked to user: `No`
- Used for tracking: `No`
- Reason: PostHog uses an anonymous install/distinct identifier for product analytics. Person profiles are now enabled and are keyed off this identifier, which is generated on device and never linked to an account, email, or name — Repster has no accounts.

## Tracking / ATT

Answer that data is not used for tracking.

This setup should not require App Tracking Transparency because Repster does not use IDFA, targeted ads, data brokers, or combine app data with third-party data for advertising or ad measurement.

## Privacy Policy Copy To Include

Add a section like this to the live privacy policy:

`docs/privacy.html` **is** the deployed page — as of 2026-08-17 there is only one
copy, and GitHub Pages serves this folder directly. As of August 17, 2026 it
covers, in addition to the original event list: onboarding progression, workout
abandonment, in-workout interaction counts, masked session recordings,
multiple-choice surveys, the anonymous per-install identifier behind person
profiles, Apple Health, crash and error diagnostics, and Apple Search Ads
attribution. Do not paraphrase it here — read the file.

⚠️ **Until the Pages source is switched, the file and the live page still differ.**
Pages must be repointed to branch `NewMain`, folder `/docs` (it currently serves
the root of `main`). Until that happens the live page is dated May 16, 2026 and
actively states that replay and surveys are disabled. See `PRE_1.4_CHECKLIST.md`
§1.1.

The three commitments that must stay literally true in the app:

1. All text and images are masked on device before a recording is uploaded
   (`maskAllTextInputs` / `maskAllImages` in `AnalyticsService.configureSessionReplay`).
2. The Share Anonymous Analytics toggle disables events, replay, surveys, and crash
   reports together (`optOut` is applied at SDK setup, not after it, and
   `AnalyticsService.captureError` checks `isCollectionEnabled`).
3. Error reports carry only the error type and a fixed `error_context` label from a
   closed enum — never the payload the failing operation was working on
   (`AnalyticsErrorContext` in `AnalyticsServiceProtocol.swift`).
4. With analytics off, no attribution request reaches Apple at all —
   `AttributionServiceFactory.makeService` returns `nil` on
   `analytics.isCollectionEnabled`, which also suppresses RevenueCat's collector
   (`AttributionService.swift`, `RepsterApp.swift`).
5. Apple Health is write-only: `requestAuthorization` is called with an empty read
   set (`HealthKitService.swift`). `NSHealthShareUsageDescription` is present only
   so a deleted Repster workout can be located and removed from Health — do **not**
   tell review the key is absent, it is not.

## App Review Notes

Use this in the App Review Notes field:

> Repster is a workout logging app and does not require account creation. Workout history, exercises, templates, bodyweight entries, and settings are stored locally on device unless the user exports or shares them.
>
> The app uses anonymous PostHog EU product analytics for aggregate usage statistics only. It does not use IDFA, advertising, tracking, autocapture, or heatmaps. Users can turn all analytics off in Settings -> Data & Backups -> Share Anonymous Analytics, which disables events, session recordings, surveys, crash and error diagnostics, and Apple Search Ads attribution together.
>
> The app captures masked session recordings to diagnose usability problems. All text and all images are masked on device before any recording is uploaded, so recordings show only layout, navigation, and tap locations. Analytics and recordings do not include exercise names, weights, reps, notes, CSV contents, bodyweight values, or raw workout logs.
>
> The app sends crash and error diagnostics (exception type, stack trace, device model, OS and app version) so crashes can be found and fixed. These contain no workout data and are covered by the same Share Anonymous Analytics toggle.
>
> The app shows occasional optional multiple-choice in-app surveys about the user's experience. No free-text survey responses are collected. Repster has no user accounts, so all analytics data is grouped under a random identifier generated on device at install time and is not linked to any real-world identity.
>
> APPLE HEALTH: Repster writes finished workouts to Apple Health. It requests write access only — `requestAuthorization` is called with an empty read set, so no read authorization for any health data type is ever requested. The permission prompt is never shown at launch or during onboarding: it appears only when the user turns on an explicit toggle at Settings -> Body -> Apple Health, so a reviewer must enable that toggle to see any Health behaviour at all. `NSHealthShareUsageDescription` is present in Info.plist for one reason only: when a user deletes a workout in Repster, the app looks up the matching workout it previously wrote so it can remove that entry from Health too. That lookup can only return samples Repster itself created. Active energy is a separate opt-in, off by default, and is a MET-based estimate calculated on device rather than a measurement.
>
> ATTRIBUTION: Repster uses Apple's own AdServices framework (`AAAttribution`) for first-party Apple Search Ads attribution only, once per install. No App Tracking Transparency prompt is shown because no IDFA is requested, no advertising profile is built, and no data is shared with third parties for tracking or ad targeting. The corresponding App Privacy answer is Identifiers -> Advertising Data, with purpose Analytics, not linked to the user, and not used for tracking. It is covered by the same Share Anonymous Analytics toggle: with analytics off, no request to Apple's attribution endpoint is made at all.
>
> The free tier allows up to 5 completed workouts. After that limit, the app presents the RevenueCat/App Store paywall to unlock unlimited workout logging. Restore Purchases and Manage Subscription are available in Settings -> Membership. Privacy Policy and Terms of Use are available in Settings -> About.
>
> Local notifications are used for rest timer alerts. Live Activities are used to show the active workout/rest timer state while a workout is in progress.

## Repo Files To Keep In Sync

- `Repster/PrivacyInfo.xcprivacy`
- `Repster/Core/Services/AnalyticsService.swift`
- `Repster/Core/Services/AttributionService.swift`
- `Repster/Core/Services/HealthKitService.swift` and `Repster/Info.plist`
- `docs/privacy.html` (repo source of truth)
- Live GitHub Pages privacy policy at `https://repster-app.github.io/Repster/privacy.html`
  — served from the **root of `main`**, not from the file above

## References

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Apple Manage App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Apple Privacy Manifest Files: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- RevenueCat Apple App Privacy: https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy
