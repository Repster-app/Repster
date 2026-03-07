# Strength Training App — Screen Tree & Navigation Map

**Version:** 1.0  
**Status:** Working Draft  
**Last Updated:** February 2026

---

## Tab Bar

```
[ Programs ] [ Calendar ] [ + FAB + ] [ Charts ] [ Settings ]
```

- Bottom nav visible on all tab screens
- Bottom nav HIDDEN on focused screens (active workout, detail screens)
- FAB: if no active workout → Exercise List. If active workout exists → returns to it.

---

## 1. Programs Tab [v1: empty state placeholder]

```
Programs List
└── Coming soon messaging, no functionality in v1
```

**v1.1:** Full program CRUD, schedule workouts, start workout from program.

---

## 2. Calendar Tab

```
Calendar (bottom nav visible)
├── Vertically scrollable month grids
├── "Today" button — jumps to current date
├── Colored dots on dates — represent muscle groups worked
├── Blue fill = today, blue outline = scheduled future session
├── Tap a date → Workout Detail [inline below calendar]
│   ├── Summary stats (volume, exercises, sets)
│   ├── Exercise cards with sets, weights, reps, PR badges
│   └── Tap exercise card ↓
│
└── Exercise Detail (full screen, pushed)
    ├── [ History ] — past sessions for this exercise, newest first
    ├── [ PRs ] — suffix-max filtered rep-max table
    └── [ Charts ] — e1RM trend, volume per session
```

---

## 3. FAB → Exercise List & Active Workout

```
Exercise List (bottom nav visible when browsing, hidden when in workout flow)
├── Search bar
├── Muscle group filter pills (horizontally scrollable)
├── Sort options (A–Z, most recent, most used)
├── Exercise cards — name, muscle, equipment, tracking type, last performed, best lift
│   ├── Tap card (browse mode) → Exercise Detail (same as 2, reused)
│   └── Select card (workout mode) → adds to workout selection
├── [+ New] → Create/Edit Exercise [sheet]
│   └── Full form: name, equipment, tracking type, primary/secondary muscles,
│       movement pattern, unilateral, bodyweight factor, weight increment, rest time
├── "Start Workout (N)" button — visible when exercises selected
│
└── Active Workout (focused — NO bottom nav)
    ├── Elapsed timer + [+Exercise] button + End/Back button
    ├── Exercise Tab Strip — horizontally scrollable, drag to reorder
    │   ├── Long-press tab → context menu: Delete Exercise (with confirmation)
    │   └── Active exercise shown below
    │
    ├── Sub-tabs within each exercise:
    │   ├── [ Sets ] (default)
    │   │   ├── Set table: Set#, Weight, Reps, RPE/RIR, Completion checkbox
    │   │   │   ├── Columns adapt to exercise trackingType
    │   │   │   ├── Warmup rows: "W" badge, 0.45 opacity
    │   │   │   ├── Completed rows: green tint, green checkmark
    │   │   │   ├── PR badge (gold) on cachedPRStatus = "current"
    │   │   │   ├── Match badge (blue =) on cachedPRStatus = "matched"
    │   │   │   └── Long-press row → context menu: Edit Set Type, Delete Set
    │   │   ├── [+ Add Set] [+ Add Warmup]
    │   │   └── Rest Timer — auto-starts on set completion
    │   │       ├── Countdown from exercise defaultRestTime
    │   │       └── [Dismiss] [+30s]
    │   ├── [ History ] — past sessions for this exercise (reused component)
    │   └── [ Charts ] — e1RM trend, volume chart (reused component)
    │
    └── [Finish Workout] → Workout Summary [sheet]
        ├── Date, duration, total volume, total sets
        ├── Exercise list with set counts and best lift each
        ├── PRs hit during session (highlighted)
        ├── Session notes (editable → Workout.notes)
        ├── Session RPE selector (1–10 → Workout.perceivedEffort)
        └── [Save & Close] → sets status = completed, returns to Calendar tab
```

---

## 4. Charts Tab

