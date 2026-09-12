# SwiftData live-model fix: test gates

Use this as the short release checklist. The detailed reasoning and race markers stay in
`SWIFTDATA_LIVE_MODEL_FIX_SCOPING.md` and `LiveModelRaceReproTests.swift`.

## Now — Phases 1 + 4

Automated:

- iOS 17.5: onboarding race regression is clean.
- iOS 18.6: suggestion-engine and set/workout snapshot regressions are clean.
- iOS 18.6: active-workout, suggestion and fatigue-learning suites pass.
- Test target builds with no new warnings from this change.

Manual (one short workout):

- Finish onboarding; relaunch and confirm unit/reps/RIR defaults persisted.
- Start a workout, switch exercises, log a set, refresh suggestions, finish it.
- Confirm title, notes, effort, timer and suggestion values remain correct.

## Next — Phase 5 (live sets → snapshots)

Automated:

- Held-set race regression becomes clean on iOS 18.6 and iOS 26.3.
- Active and edit workout suites plus snapshot/model parity tests pass.

Manual (full device pass):

- Add, edit, uncomplete, delete and reorder sets; add/remove/reorder exercises.
- Check supersets, rest timer, PR badge promotion/demotion and suggestion refresh.
- Edit a finished workout, then relaunch and verify the saved result.

## Then — Phases 2 + 3 (remaining writes)

Automated:

- Bug-2 set/PR/stats controls are clean on iOS 17.5.
- PR, stats, template, workout, bodyweight and fatigue-learning suites pass.

Manual:

- Create a PR, edit/delete its set, and confirm the badge and charts rebuild.
- Change workout exclusions and settings; relaunch and verify persistence.

## Final — Phase 6 / release gate

- Full suite on iOS 17.5, 18.6 and 26.3, one run at a time; read totals from `.xcresult`.
- No remaining `@unchecked Sendable` on models whose crossings are closed.
- Repeat the Phase 5 device workout once on the oldest supported real device available.
