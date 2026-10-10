import Foundation
import Testing
@testable import PlannerCore

@Suite("Conditional prerequisite solver")
struct ConditionalPrerequisiteSolverTests {
    typealias F = PlaceholderPrerequisiteFixtures

    private func solve(
        _ f: (catalog: Catalog, input: ConditionalPrerequisiteInput, requests: [ConditionalPrerequisiteRequest]),
        forcedChoices: [String: String] = [:],
        limit: Int = 10_000
    ) throws -> ConditionalFeasibility {
        var budget = ConditionalSearchBudget(limitPerGroup: limit)
        return try ConditionalPrerequisiteSolver(catalog: f.catalog)
            .solve(f.requests, in: f.input, forcedChoices: forcedChoices, budget: &budget)
    }

    private func assignments(_ result: ConditionalFeasibility) -> [String: String]? {
        if case .feasible(let assignments, _) = result { return assignments }
        return nil
    }

    private func uses(_ result: ConditionalFeasibility) -> Set<ConditionalProviderUse> {
        if case .feasible(_, let uses) = result { return uses }
        return []
    }

    // MARK: Compatibility

    @Test func oneSlotCannotSupplyBothAAndB() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.all([.course("A"), .course("B")])])
        #expect(try solve(f) == .impossible)
    }

    @Test func twoSlotsSupplyBoth() throws {
        let f = F.makeInput(slots: [["A", "B"], ["A", "B"]], dependencies: [.all([.course("A"), .course("B")])])
        let chosen = try #require(assignments(try solve(f)))
        #expect(Set(chosen.values) == ["A", "B"])
        #expect(chosen.count == 2)
    }

    @Test func oneChoiceSupportsMultipleDependents() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A"), .course("A")])
        let result = try solve(f)
        #expect(assignments(result) == [F.slotID(0): "A"])
        #expect(uses(result) == Set(f.requests.map {
            ConditionalProviderUse(placeholderID: F.slotID(0), supportingCourseID: "A", dependent: $0.key)
        }))
    }

    @Test func orBranchPreserved() throws {
        let f = F.makeInput(slots: [["B"]], dependencies: [.any([.course("A"), .course("B")])])
        #expect(assignments(try solve(f)) == [F.slotID(0): "B"])
    }

    @Test func conflictingSeparateDependentsAreImpossible() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A"), .course("B")])
        #expect(try solve(f) == .impossible)
    }

    @Test func emptyMenuMeansFullCatalog() throws {
        let f = F.makeInput(slots: [[]], dependencies: [.course("A")])
        #expect(assignments(try solve(f)) == [F.slotID(0): "A"])
    }

    @Test func realCourseNeedsNoSlot() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")], extraItems: [0: ["A"]])
        #expect(assignments(try solve(f)) == [:])
    }

    @Test func resolvedOrAbsentSlotMetadataIsIgnored() throws {
        var f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        // The definition survives, but the slot is no longer in the schedule.
        var pathway = f.input.pathway
        pathway.semesters[0].courseIDs = []
        f.input = F.input(f.input, pathway: pathway)
        #expect(try solve(f) == .impossible)
    }

    @Test func alreadyScheduledLaterCourseIsNotDuplicatedThroughASlot() throws {
        // A is scheduled too late; an earlier slot must not invent a second A.
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")], extraItems: [1: ["A"]])
        #expect(try solve(f) == .impossible)
    }

    @Test func forcedIncompatibleChoiceIsImpossible() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        #expect(try solve(f, forcedChoices: [F.slotID(0): "B"]) == .impossible)
        #expect(assignments(try solve(f, forcedChoices: [F.slotID(0): "A"])) == [F.slotID(0): "A"])
    }

    @Test func forcedChoiceOutsideTheMenuIsImpossible() throws {
        let f = F.makeInput(slots: [["B"]], dependencies: [.course("A")])
        #expect(try solve(f, forcedChoices: [F.slotID(0): "A"]) == .impossible)
    }

    // MARK: Domain

    @Test func domainKeepsValidAlternatesInOrderWithoutDuplicates() {
        let f = F.makeInput(slots: [], dependencies: [])
        let spec = PlaceholderSpec(categoryID: "c", categoryName: "C", alternates: ["B", "missing", "A", "B"], credits: 3)
        #expect(PlaceholderCourseDomain.eligibleCourseIDs(for: spec, catalog: f.catalog) == ["B", "A"])
    }

    @Test func domainOfAnEmptyMenuIsTheCatalog() {
        let f = F.makeInput(slots: [], dependencies: [])
        let spec = PlaceholderSpec(categoryID: "c", categoryName: "C", alternates: [], credits: 3)
        #expect(PlaceholderCourseDomain.eligibleCourseIDs(for: spec, catalog: f.catalog) == f.catalog.courses.map(\.id))
    }

    // MARK: Provider feasibility

    @Test func sameTermDoesNotSupplyPrerequisite() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")], slotSemesterOffset: 1, dependentSemesterOffset: 1)
        #expect(try solve(f) == .impossible)
    }

    @Test func sameTermCanSupplyCorequisite() throws {
        var f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")], slotSemesterOffset: 1, dependentSemesterOffset: 1)
        f.requests = [ConditionalPrerequisiteRequest(
            key: ConditionalDependencyKey(courseID: "D0", semester: F.spring, kind: .corequisite),
            expression: .course("A")
        )]
        #expect(assignments(try solve(f)) == [F.slotID(0): "A"])
    }

    @Test func missingLabPreventsProvider() throws {
        let lecture = F.course("C100", code: "CHEM 100", corequisite: .course("C100L"))
        let lab = F.course("C100L", code: "CHEM 100L", credits: 1, corequisite: .course("C100"))
        let alone = F.makeInput(slots: [["C100"]], dependencies: [.course("C100")], extraCourses: [lecture, lab])
        #expect(try solve(alone) == .impossible)

        let withLab = F.makeInput(slots: [["C100"]], dependencies: [.course("C100")], extraCourses: [lecture, lab], extraItems: [0: ["C100L"]])
        #expect(assignments(try solve(withLab)) == [F.slotID(0): "C100"])

        // A second slot can hold the lab, but nothing invents one.
        let labSlot = F.makeInput(slots: [["C100"], ["C100L"]], dependencies: [.course("C100")], extraCourses: [lecture, lab])
        #expect(assignments(try solve(labSlot)) == [F.slotID(0): "C100", F.slotID(1): "C100L"])
    }

    @Test func standingAndKnownAvailabilityFilterProvider() throws {
        var juniorOnly = F.makeInput(
            slots: [["A"]],
            dependencies: [.course("A")],
            extraCourses: [F.course("A", code: "MATH 300", prerequisite: .standing(StandingRequirement(minimum: .junior)))]
        )
        juniorOnly.input = ConditionalPrerequisiteInput(
            pathway: juniorOnly.input.pathway,
            completedAtStart: [],
            standingBySemester: [F.fall: .sophomore, F.spring: .sophomore],
            workload: .light,
            activeProgramTitle: nil
        )
        #expect(try solve(juniorOnly) == .impossible)

        let springOnly = F.makeInput(
            slots: [["A"]],
            dependencies: [.course("A")],
            extraCourses: [F.course("A", code: "MATH 300", availability: [.spring])]
        )
        #expect(try solve(springOnly) == .impossible)

        // Unknown availability stays permissive.
        let unknown = F.makeInput(
            slots: [["A"]],
            dependencies: [.course("A")],
            extraCourses: [F.course("A", code: "MATH 300", availability: nil)]
        )
        #expect(assignments(try solve(unknown)) == [F.slotID(0): "A"])
    }

    @Test func hypotheticalFourCreditChoiceExceedsCap() throws {
        // Light load caps at 13: 10 real credits plus the 3-credit reservation.
        let fillers = (1...3).map { F.course("F\($0)", code: "ENG 10\($0)") } + [F.course("F4", code: "ENG 104", credits: 1)]
        let fourCredit = F.makeInput(
            slots: [["A", "B"]],
            dependencies: [.course("A")],
            extraCourses: fillers + [F.course("A", code: "MATH 300", credits: 4)],
            extraItems: [0: ["F1", "F2", "F3", "F4"]]
        )
        #expect(try solve(fourCredit) == .impossible)

        let threeCredit = F.makeInput(
            slots: [["A", "B"]],
            dependencies: [.course("B")],
            extraCourses: fillers + [F.course("A", code: "MATH 300", credits: 4)],
            extraItems: [0: ["F1", "F2", "F3", "F4"]]
        )
        #expect(assignments(try solve(threeCredit)) == [F.slotID(0): "B"])
    }

    @Test func upstreamCycleCannotBootstrap() throws {
        let f = F.makeInput(
            slots: [["A"], ["B"]],
            dependencies: [.course("A")],
            extraCourses: [
                F.course("A", code: "MATH 300", prerequisite: .course("B")),
                F.course("B", code: "MATH 336", prerequisite: .course("A"))
            ]
        )
        #expect(try solve(f) == .impossible)
    }

    @Test func chainThroughEarlierSlotIsFeasible() throws {
        // D0 (spring) needs A; A needs B; B must come from an earlier slot.
        let semesters = [F.fall, F.spring, SemesterIdentity(year: 2027, term: .fall)]
        var f = F.makeInput(
            slots: [["A"]],
            dependencies: [.course("A")],
            extraCourses: [F.course("A", code: "MATH 300", prerequisite: .course("B"))]
        )
        var pathway = f.input.pathway
        pathway.semesters = [
            SemesterPlan(id: semesters[0], courseIDs: [F.slotID(1)]),
            SemesterPlan(id: semesters[1], courseIDs: [F.slotID(0)]),
            SemesterPlan(id: semesters[2], courseIDs: ["D0"])
        ]
        pathway.placeholders[F.slotID(1)] = PlaceholderSpec(categoryID: F.categoryID, categoryName: "Choose a Course", alternates: ["B"], credits: 3)
        f.input = F.input(f.input, pathway: pathway)
        f.requests = [ConditionalPrerequisiteRequest(
            key: ConditionalDependencyKey(courseID: "D0", semester: semesters[2], kind: .prerequisite),
            expression: .course("A")
        )]
        let result = try solve(f)
        #expect(assignments(result) == [F.slotID(0): "A", F.slotID(1): "B"])
        // The upstream slot is credited to the real course it ultimately serves.
        #expect(uses(result).contains(ConditionalProviderUse(placeholderID: F.slotID(1), supportingCourseID: "B", dependent: f.requests[0].key)))
    }

    @Test func workLimitIsUnconfirmed() throws {
        let f = F.makeInput(slots: [["A", "B"], ["A", "B"]], dependencies: [.all([.course("A"), .course("B")])])
        #expect(try solve(f, limit: 1) == .unconfirmed)
    }

    @Test func cancelledSearchThrows() async throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let task = Task { () throws -> ConditionalFeasibility in
            withUnsafeCurrentTask { $0?.cancel() }
            var budget = ConditionalSearchBudget()
            return try ConditionalPrerequisiteSolver(catalog: f.catalog).solve(f.requests, in: f.input, budget: &budget)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func solvingDoesNotMutateTheInputPathway() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let before = f.input.pathway
        _ = try solve(f)
        #expect(f.input.pathway == before)
        #expect(f.input.pathway.resolvedPlaceholders.isEmpty)
    }
}

