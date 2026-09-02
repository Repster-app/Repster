# Post drafts — solo dev, lifter-first, origin

2026-08-31. Feature-driven first pass parked in `organic-post-drafts-feature-angle.parked.md`.
No product explanation in any of these. `[brackets]` = only you can fill it.

Verify before posting: 200+ users, 9-15 DAU, 1.4 shipped 2026-08-20 with 7 day-one
installs, free tier 5→10 on 2026-08-18. Revenue and ASA spend I don't have.

---

# REDDIT

## R1 — r/SideProject
**Title:** I built a retention feature, it worked, and I deleted it the same day

My app's retention is bad. I know it's bad. Notifications are the obvious lever, so
I spent a day building them properly: scheduling service, a settings screen so people
could turn it off, analytics, 14 tests. Merged and working.

Then I imagined getting one. "You haven't trained since the 12th." From software that
has no idea whether I was ill, travelling, deloading, or just having a bad week.

I deleted it. Same day, all of it.

I'm not claiming this was smart. It was the highest-leverage thing on my list and I
threw it away for a feeling. But I've been on the receiving end of apps that decided
my lapse was a problem to be solved, and I didn't want to build one.

Retention is still bad and I still have to fix it. What I'm actually asking: what's
the retention lever that isn't a notification? The honest answer might be "there
isn't one, grow up" and I'd rather hear that than keep guessing.

---

## R2 — r/iOSProgramming or r/SideProject
**Title:** I went to fix my onboarding and found something worse than bad onboarding

Three screens. I checked what each one does.

Screen one is a welcome. Asks nothing, does nothing.

Screen two asks for units and bodyweight. The device locale already told me kg or lbs.
And nothing in the app reads the bodyweight. I just collect it.

Screen three asks you to import your history from a CSV, which almost nobody has, so
for most people it's a third screen that ends in "skip".

So the first thing a new user does is answer three questions — one I already knew, one
I never use, one that doesn't apply — and then arrive at an empty app.

I've been paying for installs and sending them into that.

The thing that got me isn't that it's bad. It's that I wrote all three screens
deliberately, shipped them, and then never once opened the app as a new user again.
I've been staring at a simulator with two years of test data in it since launch.

---

## R3 — r/weightroom or r/naturalbodybuilding
**No app. No link. No disclosure, because there's nothing to disclose.**
**Title:** When do you add weight vs add a rep? Genuinely asking.

I've been going back and forth on this for months and I still don't have a rule I
trust.

Say the target is 3 sets of 6-10 and I hit 10, 10, 9 at [weight]. Obvious answer is
add weight, drop back to 6ish, climb again. Double progression, fine.

Where I keep getting stuck is the edges. If I hit 10, 9, 8 — is that "not finished
with this weight" or "the last set is always going to be short and I should move on
anyway"? If I add 2.5kg and drop to 6, 6, 5, I've done a lot less total work than the
session before, and I can't tell if that's the point or a problem.

And on the small stuff — laterals, curls — the smallest jump I have is a bigger
percentage of the weight than it is on a squat, so double progression means either
grinding the same weight for two months or making a 10% jump. Neither feels right.

[If you have a specific thing you've settled on, say it here — one line, as your own
experience, not advice.]

What I actually want to know is whether people run one rule everywhere or genuinely
switch approaches by movement, and if it's the second, what decides it.

---

## R4 — r/weightroom, alternative to R3
**Title:** Does anyone actually take the rest they say they take?

Programme says 3 minutes. I've started actually timing it instead of estimating, and
the number of times I've been sat there at 1:40 thinking "yeah that's about three
minutes" is embarrassing.

What surprised me more is how much it moves. Rest is the one variable I was treating
as fixed while carefully tracking everything else, and when I started looking, it was
swinging from 90 seconds to five minutes depending on whether the gym was busy, how
much I was dreading the set, and whether someone was talking to me.

[One line about what you noticed happened to your numbers when it swung.]

Two things I'm curious about: does anyone here actually enforce it, and does it matter
as much on accessories as I assume it does on the main lifts, or am I being precious
about something that only matters for heavy singles?

---

## R5 — r/SideProject
**Title:** Why I built a workout app, which is a stupid response to the problem I had

