# Screenshot revamp — same six screens, rebuilt

Written 2026-08-16. Keeps every screen currently on the page. Changes the crop, the
caption and the order. No new features, no new app surfaces — five of the six need no new
capture at all.

Baseline: `live-screenshots-inventory.md`. Craft rules follow `screenshot-review.md` §7.

---

## The three problems, in one place

1. **The caption block eats the top third and the phone starts past halfway.** At the
   320×480 Apple serves in search results, you're showing a headline and a sliver of dark
   device. The product isn't visible when the decision gets made.
2. **Whole-phone shots make every number illegible.** The arguments on this page are
   numbers — 125 kg, 1.80%, 52.5 kg × 9 — and not one of them survives thumbnail scale.
3. **The headlines are the category's default vocabulary.** START FAST, TRACK PROGRESS,
   BUILD PROGRAMS. Every competitor could ship them verbatim. All the specific information
   is in the subtitle, which nobody reads at thumbnail size.

The fix for all three is the same: **crop into the UI, put the number in the headline
position, shrink the caption.**

---

## Global changes

| | Now | Change to |
|---|---|---|
| Composition | 3 flat, 1 angled 4-up, 1 collage | One grammar: hard crop into the UI, magnified 2–2.5× |
| Device area | Starts past 50% | Top 55–60% of frame |
| Caption | Top third, two-line headline + subtitle | Below or overlapping the art, one-line headline |
| Background | Charcoal on charcoal | Brand blue `#5B8DEF` (from the v2 set) — keep the UI dark, give it a field to separate from |
| Headline | Generic category verb | Specific capability, ≤4 words |
| Numbers | Buried in UI at 1× | Hero element, magnified |

---

## Frame by frame

### 1. TRAIN SMARTER → **"IT PICKS THE WEIGHT"**

Your strongest frame, and the argument is at the very bottom cut off mid-sentence.

- **Now:** whole phone, Sets tab. The Smart Suggestions card is bottom-of-frame, and the
  reasoning line truncates at `…adjusted for this`.
- **Crop to:** the Smart Suggestions card at ~2.5×, with the set row `1 · 122,5 · 8 · RIR 3 · ★PR`
  above it for context. Nothing else.
- **Headline:** IT PICKS THE WEIGHT
- **Subtitle:** Based on your recent sets and the rest you actually took.
- **Survives at 320×480:** **125 kg**, huge.
- **Move to slot 1.** This is the only frame on the page a competitor can't copy.

### 2. START FAST → **"PRs FIND THEMSELVES"**

- **Now:** whole Home screen. The generic `Start Workout / Log exercises, sets & reps` card
  gets prime position; the genuinely good content (real lifts, real weights) is below it.
- **Crop to:** the `RECENT PRS` block only — three trophy rows, magnified. Drop the week
  strip and the start card.
- **Headline:** PRs FIND THEMSELVES
- **Subtitle:** Every rep-max tracked automatically, from the set you just did.
- **Survives:** three gold trophies + `52.5kg × 9 reps`.

### 3. AND MORE… → **"IT GRADES ITS OWN GUESSES"** *(replace outright)*

Never ship an "and more" slot — it says you ran out of things worth naming. And the
Fatigue Learning screen trapped inside it at 1/9 scale is the most differentiated image
you own.

- **Now:** three phones at one-third scale; the front one shows a numeric keypad, which is
  a picture of data-entry drudgery. Also ships `50 kg × 0 reps` as visible data.
- **Replace with:** `FatigueLearningAdminView` full-frame, cropped to `Applied Rate 1.80%`
  plus three per-exercise diagnostic rows (One Arm Pulldown 2.10%, Seated Dip 2.40%, Chest
  Assisted Row 3.40%).
- **Headline:** IT GRADES ITS OWN GUESSES
- **Subtitle:** Per-exercise error tracking that corrects the fatigue rate.
- **Survives:** `1.80%` + the percentage column.
- Kill the keypad phone. Do not reuse the zero-rep capture anywhere.

### 4. REVIEW HISTORY → **"SEE YOUR CONSISTENCY"**

The dot grid is the one thing in your whole set that already reads at thumbnail size — a
pattern of colour holds up when text doesn't. The frame wastes it by showing the set table
underneath.

- **Now:** whole phone; month grid shares the frame with the Chest Press Machine set table.
- **Crop to:** the March 2026 month grid alone, edge to edge, dots enlarged. Drop
  everything below the calendar.
- **Headline:** SEE YOUR CONSISTENCY
- **Subtitle:** Every session, colour-coded by muscle group.
- **Survives:** the dot pattern. Best thumbnail performance of the six.

### 5. BUILD PROGRAMS → **"START IN ONE TAP"**

- **Now:** the top third of the screen is an instructional card — *"Tap any template to
  launch your workout. Use the top-right menu for import and AI tools…"* That's onboarding
  copy for existing users, sitting inside an ad.
- **Crop to:** the four template rows only. Coloured avatars, names, `4 exercises · 13
  sets`, muscle tags. Info card cropped out entirely.
- **Headline:** START IN ONE TAP
- **Subtitle:** Save any session as a template, then run it again.
- **Survives:** four coloured avatar circles — good shape recognition.

### 6. TRACK PROGRESS → **"FIVE YEARS, ONE CHART"**

The donut is a genuinely striking asset being shown at one-third scale inside an angled
composition. Angled multi-device mockups are the weakest performer at thumbnail size — the
text skews and it reads as a template.

- **Now:** four devices, angled, nothing legible on any of them.
- **Rebuild as:** single flat frame. Donut magnified to ~60% of the frame with `5.0M kg /
  Total Volume` centred, legend beneath, and the stats strip as a hero row: `11,345 sets ·
  114,667 reps · 556 workouts`.
- **Headline:** FIVE YEARS, ONE CHART
- **Subtitle:** Volume, e1RM and muscle split over any window.
- **Survives:** the donut ring shape + one big number.
- Drop the three edge devices. One screen, one argument.

---

## New order

| Slot | Frame | Was |
|---|---|---|
| 1 | IT PICKS THE WEIGHT | 6 (TRAIN SMARTER) |
| 2 | PRs FIND THEMSELVES | 5 (START FAST) |
| 3 | IT GRADES ITS OWN GUESSES | 2 (AND MORE…) |
| 4 | SEE YOUR CONSISTENCY | 3 (REVIEW HISTORY) |
| 5 | START IN ONE TAP | 4 (BUILD PROGRAMS) |
| 6 | FIVE YEARS, ONE CHART | 1 (TRACK PROGRESS) |

Rationale: the differentiator moves from last to first, the filler slot becomes the second
strongest argument, and the angled composition — the weakest thumbnail in the set — moves
off slot 1.

Confirm the current live order in App Store Connect before reordering; the order in
`live-screenshots-inventory.md` is inferred from CDN filenames, not verified.

---

## Captures needed

Five of six re-cut from captures you already have. Only one is new:

- [ ] **`FatigueLearningAdminView`** — clean capture, scrolled so Applied Rate and at least
      three diagnostic rows are in frame. (A capture exists inside the old "AND MORE"
      collage but is too small to re-crop.)
- [ ] Re-shoot the Smart Suggestions card **without** the truncated reasoning line, or crop
      above the truncation.
- [ ] Verify no frame ships a zero-rep set.

## Before rendering

Every frame gets checked at **320×480** — render, scale down, look. If the number that
carries the argument isn't readable at that size, the crop isn't tight enough yet.

Note: screenshots are version-locked to a build submission, so these ship with 1.4.