```
Charts Dashboard (bottom nav visible)
├── OVERVIEW section
│   ├── Weekly volume (bar chart, last 12 weeks)
│   ├── Training frequency (sessions per week)
│   └── Muscle group distribution (last 4 weeks)
│
├── PER EXERCISE section
│   ├── Exercise cards sorted by most recent
│   │   └── Current e1RM, trend direction, sparkline
│   └── Tap card ↓
│
└── Exercise Charts Detail (pushed)
    ├── Time range selector: [3M] [6M] [1Y] [All]
    ├── e1RM trend (line chart)
    ├── Volume per session (bar chart)
    ├── Top weight per session (line chart)
    └── Rep PR progression (multi-line: 1RM, 3RM, 5RM over time)
```

---

## 5. Settings Tab

```
Settings (bottom nav visible)
├── GENERAL
│   ├── Units → [sheet] metric / imperial toggle
│   └── e1RM Formula → [sheet] formula picker with descriptions
│
├── WORKOUT PREFERENCES
│   ├── Include Warmups in Volume (toggle)
│   ├── Include Warmups in PRs (toggle)
│   └── Default Rest Time → picker
│
├── DATA
│   ├── Import Data (CSV) → file picker, preview, mapping, progress, results
│   ├── Export Data (CSV) → options, share sheet
│   └── Rebuild Stats → explanation, [Rebuild PRs] [Rebuild Stats] [Rebuild All]
│
├── BODY
│   └── Bodyweight Log → trend chart, chronological entries, [+Add] entry
│
└── ABOUT
    ├── Version number
    └── Send Feedback
```

---

## 6. Onboarding (first launch only)

```
Onboarding Flow
├── Welcome screen
├── Units selection (kg / lbs)
├── e1RM formula (Epley default, with descriptions)
├── Bodyweight entry (optional, skippable)
└── Import prompt (optional — "Migrating from another app?")
    └── After completion → Calendar tab
```

---

## 7. Navigation Reference

### Navigation Patterns

| From | Action | To | Type |
|------|--------|----|------|
| Any tab | Tap FAB (no active workout) | Exercise List | Push |
| Any tab | Tap FAB (active workout exists) | Active Workout | Push |
| Exercise List | Select exercises + "Start Workout" | Active Workout | Push (focused) |
| Exercise List | Tap [+ New] | Create Exercise | Sheet |
| Exercise List | Tap exercise card (browse mode) | Exercise Detail | Push |
| Active Workout | Tap [+Exercise] | Exercise List (selection mode) | Sheet |
| Active Workout | Tap "Finish Workout" | Workout Summary | Sheet |
| Workout Summary | "Save & Close" | Calendar tab (today) | Dismiss to root |
| Calendar | Tap exercise card in workout detail | Exercise Detail | Push |
| Charts Dashboard | Tap exercise card | Exercise Charts Detail | Push |
| Settings | Tap any row | Setting detail | Push or Sheet |

### Gesture Reference

| Gesture | Context | Action |
|---------|---------|--------|
| Long-press | Set row in active workout | Context menu: Edit Set Type, Delete Set |
| Long-press | Exercise tab in active workout | Context menu: Delete Exercise |
| Drag | Exercise tab in active workout | Reorder exercises |
| Tap | Completion checkbox | Mark set complete, trigger PR pipeline, start rest timer |
| Tap | Calendar date | Show workout detail inline below calendar |

---

## 8. Reused Components

These components appear in multiple places — build once, use everywhere:

| Component | Used In |
|-----------|---------|
| Exercise Detail (History/PRs/Charts tabs) | Calendar workout detail, Exercise List browse, Active Workout sub-tabs |
| Exercise Card (summary) | Calendar workout detail, Exercise List, Charts Dashboard |
| Set Row | Active Workout set table, Calendar workout detail (read-only) |
| PR Badge (gold) / Match Badge (blue) | Set rows anywhere |
| Summary Stats Strip (volume, exercises, sets) | Calendar workout detail, Workout Summary |

---

## 9. Screen Count

| Category | Screens | v1 Status |
|----------|---------|-----------|
| Programs | 1 (empty state) | Placeholder |
| Calendar | 2 (calendar + exercise detail) | Build |
| Workout | 4 (exercise list, create exercise, active workout, summary) | Build |
| Charts | 2 (dashboard + exercise charts detail) | Build |
| Settings | 7 (main + units, e1RM, import, export, bodyweight, rebuild) | Build |
| Onboarding | 5 (welcome, units, e1RM, bodyweight, import) | Build |
| **Total** | **~21 screens** | |

---

*End of Document*
