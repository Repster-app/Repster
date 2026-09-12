import XCTest

/// Session replay records the app legibly since 1.5 (`AnalyticsService.configureSessionReplay`),
/// so masking is now opt-in per field instead of opt-out per screen. That default fails
/// open: a text field added next month is recorded unless somebody remembers to mask it,
/// and nothing about the app looks wrong when they don't — the leak is only visible in
/// PostHog, weeks later.
///
/// This test is what stands in that gap. It reads the source rather than the running app,
/// and holds the full inventory of text entry in Repster. Adding a `TextField` or
/// `TextEditor` fails the build until it is classified here, which forces the question
/// "should a recording show this?" to be answered once, at the point of writing it.
///
/// When it fails on a field you just added, pick a disposition:
///   - `.masked`     the value must never appear — apply `replayMasked()` to the field
///   - `.paused`     the field lives in a `.alert`, where a mask cannot reach it — apply
///                   `replayPaused(while:)` to the view presenting the alert
///   - `.recorded`   a figure whose meaning is fixed by the field's purpose (reps, RIR,
///                   seconds, a factor) and which the event stream already carries in
///                   bucketed form
///
/// A `.masked` or `.paused` entry also asserts that its file still applies the matching
/// modifier, so deleting a mask fails here too.
///
/// Changing what is masked means changing `docs/privacy.html` and the App Review Notes in
/// `marketing/app-store/privacy-review-checklist.md` with it.
final class ReplayMaskCoverageTests: XCTestCase {

    private enum Disposition {
        case masked
        case paused
        case recorded
    }

    /// Keyed by the source line as written, because that is what a failure has to quote
    /// back for the message to be actionable. Reformatting a field re-opens the question,
    /// which is the intended cost.
    private static let inventory: [String: [String: Disposition]] = [
        "Features/Onboarding/Views/UnitsBodyweightStepView.swift": [
            #"TextField("Enter weight", text: $bodyweightInput)"#: .masked
        ],
        "Features/Settings/Views/Components/AddBodyweightEntrySheet.swift": [
            #"TextField("Weight", text: $weightText)"#: .masked
        ],
        "Features/Workout/Views/WorkoutSummarySheet.swift": [
            #"TextField("", text: $workoutTitle, prompt: Text(automaticWorkoutTitle).foregroundColor(.textSecondary))"#: .masked,
            #"TextEditor(text: $notes)"#: .masked,
            #"TextField("Template name", text: $controller.templateName)"#: .paused
        ],
        "Features/Workout/Views/EditWorkoutView.swift": [
            #"TextEditor(text: $viewModel.notesText)"#: .masked
        ],
        "Features/Workout/Views/SetTableView.swift": [
            #"TextField("Add a note…", text: $noteText)"#: .paused
        ],
        "Features/Workout/Views/RestTimerView.swift": [
            #"TextField("Seconds", text: $exactTimeText)"#: .recorded
        ],
        "Features/Workout/Views/Components/SetInputField.swift": [
            #"TextField(placeholder, text: $value)"#: .recorded
        ],
        "Features/Exercise/Views/CreateEditExerciseSheet.swift": [
            #"TextField("Exercise Name", text: $viewModel.name)"#: .masked,
            #"TextField("0.0", value: $viewModel.bodyweightFactor,"#: .recorded
        ],
        "Features/Templates/Views/CreateEditTemplateView.swift": [
            #"TextField("e.g. Push Day, Upper Body A...", text: $viewModel.templateName)"#: .masked,
            #"TextEditor(text: Binding("#: .masked,
            #"TextField("—", value: Binding("#: .recorded,
            // The two rep-bound fields that replaced the single "6-8" parser. Rep counts are
            // prescription numbers, not content the user authored — same call as RIR below.
            #"TextField(placeholder, text: text)"#: .recorded,
            #"TextField("RIR", text: $rirText)"#: .recorded,
            // A folder name is something the user wrote, like the template name above it.
            #"TextField("New folder name", text: $newFolderName)"#: .masked
        ],
        "Features/Templates/Views/TemplateFlowView.swift": [
            // A search query over template names is the same content as the names themselves.
            #"TextField("Search templates", text: $viewModel.searchText)"#: .masked
        ],
        "Features/Charts/Views/Components/ExerciseSelectionSheet.swift": [
            #"TextField("Preset name", text: $presetName)"#: .paused
        ]
    ]

    // MARK: - Tests

