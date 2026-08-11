# App Store product page review — Aug 2026

Audit of the live listing plus two candidate screenshot sets. Written 2026-08-11 against
what is actually live (**1.3**), not against the repo.

Companion to `product-page.md` (the launch metadata) and
`../campaigns/technical-lifter/ad-kit.md` (the technical positioning test, whose copy
this reuses).

---

## 1. What is actually live

Pulled from the iTunes lookup API on 2026-08-11, app id `6766094305`.

| | |
|---|---|
| Name | `Repster - Gym Workout Tracker` (29/30 chars) |
| Version live | **1.3**, released **2026-06-11** — two months stale |
| Ratings 🇺🇸 | **0 ratings** |
| Ratings 🇬🇧 | **0 ratings** |
| Ratings 🇩🇰 | 5 ratings, 5.0 avg |
| App Preview video | **none** |
| Screenshots | 6, iPhone only, no iPad set |

Ratings are **per storefront**. Denmark has stars; every other market shows a product
page with no rating row at all.

**Live screenshot order.** The CDN paths preserve your upload filenames. Display order is:

> `4.png` → `1.png` → `2.png` → `5.png` → `3.png` → `6.png`

If the files you sent are numbered in that same 1–6 order, the live sequence is:

1. TRACK PROGRESS (the angled 3-phone shot)
2. AND MORE…
3. REVIEW HISTORY
4. BUILD PROGRAMS
5. START FAST
6. TRAIN SMARTER

That mapping is an inference — confirm it in App Store Connect. If it's right, the two
weakest frames are in slots 1 and 2 and the differentiator is dead last, which is the
single most expensive thing on this page.

---

## 2. Three things that matter more than the screenshots

### 2.1 The page has no stars in the markets you're buying traffic in

Paid ASA traffic is landing on a page with zero social proof. In this category — where
a search for "workout tracker" returns Hevy and Strong with five-figure rating counts —
no stars reads as abandoned. No screenshot fixes that.

**It's already fixed in code and just unshipped.** `ReviewPromptService.swift` landed in
`f4d2e65` on 2026-08-08 — *after* 1.3 went out. Milestones are 3 / 12 / 30 completed
workouts, and the first one fires before `freeWorkoutLimit = 5`, which is the right
placement. So: shipping 1.4 turns the ratings tap on.

Until it's on, consider narrowing ASA spend toward storefronts that have stars, or accept
that you're paying to send people to a page that can't close.

### 2.2 The live build is 1.3, and screenshots are version-locked

Default-product-page screenshots can't change without a new version submission. You need
to ship 1.4 anyway (Insights v2, HealthKit, the review prompt), so the new screenshot set
should ride along with it.

That also changes what you're allowed to claim. The ad-kit's "off-limits until it ships"
list — Insights v2, HealthKit — expires the moment 1.4 is live. Insights is a genuinely
differentiated surface and it should be on the page.

**Two exceptions that don't need a build:**

- **Custom Product Pages** — up to 35, each with its own screenshots, preview and promo
  text, each with its own URL, and usable as Apple Search Ads creative. This is exactly
  what the ad-kit flagged ASA as blocked on.
- **Product Page Optimization** — up to 3 treatments against your current page, traffic
  split automatically, conversion measured by Apple. This is the mechanism that answers
  your broad-vs-hardcore question with data instead of taste.

### 2.3 No App Preview video

Your differentiator is a *behaviour*: cut your rest short, and the suggested weight drops.
A still frame can't show that. A muted 20-second video can, and it takes over the first
slot in search results.

The storyboard already exists in `product-page.md` §Preview Video Storyboard, and the
sharper one is Script A in the ad-kit ("Watch the target move"). Neither was ever shot.
This is the highest-value unmade asset you have.

---

## 3. What's wrong with the current six

**The caption block eats the top third and the phone starts past the halfway mark.**
Apple serves search results at roughly 320×480 per thumbnail. At that size your frames
show a headline, some grey subtext, and a sliver of dark device. The product — the thing
that makes someone tap — is not visible at the moment the decision gets made. Pull the
device up, crop into the UI, and let the screen occupy the top 55–60%.

**Dark UI on a dark background gives you no silhouette.** All six are charcoal on charcoal.
In a results row of three thumbnails they read as three grey rectangles. Your own v2 set
(`../generated/app-store-v2/`) put the app on brand blue `#5B8DEF` — that instinct was
right and it got dropped. Keep the app dark (that's a real product attribute; gyms are
dark and phones are bright), but put it on a field it can separate from.

