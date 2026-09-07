# App Privacy and Review Checklist

Last checked: September 6, 2026

> **Changed for 1.5 (September 6, 2026):** two corrections to the App Review Notes
> below. The free-tier limit was stated as 5 completed workouts; the code has said
> **10** (`RevenueCatConfiguration.freeWorkoutLimit`), and so do the website and the
> support page — this note was the only thing saying 5. And 1.5 adds
> `NSPhotoLibraryAddUsageDescription` for Save to Photos on the workout share card,
> which needed its own paragraph so a reviewer meeting a new permission string has an
> explanation. Neither is an App Privacy change: add-only access to write an image the
> user asked to save collects nothing and sends nothing off device.
>
> **Also removed 2026-09-06:** every reference to the **AI template helper**. It was
> deleted from the app in the 1.5 templates rebuild (`3cf55ed`) and no paste box
> exists any more, so the privacy policy's "AI Template Feature" section, the terms'
> "AI Template Helper" section, the feature guide bullet and the support FAQ entry
> all described a feature that is gone. The replay masking list drops from four items
> to three for the same reason.

> **Changed in the analytics expansion (August 2026):** PostHog person profiles,
> application lifecycle events, session replay, and multiple-choice surveys
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
>
> **Changed again on August 29, 2026:** session replay masking was inverted. 1.4
> masked every screen and opted a handful back in, which left six sections and 41 of
> the app's 45 sheets rendered as solid black and made the recordings useless. From
> 1.5 the recording is legible and a named list of values is masked instead — see
> "The commitments that must stay literally true" below. The policy copy and the App
> Review note in this file were rewritten in the same change; `PrivacyInfo.xcprivacy`
> needed nothing, `Other Usage Data` already covers it.

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
and surveys capture multiple-choice answers, neither of which is cleanly covered by
`Product Interaction`.

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
- Reason: session recordings (screen imagery, with notes, bodyweight and import
  previews obscured on device before upload) and multiple-choice in-app survey
  responses.

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
abandonment, in-workout interaction counts, session recordings,
multiple-choice surveys, the anonymous per-install identifier behind person
profiles, Apple Health, crash and error diagnostics, and Apple Search Ads
attribution. Do not paraphrase it here — read the file.

✅ **Resolved 2026-08-18.** Pages now serves branch `NewMain`, folder `/docs`, so
this file *is* the live page once it is pushed. `main` is a stale rollback copy and
touching it deploys nothing.

⚠️ **As of 2026-09-06 the rewrite is committed and unpushed.** `NewMain` is 47
commits ahead of `origin/NewMain`, so the live page is still the pre-1.5 text saying
everything typed in your own words is masked. **Pushing `NewMain` is the deploy**,
and it has to happen before the 1.5 build reaches users. See
`PRE_1.5_CHECKLIST.md` §1.1.

The three commitments that must stay literally true in the app:

