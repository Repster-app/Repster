# Pre-1.6 Launch Checklist

**Currently live:** 1.5 (build 2). 1.5.1 was TestFlight only, up to build 8.
**This release:** **1.6 build 1**, set 2026-11-04 (§1.1). No 1.6 build has reached TestFlight yet.
**Branch:** `NewMain`, pushed on 2026-11-07 (`a468deb`) with the suggestion data added to
training data on 2026-11-06 and fixes for three known issues (§1.7).
**Last checked:** 2026-11-07, against the tree. PostHog last on 2026-11-06.

What 1.6 contains is [RELEASE_1_6_PLAN.md](RELEASE_1_6_PLAN.md). What it leaves out is
[RELEASE_1_6_CONSIDERATIONS.md](RELEASE_1_6_CONSIDERATIONS.md). Recurring setup that is already
done is in [PRE_1.4_CHECKLIST.md](PRE_1.4_CHECKLIST.md) and isn't repeated here.

---

## 0. Decide first

These change what gets built or tested, so they come before everything else.

- [x] **Left vs Right: ship today's version, or build the rethink first?** Built the rethink on
      2026-11-02 ([SIDES_RETHINK_SCOPING.md](SIDES_RETHINK_SCOPING.md)): tile, one list, line-chart
      exercise page, committed as `728a462`. 1,040 tests, 0 failures. The device pass in §9 of that
      doc is still to do
- [x] **Lock the scope.** Locked on 2026-11-07, after the suggestion data (2026-11-06) and three
      known-issue fixes. Nothing else goes in: Part 6 of the plan stays out, and new ideas go to
      the considerations list
- [x] **Tell upgraders that Share Training Data is on?** Decided 2026-11-04: yes, through What's
      New, and default-on stays. It's the third tile in §5.1, now in the app. Apple's 5.1.1(ii)
      asks for consent to collection "even if such data is considered to be anonymous", and
      default-on analytics has already passed review, so this was a judgement rather than a
      known rejection
- [ ] **Close the open training-data questions** from
      [TRAINING_DATA_SHARING_DESIGN.md](TRAINING_DATA_SHARING_DESIGN.md):
  - EU read on default-on: **option 1 chosen 2026-11-07.** Default-on stays, and the privacy
    policy gets what it was missing (§1.4). A lawyer's view on two questions stays optional: is
    set-level training data health data, and does default-on analytics need consent under the
    EU's device-storage rule
  - Deleting already-shared data: the 2026-11-07 policy draft promises it on request, found
    through the workouts someone describes
  - Custom exercise names and `Other User Content`: **no**, decided 2026-11-09. `Fitness` covers
    them, and `PrivacyInfo.xcprivacy` needs no change

---

## 1. Blocking — before submitting

### 1.1 Version

- [x] `MARKETING_VERSION` 1.5.1 → **1.6** on the app target and `WorkoutLiveActivity`, Debug and
      Release, four values, done by hand on 2026-11-04. `RepsterTests` stays at 1.0.
      `scripts/bump_release.sh` can't do it: it only accepts `0.x`
- [x] It has to stay exactly 1.6: `docs/privacy.html`, the support and terms pages and the review
      note all name 1.6

### 1.2 What's New

- [x] Added the `"1.6"` entry to `WhatsNewRelease.all` on 2026-11-04, with the three tiles in
      §5.1. The match is exact, so the version and this entry have to change together

### 1.3 MIT notice for the body artwork

- [x] No notice needed. On 2026-11-02 the artwork stopped compiling into the app: it sits behind
      `REPSTER_BODY_MAP`, which no build configuration defines, and a Release build confirms it
      isn't in the binary. The licence stays in `BodyMapPaths.swift` and `scripts/body-map/LICENSE`
      because the repo is public. If the map ever comes back, the notice comes back with it

### 1.4 Public pages that go false when 1.6 ships

The live privacy policy covers training data and the free month, but it's one edit behind the
repo: the 2026-11-06 sentence on suggestion data goes live with the next push (last item). The
support and terms pages were the two that had been missed:

- [x] [docs/support.html:85](docs/support.html:85) answered "Is my workout data stored in the
      cloud?" with "No". Since 2026-11-04 it says the full history isn't, that from 1.6 an
      anonymous copy of each finished workout is shared, and where to turn that off
- [x] [docs/terms.html:85](docs/terms.html:85) said workout data stays local unless exported or
      shared. Since 2026-11-04 it names the training data and says that copy is not a backup.
      Last updated November 4, 2026
- [x] Pushed `NewMain`, which is the deploy, on 2026-11-04. Both pages say "From Repster 1.6",
      so they're accurate before and after the release
