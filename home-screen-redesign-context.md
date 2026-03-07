# Home Screen & Workout UX Redesign — Context & Decisions

**Date:** March 2026
**Status:** Planning complete, ready for spec-kitty feature creation

---

## Background

The user felt the app's screen structure didn't align with their vision. Through a collaborative discussion, we identified the core issues and designed a solution.

### Original Concerns
1. **Wrong home screen** — The app opens to a "Programs" placeholder (coming soon), not a useful landing page
2. **Missing key screen** — No dashboard/home screen that ties everything together and shows at-a-glance information
3. **Active workout display** — Wanted a dedicated screen for the current workout (later refined to keeping the focused fullScreenCover approach)

---

## Discussion Summary

### Navigation Structure Decision

**Explored options:**
- 5 tabs with a Workout tab replacing the fullScreenCover (initially discussed)
- 4 tabs + center FAB matching reference app (final decision)

**Final decision:** Keep the current 4-tab + center FAB architecture. The active workout stays as a focused fullScreenCover with no tab bar — this is the standard pattern in fitness apps and provides an immersive logging experience.

```
[ Home ] [ Calendar ] [ + FAB + ] [ Charts ] [ Settings ]
```

Changes from current:
- "Programs" tab → renamed to "Home" with house icon
- Programs placeholder → replaced with full Home screen
- FAB stays centered, same size and behavior
- Everything else unchanged

### Home Screen Design (Reference: Screenshot 1)

The user provided a reference screenshot from another workout app showing the ideal home screen layout. Key sections:

1. **Header** — Date display + title ("Workout") + profile avatar
2. **Week Strip** — Compact Mon–Sun calendar showing current week, today highlighted with accent color, dots under days with completed workouts
3. **Start Workout Card** — "READY TO TRAIN" label, "Start Workout" title, "Log exercises, sets & reps" subtitle, [+] button on right. Tapping opens exercise list or starts workout directly.
4. **Quick Action Cards** (side by side):
   - "Copy Previous" — Repeat a past workout (pick from recent workouts, duplicate exercises)
   - "Templates" — Use a saved routine (maps to Programs feature, v1.1)
5. **This Week Activity** — Day-by-day bar chart (M-S), "X / Y sessions" counter, bars filled for workout days
6. **Recent Workouts** — Cards showing: workout title/muscle groups, date, exercise count, sets, duration, volume, muscle group tags

### Active Workout Enhancement (Reference: Screenshot 2)

The reference showed an **Exercise Info section** below the set table in the active workout view. This provides contextual data to help the user make decisions while logging:

1. **Estimated 1RM** (large card) — Current e1RM value, "Best today: X kg × Y reps", "vs N wk ago: +/- X kg"
2. **Last Workout** (compact card) — Top sets from last session (e.g., "85×8, 45×8"), "N days ago"
3. **Est. for N reps** (compact card) — Estimated weight for current rep range, "Based on recent data"

### Historic Workout Detail (Reference: Screenshot 3)

The reference showed a workout detail view with:
- Date header + summary stats strip (exercises, sets, duration, volume)
- Muscle group filter pills
- Exercise-by-exercise breakdown with all sets, weights, reps, PR badges, and best lift per exercise
- Tab bar visible (normal screen, not focused)

This is similar to the existing `CalendarWorkoutDetailView` but presented as a standalone pushed view. The Home screen's recent workout cards should navigate to this view.

---

## Key Decisions Made

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Tab bar structure | 4 tabs + center FAB (unchanged) | Matches reference app, simpler than 5-tab approach |
| Active workout presentation | fullScreenCover (unchanged) | Focused immersive experience, matches reference |
| First tab | "Home" with house icon | Action-focused landing page |
| Home screen style | Match reference closely | Week strip, start workout CTA, copy previous, templates, activity, recent workouts |
| Copy Previous | Build it (simple feature) | Take past workout exercises → duplicate into new workout |
| Templates card | Link to Programs (v1.1 placeholder) | Templates = Programs feature, coming later |
| Exercise Info section | Include in active workout | Estimated 1RM, last workout, progress comparison below set table |
| FAB position | Center (unchanged) | Shrinking not needed since tab count unchanged |

---

## Feature Breakdown

### Feature 013: Home Screen
Replace the Programs placeholder tab with a full Home screen. Includes: week strip calendar, start workout CTA card, copy previous quick action, templates quick action (placeholder), this week activity tracker, recent workouts list. Also renames the tab from "Programs" to "Home".

### Feature 014: Copy Previous Workout
Sheet flow accessible from the Home screen's "Copy Previous" card. Shows recent completed workouts with summary stats. Tapping one creates a new workout with the same exercises in the same order, then opens the active workout fullScreenCover.

### Feature 015: Exercise Info in Active Workout
Adds a contextual Exercise Info section below the set table in ActiveWorkoutView. Shows estimated 1RM with today's best and historical comparison, last workout summary for the exercise, and estimated weight for the current rep range.

---

## Reference Screenshots

Three screenshots were provided as reference:
1. **Home screen** — Shows the ideal landing page layout with week strip, start workout card, quick actions, activity tracker, and recent workouts
2. **Active workout** — Shows the focused workout logging view with exercise tab strip, set table, and Exercise Info section below
3. **Historic workout detail** — Shows a full workout breakdown view with stats, muscle filters, and exercise-by-exercise set details

---

## What Stays Unchanged

- 4-tab layout with center FAB
- Active workout as fullScreenCover (focused, no tab bar)
- FAB behavior and positioning
- Calendar, Charts, Settings tabs (all content unchanged)
- On-launch active workout resume logic
- All existing services, repositories, and data model
- Onboarding flow

---

## Services Available for Home Screen (no new services needed)

| Data | Existing Service |
|------|-----------------|
| Workouts for week strip dots | `workoutService` |
| This week session count | `workoutService` |
| Recent workout summaries | `workoutService` + `setService` + `exerciseService` |
| Copy previous exercises | `workoutService` + `setService` |
| Start workout flow | `workoutService.startWorkout()` + `setService.save()` |
| Estimated 1RM | `statsService` e1RM calculation |
| Historical e1RM comparison | `chartDataService` |
| Last workout for exercise | `setService` |
