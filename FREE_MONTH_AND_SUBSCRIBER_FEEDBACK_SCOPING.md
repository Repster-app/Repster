# Free Month for Feedback + Subscriber Thanks — Scoping

**Date:** 2026-10-26
**Status:** Built 2026-10-29, uncommitted. The files are listed in §7, and how to test it is in §6. The offer
and the `REPSTERMONTH` code were created in App Store Connect on 2026-10-29 (§2.5).
**Target release:** 1.6, with Parts A and B together. Part A depends on the free-limit sheet (9cbf4d6), which is
also in 1.6.
**Feature area:** Monetization / feedback

The doc has two parts that share one new component, a short question flow:

- **Part A, free month for feedback:** people who have used their 10 free workouts, or whose subscription
  ended, get a single notification. They then answer 3 questions and receive a free month of the monthly
  subscription.
- **Part B, subscriber thanks:** paying users get a one-time thank-you on Home that asks whether they'd help
  shape Repster, through 3 questions or an email.

Part A is the user's main idea and can ship on its own. Part B can follow in the same or a later release.

## 1. Summary

**Scale is tiny, so this is about listening, not volume.** From
[business-model-review-2026-10-23.md](marketing/metrics/business-model-review-2026-10-23.md):

- From 24 Aug to 21 Oct, 4 people reached the free limit and 1 of them bought.
- About 6 subscribed people were active in the last 30 days.

Neither part will move a revenue number you can measure. What both parts produce is answers from the people
who know the app best. Judge them by what those answers say.

**Apple allows both parts.** Guideline 3.2.2(x), current text checked 2026-10-26, forbids *forcing* ratings,
reviews, downloads or "other store-related actions". It explicitly allows incentivising actions inside the app.
So answering in-app questions for a reward is fine. Two rules keep it that way:

- Never tie the reward, or the thank-you, to rating or reviewing the app.
- The free month must come from an Apple offer code, not from a grant in RevenueCat. Unlocking access outside
  Apple's purchase system reads close to 3.1.1 ("own mechanisms to unlock content").

**No free trial is involved.** No product has an introductory offer today (RevenueCat: monthly and annual both
have `trial_duration: null`), and this feature doesn't need one. An offer code only reaches the people you
give it to. A trial would change the paywall for every buyer. See §9 for when the trial question comes back.

## 2. Part A: free month for feedback

### 2.1 Flow

| Step | What the user sees | Code |
|---|---|---|
| Finishes workout 10 | Nothing new on screen. Back on Home, the monetization refresh finds them eligible and schedules a local notification for 48 h later | `ContentView.refreshMonetizationState` → `FreeMonthOfferService.refresh` |
| 48 h later, still locked | "Get a month of Repster free. You've used your 10 free workouts. Answer 3 quick questions and the next month is on us." | `UserNotificationFreeMonthScheduler` |
| Taps the notification | The app opens directly on the questions | `RestTimerAlarmCoordinator` `didReceive` → `NotificationOpenRouter` → `ContentView` |
| Or taps Start in the app | The free-limit sheet shows an offer card, with "Answer 3 questions" as the main button and "See plans" as a text button | `FreeLimitSheet.swift` (`offer`) |
| Answers 3 questions | One question per screen. A tap moves on, and Back is available | `FeedbackQuestionsView.swift` (shared with Part B) |
| Done | "Thanks. Your free month is ready", a **Claim free month** button, and "Then €X a month. Cancel anytime in your Apple ID settings." | `FeedbackFlowView.swift` |
| Taps Claim | The flow closes and Apple's redeem screen opens with the code filled in. The user confirms it there | `FreeMonthOfferService.redeemURL` (§2.5) |
| Comes back | Unlocked. The foreground refresh and the existing `customerInfoStream` observation pick up the new entitlement | No change |

### 2.2 Who gets it (eligibility)

All of these must hold. The rules should live in one pure `FreeMonthOfferPolicy` so the full matrix can be
unit-tested:

1. The subscription status is `.inactive`, **not** `.unknown`. An offline launch reports `.unknown`, and that
   must never produce an offer, because it could be shown to a subscriber.
2. No free workouts are left (`AccessSnapshot.requiresPaywall`).
3. **The user is new or lapsed** (decision 3). Both get the offer, but the app has to know which one it's
   dealing with, because the first question and the notification text differ. This needs one new field on
   `SubscriptionSnapshot`, set in `makeSnapshot`: `customerType` is `.lapsed` when the entitlement exists in
   `customerInfo.entitlements.all` but isn't active, and `.new` when it isn't there at all.
   **Correction found while building:** lapsed users are not always locked straight away. Subscribers don't
   use up free workouts, so someone who bought after 3 free workouts gets the other 7 back when the
   subscription ends. They see the offer once those run out, through rule 2, like anyone else.
