# Stuff To Do Before App Store

- [x] `repsterworkout@gmail.com` confirmed as the final `Repster` support email (2026-08-18). It is what the app uses, what all three site pages show, and what App Store Connect should list.
- [x] `docs/privacy.html` is live at `https://repster-app.github.io/Repster/privacy.html` (2026-08-18, Pages serves NewMain /docs).
- Add a visible `Terms of Use` link around the membership/paywall flow and make sure purchase, restore, and manage-subscription paths are all review-ready.
- Replace the RevenueCat test API key with the live production key and verify the real offering / entitlement setup before submission.
- Do a last pass on App Store-facing copy, screenshots, and icon branding.
- Replace the draft `marketing/generated/app-store/06-import-history-and-keep-control.png` source with a final import, export, or backup settings screenshot.
- Record and export the 20-30 second App Store preview from the storyboard in `marketing/app-store/product-page.md`.
- Finish App Store Connect metadata: subtitle, description, keywords, support URL, age rating, privacy answers, screenshots, and review notes.
- Fill out App Store Connect privacy answers from `marketing/app-store/privacy-review-checklist.md`: Purchase History, Fitness, Product Interaction, and Device ID; no tracking.
- Add App Review notes explaining the free-workout limit, what the paywall unlocks, and where restore/manage purchase actions live.
- Move notification permission out of app launch and only request it when rest-timer alerts are actually needed.
- Run the full automated test suite and fix any remaining failures before submitting.
- Smoke-test onboarding, paywall, export/import, and backup restore on a clean install.
- Do a real-device QA pass for purchases, restore purchases, local notifications, and Live Activity behavior.
- Verify clean-install behavior and upgrade expectations for older internal `Repster` builds before submitting.
