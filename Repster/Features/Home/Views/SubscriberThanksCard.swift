// SubscriberThanksCard.swift
// A one-time thank-you on Home for paying users, asking whether they'd help shape what comes
// next. Scoping: FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md §3.
//
// Sits in the walkthrough banner's slot, below Start Workout, which stays the loudest thing on
// the screen. When it shows is `SubscriberThanksPolicy`'s call; any button closes it for good.

import SwiftUI

struct SubscriberThanksCard: View {
    let onAnswerQuestions: () -> Void
    let onEmail: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "heart")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.accent)
                    .frame(width: 30, height: 30)
                    .background(Color.accentSoft)
                    .cornerRadius(9)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Thanks for supporting Repster")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Subscribers shape what comes next. Would you help?")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                // Same dismiss as `HomeWalkthroughBanner`, in the slot a chevron would hold.
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            HStack(spacing: 10) {
                Button(action: onAnswerQuestions) {
                    Text("Answer 3 questions")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.accentSoft)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button(action: onEmail) {
                    Label("Email me", systemImage: "envelope")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Color.bgSubtle)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            // The header's dismiss frame supplies its trailing inset; the buttons need their own.
            .padding(.trailing, 6)
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        // Matches the walkthrough banner: the dismiss button's own frame supplies the rest of
        // the trailing inset.
        .padding(.trailing, 6)
        .background(Color.bgCard)
        .cornerRadius(14)
    }
}

#Preview {
    SubscriberThanksCard(onAnswerQuestions: {}, onEmail: {}, onDismiss: {})
        .padding(20)
        .background(Color.bg)
        .preferredColorScheme(.dark)
}