4. They haven't already finished the questions. This is a Keychain flag next to the quota, so a reinstall
   doesn't offer it again. Apple also allows only one redemption per Apple ID.

After the questions are answered, the free-limit sheet swaps the offer card for a **Claim free month** link.
That covers people who answered but never confirmed in the App Store. It never asks the questions a second
time.

### 2.3 The questions

Multiple choice only. The privacy policy already promises "short multiple-choice surveys" with no free text
(`docs/privacy.html`, Surveys section).

| # | Question | Options |
|---|---|---|
| 1 | What stopped you from upgrading? | The price · Not sure it's worth it yet · I'd rather pay once · Something's missing · I didn't know I'd run out |
| 2 | What would you miss most? | Logging workouts · Charts and progress · Smart suggestions · Insights · Templates |
| 3 | Which plan would you pick? | Monthly (€X) · Yearly (€X) · Lifetime (€X) · None of these |

**Lapsed subscribers get a different Q1** (decided 2026-10-26). Q2 and Q3 stay the same:

| # | Question | Options |
|---|---|---|
| 1 | Why did you stop your subscription? | The price · I'm not training right now · Something's missing · I use another app now · I didn't mean to cancel |

It gets its own `question_id` (`why_cancelled`), so it never mixes with the new-customer Q1 in queries.

- **Q1 settles the trial question.** If "The price" wins, that's evidence for a trial. If it loses, a trial
  wouldn't fix the real problem.
- **Q3 covers plan mix**, lever 3 in the business review. The paywall pre-selects yearly, and 0 of 5 buyers
  have picked it.
- **Prices come from the RevenueCat offering's `localizedPriceString`, never literals.** Regional prices
  differ (BG pays €0.99 a month). The claim screen's "Then €X a month" line uses the same fetch.
- **Option order is fixed, not shuffled.** At this volume a shuffled order adds nothing.
- **Analytics turned off:** the user still gets the free month, and the answers are simply not sent. The
  reward is for answering, not for sharing data.

### 2.4 The notification

- **One notification, sent once.** This is not the reminder system that was rolled back on 2026-08-09. It
  fires 48 h after workout 10, which falls at roughly the same time of day the user trains.
- **Scheduled the first time the app sees someone eligible (§2.2) who hasn't been offered yet.** That moment
  comes in three ways:
  - A new user finishes workout 10.
  - On the first launch of the new build, someone is already at the limit. That catches people who reached
    it on 1.4 or 1.5 and still open the app occasionally.
  - The first refresh after a subscription ends (launch or return to the foreground) finds them locked.
    Lapsed users may never finish a "workout 10" again, so this is often the only moment they get one.

  As built, all three are one hook: `FreeMonthOfferService.refresh` runs on every monetization refresh, and
  the first one that finds the user eligible makes the decision. The decision is stored before the first
  `await`, so two refreshes landing together can't both schedule.
- **Copy depends on `customerType`:**
  - New: "Get a month of Repster free. You've used your 10 free workouts. Answer 3 quick questions and the
    next month is on us."
  - Lapsed: "Get a month of Repster free. Your subscription has ended. Answer 3 quick questions and the next
    month is on us."
- **Cancelled when** the user opens the offer from the sheet, finishes the questions, or becomes subscribed
  (through the `customerInfoStream`).
- **Permission:** Repster asks for notification permission in only one place, the rest-timer alarm prompt
  (`ActiveWorkoutViewModel.swift:1530`). The answer isn't recorded anywhere. v1 adds no new permission
  prompt. If permission is missing, nothing is scheduled and the sheet is the only way in. The scheduling
  event records the permission state (§4), which tells us how many people the notification can reach.
- **Tap routing:** `RestTimerAlarmCoordinator` owns the app's only `UNUserNotificationCenterDelegate`
  (installed at `RepsterApp.swift:74`). It has no `didReceive` handler today. Add one that ignores the rest
  alarm, as now, and forwards the free-month identifier to a small router that `ContentView` observes. Keep
  to its own comment's rule: the delegate makes the decision about the alarm, and passes everything else on.

### 2.5 The offer code and redeem link

