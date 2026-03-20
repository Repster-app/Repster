# SwiftData Cross-Actor Audit

This note tracks places where repository actors currently return live SwiftData `@Model` objects and a different actor or context then reads those properties later.

## Fixed in this change

| Area | Status | Fix |
| --- | --- | --- |
| `ChartDataService` | Fixed | Charts now read `ChartSetData`, `ChartExerciseData`, `ChartExerciseStatsData`, and scalar workout dates produced inside repository actors. |

## Remaining hotspots

| Service | Current model crossing | Likely fix pattern |
| --- | --- | --- |
| `PRService` | Reads `WorkoutSet`, `PerformanceRecord`, `Exercise`, and `HealthProfile` instances returned from repository actors. | Add PR-focused snapshot/scalar reads for candidate sets, existing PR rows, exercise metadata, and settings values. |
| `StatsService` | Reads `Exercise`, `ExerciseStats`, and `WorkoutSet` models after async repository calls. | Return aggregate snapshots/scalars and stats snapshots instead of live models for rebuild/read paths. |
| `WorkoutService` | Reads `Workout` models returned from `WorkoutRepository`. | Add workout summary snapshots and scalar lookup helpers for status/date checks. |
| `ExerciseService` | Reads `Exercise`, `ExerciseStats`, and `PerformanceRecord` models after repository hops. | Add exercise detail snapshots and scalar existence/count helpers. |
| `TemplateService` | Reads `WorkoutTemplate`, `TemplateExercise`, `TemplateSet`, `Workout`, `WorkoutSet`, and `Exercise` models across actor boundaries. | Add template export/import DTO snapshots returned inside repository actors. |
| `ExportService` | Reads live `Exercise` and `WorkoutSet` models while building export rows. | Add export row snapshots or CSV DTO snapshots from repository actors. |
| `ImportService` | Reads live `Exercise` and `Workout` models for dedupe/matching logic. | Add lightweight import lookup snapshots keyed by ID/name/date. |
| `BodyweightService` | Reads `HealthProfile` and `BodyweightEntry` models outside the owning repository actor. | Add scalar settings/profile snapshots and bodyweight entry snapshots for list/read flows. |

## Notes

- `@unchecked Sendable` on SwiftData models suppresses compiler complaints but does not make cross-actor property access safe.
- The risk is highest anywhere a service stores, filters, sorts, or groups repository-returned `@Model` objects after an `await`.
- Recommended follow-up order: `PRService`, `StatsService`, `WorkoutService`, then the template/import-export paths.
