import Foundation
import Testing
@testable import PlannerCore

@Suite struct AnchoredScheduleGeneratorTests {
    private let fall = SemesterIdentity(year: 2026, term: .fall)
    private func regenerate(_ source: Pathway, catalog: Catalog, programID: String = "cs",
                            credits: [TransferCredit] = [], extras: [Program] = [], hours: Double? = nil,
                            strict: Bool = false) throws -> Pathway {
        try ScheduleGenerator(catalog: catalog, strictPrereqs: strict).regeneratePathway(
            from: source, through: source.semesters.last!.id, for: programID, strategy: .balanced,
            workload: .light, transferCredits: credits, additionalPrograms: extras, earnedHoursAtStart: hours)
    }
    @Test func anchoredPrerequisitesAndCorequisites() throws {
        var catalog = AnchoredRegenerationFixtures.prerequisiteCatalog()
        catalog.courses[1].corequisiteExpr = .course("CS149")
        let source = Pathway(id: "path-2", name: "Crafted", semesters: [.init(id: fall, courseIDs: ["CS149"])])
        let result = try regenerate(source, catalog: catalog, strict: true)
        #expect(result.id == "path-2" && result.name == "Crafted")
        #expect(result.semesters.first == source.semesters.first)
        #expect(result.semesters[1].courseIDs == ["CS159"])
        #expect(result.semesters[1].id == .init(year: 2027, term: .spring))
        #expect(!ConflictDetector(catalog: catalog).warnings(for: result, overrides: []).contains { $0.courseID == "CS159" && ($0.kind == .missingPrerequisite || $0.kind == .missingCorequisite) })
    }
    @Test func warningsDoNotModifyAnchors() throws {
        var source = AnchoredRegenerationFixtures.pathway()
        source.semesters[0].courseIDs += ["CS159"]
        let anchors = Array(source.semesters.prefix(2))
        let result = try ScheduleGenerator(catalog: AnchoredRegenerationFixtures.prerequisiteCatalog()).regeneratePathway(
            from: source, through: anchors[1].id, for: "cs", strategy: .genEdFirst, workload: .standard, transferCredits: [])
        #expect(result.semesters == anchors)
        #expect(result.placeholders.count == 2) // only definitions present in the source
        #expect(result.resolvedPlaceholders == ["__pl::choice::1": "CS149", "__pl::suffix::1": "CS159"])
        #expect(ConflictDetector(catalog: AnchoredRegenerationFixtures.prerequisiteCatalog()).warnings(for: result, overrides: []).contains { $0.kind == .missingPrerequisite })
    }
    @Test func reservedSlotDoesNotGrantPrerequisite() throws {
        let slot = "__pl::core::0"
        var c = AnchoredRegenerationFixtures.prerequisiteCatalog()
        c.programs[0].requirements[0].courseOptions[0] = ["CS149", "ALT"]
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: [slot])],
                        placeholders: [slot: .init(categoryID: "core", categoryName: "Core", alternates: ["CS149", "ALT"], credits: 3)])
        #expect(throws: PlannerError.self) { try regenerate(p, catalog: c, strict: true) }
        let result = try regenerate(p, catalog: c)
        #expect(result.semesters.first == p.semesters.first)
        #expect(result.semesters.dropFirst().flatMap(\.courseIDs) == ["CS159"])
        #expect(result.semesters.flatMap(\.courseIDs).filter { $0 == slot }.count == 1)
        #expect(ConflictDetector(catalog: c).warnings(for: result, overrides: []).contains { $0.courseID == "CS159" && $0.kind == .missingPrerequisite })
    }
    @Test func resolvedAndSharedElectiveReservations() throws {
        let courses = (1...5).map { Course(id: "EL\($0)", code: "EL 10\($0)", title: "Elective", credits: 3, availability: [.fall, .spring], prerequisites: []) }
        let major = Program.fixture(id: "m", title: "M", requirements: [.init(id: "choice", name: "Electives", requiredCredits: 9, courseOptions: courses.map { [$0.id] })])
        let extra = Program.fixture(id: "extra", title: "Extra", requirements: [.init(id: "other", name: "Required", requiredCredits: 3, courseOptions: [["EL2"]])])
        let c = Catalog.fixture(courses: courses, program: major)
        let s = PlaceholderSpec(categoryID: "choice", categoryName: "Electives", alternates: courses.map(\.id), credits: 3)
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: ["__pl::choice::0", "EL1"])],
                        placeholders: ["__pl::choice::0": s, "__pl::choice::1": s],
                        resolvedPlaceholders: ["__pl::choice::1": "EL1"])
        let r = try regenerate(p, catalog: c, programID: "m", extras: [extra])
        #expect(r.semesters.first == p.semesters.first)
        #expect(r.semesters.dropFirst().flatMap(\.courseIDs) == ["EL2"])
        #expect(r.placeholders == p.placeholders)
        #expect(r.resolvedPlaceholders == p.resolvedPlaceholders)
    }
    @Test func ordinarySlotsAndNewIDsRetainExactReservations() throws {
        let courses = ["A", "B", "C", "D"].map { Course(id: $0, code: $0, title: $0, credits: 3, availability: nil, prerequisites: []) }
        let c = Catalog.fixture(courses: courses, program: .fixture(id: "m", title: "M", requirements: [
            .init(id: "choice", name: "Core", requiredCredits: 6, courseOptions: [["A", "B"], ["C", "D"]])]))
        let spec = PlaceholderSpec(categoryID: "choice", categoryName: "Core", alternates: ["A", "B"], credits: 3)
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: ["__pl::choice::0"])], placeholders: ["__pl::choice::0": spec])
        let r = try regenerate(p, catalog: c, programID: "m")
        #expect(r.semesters.dropFirst().flatMap(\.courseIDs) == ["__pl::choice::1"])
        #expect(r.placeholders["__pl::choice::0"] == spec)
    }
    @Test func fractionalPriorAndAnchorHoursCountOnce() throws {
        let c = AnchoredRegenerationFixtures.degreeCatalog()
        let p = Pathway(id: "path-1", name: "P", semesters: [.init(id: fall, courseIDs: ["REQ1"], creditOverrides: ["REQ1": 1.5])])
        let prior = [TransferCredit(sourceDescription: "General", courseIDs: [], credits: 10.5)]
        let r = try regenerate(p, catalog: c, programID: "degree", credits: prior)
        #expect(r.placeholders.values.reduce(0.0) { $0 + $1.credits } == 21)
        #expect(AcademicCreditCalculator.projectedHours(in: r.semesters, placeholders: r.placeholders, transferCredits: prior, catalog: c) == 120)
        let repeated = [p.semesters[0], .init(id: fall.next, courseIDs: ["REQ1", "ZZZ"], creditOverrides: ["REQ1": 3, "ZZZ": 1.5])]
        #expect(AcademicCreditCalculator.projectedHours(in: repeated, placeholders: [:], transferCredits: [.init(sourceDescription: "Award", courseIDs: ["REQ1"], credits: 2)], catalog: c) == 3.5)
    }
    @Test func anchoredOpenSlotShrinksFutureAllowanceWithoutCollision() throws {
        let c = AnchoredRegenerationFixtures.degreeCatalog()
        let slot = "__pl::open-elective::0"
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: [slot])],
                        placeholders: [slot: .init(categoryID: "open-elective", categoryName: "Open Elective", alternates: [], credits: 3)])
        let r = try regenerate(p, catalog: c, programID: "degree")
        let suffix = r.semesters.dropFirst().flatMap(\.courseIDs)
        #expect(!suffix.contains(slot))
        #expect(suffix.filter(PathwayPlaceholder.isPlaceholder).reduce(0.0) { $0 + r.placeholders[$1]!.credits } == 27)
        #expect(AcademicCreditCalculator.projectedHours(in: r.semesters, placeholders: r.placeholders, transferCredits: [], catalog: c) == 120)
    }
    @Test(arguments: ["BIO140", "BIO140L"]) func boundaryDoesNotMoveLectureOrLab(_ anchor: String) throws {
        var c = LabPairingTests.catalog()
        c.programs[0].requirements = [.init(id: "core", name: "Required", requiredCredits: 4, courseOptions: [["BIO140"], ["BIO140L"]])]
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: [anchor])])
        let r = try regenerate(p, catalog: c, programID: "p")
        #expect(r.semesters.first == p.semesters.first)
        #expect(r.semesters.flatMap(\.courseIDs).filter { $0 == anchor }.count == 1)
        #expect(r.semesters.dropFirst().flatMap(\.courseIDs).count == 1)
    }
    @Test func standingAndTimingRetainOffsets() throws {
        var c = AnchoredRegenerationFixtures.prerequisiteCatalog()
        c.courses[1].prerequisiteExpr = .standing(.init(minimum: .junior))
        c.courses[1].prerequisites = []
        c.programs[0].requirements[0].courseOptions = [["CS159"]]
        let semesters = (0..<4).reduce(into: [SemesterPlan]()) { a, _ in a.append(.init(id: a.last?.id.next ?? fall, courseIDs: [])) }
        let p = Pathway(id: "p", name: "P", semesters: semesters)
        let r = try regenerate(p, catalog: c, strict: true)
        #expect(r.semesters.last?.id == .init(year: 2028, term: .fall))
        let slot = "__pl::open-elective::0"
        let creditP = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: [slot])],
                             placeholders: [slot: .init(categoryID: "open-elective", categoryName: "Open", alternates: [], credits: 3)])
        let earned = try regenerate(creditP, catalog: c, hours: 57, strict: true)
        #expect(earned.semesters.last?.id == fall.next)
    }
    @Test func lastCutoffCanAppendOrHaveNoSuffix() throws {
        let c = AnchoredRegenerationFixtures.prerequisiteCatalog()
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: [])])
        #expect(try regenerate(p, catalog: c).semesters.count == 3)
        let done = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: ["CS149", "CS159"])])
        #expect(try regenerate(done, catalog: c).semesters == done.semesters)
    }
    @Test func retainedResolutionKeyWithoutDefinitionStillReservesID() throws {
        let c = AnchoredRegenerationFixtures.degreeCatalog()
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: ["REQ1"])],
                        resolvedPlaceholders: ["__pl::open-elective::0": "REQ1"])
        let r = try regenerate(p, catalog: c, programID: "degree")
        #expect(!r.semesters.dropFirst().flatMap(\.courseIDs).contains("__pl::open-elective::0"))
        #expect(r.resolvedPlaceholders == p.resolvedPlaceholders)
    }
    @Test func preferencesUseElapsedCalendarAcrossGaps() throws {
        let ids = ["LOW100", "HIGH400", "WELL101", "WELL102"]
        let courses = ids.map { Course(id: $0, code: $0, title: $0, credits: 7, availability: nil, prerequisites: []) }
        let c = Catalog.fixture(courses: courses, program: .fixture(id: "m", title: "M", requirements: [
            .init(id: "core", name: "Core", requiredCredits: 14, courseOptions: [["LOW100"], ["HIGH400"]]),
            .init(id: "c5", name: "Wellness Domain [C5W]", requiredCredits: 7, courseOptions: [["WELL101", "WELL102"]])
        ]))
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: []), .init(id: .init(year: 2029, term: .spring), courseIDs: [])])
        let r = try regenerate(p, catalog: c, programID: "m")
        #expect(r.semesters[2].courseIDs == ["__pl::c5::0"])
        #expect(r.semesters[3].courseIDs == ["HIGH400"])
    }
    @Test func unavailableFutureUsesExistingStrictBehavior() throws {
        var c = AnchoredRegenerationFixtures.prerequisiteCatalog()
        c.courses[1].availability = []
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: ["CS149"])])
        #expect(throws: PlannerError.self) { try regenerate(p, catalog: c, strict: true) }
    }
    @Test func cancellationStopsBuilder() async throws {
        let c = AnchoredRegenerationFixtures.degreeCatalog()
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: fall, courseIDs: [])])
        let task = Task.detached {
            try ScheduleGenerator(catalog: c).regeneratePathway(from: p, through: p.semesters[0].id,
                for: "degree", strategy: .balanced, workload: .light, transferCredits: [],
                progress: { _, _, _ in withUnsafeCurrentTask { $0?.cancel() } })
        }
        do { _ = try await task.value; Issue.record("Canceled generation returned a result") }
        catch { #expect(error is CancellationError) }
    }
}
