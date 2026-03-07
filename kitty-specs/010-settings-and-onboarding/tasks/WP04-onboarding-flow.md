---
work_package_id: "WP04"
subtasks:
  - "T019"
  - "T020"
  - "T021"
  - "T022"
  - "T023"
  - "T024"
  - "T025"
title: "Onboarding Flow"
phase: "Phase 2 - Onboarding"
lane: "doing"
assignee: ""
agent: "claude-opus"
shell_pid: "56690"
review_status: ""
reviewed_by: ""
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-28T18:49:28Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP04 – Onboarding Flow

## Implementation Command

```bash
spec-kitty implement WP04 --base WP01
```

## Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

Build the 5-screen first-launch onboarding flow that guides new users through initial setup:

1. **OnboardingStep** enum — view-layer step progression tracker.
2. **OnboardingViewModel** — manages step state, user selections, and saves preferences on completion.
3. **OnboardingContainerView** — TabView-based step container with Next/Skip/Finish navigation.
4. **5 step views** — Welcome, Units, Formula, Bodyweight (optional), Import prompt (stub).

**Success criteria**:
- First launch: onboarding appears with 5 steps.
- All steps are skippable (except Welcome which has only "Get Started").
- User selections (unit, formula, bodyweight) persist to HealthProfile via SettingsService.
- Skipped steps use sensible defaults (metric, Epley, no bodyweight, no import).
- After completion, `@AppStorage("hasCompletedOnboarding")` is set to `true`.
- Re-launch: onboarding does NOT show again.
- Onboarding completes in under 2 minutes (SC-002).

## Context & Constraints

**Design documents**:
- `kitty-specs/010-settings-and-onboarding/plan.md` — OnboardingViewModel spec, view hierarchy, data flow
- `kitty-specs/010-settings-and-onboarding/research.md` — RQ-1 (onboarding persistence), RQ-2 (formula options)
- `kitty-specs/010-settings-and-onboarding/data-model.md` — OnboardingStep enum definition, SettingsService protocol
- `kitty-specs/010-settings-and-onboarding/spec.md` — User Story 5, acceptance scenarios, edge cases

**Architecture rules**:
- `@Observable` ViewModels, all data via services.
- TabView with `.tabViewStyle(.page(indexDisplayMode: .never))` — no system page dots (custom indicators).
- Manual Next/Skip/Finish buttons — user cannot swipe between pages (controlled navigation).
- `@AppStorage("hasCompletedOnboarding")` for first-launch detection (NOT on HealthProfile).
- Dark mode only, design tokens for colors.
- All steps skippable — onboarding must not gate app usage.

**Prerequisite WP01 provides**:
- `SettingsService` (save preferences to HealthProfile)
- `E1RMFormula` enum (formula cases + descriptions for FormulaStepView)

**Existing code references**:
- `Reppo/Core/Services/BodyweightService.swift` — `saveEntry(bodyweightKg:date:)` for optional bodyweight
- `Reppo/Core/Services/Protocols/SettingsServiceProtocol.swift` — `updateUnitPreference()`, `updateE1RMFormula()`
- `Reppo/Data/Enums/UnitPreference.swift` — `.metric`, `.imperial`

## Subtasks & Detailed Guidance

### Subtask T019 – Create OnboardingStep Enum

**Purpose**: Define the 5 onboarding steps with metadata for skip behavior and progression.

**Steps**:
1. Create `Reppo/Features/Onboarding/OnboardingStep.swift`.
2. Define:
   ```swift
   import Foundation

   enum OnboardingStep: Int, CaseIterable {
       case welcome       = 0
       case units         = 1
       case formula       = 2
       case bodyweight    = 3
       case importPrompt  = 4

       static var totalSteps: Int { allCases.count }

       var isSkippable: Bool {
           switch self {
           case .welcome:      return false
           case .units:        return true
           case .formula:      return true
           case .bodyweight:   return true
           case .importPrompt: return true
           }
       }

       var skipBehavior: String {
           switch self {
           case .welcome:      return "N/A"
           case .units:        return "metric (kg)"
           case .formula:      return "Epley"
           case .bodyweight:   return "No entry recorded"
           case .importPrompt: return "No import triggered"
           }
       }
   }
   ```

**Files**: `Reppo/Features/Onboarding/OnboardingStep.swift` (NEW, ~30 lines)

**Notes**:
- This is view-layer only — not persisted, not in `Data/Enums/`.
- The `skipBehavior` property is for documentation/debug purposes — actual defaults are applied in OnboardingViewModel.

---

### Subtask T020 – Create OnboardingViewModel

**Purpose**: Manage onboarding step progression, collect user selections, and save preferences on completion.

**Steps**:
1. Create `Reppo/Features/Onboarding/ViewModels/OnboardingViewModel.swift`.
2. Define as `@Observable`:
   ```swift
   import Foundation

   @Observable
   final class OnboardingViewModel {
       // Step progression
       var currentStep: OnboardingStep = .welcome

       // User selections (defaults applied)
       var selectedUnit: UnitPreference = .metric
       var selectedFormula: E1RMFormula = .epley
       var bodyweightInput: String = ""

       // State
       var isSaving = false

       // Dependencies
       private let settingsService: any SettingsServiceProtocol
       private let bodyweightService: any BodyweightServiceProtocol

       init(settingsService: any SettingsServiceProtocol,
            bodyweightService: any BodyweightServiceProtocol) {
           self.settingsService = settingsService
           self.bodyweightService = bodyweightService
       }
   }
   ```
3. Implement methods:
   - `next()` — Advance to the next step:
     ```swift
     func next() {
         guard let nextIndex = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
         withAnimation { currentStep = nextIndex }
     }
     ```
   - `skip()` — Same as `next()` but applies defaults (defaults are already set as initial values, so skip just advances).
   - `finish()` — Save all selections and complete onboarding:
     ```swift
     func finish() async {
         isSaving = true
         do {
             // Save unit preference
             try await settingsService.updateUnitPreference(selectedUnit)

             // Save e1RM formula
             try await settingsService.updateE1RMFormula(selectedFormula)

             // Save bodyweight if entered
             if let weight = Double(bodyweightInput), weight > 0 {
                 let weightKg = selectedUnit == .imperial
                     ? UnitConversion.lbsToKg(weight)
                     : weight
                 _ = try await bodyweightService.saveEntry(bodyweightKg: weightKg, date: Date())
             }

             isSaving = false
         } catch {
             isSaving = false
             // Errors are non-fatal for onboarding — defaults are applied
         }
     }
     ```
4. Computed helpers:
   - `isLastStep: Bool` — `currentStep == .importPrompt`
   - `stepProgress: Double` — `Double(currentStep.rawValue + 1) / Double(OnboardingStep.totalSteps)`
   - `canSkip: Bool` — `currentStep.isSkippable`

**Files**: `Reppo/Features/Onboarding/ViewModels/OnboardingViewModel.swift` (NEW, ~80 lines)

**Notes**:
- `finish()` is called on the LAST step. The `@AppStorage("hasCompletedOnboarding") = true` is set by the CALLER (OnboardingContainerView or ReppoApp) AFTER `finish()` completes — the ViewModel does not own the AppStorage flag.
- Bodyweight input is in the user's selected unit. Convert to kg before saving.
- If `finish()` throws, we still want to mark onboarding as complete (user can adjust settings later). The `isSaving = false` in the catch block allows the container to proceed.
- `withAnimation` on step transitions for smooth TabView page change.

---

### Subtask T021 – Create OnboardingContainerView

**Purpose**: The top-level container that manages the TabView-based step progression with custom navigation controls.

**Steps**:
1. Create `Reppo/Features/Onboarding/Views/OnboardingContainerView.swift`.
2. Structure:
   ```swift
   import SwiftUI

   struct OnboardingContainerView: View {
       @State private var viewModel: OnboardingViewModel
       let onComplete: () -> Void

       init(settingsService: any SettingsServiceProtocol,
            bodyweightService: any BodyweightServiceProtocol,
            onComplete: @escaping () -> Void) {
           _viewModel = State(initialValue: OnboardingViewModel(
               settingsService: settingsService,
               bodyweightService: bodyweightService
           ))
           self.onComplete = onComplete
       }

       var body: some View {
           VStack(spacing: 0) {
               // Progress indicator
               progressDots

               // Step content
               TabView(selection: $viewModel.currentStep) {
                   WelcomeStepView(onNext: { viewModel.next() })
                       .tag(OnboardingStep.welcome)

                   UnitsStepView(
                       selectedUnit: $viewModel.selectedUnit,
                       onNext: { viewModel.next() }
                   )
                   .tag(OnboardingStep.units)

                   FormulaStepView(
                       selectedFormula: $viewModel.selectedFormula,
                       onNext: { viewModel.next() }
                   )
                   .tag(OnboardingStep.formula)

                   BodyweightStepView(
                       bodyweightInput: $viewModel.bodyweightInput,
                       unitPreference: viewModel.selectedUnit,
                       onNext: { viewModel.next() },
                       onSkip: { viewModel.skip() }
                   )
                   .tag(OnboardingStep.bodyweight)

                   ImportStepView(onFinish: {
                       Task {
                           await viewModel.finish()
                           onComplete()
                       }
                   }, onSkip: {
                       Task {
                           await viewModel.finish()
                           onComplete()
                       }
                   })
                   .tag(OnboardingStep.importPrompt)
               }
               .tabViewStyle(.page(indexDisplayMode: .never))
               .animation(.easeInOut, value: viewModel.currentStep)
           }
           .background(Color.bg)
       }

       var progressDots: some View {
           HStack(spacing: 8) {
               ForEach(OnboardingStep.allCases, id: \.self) { step in
                   Circle()
                       .fill(step.rawValue <= viewModel.currentStep.rawValue ? Color.accent : Color.textSecondary.opacity(0.3))
                       .frame(width: 8, height: 8)
               }
           }
           .padding(.top, 16)
       }
   }
   ```

