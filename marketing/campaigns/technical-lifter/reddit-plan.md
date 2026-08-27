# Reddit plan — technical-lifter positioning

Written 2026-08-09. Companion to `ad-kit.md`.

> **Verification warning.** Subreddit rules could not be checked programmatically
> when this was written — Reddit blocks automated fetching. Every rule claim below
> is structural (how these communities work) rather than quoted. **Confirm the
> current sidebar, wiki, and pinned posts of any sub before posting.** Rules change,
> mod teams change, and getting this wrong costs you the account.

---

## 1. The distinction everything else depends on

There are two Reddit games and conflating them is the most common way app founders
get banned.

**Paid — Reddit Ads.** You target a subreddit's audience without being subject to
that subreddit's self-promotion rules. The frames in `ad-kit.md` are for this. No
permission needed, fully measurable, costs money.

**Organic — posting and commenting.** Subject to each sub's rules *and* to a
community's spam immune system, which is far stricter than the written rules. Free,
slow, high-risk, and the only channel that builds credibility.

They are not substitutes. Run paid for volume. Run organic for the thing paid can
never buy: technical lifters believing the model is real.

### Why organic is viable here at all

It normally isn't. "I built a workout tracker" is the single most spammed post
category in fitness subreddits, and every one of these communities has seen a
hundred of them.

The unlock is the positioning test itself. **A fast lifting log has nothing to say
to r/weightroom. A fatigue model calibrated against Willardson, Nuzzo/SBS and RTS
is content that sub already argues about.** The methodology is the post. The app is
a footnote.

This is the whole strategy in one line: *you are not promoting an app, you are
contributing to a technical argument you happen to have built a tool for.*

---

## 2. Subreddit map

Tiered by audience fit against promo tolerance. Sizes are qualitative on purpose —
verify before relying on any of it.

### Tier A — the actual target, strictest rules

High technical literacy, exactly your buyer, near-zero tolerance for promotion.
These are worth months of patience.

| Sub | Why it fits | How to approach |
|---|---|---|
| **r/weightroom** | Intermediate-to-advanced, methodology-obsessed, rewards long effort posts. Your single best fit. | Methodology post only, after real participation. Message mods first. |
| **r/AdvancedFitness** | Research-literate, discusses studies directly. Small but perfectly aligned. | Literature-framed post. Cite the actual papers; expect to defend them. |
| **r/powerlifting** | Competitive, percentage- and RPE-native. | Comments first. Check for a weekly/self-promo thread. |
| **r/naturalbodybuilding** | RIR/RPE-fluent, hypertrophy framing, volume-per-muscle discussions. | Good fit for the 1.4 Insights work later, not now. |
| **r/Fitness** | Enormous reach, but the most aggressively anti-promotion sub in the category. | **Participate, never promote.** Treat any promo as an account loss. |

### Tier B — adjacent, more forgiving

Smaller, friendlier, lower ceiling, much lower risk. This is where to make your
first mistakes.

- **r/Fitness30plus** — friendlier culture, receptive to "training smarter" framing.
- **r/QuantifiedSelf** — data/self-tracking people. Tool-tolerant by nature and
  genuinely interested in modelling. Underrated fit for your angle.
- **r/PowerliftingTechnique**, **r/deadlift**, **r/bench**, **r/squat** — narrow,
  practical, low promo tolerance but useful for comment-level presence.
- **r/xxfitness** — supportive, rule-enforced, worth checking for a promo thread.
- **r/gainit**, **r/GYM**, **r/StrengthTraining** — general, mixed quality.
- **Velocity-based-training and autoregulation communities** — if an active one
  exists, it is the highest-intent audience on this entire list, because
  autoregulation is precisely what your model does. Search before assuming.

### Tier C — promo is allowed by design

Legitimate, but understand what you're buying: **builders and deal-hunters, not
lifters.** Useful for feedback, bug reports, and early testers. Nearly useless for
finding people who will still be logging sets in March.

- **r/SideProject** — show-and-tell is permitted; story and proof-of-work expected.
- **r/AlphaAndBetaUsers**, **r/BetaTestersNeeded** — built for tester recruitment.
- **r/AppHookup** — requires you to actually give something away (promo codes, free
  IAP). Attracts free-tier users almost exclusively.
- **r/iosapps** — verification typically required; confirm rules first.
- **r/iOSProgramming** — designated feedback threads only, never raw links. Your
  peers, and a decent place to discuss the SwiftData and `@ModelActor` work.

### Tier D — skip

- **r/bodybuilding** — large, meme-driven, hostile to tools and promo.
- **r/iPhone** and general tech subs — self-promotion banned, audience unqualified.

---

## 3. Post archetypes

Ranked by what actually works. Note that the top two are not promotion at all.

### Archetype 1 — the comment (highest ROI, lowest risk)

Find existing threads asking the question your app answers: *how much weight should
I drop between sets*, *how do I autoregulate*, *does anyone track RIR*, *app that
does RPE*. Answer the question completely and well. Mention the app only if directly
relevant, and always disclosed.

This is where most of your first 90 days should go. It is unglamorous, it does not
scale, and it is the only approach with essentially no downside.

### Archetype 2 — the methodology post (highest ceiling)

A genuinely educational post where the reader gets full value without ever
downloading anything. The app is one disclosed line at the end.

Candidate framings drawn from what you actually built:

> **"How much does cutting rest from three minutes to ninety seconds cost your next
> set?"** — walk through the exponential decay model, the τ=180s default, and where
> the calibration comes from. This is a question that sub genuinely argues about and
> you have a defensible answer.

> **"Why your next set shouldn't be a flat percentage of your 1RM."** — the case for
> deriving load from the rep and RIR target of *that specific set*, plus fatigue
> state, rather than a fixed block percentage.

> **"Estimating capacity from peak sets across recent sessions, not your last
> workout."** — why one bad session shouldn't reset your numbers. Short, arguable,
> concrete.

Rules for this format:
- The post must stand alone as useful writing. If deleting the last line makes it
  worthless, it's an ad.
- Show the actual reasoning, including the parts you're unsure about.
- Cite real sources and be ready to defend them. **Expect the top comment to be a
  methodology challenge** — that is the best possible outcome. Answer it
  specifically, in public, without defensiveness.
- Never overstate. This community can smell "optimal" and "science-based" from
  orbit, and the same restraint the ad kit demands applies double here.

### Archetype 3 — the aggregate-data post (highest ceiling, needs clearance)

*"I looked at N thousand logged sets — here's the real rep drop-off curve versus
what the literature predicts."* This is catnip for r/weightroom and r/AdvancedFitness
and nobody else can write it, because nobody else has the data.

**Do not do this without checking three things first:**
1. Your privacy policy permits aggregate analysis and publication of it.
2. The data is genuinely aggregate — no individual user is identifiable, no
   outlier is quotable back to a person.
3. You are comfortable that users would not feel surprised or exploited reading it.

Get that clearance before writing, not after. See `POSTHOG_ANALYTICS_GUIDE.md` and
the privacy posture notes. If in doubt, don't — the downside is a trust story, and
trust is the only asset this campaign is trying to build.

### Archetype 4 — the honest failure post

Works in r/SideProject, and occasionally in fitness subs where the failure is
technically interesting.

You have a genuinely good one: **the suggestion engine recommended 32.5 kg to
someone who could do 45.** The root cause was not the model — it was the RIR chip
censoring input at "5+", so the model was fed bad data. That is a real, specific,
non-flattering story about the gap between a correct algorithm and a wrong UI, and
that kind of post earns more goodwill than any feature announcement.

### Archetype 5 — asking permission

Message the mods of Tier A subs before your first post there. Describe the post,
disclose that you built the app, ask whether it's acceptable and in what form.

This is the most underrated move on this list. Cost is zero, the worst case is
"no", and a mod who has said yes is a mod who will not remove you.

---

## 4. Rules of engagement

**Account.** The single biggest determinant of whether your post survives. Automod
gates on account age, karma, and link ratio. A new account posting a link is removed
before a human sees it. Use an established personal account with genuine history, or
spend three to four weeks participating before posting anything promotional.

**Always disclose.** "I built this" in the post itself, every time. Undisclosed
promotion that gets discovered is unrecoverable; disclosed promotion that gets
removed is just a removed post.

**Never run alt accounts.** No sockpuppets, no friends upvoting, no "has anyone
tried Repster?" from a second account. This is the one failure mode with permanent
consequences, and these communities are unusually good at spotting it.

**Never cross-post the same content.** Identical text across subs is the strongest
spam signal there is. One sub at a time, spaced out, rewritten for each audience.

**Don't use the ad creative organically.** The rendered frames in
`generated/campaigns/technical-lifter/` read as advertising, because they are. An
organic post uses plain text and, at most, a raw screenshot.

**Let them ask for the link.** Where rules are ambiguous, post without a link and
put it in a comment if someone asks. Costs a few clicks, avoids most removals.

**Timing.** These communities skew US. Weekday mornings US Eastern are the
high-traffic window — worth planning around from a European timezone.

---

## 5. Sequencing

Realistic pacing. Compressing this is how it fails.

**Weeks 1–2 — reconnaissance and presence.**
Verify rules for every sub above. Comment substantively in Tier A and B. Zero
promotion, zero links. Note which recurring threads exist and which questions come
up repeatedly.

**Weeks 3–4 — Tier C and first contact.**
Post to r/SideProject and the beta-tester subs. Low stakes, real feedback, and it
seasons the account. Message r/weightroom and r/AdvancedFitness mods describing the
methodology post you want to write.

**Weeks 5–6 — first methodology post.**
One post, in whichever Tier A sub responded best. Rest-interval framing is the
strongest opener. Spend the day it goes up answering comments properly.

**Weeks 7–8 — read the result, then decide.**
If it landed, write the second one for a different sub with different framing. If it
was removed or ignored, the diagnosis is almost always account history or framing,
not the idea — fix the input rather than abandoning the channel.

Paid ads can run in parallel throughout, and should.

---

## 6. Attribution

Reddit organic is hard to measure: the App Store passes no referrer, so installs
from a Reddit post are invisible by default.

The clean fix ties into the CPP decision already flagged in `ad-kit.md`: **a Custom
Product Page has its own URL.** Use one CPP link exclusively in Reddit posts and
every install through it is attributable, with conversion reported in App Store
Connect. That single fact is a decent argument for building the CPP a little earlier
than the ad kit's sequencing suggests.

Interim option: point posts at a dedicated path on the existing GitHub Pages site
that redirects to the App Store, and count hits there.

---

## 7. Expectations

Set these honestly before spending eight weeks on it.

A **good** methodology post in r/weightroom is worth tens to low hundreds of
installs — not thousands. Organic Reddit is not a growth channel at your stage.

What it *is* worth: the people who arrive this way are the highest-intent users you
will ever get, they retain, and they tell other lifters. It also produces something
paid never does — direct technical argument with the exact audience you are
repositioning toward, which is free product research. Given that
`project_growth_retention` identifies post-install activation and retention as the
bottleneck rather than install volume, that trade is favourable.

**The failure mode to avoid** is treating this as a distribution channel, getting
impatient at the numbers, and posting something promotional in r/Fitness. That
converts a slow-but-positive channel into a banned account.

---

## 8. Before you post anything — checklist

- [ ] Read the sub's sidebar, full rules page, wiki, and pinned posts. Today.
- [ ] Search the sub for "app" and sort by new — see what gets removed and what survives.
- [ ] Confirm whether a weekly self-promo or feedback thread exists.
- [ ] Confirm the account clears age/karma gates.
- [ ] Confirm the post is useful with the last line deleted.
- [ ] Confirm every claim traces to the claim inventory in `ad-kit.md`.
- [ ] Confirm nothing references unshipped 1.4 work.
- [ ] Message mods if the sub is Tier A.
