# Prompt: screenshot coverage audit → suggestion sheet

Reusable prompt for a fresh session. Copy everything below the line.

Purpose: produce a complete map of what Repster can actually do, diffed against what the
current App Store screenshots show, so the full menu of possible frames is visible —
including options neither the live set nor the proposed sets in `screenshot-review.md`
considered.

---

You are auditing App Store screenshot coverage for Repster, a shipped iOS lifting tracker.
The repo root is the working directory. Work from the source code, not the simulator.

## Context you must read first

- `marketing/app-store/live-screenshots-inventory.md` — transcription of the six
  screenshots currently live on the App Store. This is your baseline for "what is shown".
- `marketing/app-store/screenshot-review.md` — an existing critique of that set, plus two
  proposed replacement sets (Set A broad, Set B technical).
- `marketing/campaigns/technical-lifter/ad-kit.md` — claim inventory and copy guardrails.
- `marketing/app-store/product-page.md` — the launch metadata and capture requirements.

**Do not simply restate Set A or Set B.** They already exist. Your job is the layer
underneath them: the exhaustive capability inventory that reveals what *both* of those
sets missed. If your output could have been written without reading the source code, you
have failed the task.

## Phase 1 — Build the true feature surface from source

Walk `Repster/Features/` and enumerate every user-facing capability. The feature modules
are: Calendar, Charts, Exercise, Health, History, Home, Insights, Onboarding, Programs,
Settings, Templates, WhatsNew, Workout. Also check `Repster/Core/` and
`WorkoutLiveActivity/` for capabilities that surface in the UI but do not have their own
feature folder.

For each capability record:

- **Name** — what a user would call it, not the type name.
- **Primary view file** — the SwiftUI view that would be captured, as a repo path.
- **Visual weight** — is there a distinctive screen here, or is it a toggle buried in
  settings? A capability with no photogenic surface is still worth recording, but mark it.
- **Version gate** — is this in the live 1.3 build, or only on `NewMain` awaiting 1.4?
  1.3 was released 2026-06-11; use `git log` against that date to decide. This matters:
  App Store screenshots are version-locked to a submission, so anything 1.4-only cannot
  appear on the page until 1.4 ships.
- **Claim status** — can the feature's benefit be stated as a verifiable fact about
  observable behaviour? If the honest description is vague, say so.

Be exhaustive. Include the unglamorous surfaces — import, export, backup, units, rest
timer configuration, plate maths, warmup handling, exercise creation, superset support,
notes, Live Activity, HealthKit, onboarding. Small features are exactly what the existing
sets overlooked.

## Phase 2 — Diff against the live set

For every capability from Phase 1, assign one of:

- **Covered** — a live screenshot has this as its subject.
- **Incidental** — visible on screen, but not what the frame is about, and unreadable at
  thumbnail scale.
- **Absent** — nowhere in the six.

Then answer, briefly: which absent capabilities are absent because they genuinely don't
deserve a slot, and which are absent by oversight? Those are different problems.

## Phase 3 — The suggestion sheet

This is the deliverable. Produce a table of every frame that *could* be made, ranked by
how strong a case there is for it. Not a set of six — the full menu, so a set can be
assembled from it later.

Each row needs:

| Column | Content |
|---|---|
| Frame | Working name |
| Headline | Max four words, one line. If it needs the subtitle to make sense, it's wrong |
| Subtitle | One line, the qualifier that makes the headline credible |
| Screen | Repo path to the view, plus which state it must be in |
| Data required | The specific numbers/exercises that must be on screen |
| Argument | What this frame makes someone believe. One sentence |
| Version | 1.3-capturable, or 1.4-gated |
| Capture status | Does a usable capture already exist in `marketing/source/`, or is this a new capture? |
| Strength | Strong / situational / weak — with a reason |

Group the table by what the frame is arguing: capability, differentiation, switching cost,
trust/control. Flag any frame whose argument duplicates another's.

Close with:

1. **The frames nobody has proposed yet** — call these out explicitly, with why they were
   missed.
2. **Captures that must be taken** before any of this is renderable, as a checklist.
3. **Anything the app does that should stay off the page**, and why.

## Constraints

- **Read the SwiftUI source to determine what a screen shows.** Do not boot the simulator;
  it is a last resort, not the default check.
- **Verify before you claim.** If you propose a frame, the feature must exist in code and
  you must cite the file. A proposed frame for a feature that turns out to be half-built is
  worse than no proposal.
- **Copy guardrails** (from the ad-kit): nothing medical, nothing about injury, no
  "optimal", no "scientifically proven", no "makes you stronger". Describe the mechanism,
  never promise the outcome.
- **Thumbnail test.** Apple serves roughly 320×480 in search results. For each proposal,
  state in a few words what survives at that size. If nothing does, mark it weak.
- **Real data only.** No placeholder numbers, no zero-rep sets — the live "AND MORE…"
  frame ships `50 kg × 0 reps` and that is the mistake not to repeat.
- **No filler slots.** Never propose an "and more" frame.
- Apple allows up to 10 screenshots per device size. Do not artificially cap your menu at
  six — the point is the full range of options.

## Output

Write to `marketing/app-store/screenshot-suggestions.md`. Markdown, tables where the
content is tabular. Report honestly: if a section of the app has no case for a screenshot,
say so plainly rather than padding the sheet.
