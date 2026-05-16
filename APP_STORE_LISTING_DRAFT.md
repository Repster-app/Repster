# Repster App Store Listing Draft

Prepared from the current app code, public Repster pages, and App Store Connect requirements checked on May 15, 2026.

## Core Metadata

App name:
Repster

Subtitle, 28 characters:
Workout Tracking for Lifters

Promotional text, 137 characters:
Fast lifting logs, templates, PRs, charts, rest timers, Live Activities, CSV import, and Smart Suggestions for focused strength training.

Primary category:
Health & Fitness

Marketing URL:
https://repster-app.github.io/Repster/

Support URL:
https://repster-app.github.io/Repster/support.html

Privacy Policy URL:
https://repster-app.github.io/Repster/privacy.html

Terms of Use URL:
https://repster-app.github.io/Repster/terms.html

## Description

Repster is a fast workout tracker for lifters who want their training history to stay useful during and after the session.

Log sets quickly, start workouts from saved templates, review previous performance while you train, and keep your records, charts, and bodyweight context in one focused app.

Built for strength training:

- Log weight, reps, RIR, duration, distance, rest time, and unilateral work
- Use templates to start recurring sessions quickly
- See previous sets and exercise context without leaving the workout
- Track PRs, weekly activity, workout history, and progress charts
- Use Smart Suggestions to estimate useful next-set weights from your history, targets, and fatigue
- Import compatible CSV history from FitNotes or Strong
- Export backups and templates when you want to move or preserve your data
- Use rest timers and Live Activities to stay oriented between sets

Repster keeps your workout data on your device unless you choose to export or share it. The free tier includes 5 logged workouts. Full access unlocks unlimited logging through App Store purchases.

Repster is not medical advice. Train within your ability and consult a qualified professional before changing your training if you have injuries, medical conditions, or concerns.

## Keywords

97 bytes:

workout,logger,strength,lifting,gym,weightlifting,sets,reps,tracker,training,fitness,bodybuilding

Notes:
- Do not include `Repster`; Apple already searches by app name.
- Do not include other app or company names in the keyword field.
- Keep this under Apple's 100-byte limit.

## Screenshots

Launch screenshot frames are now generated in `marketing/generated/app-store/` at `1320 x 2868` PNG.

Recommended order:

1. Active workout logging: set table, previous performance, rest timer.
2. Home: recent PRs, recent workouts, quick start.
3. Templates: saved routines and fast start.
4. Charts: progress and training distribution.
5. Exercise detail/history: PRs, history, trends.
6. Data/import or backups if you want to show migration from another tracker.

Apple currently allows 1 to 10 screenshots per localization and accepts `.jpeg`, `.jpg`, and `.png`.

Current launch frame copy:

- Log sets without slowing down
- Start from your saved routines
- Know what you did last time
- Track PRs automatically
- See progress beyond one workout
- Import history and keep control

Frame 6 is a draft frame until a final import, export, or backup settings capture is available. The complete App Store product page brief and 20-30 second app preview storyboard live in `marketing/app-store/product-page.md`.

## Launch Marketing Kit

Implemented local marketing materials:

- App Store screenshot frames: `marketing/generated/app-store/`
- Social static posts: `marketing/generated/social/static/`
- Short-form video cover frames and scripts: `marketing/generated/social/video-covers/` and `marketing/social/social-launch-kit.md`
- Creator and press pitch: `marketing/press/creator-press-kit.md`
- Website refresh draft: `marketing/website/index.html`
- Measurement plan: `marketing/metrics/launch-measurement.md`

## App Privacy Questionnaire

Recommended answers based on the current app with simplified anonymous PostHog EU product analytics enabled:

Does the app collect data?
Yes.

Data types:
- Purchases -> Purchase History
- Health & Fitness -> Fitness
- Usage Data -> Product Interaction
- Identifiers -> Device ID

Purposes:
- Purchase History: App Functionality and Analytics
- Fitness: Analytics
- Product Interaction: Analytics
- Device ID: Analytics

Linked to user:
- Fitness: No
- Product Interaction: No
- Device ID: No
- Purchase History: Use RevenueCat's anonymous-ID guidance. If Repster still has no accounts, emails, or custom user IDs tied to a real identity, answer No. If you later connect RevenueCat IDs to an email/account/support identity, revisit this.

Used for tracking:
No.

