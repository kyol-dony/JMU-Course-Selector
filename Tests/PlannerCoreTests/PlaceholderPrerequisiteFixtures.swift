import Foundation
@testable import PlannerCore

/// Shared fixtures for conditional placeholder prerequisites: concrete
/// courses A (MATH 300) and B (MATH 336) offered through `__pl::choice::<i>`
/// slots, and dependents D0 (MATH 410) and D1 (MATH 430) whose
/// prerequisites are the supplied expressions. Fall 2026 is followed by
/// Spring 2027; everything is three credits and offered both terms.
enum PlaceholderPrerequisiteFixtures {
    static let fall = SemesterIdentity(year: 2026, term: .fall)
    static let spring = SemesterIdentity(year: 2027, term: .spring)
    static let semesters = [fall, spring]
    static let programID = "test-major"
    static let categoryID = "choice"

    static func slotID(_ index: Int) -> String {
        PathwayPlaceholder.id(categoryID: categoryID, optionIndex: index)
    }

    static func course(
        _ id: String,
        code: String,
        credits: Int = 3,
        prerequisite: PrereqExpr = .empty,
        corequisite: PrereqExpr = .empty,
        availability: Set<SemesterTerm>? = [.fall, .spring]
    ) -> Course {
        Course(
            id: id,
            code: code,
            title: code,
            credits: credits,
            availability: availability,
            prerequisites: [],
            prerequisiteExpr: prerequisite,
            corequisiteExpr: corequisite
        )
    }

    /// `slots[i]` becomes `__pl::choice::i` in `semesters[slotSemesterOffset]`;
    /// `dependencies[i]` is the prerequisite of `D<i>`, scheduled in
    /// `semesters[dependentSemesterOffset]`. `extraCourses` replace or add
    /// catalog courses by id; `extraItems` appends items to a semester.
    static func makeInput(
        slots: [[String]],
        dependencies: [PrereqExpr],
        slotSemesterOffset: Int = 0,
        dependentSemesterOffset: Int = 1,
        extraCourses: [Course] = [],
        extraItems: [Int: [String]] = [:],
        workload: WorkloadPreference? = .light
    ) -> (catalog: Catalog, input: ConditionalPrerequisiteInput, requests: [ConditionalPrerequisiteRequest]) {
        var coursesByID: [String: Course] = [
            "A": course("A", code: "MATH 300"),
            "B": course("B", code: "MATH 336")
        ]
        let dependentCodes = ["MATH 410", "MATH 430"]
        for (index, dependency) in dependencies.enumerated() {
            coursesByID["D\(index)"] = course("D\(index)", code: dependentCodes[index], prerequisite: dependency)
        }
        for extra in extraCourses {
            coursesByID[extra.id] = extra
        }
        let dependentIDs = dependencies.indices.map { "D\($0)" }
        let catalog = Catalog.fixture(
            courses: coursesByID.values.sorted { $0.id < $1.id },
            program: Program.fixture(id: programID, title: "Test Major", requirements: [
                RequirementCategory(id: categoryID, name: "Choose a Course", requiredCredits: 3 * slots.count, courseOptions: slots),
                RequirementCategory(id: "core", name: "Required Core", requiredCredits: 3 * dependencies.count, courseOptions: dependentIDs.map { [$0] })
            ])
        )

        var items: [[String]] = semesters.map { _ in [] }
        items[slotSemesterOffset] += slots.indices.map(slotID)
        items[dependentSemesterOffset] += dependentIDs
        for (offset, extra) in extraItems {
            items[offset] += extra
        }
        let placeholders = Dictionary(uniqueKeysWithValues: slots.enumerated().map { index, alternates in
            (slotID(index), PlaceholderSpec(categoryID: categoryID, categoryName: "Choose a Course", alternates: alternates, credits: 3))
        })
        let pathway = Pathway(
            id: "p",
            name: "P",
            semesters: zip(semesters, items).map { SemesterPlan(id: $0, courseIDs: $1) },
            placeholders: placeholders
        )
        let input = ConditionalPrerequisiteInput(
            pathway: pathway,
            completedAtStart: [],
            standingBySemester: [fall: .senior, spring: .senior],
            workload: workload,
            activeProgramTitle: nil
        )
        let requests = dependencies.enumerated().map { index, dependency in
            ConditionalPrerequisiteRequest(
                key: ConditionalDependencyKey(courseID: "D\(index)", semester: semesters[dependentSemesterOffset], kind: .prerequisite),
                expression: dependency
            )
        }
        return (catalog, input, requests)
    }

    /// `input` with its pathway replaced.
    static func input(_ input: ConditionalPrerequisiteInput, pathway: Pathway) -> ConditionalPrerequisiteInput {
        ConditionalPrerequisiteInput(
            pathway: pathway,
            completedAtStart: input.completedAtStart,
            standingBySemester: input.standingBySemester,
            workload: input.workload,
            activeProgramTitle: input.activeProgramTitle
        )
    }
}
