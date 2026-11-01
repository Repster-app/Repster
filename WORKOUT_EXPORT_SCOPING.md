# Single-workout export — scoping

**Status:** scoped and **built 2026-10-22**, uncommitted. Full suite green (957 tests, 0
failures, 14 skipped; iOS 26.3 sim). The device pass (§8) is outstanding. Target: 1.6. Free
(it is not part of the paywall quota).
**Origin:** the user wants to export one workout so an outside system (a coach, an AI, a
spreadsheet or a script) can evaluate it. Today the only export is the full backup.
**Decided with the user (2026-10-22):**
- The format is **JSON**.
- Sets that were never ticked are **included and marked `"completed": false`**. They are not
  dropped.
- Weights use the **user's unit setting**, and the file states which unit that is.

Everything else here is a default the build follows. §9 lists the calls I made, so any of them
can be reversed.

---

## 1. What exists today

**There is one export: Settings → Data & Backups → Export Backup.**
`WorkoutHistoryBackupService.exportBackup()`
([ExportService.swift:42](Repster/Core/Services/ExportService.swift:42)) writes every workout, set,
exercise, template and fatigue-learning row to a `.repsterbackup` file. Nothing can export a
single workout.

**Both screens that show a saved workout already hold the whole workout in memory.** Each one
loads a `WorkoutDetail` ([CalendarViewModel.swift:94](Repster/Features/Calendar/ViewModels/CalendarViewModel.swift:94)):
a `WorkoutSnapshot` and its `ExerciseGroup`s, each holding a `ChartExerciseData` and *every*
`ChartSetData` row for that exercise. `fetchChartSets(for:)`
([SetRepository.swift:419](Repster/Core/Repositories/SetRepository.swift:419)) has no completion
filter. These are snapshots, not live `@Model`s. That means:
- The export needs **no new fetch and no service**. It is a pure function of a value the screen
  already holds.
- It cannot reach the cross-actor crash class (BACKUP_EXPORT_SCOPING.md F1), because no model
  object is touched.

**The two screens:**

| Screen | Where | Menu |
|---|---|---|
| Workout detail (reached from Home, the Workouts tab and the Exercises tab) | [WorkoutDetailFromHomeView.swift:86](Repster/Features/Home/Views/WorkoutDetailFromHomeView.swift:86) | Toolbar "…": Edit Workout, Save as Template, Delete |
| Calendar day pane | [CalendarWorkoutDetailView.swift:197](Repster/Features/Calendar/Views/CalendarWorkoutDetailView.swift:197), wired in [CalendarView.swift:318](Repster/Features/Calendar/Views/CalendarView.swift:318) | One "…" per workout header, built from optional callbacks |

The share-card icon already sits next to both menus. It uses the same pattern this feature needs:
the screen sets a `WorkoutDetail?` binding and one shared modifier (`.shareWorkoutCard`) does
the rest.

**There is a precedent for a one-item export.** Templates have "Export Template" in their "…"
menu ([TemplateDetailView.swift:65](Repster/Features/Templates/Views/TemplateDetailView.swift:65)).
It writes a temp file and presents a `UIActivityViewController`.

---

## 2. The one thing that must not happen

**The file must not be a backup, and must not look like one.** Restore is a *replace*. It
deletes every workout, set, stat and record before inserting
([ExportService.swift:209](Repster/Core/Services/ExportService.swift:209)). A one-workout file
that restore could read would turn into "delete my history except this workout".

The guard has two layers:
- **The extension is `.json`, not `.repsterbackup`.** The Restore picker only accepts the two
  backup UTIs ([ExportView.swift:358](Repster/Features/Settings/Views/ExportView.swift:358)), so
  the file cannot even be selected there.
- **The top-level shape is different.** There is no `version`, `workouts` or `sets` key, so even
  a renamed file fails `decodeArchive` before anything is deleted. A test pins this.

The backup format would also be the wrong format for an outside reader. It carries internal
columns: fatigue-learning rows, `cachedPRStatus` (never written), `targetWeight` (never
written), and kg everywhere regardless of the user's setting.

---

## 3. What the user sees

- **"Export Workout"** in the "…" menu on both screens. The icon is `arrow.up.doc`, so it is not
  confused with the share-card icon (`square.and.arrow.up`) right next to it. It sits after
  "Save as Template" and before the destructive divider.
