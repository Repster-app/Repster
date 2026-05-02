// ChartPreset.swift
// Model and persistence store for saved exercise chart selections.
// Feature: 016-charts-tab-v2 WP09 (T129)

import Foundation

struct ChartPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var exerciseIds: [UUID]

    init(id: UUID = UUID(), name: String, exerciseIds: [UUID]) {
        self.id = id
        self.name = name
        self.exerciseIds = exerciseIds
    }
}

final class ChartPresetStore {
    private let key = "chartExercisePresets"

    func loadPresets() -> [ChartPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([ChartPreset].self, from: data) else {
            return []
        }
        return presets
    }

    func savePreset(_ preset: ChartPreset) {
        var presets = loadPresets()
        presets.append(preset)
        persist(presets)
    }

    func deletePreset(_ id: UUID) {
        var presets = loadPresets()
        presets.removeAll { $0.id == id }
        persist(presets)
    }

    func updatePreset(_ preset: ChartPreset) {
        var presets = loadPresets()
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
            persist(presets)
        }
    }

    private func persist(_ presets: [ChartPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
