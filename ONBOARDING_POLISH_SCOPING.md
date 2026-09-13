# Onboarding polish — scoping

Four issues from a fresh-install pass on 2026-09-13. They're all in the view layer: no model, service or
migration changes. Target is 1.6.

Status: **built 2026-09-13 (uncommitted); device pass outstanding.**

---

## 1. "I'd rather build my own" should look like the program cards

**Now.** `ProgramPickerView.buildOwnLink` (ProgramPickerView.swift:138) is a centred text
link under the four program cards. That was a deliberate choice, recorded in
ONBOARDING_REDESIGN_SCOPING.md §4.5 as "a de-emphasised link" and in the code comment as "an
escape hatch, not a peer … so it is a link, not a fifth card". This change reverses it.

**Proposal.** Make it a fifth card built from the same parts as `programCard`: same
background, border, corner radius, padding and selection tick.

- Title: **Build my own**. Detail line: *Start with an empty library and add sessions as you go.*
- No `DAYS` badge. There's nothing to count.
- Selecting it works like a program card: a second tap no longer deselects it (the link
  currently toggles back to `.undecided`).
- The CTA copy stays as it is ("Start from scratch"), and so do the rotation preview (programs
  only) and the Extras confirmation line ("Empty library ready…").

`ProgramPickerView` has one call site today (onboarding), so nothing else changes.

## 2. FitNotes has a unit preselected and Strong/Hevy don't

**Why it happens.** The difference is real, but the onboarding sheet hides the reason:

- A FitNotes CSV has both `Weight (kg)` and `Weight (lbs)` columns (ImportService.swift:382).
  The unit only chooses which column is preferred, and the other is the fallback. A wrong
  guess costs nothing, so `ImportSource.fitNotes.requiresUnitSystem == false` and the view
  model gives it a default.
- Strong and Hevy CSVs don't say which unit they use. A wrong default would silently scale every
  imported weight by 2.2×, so those two start blank and "Select … CSV" stays disabled until
  the user picks.

Settings → Import shows the difference ("FitNotes Weight Units" vs "Strong Export Units",
plus a hint line). The onboarding sheet puts all three under one label, **"Units in CSV"**,
with no hint, so the difference looks arbitrary.

**Options**

| | What changes | Verdict |
|---|---|---|
| **D (recommended)** | In the onboarding sheet, hide the unit row for FitNotes. The file already carries both columns, and the step-1 unit choice is still passed in as the preferred column, as it is today. Strong/Hevy keep the blank picker and get the one-line hint Settings already uses ("Strong exports don't include units — pick the one used in your export."). Rule: *any picker you can see starts blank.* | View-only, ImportStepView.swift. No VM or Settings change. |
| A | Leave FitNotes blank too, so every source needs one tap. | Makes `selectedFitNotesUnitSystem` optional, which Settings' ImportView.swift:102 also reads. Adds a tap for no benefit. |
| B | Preselect all three from the step-1 unit. | **Don't.** A kg user whose Strong export was in lb gets every weight off by 2.2× with no warning. |

## 3. Button wording says you're leaving onboarding when you aren't

Both extras are sheets over the final onboarding step. Closing either one returns there, and
"Start training" is still the only way into the app.

**Import sheet** (ImportStepView.swift, used only by onboarding)

| Where | Now | Proposed |
|---|---|---|
| Idle, secondary button | Start Without Importing (arrow icon) | **Not now** |
| Completed | Get Started | **Done** |
| Failed, left button | Start Without Importing | **Not now** |
| Header subtitle | "…from FitNotes or Strong now, or start fresh and import later from Settings." | "Bring over past workouts from FitNotes, Strong or Hevy. You can also do this later from Settings." (the current line leaves out Hevy) |

**Walkthrough** (HowItWorksView.swift:64): the last page's button says **"Start your first
workout"** but only calls `dismiss()`. It has three hosts:

| Host | After tapping, you land on | Proposed label |
|---|---|---|
| Onboarding extras | the final onboarding step | **Done** |
| Settings → About | Settings | **Done** (same defect; one-word change, drop if unwanted) |
| Home banner | Home, with Start Workout right there | keep "Start your first workout" |

Implementation: add a `finishTitle: String` parameter with the current text as its default.
Onboarding and Settings pass "Done". The analytics (`walkthroughCompleted`) don't change.

## 4. Apple Health prompt: the "box" and the full-screen sheet

This isn't onboarding. It's the one-time offer after the first finished workout
(`ContentView.offerAppleHealthIfEarned`, presented as a sheet at ContentView.swift:383).

**The box.** The button bar in AppleHealthPromptView.swift:66–86 paints `.background(Color.bg)`
(#111113), but that VStack has no `.frame(maxWidth: .infinity)`. The dark fill only reaches
as wide as "Connect Apple Health" plus 32 pt on each side. The rest of the sheet sets no background, so the system's
lighter sheet grey shows around it. That's the rectangle in the screenshot.

**Proposal**

- Make the button bar full width, and give the sheet one background
  (`presentationBackground(Color.bgCard)`, matching WhatsNewSheet and StartWorkoutSheet).
- Size the sheet to its content instead of full height. Reuse WhatsNewSheet's pattern: measure
  the scroll content with a `PreferenceKey`, then `.presentationDetents([.height(clamped)])`
  with a floor and a ceiling so large Dynamic Type still scrolls. `.medium` alone is too
  short: the content is about 530 pt and would cut off the three-point card.
- Cut the 48 pt bottom padding to the sheet's value (~8–16 pt), since the sheet adds the safe area itself.
- Fix the header comment that says onboarding uses this as a full page. It hasn't since 1.5
  (see the note at ContentView.swift:772).

## Files

- `Programs/Views/ProgramPickerView.swift` — #1
- `Onboarding/Views/ImportStepView.swift` — #2, #3
- `HowItWorks/HowItWorksView.swift`, `Onboarding/Views/OnboardingContainerView.swift`,
  `Settings/Views/SettingsView.swift` — #3
- `Health/AppleHealthPromptView.swift` — #4

`OnboardingContainerView.swift` carries the "stuck after finish" fix (committed in 65c2652).
#3 only adds one argument there.

No tests assert on any of these strings (checked RepsterTests + RepsterUITests).

## Verification

- Full suite on the iOS 26.3 simulator (2026-09-13): **915 tests, 901 passed, 0 failed, 14 skipped**.
  The same suite on the iOS 17.5 simulator crashed 4 tests (segv) in AffectedSetsPreconditionTests
  and WorkoutJourneyTests. Those are the known iOS 17 live-set crashes, and neither file references
  anything changed here.
- Tap steps for a device or simulator pass, done by the user:
  1. Step 2: the fifth card selects and deselects like the others, and the CTA reads "Start from scratch".
  2. Extras → Bring your history in: FitNotes shows no unit row. Strong and Hevy show a blank
     picker with a hint, and Select CSV stays disabled until you pick. "Not now" returns to Extras.
  3. Extras → See how it works → last page reads "Done" and returns to Extras.
  4. Finish a first workout on a fresh install: the Health sheet is shorter than the
     screen, has one background, and has no box behind the buttons.

## Decisions (2026-09-13)

The user accepted all three recommendations:

1. #1 card wording as proposed ("Build my own" / "Start with an empty library…").
2. #2: option D. The Strong/Hevy hint moved to `ImportSource.unitSystemHint`, so Settings
   and onboarding read the same strings.
3. #3: Settings → About also says "Done".