[The moment: a specific day, a specific set, the thing you wanted to know and
couldn't. One paragraph. It needs to be concrete enough that it could only be you.]

[What you used instead — notes app, spreadsheet, another app, memory. And the
specific way it failed. Not "clunky". The actual failure.]

The reasonable response to this is to write it in a notebook. What I did instead was
learn Swift and spend [how long] building an iOS app, which is an absurdly
disproportionate reaction and I want to be honest that some of it was wanting to build
something and this being the excuse.

It's been on the App Store since May. A couple hundred people use it. I'm still not
done and I've stopped estimating when I will be.

---

# X / TWITTER

## T1 — the deleted feature (thread)

> I spent a day building re-engagement notifications for my app.
>
> Scheduling service, settings screen, analytics, 14 tests. Merged and working.
>
> Then I deleted all of it, the same day.

> 1/ It worked. That wasn't the problem. Someone stops logging for nine days, the app
> taps them on the shoulder. Every growth guide tells you to build this.

> 2/ My retention is bad. This was the obvious lever and I had it working.

> 3/ Then I imagined receiving it. "You haven't trained since the 12th." From software
> that can't possibly know if I was ill, travelling, deloading, or just having a week.

> 4/ Deleted. Tests still green, no references left behind. Cost me a day and it's the
> decision I'm most sure about all quarter.

> 5/ Retention is still bad. I just have to fix it with something that isn't nagging
> people. Open to suggestions, genuinely.

---

## T2 — ads

> My Apple Search Ads are working fine.
>
> People search, they tap, they install. The ad is doing exactly what I paid for.
>
> Then they open it once and never come back.
>
> Turns out "installs are cheap" and "installs are worthless" are the same sentence.

---

## T3 — onboarding (thread)

> Went to fix my app's onboarding this week. Found something worse than bad onboarding.
>
> Three screens. None of them do anything.

> 1/ Screen one: welcome. Asks nothing, does nothing. A door with a picture of a door
> on it.

> 2/ Screen two: units and bodyweight. Locale already told me kg or lbs. And nothing in
> the app reads the bodyweight. I just collect it.

> 3/ Screen three: import your CSV. Almost nobody has a CSV. For most people it's a
> third screen that ends in "skip".

> 4/ So new users answer three questions — one I knew, one I never use, one that
> doesn't apply — then arrive at an empty app. I've been paying for installs and
> sending them into that.

> 5/ Worst part: I wrote all three deliberately. Then never opened the app as a new
> user again. I've been looking at a simulator with two years of fake data since launch.

---

## T4 — launch day
**Post on the next release day, before you know how it went.**

> Shipped 1.4 today after six weeks of work.
>
> Seven installs.
>
> Posting because every launch post I read while building was a screenshot of a hockey
> stick, and there should be one of these in the timeline too.

No "but here's what I learned" section. The flatness is the post.

---

## T5 — the free limit

> My app was free for 5 workouts, then paywalled.
>
> Problem: the parts worth paying for — history, charts, trends — need more than 5
> workouts to show you anything. People hit the wall exactly when the app still looked
> empty, and I was asking them to pay to find out if it wasn't.
>
> Raised it to 10. Not a growth tactic. I just don't want to charge people before the
> thing has had a chance to be good.

---

## T6 — origin (thread)

> [The moment. One tweet. Specific: the day, the set, the thing you wanted to know.]

> 1/ [What you did instead. Notes app, spreadsheet, memory.]

> 2/ [The specific way that failed. Not "clunky" — the actual failure.]

> 3/ The reasonable response is a notebook. I learned Swift and built an iOS app,
> which is a wildly disproportionate reaction to a logging problem.

> 4/ Some of it was wanting to build something and this being the excuse. I think
> that's true of most apps and nobody says it.

> 5/ It's been on the App Store since May. A couple hundred people use it. Still not
> done.

---

## T7 — the simulator

> Every bug I've shipped has the same root cause: I test on a simulator with two years
> of perfect data in it, and every real user opens an app with nothing in it.
>
> I've been building for a version of my app that only I have ever seen.

---

# Order

- **This week:** R1 on r/SideProject, T1 on X. Best story you have, safest room.
- **Then:** T2 and T3, spaced a few days. These are the reach plays.
- **R3 or R4:** only after two weeks of genuine commenting in that sub. No link ever.
- **Next release day:** T4, same day.
- **When ready:** R5 and T6, a few days apart. You get one origin post people believe.

Before any of it: a redirect path on the Pages site pointing at the App Store, so you
can count hits. App Store passes no referrer — without it none of this is measurable.
