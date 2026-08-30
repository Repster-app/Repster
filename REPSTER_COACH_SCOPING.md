# Repster Coach — scoping

**Date:** 2026-08-29 · **Branch:** `NewMain` · **Status:** scoping. Nothing here is built or agreed.

The proposition: the app's "smart" behaviour is currently three unrelated features with three
names — Smart Suggestions (a wand inside a set row), Training Insights (a destination off Home),
and a parked category of coaching tiles. **Repster Coach** collapses them into one named thing
with a front door, fed by what the user logs and by the little it asks.

This doc answers four questions in order of how hard they are to reverse:

1. [Name and reference](#2-name-and-reference) — what things are called, and what stops being called what.
2. [Where it lives](#3-where-it-lives) — the IA, and how every existing screen changes.
3. [What we ask](#4-onboarding--what-we-ask-and-why) — the onboarding question set, why most of it was cut, and what replaces it.
4. [What is in the module](#5-the-module--feature-inventory) — the feature inventory. The most important section.

### Standing caveats

- **Not n=1.** Every percentage carried over from [SUGGESTION_OPEN_QUESTIONS.md](SUGGESTION_OPEN_QUESTIONS.md)
  comes from one lifter's backup. Repster has 200+ users. Structural claims about the code hold for
  everyone; behavioural ones are hypotheses and are marked *(n=1)*.
- **Notifications are a settled no**, and social is a settled no. Both constrain the design below and
  neither is revisited here.
- **Nothing in this doc is a commitment.** It is a menu with dependencies marked.

---

## 1. The bill

The rename is not free, and the price is worth stating before the design.

Today "Smart Suggestions" is an optional feature behind a toggle. Its live defects — the plateau
feedback loop, the RIR ≥ 3 capability gate, the §2.2 baseline over-reaction, the 32.5 kg
first-exposure undershoot — are contained inside a wand you can leave off.

Put it under the app's own name — wherever it lives — and those stop being feature defects and become
**"the coach is wrong."**

That moves [SUGGESTION_ENGINE_PROGRAM.md](SUGGESTION_ENGINE_PROGRAM.md) from *adjacent work that should
happen first* to *inside this project's scope*. Specifically Fix 1 (credit easy sets), Fix 3 (drop sets),
and a decision — not necessarily an implementation — on Fix 2 (progression).

**The single hardest constraint in this document:** the Coach cannot ship a card that says
*"your bench hasn't moved in seven sessions"* while the wand is the reason it hasn't moved.
See [§5.4 D1](#54-track--the-tiles) and [§7](#7-sequencing).

The upside is the mirror image. 1.4 is a large, unshipped, mostly invisible release. Coaching is
what makes the engine work visible — it is the release note the engine program doesn't have.

---

## 2. Name and reference

### 2.1 The names

| Level | Name | Used where |
|---|---|---|
| Product / marketing | **Repster Coach** | App Store, ASA creative, release notes, the positioning test |
| In-app | **Coach** | The Home hook, the destination title, section headers, settings. You are already in Repster |
| The descriptive half | **Insights** | A section inside Coach. Kept deliberately — see below |

**Insights survives, inside Coach.** It is tempting to put everything under one word, but
[TRAINING_INSIGHTS_V2_DESIGN.md](TRAINING_INSIGHTS_V2_DESIGN.md) §"The organising idea" locked a
distinction that is load-bearing:

- **Status / Insights** — arithmetic on the user's own data. Always renders, never gated, cannot be
  wrong. *Describing.*
- **Coach** — interpretation that names a next step. Gated, occasional, allowed to say nothing.
  *Prescribing.*

If everything is "Coach", you lose the ability to show a number that is *just a number*. A declining
chart under a Coach label reads as criticism; the same chart under Insights reads as a mirror. Keeping
both words makes a decision that already exists in the design visible in the navigation instead of
buried in a doc.

### 2.2 What each surface is called

| Surface | Today | Proposed |
|---|---|---|
| The in-workout strip | "Smart Suggestions · 2 ready" | **"Coach · 2 ready"** |
| The explainer sheet | (unbuilt) | **"Why this weight"** — keep, it is exactly the question |
| The tiles | (unbuilt, "coaching tiles") | No user-facing category noun. They are cards in Coach |
| Settings screen | "Smart Suggestions" (`PrescriptionSettingsView`) | **"Coach"**, with whatever the app has inferred or been told, editable in it |
| The old Home hook | `InsightsTeaserCardView` | The Coach line — see [§3.4](#34-screen-by-screen) |

**Resist inventing more nouns.** "Coach notes", "coach cards", "Coach Feed" all add vocabulary the
user has to learn. Cards in Coach are cards in Coach.

### 2.3 Terms retired

- **"Smart Suggestions"** — everywhere user-facing. Retained only in `HealthProfile`'s legacy field
  names (`prescriptionEnabled`, `prescriptionDefaultTargetReps`, …), which must not be renamed —
  see below.
- **"Training Insights"** as a *destination* — becomes a sub-tab.
- **"Findings"** — already internal-only; keep it that way.

### 2.4 Code naming — don't

`SuggestionEngine`, `LoadPrescriptionService`, `InsightRule`, `FatigueObservation`,
`prescription*` on `HealthProfile` — **leave all of it alone.**

A wholesale rename is churn with no user-visible value, it invalidates every file:line reference in
the thirty-odd markdown docs at repo root, and `HealthProfile`'s field names are explicitly annotated
*"legacy field names for migration compatibility"*. The cost is one glossary:

| User-facing term | Code |
|---|---|
| Coach (in-workout) | `LoadPrescriptionService`, `SuggestionEngine` |
| Coach (cards) | `InsightsService`, `InsightRule`, `InsightRecord` |
| Insights (charts, status) | `ChartDataService`, `StatsService`, status layer |
| Why this weight | new — `SuggestionExplanation*` |
| Goals & preferences | new fields on `HealthProfile` |

Put that table at the top of the code-side doc and the divergence is a five-line cost forever,
against a multi-day rename that breaks every cross-reference in the repo.

### 2.5 The promise problem

**Repster's coach can never initiate.** Notifications are a settled no. It only speaks when the user
opens the app. That is a hard constraint on copy:

- Never imply follow-up: no *"I'll check in on you"*, *"see you Thursday"*, *"don't forget"*.
- Never imply obligation: no streaks, no *"you missed"*, no scolding for a gap.
- Never make outcome claims: no *"this will build muscle"*, no *"you'll hit 200 kg by October"*
  without the hedge (see D7).
- Avoid anything diagnostic or medical. "Coach" is fine as a training-log term; injury, recovery
  and health advice are not, and App Review is the least of the reasons.

The coach is **an observant training partner who is there when you arrive**, not a program manager
who chases you. Every line of copy should survive being read by someone who has not opened the app
in three weeks.

---

## 3. Where it lives

### 3.1 Today's IA — verified

`TabView` in [ContentView.swift:185](Repster/App/ContentView.swift:185):

```
[ Home ]  [ Calendar ]  ( FAB )  [ Charts ]  [ Settings ]
```

Four tabs plus a centre FAB overlay. **There is no Insights tab** — Insights is a hook card on Home
that pushes a destination. `ChartsTabView` internally has its own sub-tabs (Breakdown / Workouts /
Exercises).

**And templates have no home at all.** `TemplateListSheet` (1,074 lines) is presented from exactly one
place: the Start Workout sheet's "Use Template" row
([StartWorkoutSheet.swift:111](Repster/Features/Home/Views/StartWorkoutSheet.swift:111)). There is no
other entry point anywhere in the app. **You cannot look at, edit or plan your training without first
committing to start a workout.** This matters more than it looks — see [§3.3](#33-the-recommendation)
and [§5.1](#51-plan--before-the-session).

### 3.2 The options, honestly

**Charts stays.** Ruled out.

| Option | For | Against |
|---|---|---|
| **A · Coach replaces Settings**, Settings moves to a gear in Home's nav bar | Settings is a low-frequency destination holding a permanent slot. A gear in the nav bar is the standard iOS pattern, not a compromise. Fully reversible | Early-life users *do* visit Settings often — units, rest timer, suggestions toggle — and they are the least oriented |
| **B · Coach is not a tab.** Home becomes the plan surface; a Coach destination is pushed from it | Home is already the pre-workout moment. Cheapest, reversible, and does not force the tab decision before the module has earned one | The deep surface sits one tap down — exactly where Insights sits today, and Insights' problem was that people stopped tapping |
| **C · Five tabs** | — | Six targets with the FAB |

### 3.3 The recommendation

**B now. A when the module earns it — and the trigger is templates.**

The reason Insights failed as a one-tap-down destination was that the hook was usually empty
("Findings from your training data / Unlocks as you log workouts"). The Coach hook is different in
kind: it is always-on arithmetic — *"Legs was 16 days ago; your usual gap is 5"* — which renders on
day one and every day after. A hook that always says something does not train people to stop tapping.

So Coach v1 is:

- **On Home** — one always-on line, and "Today's session" when there is one.
- **One tap down** — the Coach destination: the cards, the performance-vs-expected rollup, and Insights.

**What flips it to a tab:** the moment the coach owns *planning*. A reading surface can live one tap
down. A surface where you build, adjust and schedule your training cannot — and if templates become
the engine behind planned workouts ([§5.1](#51-plan--before-the-session)), the coach stops being a
reading surface. That is also the fix for templates having no home.

**So the tab question and the template question are the same question**, and neither has to be
answered in v1.

### 3.4 Screen by screen

| Screen | Today | After |
|---|---|---|
| **Home** | `InsightsTeaserCardView` → Insights destination. `MonthlyStatsCardView`. Training status. Free-workout counter | Teaser becomes **the Coach line** — one always-on arithmetic sentence, tapping through to the Coach destination. Nothing else moves |
| **Start Workout sheet** | Empty / Copy Previous / Use Template — on a fresh install two of three are dead | Gains **"Today's session"** at the top when the coach has one. `Use Template` stops being dead once a split is seeded |
| **Active workout** | Suggestion strips, read-only | Strips relabelled **Coach**; tappable → *Why this weight*. Optional write-back into the set row |
| **Summary sheet** | Title, notes, effort 1–10, exercise recap, per-exercise suggestion feedback, save-as-template, discard | **Less, not more** — see [§5.3](#53-review--how-that-went) |
| **Workout history detail** | `CalendarWorkoutDetailView`, `WorkoutDetailFromHomeView` | Gains the performance-vs-expected read. **The primary home for it** |
| **Charts tab** | Unchanged | Unchanged |
| **Insights destination** | Pushed from Home | Becomes a section of the Coach destination |
| **Templates** | Two modals deep, no home | Prerequisite work — [§5.1 P0](#51-plan--before-the-session) |
| **Settings → Smart Suggestions** | `PrescriptionSettingsView` | Renamed **Coach**; gains whatever preferences [§4](#4-onboarding--what-we-ask-and-why) settles on |

### 3.5 What an upgrading user sees

200+ people already have this app. Nothing in Option B moves a tab under them, which is most of the
argument for it. What does change: a feature toggle under a new name, a new line on Home, and — for
anyone whose intent the coach wants to know — a confirmation card, not a form. See
[§4.5](#45-existing-users-and-new-ones-take-the-same-path).

---

## 4. Onboarding — what we ask and why

### 4.0 The challenge, and the correction

The first version of this section proposed six questions and claimed each one unlocked something.
Under scrutiny that does not hold, and the objection is right: **stated intent is good for seeding
defaults and weak for licensing judgment.**

Audit each question honestly against what it was supposed to buy:

| What it was for | What the answer actually is | Better source |
|---|---|---|
| **Goal** → licenses the stance-gated cards | An aspiration picked in fifteen seconds by someone who has not used the app yet. Most will pick "muscle" — and a card that corrects your training based on a chip you tapped before your first set is on very thin ice | **Rep distribution after ~3 sessions.** Observed, specific, and unarguably theirs |
| **Frequency** → cold start, week shape | What they *hope* to do. "You said 4 days and you've done 2" is the app holding someone to an optimistic guess and calling it coaching | **Workout dates.** Weak for ~3 weeks, then better than any answer they could give |
| **Experience** → progression path | Self-assessment, and lifters are famously unreliable at it. It would decide real engine behaviour off a guess about self-image | **e1RM trend slope.** A beginner's curve is unmistakable and needs no honesty |
| **RIR tracking** → whether "cleared" can depend on RIR | Half of users will not know the term. Saying yes is not doing it | **`rir_entered` fill rate**, already instrumented and already a shipped property |
| **Equipment** → increments | **A fact.** What plates exist in your gym is not an aspiration and does not drift | Inferrable from logged weights *eventually* — but the first suggestion needs it before any weight is logged |
| **Split** → seeds templates | Not data at all. It is the payoff that fills an empty app | — |

**Two survive.** Equipment, because it is a fact that is needed before any behaviour exists; and the
split, because it is not a question — it is the thing that makes the app non-empty.

### 4.1 The principle

> **Ask only what behaviour cannot tell us, or what is needed before behaviour exists.
> Infer everything else, then confirm it.**

The stance unlock does not need a questionnaire. **Observed pattern is stronger evidence than stated
intent anyway.** "Your last 200 sets are 8–12" is a fact about the user; it needs no doctrine and no
declaration. The app names the pattern back and measures deviation from it.

Where the app needs to know whether a pattern is *wanted* rather than drifted into, it asks **then** —
informed, specific, and answerable with a yes:

> *"You've trained 3 days a week for the last six weeks. Is that the plan, or are you aiming for more?"*

That is a different act from a form. It is asked once the app has a hypothesis, it can be dismissed,
and it is right most of the time — so the common case is one tap.

### 4.2 What onboarding actually becomes

Onboarding gets **shorter**, not longer. That also removes the activation risk the first draft carried.

```
Welcome  →  Where do you train?  →  Pick a split  →  "Here's your first session"
                                                              ↓
                                     log one set  →  set 2 arrives with a load on it
```

**Q1 · Where do you train?** — `commercial gym` · `home barbell` · `dumbbells / minimal`
Seeds `Exercise.weightIncrement`. Same-session payoff: the first suggestion rounds to plates you
actually own. Default `commercial gym` (2.5 kg, today's behaviour). Addresses §2.4, the light-load
rounding staircase (−8.3% steps at 42.5 kg against −3.3% at 100 kg), which is aimed squarely at new
users.

**Q2 · Pick a split** — `Push/Pull/Legs` · `Upper/Lower` · `Full Body` · `I'll build my own`
Seeds real `WorkoutTemplate` rows. This is the payoff: the onboarding review found five empty states
and three dead paths on a fresh install because `SeedService` seeds only the exercise library and no
templates ship. Default: none seeded — today's behaviour.

**Dropped:** units (`UnitPreference.fromCurrentLocale()` already gets it right — confirm silently) and
bodyweight (nothing reads it; `LoadPrescriptionService` never touches body weight).

Net: three screens today → three screens, of which two now produce something the app uses. Today,
none of them do.

The last two steps are direction D unchanged, with its open calls intact: the tutorial must not cost a
free workout (`recordCompletedWorkoutIfNeeded` is currently unconditional), the default lifts must be
weighted so `isEligibleForCapacity` passes, and `WorkoutStartSource` needs a `guidedFirstSet` case or
none of it is visible in the funnel. Import moves out of the linear flow and becomes a card (direction E).

### 4.3 Asked later, in context

Three questions are valuable at the moment they matter, where the answer is concrete rather than
abstract:

- **"Roughly what do you lift on this?"** — at **first exposure to an exercise**, skippable. The direct
  fix for §2.3, the largest observed error in the engine: 32.5 kg suggested against a real ~45 kg
  capacity. The floor cannot fire on set 1 and the baseline needs history; one optional number removes
  both problems. Asking this in onboarding across 171 exercises is absurd; asking it once, in context,
  is natural.
- **"Is this the plan?"** — the frequency confirmation above, once there is a pattern to confirm.
- **"Still training for size?"** — the goal confirmation, once there is a rep distribution to name.

### 4.4 What this costs

Being honest about what the rethink gives up:

- **Nothing licenses stance for ~3 sessions.** A brand-new user gets a coach that describes and
  prescribes weight, but does not comment on their training shape. That is correct — it has nothing
  to comment on — but it means the Coach's most distinctive cards are invisible at exactly the moment
  a new install is deciding whether to stay.
- **The population data arrives slower**, and by inference rather than declaration. Against that: the
  inferred version is *better data*. "62% of users train in an 8–12 band" beats "62% said they train
  for size".
- **The confirmation prompts need somewhere to live** and a rule about how often they may fire. They
  are cards in Coach subject to the existing refire intervals, not modals.

### 4.5 Existing users and new ones take the same path

This is the quiet win. In the first draft, inference-then-confirmation was a backfill hack for the
200+ users who would never see the new onboarding. Under the corrected principle **it is the primary
mechanism for everybody** — new users simply reach it after three sessions instead of immediately.

One mechanism, not two. Everything computes from `WorkoutSet`, which every user has always had.

---

## 5. The module — feature inventory

### 5.0 How this is organised

Coaching in a fitness app has a natural loop, and Repster already owns all three moments:

| Moment | Surface that exists today |
|---|---|
| **Plan** — what should I do | Home, Start Workout sheet |
| **Do** — what should I lift right now | Set rows, suggestion strips |
| **Review** — how did that go | Summary sheet on Finish |

Plus two layers underneath: **Track** (the cards that watch trends across sessions) and **Insights**
(the descriptive mirror), and the **Engine** they all stand on.

Every item is marked:

- **Coverage** — *All* (computes from `WorkoutSet`, works for every user) or *Wand* (needs
  `FatigueObservation` / `FatigueLearningSetAudit`, so blank for anyone not using suggestions).
- **Stance** — *Safe* (arithmetic on the user's data), *Intent* (needs Q1/Q2/Q3 to be honest),
  *Doctrine* (asserts a training opinion regardless).
- **Size** — XS/S/M/L, consistent with [FEATURE_SCOPING_BRIEF.md](FEATURE_SCOPING_BRIEF.md).

**The coverage rule for v1: nothing that is *Wand*-only may be a headline surface.** C4 of the
implementation plan spells out why — audits skip sets with no RIR, so the users with the least data
get the least coaching. That is precisely backwards for a tab named after the app.

---

### 5.1 Plan — before the session

**Templates are the engine, not `Program`.** A planned workout is a template plus a date and an
intention. The dormant `Program` / `ProgramExercise` / `PlannedWorkout` / `PlannedSet` models are a
heavier, separate abstraction written before the current engine existed; building on them means
running a second concept alongside templates that does the same job, and keeping both correct forever.

That decision has a prerequisite, and it is bigger than any single card in this document.

| ID | Feature | What it does | Coverage | Stance | Size | Needs |
|---|---|---|---|---|---|---|
| **P0** | **Template surface rework** | Give templates a home, a browsable list, and an editing experience good enough to be the thing the coach proposes against | All | Safe | **M–L** | See below. **Prerequisite for P2 and P5** |
| **P1** | **Today** | "Legs is your freshest group — last trained 16 days ago, your usual gap is 5." States facts, offers, does not instruct | All | Safe | **S** | Workout dates + `primaryMuscle`. Nothing new |
| **P2** | **Today's session** | Proposes a template for today — chosen by what is freshest, ordered so the lift that costs most goes first — and lets you adjust it before starting | All | Safe | **M** | P0, plus a write path |
| **P3** | **Seeded templates** | The split from Q2, materialised as real `WorkoutTemplate` rows | All | Safe | **S** | Content work, not engineering |
| **P4** | **Week shape** | "You've trained twice this week; legs hasn't come round." Against the user's *observed* cadence, not a stated one | All | Safe | **S** | ~3 weeks of history |
| **P5** | **Forward schedule** | Templates with dates attached — a week laid out, adjustable | All | Intent | **M** | P0. Reframed, see below |

**On P0.** Today `TemplateListSheet` is 1,074 lines reachable from one place: Start Workout → "Use
Template". There is no way to browse, build or adjust a plan without starting a workout. If templates
become the planning substrate, that is disqualifying — the coach would be proposing against an object
the user cannot comfortably see or edit. P0 is: a home for templates (which is the same surface the
Coach tab would eventually be), a better list and card treatment, and an editing flow that survives
being used to *plan* rather than to *save what I just did*.

**On P5, reframed.** In the first draft this was a periodisation engine and marked *doctrine* and **L**.
Built on templates it is much smaller and much safer: a planned workout is a template with a date.
The app is not inventing sets and reps for a training block — it is placing the user's own sessions on
a calendar and adjusting loads through the engine that already exists. That is *intent*, not doctrine,
and **M**, not **L**.

The genuine periodisation version — auto-regulated blocks, deloads, progression models across weeks —
stays out. Note the caution: the coach cannot send notifications, so a schedule it makes is one nobody
is reminded of.

**The adjustability question, which must be answered before P2 or P5.** When the coach proposes a
session and the user changes it, what does the change stick to?

1. **This session only** — simplest, and the plan never learns.
2. **The template** — the plan improves, but a one-off substitution silently rewrites your programme.
3. **Ask, once** — "keep this change for next time?" Correct, and it is a decision point in a flow
   that should be fast.

Recommendation: (1) by default with (3) offered on structural changes — a swapped or added exercise —
and never on a weight change, which is what the engine is for.

---

### 5.2 Do — inside the workout

This is Smart Suggestions, renamed and finished.

| ID | Feature | What it does | Coverage | Stance | Size | Status |
|---|---|---|---|---|---|---|
| **D1** | **The strips** | Per-set weight and rep suggestion | Wand | Safe | — | **Ships today.** Relabel only |
| **D2** | **Why this weight** | Tap a strip → where the number came from, in a lifter's language | Wand | Safe | **M** | Fully mocked — [artifact](https://claude.ai/code/artifact/1e9ccaa9-a0c4-47e7-974c-82000444d304), 24 screens, three directions. Needs a direction picked |
| **D3** | **Write-back** | "Put 57.5 kg in set 3" from the explainer | Wand | Safe | **S** | New. The suggestions module is read-only today. **Shared with C3/C4 of the explainer** |
| **D4** | **Tune the target** | Rep range, target effort and weight increment per exercise, edited in place | All | Safe | **S** | Overlaps Exercise Settings, which already owns the increment picker. This is where Q1/Q4 become editable per lift |
| **D5** | **Probe mode** | First time on an exercise, step up 15–25% per set instead of guessing low | All | Safe | **M** | §2.3. The largest observed error in the engine. Pairs with the in-context question in [§4.4](#44-asked-later-in-context--not-at-onboarding) |
| **D6** | **Confidence** | "How sure are we" — a grade, or a band on the number itself | Wand | Safe | **S** | Mocked five ways in the explainer artifact. The *weakest-link* variant naming the `5+` truncation also discharges the undisclosed-cap debt in §5 of the open questions |
| **D7** | **Alternatives** | "Heavier: 65 × 5 · Lighter: 57.5 × 9", with what each costs you | Wand | Intent | **M** | Needs `repRangeCandidates` — the only part of the explainer needing engine work |
| **D8** | **Rest coaching** | The rest timer already exists; `restSweetSpot` already fires as a rule. Connecting them is the coach speaking at the one moment the user is idle and looking at the phone | All | Safe | **S** | Underrated. The rest screen is the most attention-rich, least-used surface in the app |

---

### 5.3 Review — "how that went"

**The tone rule comes first, because it decides everything else:**

> **The subject of the sentence is the model, not the lifter.**

| Never | Instead |
|---|---|
| "You came in under on bench." | "The app expected 62.5 on bench — you did 60, so it's eased off." |
| "Two lifts beat expectations, one underperformed." | "Bench and rows went better than planned for. The app has adjusted up." |
| "You missed your target." | "That target was the app's guess, and it was high." |

The attribution is deliberately asymmetric: **when actual is below expected, the app was wrong; when
actual is above expected, the lifter was strong.** That is not spin. The app is the thing making a
claim, and a missed prediction genuinely is the model's error — the whole point of
`FatigueLearningSetAudit` is that the model learns from the gap. Copy that says otherwise misdescribes
what the system is doing.

This is the same trap COACHING_TILES already flagged for the Model check tile: a table saying the model
was wrong invites *"so why trust it"*. The answer is that it learns — so the copy has to be about
learning, every time, not just when it is convenient.

**Where it lives — more than one place, deliberately.**

| ID | Home | What it carries | Why there |
|---|---|---|---|
| **R1** | **Workout history detail** — `CalendarWorkoutDetailView`, `WorkoutDetailFromHomeView` | Per-session: what the app expected, what happened, what it changed | **The primary home.** Retrospective and low-stakes — you are browsing your own history days later, not being handed a verdict while you pack your bag |
| **R2** | **Coach destination** | The rollup across sessions: "over the last month the app has run about 4% light on your pressing" | This is model transparency, not grading. It belongs with the rest of the coach's account of itself |
| **R3** | **Exercise detail / history** | Per-lift: expected vs actual over time, alongside the e1RM chart already there | The natural place to ask "how is bench going" |
| **R4** | **Summary sheet** | **At most one line, positive-only, or nothing at all** | See below |
| **R5** | **Share card** | Fed by the review rather than raw stats. "3 PRs" travels; "12,400 kg" does not | Marketing, and it is the one place a good session should be loud |

**On the summary sheet.** The instinct to cut it is right, and the count backs it up: it currently asks
for a title, notes, effort out of ten, and per-exercise suggestion feedback, and offers save-as-template
and discard — **six things at the moment someone wants to leave the gym.** Adding a performance verdict
to that is the worst possible placement for it: the user is tired, they have just finished, and it is
the one moment where "how did that go" cannot help but read as a grade.

**Slimming it is a separate workstream** and should stay one. But it has a dependency worth recording
before anyone starts, because both candidates for the chop are read by something:

- `perceivedEffort` (effort 1–10) has exactly one reader in the codebase —
  `InsightRules+Readiness` — which is `deloadReadiness`. Cut the question and that rule loses its input.
- The per-exercise suggestion feedback feeds the fatigue taper. Cut it and the learning loop loses a signal.

Neither is a reason to keep them. Both are a reason to know what breaks first.

---

### 5.4 Track — the tiles

The eight from [COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md), re-scored against
**observed** pattern rather than stated intent. Note how many move out of *Doctrine* once the app
measures a user against their own history — no questionnaire required, but ~3 sessions of data before
they can fire.

| ID | Tile | Coverage | Stance (as doctrine) | Stance (vs own pattern) | Size | Blocker |
|---|---|---|---|---|---|---|
| **T1** | **Session order** — "you squat fourth and it costs you most" | All | Safe | Safe | **S** | None. **Build first** |
| **T2** | **Stalled** — flat weight with reps rising underneath | All | Safe | Safe | **M** | **Fix 2.** See below |
| **T3** | **Frequency** — "chest gets 16 sets, all in one day, everything else across two or three" | All | Doctrine | Safe — it states the user's own distribution | **S** | ~3 weeks of history |
| **T4** | **Rep mix** — "84% of your sets are 8–12" | All | Doctrine | Safe — states the concentration, stops there | **S** | ~60 days of sets |
| **T5** | **Fatigue cost** — which lift takes most out of you | Wand | Safe | Safe | **S** | Must gate on `source` and `hasAuditHistory` — ranking *default* rates shows the model's priors dressed as fact |
| **T6** | **On pace** — "200 kg around mid-October" | All | Doctrine | Intent — needs a goal the user *confirmed*, not one they were asked for at install | **S** | A hedge and a short window, or it is the most disappointing card in the app |
| **T7** | **Balance** — push : pull | All | Doctrine | Doctrine | **M** | A movement-pattern taxonomy that does not exist on `Exercise`, **plus** stance. This one stays an opinion however it is framed |
| **T8** | **Deload readiness** | Wand | Safe | Safe | — | **Ships today**. Inherits the 21-day refire interval and the never-say-take-a-deload-week rule |
| **T9** | **Pattern check** *(new)* | All | Safe | Safe | **S** | "You've trained 3 days a week for six weeks and mostly in the 8–12 band. Is that the plan?" — the confirmation prompt from [§4.1](#41-the-principle), as a card |

**T2 is the trap.** §1 of the open-questions doc shows the plateau is a feedback loop the app closes:
the card says 8 reps, so the lifter does 8, so capacity never moves, so the card says 8 reps. Shipping
a tile that says "your bench is stalled" while the wand is what is holding it flat means **the app
diagnosing the user for its own defect.** T2 ships after Fix 2 or not at all.

**T9 is the most important card here, and it is not really a card — it is the mechanism from
[§4.1](#41-the-principle) wearing a card's clothes.** It is how the app acquires intent without a
questionnaire: it names a pattern it has observed and asks whether that pattern is wanted. It is
right most of the time, so the common case is one tap; when it is wrong, the correction is worth more
than any answer given at install. Every *Intent*-stance item in this document is downstream of it.

---

### 5.5 Insights — the describing layer

Unchanged in substance. Status card, muscle panel, monthly stats and the four reworked chart kinds
become a section of the Coach destination; the Charts tab stays exactly where it is.

One thing this move should fix while it is open:
- **Findings history** (§13.2) — records are deleted when a finding stops holding, so "your squat is
  up 6%" appears once and vanishes. Under a Coach brand that is worse than untidy: **a coach with no
  memory of what it told you is a fact generator.** See [§5.7 S3](#57-substrate).

---

### 5.6 Engine — invisible, and now in scope

Everything here is from [SUGGESTION_ENGINE_PROGRAM.md](SUGGESTION_ENGINE_PROGRAM.md) and
[SUGGESTION_OPEN_QUESTIONS.md](SUGGESTION_OPEN_QUESTIONS.md). It is in this inventory because
[§1](#1-the-bill) makes it so.

| ID | Fix | Why the Coach needs it | Size |
|---|---|---|---|
| **E1** | **Credit easy sets** (RIR ≥ 3 as a lower bound) | Telling the app a set was easy currently can only move the number *down*. Under a Coach label that is indefensible | **S** |
| **E2** | **Drop sets don't crater capacity** | One tagged set replaces the capacity estimate outright — a 38% phantom drop | **S** |
| **E3** | **Progression / Fix 2** | The plateau. Blocks T2, shapes P2, and is the difference between a predictor and a coach | **M–L** |
| **E4** | **Baseline over-reaction** (§2.2) | Peak-of-3-workouts means one 12-rep set makes the app ask for the heaviest weight yet on a bad day. Live now, in no other doc | **S** |
| **E5** | **Light-load rounding** (§2.4) | −8.3% steps at 42.5 kg vs −3.3% at 100 kg. Aimed at new users; Q4 seeds the fix | **S** |
| **E6** | **Adherence metric** | Built in epoch-2, unreleased. **Wants shipping a release ahead of any engine change** or there is no before-picture. It is also the Coach's ledger — see S3 | — |

**The thesis worth restating**, because the rename depends on it: stages 1–3 of the engine are a
*prediction* system. A coach *prescribes*. E3 is the only item that closes that gap, which is why it
is the one real project in the engine list.

---

### 5.7 Substrate

Cross-cutting work that several features need and none of them owns.

| ID | Item | Needed by | Size |
|---|---|---|---|
| **S1** | **Inference + confirmation** — derive goal, cadence, experience and RIR habit from `WorkoutSet`; a confirmation card that stores the answer on `HealthProfile`; rep-range fields on `Exercise` | T6, T9, P2, D4, E3 — and it is the only source of intent in the design | **M** |
| **S2** | **Coach-mark overlay** — a two-step anchored, dimming overlay | Onboarding direction D *and* any in-workout coaching. **No `.overlay(` in `ActiveWorkoutView` is anything but a border stroke today** — this exists nowhere and is most of D's build | **M** |
| **S3** | **The coach ledger** — what it said, whether you did it, what happened | R1, R2, T2, T9, and the adherence metric (E6). Same table, two uses | **S** |
| **S4** | **Write path into set rows / new workouts** | D3, P2 | **S** |
| **S5** | ~~Backfill for existing users~~ | **Folded into S1.** New and existing users take the same path — see [§4.5](#45-existing-users-and-new-ones-take-the-same-path) | — |
| **S6** | **Size the audit table** | C2 is still open — nobody knows how large `FatigueLearningSetAudit` grows, and it is the substrate under R1 and T5 | **XS** |
| **S7** | **Template surface** — P0 in [§5.1](#51-plan--before-the-session) | P2, P5, and the tab decision in [§3.3](#33-the-recommendation) | **M–L** |

---

### 5.8 What is *not* in the Coach

Naming the boundary is part of the scope.

- **Notifications / re-engagement** — settled no. A full implementation was built and rolled back on
  2026-08-09.
- **Social anything** — settled no. Feeds, following, comparison, sharing to other users.
- **Nutrition, sleep, bodyweight programming, injury or rehab advice** — out. Health claims, and none
  of it is in the data model.
- **Form checking / video** — out.
- **Exercise instruction content** — tentative on the roadmap, but it is a content project, not a
  coaching one. Keep separate.
- **Full periodisation (P5)** — deferred, not rejected. See the warning in [§5.1](#51-plan--before-the-session).

---

## 6. The two gates, applied

[COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md) names two gates. Under a Coach brand
both get sharper.

**Coverage.** A Coach surface that is half-blank for non-wand users reproduces exactly the failure
Insights v2 exists to fix — "a surface that is blank by design reads as broken." So: **no *Wand*-coverage
item may be a headline surface in v1.** By the marks in [§5](#5-the-module--feature-inventory) that
leaves P1, P2, P3, P4, R1, R3, T1, T2, T3, T4, T6, T9, D4, D5 and D8, all computing from `WorkoutSet`.

**Stance.** Resolved without a questionnaire and without doctrine. The rule:

> The app never asserts what is good training. It names the user's own pattern, and asks before it
> treats that pattern as a goal.

Two consequences. **T7 (push:pull) does not survive it** — "most programmes keep these even" is doctrine
however it is framed, so it either ships purely descriptive ("1.9:1 over the last 30 days", no
recommendation) or not at all. And **every stance-gated card needs history before it can speak**, which
is a cold-start cost the first draft avoided by asking. Insights v2 §8 already has the rule for that
period: state what you *are* showing, never what you can't.

---

## 7. Sequencing

Dependencies, not dates.

**Wave 0 — cheap, unblocking, no user-visible change**
S6 (size the audit table) · E6 (ship adherence a release ahead, so there is a before-picture) ·
rewrite the GROWTH_MEASUREMENT funnel against the real `OnboardingStep` enum.

**Wave 1 — the engine bill**
E1 + E2 together, one release, one recalibration. E4 alongside if it holds. This is [§1](#1-the-bill)
being paid, and it is the precondition for putting the app's name on the output.

**Wave 2 — the empty install**
Q1 + Q2 · P3 (seeded templates) · the D-flow first set · D5 (probe mode) and the in-context
"what do you lift on this?" question. No rename yet, no new surfaces. This wave is aimed entirely at
activation.

**Wave 3 — the module appears**
The rename in full · the Coach line on Home · the Coach destination · P1 · T1 · R1 · D2 (a direction
picked). First release where "Repster Coach" is a thing a user can point at.

**Wave 4 — inference and the cards that need it**
The inference-then-confirm mechanic ([§4.1](#41-the-principle)) · T3 · T4 · T6 · T9 · P4 · R2 · R3 · D4.

**Wave 5 — planning**
P0 (template rework) · P2 · then the tab decision, which P0 forces
([§3.3](#33-the-recommendation)) · P5 if wanted.

**Wave 6 — the real project**
E3 (progression), and T2 behind it.

**Later / maybe never** — T7 (push:pull), D7 (alternatives), genuine periodisation.

---

## 8. Decisions

Answered ones first, then what is still open — in plain language this time, because the first draft
asked several of these in shorthand that only made sense next to the tables.

### Settled

| # | Question | Answer |
|---|---|---|
| 1 | Does Coach take the Charts slot? | **No.** Charts stays. Coach is not a tab in v1 — Home carries the hook, a destination carries the rest. If it earns a tab later, Settings is the slot to give up, not Charts ([§3.3](#33-the-recommendation)) |
| 2 | Does this change what's paid? | **No.** Coach is free, like Insights. The subscription model is not part of this work. *Cheap insurance for a future change:* keep every Coach surface behind one service boundary rather than scattering the logic, so a later entitlement check has exactly one place to live. That costs nothing now and is expensive to retrofit |
| 3 | The onboarding question set | **Cut to two** — where you train, and pick a split. Everything else is inferred and then confirmed ([§4](#4-onboarding--what-we-ask-and-why)) |
| 7 | Staged rename or one release? | **Full rework, one release.** No period of mixed vocabulary |

### Open

**A · When the coach suggests a session, is it one session at a time, or a week planned ahead?**
One session ("here's a good session for today, adjust it and go") is smaller, needs no calendar, and
carries no obligation. A planned week is more useful to someone following a programme, but the coach
cannot send reminders, so a plan nobody is nudged about may just be a list that goes stale. *Leaning:
one session first.*

**B · When someone taps a suggestion to ask "why this weight", what do they get?**
Three directions are fully mocked in the [Why This Weight artifact](https://claude.ai/code/artifact/1e9ccaa9-a0c4-47e7-974c-82000444d304):

- **Show your work** — the full chain, step by step: your recent best → how today is going → fatigue
  so far → priced for your target. Longest read; the "do I trust this thing" answer you open once.
- **The dials** — a compact dashboard of the same factors with a spent/remaining bar. Readable in two
  seconds with a bar racked, but it never shows where the top number came from.
- **What if** — a tool where you change the reps or the effort and watch the weight move. Answers
  *"should I do this"* rather than *"how was this computed"*. **Needs the ability to write a number
  into a set row, which does not exist today.**

**C · Does a card state the facts and let you decide, or does it tell you what to do?**
Both registers are mocked side by side in the tiles prototype:

- *States:* "Legs is your freshest group. Last legs session 16 days ago, your usual gap is 5 days.
  [Start a legs session]"
- *Tells:* "Train legs today — 4 sets of squats to start. [Load this session]"

The second is more useful and more of a commitment: it needs the write path, and it is the register
that makes the app responsible for the recommendation. *Leaning: states, for v1.*

**D · When the coach proposes a session and you change it, what does the change stick to?**
This session only, the template, or ask once. See [§5.1](#51-plan--before-the-session).

**E · Where is the primary home for performance-vs-expected?**
History detail, the Coach destination, or exercise detail — all three are defensible and they carry
different amounts. See [§5.3](#53-review--how-that-went).

**F · How big is P0?** The template rework is the largest single item here and it is not really a
coaching feature. It may deserve its own scoping pass before it is committed to as a prerequisite.

---

## 9. What would make this wrong

- **If activation gets worse after Wave 2**, the two remaining questions are the suspect. The funnel
  measures per step, so this is falsifiable within one release — provided §2 of GROWTH_MEASUREMENT is
  fixed first.
- **If confirmation prompts are ignored or dismissed**, the whole intent model fails quietly and every
  *Intent*-stance card stays stuck. Instrument the confirm/dismiss rate from day one; it is the single
  metric this design stands on.
- **If observed patterns cluster hard** — say most users sit in one rep band anyway — then intent buys
  much less differentiation than assumed and several Wave 4 cards collapse into one default.
- **If the audit table is large** (S6), R1 and T5 need a retention policy before they can be built on.
- **If adherence data (E6) shows lifters routinely ignore suggestions**, the whole prescribing frame
  is wrong and Coach should lean describing — which would make Insights, not Coach, the right umbrella
  after all.

---

## Related documents

| Doc | What it holds |
|---|---|
| [COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md) | The ten tiles, the two gates, the four parked decisions |
| [SUGGESTION_OPEN_QUESTIONS.md](SUGGESTION_OPEN_QUESTIONS.md) | The plateau, the defaults, what nobody knows about the user base |
| [SUGGESTION_ENGINE_PROGRAM.md](SUGGESTION_ENGINE_PROGRAM.md) | Why the four suggestion docs are one body of work |
| [SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md](SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md) | §4 — what the engine plan does to the coaching module (C1–C4) |
| [TRAINING_INSIGHTS_V2_DESIGN.md](TRAINING_INSIGHTS_V2_DESIGN.md) | §2 locked names, §6 curation, §8 cold start, §12 out of scope |
| [GROWTH_MEASUREMENT.md](GROWTH_MEASUREMENT.md) | The funnel — **§2 is stale, see [§4.0](#40-correction-onboarding-is-three-screens)** |
| [FEATURE_SCOPING_BRIEF.md](FEATURE_SCOPING_BRIEF.md) | Project-wide constraints; share card; the roadmap this sits beside |
| [Repster Onboarding](https://claude.ai/code/artifact/f692c43c-c681-4d00-9c50-14149fecdb2f) | Directions A, D, E; the empty-install audit |
| [Why This Weight](https://claude.ai/code/artifact/1e9ccaa9-a0c4-47e7-974c-82000444d304) | 24 screens; three explainer directions plus content blocks |
| `html prototype/prototype-coaching-tiles.html` | The ten tiles mocked, with per-tile constraints |
