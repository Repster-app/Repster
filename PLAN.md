# Metric / Imperial Unit Support Cleanup

## Document Intent
- This file is the current execution spec, not a chronological change log.
- It supersedes the earlier metric / imperial rollout draft and folds in the later Smart Suggestions, FitNotes, and UI-leak learnings.
- The key post-draft corrections are: imperial rounding must happen in displayed `lb` space, legacy history stays exact after conversion, FitNotes needs its own weight-column choice, and the remaining bugs are a broad presentation-layer audit rather than isolated screen-specific defects.

## Summary
- Finish the app-wide metric / imperial rollout using the existing `unitPreference`, with canonical storage unchanged: weight stays in `kg`, distance stays in meters, and increment values stay persisted canonically.
- Treat the remaining issues as one incomplete presentation-layer rollout, not as separate storage or stats bugs.
- Fix the real imperial rounding bug in Smart Suggestions and increment behavior, add an explicit FitNotes weight-column choice, and do one full audit of user-visible weight/distance surfaces so metric fallback does not keep leaking through older screens.

## Implementation Changes
- Shared unit boundary:
  - Keep `UnitConversion.swift` as the single source of truth for canonical/display conversion, parse helpers, user-facing unit labels, distance formatting, and increment resolution.
  - Replace the imperial increment list with `2.5, 5, 10, 15, 20, 25 lb`.
  - Add helpers to normalize legacy canonical increment values onto that supported imperial list for display/editing in imperial mode.
  - Add helpers to round weights in displayed `lb` space, then convert the rounded result back to canonical `kg`.
- Shared formatters:
  - Make `WorkoutSetPerformanceFormatter.swift` require the active `unitPreference` for display, performance labels, read-only fields, weight labels, and summary distance formatting.
  - Remove silent metric defaults from `WorkoutPrimaryMetric.formattedValue` so missed callers fail at compile time instead of quietly rendering `kg`.
  - Keep bodyweight-style `BW` behavior unchanged.
  - Keep read-only/history weights exact after conversion. Do not snap, reinterpret, or infer original unit for previously logged sets.
- Workout entry and Smart Suggestions:
  - Keep calculations canonical in `kg`, but round suggestions, applies, and `+/-` nudges in displayed-unit space when the user is in imperial mode.
  - Use the same increment resolution path for Smart Suggestions, exercise-specific increment overrides, app-default increment, and workout-entry nudges.
  - Keep the `45 lb` barbell helper in imperial mode and `20 kg` in metric mode.
- Increment UI and settings:
  - Update global default increment UI and per-exercise increment UI to show the supported imperial list in imperial mode instead of hard-coded metric values or approximate aliases.
  - Continue persisting increment values canonically in `kg`.
  - Normalize legacy metric-origin increment values when surfaced in imperial mode so the picker, displayed summary, and Smart Suggestions agree.
- User-visible surface audit:
  - Replace remaining hard-coded `kg`, `m`, and `km` UI in Home, Exercise Detail, Calendar, Charts, and Settings/editor surfaces with shared helpers.
  - This includes recent PRs, this month, recent workouts, copy previous, exercise history, exercise PRs, embedded exercise charts, calendar summary strips, calendar read-only exercise cards, workout charts, breakdown charts, chart navigator detail text, and increment summaries/pickers.
  - Read-only/home/calendar/exercise/chart view models should load `unitPreference` through `settingsService` and cache it locally, rather than formatting directly with metric assumptions.
- Distance behavior:
  - Metric read-only formatting stays `m` below `1000 m` and `km` at or above.
  - Imperial read-only formatting stays `ft` below `1000 ft` and `mi` at or above.
  - Imperial chart distance always uses miles.
  - `Min Pace` remains `m/s`.
- Import behavior:
  - Keep canonical normalization for all imports.
  - Replace FitNotes’ current hard-coded `Weight (kg)` precedence with an explicit FitNotes-specific weight-column choice: trust `Weight (kg)` or trust `Weight (lbs)` when both are present.
  - If the chosen FitNotes column is empty for a row, fall back to the populated weight column for that row.
  - Keep FitNotes distance parsing unchanged.
  - Keep Strong’s existing explicit unit-system chooser unchanged.
  - Update both onboarding and settings import flows so Strong and FitNotes each show the correct source-specific configuration UI and summary text.

## Interface Changes
- Extend `UnitConversion` with public helpers for:
  - supported imperial increment options
  - canonical/display increment normalization
  - display-space rounding for imperial weight behavior
  - user-facing weight/distance/increment labels
- Change `WorkoutSetPerformanceFormatter` public display APIs to require explicit `unitPreference`.
- Change `WorkoutPrimaryMetric.formattedValue` to require explicit `unitPreference`.
- Add `settingsService` and cached `unitPreference` state to the Home, Calendar, Exercise Detail, and Chart view models that currently format values directly.
- Extend the import configuration API so source-specific options can represent:
  - Strong unit-system choice
  - FitNotes weight-column choice

## Test Plan
- Formatter tests:
  - metric vs imperial weight labels
  - metric vs imperial distance labels
  - exact read-only/history conversion behavior
  - aggregate workout metric formatting
  - bodyweight-style set behavior
  - chart-distance behavior in miles
  - `Min Pace` remaining `m/s`
- Smart Suggestions and workout-entry tests:
  - imperial recommendations never emit stray values like `60.63 lb`
  - imperial apply/nudge behavior rounds in displayed-unit space
  - global default increment and exercise increment overrides resolve through the same path
  - `45 lb` helper behavior in imperial mode
- Surface tests:
  - recent PRs, this month, recent workouts, copy previous
  - exercise history, PRs, and embedded charts
  - calendar summary and read-only cards
  - workout charts and breakdown charts
  - increment pickers and increment summary text
- Import tests:
  - FitNotes chooses `kg` when selected
  - FitNotes chooses `lbs` when selected
  - FitNotes falls back to the populated column when the selected one is empty
  - FitNotes distance parsing remains unchanged
  - Strong import behavior remains unchanged
- Audit gate:
  - final grep-based sweep for user-visible hard-coded `kg`, `km`, and `m` strings in Home, Exercise, Calendar, Charts, and Settings/editing flows, excluding internal comments/logs and intentional technical/admin text

## Assumptions
- No schema changes, migrations, or rebuild-only operations are required.
- Logged history remains truthful canonical data; this pass does not try to “gym-snap” older `kg -> lb` history values.
- Internal logs/comments may remain metric; the target is user-visible UI and import configuration behavior.
- Implementation order should be:
  - shared helpers and explicit formatter interfaces
  - Smart Suggestions / increment rounding
  - import configuration cleanup
  - full UI surface audit
  - tests and final sweep