- **Shown only for finished workouts** (`status == .completed`). The Calendar lists in-progress
  workouts (SHARE_FROM_HISTORY_SCOPING.md). Exporting one mid-session would produce a file that
  is wrong a minute later.
- Tapping it opens the system share sheet straight away, with no intermediate screen. From
  there the user can Save to Files, AirDrop, Mail, or send it to any app that takes a file
  (ChatGPT, Claude, a coach's app, and so on).
- If the file cannot be written, the user gets an alert: "Export Failed" plus the error text.

The preview-sheet step that the share card has is deliberately left out. There is nothing to
toggle.

---

## 4. File format (schema version 1)

`repster-workout-2026-09-10-push-day-a.json`: the date plus a sanitised title. It is
pretty-printed with sorted keys, so two exports of the same workout differ only in `exportedAt`.

```json
{
  "app" : { "name" : "Repster", "version" : "1.6" },
  "conventions" : [ "…short plain-English notes, see §5…" ],
  "exportedAt" : "2026-10-22T14:03:00+02:00",
  "format" : "repster.workout",
  "schemaVersion" : 1,
  "units" : { "distance" : "m", "duration" : "s", "weight" : "kg" },
  "workout" : {
    "id" : "…uuid…",
    "title" : "Push Day A",
    "date" : "2026-09-10T18:00:00+02:00",
    "startTime" : "…", "endTime" : "…",
    "durationSeconds" : 3840,
    "perceivedEffort" : 7,
    "notes" : "…",
    "countsTowardProgression" : true,
    "summary" : { "exerciseCount" : 4, "setCount" : 12, "completedSetCount" : 10 },
    "exercises" : [
      {
        "name" : "Barbell Bench Press",
        "exerciseId" : "…uuid…",
        "equipment" : "barbell",
        "trackingType" : "weightReps",
        "primaryMuscle" : "chest",
        "secondaryMuscles" : [ "triceps" ],
        "movementPattern" : "press",
        "unilateral" : false,
        "bodyweightFactor" : 0,
        "supersetGroup" : 1,
        "countsTowardProgression" : true,
        "sets" : [
          {
            "number" : 1,
            "type" : "working",
            "completed" : true,
            "weight" : 100, "effectiveWeight" : 100,
            "reps" : 5, "rir" : 2,
            "estimatedOneRepMax" : 116.7,
            "personalRecord" : "current",
            "target" : { "repMin" : 5, "repMax" : 8, "rir" : 2 },
            "restSeconds" : 180,
            "startedAt" : "…", "completedAt" : "…",
            "notes" : "…"
          }
        ]
      }
    ]
  }
}
```

**Optional values are omitted rather than written as `null`.** `completed` is always present on
every set.

### Field decisions

| Field | Rule | Why |
|---|---|---|
| `title` | `displayTitle` | What the user sees on screen, including the auto "Evening Workout" title. |
| Dates | ISO 8601 with the device's current UTC offset | An evaluator reading "07:10+02:00" knows it was a morning session. `Z` hides that. |
| `weight`, `effectiveWeight`, `estimatedOneRepMax` | Converted with `UnitConversion.displayedWeight` and rounded to 2 dp, the same precision `formatWeight` shows | Stored kg turned into lb gives values like 220.46200000000002. |
| `effectiveWeight` | Only when it differs from `weight` | For most sets they are equal. The difference is the logged bodyweight share (`SetService.computeEffectiveWeight`). |
| `distance` | **Always metres** | The app *stores and accepts input* in metres for every user. `handleDistanceChange` parses the field with no conversion ([SetTableView.swift:736](Repster/Features/Workout/Views/SetTableView.swift:736)). Only the read-only display turns it into ft/mi. Metres is what the user typed. Mixed ft/mi per row would be unreadable to a machine. |
| `number` | Position within the exercise, 1-based, in `orderInExercise` order | `orderInExercise` is not contiguous once sets are deleted. |
| `type` | `SetType` raw value (`warmup`, `working`, `dropset`, …) | It is already a stable lowercase vocabulary. |
| `completed` | `ChartSetData.completed`, always written | The decision with the user. See §6. |
| `personalRecord` | `.current` → `"current"`, `.matched` → `"matched"`, `.previous` → `"beaten"`; `.dominated` and nil are omitted | Mirrors the app's badges, plus "beaten", so that a PR set on that day still shows up. `dominated` is a rep-count technicality that has no badge, and calling it a PR would overclaim. Reads `prStatus`, never the legacy `cachedPRStatus` (always nil). |
| `target` | `preferredTargetRepBounds` (override first, then template) plus `targetRIR`; omitted when all are nil | The same resolver the set table uses. `targetWeight` and `targetRPE` are left out: nothing in the app writes them. |
| `rir` / `leftRIR` / `rightRIR` | Raw value | 5 means "5+" (the chip is a floor). Stated in `conventions`. |
| `rpe` | Raw value when present | Only CSV import writes it. |
| `restSeconds` | `restDurationSeconds` | Nil unless the timer ran to zero (project_rest_duration_blind_spot). Stated in `conventions`: absent means "not measured", not "no rest". |
| `supersetGroup` | 1, 2, … in order of first appearance; omitted when the exercise isn't grouped | A UUID is meaningless outside the app. A small number shows the pairing. |
| `countsTowardProgression` | Workout: `!excludesEntireWorkoutFromProgressionHistory`. Exercise: `!excludesFromProgressionHistory(exerciseId:)` | Without it an evaluator can't explain why a heavy set "isn't a PR" (project_excluded_workouts_pr_gap). |
| `unilateralRepCounting` | `perSide` / `totalAcrossSides`, only when `unilateral` | Needed to read `reps` against `leftReps`/`rightReps`. |
| `summary.setCount` / `completedSetCount` | Every exported row / rows with `completed` | See §6 for why these can differ from the on-screen count. |
| `app.version` | `CFBundleShortVersionString` | Lets a reader tie a file to the build that wrote it. |

**Left out on purpose:** set and workout `createdAt`/`updatedAt`, `orderInWorkout`, fatigue-model
fields (`fatigueRate`, `recoveryConstant`, learning counters), `healthKitWorkoutUUID`,
`programId`, `excludeFromPRs` on sets, and per-exercise stats. None of them helps an evaluator
judge the session. A later schema version can add any of them without breaking readers.

---

## 5. `conventions`

A short array of plain sentences in the file itself. The reader is often an AI or a person
with no access to this doc, and four of these fields are routinely misread:
- Units, and that distance is always metres.
- `completed: false` means the set was planned or pre-filled but never ticked. Don't count it as
  performed.
- RIR 5 means 5 or more.
- `effectiveWeight` includes the logged bodyweight share.
- An absent `restSeconds` means it wasn't measured.
- What the three `personalRecord` values mean.
- `perceivedEffort` is session RPE on a 1–10 scale.

---

## 6. Edge cases

1. **Ghost rows from Copy Previous** (UNPERFORMED_SETS_SCOPING.md). They are exported with
   their values and `"completed": false`. The detail screen's set count uses `hasData`, which
   *does* count them. So `summary.completedSetCount` can be lower than the number on screen. That
   is the file being right and the screen being wrong. It is not a bug in this feature.
2. **An exercise added and never done.** Exported, with every set `completed: false`. The share
   card hides it; an export shouldn't.
3. **An empty finished workout** (project_free_tier_behaviour: the first free workout often is
   one). It exports with `exercises: []`. The file is harmless and truthful.
4. **Sets whose exercise was deleted.** `ExerciseGroup.build` drops sets it can't resolve
   ([CalendarViewModel.swift:45](Repster/Features/Calendar/ViewModels/CalendarViewModel.swift:45)).
   The detail screen hides them too, so the export matches the screen. Known limitation; not
   fixed here.
5. **The same exercise added twice** (project_duplicate_exercise_add). Grouping is by
   `exerciseId`, so all its sets land in one exercise in `orderInExercise` order. The file
   shows sets the screen currently hides, which is better than the screen.
6. **Supersets of three** (project_supersets_direction). They get one group number, so trios
   need no special case.
7. **Unit setting changed after the workout.** The file uses today's setting. Stored values
   are kg, so the conversion is exact either way.
8. **The workout is deleted while its screen is open.** The export reads the snapshot already
   on screen, so it still exports what was shown. That is acceptable.
9. **Bodyweight exercise with a blank weight.** `weight` is nil, so `weight` and
   `effectiveWeight` are both omitted. The data is reported as it is
   (project_bodyweight_suggestions).

---

## 7. Analytics

One event, **`workout exported`**, fired only when the share sheet reports a completed share.
That is the same rule as `share card shared`, since a tap-fired event would count taps.

| Property | Values |
|---|---|
| `entry_point` | `calendar` / `workout_detail` (same values as the share card) |
| `destination` | `UIActivity.ActivityType` raw value, or `unknown` |

`destination` answers the question this feature rests on: *which* outside systems people
actually send workouts to. No workout content is sent.

---

## 8. Build plan

| # | Change | File |
|---|---|---|
| 1 | `WorkoutExport` (Encodable schema) + `WorkoutExportBuilder.make(detail:unitPreference:…)` + `encode` + `filename` | new `Repster/Features/Workout/Views/WorkoutExportBuilder.swift` |
| 2 | `.exportWorkout(item:entryPoint:)` modifier: write temp file → activity sheet with completion → analytics → error alert | new `Repster/Features/Workout/Views/WorkoutExportPresenter.swift` |
| 3 | Menu item + `detailToExport` state | `WorkoutDetailFromHomeView.swift` |
| 4 | `onExport` callback (defaults to nil) + menu item | `CalendarWorkoutDetailView.swift`, `CalendarView.swift` |
| 5 | `workout exported` event + helper | `AnalyticsServiceProtocol.swift`, `POSTHOG_ANALYTICS_GUIDE.md` |
| 6 | Tests | new `RepsterTests/WorkoutExportTests.swift` |
| 7 | Register the three new files | `project.pbxproj` |

**Temp files** go in their own `tmp/WorkoutExports/` directory, which is cleared on each export,
the same way the backup export does it. The modifier follows `ShareWorkoutCardModifier`. The
activity sheet is a small private representable with a completion handler. Promoting the share
card's private one is the consolidation job that
[TemplateSharing.swift:6](Repster/Features/Templates/Views/TemplateSharing.swift:6) already
parks, so it's not done here.

### Tests (RepsterTests/WorkoutExportTests.swift)
- Never-ticked rows are present with `completed: false`, and the summary counts are right.
- An exercise with zero completed sets is still exported.
- Imperial converts weight and e1RM to lb, rounded. Distance stays in metres. `units` says so.
- Exercises are in workout order and sets are numbered 1…n even when `orderInExercise` has
  gaps.
- `personalRecord` mapping: current/matched/previous are mapped, dominated and nil are omitted.
- Target resolution: the override wins over the template.
- Superset numbering: two groups get 1 and 2, and an ungrouped exercise gets no key.
- Progression exclusion at workout and exercise level.
- Dates carry the injected time zone's offset.
- The encoded file is valid JSON, has no `null`, and `completed` is present on every set.
- **Restore rejects the file:** decoding it as `WorkoutHistoryArchive` with restore's own
  decoder settings throws. That decode is the first step of both `previewBackup` and
  `restoreBackup` (`decodeArchive`), and nothing is deleted before it. The test mirrors the
  decoder rather than building the whole backup service.
- Filename: date plus sanitised title, `.json`, no path characters.

### Device pass (outstanding until done on a phone)
1. Open a finished workout from Home → "…" → Export Workout → Save to Files. Open the file in
   Files and check that it reads.
2. Calendar → a day with two workouts → export the second one. Check it is the right workout.
3. Send to ChatGPT or Claude: check the app accepts a `.json` attachment.
4. Switch the unit setting to lb and export again. Check the weights and `units`.
5. Confirm the "…" menu has no Export item on an in-progress workout in the Calendar.

---

## 9. Calls I made (reversible)

| # | Call | Alternative |
|---|---|---|
| C1 | Distance is always metres, even for lb users | Use ft/mi. That would put the unit the user never typed into the file. |
| C2 | `personalRecord` maps `previous` → `"beaten"` | Export only `current`, like the share card. |
| C3 | Include the `conventions` block | Leave the file bare and rely on field names. |
| C4 | Export only finished workouts | Allow in-progress workouts too. |
| C5 | Include one analytics event | No event. |
| C6 | Share sheet straight away, no preview screen | Add a preview with toggles (hide notes, and so on). |

## 10. Not in this version
- Export from the summary sheet right after finishing.
- Exporting several or all workouts as this format. The schema has a single `workout` key
  today. A later version could add `workouts: []` under a new `schemaVersion`.
- CSV or plain-text variants.
- Importing this format back into Repster.
