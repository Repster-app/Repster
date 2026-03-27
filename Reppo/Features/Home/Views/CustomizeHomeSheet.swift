// CustomizeHomeSheet.swift
// Settings sheet for customizing home screen section order, visibility, and display preferences.

import SwiftUI

struct CustomizeHomeSheet: View {
    @Binding var config: HomeSectionConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Section Order & Visibility
                Section {
                    ForEach($config.sections) { $entry in
                        if entry.sectionId.isSupportedHomeSection {
                            HStack(spacing: 12) {
                                Text(entry.sectionId.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)

                                Spacer()

                                Toggle("", isOn: $entry.visible)
                                    .labelsHidden()
                                    .tint(Color.accent)
                            }
                        }
                    }
                    .onMove { from, to in
                        config.sections.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Drag to reorder, toggle to show or hide")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                }

                // MARK: - Recent Workouts Count
                Section {
                    Stepper(
                        "Show \(config.recentWorkoutsCount) workouts",
                        value: $config.recentWorkoutsCount,
                        in: 1...10
                    )
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                } header: {
                    Text("Recent Workouts")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                }

                // MARK: - PR Display Mode
                Section {
                    ForEach(PRDisplayMode.allCases, id: \.self) { mode in
                        Button {
                            config.prDisplayMode = mode
                        } label: {
                            HStack {
                                Text(mode.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                if config.prDisplayMode == mode {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Personal Records Layout")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                } footer: {
                    Text("Compact shows 6 PRs in a two-column grid")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        config.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            config.save()
        }
    }
}
