# Quickstart: CSV Import + Export

**Feature**: 011-csv-import-export | **Date**: 2026-03-01

## New Files to Create

| # | File | Type | Purpose |
|---|------|------|---------|
| 1 | `Reppo/Core/Utilities/CSVParser.swift` | Utility | RFC 4180 CSV parsing (pure Swift, no SwiftData) |
| 2 | `Reppo/Core/Services/Protocols/ImportServiceProtocol.swift` | Protocol | ImportService contract |
| 3 | `Reppo/Core/Services/Protocols/ExportServiceProtocol.swift` | Protocol | ExportService contract |
| 4 | `Reppo/Core/Services/ImportService.swift` | Service (actor) | CSV import orchestration, bulk insert, rebuild trigger |
| 5 | `Reppo/Core/Services/ExportService.swift` | Service (actor) | CSV export generation |
| 6 | `Reppo/Features/Settings/Views/ImportView.swift` | View | File picker, preview, progress, results |
| 7 | `Reppo/Features/Settings/Views/ExportView.swift` | View | Export trigger, ShareLink |
| 8 | `Reppo/Features/Settings/ViewModels/ImportViewModel.swift` | ViewModel | @Observable, import state machine |
| 9 | `Reppo/Features/Settings/ViewModels/ExportViewModel.swift` | ViewModel | @Observable, export state |

## Existing Files to Modify

| # | File | Change |
|---|------|--------|
| 1 | `Reppo/Core/Services/ServiceContainer.swift` | Add `importService` and `exportService` properties + initialization |
| 2 | `Reppo/Features/Settings/Views/SettingsView.swift` | Replace "Coming Soon" stubs with NavigationLinks to ImportView/ExportView |
| 3 | `Reppo.xcodeproj/project.pbxproj` | Add all new file references |

## File Structure

```
Reppo/
├── Core/
│   ├── Utilities/
│   │   └── CSVParser.swift                        # NEW
│   ├── Services/
│   │   ├── ImportService.swift                    # NEW
│   │   ├── ExportService.swift                    # NEW
│   │   ├── Protocols/
│   │   │   ├── ImportServiceProtocol.swift         # NEW
│   │   │   └── ExportServiceProtocol.swift         # NEW
│   │   └── ServiceContainer.swift                 # MODIFY
│   └── ...
│
├── Features/
│   └── Settings/
│       ├── Views/
│       │   ├── SettingsView.swift                  # MODIFY
│       │   ├── ImportView.swift                    # NEW
│       │   └── ExportView.swift                    # NEW
│       └── ViewModels/
│           ├── ImportViewModel.swift               # NEW
│           └── ExportViewModel.swift               # NEW
│
└── ...
```

## Dependency Order

Build in this order to avoid compile errors:

1. `CSVParser.swift` — no dependencies, pure utility
2. `ImportServiceProtocol.swift` + `ExportServiceProtocol.swift` — depend on CSVParser types
3. `ImportService.swift` — depends on protocol + repositories + PRService + StatsService
4. `ExportService.swift` — depends on protocol + repositories
5. `ServiceContainer.swift` modification — depends on ImportService + ExportService
6. `ImportViewModel.swift` + `ExportViewModel.swift` — depend on service protocols
7. `ImportView.swift` + `ExportView.swift` — depend on ViewModels
8. `SettingsView.swift` modification — depends on ImportView + ExportView

## Verification Checklist

### Build Verification
- [ ] Project compiles with no errors after adding all files
- [ ] No SwiftData `@Model` changes (no migration needed)
- [ ] ServiceContainer initializes without crashes

### Import Verification
- [ ] File picker opens and accepts `.csv` files
- [ ] Preview shows first 5 rows with column mapping
- [ ] Import of test CSV creates correct Workouts (one per date)
- [ ] Import creates new Exercises for unknown names
- [ ] Existing exercises matched case-insensitively (no duplicates)
- [ ] WorkoutSets created with correct field mapping
- [ ] Weight (lbs) column is ignored
- [ ] Kind column infers Exercise.trackingType (not Set.setType)
- [ ] All imported sets have setType = .working
- [ ] effectiveWeight computed correctly
- [ ] Progress indicator updates during import
- [ ] StatsService.rebuildAll() runs after import
- [ ] PRService.rebuildAll() runs after import
- [ ] Result summary shows correct counts
- [ ] Malformed rows skipped with error reporting

### Export Verification
- [ ] Export generates CSV with all data
- [ ] CSV header matches expected 11 columns
- [ ] Weight values in kg
- [ ] Share sheet appears with CSV file
- [ ] Exported CSV can be re-imported with no data loss (SC-004)

### Performance Verification
- [ ] Import of 12,000 rows completes within 60 seconds (SC-001)
- [ ] UI remains responsive during import (not frozen)
- [ ] Memory stays within bounds during bulk insert

### Edge Cases
- [ ] Empty CSV (header only) — shows appropriate message
- [ ] CSV with only invalid rows — shows error count, no crash
- [ ] Duplicate exercise names across rows — matched, not duplicated
- [ ] Notes containing commas — parsed correctly (quoted field)
- [ ] UTF-8 encoded file — handles correctly
