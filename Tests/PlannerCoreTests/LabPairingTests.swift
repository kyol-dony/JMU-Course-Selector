import Foundation
import Testing
@testable import PlannerCore

/// Lecture/lab pairs that must share a semester, derived from coreqs.
@Suite("Lab pairing rules")
struct LabPairingTests {
    /// Course shapes from the live catalog.
    static func catalog() -> Catalog {
        func course(_ code: String, _ raw: String? = nil, credits: Int = 3) -> Course {
            Course(
                id: code.replacingOccurrences(of: " ", with: ""),
                code: code,
                title: code,
                credits: credits,
                availability: [.fall, .spring],
                prerequisites: [],
                rawPrerequisiteText: raw
            )
        }
        return Catalog.fixture(
            courses: [
                course("BIO 140", "Prerequisites: BIO 140L . Corequisites: BIO 140L ."),
                course("BIO 140L", "Prerequisites: BIO 140 . Corequisites: BIO 140 .", credits: 1),
                course("CHEM 131", "Corequisites: CHEM 131 ."),
                course("CHEM 131L", "Corequisites: CHEM 131 .", credits: 1),
                course("CHEM 135L", "Corequisites: CHEM 131 .", credits: 1),
                course("CHEM 132", "Prerequisites: CHEM 131 . Corequisites: CHEM 132L or CHEM 136L ."),
                course("CHEM 132L", "Prerequisites: CHEM 131 .", credits: 1),
                course("CHEM 136L", "Corequisites: CHEM 132 .", credits: 1),
                course("PHYS 140"),
                course("PHYS 140L", "Prerequisites: PHYS 140 . Corequisites: PHYS 140 .", credits: 1),
                course("BIO 103"),
                course("BIO 245", "Prerequisites: BIO 245L and BIO 103 or BIO 140 . Corequisites: BIO 245L and BIO 103 or BIO 140 ."),
                course("BIO 245L", "Corequisites: BIO 245 and BIO 103 or BIO 140 / BIO 140L .", credits: 1),
                course("NSG 453"),
                course("NSG 453L", "Corequisites: NSG 453 .", credits: 1),
                course("NSG 456", "Corequisites: NSG 453 and NSG 453L .")
            ],
            program: Program.fixture(id: "p", title: "P", requirements: [])
        )
    }

    private let pairing = LabPairing(catalog: Self.catalog())

    @Test("a lecture whose coreqs name its lab needs that lab", arguments: [
        ("BIO140", ["BIO140L"]),
        ("BIO245", ["BIO245L"]),
        ("CHEM132", ["CHEM132L", "CHEM136L"])
    ])
    func lectureNeedsLab(lecture: String, labs: [String]) {
        #expect(pairing.labOptions(forLecture: lecture) == labs)
    }

    @Test("a lecture whose coreqs don't name its own lab can stand alone", arguments: [
        "PHYS140",  // only PHYS 140L names the other
        "CHEM131",  // catalog text glitch: its coreq names itself
        "NSG456",   // names another course's lab
        "BIO103"
    ])
    func lectureStandsAlone(lecture: String) {
        #expect(pairing.labOptions(forLecture: lecture).isEmpty)
    }

    @Test("a lab needs its lecture", arguments: [
        ("BIO140L", ["BIO140"]),
        ("CHEM132L", ["CHEM132"]),  // named only by the lecture
        ("CHEM136L", ["CHEM132"]),  // differently numbered lecture
        ("CHEM135L", ["CHEM131"]),
        ("PHYS140L", ["PHYS140"]),
        ("BIO245L", ["BIO245"]),    // ignores the other courses its coreq lists
        ("NSG453L", ["NSG453"])
    ])
    func labNeedsLecture(lab: String, lectures: [String]) {
        #expect(pairing.lectures(forLab: lab) == lectures)
    }

    @Test("lab placeholders round-trip their lecture")
    func labPlaceholderID() {
        let id = LabPairing.labPlaceholderID(forLecture: "CHEM132")
        #expect(PathwayPlaceholder.isPlaceholder(id))
        #expect(LabPairing.lecture(forLabPlaceholder: id) == "CHEM132")
        #expect(LabPairing.lecture(forLabPlaceholder: PathwayPlaceholder.id(categoryID: "core", optionIndex: 0)) == nil)
    }
}

@Suite("Lab pairing warnings")
struct LabPairingWarningTests {
    static let fall = SemesterIdentity(year: 2026, term: .fall)
    static let spring = SemesterIdentity(year: 2027, term: .spring)

