import Foundation
import Testing
@testable import PlannerCore

@Suite("Generation through unresolved prerequisite slots")
struct PlaceholderScheduleGeneratorTests {
    typealias F = PlaceholderPrerequisiteFixtures

    private func generate(_ catalog: Catalog, strict: Bool = true, workload: WorkloadPreference = .light) throws -> [Pathway] {
        try ScheduleGenerator(catalog: catalog, strictPrereqs: strict).generatePathways(
            for: F.programID,
            workload: workload,
            transferCredits: [],
            starting: F.fall
        )
    }

    private func index(of item: String, in pathway: Pathway) -> Int? {
        pathway.semesters.firstIndex { $0.courseIDs.contains(item) }
    }

    /// The fixture catalog plus a required category of extra courses.
    private func catalog(slots: [[String]], dependencies: [PrereqExpr], extraCourses: [Course] = [], required: [String] = []) -> Catalog {
        var catalog = F.makeInput(slots: slots, dependencies: dependencies, extraCourses: extraCourses).catalog
        if !required.isEmpty {
            catalog.programs[0].requirements.append(RequirementCategory(
                id: "fillers", name: "Required Fillers", requiredCredits: 3 * required.count, courseOptions: required.map { [$0] }
            ))
        }
        return catalog
    }

    @Test func strictGenerationPlacesDependentAfterSlot() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let path = try #require(try generate(f.catalog).first)
        #expect(path.semesters[0].courseIDs.contains(F.slotID(0)))
        #expect(path.semesters[1].courseIDs.contains("D0"))
        #expect(path.resolvedPlaceholders.isEmpty)
        #expect(!path.semesters.flatMap(\.courseIDs).contains("A"))
    }

    @Test func everyStrategyLeavesTheSlotUnresolved() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let paths = try generate(f.catalog)
        #expect(paths.count == 3)
        for path in paths {
            let slot = try #require(index(of: F.slotID(0), in: path))
            let dependent = try #require(index(of: "D0", in: path))
            #expect(slot < dependent)
            #expect(path.resolvedPlaceholders.isEmpty)
            #expect(!path.semesters.flatMap(\.courseIDs).contains("A"))
        }
    }

    @Test func neededSlotGoesEarlyDespiteAHighMedianLevel() throws {
        // The slot's menu is mostly 400-level, which alone would hold it back
        // behind eight 100-level requirements.
        let fillers = (1...8).map { F.course("F\($0)", code: "ENG 1\($0)0") }
        let advanced = [F.course("X1", code: "MATH 440"), F.course("X2", code: "MATH 441")]
        let catalog = catalog(
            slots: [["A", "X1", "X2"]],
            dependencies: [.course("A")],
            extraCourses: fillers + advanced,
            required: fillers.map(\.id)
        )
        let path = try #require(try generate(catalog).first)
        #expect(index(of: F.slotID(0), in: path) == 0)
        let dependent = try #require(index(of: "D0", in: path))
        #expect(dependent >= 1 && dependent < 3)
    }

    @Test func twoSlotsFeedAMultiStepChain() throws {
        // D0 needs A; A needs B; each comes from its own slot.
        let catalog = catalog(
            slots: [["B", "Y1"], ["A", "Y2"]],
            dependencies: [.course("A")],
            extraCourses: [
                F.course("A", code: "MATH 300", prerequisite: .course("B")),
                F.course("Y1", code: "ENG 101"),
                F.course("Y2", code: "ENG 102")
            ]
        )
        let path = try #require(try generate(catalog).first)
        let b = try #require(index(of: F.slotID(0), in: path))
        let a = try #require(index(of: F.slotID(1), in: path))
        let d = try #require(index(of: "D0", in: path))
        #expect(b < a && a < d)
        #expect(path.resolvedPlaceholders.isEmpty)
    }

    // MARK: Regressions

    @Test func dependentNeverSharesItsSupplyingSlotsSemester() throws {
        // Heavy load has room for both in one term; the prerequisite still
        // has to come first.
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let path = try #require(try generate(f.catalog, workload: .heavy).first)
        let slot = try #require(index(of: F.slotID(0), in: path))
        let dependent = try #require(index(of: "D0", in: path))
        #expect(slot < dependent)
    }

    @Test func tooLatePrerequisiteIsNotDuplicatedThroughASlot() throws {
        // A is a required spring-only course that doesn't fit in the first,
        // full spring, so it lands a year later. A slot in that first spring
        // also lists A, but it must not stand in for a second, earlier
        // enrollment of A that would let D0 go before the real one.
        let fillers = (1...7).map { F.course("F\($0)", code: "ENG 1\($0)0") }
        let catalog = catalog(
            slots: [["A", "Z"]],
            dependencies: [.course("A")],
            extraCourses: fillers + [F.course("Z", code: "ENG 101"), F.course("A", code: "MATH 300", availability: [.spring])],
            required: fillers.map(\.id) + ["A"]
        )
        let path = try #require(try generate(catalog).first)
        let a = try #require(index(of: "A", in: path))
        let dependent = try #require(index(of: "D0", in: path))
        #expect(a < dependent)
    }

    @Test func providerUnavailableInTheSlotsTermWaitsForAUsefulTerm() throws {
        // A is offered only in spring, so the slot goes to spring to supply it.
        let catalog = catalog(
            slots: [["A", "B"]],
            dependencies: [.course("A")],
            extraCourses: [F.course("A", code: "MATH 300", availability: [.spring])]
        )
        let path = try #require(try generate(catalog).first)
        let slot = try #require(index(of: F.slotID(0), in: path))
        let dependent = try #require(index(of: "D0", in: path))
        #expect(path.semesters[slot].id.term == .spring)
        #expect(slot < dependent)
    }

    @Test func noFeasibleRouteStillFailsStrictly() throws {
        let f = F.makeInput(slots: [["B", "Z"]], dependencies: [.course("A")], extraCourses: [F.course("Z", code: "ENG 101")])
        #expect(throws: PlannerError.self) { try generate(f.catalog) }
        // Non-strict generation still falls back to best effort.
        let path = try #require(try generate(f.catalog, strict: false).first)
        #expect(path.semesters.flatMap(\.courseIDs).contains("D0"))
    }

    @Test func anchoredPrefixLabIsNotManufactured() throws {
        // The preserved fall slot offers lecture C100, which needs lab C100L
        // beside it; nothing may add that lab to the preserved semester.
        let lecture = F.course("C100", code: "CHEM 100", corequisite: .course("C100L"))
        let lab = F.course("C100L", code: "CHEM 100L", credits: 1, corequisite: .course("C100"))
        let catalog = catalog(
            slots: [["C100", "Z"]],
            dependencies: [.course("C100")],
            extraCourses: [lecture, lab, F.course("Z", code: "ENG 101")]
        )
        let prefix = Pathway(
            id: "p", name: "P",
            semesters: [SemesterPlan(id: F.fall, courseIDs: [F.slotID(0)])],
            placeholders: [F.slotID(0): PlaceholderSpec(categoryID: F.categoryID, categoryName: "Choose a Course", alternates: ["C100", "Z"], credits: 3)]
        )
        func regenerate(strict: Bool) throws -> Pathway {
            try ScheduleGenerator(catalog: catalog, strictPrereqs: strict).regeneratePathway(
                from: prefix, through: F.fall, for: F.programID, strategy: .balanced,
                workload: .light, transferCredits: []
            )
        }
        #expect(throws: PlannerError.self) { try regenerate(strict: true) }
        let result = try regenerate(strict: false)
        #expect(result.semesters.first == prefix.semesters.first)
    }

    @Test func cancelledGenerationThrows() async throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let task = Task { () throws -> [Pathway] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ScheduleGenerator(catalog: f.catalog, strictPrereqs: true).generatePathways(
                for: F.programID, workload: .light, transferCredits: [], starting: F.fall
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func openElectivesDontCrowdOutEarlyRequirements() throws {
        // Four 100-level requirements, four Open Electives (which offer every
        // course) and one restricted slot offering the A that D0 needs. Only
        // that restricted slot should be pulled forward.
        let fillers = (1...4).map { F.course("F\($0)", code: "ENG 1\($0)0") }
        var catalog = catalog(
            slots: [["A", "Z"]],
            dependencies: [.course("A")],
            extraCourses: fillers + [F.course("Z", code: "ENG 101")],
            required: fillers.map(\.id)
        )
        // Open Electives come from padding a major to 120 credits.
        catalog.programs[0].requirements.append(RequirementCategory(
            id: "bulk", name: "Required Bulk", requiredCredits: 51,
            courseOptions: (1...17).map { ["G\($0)"] }
        ))
        catalog.courses += (1...17).map { F.course("G\($0)", code: "HIST 3\($0 + 10)") }
        let path = try #require(try generate(catalog).first)
        let first = path.semesters[0].courseIDs
        #expect(first.contains(F.slotID(0)))
        #expect(first.filter { $0.hasPrefix("F") }.count == 3)
        #expect(!first.contains { $0.contains("open-elective") })
    }
}

