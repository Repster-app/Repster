// TemplateDetailViewModel.swift
// The template detail screen: what a template prescribes, before you commit to running it.
//
// This surface did not exist. Tapping a template started a workout immediately, so the only way to
// see what was in one was to start it and then look at the workout.

import SwiftUI

// MARK: - Layout

/// One entry in the detail list: either a lone exercise or a superset block holding a pair.
enum TemplateDetailRow: Identifiable {
    case single(number: Int, exercise: TemplateExerciseDetail)
    case superset(id: UUID, letter: String, members: [TemplateDetailSupersetMember])

    var id: String {
        switch self {
        case .single(_, let exercise): return exercise.id.uuidString
        case .superset(let id, _, _): return "group-\(id.uuidString)"
        }
    }
}

struct TemplateDetailSupersetMember: Identifiable {
    /// "3a", "3b" — the position shared with its partner, disambiguated by letter.
    let label: String
    let exercise: TemplateExerciseDetail

    var id: UUID { exercise.id }
}

/// Pure shaping for the detail list. Kept off the view model so the numbering and grouping rules are
/// testable without a service.
enum TemplateDetailLayout {

    /// Group letters, matching the template editor's palette. See SUPERSETS_SCOPING.md §6: the letter
    /// is the group's identity and colour is only reinforcement, cycling every four.
    static let groupLetters = ["A", "B", "C", "D", "E"]

    static func color(forGroupIndex index: Int) -> Color {
        let palette: [Color] = [.accent, .chart5, .chart7, .chart8]
        return palette[index % palette.count]
    }

    static func letter(forGroupIndex index: Int) -> String {
        index < groupLetters.count ? groupLetters[index] : "\(index + 1)"
    }

    /// Collapses **adjacent** exercises sharing a group into one block.
    ///
    /// Only adjacent ones: SUPERSETS_SCOPING.md §6 constraint 1 requires a group to be contiguous, and
    /// data that predates that — or arrived through import, where a free-text group key maps to a
    /// UUID — can break it. A stray member renders on its own rather than being silently reordered or
    /// dropped, which keeps what is on screen honest about what is stored.
    static func rows(for exercises: [TemplateExerciseDetail]) -> [TemplateDetailRow] {
        let ordered = exercises.sorted { $0.orderInTemplate < $1.orderInTemplate }
        var rows: [TemplateDetailRow] = []
        var position = 0
        var index = 0

        while index < ordered.count {
            let exercise = ordered[index]

            guard let groupId = exercise.supersetGroupId else {
                position += 1
                rows.append(.single(number: position, exercise: exercise))
                index += 1
                continue
            }

            var run = [exercise]
            var lookahead = index + 1
            while lookahead < ordered.count, ordered[lookahead].supersetGroupId == groupId {
                run.append(ordered[lookahead])
                lookahead += 1
            }

            position += 1
            if run.count == 1 {
                // A group of one. Today's editor makes these trivially — assign a letter, never do
                // the second half — so they exist in real libraries. Render it as an ordinary
                // exercise rather than an empty-looking block; the stored id is untouched.
                rows.append(.single(number: position, exercise: exercise))
            } else {
                let members = run.enumerated().map { offset, member in
                    TemplateDetailSupersetMember(
                        label: "\(position)\(Character(UnicodeScalar(97 + min(offset, 25))!))",
                        exercise: member
                    )
                }
                rows.append(.superset(id: groupId, letter: "", members: members))
            }
            index = lookahead
        }

        return assignLetters(to: rows)
    }

    /// Letters are assigned by encounter order, so the first group on screen is A whatever UUID it holds.
    private static func assignLetters(to rows: [TemplateDetailRow]) -> [TemplateDetailRow] {
        var groupIndex = 0
        return rows.map { row in
            guard case .superset(let id, _, let members) = row else { return row }
            let letter = letter(forGroupIndex: groupIndex)
            groupIndex += 1
            return .superset(id: id, letter: letter, members: members)
        }
    }

    static func groupIndex(forLetter letter: String) -> Int {
        groupLetters.firstIndex(of: letter) ?? 0
    }

    /// "3 × 6–8", or "3 × 8" when a fixed target was authored.
    static func prescription(for sets: [TemplateSetDetail]) -> String? {
        let working = sets.filter { $0.setType != .warmup }
        guard let first = working.first else { return nil }

        let reps: String?
        switch (first.targetRepMin, first.targetRepMax) {
        case let (.some(min), .some(max)) where min == max: reps = "\(min)"
        case let (.some(min), .some(max)): reps = "\(min)–\(max)"
        case let (.some(min), .none): reps = "\(min)+"
        case let (.none, .some(max)): reps = "≤\(max)"
        case (.none, .none): reps = nil
        }

        guard let reps else { return "\(working.count) set\(working.count == 1 ? "" : "s")" }
        return "\(working.count) × \(reps)"
    }

    static func warmupCount(for sets: [TemplateSetDetail]) -> Int {
        sets.filter { $0.setType == .warmup }.count
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class TemplateDetailViewModel {

    var detail: TemplateDetail?
    var isLoading = false
    var loadFailed = false

    private let templateId: UUID
    private let templateService: TemplateServiceProtocol

    init(templateId: UUID, templateService: TemplateServiceProtocol) {
        self.templateId = templateId
        self.templateService = templateService
    }

    var rows: [TemplateDetailRow] {
        TemplateDetailLayout.rows(for: detail?.exercises ?? [])
    }

    var exerciseCount: Int { detail?.exercises.count ?? 0 }
    var setCount: Int { detail?.template.totalSetCount ?? 0 }
    var folder: String? { detail?.template.folder }

    /// Reads `lastUsedAt`, which is stamped when a workout **starts**, so this is "last opened from
    /// here" rather than "last completed". Labelled Last used for exactly that reason. A true
    /// times-done count needs `Workout.templateId`, which does not exist yet.
    var lastUsedDescription: String {
        guard let lastUsed = detail?.template.lastUsedAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUsed, relativeTo: Date())
    }

    func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        do {
            detail = try await templateService.fetchTemplateDetail(templateId)
            loadFailed = detail == nil
        } catch {
            dbg("[TemplateDetailViewModel] Failed to load template: \(error)")
            loadFailed = true
        }
    }
}