Analytics implementation notes:
- PostHog host is EU cloud: `https://eu.i.posthog.com`.
- PostHog is configured with no `identify`, no person profiles, no session replay, no autocapture, no element interactions, no surveys, no rage click capture, and no IDFA/ads/tracking.
- Custom analytics is limited to main screen views, workout started/completed/discarded, paywall/purchase/restore, import completed, and backup exported.
- Workout duration is sent only as `under_30m` or `30m_or_more`.
- Import size/workout counts use coarse buckets only.
- Do not send exercise names, set weights, reps, notes, CSV contents, bodyweight values, individual workout logs, or exercise-level detail.
- `Identifiers -> Device ID` is included because PostHog uses an anonymous distinct/install identifier. Confirm the final App Store Connect wording during legal/privacy review.

Do not declare these as collected by Repster if current behavior stays the same:
- Health & Fitness -> Body Measurements: bodyweight data is stored locally and is not transmitted to Repster servers.
- Usage Data -> Other Usage Data: not needed for the current simplified analytics plan; use Product Interaction for app launches, screen views, sessions, paywall actions, import/export actions, and similar app behavior.
- Contact Info: feedback/support email is optional and user-initiated.
- User ID: no account/user ID in the current app.
- Diagnostics: no crash SDK was added beyond Apple-controlled diagnostics.
- Location, Contacts, Photos, Audio, Browsing/Search History, Sensitive Info: no.

Important RevenueCat note:
RevenueCat says apps using RevenueCat must disclose Purchase History. RevenueCat also says Purchase History should include both App Functionality and Analytics. If you later identify users with a custom app user ID tied to email or another identity, revisit `Linked to user` and possibly add `Identifiers -> User ID`.

Local manifest follow-up:
`Repster/PrivacyInfo.xcprivacy` now declares Purchase History, Fitness, Product Interaction, and Device ID with tracking disabled. Recheck Purchase History linkage after confirming the final RevenueCat identity setup.

## Age Rating

Recommended questionnaire posture:

- Made for Kids: No.
- Health or wellness topics: Yes / Frequent, because the app is a workout tracker with training recommendations and fitness progress views.
- Medical or treatment information: None. Repster should be positioned as workout tracking and training information, not medical advice, diagnosis, treatment, or physical therapy.
- Unrestricted web access: No.
- User-generated content: No.
- Messaging/chat: No.
- Advertising: No.
- Gambling, simulated gambling, loot boxes, contests: No.
- Violence, weapons, sexual content, nudity, profanity, horror, alcohol/tobacco/drug references: No.

Expected result:
Apple generates the final rating from the questionnaire. With Apple's current age-rating categories, health/wellness topics may produce a 9+ style rating on iOS 26-era displays. Avoid overriding upward unless your legal/EULA age requirement requires it.

## App Review Notes

Suggested note:

Repster is a workout logging app and does not require account creation. Workout history, exercises, templates, bodyweight entries, and settings are stored locally on device unless the user exports or shares them.

The free tier allows up to 5 completed workouts. After that limit, the app presents the RevenueCat/App Store paywall to unlock unlimited workout logging. Restore Purchases and Manage Subscription are available in Settings -> Membership. Privacy Policy and Terms of Use are available in Settings -> About.

Repster uses anonymous PostHog EU product analytics for aggregate usage statistics only. The analytics setup does not use IDFA, ads, tracking, session replay, autocapture, heatmaps, surveys, or person profiles. Users can turn analytics off in Settings -> Data & Backups -> Share Anonymous Analytics. Analytics do not include exercise names, weights, reps, notes, CSV contents, bodyweight values, or raw workout logs.

Local notifications are used for rest timer alerts. Live Activities are used to show the active workout/rest timer state while a workout is in progress.

## Pre-Submission Blockers To Clear

- Confirm `contact@repster.site` is the final in-app and public support/privacy/terms contact email.
- Align `Repster/PrivacyInfo.xcprivacy` with the final App Store privacy answers.
- Confirm the RevenueCat production public SDK key, offering, entitlement, subscription, and lifetime package setup.
- Make Terms of Use visible around the purchase/paywall flow, not only in Settings.
- Move notification permission so it is requested when rest timer alerts are needed, not at app launch.
- Run a clean-install QA pass for onboarding, purchase, restore, manage subscription, backup export/restore, CSV import, local notifications, and Live Activities.

## References

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Apple Manage App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Apple Privacy Manifest Files: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- Apple Platform Version Information: https://developer.apple.com/help/app-store-connect/reference/platform-version-information
- Apple Screenshot Specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- Apple Age Rating Values: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- RevenueCat Apple App Privacy: https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy
