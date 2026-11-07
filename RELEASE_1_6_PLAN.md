# 1.6 Release Plan

**Written:** 2026-11-02, from git, the tree and PostHog, not copied from older plans.
**Re-checked:** 2026-11-04, against the same sources.
**Live:** 1.5 (build 2), public since 2026-09-07.
**1.5.1 never shipped.** It only reached TestFlight (builds 1 to 7, two team iPhones), so
everything after the 1.5 commit is unreleased and rolls into 1.6.
**In the project right now:** `MARKETING_VERSION = 1.6`, build 1 (set 2026-11-04).
**Status:** rounded up, scope not locked. The open scope calls are in
[PRE_1.6_CHECKLIST.md §0](PRE_1.6_CHECKLIST.md).

## What this document is

**Everything below is in the build.** It follows the same split as 1.5:

- This file is what 1.6 contains.
- [PRE_1.6_CHECKLIST.md](PRE_1.6_CHECKLIST.md) is what has to happen before it ships.
- [RELEASE_1_6_CONSIDERATIONS.md](RELEASE_1_6_CONSIDERATIONS.md) is what was considered and is
  not in the build.

## State of the tree

| | |
|---|---|
| Since the 1.5 commit (`ac67d7f`, 2026-09-07) | 43 commits. 31 change the app or tests; 12 are docs, tooling or the 1.5.1 bump |
| App code | 87 files, +7,758 / −848. 21 new files, none removed |
| Uncommitted | Only the Part 5 files, which stay out of git on purpose. The suggestion data (`60f9e5e`) and the three 2026-11-07 fixes were committed on 2026-11-07 |
| Pushed | Up to `468fb24`, on 2026-11-04. Pages serves `NewMain:/docs`, so the corrected support and terms pages went live with it. Nothing since is pushed, including the 2026-11-06 privacy policy |
| Test suite | 1,048 run, 14 skipped, 0 failed, no crashes. iPhone 17 Pro simulator, re-run 2026-11-07 on the code committed as `ec2f921` (1,040 on `ad3cacf`, 2026-11-04). The built app and the Live Activity extension both report 1.6 |
| Release-config build | Succeeds with 0 errors, unsigned, generic iOS device, 2026-11-04. The body-map artwork is absent from the built app, checked by searching it for a path string, while a known app string is found |
| Upgrade risk | No SwiftData model change, no backup format change, no new permission string, no entitlement, privacy manifest or package change since 1.5 |
| TestFlight | Newest is 1.5.1 build 8 (2026-11-04, iOS 26.6). It has everything up to the Left vs Right rebuild, but was used for about a minute. No 1.6 build yet, and the suggestion data isn't in any build |
| Phone sign-off | None recorded. The last column of each table says what PostHog can prove |

**The last column:**

- **Ran:** PostHog shows it firing on a TestFlight iPhone. It has been used, not signed off
- **Never fired:** it reports an event, and none has ever arrived from a real phone
- **No signal:** it reports no event of its own, so PostHog can't say
- **Not on TestFlight yet:** in no TestFlight build so far

---

# Part 1 — New for users

| Feature | What it does | Commits | Doc | Real phone |
|---|---|---|---|---|
| **Left vs Right** | One tile on Insights, a list of exercises under their muscle groups, and an exercise page with a line chart and the best set from the last 3 sessions, marked with whether RIR counted. Rebuilt 2026-11-02. Hidden until both sides have been logged; 6 of 69 library exercises are unilateral | `23240ee` `b40bf34` `331db42` `728a462` | [UNILATERAL_IMBALANCE_EXPLORATION.md](UNILATERAL_IMBALANCE_EXPLORATION.md), [SIDES_RETHINK_SCOPING.md](SIDES_RETHINK_SCOPING.md) | Ran, briefly: opened once on build 8 |
| **Share any saved workout** | The share card now opens from Calendar and the Home workout screen, not just the summary | `dad017f` | [SHARE_FROM_HISTORY_SCOPING.md](SHARE_FROM_HISTORY_SCOPING.md) | Ran |
| **Export one workout** | "Export Workout" in the "…" menu writes a JSON file and opens the share sheet. It can never be restored as a backup | `dd2256b` | [WORKOUT_EXPORT_SCOPING.md](WORKOUT_EXPORT_SCOPING.md) | **Never fired** |
| **Set notes in history** | Tap a noted set to read its note, in exercise history and Calendar. Masked in replay | `a4d7567` | [SET_NOTES_IN_HISTORY_SCOPING.md](SET_NOTES_IN_HISTORY_SCOPING.md) | No signal |
| **Secondary muscles** | Exercise detail lists them. The editor gains a 19-muscle grouped picker, and Primary Muscle becomes a menu with colour dots. Nothing recalculates | `acf4c39` `219b49b` | [SECONDARY_MUSCLES_SCOPING.md](SECONDARY_MUSCLES_SCOPING.md) | No signal (the rework is in build 8); colour dots unverified |
| **Supersets past a pair** | Picking a partner already in a superset joins that group, so trios work. The partner picker shows existing groups | `96de8f2` | [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) | No signal |
| **Insights preview for new users** | Someone with no sets sees what will appear and when, instead of an empty screen | `188e5ff` | [INSIGHTS_NEW_USER_SCOPING.md](INSIGHTS_NEW_USER_SCOPING.md) | No signal |
| **Free-limit sheet** | Running out of free workouts now explains itself before the paywall: what was logged, and that history, charts and insights stay open | `9cbf4d6` | [PAYWALL_BRIDGE_SCOPING.md](PAYWALL_BRIDGE_SCOPING.md) | **Never fired** |
| **Free month for feedback** | At the free limit, or after a subscription ends: one notification, an offer card, 3 questions, then the App Store redeem link with `REPSTERMONTH` | `881af48` | [FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md](FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md) | **Never fired**, and required before submission |
| **Subscriber thank-you** | A one-time card on Home offering 3 questions or an email | `881af48` | Same doc | Ran |
| **Share Training Data** | Sends each finished workout, set by set, to PostHog under the anonymous id. **On by default.** Turning analytics off stops it too. Since 2026-11-06 each ticked set also carries what Smart Suggestions had for it (schema 2), for calibrating suggestions across users | `4fef2c0` `60f9e5e` | [TRAINING_DATA_SHARING_DESIGN.md](TRAINING_DATA_SHARING_DESIGN.md) | Sending ran. The on/off switch **never fired**, so the history upload hasn't run. The suggestion fields have never run on a phone |