**The headlines are the category's default vocabulary.** START FAST, TRACK PROGRESS,
BUILD PROGRAMS, REVIEW HISTORY — every competitor could ship those verbatim. Nothing on
this page is a reason to switch. Meanwhile the *subtext* carries all the specific
information, and subtext is unreadable at thumbnail scale. The information is in the wrong
line.

**"AND MORE…" is a wasted slot, and it's slot 2.** Never ship "and more" — it's a
placeholder that says you ran out of things worth naming. Three phones at one-third scale
means nothing on any of them is legible, and the middle one is showing a numeric keypad,
which is a picture of data entry drudgery in an ad for a tracker that saves you time.

**Slot 1 is the angled 3-phone composition.** Rotated device mockups are the weakest
performer at thumbnail scale — the text skews, the crop fights the frame, and it reads as
a template. Whatever else you change, slot 1 wants to be flat, tight, and high-contrast.

**The visual grammar is inconsistent.** Two frames are flat 1-up, one is angled 3-up, one
is a floating collage. The set reads as assembled rather than designed.

**There are no numbers anywhere.** "Smart weight suggestions" is a claim. "125 kg for 5–8
reps, adjusted for the rest you took" is evidence. Your own ad-kit already worked this out
— "*at feed scale a full screenshot makes every number illegible, which kills creative
whose argument is the numbers*" — and then the App Store set does the exact thing the kit
warns against.

**The one thing nobody else has is buried.** The fatigue/e1RM load model appears as the
word "fatigue" in a subtitle on the last frame and as a 1/9th-scale panel inside "AND
MORE". That screen — Fatigue Learning, applied rate 1.80%, cumulative error, per-exercise
diagnostics — is the most differentiated image you own and it's currently thumbnail-sized
inside a filler slide.

**Nothing speaks to the switcher.** CSV import from Strong and Hevy is in your description
and nowhere in your screenshots. "Bring your history with you" is one of the highest-intent
messages available in this category, because everyone worth acquiring is already logging
somewhere else.

---

## 4. Set A — broad (mainstream lifter)

Refines what you have rather than replacing the audience. Every headline states a specific
capability; every subtitle adds the qualifier that makes it credible.

| # | Headline | Subtitle | Capture |
|---|---|---|---|
| 1 | **It picks your next weight** | From your recent sessions and the rest you actually took | `ActiveWorkoutView` + `WeightSuggestionCardView` |
| 2 | **Last time, in the same row** | Weight, reps and RIR from your last session while you log | `SetTableView` + `LastWorkoutCardView` |
| 3 | **PRs find themselves** | Every rep-max tracked automatically, from the set you just did | `RecentPRsView` / `ExercisePRsView` + `PRBadgeView` |
| 4 | **The rest timer lives on your Lock Screen** | Live Activities and Dynamic Island keep the clock in reach | `RestTimerView` + Live Activity |
| 5 | **Start in one tap** | Save a session once, then repeat it forever | `TemplateCardView` |
| 6 | **What changed this week** | Sets per muscle against your own 8-week baseline | `TrainingStatusCardView` + `MuscleVolumePanelView` — **1.4 only** |
| 7 | **Years of training, one chart** | Volume, e1RM and muscle split over any window | `ChartsTabView` / `BreakdownTabView` |
| 8 | **Bring your history with you** | CSV import from Strong, Hevy and others. Export any time. | `ImportView` / `ExportView` |

Notes on the set:

- Slots 1–3 are the ones that matter. Everything from 4 down is for people already
  scrolling, which is a minority.
- Slot 6 requires 1.4 to be live. If 1.4 slips, promote 7 and 8 and ship seven frames.
- Slot 8 is the switcher frame and is worth more than its position suggests — consider
  testing it at 3.

## 5. Set B — technical (hardcore lifter)

Same app, narrower door. This deliberately loses people who don't log RIR, which is the
point: the ad-kit's whole thesis is that the audience which cares is smaller and converts
harder. All copy here is already claim-verified in the ad-kit's claim inventory.

| # | Headline | Subtitle | Capture |
|---|---|---|---|
| 1 | **Set 3 costs more than set 1** | Fatigue accumulates per set and decays with the rest you actually take | Smart Suggestions card, magnified |
| 2 | **Rest is an input, not a stopwatch** | Cut it short and the next target moves down | `RestTimerView` → suggestion recalculating |
| 3 | **RIR is a column, not an afterthought** | Weight, reps and RIR all feed the model. Warmups never touch it. | `SetTableView` with the RIR column |
| 4 | **e1RM from your peak sets, not your last one** | One bad session doesn't reset your numbers | `E1RMCardView` + history with PR markers |
| 5 | **Tune the model. Or switch it off.** | Recency window, default RIR and fatigue rate are all yours | `PrescriptionSettingsView` — **capture still missing** |
| 6 | **It grades its own predictions** | Per-exercise error tracking that corrects the fatigue rate | `FatigueLearningAdminView` |
| 7 | **Your data leaves when you do** | CSV in, CSV out, on device, no account | `ExportView` |

