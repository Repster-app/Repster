// ExercisePRsView.swift
// Renders the suffix-max filtered rep-max PR table.
// Spec: FR-006, SC-004
// Contract: view-contracts.md ExercisePRsView
// Feature: 007-exercise-list-and-detail WP04 T019

import SwiftUI

struct ExercisePRsView: View {

    let prTable: [PRTableEntry]
    let unitPreference: UnitPreference
    var isPerSide: Bool = false

    // MARK: - Body

    var body: some View {
        if prTable.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    if isPerSide {
                        perSideHint
                    }

                    headerRow

                    Divider().background(Color.border)

                    ForEach(prTable, id: \.reps) { entry in
                        prRow(entry)
                        Divider().background(Color.border)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Header Row

    private var perSideHint: some View {
        HStack {
            Text("PRs use the stronger side and are shown per side.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.bgCard)
        .cornerRadius(10)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var headerRow: some View {
        HStack {
            Text("REPS")
                .frame(width: 50, alignment: .leading)
            Spacer()
            Text("WEIGHT")
            Spacer()
            Text("DATE")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.textTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - PR Row

    private func prRow(_ entry: PRTableEntry) -> some View {
        HStack {
            Text("\(entry.reps)")
                .font(.system(size: 15, weight: entry.reps == 1 ? .bold : .semibold))
                .foregroundStyle(entry.reps == 1 ? Color.gold : Color.textPrimary)
                .frame(width: 50, alignment: .leading)

            Spacer()

            Text(formatWeight(entry.value))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text(formatDate(entry.date))
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(entry.reps == 1 ? Color.goldSoft : Color.clear)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "trophy")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("No PRs recorded yet")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Formatting

    private func formatWeight(_ weight: Double) -> String {
        UnitConversion.formatWeightLabel(weight, unitPreference: unitPreference)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