    /// Every text input in the app is classified, and nothing classified has disappeared.
    func testEveryTextInputIsClassified() throws {
        let found = try Self.textInputSites()

        var unclassified: [String] = []
        for (file, lines) in found {
            let known = Self.inventory[file] ?? [:]
            for line in lines where known[line] == nil {
                unclassified.append("\(file)\n      \(line)")
            }
        }

        XCTAssertTrue(
            unclassified.isEmpty,
            """
            New text entry with no session-replay decision behind it:

              \(unclassified.joined(separator: "\n\n  "))

            Classify each one in ReplayMaskCoverageTests.inventory, and apply the
            modifier that goes with the disposition you pick. See this file's header.
            """
        )

        var vanished: [String] = []
        for (file, lines) in Self.inventory {
            let present = found[file] ?? []
            for line in lines.keys where !present.contains(line) {
                vanished.append("\(file)\n      \(line)")
            }
        }

        XCTAssertTrue(
            vanished.isEmpty,
            """
            Classified text entry that is no longer in the source — deleted, moved or
            reformatted:

              \(vanished.joined(separator: "\n\n  "))

            Update ReplayMaskCoverageTests.inventory to match.
            """
        )
    }

    /// A file holding a masked field still applies the mask. Catches the case where the
    /// field survives a refactor and the modifier does not.
    func testMaskedFieldsStillCarryTheirModifier() throws {
        let root = Self.sourceRoot

        for (file, lines) in Self.inventory {
            let contents = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)

            if lines.values.contains(.masked) {
                XCTAssertTrue(
                    contents.contains("replayMasked()"),
                    "\(file) holds a field classified `.masked` but no longer calls replayMasked()."
                )
            }

            if lines.values.contains(.paused) {
                XCTAssertTrue(
                    contents.contains("replayPaused(while:"),
                    "\(file) holds a field classified `.paused` but no longer calls replayPaused(while:)."
                )
            }
        }
    }

    /// The inventory above only means anything under the inverted default. If masking
    /// goes back to being global, this test is measuring nothing — and the privacy copy
    /// that describes the current behaviour would be wrong too.
    func testGlobalDefaultIsStillInverted() throws {
        let config = try String(
            contentsOf: Self.sourceRoot.appendingPathComponent("Core/Services/AnalyticsService.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            config.contains("maskAllTextInputs = false"),
            """
            Session replay masking is no longer opt-in per field. If that is deliberate, \
            rewrite this test's premise, and update docs/privacy.html and the App Review \
            Notes in marketing/app-store/privacy-review-checklist.md to match.
            """
        )

        XCTAssertTrue(
            config.contains("maskAllSandboxedViews = true"),
            "Sandboxed views are drawn by another process and are not ours to record."
        )
    }

    // MARK: - Displayed notes

    /// Every place note text is *drawn*, as opposed to typed, outside `SetNoteStrip`.
    ///
    /// `testEveryTextInputIsClassified` only sees fields, so without this a
    /// `Text(set.notes ?? "")` added to some screen would put a note into recordings with
    /// nothing failing — and the privacy policy promises notes are hidden there. Set notes are
    /// drawn through `SetNoteStrip`, which masks itself and is checked by
    /// `testSetNoteStripStillMasks`, so it never needs an entry here.
    ///
    /// Keyed like `inventory`, by the source line as written. Each file listed must still call
    /// `replayMasked()`.
    private static let displayedNoteInventory: [String: Set<String>] = [
        "Features/Templates/Views/TemplateDetailView.swift": [
            #"Text(notes)"#
        ],
        "Features/Templates/Views/TemplateImportReviewSheet.swift": [
            #"Text(notes)"#,
            #"Text("Notes: \(notes)")"#
        ]
    ]

    /// Note text is never drawn without a decision behind it, and the files that draw it
    /// still mask.
    func testDisplayedNoteTextIsMasked() throws {
        let found = try Self.displayedNoteSites()

        var unlisted: [String] = []
        for (file, lines) in found {
            let known = Self.displayedNoteInventory[file] ?? []
            for line in lines where !known.contains(line) {
                unlisted.append("\(file)\n      \(line)")
            }
        }

        XCTAssertTrue(
            unlisted.isEmpty,
            """
            Note text drawn with no session-replay decision behind it:

              \(unlisted.joined(separator: "\n\n  "))

            Show a set note through SetNoteStrip, which masks itself. For any other note, apply
            replayMasked() to the Text and list the line in displayedNoteInventory.
            """
        )

        var vanished: [String] = []
        for (file, lines) in Self.displayedNoteInventory {
            let present = found[file] ?? []
            for line in lines where !present.contains(line) {
                vanished.append("\(file)\n      \(line)")
            }
        }

        XCTAssertTrue(
            vanished.isEmpty,
            """
            Listed note display that is no longer in the source — deleted, moved or reformatted:

              \(vanished.joined(separator: "\n\n  "))

            Update ReplayMaskCoverageTests.displayedNoteInventory to match.
            """
        )

        for file in Self.displayedNoteInventory.keys {
            let contents = try String(contentsOf: Self.sourceRoot.appendingPathComponent(file), encoding: .utf8)
            XCTAssertTrue(
                contents.contains("replayMasked()"),
                "\(file) draws note text but no longer calls replayMasked()."
            )
        }
    }

    /// The component every set note is drawn through still masks what it draws.
    func testSetNoteStripStillMasks() throws {
        let contents = try String(
            contentsOf: Self.sourceRoot.appendingPathComponent("Features/Workout/Views/Components/SetNoteStrip.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            contents.contains("replayMasked()"),
            "SetNoteStrip no longer masks the note. The privacy policy promises set notes are hidden from recordings."
        )
    }

    // MARK: - Source scanning

    /// `<repo>/Repster`, derived from this file rather than from the build environment so
    /// it holds for both a local run and CI.
    private static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RepsterTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Repster")
    }

    /// Every line declaring text entry, keyed by path relative to `Repster/`.
    private static func textInputSites() throws -> [String: Set<String>] {
        let root = sourceRoot
        let constructors = ["TextField(", "TextEditor(", "SecureField("]

        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw XCTSkip("Source tree not readable at \(root.path)")
        }

        var sites: [String: Set<String>] = [:]

        for case let url as URL in walker where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")

            for rawLine in contents.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)

                // A mention in a comment is not a field.
                guard !line.hasPrefix("//"), !line.hasPrefix("///"), !line.hasPrefix("*") else { continue }
                guard constructors.contains(where: { line.contains($0) }) else { continue }

                sites[relative, default: []].insert(line)
            }
        }

        return sites
    }

    /// Every line that passes code mentioning "note" to `Text(`, keyed by path relative to
    /// `Repster/`. String-literal text is ignored, so `Text("Add a note")` is not a match, but
    /// an interpolation inside a literal is code, so `Text("Notes: \(notes)")` is.
    private static func displayedNoteSites() throws -> [String: Set<String>] {
        let root = sourceRoot

        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw XCTSkip("Source tree not readable at \(root.path)")
        }

        var sites: [String: Set<String>] = [:]

        for case let url as URL in walker where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")

            for rawLine in contents.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)

                guard !line.hasPrefix("//"), !line.hasPrefix("///"), !line.hasPrefix("*") else { continue }
                guard textArgumentMentionsNote(in: line) else { continue }

                sites[relative, default: []].insert(line)
            }
        }

        return sites
    }

    /// Whether any `Text(` call on this line has "note" in its code — not in the text of a
    /// string literal. `SomethingText(` does not count.
    private static func textArgumentMentionsNote(in line: String) -> Bool {
        let chars = Array(line)
        let marker = Array("Text(")
        var i = 0

        while i + marker.count <= chars.count {
            let isCall = Array(chars[i..<(i + marker.count)]) == marker
            let startsWord = i == 0 || !(chars[i - 1].isLetter || chars[i - 1].isNumber || chars[i - 1] == "_")

            if isCall, startsWord,
               codeOutsideStringLiterals(chars[(i + marker.count)...]).lowercased().contains("note") {
                return true
            }
            i += 1
        }

        return false
    }

    /// `chars` with the text of string literals removed and `\( … )` interpolations kept.
    private static func codeOutsideStringLiterals(_ chars: ArraySlice<Character>) -> String {
        var code = ""
        var inLiteral = false
        var i = chars.startIndex

        while i < chars.endIndex {
            let c = chars[i]

            if !inLiteral {
                if c == "\"" {
                    inLiteral = true
                } else {
                    code.append(c)
                }
                i += 1
            } else if c == "\\", i + 1 < chars.endIndex, chars[i + 1] == "(" {
                var j = i + 2
                var depth = 1
                while j < chars.endIndex, depth > 0 {
                    if chars[j] == "(" {
                        depth += 1
                    } else if chars[j] == ")" {
                        depth -= 1
                    }
                    if depth > 0 {
                        code.append(chars[j])
                    }
                    j += 1
                }
                i = j
            } else {
                if c == "\"" {
                    inLiteral = false
                }
                i += 1
            }
        }

        return code
    }
}
