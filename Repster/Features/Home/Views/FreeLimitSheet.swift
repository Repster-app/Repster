// FreeLimitSheet.swift
// Raised instead of the paywall when a free user with no workouts left tries to start one.
//
// Going straight from a Start Workout tap to a price screen read as an error: nothing said
// the free workouts had run out, or that the rest of the app stays open. This says both and
// leaves the paywall as a choice. Scope and decisions: PAYWALL_BRIDGE_SCOPING.md.
//
// Presented by `ContentView.ensureWorkoutCreationAccess`, the one gate every start path goes
// through. The host owns the paywall — "See plans" only reports the answer, and the host
// opens the paywall once this sheet has finished dismissing.

import SwiftUI

/// What the user has logged so far, for the sheet's recap row.
///
/// Workouts and sets only. PRs were left out on purpose: ten workouts in, nearly every
/// exercise tried holds a first-time rep max, so the count would be "exercises tried"
/// relabelled as PRs.
struct FreeLimitRecap: Equatable {
    let workouts: Int
    let sets: Int

    /// Nil when there is no history to show. A zero would read as "you did nothing", the
    /// opposite of what the row is for — the sheet drops the row instead.
    init?(workouts: Int, sets: Int) {
        guard workouts > 0 else { return nil }
        self.workouts = workouts
        self.sets = max(0, sets)
    }

    var workoutsLabel: String { workouts == 1 ? "workout" : "workouts" }
    var setsLabel: String { sets == 1 ? "set" : "sets" }

    /// Grouped for the locale, so an imported history reads "4,210" rather than "4210".
    static func value(_ count: Int, locale: Locale = .current) -> String {
        count.formatted(.number.locale(locale))
    }
}

struct FreeLimitSheet: View {
    /// The quota that ran out. Read from the access snapshot, not a literal — it has
    /// changed once already (5 → 10).
    let freeWorkoutLimit: Int
    /// Loaded by the host before presenting, so the sheet opens at its final height instead
    /// of growing when the numbers land. Nil hides the row.
    let recap: FreeLimitRecap?
    /// Fires once per presentation, however many times `onAppear` does.
    let onShown: () -> Void
    let onSeePlans: () -> Void
    let onNotNow: () -> Void

    @State private var measuredHeight: CGFloat = 420
    @State private var hasReportedShown = false

    private var detentHeight: CGFloat {
        promptDetentHeight(for: measuredHeight, minimum: 320)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        // A finished quota, not an error — so a check, not a lock.
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.success)

                        Text("You've used your \(freeWorkoutLimit) free workouts")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.center)
                    }

                    if let recap {
                        HStack(spacing: 12) {
                            recapTile(value: recap.workouts, label: recap.workoutsLabel)
                            if recap.sets > 0 {
                                recapTile(value: recap.sets, label: recap.setsLabel)
                            }
                        }
                    }

                    Text("Your history, charts and insights stay open. Unlock Repster to keep logging new workouts.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 12)
                .measuringHeight()
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 12) {
                Button(action: onSeePlans) {
                    Text("See plans")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not now", action: onNotNow)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .measuringHeight()
        }
        .onPreferenceChange(PromptHeightKey.self) { measuredHeight = $0 }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgCard)
        .onAppear {
            // `paywall shown` hangs off a bare `onAppear` and was measured double-firing.
            // This state is fresh per presentation, so the guard makes it exactly one.
            guard !hasReportedShown else { return }
            hasReportedShown = true
            onShown()
        }
    }

    private func recapTile(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(FreeLimitRecap.value(value))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: 12))
    }
}

// Height measurement lives in `PromptSheetHeight.swift`, shared with the Health and rest-alarm prompts.

// MARK: - Previews

#Preview("With recap") {
    Color.bg
        .sheet(isPresented: .constant(true)) {
            FreeLimitSheet(
                freeWorkoutLimit: 10,
                recap: FreeLimitRecap(workouts: 12, sets: 184),
                onShown: {}, onSeePlans: {}, onNotNow: {}
            )
        }
}

#Preview("Imported history") {
    Color.bg
        .sheet(isPresented: .constant(true)) {
            FreeLimitSheet(
                freeWorkoutLimit: 10,
                recap: FreeLimitRecap(workouts: 312, sets: 4210),
                onShown: {}, onSeePlans: {}, onNotNow: {}
            )
        }
}

#Preview("No recap") {
    Color.bg
        .sheet(isPresented: .constant(true)) {
            FreeLimitSheet(
                freeWorkoutLimit: 10,
                recap: nil,
                onShown: {}, onSeePlans: {}, onNotNow: {}
            )
        }
}

#Preview("Largest Dynamic Type") {
    Color.bg
        .sheet(isPresented: .constant(true)) {
            FreeLimitSheet(
                freeWorkoutLimit: 10,
                recap: FreeLimitRecap(workouts: 12, sets: 184),
                onShown: {}, onSeePlans: {}, onNotNow: {}
            )
            .dynamicTypeSize(.accessibility3)
        }
}