Set up by the user in App Store Connect (I can't do it from here). It's two steps: first the offer, then the
code that redeems it. The path below follows Apple's help page as checked on 2026-10-29.

1. **The offer.** Apps → Repster → **Subscriptions** (sidebar) → Repster Full Access → Repster Monthly. In
   the **Subscription Prices** section, click **+** → **Create Offer Codes**.
   - Reference name: anything, for example "Free month for feedback".
   - Leave the box that stops auto-renewal **unticked**. The claim screen tells people it renews at the
     monthly price.
   - Eligibility: tick **New subscribers** and **Expired subscribers** (decision 3). One offer can have both.
   - All countries and regions → **Free** → **1 month** → Confirm. An offer can't be edited afterwards.
2. **The code.** On the same subscription, Subscription Prices → **View all Subscription Pricing** → **Offer
   Codes** in the menu bar → your offer → **Create Custom Codes**.
   - Code: exactly **`REPSTERMONTH`**, which is what the app sends.
   - Redemption limit: 100 is plenty.
   - Expiry: **No End Date**, because changing the code needs an app release.
   - It can take up to an hour before the code works.
3. The app's numeric **Apple ID** is `6766094305`, the same number as the App Store links in `docs/`.

Required role: Account Holder, Admin, App Manager or Marketing. Using a different code name means changing
`RevenueCatConfiguration.freeMonthOfferCode` to match.

**As created (2026-10-29, read back through RevenueCat):** there are two identical active offers on Monthly,
"Free month for feedback" and "Free monthfeedback". Both are free for 1 month, renew automatically, are open to
new and expired subscribers, and cover every territory. A custom code can only belong to one offer, so
`REPSTERMONTH` sits on one of them and the other is empty. The empty one does nothing. If it's ever tidied up,
deactivate only the offer **without** codes: deactivating can't be undone, and it kills every code on that offer.

The app opens `https://apps.apple.com/redeem?ctx=offercodes&id=6766094305&code=REPSTERMONTH`. Both values
are plain constants in `RevenueCatConfiguration` (`appStoreAppID`, `freeMonthOfferCode`). A custom code isn't a credential, so the xcconfig rule doesn't
apply. If it leaks, it only works for Apple IDs that have never subscribed, it hits the redemption cap, and it
renews at full price.

## 3. Part B: subscriber thanks and feedback

### 3.1 Flow

A single dismissible card on Home, shown once:

> **Thanks for supporting Repster**
> Subscribers shape what comes next. Would you help?
> [Answer 3 questions] [Email me] [×]

- **Who sees it:** anyone with full access (monthly, yearly or lifetime) who has finished a workout with at
  least one ticked set while subscribed. This covers new buyers and existing subscribers after updating.
- **When, as built:** from the next launch, or the next return from the background, after that workout. Not
  in the moment right after it, which the Apple Health offer and the rating prompt already compete for. A
  system sheet such as the Health permission prompt doesn't count as a return.
- **Where, as built:** below Start Workout, in the walkthrough banner's slot. The design canvas showed it
  above; the app's own rule is that Start Workout stays the loudest thing on Home.
- **Not during an offer-code free month.** Thanking someone "for supporting" before they've paid reads oddly.
  How RevenueCat reports an offer-code free period (`EntitlementInfo.periodType`) needs checking on a
  sandbox redemption before relying on it. If it can't be told apart, show the card anyway. It's harmless.
- **Never in the same session as the App Store review prompt** (`ContentView.requestReviewIfEarned`, :862).
  Both come after a finished workout, and two asks at once is one too many.
- **Gone for good** after any button, including ×. This is a UserDefaults flag, so a reinstall shows it
  again, which is fine.

### 3.2 The questions

| # | Question | Options |
|---|---|---|
| 1 | What made you upgrade? | I ran out of free workouts · Smart suggestions · Charts and progress · Insights · To support the app |
| 2 | What should Repster get better at next? | Suggestions · Charts and progress · Templates and programs · Logging speed · Something else |
| 3 | Would you tell me more by email? | Yes, open an email · Not now |

**Email me** and Q3's "Yes" both open a mail draft to the support address, built like the existing feedback
draft (`SupportEmailComposer.subscriberFeedbackURL()`, subject "Repster subscriber feedback"). You only get an address when the user sends the
email themselves, so nothing personal is collected in the app.

**The email is probably the more valuable half here.** With about 6 subscribers, one conversation tells you
more than 6 tapped answers.

### 3.3 Later, not in v1: messages without a release

PostHog surveys are already switched on in the SDK (`AnalyticsService.swift:111`, posthog-ios 3.71.4). With a
person property for subscription status, which isn't set today (`access_tier` exists on events only), future
thank-yous, announcements and question sets could be set up in PostHog and reach subscribers without an app
update. It's left out of v1 for two reasons:

- It hasn't been checked that the iOS SDK renders and targets surveys the way the dashboard claims.
- At this scale, a native card per release is enough.

## 4. Analytics

Names follow the lowercase-with-spaces style. `result` reuses the existing property key.

| Event | Properties | Fires |
|---|---|---|
| `free month notification scheduled` | `notification_permission`: `authorized` \| `denied` \| `not_determined`, `customer_type`: `new` \| `lapsed` | At one of the three moments in §2.4. Also fires when permission is missing and nothing is scheduled, so reach can be measured |
| `free month notification opened` | `customer_type` | The notification is tapped |
| `free month offer shown` | `entry_point`: `sheet` \| `notification`, `customer_type` | The offer card or the questions are shown. Reuses the existing `entry_point` key instead of adding `entry` |
| `questions answered` | `question_set`: `free_month` \| `subscriber`, `question_id`, `answer` | Each answer |
| `questions completed` | `question_set` | The last answer is given |
| `questions closed` | `question_set`, `last_question_id` | The flow is left early |
| `free month claim tapped` | `customer_type` | Claim opens the redeem link |
| `subscriber card shown` / `subscriber card closed` | `result`: `questions` \| `email` \| `dismissed` | Once per presentation, with a one-shot guard as in `FreeLimitSheet` |

- **Redemptions can't be seen from the app.** The redemption happens in the App Store. Count them in App Store
  Connect (Offer Codes) and in RevenueCat. Watch renewals one month later.
- **Answer ids are stable snake_case** (`price`, `not_sure_worth_it`, …), never the display text, so copy
  can change without breaking queries.
- Update `POSTHOG_ANALYTICS_GUIDE.md` with the new events.

## 5. Privacy

- **The current policy already covers this:** optional, multiple-choice surveys under the anonymous device ID.
  Nothing new is collected.
- **Add one sentence** (decision 7) to the Surveys paragraph of `docs/privacy.html`: "Some surveys offer a
  free month of Repster for answering. The reward is the same whatever you answer, is redeemed through the
  App Store, and is still given if Share Anonymous Analytics is off, in which case your answers are not sent."
  It ships in the 1.6 policy push. NewMain serves Pages, so pushing NewMain is what publishes it.
- **No email address or free text** is ever stored by the app.

## 6. How to test

Four levels, from cheapest to most real. Levels 1 and 2 need no purchase and no offer code.

**One thing shapes the whole plan:** the Claim link always goes to the real App Store, which ignores sandbox
accounts. So the link can't be tested in sandbox, and the sandbox unlock can't be tested through the link.
Level 3 tests the unlock through Apple's sandbox route, and Level 4 tests the link against the real code.

### Level 1: automated tests

`RepsterTests/FreeMonthOfferTests.swift` covers who gets the offer, the one notification (scheduled once,
skipped without permission, cancelled on subscribing, opening or answering), the question sets and their
fixed ids, the price labels, the redeem link, the subscriber card's rules, the notification-tap hand-off and
the analytics events. Run them with ⌘U. They can't cover the screens themselves, a real notification,
Apple's redeem screen or RevenueCat. That's what the levels below are for.

### Level 2: simulator, or your phone from Xcode (no purchase needed)

Add these in Xcode under **Product → Scheme → Edit Scheme… → Run → Arguments → Arguments Passed On
Launch**, one per row. Untick a row to switch it off. They only work in builds run from Xcode; TestFlight and
App Store builds ignore them.

| Argument | What it does |
|---|---|
| `-RepsterFreeWorkoutsUsed 10` | Puts you at the free limit (it already existed). It stays in the Keychain after you untick it; `0` resets it. |
| `-RepsterFreeMonthReset YES` | Forgets the offer on every launch (notification decision, answers, claim) so you can run it again. |
| `-RepsterFreeMonthNotificationDelay 10` | The notification comes 10 seconds after the offer is first seen, instead of 48 hours. |
| `-RepsterFreeMonthCustomerType lapsed` | Treats you as someone whose subscription ended. |
| `-RepsterSubscriberThanksPreview YES` | Shows the subscriber thank-you card on Home on every launch. |

**A. The offer on the sheet.** Arguments: `FreeWorkoutsUsed 10`, `FreeMonthReset YES`.
1. Tap Start Workout, then any option. The free-limit sheet shows a "Get a month free" card, an **Answer 3
   questions** button, and "See plans" as a text link.
2. Tap Answer 3 questions. Check "Question 1 of 3", the progress bar and the five options. Tap one to move
   on, use Back (‹) to return, and × to close.
3. Open it again and answer all three. Question 3 shows prices when the store has loaded them.
4. The claim screen says "Thanks. Your free month is ready", with the renewal line and the monthly price.
5. Tap Claim free month. The flow closes and the redeem link opens. The simulator has no App Store, so
   expect nothing visible or Safari. On a phone the App Store opens, but won't know the code until it exists.
6. Tap Start again. The sheet now says "Your free month is ready" with a **Claim free month** button, and it
   never asks the questions again.

**B. The notification.** Notifications must be allowed for Repster on that device first, and Repster only
asks in one place: the rest-timer prompt. If you've never answered it there, run once with
`FreeWorkoutsUsed 0`, start a workout, tick a set so the rest timer starts, and allow alerts.
1. Arguments: `FreeWorkoutsUsed 10`, `FreeMonthReset YES`, `FreeMonthNotificationDelay 10`. Run, wait for
   Home, then go to the home screen (⌘⇧H in the simulator).
2. About 10 seconds later "Get a month of Repster free" arrives. Tap it: Repster opens on question 1.
3. **Closed app:** run again, and this time swipe Repster away in the app switcher before the 10 seconds
   are up. Tap the notification: Repster launches straight into the questions. (Launched from the
   notification, Xcode's arguments don't apply, but the free-workout count is already in the Keychain.)

**C. "Subscription ended" version.** Add `FreeMonthCustomerType lapsed` and repeat A or B. The notification
reads "Your subscription has ended…" and question 1 is "Why did you stop your subscription?".

**D. Notifications turned off.** In iOS Settings → Notifications → Repster, switch notifications off and repeat
B. Nothing arrives, but the offer is still on the sheet (A).

**E. The subscriber card.** Argument: `SubscriberThanksPreview YES`.
1. "Thanks for supporting Repster" is on Home, under Start Workout.
2. **Answer 3 questions** opens "Help shape Repster". On question 3, "Yes, open an email" opens a Mail draft
   on a phone (the simulator has no Mail), then the "Thanks. That really helps" screen.
3. **Email me** opens the same draft. × hides the card; in preview mode it comes back on the next launch.

**F. Large text (optional).** Settings → Accessibility → Display & Text Size → Larger Text, at the largest size.
The questions should scroll and the sheet should still fit.

### Level 3: real purchase states on your phone (sandbox)

This needs a sandbox Apple account (App Store Connect → Users and Access → Sandbox), signed in on the phone
under Settings → Developer → Sandbox Apple Account, and a build from Xcode or TestFlight. Sandbox purchases
cost nothing.

- **The subscriber card, for real.** Buy Monthly from the paywall (Settings → Unlock Repster) with the
  sandbox account. Finish a workout with at least one ticked set. It should not appear yet. Send Repster to
  the background, open it again, and the card should be on Home.
- **Subscription ended, for real.** Cancel the sandbox subscription (Settings → Developer → Sandbox Apple
  Account → Manage) and let it expire; sandbox months last minutes. In an Xcode build with
  `FreeWorkoutsUsed 10` and `FreeMonthNotificationDelay 10`, open Repster. The sheet should offer the free
  month with the "Why did you stop" question, and the notification should arrive 10 seconds later.
- **Redeeming.** Apple's sandbox route (iOS 16.3 or later) is Settings → Developer → Sandbox Apple Account →
  Initiate Transaction → Offer Codes, using a one-time sandbox code generated for this offer in App Store
  Connect. Developers report that custom codes can be refused there as "not valid", so use a one-time code.
  Then open Repster. It should be unlocked, the offer gone from the sheet, and any pending notification
  cancelled. Finish a workout and come back from the background: whether the thank-you card stays hidden
  during the free month shows how RevenueCat reports it (§3.1). If the card shows, that's the harmless case.

### Level 4: the real link, before release

Once `REPSTERMONTH` exists in App Store Connect, open
`https://apps.apple.com/redeem?ctx=offercodes&id=6766094305&code=REPSTERMONTH` on your iPhone (paste it into
Safari, or tap Claim in a TestFlight build). The App Store should show Repster Monthly with 1 month free.
That proves the code and the link match, and you can stop there. If you confirm with your own Apple ID, it's a
real subscription: it renews at your local price after the month unless you cancel, and cancelling straight
away keeps the free month.

### After release

Watch the events in §4 in PostHog, the offer's redemption count in App Store Connect, and renewals in
RevenueCat a month later. Expect about 2 people a month: read people, not rates.

## 7. What was built (2026-10-29, uncommitted)

| File | Change |
|---|---|
| `Core/Services/FreeMonthOfferService.swift` (new) | Who is eligible, Keychain state, the one notification, the redeem link, the DEBUG launch arguments |
| `Core/Services/NotificationOpenRouter.swift` (new) | Hands a notification tap to `ContentView` |
| `Core/Services/SubscriberThanks.swift` (new) | When the thank-you card shows, and what it remembers |
| `Features/Home/Views/FeedbackQuestionsView.swift` (new) | The three question sets and the question screen |
| `Features/Home/Views/FeedbackFlowView.swift` (new) | Questions, then the claim or thank-you screen |
| `Features/Home/Views/SubscriberThanksCard.swift` (new) | The card on Home |
| `RepsterTests/FreeMonthOfferTests.swift` (new) | 32 tests |
| `Core/Services/MonetizationService.swift` | `customerType`, `isInFreePeriod`, `planPrices()`, the code and Apple ID constants |
| `App/ContentView.swift` | The refresh hook, the sheet's new results, notification taps, both flows, the card |
| `Features/Home/Views/FreeLimitSheet.swift` | The offer card and the reordered buttons |
| `Features/Home/Views/HomeView.swift` | The card's slot |
| `Core/Services/RestTimerAlarmCoordinator.swift` | `didReceive` passes non-alarm taps on |
| `Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` | One call: a subscribed workout with a ticked set earns the card |
| `Core/Services/ServiceContainer.swift`, `App/RepsterApp.swift` | Wiring, and the DEBUG reset at launch |
| `Core/Services/Protocols/AnalyticsServiceProtocol.swift` | 9 events, 6 property keys, two new free-limit sheet results |
| `Features/Settings/ViewModels/SettingsViewModel.swift` | The subscriber feedback email |
| `docs/privacy.html` | The free-month sentence, and Last updated set to October 29, 2026 |
| `POSTHOG_ANALYTICS_GUIDE.md` | The new events |
| `Repster.xcodeproj/project.pbxproj` | The 7 new files registered (FMO001–FMO107) |

**Suite:** 1,014 executed, 14 skipped, 0 failures, on the iPhone 16 simulator. All 32 new tests pass. The first
run had one failure: `ReplayMaskCoverageTests` flags any `Text(...)` whose argument contains "note", and the
question screen drew `Text(footnote(index))`. That was renamed to `finePrint`. It's fixed app copy, not a user's
note, so masking it would have been wrong.

**Not done:** Levels 2 to 4 of §6 (nobody has looked at the screens on a device yet), and the offer code in
App Store Connect. No SwiftData model or migration changed.

## 8. Out of scope

- A free trial (introductory offer) on the paywall. Revisit after Q1 answers come in.
- Asking for notification permission anywhere new.
- More than one notification, or any repeat.
- Remote messages through PostHog surveys (§3.3).
- Asking subscribers for an App Store review. It's a valid ask, but it must stay separate from the thanks
  and can never be a reward.
- The free-limit sheet's title ("You've used your 10 free workouts") is also what lapsed subscribers see
  today, which is wrong for them. Fixing the title is a separate copy change. Only the offer card in this
  doc is written to fit both groups.

## 9. Decisions

All decided by the user on 2026-10-26.

1. **How many months: 1.** Ten workouts is about 3 weeks at 3 a week, so one more month is about 12 workouts.
   That's enough to come to rely on the charts, and it delays the first payment the least.
2. **Notification timing: 48 h** after the moment the user becomes eligible (§2.4). It lands at the same time
   of day they trained.
3. **Lapsed subscribers: included**, with their own Q1 ("Why did you stop your subscription?"). The code
   needs the "Expired subscribers" eligibility too (§2.5), and the app tells the two groups apart with
   `customerType` (§2.2).
4. **Code storage: a constant** in `RevenueCatConfiguration`. Changing or rotating the code needs a release,
   so give the custom code No End Date in App Store Connect (§2.5).
5. **Part B ships with Part A**, in the same release.
6. **Release: 1.6.** This was chosen over 1.7, knowing 1.6 already carries a lot of uncommitted work with
   device passes outstanding. Levels 2 to 4 in §6 have to pass before 1.6 is submitted.
7. **Privacy policy: add the sentence** in §5.
