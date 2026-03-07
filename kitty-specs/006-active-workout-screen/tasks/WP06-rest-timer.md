---
work_package_id: "WP06"
subtasks:
  - "T027"
  - "T028"
  - "T029"
  - "T030"
title: "Rest Timer"
phase: "Phase 1 - Core UI"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "8628"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP02"]
history:
  - timestamp: "2026-02-24T14:26:08Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP06 – Rest Timer

## Implementation Command

Depends on WP02:
```bash
spec-kitty implement WP06 --base WP02
```

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Objectives & Success Criteria

- Rest timer auto-starts when a set is completed, counting down from `exercise.defaultRestTime`
- Timer shows MM:SS countdown with visual progress
- "+30s" button adds 30 seconds to running timer
- "Dismiss" button hides the timer
- Timer recalculates correctly when app returns from background
- Timer restarts when a new set is completed while timer is running
- Covers spec User Story 4 and FR-006

## Context & Constraints

**Feature**: 006-active-workout-screen — User Story 4 (Rest Timer)
**Plan**: `kitty-specs/006-active-workout-screen/plan.md` — Rest timer section
**Research**: `kitty-specs/006-active-workout-screen/research.md` — Topic 2 (Timer.publish decision)
**Constitution**: No background notifications for v1, timer is visual-only

**Key constraint**: Timer is purely visual — no persistence, no local notifications. If the app is backgrounded, recalculate remaining time from timestamps on foreground return. If the app is killed, the timer is lost (acceptable for v1).

## Subtasks & Detailed Guidance

### Subtask T027 – RestTimerState + ViewModel Timer Methods

- **Purpose**: Define the timer state model and management methods on the ViewModel.
- **File**: `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` (add to existing)

**Steps**:
1. `RestTimerState` should already exist from WP02 (T006). If not, add it:
   ```swift
   enum RestTimerState: Equatable {
       case idle
       case running(remaining: Int, total: Int)
       case finished
   }
   ```

2. Add timer management properties to the ViewModel:
   ```swift
   // Timer internals
   private var timerSubscription: AnyCancellable?
   private var timerStartDate: Date?
   private var timerTotalDuration: Int = 0
   ```

3. Implement timer methods:
   ```swift
   func startRestTimer(duration: Int) {
       // Cancel any existing timer
       timerSubscription?.cancel()

       // Store start time for background recalculation
       timerStartDate = Date()
       timerTotalDuration = duration
       restTimer = .running(remaining: duration, total: duration)

       // Start 1-second tick
       timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
           .autoconnect()
           .sink { [weak self] _ in
               self?.timerTick()
           }
   }

   func addTime(_ seconds: Int) {
       guard case .running(let remaining, let total) = restTimer else { return }
       let newTotal = total + seconds
       let newRemaining = remaining + seconds
       timerTotalDuration = newTotal
       restTimer = .running(remaining: newRemaining, total: newTotal)
   }

   func dismissTimer() {
       timerSubscription?.cancel()
       timerSubscription = nil
       timerStartDate = nil
       restTimer = .idle
   }

   private func timerTick() {
       guard case .running(let remaining, let total) = restTimer else { return }
       if remaining <= 1 {
           restTimer = .finished
           timerSubscription?.cancel()
           timerSubscription = nil
           // Optionally auto-dismiss after a delay
       } else {
           restTimer = .running(remaining: remaining - 1, total: total)
       }
   }
   ```

4. Import `Combine` for `AnyCancellable` and `Timer.publish`.

**Validation**:
- [ ] startRestTimer() sets state to .running and starts countdown
- [ ] addTime() increases both remaining and total
- [ ] dismissTimer() resets to .idle and cancels subscription
- [ ] Timer reaches .finished when remaining hits 0
- [ ] Subscription properly cancelled to prevent leaks

### Subtask T028 – Timer Countdown Logic

- **Purpose**: Ensure the countdown works correctly including edge cases.
- **File**: `ActiveWorkoutViewModel.swift` (enhance timer methods)

**Steps**:
1. Verify the `timerTick()` method decrements correctly every second.

2. Handle the `.finished` state — options:
   - Keep showing "0:00" with a "Done" indicator
   - Auto-dismiss after 3 seconds: `DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.dismissTimer() }`
   - Stay in `.finished` until user taps dismiss or starts a new set

