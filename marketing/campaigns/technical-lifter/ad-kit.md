# Technical-lifter ad kit

Positioning test written 2026-08-09 against shipped version **1.3**.

This is a creative test, not a repositioning. The App Store product page, subtitle,
and keyword field stay exactly as they are (`marketing/app-store/product-page.md`).
Nothing here requires an App Store Connect change except the Apple Search Ads
section, which is flagged as blocked for that reason.

---

## 1. What this tests

The launch kit sells speed: *"A fast lifting log that keeps your training history
useful while you train."* That is the most contested claim in the category — every
competitor makes it, and it gives a lifter no reason to switch.

The hypothesis here is that Repster's actual differentiator is the load model
behind Smart Suggestions, that nobody else markets it, and that the audience which
cares about it is smaller but converts harder.

**Control:** the existing creative in `marketing/generated/social/`.
**Variant:** the four concepts below.

Same destination for both. This isolates message from everything else.

---

## 2. Claim inventory

Every claim used in this kit, and where it is true in the code. Do not add a claim
to this campaign without adding a row here first.

| Claim | Where it's true |
|---|---|
| Fatigue accumulates per set and decays with actual rest | `LoadPrescriptionService.swift:5-13` — `exp(-restSeconds / τ)`, τ=180s default, per-exercise override |
| Fatigue is projected forward across pending sets | `LoadPrescriptionService.swift:9` |
| Target load comes from your rep and RIR target, not a flat percentage | `LoadPrescriptionService.swift:11-12` — `intensity_factor = reverseCalculate(1.0, targetReps + targetRIR)` |
| Capacity e1RM is the peak across recent workouts, not the last session | `estimateCapacityBaseE1RM` / `peakAcrossRecentWorkouts`, `LoadPrescriptionService.swift:196-315` |
| Warmups never contribute to estimates | `isEligibleForCapacity`, `LoadPrescriptionService.swift:274-284` |
| The model is calibrated against published research | `LoadPrescriptionService.swift:14-15` — Willardson, Nuzzo/SBS, RTS, PCr resynthesis |
| Recency window, default RIR, and fatigue are user-tunable | `PrescriptionSettingsView.swift` — `recencySection`, `defaultsSection`, `fatigueSection` |
| The model measures its own prediction error and adapts per exercise | `FatigueLearningService.swift` — `PredictionSnapshot`, `SessionErrorSummary`, `AppliedFatigueRateSource` |
| Data is local-first with CSV import and export | `ImportService.swift`, `ExportService.swift` |

### Off-limits until it ships

- **Training Insights v2** — the training-status card, muscle-volume-vs-baseline
  panel, and insight charts are untracked work on `NewMain` for 1.4
  (`TRAINING_INSIGHTS_V2_DESIGN.md`). Not in any user's hands. Do not advertise.
- **HealthKit** — write-on-finish was built on `NewMain` on 2026-08-09
  (`HealthKitService.swift`, still untracked) but is unshipped and still needs the
  App ID capability and device QA. Not in 1.3, so not advertisable.
- **Anything medical, diagnostic, injury-related, or coaching-shaped.** Already a
  rule in the capture checklist and it applies harder here, because technical copy
  drifts toward clinical phrasing on its own.
- **"Makes you stronger", "optimal", "scientifically proven".** The model is
  calibrated against literature; it is not a validated intervention. Describe what
  it does, never what it will do for the user's results.

---

## 3. Concepts

Rendered by `marketing/tools/render_technical_campaign.swift` into
`marketing/generated/campaigns/technical-lifter/` in three formats:
`feed-1080x1350/`, `vertical-1080x1920/`, `wide-1200x628/`.

The format deliberately breaks from the launch kit: it shows a **magnified crop of
the real UI**, not a whole phone. At feed scale a full screenshot renders every
number illegible, which is fatal for creative whose entire argument is the numbers.

### 01 — "It knows what set three cost you."
Fatigue accumulates set by set and decays with the rest you actually took. The
suggested load moves with it.
Crop: Smart Suggestions card. Annotation: *Every set priced from its own rep and RIR target.*
**Lead with this one.** It is the sharpest statement of the differentiator.

### 02 — "Your rest timer is an input, not a stopwatch."
Fatigue decays exponentially with the rest you actually take. Cut it short and the
next target reflects it.
Crop: rest timer. Annotation: *Rest feeds the model that sets your next load.*
The most demo-able claim — best candidate for video.

### 03 — "RIR is a column, not an afterthought."
Weight, reps, and RIR in one row. All three feed the load model, and warmups stay
out of it.
Crop: set table with the RIR column. Annotation: *Warmup sets excluded from every estimate.*
Cheapest qualifier: a lifter who doesn't know what RIR is will scroll past, which
is the point.

### 04 — "e1RM from your top sets. Not a guess."
Capacity is estimated from peak sets across your recent workouts, so one bad
session doesn't reset your numbers.
Crop: per-set history with PR markers. Annotation: *Peak across recent sessions, not just the last one.*

### 05 — "Tune the model, or turn it off." — BLOCKED

The strongest trust claim in the set, and the only one with no usable source
capture. It needs a screenshot of Settings → Smart Suggestions showing the recency
window picker, default RIR, and the fatigue toggle.

