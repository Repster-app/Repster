# Workout App — New Agent Starter Prompt

Copy everything below the line and paste it as your first message to the new agent.

---

I'm building an iOS strength training app. I have a complete set of project documentation that I need you to use as the foundation for setting up the project with spec-kitty (a spec-driven development CLI tool).

## Your task

1. **Read all 7 files** in the project folder before doing anything else:
   - `specdoc.md` — **The authoritative source of truth.** v1.4. Complete schema, PR logic, implementation contracts. If anything conflicts with this, the specdoc wins.
   - `AGENT_RULES.md` — v1.2. Mandatory rules for AI agents. Architecture layers, anti-patterns, performance rules, v1 scope, what NOT to do.
   - `design-system.md` — Color tokens, typography, spacing, component patterns. Dark mode only for v1. System font for v1 (not DM Sans). Custom keyboard is v1.1.
   - `screen_tree.md` — All screens, navigation flows, gestures, reused components. The FAB always opens Exercise List (context-aware based on active workout).
   - `tech_stack_and_architecture.md` — Platform decisions (iOS 17+, SwiftUI, SwiftData, MVVM). All locked.
   - `project_overview.md` — Index document. Read this for a high-level map of everything.
   - `seed_exercises.json` — 67 default exercises with full metadata (bodyweightFactor, trackingType, muscle groups, equipment, rest times). Ships with the app on first launch.

2. **Install and initialize spec-kitty** for this project:
   ```
   pip install spec-kitty-cli
   spec-kitty init --here --ai claude
   ```

3. **Create the constitution** using `/spec-kitty.constitution` with these core principles derived from the documentation:
   - Architecture: Views → ViewModels → Services → Repositories → SwiftData. Never skip layers.
   - All weight storage in kg. All distance in meters. All duration in seconds. Convert only at the UI boundary.
   - PRs and stats computed at write-time, never at read-time. No startup rebuilds.
   - Database aggregation (SQL SUM/MAX/GROUP BY), never iterate in Swift.
   - Float comparisons for PRs use integer grams conversion.
   - `trackingType` is immutable once sets exist.
   - Use `hasData` (computed) for analytics/PRs, not `completed` (stored boolean).
   - Hard delete only, no soft delete. Everything rebuildable from raw sets.
   - Dark mode only for v1. System font. SF Symbols. No third-party UI libs.
   - Single `PerformanceRecord` table for all PR types.
   - Sets persist immediately on entry. "Finish Workout" is a UI action, not a data commit.
   - Do NOT add fields, tables, enums, services, or screens not documented in the specdoc. Flag gaps as questions.

4. **Create features in this order** using `/spec-kitty.specify` for each. When specifying each feature, reference the exact sections of the documentation that define it — do NOT describe the feature from scratch or invent requirements:

   | # | Feature | Key doc references |
   |---|---------|-------------------|
   | 001 | Xcode project + SwiftData models | Create the Xcode project (iOS 17+, SwiftUI, bundle ID TBD). Then implement all SwiftData @Model classes from specdoc Section 6 (all tables), all enums from Appendix A, following AGENT_RULES Section 3 (naming, units, effectiveWeight). File structure per AGENT_RULES Section 2. |
   | 002 | Repositories + indexes | Repository protocols and implementations per tech_stack Section 4.3. Required indexes per AGENT_RULES Section 5.4. Layer rules per AGENT_RULES Section 2. |
   | 003 | PR Service | Full PR pipeline per specdoc Section 7 (all subsections including 7.0 scope/constraints). PR rules per AGENT_RULES Section 4. Integer grams comparison per AGENT_RULES Section 3.4. |
   | 004 | Set + Stats Services | SetService orchestration per specdoc Sections 4 and 8. Service responsibilities per AGENT_RULES Section 6. Performance rules per AGENT_RULES Section 5. |
   | 005 | Workout + Exercise + Bodyweight Services | Workout lifecycle (status field) per specdoc Sections 3 and 6.2. Exercise CRUD and trackingType immutability per specdoc Section 5. Service responsibilities per AGENT_RULES Section 6. |
   | 006 | Active Workout Screen | screen_tree Section 3 (FAB → Exercise List → Active Workout). Set table columns per AGENT_RULES Section 7.5. Design per design-system Section 6.3. Active workout flow per AGENT_RULES Section 7.3. Rest timer per specdoc Section 9 (rest timer behavior). PR badges per AGENT_RULES Section 7.4. |
   | 007 | Exercise List + Detail | Exercise list from screen_tree Section 3 (search, filter, sort, browse vs selection mode). Exercise detail from screen_tree Section 2 (History/PRs/Charts tabs — reused component). Create/edit exercise sheet from screen_tree Section 3. |
   | 008 | Calendar Tab | screen_tree Section 2. Muscle group dots from Workout.muscleGroupsWorked per specdoc Section 6.2. Workout detail inline below calendar. |
   | 009 | Charts Tab | screen_tree Section 4. Chart performance strategy per specdoc Section 8.10. Time-series aggregation per specdoc Section 11.1. |
   | 010 | Settings + Onboarding | Settings from screen_tree Section 5. Onboarding (5 screens) from screen_tree Section 6. User settings per specdoc Section 9. Onboarding rules per AGENT_RULES Section 11. |
   | 011 | CSV Import + Export | Export format per specdoc Section 12. Import mapping per tech_stack Section 11 (NOTE: Kind column maps to Exercise.trackingType, NOT Set.setType — all imported sets default to setType=working). Import rules per AGENT_RULES Section 9. |
   | 012 | Seed Exercise Library | Load seed_exercises.json on first launch. 67 exercises with full metadata. Ensure trackingType, bodyweightFactor, primaryMuscle, and equipment are all correctly mapped to the Exercise model. |

5. **For each feature**, follow the full spec-kitty workflow:
   - `/spec-kitty.specify` → reference docs, don't reinvent
   - `/spec-kitty.plan` → tech approach scoped to that feature
   - `/spec-kitty.tasks` → work packages
   - `/spec-kitty.implement` → build it
   - `/spec-kitty.review` → validate against spec
   - `/spec-kitty.merge` → merge to main

## Critical rules

- **Do NOT invent features, fields, or behaviors** not in the documentation. The specdoc is the single source of truth for all schema. AGENT_RULES.md is the source of truth for coding patterns.
- **The `Set` model must be named `WorkoutSet`** in Swift to avoid collision with Swift's `Set` type.
- **Only build v1 scope.** Check AGENT_RULES Section 0 for what ships in v1 vs v1.1. Programs tab is an empty state placeholder. Custom keyboard is v1.1. RPE input is deferred (RIR only). Superset grouping has no v1 UI (schema only).
- **Read the anti-patterns** in AGENT_RULES Section 10 before writing any code. These exist because competitor apps have severe performance issues.
- **Xcode project creation is part of feature 001.** The project should target iOS 17+, use SwiftUI lifecycle, and follow the file organization in AGENT_RULES Section 2.

Start by reading all 7 files, then initialize spec-kitty.
