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
