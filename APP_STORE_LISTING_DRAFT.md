# Repster App Store Listing Draft

Prepared from the current app code, public Repster pages, and App Store Connect requirements checked on May 9, 2026.

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

Screenshots are in progress. Recommended order:

1. Active workout logging: set table, previous performance, rest timer.
2. Home: recent PRs, recent workouts, quick start.
3. Templates: saved routines and fast start.
4. Charts: progress and training distribution.
5. Exercise detail/history: PRs, history, trends.
6. Data/import or backups if you want to show migration from another tracker.

Apple currently allows 1 to 10 screenshots per localization and accepts `.jpeg`, `.jpg`, and `.png`.

## App Privacy Questionnaire

Recommended answers based on the current app:

Does the app collect data?
Yes.

Data type:
Purchases -> Purchase History

Purposes:
- App Functionality
- Analytics

Linked to user:
No, if RevenueCat stays configured with anonymous app user IDs and Repster does not add accounts, email login, or custom RevenueCat user IDs tied to contact information.

Used for tracking:
No.

Do not declare these as collected by Repster if current behavior stays the same:
- Health & Fitness: workout/bodyweight data is stored locally and is not transmitted to Repster servers.
- Contact Info: feedback/support email is optional and user-initiated.
- Identifiers: no IDFA and no custom account/user ID in the current app.
- Usage Data/Diagnostics: no analytics or crash SDK was found beyond RevenueCat purchase handling and Apple-controlled diagnostics.
- Location, Contacts, Photos, Audio, Browsing/Search History, Sensitive Info: no.

Important RevenueCat note:
RevenueCat says apps using RevenueCat must disclose Purchase History. RevenueCat also says Purchase History should include both App Functionality and Analytics. If you later identify users with a custom app user ID tied to email or another identity, revisit `Linked to user` and possibly add `Identifiers -> User ID`.

Local manifest follow-up:
`Repster/PrivacyInfo.xcprivacy` currently declares Purchase History as linked to the user and only lists App Functionality. That does not match the recommendation above. Before submission, align the manifest and App Store questionnaire after confirming the final RevenueCat identity setup.

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

Local notifications are used for rest timer alerts. Live Activities are used to show the active workout/rest timer state while a workout is in progress.

## Pre-Submission Blockers To Clear

- Replace the in-app placeholder support email `feedback@repster.app` with the final address. The public support/privacy/terms pages currently use `support@reppo.app`.
- Align `Repster/PrivacyInfo.xcprivacy` with the final App Store privacy answers.
- Confirm the RevenueCat production public SDK key, offering, entitlement, subscription, and lifetime package setup.
- Make Terms of Use visible around the purchase/paywall flow, not only in Settings.
- Move notification permission so it is requested when rest timer alerts are needed, not at app launch.
- Run a clean-install QA pass for onboarding, purchase, restore, manage subscription, backup export/restore, CSV import, local notifications, and Live Activities.

## References

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Apple Platform Version Information: https://developer.apple.com/help/app-store-connect/reference/platform-version-information
- Apple Screenshot Specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- Apple Age Rating Values: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- RevenueCat Apple App Privacy: https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy
