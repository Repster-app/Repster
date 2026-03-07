// TabPlaceholderViews.swift
// Placeholder content for tabs not yet implemented.
// These will be replaced by real feature views in future features.

import SwiftUI

struct ProgramsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("Programs")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
    }
}

struct CalendarPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("Calendar")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
    }
}

struct ChartsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("Charts")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
    }
}
