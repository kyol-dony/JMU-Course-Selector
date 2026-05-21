import XCTest
@testable import PlannerCore

final class PrereqExprTests: XCTestCase {
    func testCodableRoundTripPreservesStructure() throws {
        let expr: PrereqExpr = .all([
            .course("cs-159"),
            .any([.course("math-235"), .course("math-236")]),
            .unknown("instructor permission")
        ])
        let data = try JSONEncoder().encode(expr)
        let decoded = try JSONDecoder().decode(PrereqExpr.self, from: data)
        XCTAssertEqual(expr, decoded)
    }

    func testEmptyIsDefault() throws {
        let data = try JSONEncoder().encode(PrereqExpr.empty)
        let decoded = try JSONDecoder().decode(PrereqExpr.self, from: data)
        XCTAssertEqual(decoded, .empty)
    }
}

final class CourseModelTests: XCTestCase {
    func testCourseDefaultsToEmptyExpressions() {
        let c = Course(
            id: "cs-159",
            code: "CS 159",
            title: "Intro",
            credits: 3,
            availability: nil,
            prerequisites: []
        )
        XCTAssertEqual(c.prerequisiteExpr, .empty)
        XCTAssertEqual(c.corequisiteExpr, .empty)
        XCTAssertFalse(c.hasUnknownPrereqTokens)
    }

    func testCourseExpressionsRoundTripCodable() throws {
        var c = Course(
            id: "cs-240",
            code: "CS 240",
            title: "Data",
            credits: 3,
            availability: nil,
            prerequisites: ["cs-159"]
        )
        c.prerequisiteExpr = .course("cs-159")
        c.corequisiteExpr = .course("math-235")
        c.hasUnknownPrereqTokens = true
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(Course.self, from: data)
        XCTAssertEqual(decoded.prerequisiteExpr, .course("cs-159"))
        XCTAssertEqual(decoded.corequisiteExpr, .course("math-235"))
        XCTAssertTrue(decoded.hasUnknownPrereqTokens)
    }

    func testCourseDecodesOldJSONWithoutNewFields() throws {
        let json = """
        {"id":"cs-159","code":"CS 159","title":"Intro","credits":3,"availability":null,"prerequisites":[],"verificationStatus":"verified"}
        """
        let decoded = try JSONDecoder().decode(Course.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.prerequisiteExpr, .empty)
        XCTAssertEqual(decoded.corequisiteExpr, .empty)
        XCTAssertFalse(decoded.hasUnknownPrereqTokens)
    }
}

final class ConflictKindTests: XCTestCase {
    func testMissingCorequisiteCaseExists() {
        let k = ConflictKind.missingCorequisite
        XCTAssertEqual(k.rawValue, "missingCorequisite")
    }

    func testMissingCorequisiteDisplayName() {
        XCTAssertEqual(ConflictKind.missingCorequisite.displayName, "Corequisite warning")
    }
}