    private func warnings(_ fallCourses: [String], _ springCourses: [String] = []) -> [ConflictWarning] {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: Self.fall, courseIDs: fallCourses),
            SemesterPlan(id: Self.spring, courseIDs: springCourses)
        ])
        return ConflictDetector(catalog: LabPairingTests.catalog()).warnings(for: pathway, overrides: [])
    }

    private func labWarnings(_ fallCourses: [String], _ springCourses: [String] = []) -> [ConflictWarning] {
        warnings(fallCourses, springCourses).filter { $0.kind == .labNotPaired }
    }

    @Test("a lecture without its lab that semester must be fixed")
    func lectureWithoutLab() throws {
        let warning = try #require(labWarnings(["BIO140"]).first)
        #expect(warning.courseID == "BIO140")
        #expect(warning.kind.severity == .mustFix)
        #expect(warning.summary == "Needs BIO 140L this term")
        #expect(warning.missingCourseIDs == ["BIO140L"])
        #expect(labWarnings(["BIO140", "BIO140L"]).isEmpty)
    }

    @Test("a lab a semester apart from its lecture flags both")
    func splitPair() {
        let flagged = labWarnings(["BIO140"], ["BIO140L"])
        #expect(Set(flagged.map(\.courseID)) == ["BIO140", "BIO140L"])
        #expect(flagged.first { $0.courseID == "BIO140L" }?.summary == "Take with BIO 140")
    }

    @Test("any listed lab, or the lab placeholder, pairs a lecture with lab choices")
    func labChoices() {
        #expect(labWarnings(["CHEM132", "CHEM136L"]).isEmpty)
        #expect(labWarnings(["CHEM132", LabPairing.labPlaceholderID(forLecture: "CHEM132")]).isEmpty)
        #expect(labWarnings(["CHEM132"]).first?.summary == "Needs CHEM 132L or CHEM 136L this term")
    }

    @Test("an optional lab leaves its lecture alone but still needs the lecture")
    func optionalLab() {
        #expect(labWarnings(["PHYS140"]).isEmpty)
        #expect(labWarnings(["PHYS140L"]).map(\.courseID) == ["PHYS140L"])
    }

    @Test("lab pairs aren't also reported as missing corequisites")
    func noDuplicateCoreqWarning() {
        let coreqs = warnings(["BIO140"], ["BIO140L"]).filter { $0.kind == .missingCorequisite }
        #expect(!coreqs.contains { $0.courseID == "BIO140" || $0.courseID == "BIO140L" })
        // Other coreqs still are: NSG 456 needs NSG 453 and 453L, not its own lab.
        #expect(warnings(["NSG456"]).contains { $0.courseID == "NSG456" && $0.kind == .missingCorequisite })
    }
}

@Suite("Lab pairing board operations")
struct LabPairingBoardTests {
    static let fall = SemesterIdentity(year: 2026, term: .fall)
    static let spring = SemesterIdentity(year: 2027, term: .spring)
    private let pairing = LabPairing(catalog: LabPairingTests.catalog())

    private func pathway(_ fall: [String], _ spring: [String] = [], placeholders: [String: PlaceholderSpec] = [:]) -> Pathway {
        Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: Self.fall, courseIDs: fall),
            SemesterPlan(id: Self.spring, courseIDs: spring)
        ], placeholders: placeholders)
    }

    private func items(_ pathway: Pathway) -> [[String]] { pathway.semesters.map(\.courseIDs) }

    @Test("moving a lecture brings its lab, and moving a lab brings its lecture")
    func pairedMove() {
        let start = pathway(["MATH1", "BIO140", "BIO140L"])
        #expect(items(pairing.moving("BIO140", to: Self.spring, at: nil, in: start)) == [["MATH1"], ["BIO140", "BIO140L"]])
        #expect(items(pairing.moving("BIO140L", to: Self.spring, at: nil, in: start)) == [["MATH1"], ["BIO140L", "BIO140"]])
    }

    @Test("a lab placeholder moves with its lecture")
    func placeholderMovesWithLecture() {
        let lab = LabPairing.labPlaceholderID(forLecture: "CHEM132")
        let moved = pairing.moving("CHEM132", to: Self.spring, at: 0, in: pathway(["CHEM132", lab]))
        #expect(items(moved) == [[], ["CHEM132", lab]])
    }

    @Test("an unpaired course moves alone")
    func unpairedMove() {
        let moved = pairing.moving("PHYS140", to: Self.spring, at: nil, in: pathway(["PHYS140", "BIO140L"]))
        #expect(items(moved) == [["BIO140L"], ["PHYS140"]])
    }

    @Test("adding a lecture with one lab adds that lab beside it")
    func addSingleLab() {
        let added = pairing.addingLab(for: "BIO140", in: Self.fall, to: pathway(["BIO140"]))
        #expect(items(added) == [["BIO140", "BIO140L"], []])
    }

    @Test("adding a lecture with lab choices adds a lab placeholder")
    func addLabPlaceholder() throws {
        let added = pairing.addingLab(for: "CHEM132", in: Self.fall, to: pathway(["CHEM132"]))
        let lab = LabPairing.labPlaceholderID(forLecture: "CHEM132")
        #expect(items(added) == [["CHEM132", lab], []])
        let spec = try #require(added.placeholders[lab])
        #expect(spec.alternates == ["CHEM132L", "CHEM136L"])
        #expect(spec.categoryName == "Lab for CHEM 132")
        #expect(spec.credits == 1)
    }

    @Test("a lab already in the plan is pulled in instead of adding another")
    func reuseExistingLab() {
        let added = pairing.addingLab(for: "CHEM132", in: Self.fall, to: pathway(["CHEM132"], ["CHEM136L"]))
        #expect(items(added) == [["CHEM132", "CHEM136L"], []])
        #expect(added.placeholders.isEmpty)
    }

    @Test("lectures without a required lab add nothing")
    func noLabNeeded() {
        let start = pathway(["PHYS140"])
        #expect(pairing.addingLab(for: "PHYS140", in: Self.fall, to: start) == start)
    }
}

