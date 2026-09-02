# PARKED — feature-driven post drafts (wrong angle, 2026-08-31)

> Parked the day it was written: every post here sells the mechanism, and the
> mechanism is not what to lead with while the suggestion engine has open defects.
> Revisit after the engine program ships. Live drafts: `organic-post-drafts.md`.

# Organic post drafts — Reddit and X/Twitter

Written 2026-08-31. Companion to `marketing/campaigns/technical-lifter/reddit-plan.md`
(strategy, subreddit tiers, sequencing) and `ad-kit.md` (claim inventory).

These are drafts, not a publishing queue. Read §0 before posting any of them.

---

## 0. Before you post anything

**Every claim here traces to the claim inventory in `ad-kit.md`.** Nothing below
references supersets (built 2026-08-31, uncommitted, not in anyone's hands),
HealthKit (built, blocked on App ID capability + device QA), or anything else not
in the live build. Check what's actually shipped before adding to these.

**Verify the literature yourself before posting Reddit post #1.** The citations in
`LoadPrescriptionService.swift:14-15` (Willardson, Nuzzo/SBS, RTS, PCr resynthesis)
are the model's provenance, and post #1 states them in public under your name. Open
the actual papers and confirm each sentence says what you're claiming it says. The
top comment on that post will be someone who has read them. That is the best
possible outcome, and only if you're on solid ground.

**Free tier is 10 workouts, not 5.** Raised 2026-08-18. `docs/support.html` and
`docs/docs.html` still say 5 — fix those before any post mentions the number.

**Two currently-open defects are deliberately not in these drafts:**
- The RIR>=3 capability gate (suggests ~72% of real capacity on first exposure to a
  new exercise).
- Fixed rep targets cannot progress at all (`SUGGESTION_PROGRESSION_DESIGN.md` P2).

Both are excellent honest-failure content and both are still true of the shipped
app. Writing them up now advertises a live defect in the thing you're selling. Hold
them until the fixes ship, then post them as "here's what was wrong and here's the
fix" — that version is strictly better content anyway.

**Never run alts, never buy engagement, never post the same text twice.** Covered in
the reddit plan; it applies to X as well.

---

# Part 1 — Reddit

Ordered by what to post first, not by ambition. Post #4 is the safest place to start
and the only one that doesn't need account seasoning.

---

## R1 — Methodology post: rest intervals
**Target:** r/weightroom or r/AdvancedFitness. Message mods first.
**Prerequisite:** 3-4 weeks of genuine commenting on the account; literature verified.

> **Title:** What does cutting rest from 3:00 to 1:30 actually cost your next set?

Most of us treat rest as a rule of thumb — three minutes on compounds, ninety
seconds on accessories — and then quietly ignore it when the gym is busy. I wanted a
number instead of a vibe, so I spent a while trying to write rest into an explicit
model of what your next set is worth. Here's where I landed, including the parts I'm
not confident about.

**The frame: fatigue as a quantity that accumulates and decays.**

Each working set deposits some fatigue. Rest decays it exponentially. The fraction
still weighing on you when you start the next set is:

    remaining = e^(-rest / τ)

τ is the time constant. Plug in a few numbers with τ = 180s:

| Rest | Fatigue still carried |
|---|---|
| 60s | 72% |
| 90s | 61% |
| 120s | 51% |
| 180s | 37% |
| 300s | 19% |

So 3:00 → 1:30 isn't "a bit less recovered". You start the next set carrying about
1.65× the residual fatigue of that previous set. And it compounds — set 4 of 5 is
carrying decayed remnants of sets 1, 2 and 3, each decayed by its own rest interval,
not by an average.

**The part people get wrong: the cost isn't a fixed percentage.**

A set taken to RIR 4 and a set taken to failure do not deposit the same fatigue, so
they don't cost the same next set. Which means rest and proximity-to-failure can't
be reasoned about separately — the honest version is a two-variable question, and
most rest-interval advice collapses it to one.

**Where τ = 180 comes from, and why I don't fully trust it.**

It is not a physiological constant. Phosphocreatine resynthesis is much faster than
that; performance recovery lags metabolite recovery, and the rest-interval
literature consistently shows meaningful set-to-set decrement at 1-2 minutes that
mostly resolves by 3-5 on compounds. τ = 180 is a fit to that observed performance
curve, not to a mechanism.

It's also almost certainly wrong per exercise. A heavy squat triple and a lateral
raise should not share a time constant, and I have no principled way to derive one
per movement — so it's exposed as a per-exercise setting rather than pretending I
know.

**What I'd genuinely like to be argued with about:**

1. Is exponential decay the right shape at all, or does performance recovery have a
   plateau the exponential misses?
2. Should τ scale with the load used, the reps done, or the muscle mass involved?
   I've assumed the exercise, which is a proxy for all three and precise about none.
3. Everything above is about acute within-session fatigue. Between-session recovery
   is a different animal and I've deliberately not modelled it here.

**Disclosure:** I build an iOS lifting app (Repster) and the above is the model
behind its load suggestions, so I have an obvious interest in you finding it
convincing. The argument stands or falls on its own though — you don't need the app
for any of it, and I'd rather be told the shape is wrong than get downloads.

> **Note to self:** no link in the post. If someone asks, put it in a comment.

---

## R2 — Methodology post: what your e1RM should be anchored to
**Target:** r/powerlifting (check for a weekly thread first) or r/weightroom as your
second post, weeks after R1. Shorter, more arguable, lower stakes.

> **Title:** Your e1RM shouldn't be recalculated from your last session

Short argument, genuinely open question at the end.

If you compute an estimated 1RM from your most recent top set, one bad day rewrites
your entire baseline. You slept badly, you get a lower e1RM, and every downstream
number — target loads, progress charts, whether you think you're peaking — moves
with it. Then you have a good day and it moves back. Most of that movement is noise
being recorded as signal.

The alternative I've settled on: take the **peak** across a recency window of recent
sessions rather than the latest value. A bad session simply doesn't clear the
existing peak, so it changes nothing. A genuinely better session does.

The two things that makes you choose:

- **Window length.** Too short and you're back to reacting to noise. Too long and
  you're benching against a number you set six weeks and one illness ago. There is
  no correct answer here, only a preference about which error you'd rather make, so
  I made it a setting rather than a decision.
- **What's eligible.** Warmups have to be excluded or the whole thing is garbage —
  and "warmup" has to mean flagged-as-warmup, not "below some threshold", because
  the threshold is exactly the number you're trying to estimate.

Where I think this is weak: taking the peak means the estimate ratchets up and never
down, so a real detraining period reads as a fresh set of misses rather than as a
lower baseline. The window ageing out is the only mechanism that corrects it, which
is slow and indirect. If someone has a cleaner way to let a baseline fall honestly
without letting one bad Tuesday drag it, I'd like to hear it.

**Disclosure:** this is how the app I build handles it, so grain of salt.

---

## R3 — r/QuantifiedSelf: the model scoring itself
**Target:** r/QuantifiedSelf. Tier B, tool-tolerant, genuinely interested in
modelling. Underrated fit and much lower risk than Tier A.

> **Title:** I made my training tracker grade its own predictions, and the error was the interesting part

Standard self-tracking setup: log every set, get a model that predicts what you can
lift next. The bit I hadn't seen done is the obvious one — the model writes down
what it predicted before you lift, then compares it to what actually happened, per
exercise, and adjusts its own parameters based on how wrong it was.

Three things that fell out of it that I didn't expect:

**1. The error isn't uniform across exercises.** It's systematically different on
machines versus free weights, which in hindsight is obvious: a leg press has almost
no stability or technique variance, so the model's prediction is nearly the whole
story. A barbell squat has a bad day in it that no load model can see.

**2. Self-correction needs a floor or it chases noise.** If you let each session's
error move the parameters freely, one outlier session teaches the model something
false and it takes several sessions to unlearn it. Damping it is the entire
difference between "adapts" and "flails".

**3. Measuring your own error changes what you're willing to show the user.** Once
you know the confidence interval is wide on a given exercise, printing a single
confident number to two decimal places starts to feel like a lie. I still print one,
because "somewhere between 60 and 75kg, probably" is useless in a gym — but I'm no
longer comfortable with it, and I don't have a good answer.

Happy to go into the maths if anyone wants it.

**Disclosure:** this is from an iOS lifting app I build. No link unless someone asks
— the modelling is the point of the post.

---

## R4 — r/SideProject or r/iOSProgramming: the honest failure post
**Target:** r/SideProject (show-and-tell allowed) or r/iOSProgramming (feedback
threads only — check). **Start here.** Lowest risk, seasons the account, real
feedback. Both bugs below are fixed, so this doesn't advertise a live defect.

> **Title:** My app did the right maths and printed the wrong sentence, and I spent a day debugging the maths

Two bugs from the last month, both of which taught me the same lesson from opposite
directions.

**Bug one: the algorithm was fine.** A user reported that my lifting app suggested a
weirdly specific weight — 58.75kg — after a set that should have produced a clean
increment. I assumed a regression in the load model and went digging into the
prediction code. The model was correct. It had chosen to prescribe *nine reps* at
that weight, which was a sensible progression from what the user had just done. But
the card was printing the user's own configured rep range back at them, and the
chosen rep count sat in a diagnostics view nobody outside my simulator ever sees.

So the app said "58.75kg, 6-10 reps", which reads as random, instead of "58.75kg for
9 reps", which reads as a plan. Same number, same maths, entirely different product.
The fix was a display label.

**Bug two: my ranking system silently locked.** I have a feed of training insights —
ten rules that each look for something in your data and produce a card. Feed showed
the top three by an actionability weight. Users reported "I only ever see the same
three insights". They were right, and it wasn't a caching bug: once more than three
rules were eligible, the three with the highest fixed weights won *permanently*.
Every subsequent one was structurally unreachable. The system had no bug in it. It
was working exactly as designed, and the design was wrong.

The connective tissue: both bugs were invisible to tests, because in both cases the
code did what it said it did. Tests assert behaviour and both behaviours were
correct. What was wrong was what the user could perceive of that behaviour — and I
had no instrument pointed at that at all.

I've since added an on-device diagnostic panel that runs every rule against real
data and buckets them into shown / ranked out / silent, which answers "which of my
features can this user's data even produce" for one device. Across users it's still
unmeasurable, because I never log which rules were shown. That's next.

**Disclosure:** the app is Repster, iOS, I built it. Happy to answer anything about
the SwiftData or model-actor side of it — that has produced its own horror stories.

---

## R5 — Comment templates (highest ROI, essentially zero risk)

This is where most of the first 90 days should go. Search these subs for threads
asking the question, answer it completely, mention the app only if directly relevant
and always disclosed. Three reusable bodies — rewrite, don't paste:

**When someone asks "how do I autoregulate / what weight should I use today":**
> The thing that made this click for me was separating two questions that usually
> get merged. "What can I lift today" is a prediction — it depends on your recent
> best sets, how much you've already done in this session, and how long you rested.
> "What should I lift today" is a prescription — it depends on what you're trying to
> make happen over the next few weeks. Most percentage-based programmes answer the
> second and pretend it answers the first, which is why they feel wrong on your bad
> days and leave weight on the bar on your good ones. RPE/RIR-based autoregulation
> is the standard fix; the cost is that it needs you to be honest and reasonably
> calibrated about proximity to failure, which takes months to develop.

**When someone asks "does anyone actually track RIR / is it worth it":**
> It's worth it for one specific reason that isn't the obvious one: RIR is what lets
> a submaximal set tell you something about your maximum. 100kg × 5 @ RIR 4 and
> 100kg × 5 @ RIR 0 are the same row in most logs and enormously different facts.
> Without it you're either testing maxes (fatiguing, infrequent) or guessing. The
> catch is that self-reported RIR is badly calibrated in most people until they've
> actually taken sets to failure a few times to learn what zero feels like.

**When someone asks for an app that does RPE/RIR properly:**
> [Answer the question honestly, name several apps including competitors, and
> disclose your own in one clause: "— and full disclosure, I build one of these
> (Repster), so discount accordingly."] A comment that only names your own app reads
> as an ad no matter how it's phrased. One that names four and discloses yours reads
> as a person.

---

# Part 2 — X / Twitter

## Read this first

"Viral" is not a strategy you can execute; it's an outcome you can make slightly
more likely. What is actually true for an account your size:

- **Reach on X is almost entirely amplification.** A post with no existing audience
  goes nowhere on merit. The realistic goal is a post good enough that one account
  with reach quotes it. Everything below is written to be quotable.
- **The three formats that actually travel** for technical products: (1) a
  surprising specific number, (2) a short video where the thing visibly moves, (3) a
  self-implicating failure story. Feature announcements travel zero.
- **Don't buy engagement or run a second account.** Same rule as Reddit and the
  detection is better.
- **Post images/video natively.** Links in the post body suppress reach; put the
  App Store link in a reply.

---

## T1 — The counterintuitive one (best single-post hook)

> Set 2 asks for more weight than set 1. At fewer reps.
>
> Not a bug. Set 1 was 10 reps at 2 RIR. Set 2 is 6 at 2 RIR.
>
> Same effort target, different rep target, so the weight has to move — even though
> you're more tired than you were 3 minutes ago.
>
> Most logs can't tell you that. [screenshot]

Pair with the Smart Suggestions card crop. This is concept 01 from the ad kit, which
is the sharpest statement of the differentiator, rewritten to be a post rather than
an ad.

---

## T2 — The demo (best video candidate)

> Your rest timer is an input, not a stopwatch.
>
> [8s screen recording: timer at 2:57 → tap -30s → suggested load drops]
>
> Cut your rest, carry more fatigue into the next set, get a lower target. The app
> knows what set 3 cost you.

The most demo-able claim in the whole kit and the one that survives being watched on
mute. Worth doing properly: real device capture, no captions racing the footage,
first frame legible as a still.

---

## T3 — The self-implicating story (thread)

> A user told me my app's suggestion was "random". It said 58.75kg.
>
> I spent a day convinced the load model had regressed. It hadn't. 🧵

> 1/ The model had picked 58.75kg *for 9 reps* — a real progression from what they'd
> just done. Correct maths, defensible choice.

> 2/ The card printed their own configured rep range back at them. "58.75kg, 6-10
> reps." The chosen rep count sat in an admin diagnostics view nobody but me can
> open.

> 3/ So the app was saying "here's a weirdly precise number and no reason for it"
> when it meant "here's a plan". Identical behaviour, opposite product.

> 4/ Fix was a display label. Four tests. Half an hour, after a day of looking in
> the wrong place.

> 5/ Lesson I keep re-learning: my tests assert what the code does. Nothing I own
> asserts what the user can perceive of what the code does. That gap is where all my
> real bugs live.

Founder-failure threads are the most reliably shareable format available to you, and
this one is safe because it's fixed.

---

## T4 — The contrarian claim (quote-bait, use carefully)

> Percentage-based programming is lossy compression.
>
> "75% of your 1RM" throws away: what you did 3 minutes ago, how long you rested,
> whether today is a good day, and what you're actually trying to make the set do.
>
> It was the right call when the alternative was arithmetic in a notebook.

Deliberately arguable and the argument is one you can win in the replies. Do not
post this one unless you have half an hour to defend it — a contrarian post you
abandon reads as a drive-by.

---

## T5 — The trust post

> Every part of my app's load model has an off switch.
>
> Recency window, default RIR, per-exercise fatigue constant, and a toggle that
> turns the whole suggestion engine off and gives you a plain log.
>
> If I can't explain a number to you, you should be able to delete it.

Concept 05 from the ad kit, which is blocked as ad creative for want of a screenshot
— but works fine as text. Strongest trust claim you have, and it lands especially
well with the audience currently exhausted by opaque AI features.

**Blocked on the same capture as concept 05:** Settings → Smart Suggestions, dark
mode, 6.9" simulator, realistic database, saved to
`marketing/source/screenshots/prescription-settings.png`. Worth ten minutes.

---

## T6 — The aggregate-data post — NEEDS CLEARANCE FIRST

> I looked at [N] logged sets. The set-to-set rep drop-off is [X]% at 90s rest and
> [Y]% at 3 minutes.
>
> The literature predicts [Z]. Here's where real training data and the papers
> disagree. [chart]

This is the highest-ceiling post on either list, and nobody else can write it,
because nobody else has the data. It's also the one with a downside that isn't
"post flops" — it's "users feel surveilled".

**Three things to clear before writing a word of it** (from the reddit plan, §3
archetype 3): the privacy policy permits aggregate analysis and publication; the
data is genuinely aggregate with no individual identifiable or quotable; and you're
confident a user reading it would not feel exploited. Get that clearance first, not
after. If in doubt, don't — the asset this whole effort is building is trust.

Also: n≈200 users is small enough that the honest version of this post has wide
error bars, and stating them is what makes it credible rather than what weakens it.

---

# Part 3 — Attribution

App Store passes no referrer, so every install from either channel is invisible by
default. Two options, from the reddit plan §6:

1. **Custom Product Page.** Has its own URL; installs through it are attributable in
   App Store Connect. One CPP per channel — one for Reddit, one for X — and you can
   read the two channels separately. This is a real argument for building the CPP
   earlier than the ad kit's sequencing suggests, since it also unblocks Apple
   Search Ads on the technical angle.
2. **Interim:** a dedicated path on the GitHub Pages site that redirects to the App
   Store, and count hits. Free, works today, less precise.

Do at least option 2 before posting anything, or you will run eight weeks of this
and have no idea whether it worked.