3. When `completeSet()` is called while a timer is running:
   - Restart the timer with the current exercise's `defaultRestTime`
   - This naturally happens if `completeSet()` calls `startRestTimer()` which cancels the existing timer first

4. When `defaultRestTime` is nil or 0:
   - Don't start a timer (skip the `startRestTimer()` call)
   - Guard: `guard let restTime = currentExercise?.defaultRestTime, restTime > 0 else { return }`

**Validation**:
- [ ] Timer decrements by 1 each second
- [ ] Timer stops at 0 (reaches .finished)
- [ ] New set completion restarts timer
- [ ] No timer started if defaultRestTime is nil/0
- [ ] No timer memory leaks (subscription cancelled)

### Subtask T029 – Create RestTimerView

- **Purpose**: Visual representation of the rest timer — countdown display with action buttons.
- **File**: `Reppo/Features/Workout/Views/RestTimerView.swift` (new file)
- **Parallel?**: Yes — can be built with mock state independently.

**Steps**:
1. Create `RestTimerView`:
   ```swift
   struct RestTimerView: View {
       let state: RestTimerState
       let onAddTime: () -> Void
       let onDismiss: () -> Void

       var body: some View {
           switch state {
           case .idle:
               EmptyView()

           case .running(let remaining, let total):
               timerContent(remaining: remaining, total: total)

           case .finished:
               finishedContent
           }
       }

       private func timerContent(remaining: Int, total: Int) -> some View {
           HStack(spacing: 16) {
               // Progress ring or bar
               ZStack {
                   Circle()
                       .stroke(Color.bgSubtle, lineWidth: 4)
                       .frame(width: 44, height: 44)
                   Circle()
                       .trim(from: 0, to: CGFloat(remaining) / CGFloat(total))
                       .stroke(Color.appBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                       .frame(width: 44, height: 44)
                       .rotationEffect(.degrees(-90))
                       .animation(.linear(duration: 1), value: remaining)
               }

               // Time remaining
               Text(formatTime(remaining))
                   .font(.system(size: 24, weight: .bold, design: .monospaced))
                   .foregroundColor(Color.textPrimary)

               Spacer()

               // +30s button
               Button("+30s") { onAddTime() }
                   .font(.system(size: 14, weight: .semibold))
                   .foregroundColor(Color.appBlue)
                   .padding(.horizontal, 12)
                   .padding(.vertical, 8)
                   .background(Color.blueSoft)
                   .cornerRadius(8)

               // Dismiss button
               Button(action: onDismiss) {
                   Image(systemName: "xmark")
                       .font(.system(size: 14, weight: .semibold))
                       .foregroundColor(Color.textTertiary)
                       .frame(width: 44, height: 44)
               }
           }
           .padding(.horizontal, 20)
           .padding(.vertical, 12)
           .background(Color.bgCard)
       }

       private var finishedContent: some View {
           HStack {
               Image(systemName: "checkmark.circle.fill")
                   .foregroundColor(Color.appGreen)
               Text("Rest complete")
                   .foregroundColor(Color.textPrimary)
               Spacer()
               Button("Dismiss") { onDismiss() }
                   .foregroundColor(Color.textSecondary)
           }
           .padding(.horizontal, 20)
           .padding(.vertical, 12)
           .background(Color.bgCard)
       }

       private func formatTime(_ seconds: Int) -> String {
           String(format: "%d:%02d", seconds / 60, seconds % 60)
       }
   }
   ```

2. Position: The timer view goes below the set table in ActiveWorkoutView, or as a floating bar at the bottom. It should NOT obscure the set table.

3. Visual: Blue progress ring, large monospaced countdown, +30s and dismiss buttons. Use design tokens consistently.

**Validation**:
- [ ] Timer shows countdown in MM:SS format
- [ ] Progress ring animates smoothly
- [ ] "+30s" button triggers onAddTime callback
- [ ] "Dismiss" / X button triggers onDismiss callback
- [ ] "Rest complete" state shown when finished
- [ ] Timer hidden when state is .idle

### Subtask T030 – Wire Auto-Start + Background Handling

- **Purpose**: Connect the timer to the set completion flow and handle app lifecycle.
- **Files**: `ActiveWorkoutViewModel.swift` (completeSet method + scenePhase handling)

**Steps**:
1. In `completeSet()` (from WP02 T008), add timer auto-start after successful save:
   ```swift
   // After SetService.save() succeeds:
   if let exercise = currentExercise,
      let restTime = exercise.defaultRestTime,
      restTime > 0 {
       startRestTimer(duration: restTime)
   }
   ```

2. Add `RestTimerView` to `ActiveWorkoutView` layout (between set table and bottom):
   ```swift
   // In ActiveWorkoutView body:
   if viewModel.restTimer != .idle {
       RestTimerView(
           state: viewModel.restTimer,
           onAddTime: { viewModel.addTime(30) },
           onDismiss: { viewModel.dismissTimer() }
       )
   }
   ```

3. Handle background/foreground transitions:
   ```swift
   // In ActiveWorkoutView:
   @Environment(\.scenePhase) private var scenePhase

   .onChange(of: scenePhase) { _, newPhase in
       if newPhase == .active {
           viewModel.recalculateTimerAfterBackground()
       }
   }
   ```

4. Add `recalculateTimerAfterBackground()` to ViewModel:
   ```swift
   func recalculateTimerAfterBackground() {
       guard case .running = restTimer,
             let startDate = timerStartDate else { return }

       let elapsed = Int(Date().timeIntervalSince(startDate))
       let remaining = timerTotalDuration - elapsed

       if remaining <= 0 {
           restTimer = .finished
           timerSubscription?.cancel()
       } else {
           restTimer = .running(remaining: remaining, total: timerTotalDuration)
       }
   }
   ```

**Validation**:
- [ ] Timer auto-starts after set completion
- [ ] Timer does NOT start if defaultRestTime is nil/0
- [ ] Timer restarts on next set completion
- [ ] After backgrounding for 30s, timer shows correct reduced time
- [ ] After backgrounding past timer end, shows .finished
- [ ] RestTimerView appears in ActiveWorkoutView when timer is running

## Risks & Mitigations

- **Combine import**: ViewModel needs `import Combine` for `AnyCancellable`. This is fine — Combine is a system framework.
- **Timer.publish accuracy**: `Timer.publish` is subject to RunLoop scheduling. ±100ms drift per tick is acceptable for a rest timer.
- **Memory leak**: Ensure `timerSubscription?.cancel()` is called in `dismissTimer()` and when ViewModel is deinitialized. Consider adding a `deinit` cleanup.

## Definition of Done Checklist

- [ ] Rest timer auto-starts on set completion
- [ ] Timer counts down correctly
- [ ] +30s adds time
- [ ] Dismiss hides timer
- [ ] Background/foreground recalculation works
- [ ] Timer view renders with progress ring and buttons
- [ ] No Combine subscription leaks
- [ ] Project builds with zero errors

## Review Guidance

- Verify timer accuracy (approximately 1 tick/second)
- Test background: background app for 30s, return, verify time jumped
- Test +30s while running
- Test completing a new set while timer is running (should restart)
- Verify dismiss cleans up properly
- Check that timer view doesn't obscure set table content

## Activity Log

- 2026-02-24T14:26:08Z – system – lane=planned – Prompt created.
- 2026-02-25T07:36:51Z – claude – shell_pid=6897 – lane=doing – Started implementation via workflow command
- 2026-02-25T07:41:29Z – claude – shell_pid=6897 – lane=for_review – Ready for review: Rest timer with Combine Timer.publish countdown, RestTimerView with progress ring and controls, auto-start on set completion with defaultRestTime guard, background recalculation via scenePhase, +30s extension, dismiss. Build succeeds.
- 2026-02-25T07:47:12Z – claude – shell_pid=8628 – lane=doing – Started review via workflow command
- 2026-02-25T07:47:23Z – claude – shell_pid=8628 – lane=done – Review passed: Combine Timer.publish with proper subscription lifecycle, background recalculation via stored startDate, RestTimerView with progress ring and design tokens (accent/accentSoft/success), auto-start guarded by defaultRestTime > 0, dismiss cancels subscription. No leaks.