- [x] Push `NewMain` again, for the sentence [docs/privacy.html](docs/privacy.html) gained on
      2026-11-06 about the Smart Suggestion data each ticked set carries. Pushed 2026-11-07
      (`468fb24..a468deb`), and the live policy showed it about 20 s later

- [ ] **Privacy policy draft, 2026-11-07, uncommitted.** [docs/privacy.html](docs/privacy.html) now
      names who runs Repster, states the legal basis, how long data is kept and people's rights,
      and calls the data pseudonymous rather than anonymous. Before it can go live:
  - ~~Fill in the name and country~~ Done 2026-11-09: "Magnus, an independent developer in Denmark"
  - PostHog: turn on Settings > Project > IP data capture > **Discard client IP data**; keep
    events at 2 years or less and recordings at 90 days or less (the free plan's 1 year and
    30 days already fit)
  - Accept PostHog's data processing agreement ([posthog.com/dpa](https://posthog.com/dpa)), and
    RevenueCat's if it isn't in place
  - Then commit and push `NewMain`, and set "Last updated" to the day it goes live

### 1.5 App Review note

In [privacy-review-checklist.md](marketing/app-store/privacy-review-checklist.md). It's a
statement to Apple, and four lines are out of date:

- [x] **PHOTOS:** "the card can still be shared through the standard share sheet" is false since
      `917b2d0`. Delete it, and say the card also opens from saved workouts
- [x] **Notifications:** "Local notifications are used for rest timer alerts" leaves out the one
      free-month notification. Add it. Guideline 4.5.4 limits promotional *push* notifications
      without opt-in; this one is local and uses the permission asked for rest alerts, so state
      it plainly rather than leaving a reviewer to find it
- [x] **Free tier:** "After that limit, the app presents the… paywall." The free-limit sheet and
      the free-month offer now come first. Say the reward is the same whatever the answers, and
      that it's redeemed through an Apple offer code
- [x] **Opening lines:** "stored locally on device unless the user exports or shares them" and
      "aggregate usage statistics only" both contradict the training-data paragraph further down
- [x] All four fixed on 2026-11-04. "Last checked" is November 4, 2026, with a "Changed for
      1.6" note at the top
- [ ] Paste the note into App Store Connect for 1.6

### 1.6 App Privacy

- [ ] Confirm the `Fitness` answer still reads right: same type and purpose (Analytics, not
      linked, not tracking), but no longer coarse. If PostHog adds a country or city to events
      from the IP address, `Coarse Location` (Analytics, not linked) may need declaring too. `PrivacyInfo.xcprivacy` needs no change unless
      `Other User Content` comes back yes (§0)

### 1.7 Commit and push

- [x] Commit the secondary-muscle rework as its own commit (`219b49b`), then Left vs Right
      (`728a462`) and these docs
- [x] Commit the 2026-11-06 suggestion-data work as its own commit: `60f9e5e`, 2026-11-07, and
      pushed the same day (§1.4)
- [x] Commit the three 2026-11-07 fixes, one commit each: muscle tags `1651d6f`, Suggestion
      feedback removed `052ab19`, lapsed subscribers' free-limit title `ec2f921`
- [ ] Add by path, never `git add -A`: `marketing/growth-workspace/` and the two
      `marketing/metrics/` business files must stay out, and pushing `NewMain` publishes

### 1.8 Archive

- [ ] `posthog-cli --host https://eu.posthog.com dsym upload` after archiving, and confirm one
      exception shows Swift function names

---

## 2. What changes for people on upgrade

- **Training data starts on the first launch of 1.6.** Only workouts after that moment go out.
  Workouts from before go only if someone switches the setting on by hand. Each ticked set also
  carries what Smart Suggestions expected for it, with no figures on exercises that add bodyweight
- **Admin Mode turns off once for everyone,** your own phone included. Support steps for the
  kill switch change to: Settings → About → hold Version → Turn On → Smart Suggestions →
  Capacity Guards off. It only holds while Admin Mode stays on
- **People already at the free limit** see the new sheet on their next start, and get the one
  notification 48 h later if they ever allowed rest alerts
- **The Share button disappears.** Nobody outside the team used it, so low risk
- **The data is safe to carry over.** No model, backup format or permission changed

---

## 3. Phone pass

No sign-off is recorded for any of this. TestFlight has reached two team iPhones on iOS 26.6, up
to 1.5.1 build 8 on 2026-11-04, so much of it has at least run on a real phone (the plan's last
column says what). Run the pass on the first 1.6 TestFlight build, because:

- **Four things have never fired on a real phone:** Export Workout, the free-limit sheet, the
  free month and the Share Training Data switch. Still true on 2026-11-06: none of their events
  exists in PostHog at all. Start there
- **Build 8 has the newest screens, but they've barely run.** It was used for about a minute:
  Left vs Right opened once, and no workout was started, so `e12b5a6`'s clock and rest bar (the
  most-used code in the app) still haven't run in a workout on a phone
