# Tasks Directory

This directory contains work package (WP) prompt files with lane status in frontmatter.

## Work Packages

| WP   | Title                                                          | Lane    | Dependencies |
| ---- | -------------------------------------------------------------- | ------- | ------------ |
| WP05 | Foundation — New Models, Enums, 3-Tab Shell, Shared Components | planned | none         |
| WP06 | Breakdown Tab — Donut Chart + Service Method                   | planned | WP05         |
| WP07 | Workouts Tab — Bar Chart + Time Series Service                 | planned | WP05         |
| WP08 | Exercises Tab — Multi-Line Chart + Progress Service            | planned | WP05         |
| WP09 | Exercise Selection Modal + Preset Persistence                  | planned | WP05, WP08   |
| WP10 | Cleanup — Remove Old Code, Dead Types                          | planned | WP05–WP09    |

## Execution Order

1. WP05 (Foundation)
2. WP06 (Breakdown — simplest chart)
3. WP07 (Workouts — most complex service)
4. WP08 + WP09 (Exercises + Modal — parallel then wire)
5. WP10 (Cleanup)