# Part 2 — Changes to existing screens

| Change | What it does | Commit | Real phone |
|---|---|---|---|
| **Share button removed** | Save to Photos is the card's only action, and the sheet stops at 0.85 height. A removal: people who decline Photos can no longer get the card out | `917b2d0` | Ran |
| **Admin Mode hidden** | Hold Version for 2 s and confirm. It turns off once for everyone on first launch, and Capacity Guards stay on outside it | `71b404a` | No signal |
| **Onboarding polish** | "Build my own" is a fifth program card, FitNotes import hides the unit row, sheet buttons no longer promise a workout, Health sheet fits its content | `b2defd4` | No signal |
| **Workout header** | "End" replaces the old finish label, "+ Exercise" replaces a bare "+", and the clock stays on one line past an hour | `3433981` `5226baa` `331db42` | No signal |
| **4 kg weight increment** | New option in the exercise increment picker | `0eb8eaa` | No signal |
| **Suggestion feedback removed** | Too much drop / About right / Not enough drop is gone from the workout summary. Either drop button stopped learning for that exercise for good, and the only undo is behind the now-hidden Admin Mode. About right never did anything. The admin screen keeps its own nudges | `052ab19` | Not on TestFlight yet |
| **Lapsed subscribers' free-limit title** | "Your subscription has ended" and "Subscribe again to keep logging new workouts", instead of "You've used your 10 free workouts". Same words as their free-month notification | `ec2f921` | Not on TestFlight yet |

# Part 3 — Fixes

| Fix | Who it affected | Commit | Real phone |
|---|---|---|---|
| **Onboarding could stay stuck after "Start training"** | Live on 1.5, intermittent, fine after relaunch | `65c2652` | Fresh installs passed on simulator |
| **Adding an exercise already in the workout hid its sets** | Live on 1.5. Looked like data loss; nothing was lost | `befacc4` | No signal |
| **Empty workouts spent a free slot** | Live on 1.5, and common: a first free workout is usually empty | `6611cd8` | No signal |
| **Menus refreshed every second in workout sheets** | Live on 1.5. The clock and rest bar moved into child views | `e12b5a6` | In build 8, but no workout has run on it |
| **Rest-alarm prompt was clipped** | Live on 1.5. Subtitle cut off, buttons off the bottom | `378316f` | No signal |
| **Warm-up toggles could show the wrong state** | After a failed stats rebuild | `18a29b1` | Manual pass, 2026-09-13 |
| **Three library exercises had the wrong secondary muscles** | Never shown before 1.6. Hip Adductor Machine now lists Adductors instead of Glutes, and Farmer's Walk and Dead Hang list Forearms. A one-time update fixes existing installs, leaving anything edited or renamed alone | `1651d6f` | Not on TestFlight yet |
| **SwiftData crash hardening** | Phases 1 and 4 of the fix: live models stop crossing actors on the main paths, and settings pass snapshots. Phases 2 and 3 became optional once iOS 17 was dropped | `84f24d6` `1c4f951` | Manual pass, 2026-09-13 |

# Part 4 — Build and tooling

| Change | Note | Commit |
|---|---|---|
| **Minimum iOS raised to 18.0** | Costs nobody: 0 users on iOS 17 in the last 60 days (26: 137, 27: 22, 18: 6). It retires the iOS 17 write race | `e198d0d` |
| **Test schema** | Test containers now use the app's full model list | `b7944c8` |
| **Live-model ratchet test** | A new crossing fails the build | `18a29b1` |
| **Codebase map generator** | `scripts/codemap/` | `bb260e3` |

# Part 5 — Kept out of git on `NewMain`

`marketing/growth-workspace/` is a nested repo, and the two
`marketing/metrics/` business-review files hold real money figures in a public repo. Don't
`git add -A`.

# Part 6 — Not in the build

Agreed or scoped, and not built. The detail is in
[RELEASE_1_6_CONSIDERATIONS.md](RELEASE_1_6_CONSIDERATIONS.md).

- Secondary muscles: library re-tag, the update for existing users, the coverage strip
- Insights option B ("since you started" e1RM)
- Sample history, default rep range, bodyweight suggestions, the program picker redesign,
  performance vs expected