**Files**: `Reppo/Features/Onboarding/Views/OnboardingContainerView.swift` (NEW, ~80 lines)

**Notes**:
- `.tabViewStyle(.page(indexDisplayMode: .never))` hides system page dots — we use custom progress dots.
- The `onComplete` closure is called AFTER `viewModel.finish()` returns. The caller (ReppoApp) sets `@AppStorage("hasCompletedOnboarding") = true` in this closure.
- Disable swipe gestures on the TabView if possible. In SwiftUI, `.page` style allows swipe by default. To prevent this, you can set `.disabled(true)` on the TabView gesture or use a different approach (e.g., conditional content instead of TabView). However, for v1, allowing swipe is acceptable — the buttons provide the primary navigation.
- The `onSkip` callback on BodyweightStepView and ImportStepView allows the user to skip without entering data.

---

### Subtask T022 – Create WelcomeStepView

**Purpose**: The first onboarding screen — app welcome with a "Get Started" button.

**Steps**:
1. Create `Reppo/Features/Onboarding/Views/WelcomeStepView.swift`.
2. Structure:
   ```swift
   import SwiftUI

   struct WelcomeStepView: View {
       let onNext: () -> Void

       var body: some View {
           VStack(spacing: 32) {
               Spacer()

               // App icon or logo placeholder
               Image(systemName: "dumbbell.fill")
                   .font(.system(size: 64))
                   .foregroundStyle(Color.accent)

               VStack(spacing: 12) {
                   Text("Welcome to Reppo")
                       .font(.largeTitle)
                       .fontWeight(.bold)
                       .foregroundStyle(Color.textPrimary)

                   Text("Track your workouts, log your progress, and beat your personal records.")
                       .font(.body)
                       .foregroundStyle(Color.textSecondary)
                       .multilineTextAlignment(.center)
                       .padding(.horizontal, 32)
               }

               Spacer()

               Button("Get Started") { onNext() }
                   .buttonStyle(.borderedProminent)
                   .controlSize(.large)
                   .padding(.horizontal, 32)
                   .padding(.bottom, 48)
           }
       }
   }
   ```

**Files**: `Reppo/Features/Onboarding/Views/WelcomeStepView.swift` (NEW, ~40 lines)

**Parallel?**: Yes — independent from other step views.

**Notes**:
- This step is NOT skippable — it only has "Get Started" (which calls `onNext()`).
- Use a clean, centered layout. The app icon can be an SF Symbol placeholder for now.
- Ensure text is readable and has sufficient contrast in dark mode.

---

### Subtask T023 – Create UnitsStepView

**Purpose**: Let the user select their preferred unit system (metric or imperial).

