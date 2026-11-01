// FeedbackQuestionsView.swift
// Three one-tap questions, one per screen. Shared by the free month for feedback and the
// subscriber thank-you card. Scoping: FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md §2.3, §3.2.
//
// Multiple choice only, never free text: the privacy policy promises that for in-app surveys.
// Each option carries a fixed id, which is what analytics records, so the wording can change
// without breaking the data already collected.

import SwiftUI

struct FeedbackOption: Identifiable, Equatable {
    /// Stable snake_case id, recorded as the `answer`. Never the label.
    let id: String
    let label: String
}

struct FeedbackQuestion: Identifiable, Equatable {
    let id: String
    let text: String
    let options: [FeedbackOption]
}

enum FeedbackQuestions {
    static func freeMonth(customerType: CustomerType, prices: PlanPrices) -> [FeedbackQuestion] {
        [firstFreeMonthQuestion(for: customerType), missMost, planChoice(prices: prices)]
    }

    static let subscriber: [FeedbackQuestion] = [
        FeedbackQuestion(id: "why_upgraded", text: "What made you upgrade?", options: [
            FeedbackOption(id: "ran_out", label: "I ran out of free workouts"),
            FeedbackOption(id: "suggestions", label: "Smart suggestions"),
            FeedbackOption(id: "charts", label: "Charts and progress"),
            FeedbackOption(id: "insights", label: "Insights"),
            FeedbackOption(id: "support_app", label: "To support the app")
        ]),
        FeedbackQuestion(id: "improve_next", text: "What should Repster get better at next?", options: [
            FeedbackOption(id: "suggestions", label: "Suggestions"),
            FeedbackOption(id: "charts", label: "Charts and progress"),
            FeedbackOption(id: "templates_programs", label: "Templates and programs"),
            FeedbackOption(id: "logging_speed", label: "Logging speed"),
            FeedbackOption(id: "something_else", label: "Something else")
        ]),
        FeedbackQuestion(id: emailFollowUpId, text: "Would you tell me more by email?", options: [
            FeedbackOption(id: emailFollowUpYesId, label: "Yes, open an email"),
            FeedbackOption(id: "not_now", label: "Not now")
        ])
    ]

    /// The subscriber set's last question. Its "Yes" opens the feedback email draft.
    static let emailFollowUpId = "email_followup"
    static let emailFollowUpYesId = "yes_email"

    /// A lapsed subscriber already upgraded once, so "what stopped you from upgrading" would
    /// read oddly. They get "why did you stop" under its own id instead.
    private static func firstFreeMonthQuestion(for customerType: CustomerType) -> FeedbackQuestion {
        switch customerType {
        case .new:
            return FeedbackQuestion(id: "why_not_upgraded", text: "What stopped you from upgrading?", options: [
                FeedbackOption(id: "price", label: "The price"),
                FeedbackOption(id: "not_sure_worth_it", label: "Not sure it's worth it yet"),
                FeedbackOption(id: "prefer_one_time", label: "I'd rather pay once"),
                FeedbackOption(id: "something_missing", label: "Something's missing"),
                FeedbackOption(id: "didnt_know_limit", label: "I didn't know I'd run out")
            ])
        case .lapsed:
            return FeedbackQuestion(id: "why_cancelled", text: "Why did you stop your subscription?", options: [
                FeedbackOption(id: "price", label: "The price"),
                FeedbackOption(id: "not_training", label: "I'm not training right now"),
                FeedbackOption(id: "something_missing", label: "Something's missing"),
                FeedbackOption(id: "other_app", label: "I use another app now"),
                FeedbackOption(id: "didnt_mean_to_cancel", label: "I didn't mean to cancel")
            ])
        }
    }

    private static let missMost = FeedbackQuestion(id: "miss_most", text: "What would you miss most?", options: [
        FeedbackOption(id: "logging", label: "Logging workouts"),
        FeedbackOption(id: "charts", label: "Charts and progress"),
        FeedbackOption(id: "suggestions", label: "Smart suggestions"),
        FeedbackOption(id: "insights", label: "Insights"),
        FeedbackOption(id: "templates", label: "Templates")
    ])

    /// Prices come from the store for the user's own country (BG pays €0.99 a month, DE €1.99),
    /// so a missing price drops out of the label rather than being guessed.
    private static func planChoice(prices: PlanPrices) -> FeedbackQuestion {
        func label(_ name: String, _ price: String?) -> String {
            guard let price else { return name }
            return "\(name) · \(price)"
        }
        return FeedbackQuestion(id: "plan_choice", text: "Which plan would you pick?", options: [
            FeedbackOption(id: "monthly", label: label("Monthly", prices.monthly)),
            FeedbackOption(id: "yearly", label: label("Yearly", prices.yearly)),
            FeedbackOption(id: "lifetime", label: label("Lifetime", prices.lifetime)),
            FeedbackOption(id: "none", label: "None of these")
        ])
    }
}

struct FeedbackQuestionsView: View {
    let title: String
    let questions: [FeedbackQuestion]
    /// The fine print under each question, by index.
    let finePrint: (Int) -> String
    let onAnswer: (FeedbackQuestion, FeedbackOption) -> Void
    let onFinished: () -> Void
    /// Closed before the last answer, with the question that was on screen.
    let onClose: (FeedbackQuestion) -> Void

    @State private var index = 0

    var body: some View {
        let question = questions[min(index, questions.count - 1)]

        VStack(spacing: 0) {
            FeedbackTopBar(
                title: title,
                onBack: index > 0 ? { withAnimation(.easeInOut(duration: 0.2)) { index -= 1 } } : nil,
                onClose: { onClose(question) }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach(questions.indices, id: \.self) { position in
                            Capsule()
                                .fill(position <= index ? Color.accent : Color.bgSubtle)
                                .frame(height: 4)
                        }
                    }
                    .accessibilityHidden(true)

                    Text("Question \(index + 1) of \(questions.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 24)
                        .padding(.bottom, 6)

                    Text(question.text)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 24)

                    VStack(spacing: 10) {
                        ForEach(question.options) { option in
                            Button {
                                choose(option, in: question)
                            } label: {
                                optionRow(option)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            Text(finePrint(index))
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .background(Color.bg.ignoresSafeArea())
    }

    private func optionRow(_ option: FeedbackOption) -> some View {
        HStack(spacing: 12) {
            Text(option.label)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bgSubtle, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func choose(_ option: FeedbackOption, in question: FeedbackQuestion) {
        onAnswer(question, option)
        if index + 1 < questions.count {
            withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
        } else {
            onFinished()
        }
    }
}

/// Back on the left when there is somewhere to go back to, the title, and Close on the right.
struct FeedbackTopBar: View {
    let title: String
    let onBack: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()

            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Previews

#Preview("Free month, new") {
    FeedbackQuestionsView(
        title: "Free month",
        questions: FeedbackQuestions.freeMonth(
            customerType: .new,
            prices: PlanPrices(monthly: "€1.99", yearly: "€22.99", lifetime: "€34.99")
        ),
        finePrint: { _ in "Answer all 3 to get your free month. Answers are anonymous." },
        onAnswer: { _, _ in },
        onFinished: {},
        onClose: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Free month, lapsed") {
    FeedbackQuestionsView(
        title: "Free month",
        questions: FeedbackQuestions.freeMonth(customerType: .lapsed, prices: PlanPrices()),
        finePrint: { _ in "Answer all 3 to get your free month. Answers are anonymous." },
        onAnswer: { _, _ in },
        onFinished: {},
        onClose: { _ in }
    )
    .preferredColorScheme(.dark)
}
