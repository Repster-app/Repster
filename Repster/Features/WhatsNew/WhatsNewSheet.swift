// WhatsNewSheet.swift
// Shown once on the first launch after the marketing version changes, and reachable
// again from Settings → About.
//
// The Apple Health ask lives inside its own row rather than behind a full-screen prompt.
// `AppleHealthConnectionModel` is view-agnostic by design, so this surface supplies chrome
// and `source: .whatsNew` and nothing else — the authorization call, the preference write
// and the analytics all stay in one place.
//
// Buttons are built by hand rather than with `.borderedProminent`: the AccentColor asset
// is empty, so the system style paints iOS blue capsules that belong to no other screen
// in the app. Everywhere else does the same (see `ActiveWorkoutView`).

import SwiftUI

struct WhatsNewSheet: View {

    let release: WhatsNewRelease
    let healthKitService: any HealthKitServiceProtocol
    let analyticsService: any AnalyticsServiceProtocol

    @Environment(\.dismiss) private var dismiss

    /// Held here rather than rebuilt per render so an in-flight authorization can't be
    /// lost, matching how the onboarding container owns its copy.
    @State private var healthModel: AppleHealthConnectionModel?

    /// Mirrors `HealthKitPreferences` so the row settles the moment the user answers.
    @State private var healthState: HealthRowState = .answered

    /// Measured so the sheet sits on its content. A release with one item and a release
    /// with three shouldn't open to the same half-screen of empty space.
    @State private var measuredContentHeight: CGFloat = 300

    /// What the Apple Health row offers, if anything.
    private enum HealthRowState {
        /// Never asked. The only state with a button.
        case offer
        /// Connected — confirm it and get out of the way.
        case connected
        /// Asked and declined, or unavailable on this hardware. Settings is the way back;
        /// this row must not nag.
        case answered

        static func resolve(isAvailable: Bool) -> HealthRowState {
            guard isAvailable else { return .answered }
            if HealthKitPreferences.isEnabled { return .connected }
            if HealthKitPreferences.hasBeenOffered { return .answered }
            return .offer
        }
    }

    // MARK: - Layout

    private var detentHeight: CGFloat {
        // The constant is the Done block (50pt button + 14 above + 8 below) exactly. The
        // home indicator inset is supplied by the detent itself, so adding it here is what
        // leaves a sheet floating above its own button.
        //
        // Floor keeps a one-item release from looking like an error; ceiling keeps large
        // Dynamic Type from pinning the sheet to the top of the screen, and the ScrollView
        // takes over from there.
        min(max(measuredContentHeight + 72, 260), 620)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header

                    ForEach(release.items) { item in
                        itemCard(item)
                    }
                }
                .padding(.horizontal, 18)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accent)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .onPreferenceChange(ContentHeightKey.self) { measuredContentHeight = $0 }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgCard)
        .task {
            if healthModel == nil {
                healthModel = AppleHealthConnectionModel(
                    healthKitService: healthKitService,
                    analyticsService: analyticsService,
                    source: .whatsNew
                )
            }
            healthState = HealthRowState.resolve(isAvailable: healthKitService.isAvailable)

            // The row *is* Repster's pre-permission UI, so the funnel starts when it's on
            // screen with something to offer — not when Connect is tapped.
            if healthState == .offer {
                healthModel?.promptShown()
            }
        }
        // A denial isn't an error worth dwelling on, but it's the one place to say where
        // the decision can be reversed.
        .alert("Apple Health", isPresented: Binding(
            get: { healthModel?.alertMessage != nil },
            set: { if !$0 { healthModel?.alertMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(healthModel?.alertMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // No app name: the user knows which app they just opened.
            Text("What's new")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.textPrimary)

            Spacer(minLength: 8)

            // Pushed to the trailing edge because it's metadata. Sitting inline against
            // the title it read as part of the sentence.
            Text(release.version)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentSoft)
                .cornerRadius(6)
        }
        // Even above and below: 16 here, and 6 + the stack's 10pt spacing underneath.
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Items

    private func itemCard(_ item: WhatsNewItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The icon anchors the title rather than sitting beside a paragraph, so the
            // card holds one left edge no matter how far the body wraps or how much
            // Dynamic Type grows it.
            HStack(spacing: 11) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(tint(item.tint))
                    .frame(width: 32, height: 32)
                    .background(tint(item.tint).opacity(0.13))
                    .cornerRadius(9)

                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Spacer(minLength: 0)
            }

            Text(item.body)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 9)

            if item.action == .connectAppleHealth {
                healthAction
            }
        }
        .padding(Self.cardPadding)
        .background(Color.bg)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    /// Shared so the divider can cancel it out and run edge to edge.
    private static let cardPadding: CGFloat = 13

    /// Separates what changed from what you can do about it, so the caveat and the button
    /// read as one unit instead of two loose fragments under a paragraph.
    private var cardDivider: some View {
        Rectangle()
            .fill(Color.border)
            .frame(height: 1)
            .padding(.horizontal, -Self.cardPadding)
            .padding(.top, 12)
    }

    @ViewBuilder
    private var healthAction: some View {
        switch healthState {
        case .offer:
            cardDivider

            HStack(spacing: 12) {
                // Shortened to sit beside the button. "Turn it off any time" lives on the
                // Settings row that already does it. What's left is the load-bearing half:
                // iOS spends its permission sheet once per install, so a blind Connect
                // followed by a denial is only recoverable through the Health app.
                Text("Only writes workouts, never reads your health data.")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Subtle fill with accent text: unmistakably a button, unmistakably
                // secondary to Done, and it leaves accent blue meaning one thing per sheet.
                Button {
                    connectHealth()
                } label: {
                    Text("Connect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accent)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Color.bgSubtle)
                        .cornerRadius(9)
                }
                .disabled(healthModel?.isConnecting ?? true)
            }
            .padding(.top, 12)

        case .connected:
            cardDivider

            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                Text("Connected")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.success)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)

        case .answered:
            // No divider either: with nothing to offer, the card is a plain item and
            // should look like the Insights one.
            EmptyView()
        }
    }

    // MARK: - Actions

    private func connectHealth() {
        guard let model = healthModel else { return }
        Task {
            await model.connect()
            healthState = HealthRowState.resolve(isAvailable: healthKitService.isAvailable)
        }
    }

    private func tint(_ tint: WhatsNewItem.Tint) -> Color {
        switch tint {
        case .accent: return .accent
        case .gold:   return .gold
        case .red:    return .danger
        case .green:  return .success
        }
    }
}

// MARK: - Height measurement

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