- **The suggestion data isn't in any build yet**
- **About 3 in 10 public users are on iOS 27** (14 of 46 in the 14 days to 2026-11-04), and
  neither team phone is. There's no simulator for it here (Xcode 26.3), so one phone has to update

**Workout**

- [ ] Menus and rest bar: [WORKOUT_TICK_RERENDER_SCOPING.md §9](WORKOUT_TICK_RERENDER_SCOPING.md)
- [ ] Duplicate add: [DUPLICATE_EXERCISE_ADD_SCOPING.md §7](DUPLICATE_EXERCISE_ADD_SCOPING.md)
- [ ] Superset two exercises, then pick one of them as a third exercise's partner: all three stay
      together. Take the middle one out: the other two stay joined
- [ ] **End** and **+ Exercise** read right in a live workout and when editing a past one. Leave
      a workout running past an hour: the clock stays on one line
- [ ] Fresh install, first rest: the alarm prompt shows all its text and both buttons
- [ ] Finish a workout with nothing ticked: free workouts left doesn't drop
- [ ] Finish a workout and open Add details: notes, effort and Save as template, and no
      Suggestion feedback

**History and sharing**

- [ ] Set notes: [SET_NOTES_IN_HISTORY_SCOPING.md §7](SET_NOTES_IN_HISTORY_SCOPING.md). In Calendar,
      a noted row opens its note and the rest of the card still opens the exercise
- [ ] Share from saved workouts: [SHARE_FROM_HISTORY_SCOPING.md §7](SHARE_FROM_HISTORY_SCOPING.md).
      Skip step 8, which predates the Share button's removal. Save to Photos works; deny Photos
      and the alert points to Settings
- [ ] Export: [WORKOUT_EXPORT_SCOPING.md, Device pass](WORKOUT_EXPORT_SCOPING.md)

**Exercises**

- [ ] Primary Muscle menu shows colour dots. Secondary Muscles opens on a quick tap, shows the
      grouped list, and the row summarises the picks
- [ ] Exercise detail reads like "Back · Hamstrings · Glutes · Abs". After updating from 1.5,
      Hip Adductor Machine reads "Legs · Adductors" and Dead Hang "Back · Forearms · Shoulders"
- [ ] The increment picker offers 4 kg

**Insights**

- [ ] Install with no sets: Insights shows "What you'll see here"
- [ ] Left vs Right, on an exercise logged by side: the steps in
      [SIDES_RETHINK_SCOPING.md §9](SIDES_RETHINK_SCOPING.md)

**Onboarding**

- [ ] Tap steps in [ONBOARDING_POLISH_SCOPING.md](ONBOARDING_POLISH_SCOPING.md), and a fresh install
      goes straight to Home after Start training

**Money**

- [ ] Free-limit sheet: [PAYWALL_BRIDGE_SCOPING.md §7](PAYWALL_BRIDGE_SCOPING.md). With an
      expired sandbox subscription it says "Your subscription has ended" instead of "You've used
      your 10 free workouts" (in the simulator: `-RepsterFreeMonthCustomerType lapsed`)
- [ ] **Free month and subscriber card:** Levels 2 to 4 of
      [FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md §6](FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md).
      Decided 2026-10-26: these must pass before submitting

**Privacy and upgrade**

- [ ] Hold Version 2 s and confirm: Admin Mode switches both ways
- [ ] Share Training Data: turn it off, then on by hand. The toggle event arrives, and earlier
      workouts go up once, in chunks. Use a phone with a real history. This path has never run
- [ ] A finished workout's `training workouts shared` event carries no notes, title or bodyweight.
      Turn analytics off: Share Training Data goes off and disabled
- [ ] The same event says `schema_version` 2 and has `e1rm_formula`, and its ticked sets carry a
      `suggestion` with figures. A set on an exercise that adds bodyweight (Pull-up, Chin-up, Dip,
      Push-up, Inverted Row) carries no figures: only `status`, `model_epoch`, `captured_at` and
      sometimes `unavailable_reason`
- [ ] Watch one recording: an opened set note is masked
- [ ] Update from the live 1.5 build, not a clean install: history intact, no crash, What's New
      shows once and doesn't come back

---

## 4. App Store Connect

- [ ] App Review note (§1.5)
- [ ] "What's New" field (§5)
- [ ] **Screenshots.** The live set is from 1.3 and shows a templates screen the app no longer
      has. Carried from 1.5 on purpose, so decide again: re-capture or ship unchanged. Not a gate
- [ ] **Promotional text and keywords.** The repo copy still lacks `superset` and `program`
      ([product-page.md](marketing/app-store/product-page.md)). Check the live listing, not
      verified from here
