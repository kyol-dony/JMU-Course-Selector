import Foundation
import Testing
@testable import PlannerCore

@Suite("Placeholder prerequisite analyzer")
struct PlaceholderPrerequisiteAnalyzerTests {
    typealias F = PlaceholderPrerequisiteFixtures

    private func analyze(
        _ f: (catalog: Catalog, input: ConditionalPrerequisiteInput, requests: [ConditionalPrerequisiteRequest]),
        limit: Int = 10_000
    ) throws -> PlaceholderPrerequisiteAnalysis {
        try PlaceholderPrerequisiteAnalyzer(catalog: f.catalog, workLimitPerGroup: limit).analyze(f.input)
    }

    @Test func retainsCompatibleAlternativesInsteadOfFirstWitness() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.any([.course("A"), .course("B")])])
        let result = try analyze(f)
        #expect(result.statusByDependency[f.requests[0].key] == .conditional)
        #expect(result.supportsByPlaceholder[F.slotID(0)]?["A"] == Set([f.requests[0].key]))
        #expect(result.supportsByPlaceholder[F.slotID(0)]?["B"] == Set([f.requests[0].key]))
    }

    @Test func laterDependencyNarrowsEarlierChoice() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.any([.course("A"), .course("B")]), .course("B")])
        let result = try analyze(f)
        #expect(result.statusByDependency[f.requests[0].key] == .conditional)
        #expect(result.statusByDependency[f.requests[1].key] == .conditional)
        #expect(result.supportsByPlaceholder[F.slotID(0)]?["A"] == nil)
        #expect(result.supportsByPlaceholder[F.slotID(0)]?["B"] == Set(f.requests.map(\.key)))
    }

    @Test func singleSlotConflictStaysUnmet() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A"), .course("B")])
        let result = try analyze(f)
        #expect(result.statusByDependency[f.requests[0].key] == .conditional)
        #expect(result.statusByDependency[f.requests[1].key] == .unmet)
        #expect(result.supportsByPlaceholder[F.slotID(0)] == ["A": Set([f.requests[0].key])])
    }

    @Test func chainAnnotationsNameRootDependent() throws {
        // D0 (Fall 2027) needs A from a Spring slot; A needs B from a Fall slot.
        var f = F.makeInput(
            slots: [["A"]],
            dependencies: [.course("A")],
            extraCourses: [F.course("A", code: "MATH 300", prerequisite: .course("B"))]
        )
        let fall27 = SemesterIdentity(year: 2027, term: .fall)
        var pathway = f.input.pathway
        pathway.semesters = [
            SemesterPlan(id: F.fall, courseIDs: [F.slotID(1)]),
            SemesterPlan(id: F.spring, courseIDs: [F.slotID(0)]),
            SemesterPlan(id: fall27, courseIDs: ["D0"])
        ]
        pathway.placeholders[F.slotID(1)] = PlaceholderSpec(categoryID: F.categoryID, categoryName: "Choose a Course", alternates: ["B"], credits: 3)
        f.input = F.input(f.input, pathway: pathway)
        let d0 = ConditionalDependencyKey(courseID: "D0", semester: fall27, kind: .prerequisite)

        let result = try analyze(f)
        #expect(result.statusByDependency[d0] == .conditional)
        #expect(result.supportsByPlaceholder[F.slotID(0)] == ["A": Set([d0])])
        #expect(result.supportsByPlaceholder[F.slotID(1)] == ["B": Set([d0])])
    }

    // MARK: Regressions

    /// D0 needs A and B from two shared slots (a larger search); D1 needs C
    /// from its own slot. They're separate groups with separate budgets.
    private func twoGroups() -> (catalog: Catalog, input: ConditionalPrerequisiteInput, requests: [ConditionalPrerequisiteRequest]) {
        var f = F.makeInput(
            slots: [["A", "B"], ["A", "B"]],
            dependencies: [.all([.course("A"), .course("B")]), .course("C")],
            extraCourses: [F.course("C", code: "PHYS 140")]
        )
        var pathway = f.input.pathway
        pathway.semesters[0].courseIDs.append(F.slotID(2))
        pathway.placeholders[F.slotID(2)] = PlaceholderSpec(categoryID: F.categoryID, categoryName: "Choose a Course", alternates: ["C"], credits: 3)
        f.input = F.input(f.input, pathway: pathway)
        return f
    }

    private func statesToProve(_ f: (catalog: Catalog, input: ConditionalPrerequisiteInput, requests: [ConditionalPrerequisiteRequest]), _ status: (PlaceholderPrerequisiteAnalysis) -> Bool) throws -> Int {
        try (1...500).first { limit in status(try analyze(f, limit: limit)) } ?? 0
    }

    @Test func independentComponentBudgets() throws {
        let f = twoGroups()
        let smallGroupNeeds = try statesToProve(f) { $0.statusByDependency[f.requests[1].key] == .conditional }
        let largeGroupNeeds = try statesToProve(f) { $0.statusByDependency[f.requests[0].key] == .conditional }
        #expect(smallGroupNeeds > 0 && smallGroupNeeds < largeGroupNeeds)
        // A budget too small for the large group still proves the small one.
        let result = try analyze(f, limit: smallGroupNeeds)
        #expect(result.statusByDependency[f.requests[0].key] == .unconfirmed)
        #expect(result.statusByDependency[f.requests[1].key] == .conditional)
        // Once the large group is proven, admitting D1 must not spend the
        // large group's budget again on its behalf.
        let both = try analyze(f, limit: largeGroupNeeds)
        #expect(both.statusByDependency[f.requests[0].key] == .conditional)
        #expect(both.statusByDependency[f.requests[1].key] == .conditional)
    }

    @Test func duplicateAndUnknownAlternatesMarkEachChoiceOnce() throws {
        let f = F.makeInput(slots: [["A", "A", "missing"]], dependencies: [.course("A")])
        #expect(try analyze(f).supportsByPlaceholder[F.slotID(0)] == ["A": Set([f.requests[0].key])])
    }

    @Test func realCourseIsPreferredOverASlot() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")], extraItems: [0: ["A"]])
        let result = try analyze(f)
        #expect(result.statusByDependency[f.requests[0].key] == .satisfied)
        #expect(result.supportsByPlaceholder.isEmpty)
    }

    @Test func exhaustedAnnotationProbesKeepTheProvenBaseline() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.any([.course("A"), .course("B")])])
        let baselineNeeds = try statesToProve(f) { $0.statusByDependency[f.requests[0].key] == .conditional }
        let result = try analyze(f, limit: baselineNeeds)
        #expect(result.statusByDependency[f.requests[0].key] == .conditional)
        // Probes that ran out of budget mark nothing rather than guessing.
        let marked = result.supportsByPlaceholder[F.slotID(0)] ?? [:]
        #expect(marked.count < 2)
    }

    @Test func fullChainWithSameTermLab() throws {
        let lecture = F.course("C100", code: "CHEM 100", corequisite: .course("C100L"))
        let lab = F.course("C100L", code: "CHEM 100L", credits: 1, corequisite: .course("C100"))
        let f = F.makeInput(slots: [["C100"], ["C100L"]], dependencies: [.course("C100")], extraCourses: [lecture, lab])
        let result = try analyze(f)
        #expect(result.statusByDependency[f.requests[0].key] == .conditional)
        #expect(result.supportsByPlaceholder[F.slotID(0)] == ["C100": Set([f.requests[0].key])])
        #expect(result.supportsByPlaceholder[F.slotID(1)] == ["C100L": Set([f.requests[0].key])])
    }

    @Test func repeatedAnalysisIsDeterministicAndLeavesThePlanAlone() throws {
        let f = F.makeInput(slots: [["A", "B"], ["A", "B"]], dependencies: [.course("A"), .any([.course("A"), .course("B")])])
        let before = f.input.pathway
        let first = try analyze(f)
        let second = try analyze(f)
        #expect(first == second)
        #expect(f.input.pathway == before)
    }

    @Test func providerPriorityRanksTheNeededSlotFirst() throws {
        let f = F.makeInput(
            slots: [["A"], ["X400"]],
            dependencies: [.course("A")],
            extraCourses: [F.course("X400", code: "MATH 490")]
        )
        let analyzer = PlaceholderPrerequisiteAnalyzer(catalog: f.catalog)
        func priority(_ slot: String) -> Int {
            analyzer.providerPriority(
                itemID: slot,
                pendingCourseIDs: ["D0", F.slotID(0), F.slotID(1)],
                completedCourseIDs: [],
                placeholders: f.input.pathway.placeholders,
                activeProgramTitle: nil
            )
        }
        #expect(priority(F.slotID(0)) < priority(F.slotID(1)))
        #expect(analyzer.providerPriority(itemID: "D0", pendingCourseIDs: ["D0"], completedCourseIDs: [], placeholders: [:], activeProgramTitle: nil) == 1)
    }
}

