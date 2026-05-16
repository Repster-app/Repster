# App Privacy and Review Checklist

Last checked: May 15, 2026

## App Store Connect Privacy Answers

In App Store Connect, go to `App Privacy` and answer that Repster collects data.

Data types to select:

- `Purchases` -> `Purchase History`
- `Health & Fitness` -> `Fitness`
- `Usage Data` -> `Product Interaction`
- `Identifiers` -> `Device ID`

Do not select `Usage Data` -> `Other Usage Data` for the current simplified analytics setup.

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
- Reason: screen views, app/session lifecycle, paywall actions, import completed, and backup exported.

`Device ID`

- Purpose: `Analytics`
- Linked to user: `No`
- Used for tracking: `No`
- Reason: PostHog uses an anonymous install/distinct identifier for product analytics.

## Tracking / ATT

Answer that data is not used for tracking.

This setup should not require App Tracking Transparency because Repster does not use IDFA, targeted ads, data brokers, or combine app data with third-party data for advertising or ad measurement.

## Privacy Policy Copy To Include

Add a section like this to the live privacy policy:

> Repster uses PostHog EU cloud for anonymous product analytics. We collect coarse usage events such as app screens viewed, workout started/completed/discarded, whether a workout lasted under 30 minutes or 30 minutes or more, paywall actions, import completion, and backup export. Analytics are enabled by default and can be turned off in Settings -> Data & Backups -> Share Anonymous Analytics.
>
> Repster does not send exercise names, set weights, reps, notes, CSV contents, bodyweight values, or raw workout logs to analytics.
>
> Repster uses RevenueCat to manage App Store purchases and entitlements. RevenueCat may process purchase history and anonymous app user identifiers to validate purchases, unlock paid features, and provide purchase analytics.
>
> Repster does not use analytics for advertising, does not sell data, does not use IDFA, and does not enable PostHog session replay, autocapture, heatmaps, surveys, or person profiles.

## App Review Notes

Use this in the App Review Notes field:

> Repster is a workout logging app and does not require account creation. Workout history, exercises, templates, bodyweight entries, and settings are stored locally on device unless the user exports or shares them.
>
> The app uses anonymous PostHog EU product analytics for aggregate usage statistics only. The analytics setup does not use IDFA, ads, tracking, session replay, autocapture, heatmaps, surveys, or person profiles. Users can turn analytics off in Settings -> Data & Backups -> Share Anonymous Analytics. Analytics do not include exercise names, weights, reps, notes, CSV contents, bodyweight values, or raw workout logs.
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
