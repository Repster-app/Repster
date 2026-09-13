# SwiftData live-model fix: test gates

Use this as the short release checklist. The detailed reasoning and race markers stay in
`SWIFTDATA_LIVE_MODEL_FIX_SCOPING.md` and `LiveModelRaceReproTests.swift`.

## Now — Phases 1 + 4, plus Settings snapshots

Automated:

- iOS 17.5: onboarding race regression is clean.
- iOS 18.6: suggestion-engine and set/workout snapshot regressions are clean.
- iOS 18.6 and 26.3: the real SettingsViewModel toggle/read regression is clean; its pre-fix
  iOS 18.6 run crashed with the bug-3 signature.
- iOS 18.6: active-workout, suggestion and fatigue-learning suites pass.
- Test target builds with no new warnings from this change.
- `SwiftDataLiveModelBoundaryRatchetTests` passes with the current phased allowlist; its planted
  unlisted `HealthProfile` proof fails with a clear source location.
- Warmup volume/PR error-path tests show the saved snapshot after a rebuild throws.

Recorded 2026-09-12; cleanup gates rerun 2026-09-13:

- Settings regression: pre-fix crash on iOS 18.6; post-fix pass on iOS 18.6 and 26.3.1, 2,000
  rounds each.
- Positive controls on the cleanup rerun: unsafe profile writes still SIGSEGV on iOS 17.5;
  synthetic held live sets still crash (SIGABRT this run) with the non-zero-retain-count signature
  on iOS 18.6.
- Full iOS 26.3.1 cleanup suite: 913 total, 899 passed, 14 gated skips, 0 failures, read from
  `.xcresult`.

Manual (one short workout):

- Finish onboarding; relaunch and confirm unit/reps/RIR defaults persisted.
- Start a workout, switch exercises, log a set, refresh suggestions, finish it.
- Confirm title, notes, effort, timer and suggestion values remain correct.
- In Settings, change units, working/warmup rest, timer alert and Smart Suggestions; leave and
  reopen Settings to confirm each value persists.

## Next — Phase 5 (live sets → snapshots)

Automated:

- Add a real-path regression that drives the converted active/edit workout view models while
  repository saves overlap their snapshot reads; it must be clean on iOS 18.6 and iOS 26.3.
- The synthetic held-live-set positive control deliberately retains live sets and must keep
  crashing on iOS 18.6 after Phase 5.
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
- The source-ratchet allowlist is empty: repository protocols return no audited live model, and
  views/view models store none. Any new or stale entry fails the test.
- Phase 3 repository writes use insert-only APIs with DEBUG assertions that inserted models have
  no `modelContext`. Removing redundant explicit `@unchecked Sendable` conformances is optional
  warning cleanup; Xcode 26.3's `@Model` macro adds `Sendable` itself.
- Repeat the Phase 5 device workout once on the oldest supported real device available.