- [ ] **Offer code:** leave the two duplicate offers alone. Deactivating is permanent, and only
      one of them holds `REPSTERMONTH`

---

## 5. What's New copy — draft

### 5.1 The in-app sheet

Three items at most, each something an upgrader can go and see in ten seconds, with no
before-and-after. **In the app since 2026-11-04** in `WhatsNewRelease.swift`; rewritten on 2026-11-09
(uncommitted) to the user's version below.

| # | Title | Body |
|---|---|---|
| 1 | **Various improvements** | Left vs Right on Insights shows if one side is stronger once you log exercises by side. Plus secondary muscles, visual updates and lots of smaller improvements. |
| 2 | **Your past workouts** | Save any workout as a card or a file, and open set notes in your history. |
| 3 | **Improving Smart Suggestions** | Workouts you finish, with what Smart Suggestions suggested, are now shared to help improve Repster and its suggestions, without notes or bodyweight and not linked to you. Turn it off in Settings → Data & Backups. |

Left vs Right leads the first card rather than getting its own: it stays hidden until both sides
have been logged, so the sentence says when it appears. The third card is still the only place an
upgrader learns that sharing is on, so it stays.

### 5.2 The App Store field

> **Your past workouts do more.** Save any workout as a card, export it as a file, and open set
> notes right in your history.
>
> **Left vs right.** Log an exercise by side and Insights shows whether one side is stronger.
>
> **Bigger supersets.** Groups can now grow past a pair.
>
> **Secondary muscles.** See what else each exercise works, and change it to suit how you train.
>
> Plus a 4 kg weight step, clearer workout buttons and a steadier workout screen.
>
> **Training data.** Workouts you finish are now shared anonymously to help improve Repster. Turn
> it off in Settings → Data & Backups.

---

## 6. Known issues 1.6 ships with

These are things known to be wrong or awkward in 1.6 that would ship as they are. None of them
blocks the release. Each one only becomes work if you decide to fix it first.

### 6.1 New in 1.6, or made worse by it

| What a user would notice | Who | Recommendation |
|---|---|---|
| **Saving a share card needs Photos access.** Someone who says no has no other way to get the card out, because 1.6 removed the Share button | People who decline Photos | Ship. Chosen on purpose in `917b2d0`, because nobody outside the team used Share |

### 6.2 Already in 1.5, not caused by 1.6

Listed so that shipping them again is a choice. No commit since 1.5 addresses them, and the
detail is in [RELEASE_1_6_CONSIDERATIONS.md §4](RELEASE_1_6_CONSIDERATIONS.md). Recommendation for
all of them: ship.

| What a user would notice | Where it's scoped |
|---|---|
| **Sets that were never ticked still count.** Rows filled in by Copy Previous show in history as logged, even if the exercise was never started | [UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md) |
| **A single rep target can stall.** With one target (8) instead of a range (8–12), the suggested weight can stop climbing | [PROGRESSION_LADDER_SCOPING.md](PROGRESSION_LADDER_SCOPING.md) |
| **The rest alarm is silent in any Focus mode.** Getting through needs an Apple entitlement the app doesn't have yet | [REST_TIMER_ALARM_SCOPING.md](REST_TIMER_ALARM_SCOPING.md) |
| **An imported exercise can sit beside the built-in one.** CSV import only matches exact names, so the imported history doesn't join the library exercise | — |
| **Rest is only measured when the timer runs out.** Start the next set early and suggestions assume full rest | — |
| **One user's templates showed every set piled on the first exercise** after the 1.5 templates update. Cause unknown; the evidence now suggests they were saved that way | [TEMPLATE_SET_COLLAPSE_HANDOVER.md](TEMPLATE_SET_COLLAPSE_HANDOVER.md) |
| **A rare crash at launch** when iOS starts the app in the background and the database can't open. One device on 1.4, nobody noticed | [1_5_DECISION_RECORD.md](1_5_DECISION_RECORD.md) |

---

## 7. Tidy-up — optional, not blocking

- `CHANGELOG.md` stopped at 0.1, and `scripts/bump_release.sh` still enforces `0.x`
- Five design docs still say "uncommitted" for work that's committed
- Two worktrees from March under `.claude/worktrees/` hold nothing that isn't in `NewMain`
- [docs/docs.html](docs/docs.html) doesn't describe anything from 1.5 or 1.6 yet (carried from
  PRE_1.5 §6.3): an omission, not a false claim

---

## 8. After release

- [ ] First `training workouts shared` events look right, and the HogQL in the design doc works
      on real data. Filter on `completed`
- [ ] Free-month events, redemptions in App Store Connect, and renewals a month later. Expect
      about 2 people a month, so read people, not rates
- [ ] No `$exception` frames arriving unsymbolicated
- [ ] Exclude TestFlight from every comparison: `coalesce(properties.$is_testflight, false) = false`