**Steps**:
1. Create `Reppo/Features/Onboarding/Views/UnitsStepView.swift`.
2. Structure:
   ```swift
   import SwiftUI

   struct UnitsStepView: View {
       @Binding var selectedUnit: UnitPreference
       let onNext: () -> Void

       var body: some View {
           VStack(spacing: 32) {
               Spacer()

               VStack(spacing: 12) {
                   Text("Choose Your Units")
                       .font(.title)
                       .fontWeight(.bold)

                   Text("You can change this anytime in Settings.")
                       .font(.subheadline)
                       .foregroundStyle(Color.textSecondary)
               }

               VStack(spacing: 12) {
                   unitOption(.metric, title: "Metric", subtitle: "Kilograms (kg)")
                   unitOption(.imperial, title: "Imperial", subtitle: "Pounds (lbs)")
               }
               .padding(.horizontal, 32)

               Spacer()

               Button("Continue") { onNext() }
                   .buttonStyle(.borderedProminent)
                   .controlSize(.large)
                   .padding(.horizontal, 32)
                   .padding(.bottom, 48)
           }
       }

       private func unitOption(_ unit: UnitPreference, title: String, subtitle: String) -> some View {
           Button {
               selectedUnit = unit
           } label: {
               HStack {
                   VStack(alignment: .leading, spacing: 4) {
                       Text(title).font(.headline)
                       Text(subtitle).font(.caption).foregroundStyle(Color.textSecondary)
                   }
                   Spacer()
                   if selectedUnit == unit {
                       Image(systemName: "checkmark.circle.fill")
                           .foregroundStyle(Color.accent)
                   } else {
                       Image(systemName: "circle")
                           .foregroundStyle(Color.textSecondary)
                   }
               }
               .padding()
               .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
               .overlay(
                   RoundedRectangle(cornerRadius: 12)
                       .stroke(selectedUnit == unit ? Color.accent : Color.clear, lineWidth: 2)
               )
           }
           .buttonStyle(.plain)
       }
   }
   ```

**Files**: `Reppo/Features/Onboarding/Views/UnitsStepView.swift` (NEW, ~60 lines)

**Parallel?**: Yes — independent from other step views.

**Notes**:
- Default selection: `.metric` (pre-selected).
- Visual feedback: Selected option has accent border and filled checkmark.
- "Continue" button always visible — user can proceed with default without tapping anything.
- "You can change this anytime in Settings" reassures users about their choice.

---

### Subtask T024 – Create FormulaStepView

**Purpose**: Let the user select their preferred e1RM estimation formula with plain-English descriptions.

**Steps**:
1. Create `Reppo/Features/Onboarding/Views/FormulaStepView.swift`.
2. Structure similar to UnitsStepView:
   - Title: "e1RM Formula"
   - Subtitle: "Estimates your one-rep max from your working sets. You can change this later."
   - List all 3 options from `E1RMFormula.allCases`:
     - Show `formula.displayName` as the title
     - Show `formula.description` as the subtitle (plain-English explanation)
   - Checkmark/circle for selection state.
   - "Continue" button to proceed.

**Files**: `Reppo/Features/Onboarding/Views/FormulaStepView.swift` (NEW, ~60 lines)

**Parallel?**: Yes — independent from other step views.

**Notes**:
- Default selection: `.epley` (pre-selected).
- The descriptions are critical — they help users who don't know the math make an informed choice.
- Per AGENT_RULES S11: descriptions must be in plain English, not mathematical notation (though the formula can appear as a secondary line).

---

### Subtask T025 – Create BodyweightStepView + ImportStepView

**Purpose**: Two final onboarding steps — one for optional bodyweight entry, one for the import prompt stub.

**BodyweightStepView Steps**:
1. Create `Reppo/Features/Onboarding/Views/BodyweightStepView.swift`.
2. Structure:
   ```swift
   struct BodyweightStepView: View {
       @Binding var bodyweightInput: String
       let unitPreference: UnitPreference
       let onNext: () -> Void
       let onSkip: () -> Void

       var body: some View {
           VStack(spacing: 32) {
               Spacer()

               VStack(spacing: 12) {
                   Text("Your Bodyweight")
                       .font(.title)
                       .fontWeight(.bold)
                   Text("Optional. Used for accurate tracking of bodyweight exercises.")
                       .font(.subheadline)
                       .foregroundStyle(Color.textSecondary)
                       .multilineTextAlignment(.center)
                       .padding(.horizontal, 32)
               }

               HStack {
                   TextField("Enter weight", text: $bodyweightInput)
                       .keyboardType(.decimalPad)
                       .textFieldStyle(.roundedBorder)
                       .frame(maxWidth: 150)
                   Text(unitPreference == .metric ? "kg" : "lbs")
                       .foregroundStyle(Color.textSecondary)
               }
               .padding(.horizontal, 48)

               Spacer()

               VStack(spacing: 12) {
                   Button("Continue") { onNext() }
                       .buttonStyle(.borderedProminent)
                       .controlSize(.large)

                   Button("Skip") { onSkip() }
                       .foregroundStyle(Color.textSecondary)
               }
               .padding(.horizontal, 32)
               .padding(.bottom, 48)
           }
       }
   }
   ```

