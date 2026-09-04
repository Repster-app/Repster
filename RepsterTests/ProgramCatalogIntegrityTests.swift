// ProgramCatalogIntegrityTests.swift
// Guards the join between seed_programs.json and seed_exercises.json.
//
// This is the highest-value test in the onboarding redesign: the two files are edited
// independently, by hand, and a mistyped exercise name would otherwise fail silently at
// runtime — the user picks a program and quietly gets a session missing a lift.
//
// Both files are read from disk rather than a bundle, so the test does not depend on either
// resource being a member of the test target.

import XCTest
@testable import Repster

final class ProgramCatalogIntegrityTests: XCTestCase {

    // MARK: - Fixtures

    private static func repositoryRoot(from filePath: StaticString = #filePath) -> URL {
        // .../RepsterTests/ProgramCatalogIntegrityTests.swift -> repository root
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func resourceURL(_ name: String) -> URL {
        Self.repositoryRoot()
            .appendingPathComponent("Repster/Resources/\(name)")
    }

    private func loadPrograms() throws -> [ProgramSeedDTO] {
        let data = try Data(contentsOf: resourceURL("seed_programs.json"))
        return try JSONDecoder().decode(ProgramSeedFile.self, from: data).programs
    }

    private func loadExerciseNames() throws -> Set<String> {
        let data = try Data(contentsOf: resourceURL("seed_exercises.json"))
        let file = try JSONDecoder().decode(SeedExerciseFile.self, from: data)
        return Set(file.exercises.map(\.name))
    }

    // MARK: - The join

    func testEveryProgramExerciseResolvesToASeededExercise() throws {
        let programs = try loadPrograms()
        let known = try loadExerciseNames()

        var unresolved: [String] = []
        for program in programs {
            for session in program.sessions {
                for entry in session.exercises where !known.contains(entry.exercise) {
                    unresolved.append("\(program.id) / \(session.name) / \(entry.exercise)")
                }
            }
        }

        XCTAssertTrue(
            unresolved.isEmpty,
            "Program entries name exercises that are not in seed_exercises.json:\n"
                + unresolved.joined(separator: "\n")
        )
    }

    // MARK: - Catalogue shape

    func testCatalogueIsNotEmptyAndIdsAreUnique() throws {
        let programs = try loadPrograms()
        XCTAssertFalse(programs.isEmpty)

        let ids = programs.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate program ids: \(ids)")

        let names = programs.map(\.name)
        XCTAssertEqual(Set(names).count, names.count,
                       "Duplicate program names — these become folder names: \(names)")
    }

    func testEverySessionHasExercisesAndEveryEntryIsCoherent() throws {
        for program in try loadPrograms() {
            XCTAssertFalse(program.sessions.isEmpty, "\(program.id) has no sessions")
            XCTAssertGreaterThan(program.daysPerWeek, 0, "\(program.id) daysPerWeek")

            let sessionNames = program.sessions.map(\.name)
            XCTAssertEqual(Set(sessionNames).count, sessionNames.count,
                           "\(program.id) has duplicate session names: \(sessionNames)")

            for session in program.sessions {
                XCTAssertFalse(session.exercises.isEmpty,
                               "\(program.id) / \(session.name) has no exercises")

                for entry in session.exercises {
                    let where_ = "\(program.id) / \(session.name) / \(entry.exercise)"
                    XCTAssertGreaterThan(entry.sets, 0, "\(where_) sets")
                    XCTAssertGreaterThan(entry.repMin, 0, "\(where_) repMin")
                    XCTAssertLessThanOrEqual(entry.repMin, entry.repMax, "\(where_) repMin > repMax")
                    if let rir = entry.rir {
                        XCTAssertTrue((0...5).contains(rir), "\(where_) rir out of range: \(rir)")
                    }
                    if let rest = entry.restSeconds {
                        XCTAssertGreaterThan(rest, 0, "\(where_) restSeconds")
                    }
                }
            }
        }
    }

    /// Templates prescribe reps and RIR, never weight — the suggestion engine supplies the load.
    /// A DURATION-tracked exercise (Plank, Running) has no meaningful rep range, so keeping the
    /// catalogue to WEIGHT_REPS keeps every generated TemplateSet coherent.
    func testCatalogueUsesOnlyWeightRepsExercises() throws {
        let data = try Data(contentsOf: resourceURL("seed_exercises.json"))
        let file = try JSONDecoder().decode(SeedExerciseFile.self, from: data)
        let trackingByName = Dictionary(uniqueKeysWithValues: file.exercises.map { ($0.name, $0.trackingType) })

        var offenders: [String] = []
        for program in try loadPrograms() {
            for session in program.sessions {
                for entry in session.exercises {
                    guard let tracking = trackingByName[entry.exercise] else { continue }
                    if tracking != "WEIGHT_REPS" {
                        offenders.append("\(program.id) / \(entry.exercise) is \(tracking)")
                    }
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty,
                      "Catalogue uses non WEIGHT_REPS exercises:\n" + offenders.joined(separator: "\n"))
    }
}
