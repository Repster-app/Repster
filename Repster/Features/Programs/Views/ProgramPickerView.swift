// ProgramPickerView.swift
// Pick a starter program. Deliberately standalone, with two call sites: onboarding step 2,
// and a sheet from the Templates screen.
//
// The second call site is what makes this worth building as its own view. Onboarding-only would
// mean a "build my own" user never gets a program, nobody can change program after a cycle, and
// a reset leaves the user with nothing — see ONBOARDING_REDESIGN_SCOPING.md §5.

import SwiftUI

/// Explicit three-state choice. `undecided` and `buildOwn` are genuinely different — one means
/// the CTA should stay disabled, the other is a deliberate answer — so nil cannot model both.
enum ProgramChoice: Equatable {
    case undecided
    case program(ProgramSeedDTO)
    case buildOwn

    var program: ProgramSeedDTO? {
        if case .program(let program) = self { return program }
        return nil
    }

    var isDecided: Bool { self != .undecided }
}

struct ProgramPickerView: View {
    let programs: [ProgramSeedDTO]
    @Binding var choice: ProgramChoice
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    VStack(spacing: 8) {
                        ForEach(programs) { program in
                            programCard(program)
                        }
                    }

                    buildOwnLink

                    if let program = choice.program {
                        rotationPreview(program)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            continueButton
        }
        .background(Color.bg)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick a program to run")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            Text("We build the sessions for you. Swap exercises, or change program, whenever you like.")
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Cards

    private func programCard(_ program: ProgramSeedDTO) -> some View {
        let isOn = choice.program?.id == program.id

        return Button {
            choice = .program(program)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Text(program.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Spacer(minLength: 0)

                    Text("\(program.daysPerWeek) DAYS")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(isOn ? Color.accent : Color.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isOn ? Color.accent.opacity(0.18) : Color.bgSubtle)
                        .cornerRadius(5)

                    selectionTick(isOn: isOn)
                }

                Text(program.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? Color.accentSoft : Color.bgCard)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isOn ? Color.accent.opacity(0.35) : Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(program.name), \(program.daysPerWeek) days per week, \(program.summary)")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func selectionTick(isOn: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isOn ? Color.accent : Color.white.opacity(0.04))
                .frame(width: 18, height: 18)

            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    /// An escape hatch, not a peer of the real programs — so it is a link, not a fifth card.
    private var buildOwnLink: some View {
        Button {
            choice = (choice == .buildOwn) ? .undecided : .buildOwn
        } label: {
            Text("I'd rather build my own")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(choice == .buildOwn ? Color.accent : Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 15)
                .padding(.bottom, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rotation preview

    private func rotationPreview(_ program: ProgramSeedDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR ROTATION")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                Text(rotationSummary(program))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            FlowLayout(spacing: 6) {
                ForEach(program.sessions, id: \.name) { session in
                    Text(session.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.bgSubtle)
                        .cornerRadius(6)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
        .padding(.top, 16)
    }

    /// 5×5 alternates two sessions across three days, so "2 sessions" beside "3 DAYS" reads like
    /// a bug unless it is spelled out.
    private func rotationSummary(_ program: ProgramSeedDTO) -> String {
        let count = program.sessionCount
        if count < program.daysPerWeek {
            return "\(count) sessions, alternating across \(program.daysPerWeek) days"
        }
        return "\(count) sessions, saved as templates"
    }

    // MARK: - Continue

    private var continueButton: some View {
        VStack(spacing: 0) {
            Button(action: onContinue) {
                Text(continueTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!choice.isDecided)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 34)
    }

    private var continueTitle: String {
        switch choice {
        case .undecided: return "Choose a program"
        case .buildOwn: return "Start from scratch"
        case .program(let program): return "Start with \(program.name)"
        }
    }
}
