# Live App Store screenshots — inventory

Transcription of the six iPhone screenshots currently on the Repster App Store product
page (live build **1.3**). Documented 2026-08-16 from the frames themselves.

This is a description-only record: exact caption text, and what each device screen shows.
For the critique of this set and the proposed replacements, see `screenshot-review.md`.

## Shared frame design

All six use the same template:

- Charcoal background (near-black, matching the app's dark UI).
- Two-line headline, centred, all caps. **First line light weight, second line bold.**
- One grey subtitle line below the headline, sentence case, ends with a period.
- Caption block occupies roughly the top third; device art begins below the halfway mark.
- No brand colour field, no device frame accent — dark UI on dark ground throughout.
- Screens carry the user's real training data (dates run Apr–May 2026, weights in kg).

Layout grammar is **not** consistent across the set: three frames are a single flat
device, one is an angled multi-device composition, one is a floating collage.

## Display order

Per `screenshot-review.md` §1, the inferred live order is:

1. TRACK PROGRESS
2. AND MORE…
3. REVIEW HISTORY
4. BUILD PROGRAMS
5. START FAST
6. TRAIN SMARTER

That mapping was inferred from CDN filenames and is still unconfirmed in App Store
Connect. The frames below are documented by headline, not by slot.

---

## 1. TRACK PROGRESS

| | |
|---|---|
| Headline | **TRACK** / **PROGRESS** |
| Subtitle | See trends by workout, exercise and muscle group. |
| Layout | Angled multi-device composition — four devices, one centre, three cropped at the edges |
| Screen | Charts tab |

**Centre device — Charts › Breakdown**

- Nav title `Charts`; segmented control `Breakdown` (selected) / `Workouts` / `Exercises`
- Section `Volume by Category`; range chips `All` (selected) / `Year` / `Month` / `Week` / `Day`
- Donut chart, centre label **5.0M kg** / `Total Volume`
- Legend: Legs 39%, Chest 18%, Triceps 5%, Abs 0%, Back 25%, Shoulders 8%, Biceps 4%, Forearms 0%
- Summary row: **5.0M kg** Volume · **11,345** Sets · **114,667** Reps · **556** Workouts
- Date range `May 20, 2021 → May 2, 2026`
- Tab bar: Home · Calendar · **+** (blue FAB) · Charts (selected) · Settings

**Lower-left device — Charts › Workouts**

- Dropdowns `Category`, `Per Week`, `Exercise`; range chips `All` / `1y` / `6mo` / `3mo` / `1mo`
- Dense scatter/line volume chart, y-axis 20.000–60.000, x-axis 2022 → 2024
- Red trend annotation, partially cropped (`…0.1%`)

**Left-edge device (cropped) — Charts › Exercises**

- `Exercises` segment selected; `3mo` / `1mo` chips visible
- Line chart with a green dashed trend line

**Right-edge device (cropped) — Exercise detail**

- Exercise `Incli…` (Incline Smith Barbell Press); labels `Chest`, `Other`
- `WORKOUTS 25`, `BEST E1RM 69,67 kg`
- Tab `History`; section `Estimated 1RM`; chips `All` / `1y` / `6mo`
- Chart y-axis 0–75, x-axis Jan → Jul → Jan; green delta `↗ 0.7%`
- Footer: **68.2 kg**, `52.5 kg × 9`, `Apr 28, 2026`, `View Workout` button

---

## 2. START FAST

| | |
|---|---|
| Headline | **START** / **FAST** |
| Subtitle | PRs, recent sessions and quick start on one home screen. |
| Layout | Single flat device |
| Screen | Home |

- Header `Sunday, May 3` / **Workout**, settings-sliders icon top right
- Week strip: MON 27, TUE 28, WED 29, THU 30, FRI 1, SAT 2, **SUN 3** (selected, blue);
  three coloured page dots beneath
- Primary card: `READY TO TRAIN` (blue eyebrow) / **Start Workout** /
  `Log exercises, sets & reps`, with a blue **+** button
- `RECENT PRS` — trophy rows:
  - Incline Smith Barbell Press — 52.5kg x 9 reps — 5 days ago
  - Seated Leg Curl — 85kg x 10 reps — 7 days ago
  - Leg Extension — 120kg x 10 reps — 7 days ago
- `RECENT` — session cards:
  - **Morning Workout**, Tuesday, Apr 28 — 4 exercises · 8 sets · 43m · 7.3k kg;
    tags Back, Triceps, Chest
  - **Afternoon Workout** — cropped at the frame edge

---

## 3. REVIEW HISTORY

| | |
|---|---|
| Headline | **REVIEW** / **HISTORY** |
| Subtitle | Overview of all historic workouts and PRs. |
| Layout | Single flat device |
| Screen | Calendar |

- Month header `March 2026` with `<` / `>` arrows and a `Today` button
- Weekday row M T W T F S S; full month grid
- Coloured muscle-group dots under trained days, with `+N` overflow counts
  (e.g. Mar 3 `+2`, Mar 26 `+3`); **26** circled as the selected day
- Selected session **Afternoon Workout** with a `⋯` menu
- Stats row: **11.8k kg** VOLUME · **9** EXERCISES · **29** SETS · **1:34:55** DURATION
- Exercise block `Chest Press Machine` — `5 sets`, columns SET / WEIGHT / REPS / RIR:

  | Set | Weight | Reps | RIR | |
  |---|---|---|---|---|
  | 1 | 10 kg | 8 | — | |
  | 2 | 30 kg | 8 | — | |
  | 3 | 50 kg | 4 | — | |
  | 4 | 65 kg | 7 | 0 | ★ PR |
  | 5 | 60 kg | 8 | 0 | ★ PR |

---

## 4. AND MORE…

| | |
|---|---|
| Headline | **AND** / **MORE...** |
| Subtitle | Fatigue learning, easy input and detailed exercise history. |
| Layout | Floating three-device collage, each device at roughly one-third scale |
| Screen | Fatigue Learning + two active-workout states |

**Left device — Fatigue Learning (admin/diagnostics)**

- Nav `Fatigue Learning`, back arrow, red `Reset All`
- `Global Baseline`: Applied Rate **1.80%** (`Global baseline`);
  Qualifying Workouts **11** (`global adjustments active for exercises without overrides`);
  `Cumulative Error` — value cropped, subtitle `you tend to out-perform…`
- `Exercise Diagn…` (Exercise Diagnostics): One Arm Pulldown 2.10%, Seated dip 2.40%,
  Chest Assisted Row 3.40%, Barbell Press (cropped) — each `Using 50% local lea…`

**Right device (behind) — Active workout › History**

- Timer `1:58` (paused), `+`, blue `Finish`
- Exercise chip `Barbell Back Squat` with a completion check
- Tabs Sets / **History** / PRs / Charts / ⚙
- Entry `1  115 kg × 5  RIR 2`; date `Apr 29, 2026` with a column of ★ PR badges
- Rest-timer controls `+30s` and edit

**Front device — Active workout › Sets, with rep keypad open**

- Timer `3:05`, `+`, blue `Finish`; exercise chip `Barbell Back Squat`
- Tabs **Sets** / History / PRs / Charts / ⚙
- Table SET / WEIGHT / REPS / RIR / PR / ✓ — row 1 (green, checked): `50`, `0`, `—`;
  row 2 (empty): `0`, `0`, `—`
- `+ Add Set` · `+ Add Warmup`
- Rest timer sheet `0:04` with pause / dismiss
- RIR picker `Set · Reps` — `—` `0` `1` `2` `3` `4` `5+`, colour-graded red → green
- Numeric keypad 1–9, `-`, `0`, backspace; keyboard toggle; `Set Range`; `−` / `+`;
  `Prev` / `Next`; white `Done`

> Note: this frame ships `50 kg × 0 reps` as visible data — flagged in
> `screenshot-review.md` §7 as the one place the set breaks its own realistic-data rule.

---

## 5. TRAIN SMARTER

| | |
|---|---|
| Headline | **TRAIN** / **SMARTER** |
| Subtitle | Smart weight suggestions, rest timers, RIR and fatigue. |
| Layout | Single flat device |
| Screen | Active workout › Sets |

- Header: back arrow, timer `2:46` (paused), `+`, blue `Finish`
- Exercise chips: **Barbell Back Squat** (selected) / Barbell Row / Chest Supported…
- Tabs **Sets** / History / PRs / Charts / ⚙
- Set table SET / WEIGHT / REPS / RIR / PR / ✓:

  | Set | Weight | Reps | RIR | PR | ✓ |
  |---|---|---|---|---|---|
  | … | 55 | 8 | — | | ✓ |
  | 1 | **122,5** | 8 | 3 | ★ PR | ✓ |
  | 2 | 0 | 5-8 | — | | ☐ |
  | 3 | 0 | 8 | — | | ☐ |

- `+ Add Set` · `+ Add Warmup`
- `SMART SUGGESTIONS` section with a refresh control; card reads:
  `Smart Suggestions` / `2 suggestions ready` / `Set 2` / **125 kg** `for 5-8 reps` /
  `Based on your recent performance and adjusted for this…` (truncated at the frame edge)

---

## 6. BUILD PROGRAMS

| | |
|---|---|
| Headline | **BUILD** / **PROGRAMS** |
| Subtitle | Start from a template or build your own program. |
| Layout | Single flat device |
| Screen | Templates sheet |

- Header: `Close` (left), `⋯` and `New` (right); large title **Templates**
- Info card: **Pick a template and start fast.** /
  `Tap any template to launch your workout. Use the top-right menu for import and AI
  tools, and each row menu for management actions.`
- Template rows (letter avatar · name · counts · `Tap to start` · muscle tags · `⋯`):
  - **A** (red) — Arms — 4 exercises · 13 sets — Biceps, Triceps, Forearms
  - **L** (teal) — Legs — 6 exercises · 12 sets — Legs
  - **F** (green) — Full Body — 7 exercises · 15 sets — Legs, Shoulders, Abs, +1
  - **U** (green) — Upper Body 2 — 9 exercises · 20 sets — Back, Biceps, Chest, +3

---

## Caption text, all six

| Headline | Subtitle |
|---|---|
| TRACK PROGRESS | See trends by workout, exercise and muscle group. |
| START FAST | PRs, recent sessions and quick start on one home screen. |
| REVIEW HISTORY | Overview of all historic workouts and PRs. |
| AND MORE... | Fatigue learning, easy input and detailed exercise history. |
| TRAIN SMARTER | Smart weight suggestions, rest timers, RIR and fatigue. |
| BUILD PROGRAMS | Start from a template or build your own program. |

## Screens not represented anywhere in the set

Import/export, Settings, Insights, Live Activity / Lock Screen rest timer, and the
prescription settings screen. Insights is 1.4-only so its absence is expected; the others
are shipped surfaces with no coverage.
