import XCTest
@testable import PlannerCore

final class CatalogRepositoryPrereqPassTests: XCTestCase {
    func testTwoPassResolvesPrereqAcrossCatalog() {
        let cs159 = Course(id: "cs-159", code: "CS 159", title: "Intro", credits: 3, availability: nil, prerequisites: [])
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159 and MATH 235."
        let math235 = Course(id: "math-235", code: "MATH 235", title: "Calc I", credits: 3, availability: nil, prerequisites: [])

        var courses = [cs159, cs240, math235]
        CatalogPrereqResolver.applyPassTwo(to: &courses)

        let resolved = courses.first { $0.code == "CS 240" }!
        XCTAssertEqual(resolved.prerequisiteExpr,
                        .all([.course("cs-159"), .course("math-235")]))
        XCTAssertEqual(resolved.prerequisites.sorted(), ["cs-159", "math-235"])
        XCTAssertFalse(resolved.hasUnknownPrereqTokens)
    }

    func testUnresolvedRefMarksUnknownAndPartial() {
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [], verificationStatus: .verified)
        cs240.rawPrerequisiteText = "Prerequisite: CS 159 or instructor permission."
        var courses = [cs240]
        CatalogPrereqResolver.applyPassTwo(to: &courses)

        let r = courses[0]
        XCTAssertTrue(r.hasUnknownPrereqTokens)
        XCTAssertEqual(r.verificationStatus, .partial)
    }

    func testCoreqExpressionPopulated() {
        var bio140 = Course(id: "bio-140", code: "BIO 140", title: "", credits: 3, availability: nil, prerequisites: [])
        var bio140L = Course(id: "bio-140l", code: "BIO 140L", title: "", credits: 1, availability: nil, prerequisites: [])
        bio140.rawPrerequisiteText = "Corequisite: BIO 140L."
        bio140L.rawPrerequisiteText = "Corequisite: BIO 140."
        var courses = [bio140, bio140L]
        CatalogPrereqResolver.applyPassTwo(to: &courses)

        XCTAssertEqual(courses[0].corequisiteExpr, .course("bio-140l"))
        XCTAssertEqual(courses[1].corequisiteExpr, .course("bio-140"))
    }
}
