# App Privacy and Review Checklist

Last checked: August 8, 2026

> **Changed in the analytics expansion (August 2026):** PostHog person profiles,
> application lifecycle events, masked session replay, and multiple-choice surveys
> are now enabled. Previous versions of this document and the privacy policy stated
> that replay, surveys, and person profiles were disabled — that is no longer true,
> and both the live policy and the App Review notes below were updated together.
> If any of these are turned back off, update all three in the same change.

## App Store Connect Privacy Answers

In App Store Connect, go to `App Privacy` and answer that Repster collects data.

Data types to select:

- `Purchases` -> `Purchase History`
- `Health & Fitness` -> `Fitness`
- `Usage Data` -> `Product Interaction`
- `Identifiers` -> `Device ID`

Also select:

- `Usage Data` -> `Other Usage Data`

`Other Usage Data` is now required because session replay captures screen imagery
(masked) and surveys capture multiple-choice answers, neither of which is cleanly
covered by `Product Interaction`.

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

The live policy at `marketing/website/privacy.html` is the source of truth and was
rewritten on August 8, 2026. It now covers, in addition to the original event
list: onboarding progression, workout abandonment, masked session recordings,
multiple-choice surveys, and the anonymous per-install identifier behind person
profiles. Do not paraphrase it here — read the file.

The two commitments that must stay literally true in the app:

1. All text and images are masked on device before a recording is uploaded
   (`maskAllTextInputs` / `maskAllImages` in `AnalyticsService.configureSessionReplay`).
2. The Share Anonymous Analytics toggle disables events, replay, and surveys
   together (`optOut` is applied at SDK setup, not after it).

## App Review Notes

Use this in the App Review Notes field:

> Repster is a workout logging app and does not require account creation. Workout history, exercises, templates, bodyweight entries, and settings are stored locally on device unless the user exports or shares them.
>
> The app uses anonymous PostHog EU product analytics for aggregate usage statistics only. It does not use IDFA, advertising, tracking, autocapture, or heatmaps. Users can turn all analytics off in Settings -> Data & Backups -> Share Anonymous Analytics, which disables events, session recordings, and surveys together.
>
> The app captures masked session recordings to diagnose usability problems. All text and all images are masked on device before any recording is uploaded, so recordings show only layout, navigation, and tap locations. Analytics and recordings do not include exercise names, weights, reps, notes, CSV contents, bodyweight values, or raw workout logs.
>
> The app shows occasional optional multiple-choice in-app surveys about the user's experience. No free-text survey responses are collected. Repster has no user accounts, so all analytics data is grouped under a random identifier generated on device at install time and is not linked to any real-world identity.
>
> The free tier allows up to 5 completed workouts. After that limit, the app presents the RevenueCat/App Store paywall to unlock unlimited workout logging. Restore Purchases and Manage Subscription are available in Settings -> Membership. Privacy Policy and Terms of Use are available in Settings -> About.
>
> Local notifications are used for rest timer alerts. Live Activities are used to show the active workout/rest timer state while a workout is in progress.

## Repo Files To Keep In Sync

- `Repster/PrivacyInfo.xcprivacy`
- `APP_STORE_LISTING_DRAFT.md`
- `marketing/website/privacy.html`
- Live GitHub Pages privacy policy at `https://repster-app.github.io/Repster/privacy.html`

## References

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Apple Manage App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Apple Privacy Manifest Files: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- RevenueCat Apple App Privacy: https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy
