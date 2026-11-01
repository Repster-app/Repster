// FeedbackFlowView.swift
// The full-screen flow behind both asks: the three questions, then an end screen. For the free
// month the end screen is the claim; for subscribers it is a thank-you.
// Scoping: FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md §2.1, §3.1.
//
// Presented by `ContentView`, which owns analytics, the offer service and the redeem link. The
// view only reports what was tapped.

import SwiftUI

enum FeedbackFlowKind: Equatable {
    case freeMonth(CustomerType, PlanPrices)
    case subscriber

    var questionSet: FeedbackQuestionSet {
        switch self {
        case .freeMonth:
            return .freeMonth
        case .subscriber:
            return .subscriber
        }
    }

    var questions: [FeedbackQuestion] {
        switch self {
        case .freeMonth(let customerType, let prices):
            return FeedbackQuestions.freeMonth(customerType: customerType, prices: prices)
        case .subscriber:
            return FeedbackQuestions.subscriber
        }
    }

    var title: String {
        switch self {
        case .freeMonth:
            return "Free month"
        case .subscriber:
            return "Help shape Repster"
        }
    }

    func finePrint(at index: Int) -> String {
        switch self {
        case .freeMonth:
            return "Answer all 3 to get your free month. Answers are anonymous."
        case .subscriber:
            return index == FeedbackQuestions.subscriber.count - 1
                ? "Yes opens an email to the developer. Nothing is sent until you send it."
                : "Answers are anonymous."
        }
    }

    /// The renewal line under Claim. The offer code is on the monthly plan, so its price is the
    /// one that follows the free month.
    static func renewalLine(monthlyPrice: String?) -> String {
        guard let monthlyPrice else {
            return "Then it renews monthly. Cancel anytime in your Apple ID settings."
        }
        return "Then \(monthlyPrice) a month. Cancel anytime in your Apple ID settings."
    }
}

struct FeedbackFlowView: View {
    let kind: FeedbackFlowKind
    let onAnswer: (FeedbackQuestion, FeedbackOption) -> Void
    let onQuestionsFinished: () -> Void
    /// Closed before the last answer, with the question that was on screen.
    let onClosedEarly: (FeedbackQuestion) -> Void
    /// Free month only: the user tapped Claim.
    let onClaim: () -> Void
    /// Closed from the end screen.
    let onDone: () -> Void

    @State private var showsEnd: Bool

    init(
        kind: FeedbackFlowKind,
        startsAtEnd: Bool = false,
        onAnswer: @escaping (FeedbackQuestion, FeedbackOption) -> Void,
        onQuestionsFinished: @escaping () -> Void,
        onClosedEarly: @escaping (FeedbackQuestion) -> Void,
        onClaim: @escaping () -> Void = {},
        onDone: @escaping () -> Void
    ) {
        self.kind = kind
        self.onAnswer = onAnswer
        self.onQuestionsFinished = onQuestionsFinished
        self.onClosedEarly = onClosedEarly
        self.onClaim = onClaim
        self.onDone = onDone
        _showsEnd = State(initialValue: startsAtEnd)
    }

    var body: some View {
        if showsEnd {
            endScreen
        } else {
            FeedbackQuestionsView(
                title: kind.title,
                questions: kind.questions,
                finePrint: kind.finePrint(at:),
                onAnswer: onAnswer,
                onFinished: {
                    onQuestionsFinished()
                    withAnimation(.easeInOut(duration: 0.2)) { showsEnd = true }
                },
                onClose: onClosedEarly
            )
        }
    }

    private var endScreen: some View {
        VStack(spacing: 0) {
            FeedbackTopBar(title: kind.title, onBack: nil, onClose: onDone)

            Spacer(minLength: 24)

            VStack(spacing: 0) {
                Image(systemName: endIcon)
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accent)
                    .frame(width: 76, height: 76)
                    .background(Color.accentSoft, in: Circle())
                    .accessibilityHidden(true)

                Text(endTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 24)
                    .padding(.bottom, 10)

                Text(endBody)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button(action: endAction) {
                    Text(endButton)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if case .freeMonth(_, let prices) = kind {
                    Text(FeedbackFlowKind.renewalLine(monthlyPrice: prices.monthly))
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color.bg.ignoresSafeArea())
    }

    private var endIcon: String {
        if case .subscriber = kind { return "heart" }
        return "gift"
    }

    private var endTitle: String {
        if case .subscriber = kind { return "Thanks. That really helps" }
        return "Thanks. Your free month is ready"
    }

    private var endBody: String {
        if case .subscriber = kind { return "Your answers help decide what Repster gets better at next." }
        return "Apple shows the code already filled in. Confirm it there and keep logging."
    }

    private var endButton: String {
        if case .subscriber = kind { return "Done" }
        return "Claim free month"
    }

    private func endAction() {
        if case .subscriber = kind {
            onDone()
        } else {
            onClaim()
        }
    }
}

// MARK: - Previews

#Preview("Claim") {
    FeedbackFlowView(
        kind: .freeMonth(.new, PlanPrices(monthly: "€1.99", yearly: "€22.99", lifetime: "€34.99")),
        startsAtEnd: true,
        onAnswer: { _, _ in },
        onQuestionsFinished: {},
        onClosedEarly: { _ in },
        onDone: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Subscriber done") {
    FeedbackFlowView(
        kind: .subscriber,
        startsAtEnd: true,
        onAnswer: { _, _ in },
        onQuestionsFinished: {},
        onClosedEarly: { _ in },
        onDone: {}
    )
    .preferredColorScheme(.dark)
}