To unblock: capture that screen in dark mode on a 6.9" simulator with a realistic
database, save to `marketing/source/screenshots/prescription-settings.png`, add the
concept to the `concepts` array in the renderer, and re-run it. Do not ship this
concept with a substitute screenshot — "here is the model, exposed" is the claim,
and the settings screen *is* the proof.

---

## 4. Channels

### Reddit

Where the technical audience actually is. Two things to get right:

**Paid, not organic.** r/weightroom, r/powerlifting, and r/fitness30plus all
restrict self-promotion; posting these as a founder is a ban, not a campaign. Run
them as Reddit Ads targeting those communities.

**Reddit punishes marketing voice.** The ad copy should read like a comment from
someone who built the thing. Lead with the mechanism, not the benefit.

Suggested ad titles (pair with `wide-1200x628/` or `feed-1080x1350/`):

- `The suggested weight drops if you cut your rest short. Here's the model.`
- `I got tired of load calculators that ignore the four sets you already did.`
- `RIR, e1RM, and a fatigue curve you can actually tune. iOS lifting log.`
- `Why set 2 asks for more weight than set 1 at fewer reps.`

Body copy, one paragraph, no bullets, no emoji:

> Repster estimates your capacity e1RM from peak sets across recent workouts, then
> accumulates fatigue per set and decays it against the rest you actually took. The
> target for your next set comes from that, plus the rep and RIR target for that
> specific set — not a flat percentage. Recency window, default RIR, and the fatigue
> model are all adjustable, and you can turn the whole thing off. Free tier is 5
> workouts, CSV import and export, data stays on device.

Expect the top comment to be a methodology challenge. That is a good outcome —
answer it specifically and in public.

### Instagram / TikTok

Use `vertical-1080x1920/` as cover frames over real screen recordings.

**The hook has three seconds.** These scripts front-load the mechanism.

**Script A — concept 02, the strongest demo.**
1. `0-3s` Rest timer at 2:57, finger hits `-30s`. Caption: `Watch the target move.`
2. `3-8s` Cut to Smart Suggestions, load recalculates. Caption: `Rest is an input, not a stopwatch.`
3. `8-14s` Show the fatigue toggle in settings. Caption: `Tune it. Or turn it off.`
4. `14-18s` Logo. Caption: `Repster — iOS.`

**Script B — concept 01.**
1. `0-3s` Smart Suggestions card, both sets visible. Caption: `Set 2 asks for more weight at fewer reps.`
2. `3-9s` Zoom to the rep and RIR targets. Caption: `Every set priced from its own target.`
3. `9-15s` Show the set table filling in. Caption: `Not a flat percentage of your max.`
4. `15-18s` Logo.

**Script C — concept 03, qualifier-first.**
1. `0-3s` Set table, RIR column. Caption: `If you log RIR, this one's for you.`
2. `3-9s` Add a warmup set. Caption: `Warmups never touch your estimates.`
3. `9-15s` Smart Suggestions updates. Caption: `Weight, reps, RIR — all three feed the model.`
4. `15-18s` Logo.

### Apple Search Ads — BLOCKED on a Custom Product Page

ASA has no image creative of its own. Search results ads are generated from your
App Store product page assets, so the technical angle cannot appear in an ASA ad
until there is a **Custom Product Page** carrying it. None of the frames in this
kit can be used.

Sequence: run Reddit and IG/TikTok first, and only build the CPP if the message
wins there. Building it first spends App Store Connect effort on an untested claim.

Keyword themes to bid once a CPP exists — all high-intent, all low-volume, which is
the trade:

- Mechanism: `rir tracker`, `rpe logger`, `e1rm calculator`, `1rm tracker`,
  `autoregulation app`, `fatigue tracking`
- Method: `progressive overload app`, `periodization tracker`, `training log rpe`,
  `powerlifting log`, `strength training log`
- Migration: `strong app alternative`, `workout log csv import`, `export workout data`

Note the policy distinction: `product-page.md` bars competitor names from the
**App Store keyword field**. Bidding on competitor terms in ASA is a separate,
allowed mechanism and a separate decision. Flagged, not recommended.

---

## 5. Measurement

The unit of decision is **install rate per impression**, technical variant vs.
current creative, same destination, same budget, same window.

Run both simultaneously. Sequential tests on a shipped app confound with seasonality,
App Store featuring, and 1.4's release.

Watch three numbers:

1. **Tap-through rate** — did the message earn attention?
2. **Install rate** — did it survive the product page? A technical ad pointing at a
   speed-positioned page may attract taps that don't convert. That gap is the
   argument for a CPP, and it is the specific thing to look for.
3. **D7 retention of the cohort** — the real thesis. The bet is that this audience
   retains better, and retention is what the subscription sells. A variant that
   loses on install rate but wins on D7 is still a win.

**Expect a small sample.** Do not read a two-day result as signal, and do not chase
statistical significance you cannot reach at this spend — decide on direction and
magnitude, and say so out loud when calling it.

**Kill criteria:** if the technical variant loses on both tap-through and D7 after
two full weeks, the depth angle is not the wedge and the launch positioning stands.