**ImportStepView Steps**:
1. Create `Reppo/Features/Onboarding/Views/ImportStepView.swift`.
2. Structure:
   ```swift
   struct ImportStepView: View {
       let onFinish: () -> Void
       let onSkip: () -> Void

       var body: some View {
           VStack(spacing: 32) {
               Spacer()

               VStack(spacing: 12) {
                   Image(systemName: "square.and.arrow.down")
                       .font(.system(size: 48))
                       .foregroundStyle(Color.accent)

                   Text("Migrating from Another App?")
                       .font(.title)
                       .fontWeight(.bold)

                   Text("CSV import is coming in a future update. For now, you can start fresh and add your exercises as you go.")
                       .font(.subheadline)
                       .foregroundStyle(Color.textSecondary)
                       .multilineTextAlignment(.center)
                       .padding(.horizontal, 32)
               }

               Spacer()

               VStack(spacing: 12) {
                   Button("Get Started") { onFinish() }
                       .buttonStyle(.borderedProminent)
                       .controlSize(.large)

                   Button("Skip") { onSkip() }
                       .foregroundStyle(Color.textSecondary)
               }
               .padding(.horizontal, 32)
               .padding(.bottom, 48)
           }
       }
   }
   ```

**Files**:
- `Reppo/Features/Onboarding/Views/BodyweightStepView.swift` (NEW, ~50 lines)
- `Reppo/Features/Onboarding/Views/ImportStepView.swift` (NEW, ~45 lines)

**Parallel?**: Yes — independent from other step views.

**Notes**:
- BodyweightStepView: Weight input is in the unit selected on the Units step. The ViewModel handles conversion to kg.
- BodyweightStepView: Both "Continue" and "Skip" advance to the next step. "Continue" preserves any entered value; "Skip" leaves the input empty (ViewModel will not save an entry).
- ImportStepView: This is a stub — the import feature is built in feature 011. The button says "Get Started" (not "Import") to call `onFinish()`.
- ImportStepView: Both "Get Started" and "Skip" trigger the same `finish()` flow. The difference is semantically logged but functionally identical.
- Bodyweight input validation: The ViewModel validates on `finish()` — if the input is empty or invalid, it simply skips saving a bodyweight entry.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Onboarding shows on every launch | `@AppStorage` flag is set in `onComplete` closure AFTER `finish()` completes |
| User closes app mid-onboarding | Settings remain at defaults. Re-launch shows onboarding again. This is correct behavior. |
| TabView swipe conflicts with buttons | Accept swipe for v1; buttons provide primary navigation. Disable swipe in v2 if needed. |
| Bodyweight in wrong unit | Convert to kg in `finish()` based on `selectedUnit` |
| `finish()` throws | Errors are non-fatal — mark onboarding complete anyway. User adjusts in Settings later. |

## Definition of Done Checklist

- [ ] OnboardingStep enum has 5 cases with correct properties
- [ ] OnboardingViewModel manages step progression and user selections
- [ ] OnboardingContainerView renders TabView with 5 steps and progress dots
- [ ] WelcomeStepView shows app intro + "Get Started" button
- [ ] UnitsStepView shows metric/imperial selection with visual feedback
- [ ] FormulaStepView shows 3 formula options with descriptions
- [ ] BodyweightStepView has optional weight input + Skip/Continue buttons
- [ ] ImportStepView shows stub message + "Get Started"/"Skip" buttons
- [ ] `finish()` saves selected unit, formula, and bodyweight to HealthProfile
- [ ] All steps are skippable (except Welcome)
- [ ] Default selections: metric, Epley, no bodyweight, no import
- [ ] Dark mode styling consistent across all step views
- [ ] Project compiles with 0 errors

## Review Guidance

- Walk through the full onboarding flow: Welcome → Units → Formula → Bodyweight → Import.
- Verify that skipping all optional steps leaves defaults (metric, Epley, no bodyweight).
- Verify that selections persist after `finish()` — check HealthProfile values.
- Verify progress dots update correctly on each step.
- Check that the `onComplete` closure is called AFTER `finish()` — not before.
- Test empty bodyweight input: should not crash or create a 0kg entry.

## Activity Log

- 2026-02-28T18:49:28Z – system – lane=planned – Prompt created.
- 2026-02-28T19:44:07Z – claude-opus – shell_pid=56690 – lane=doing – Started implementation via workflow command