1. Notes (workout, set and template), bodyweight wherever it is shown, and the import
   preview of the user's own training file are hidden on device before a recording is
   uploaded. (**The AI template box was deleted in the 1.5 templates rebuild**,
   `3cf55ed`, so the fourth item on this list is gone — along with the AI sections of
   the privacy policy and terms, removed 2026-09-06.) As of 1.5 the recording is
   legible by default (`maskAllTextInputs = false` in
   `AnalyticsService.configureSessionReplay`) and those values are masked at the field
   via `replayMasked()`; the three text fields that live inside a `.alert` cannot be
   masked — `UIAlertController` builds them, not SwiftUI — so recording stops while the
   dialogue is open, via `replayPaused(while:)`. Both are in
   `Repster/Core/Extensions/ReplayPrivacy.swift`, and
   `RepsterTests/ReplayMaskCoverageTests.swift` fails the build if a new text field is
   added without a decision recorded against it.

   Note what this deliberately does **not** cover: exercise names, workout titles and
   template names appear in recordings, because they are the content of nearly every
   screen. Their entry fields are masked while being typed, but the saved name is
   visible afterwards. The privacy policy and the App Review note below both say so.
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
> The app captures anonymous session recordings to diagnose usability problems, and users can turn them off with everything else under Settings -> Data & Backups -> Share Anonymous Analytics. Recordings show the app's own interface text and the training content on screen — exercise names, workout and template names, and the sets, reps and weights of a workout — which is what makes them useful for finding where people get stuck. The app has no photo picker and no user-supplied imagery, so every image in a recording is one the app ships. Three things are masked on device before any recording is uploaded and are never received: workout, set and template notes; the user's bodyweight wherever it is displayed, including the bodyweight log; and the preview of a training file being imported. Text typed inside a pop-up dialogue cannot be masked that way, so recording stops entirely while such a dialogue is open. Recordings are not linked to any account, name or email address, because the app has no accounts. Analytics events themselves carry only bucketed counts and never exact figures, notes, CSV contents, bodyweight values, or raw workout logs.
>
> The app sends crash and error diagnostics (exception type, stack trace, device model, OS and app version) so crashes can be found and fixed. These contain no workout data and are covered by the same Share Anonymous Analytics toggle.
>
> The app shows occasional optional multiple-choice in-app surveys about the user's experience. No free-text survey responses are collected. Repster has no user accounts, so all analytics data is grouped under a random identifier generated on device at install time and is not linked to any real-world identity.
>
> APPLE HEALTH: Repster writes finished workouts to Apple Health. It requests write access only — `requestAuthorization` is called with an empty read set, so no read authorization for any health data type is ever requested. The iOS permission prompt is never shown at launch or during onboarding. Repster explains the integration in its own screen first and reaches HealthKit only if the user taps Connect there. That screen appears in two places: once, on returning to the home screen after the first completed workout, and any time the user opens Settings -> Body -> Apple Health. A reviewer who wants to see any Health behaviour should use the Settings toggle. `NSHealthShareUsageDescription` is present in Info.plist for one reason only: when a user deletes a workout in Repster, the app looks up the matching workout it previously wrote so it can remove that entry from Health too. That lookup can only return samples Repster itself created. Active energy is a separate opt-in, off by default, and is a MET-based estimate calculated on device rather than a measurement.
>
> ATTRIBUTION: Repster uses Apple's own AdServices framework (`AAAttribution`) for first-party Apple Search Ads attribution only, once per install. No App Tracking Transparency prompt is shown because no IDFA is requested, no advertising profile is built, and no data is shared with third parties for tracking or ad targeting. The corresponding App Privacy answer is Identifiers -> Advertising Data, with purpose Analytics, not linked to the user, and not used for tracking. It is covered by the same Share Anonymous Analytics toggle: with analytics off, no request to Apple's attribution endpoint is made at all.
>
> PHOTOS: After finishing a workout, the user can open a shareable summary card and tap Save to Photos. That is the only thing that writes to the photo library, and it writes only the card image the user just asked to save. Repster requests add-only access (`NSPhotoLibraryAddUsageDescription`); it never requests read access, has no photo picker, and never reads or imports the user's photos. If the user declines, the card can still be shared through the standard share sheet.
>
> The free tier allows up to 10 completed workouts. After that limit, the app presents the RevenueCat/App Store paywall to unlock unlimited workout logging. Restore Purchases and Manage Subscription are available in Settings -> Membership. Privacy Policy and Terms of Use are available in Settings -> About.
>
> Local notifications are used for rest timer alerts. Live Activities are used to show the active workout/rest timer state while a workout is in progress.

## Repo Files To Keep In Sync

- `Repster/PrivacyInfo.xcprivacy`
- `Repster/Core/Services/AnalyticsService.swift`
- `Repster/Core/Services/AttributionService.swift`
- `Repster/Core/Services/HealthKitService.swift` and `Repster/Info.plist`
- `docs/privacy.html` (repo source of truth)
- Live GitHub Pages privacy policy at `https://repster-app.github.io/Repster/privacy.html`
  — served from **`NewMain:/docs`** since 2026-08-18, so it *is* `docs/privacy.html`
  above, one push behind. `main` is a stale rollback copy; pushing it deploys nothing
- `Repster/Info.plist` — also carries `NSPhotoLibraryAddUsageDescription` as of 1.5

## References

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Apple Manage App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Apple Privacy Manifest Files: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- RevenueCat Apple App Privacy: https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy
