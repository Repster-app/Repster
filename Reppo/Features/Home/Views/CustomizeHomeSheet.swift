// CustomizeHomeSheet.swift
// Settings sheet for customizing home screen section visibility and order.

import SwiftUI

struct CustomizeHomeSheet: View {
    @Binding var config: HomeSectionConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(config.sections.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Text(config.sections[index].sectionId.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.textPrimary)

                            Spacer()

                            Toggle("", isOn: $config.sections[index].visible)
                                .labelsHidden()
                                .tint(Color.accent)
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
    }
}
