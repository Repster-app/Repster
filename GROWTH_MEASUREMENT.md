# Growth Measurement — PostHog Setup

Written 2026-08-09. Purpose: find where paid App Store installs are leaking, using
events Repster already emits. Nothing here requires new code.

All event and property names below are the literal strings sent by
`Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift`. If you rename an
event there, update it here too.

---

## 0. Before you build anything: the one metric that matters

**Weekly cohort retention on `workout completed`.**

Do *not* use PostHog's default D1/D7 daily retention for this app. People don't
lift every day, so daily retention will read as a catastrophe even if the product
is healthy. A lifter training 3×/week who never misses a session still shows up as
"churned" on more than half of all D-N checks.

Set it up as:

- Insight type: **Retention**
- Cohortizing event: `workout completed` (first occurrence)
- Returning event: `workout completed`
- Granularity: **Weekly**
- Period: 8 weeks

Read the curve, not the individual numbers. What you want to see is the line
**flattening** around week 3–4 rather than continuing toward zero. A flat tail
means a real habit formed for that slice of users; a curve still sliding at week 6
means nobody is sticking and no amount of ad spend will help.

---

## 1. The activation funnel

Insight type: **Funnel**. Conversion window: **7 days**. Order: sequential.

| Step | Event | Filter |
|---|---|---|
| 1 | `onboarding step viewed` | `step` = `welcome` |
| 2 | `onboarding completed` | — |
| 3 | `workout started` | — |
| 4 | `first set logged` | — |
| 5 | `workout completed` | — |

Step 1 is your true denominator — it's the first thing that fires on a fresh
install, so it counts people who actually opened the app rather than people
App Store Connect counted as a download.

**How to read each drop:**

- **1 → 2 large:** setup friction. Break it down (§2).
- **2 → 3 large:** people finish setup and then don't know what to do. Home screen
  affordance problem.
- **3 → 4 large:** they opened a workout and stared at it. This is the one to care
  about most — it means the core screen isn't self-explanatory. Break out by
  `source` to see whether it's worse for `empty` than for `template`.
- **4 → 5 large:** something interrupts mid-session. Cross-check against
  `workout abandoned`.

---

## 2. Onboarding step-by-step drop-off

Insight type: **Funnel**, one step per screen, all on `onboarding step viewed`
filtered by `step`, in this order:

`welcome` → `units` → `bodyweight` → `smart_suggestions` → `import_prompt`

Then a second insight — **Trends**, event `onboarding step skipped`, broken down by
`step` — to separate "skipped it" from "quit here."

The hypothesis worth testing: `bodyweight` asks a stranger for a personal number
three screens in, immediately after an ad that promised a fast log. If either the
funnel or the skip chart spikes there, that's your fix.

---

## 3. Time-to-first-set

Insight type: **Trends**, event `first set logged`, broken down by
`elapsed_seconds_bucket`.

Buckets are `under_30s`, `30-60s`, `1-3m`, `3-10m`, `10m_or_more`. A heavy tail in
`3-10m` and `10m_or_more` on *first* sessions means people are hunting for how to
log rather than logging. Compare against `source` — if `empty` is much slower than
`template`, new users are being dropped into the hardest possible starting point.

---

## 4. The silent bounce: empty screens

Insight type: **Trends**, event `empty state shown`, broken down by `screen_name`.

This is already wired to fire whenever a screen renders with no data. Watch
`Charts` and `Insights` especially. A new user who taps Charts on day one and finds
a blank screen has just been shown that the app is empty rather than that it's
useful — and there's currently nothing on that screen persuading them to come back.

Cross-reference: users who saw `empty state shown` for `Charts` in their first
session, retained vs. those who didn't. If there's a gap, the empty states are
actively costing you users and are worth designing properly.

---

## 5. Paywall and subscription

Insight type: **Funnel**, 30-day window:

1. `workout completed` (first)
2. `paywall shown`
3. `purchase started`
4. `purchase completed`

Then the question that actually matters — **does the paywall land before the value
does?** Build a funnel of `paywall shown` → `insights opened` and the reverse,
`insights opened` → `paywall shown`, and compare conversion.

`freeWorkoutLimit` is 5 (`Repster/Core/Services/MonetizationService.swift:31`), so
a 3×/week lifter meets the paywall around day 12. If most people hit it having
never opened Insights, you're asking them to pay before they've seen the thing
they'd be paying for.

Also break `paywall shown` down by `source` (`paywall`, `settings`,
`membership_settings`) — conversion from a wall you hit mid-flow and a page you
chose to visit are very different numbers and shouldn't be averaged together.

Rough orientation: consumer freemium free→paid usually lands somewhere around
**1–5%**. Treat that as a sanity check, not a target.

---

## 6. Ad quality: retention by keyword

This one is not in PostHog — it's App Store Connect, and it's the cheapest
possible win, so do it first.

1. App Store Connect → Analytics → Acquisition, segmented by campaign/keyword.
2. For each keyword, look at retention rather than installs or CPI.
3. Kill keywords with high install volume and near-zero retention.

Broad match and Search Match buy installs from people who searched for something
unrelated. Those users had no intent, churn instantly, and drag every average in
this document downward — which makes the product look broken when the targeting is
what's broken. **Rule of thumb: a cheap install that never logs a set costs you
more than it saves, because it also poisons your data.**

Note the message match too: ASA generates ads from the default product page, which
still carries the "fast lifting log" line. Whatever the app does in its first
thirty seconds should deliver on that specific promise.

---

## 7. Watch ten session replays

Session replay is already enabled. Filter to users who fired
`onboarding step viewed` but never `first set logged`, and watch ten of them end
to end.

This will typically teach you more in twenty minutes than any dashboard here.
Dashboards tell you *where* people leave; replays tell you *why*.

---

## Suggested order of work

1. §6 keyword retention — free, fast, often the whole problem.
2. §1 activation funnel — find the biggest in-app drop.
3. §7 replays — understand that drop.
4. Fix the one thing.
5. §0 weekly cohort — confirm it moved. Give it 3–4 weeks before judging.

Change one thing at a time. If you fix onboarding, notifications and the paywall
all in the same release, you will not know which one worked.
