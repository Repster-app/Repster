# Pre-1.6 Launch Checklist

**Currently live:** 1.5 (build 2). 1.5.1 was TestFlight only.
**This release:** **1.6 build 1**, set 2026-11-04 (§1.1).
**Branch:** `NewMain`, pushed to `origin` on 2026-11-04.

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
- [ ] **Lock the rest of the scope.** Recommendation: nothing else goes in. Part 6 of the plan
      stays out, and new ideas go to the considerations list
- [x] **Tell upgraders that Share Training Data is on?** Decided 2026-11-04: yes, through What's
      New, and default-on stays. It's the third tile in §5.1, now in the app. Apple's 5.1.1(ii)
      asks for consent to collection "even if such data is considered to be anonymous", and
      default-on analytics has already passed review, so this was a judgement rather than a
      known rejection
- [ ] **Close the open training-data questions** from
      [TRAINING_DATA_SHARING_DESIGN.md](TRAINING_DATA_SHARING_DESIGN.md): the EU read on
      default-on, whether to promise deleting already-shared data, and whether custom exercise
      names need `Other User Content` (leaning no)

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

The privacy policy is fine: the live page matches `docs/privacy.html` exactly and already covers
training data and the free month. These two were missed:

- [x] [docs/support.html:85](docs/support.html:85) answered "Is my workout data stored in the
      cloud?" with "No". Since 2026-11-04 it says the full history isn't, that from 1.6 an
      anonymous copy of each finished workout is shared, and where to turn that off
- [x] [docs/terms.html:85](docs/terms.html:85) said workout data stays local unless exported or
      shared. Since 2026-11-04 it names the training data and says that copy is not a backup.
      Last updated November 4, 2026
- [x] Pushed `NewMain`, which is the deploy, on 2026-11-04. Both pages say "From Repster 1.6",
      so they're accurate before and after the release

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
      linked, not tracking), but no longer coarse. `PrivacyInfo.xcprivacy` needs no change unless
      `Other User Content` comes back yes (§0)

### 1.7 Commit and push

- [x] Commit the secondary-muscle rework as its own commit (`219b49b`), then Left vs Right
      (`728a462`) and these docs
- [ ] Add by path, never `git add -A`: `marketing/growth-workspace/` and the two
      `marketing/metrics/` business files must stay out, and pushing `NewMain` publishes

### 1.8 Archive

- [ ] `posthog-cli --host https://eu.posthog.com dsym upload` after archiving, and confirm one
      exception shows Swift function names

---

## 2. What changes for people on upgrade

- **Training data starts on the first launch of 1.6.** Only workouts after that moment go out.
  Workouts from before go only if someone switches the setting on by hand
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
to build 7 on 2026-11-01, so much of it has at least run on a real phone (the plan's last column
says what). Run the pass on the first 1.6 TestFlight build, because:

- **Four things have never fired on a real phone:** Export Workout, the free-limit sheet, the
  free month and the Share Training Data switch. Still true on 2026-11-04: none of their events
  exists in PostHog at all. Start there
- **Three changes came after build 7:** `e12b5a6`, which moved the clock and rest bar (the
  most-used code in the app), the final secondary-muscle rework, and the Left vs Right rebuild
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
- [ ] Exercise detail reads like "Back · Hamstrings · Glutes · Abs"
- [ ] The increment picker offers 4 kg

**Insights**

- [ ] Install with no sets: Insights shows "What you'll see here"
- [ ] Left vs Right, on an exercise logged by side: the steps in
      [SIDES_RETHINK_SCOPING.md §9](SIDES_RETHINK_SCOPING.md)

**Onboarding**

- [ ] Tap steps in [ONBOARDING_POLISH_SCOPING.md](ONBOARDING_POLISH_SCOPING.md), and a fresh install
      goes straight to Home after Start training

**Money**

- [ ] Free-limit sheet: [PAYWALL_BRIDGE_SCOPING.md §7](PAYWALL_BRIDGE_SCOPING.md)
- [ ] **Free month and subscriber card:** Levels 2 to 4 of
      [FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md §6](FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md).
      Decided 2026-10-26: these must pass before submitting

**Privacy and upgrade**

- [ ] Hold Version 2 s and confirm: Admin Mode switches both ways
- [ ] Share Training Data: turn it off, then on by hand. The toggle event arrives, and earlier
      workouts go up once, in chunks. Use a phone with a real history. This path has never run
- [ ] A finished workout's `training workouts shared` event carries no notes, title or bodyweight.
      Turn analytics off: Share Training Data goes off and disabled
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
before-and-after. **In the app since 2026-11-04,** as drafted, in `WhatsNewRelease.swift`.

| # | Title | Body |
|---|---|---|
| 1 | **Your past workouts** | Save any workout as a card or export it as a file, and open set notes right in your history. |
| 2 | **Secondary muscles** | See what else each exercise works, and change it to suit how you train. |
| 3 | **Training data** | Workouts you finish are now shared anonymously to help improve Repster. Turn it off in Settings → Data & Backups. |

Left vs Right is deliberately not a tile. It stays hidden until both sides have been logged, so
most people could not go and see it.

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

| Issue | Note |
|---|---|
| Fatigue Learning nudges write a per-exercise override that stays invisible once Admin Mode is off | Known gap from `71b404a` |
| Declining Photos leaves no way to get a card out of the app | Accepted in `917b2d0` |
| The free-limit sheet says "You've used your 10 free workouts" to lapsed subscribers too | [FreeLimitSheet.swift:85](Repster/Features/Home/Views/FreeLimitSheet.swift:85), left out of the free-month scope |
| Hip Adductor Machine shows a wrong Glutes tag; Farmer's Walk and Dead Hang lack forearms | Waits for the library re-tag |
| The 1.5 defect list | [RELEASE_1_6_CONSIDERATIONS.md §4](RELEASE_1_6_CONSIDERATIONS.md). No commit since 1.5 addresses them |

---

## 7. Tidy-up — optional, not blocking

- `CHANGELOG.md` stopped at 0.1, and `scripts/bump_release.sh` still enforces `0.x`
- Six design docs still say "uncommitted" for work that's committed
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