Notes on the set:

- Slot 5 is still the blocked capture from the ad-kit (concept 05). Same instruction
  applies: capture the real screen, don't substitute — "here is the model, exposed" *is*
  the claim, and the settings screen is the proof.
- Slot 6 is the Fatigue Learning screen you already have a capture of. Give it a full
  frame.
- The register shift is real: Set A says "it picks your next weight", Set B says "set 3
  costs more than set 1". Same feature, different reader. B assumes you know why that's
  interesting.
- Keep the ad-kit's guardrails: nothing medical, nothing about injury, no "optimal", no
  "scientifically proven", no "makes you stronger". Describe the mechanism, never promise
  the outcome.

---

## 6. How to choose between them

Don't. Run both.

1. **Ship 1.4 with Set A as the default page.** It's the safer general-audience set, it
   turns on the ratings prompt, and it refreshes a two-month-old listing.
2. **Build Set B as a Custom Product Page.** No new binary needed. This unblocks the ASA
   half of the technical positioning test, which the ad-kit correctly parked pending
   Reddit/social results — if those come back positive, the CPP is the next step and it's
   already built.
3. **Run Set B as a Product Page Optimization treatment** against Set A. Apple splits the
   traffic and reports conversion. That is a cleaner read than anything you can infer from
   ASA install rates.

**One caution about how to read it.** Per `GROWTH_MEASUREMENT.md` and what you already
know: install volume isn't your bottleneck, post-install retention is. So the number to
watch is not conversion rate — it's the retention of the cohort each page produces. A
technical page that converts *worse* but retains better is the winning page, because
you're paying for installs either way and only the ones who stay are worth anything.

That's the real argument for the hardcore direction, and it's a product argument, not a
copywriting one: a page that filters at the door sends you fewer, better-matched users,
and a better-matched user is exactly what fixes an activation problem. Same reasoning as
the ad-kit's §5 point 3, applied to the product page instead of the ad.

---

## 7. Craft rules for whoever renders these

- **Device occupies the top 55–60%.** Caption goes underneath or overlaps the top of the
  screen. Not a third of empty space above it.
- **One line of headline.** Two words if possible, four maximum. If the point needs the
  subtitle to survive, it's the wrong headline.
- **Crop into the UI.** Don't show the whole phone. Show the part that carries the
  argument, magnified — the ad-kit's format, applied to the store.
- **Test at 320×480.** That's the size Apple actually serves in search results. If the
  argument doesn't survive at that size, it doesn't exist. Render, scale down, look.
- **Give the dark UI a background it can separate from.** Brand blue `#5B8DEF` from the v2
  set, or a strong accent glow. Not charcoal on charcoal.
- **One visual grammar across all frames.** Flat, single device, consistent crop and
  caption position. No angled mockups, no collages.
- **Real data.** Realistic weights, real exercise names, believable dates. The current set
  is good on this — a set showing `50 kg × 0 reps` (frame "AND MORE") is not.
- **Numbers in frame wherever possible.** 125 kg, 5–8 reps, 1.80%, +2.5 kg. Specificity is
  the whole differentiator.
- Tooling: `aso-appstore-screenshots` skill, or extend
  `../tools/render_technical_campaign.swift`, which already has the magnified-crop layout
  grammar these need.

---

## 8. Sequence

1. Capture the missing screens: `PrescriptionSettingsView`, `FatigueLearningAdminView`,
   `ImportView`, and the 1.4 Insights screens.
2. Render Set A. Check every frame at 320×480.
3. Ship 1.4 with Set A + a refreshed description. Ratings prompt goes live with it.
4. Shoot the App Preview video (ad-kit Script A — the rest timer moving the target).
   Highest-value unmade asset.
5. Build Set B as a Custom Product Page; point the technical ASA keyword themes at it.
6. Run Set B as a PPO treatment. Judge on cohort retention, not conversion.

Not addressed here and worth a separate look: the subtitle field (the API doesn't expose
it, so it wasn't verified), the keyword field, and the fact that `Reps`, `RepFit`,
`RepCount` and `REPR` are all live in this category and will bleed your brand searches.