@Suite("Lab pairing drop previews")
struct LabPairingDropVerdictTests {
    @Test("dragging a lecture previews the paired move, so it doesn't split")
    func previewMovesPair() {
        let fall = SemesterIdentity(year: 2026, term: .fall)
        let spring = SemesterIdentity(year: 2027, term: .spring)
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: fall, courseIDs: ["BIO140", "BIO140L"]),
            SemesterPlan(id: spring, courseIDs: [])
        ])
        let verdicts = DropVerdictCalculator(catalog: LabPairingTests.catalog())
            .verdicts(moving: "BIO140", in: pathway, overrides: [])
        #expect(verdicts[spring]?.newWarnings.contains { $0.kind == .labNotPaired } == false)
        #expect(verdicts[spring]?.level == .clear)
    }
}

@Suite("Lab pairing in schedule generation")
struct LabPairingGeneratorTests {
    private func generate(_ options: [[String]]) throws -> (Pathway, Catalog) {
        var catalog = LabPairingTests.catalog()
        catalog.programs = [Program.fixture(id: "p", title: "P", requirements: [
            RequirementCategory(id: "core", name: "Required Core", requiredCredits: 9, courseOptions: options)
        ])]
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "p",
            workload: .standard,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)
        return (pathway, catalog)
    }

    private func semester(of item: String, in pathway: Pathway) -> SemesterIdentity? {
        pathway.semesters.first { $0.courseIDs.contains(item) }?.id
    }

    @Test("a lecture is scheduled with its lab, in the same semester")
    func lectureGetsLab() throws {
        let (pathway, catalog) = try generate([["BIO140"], ["CHEM131"], ["CHEM132"]])
        let bio = try #require(semester(of: "BIO140", in: pathway))
        #expect(semester(of: "BIO140L", in: pathway) == bio)

        let lab = LabPairing.labPlaceholderID(forLecture: "CHEM132")
        #expect(pathway.placeholders[lab]?.alternates == ["CHEM132L", "CHEM136L"])
        #expect(semester(of: lab, in: pathway) == semester(of: "CHEM132", in: pathway))

        // Same-semester pairs satisfy each other, including BIO 140's
        // catalog-listed "prerequisite" BIO 140L.
        let warnings = ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: [])
        #expect(!warnings.contains { $0.kind == .labNotPaired })
        #expect(!warnings.contains { $0.kind == .missingPrerequisite && ["BIO140", "BIO140L"].contains($0.courseID) })
    }

    @Test("a lab the requirements list on its own gets its lecture beside it")
    func listedLabGetsLecture() throws {
        let (pathway, catalog) = try generate([["BIO140L"], ["PHYS140L"]])
        #expect(semester(of: "BIO140", in: pathway) == semester(of: "BIO140L", in: pathway))
        #expect(semester(of: "PHYS140", in: pathway) == semester(of: "PHYS140L", in: pathway))
        let warnings = ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: [])
        #expect(!warnings.contains { $0.kind == .labNotPaired })
    }

    @Test("a lab the requirements already list is used instead of a placeholder")
    func listedLabIsReused() throws {
        let (pathway, _) = try generate([["CHEM131"], ["CHEM132"], ["CHEM136L"]])
        #expect(pathway.placeholders[LabPairing.labPlaceholderID(forLecture: "CHEM132")] == nil)
        #expect(semester(of: "CHEM136L", in: pathway) == semester(of: "CHEM132", in: pathway))
    }
}
