import XCTest
@testable import PlannerCore

final class PrereqEvaluatorPrereqModeTests: XCTestCase {
    func testCourseSatisfiedByCompletedBefore() {
        let e = PrereqEvaluator(completedBefore: ["cs-159"], scheduledThisTerm: [])
        if case .satisfied = e.evaluate(.course("cs-159"), mode: .prereq) { /* ok */ }
        else { XCTFail("expected satisfied") }
    }

    func testCourseUnsatisfied() {
        let e = PrereqEvaluator(completedBefore: [], scheduledThisTerm: [])
        if case .unmet(let missing, let original) = e.evaluate(.course("cs-159"), mode: .prereq) {
            XCTAssertEqual(missing, .course("cs-159"))
            XCTAssertEqual(original, .course("cs-159"))
        } else { XCTFail("expected unmet") }
    }

    func testAllSatisfiedIfEveryChildMet() {
        let e = PrereqEvaluator(completedBefore: ["cs-159", "math-235"], scheduledThisTerm: [])
        if case .satisfied = e.evaluate(.all([.course("cs-159"), .course("math-235")]), mode: .prereq) { /* ok */ }
        else { XCTFail("expected satisfied") }
    }

    func testAnyOneSufficient() {
        let e = PrereqEvaluator(completedBefore: ["cs-149"], scheduledThisTerm: [])
        if case .satisfied = e.evaluate(.any([.course("cs-159"), .course("cs-149")]), mode: .prereq) { /* ok */ }
        else { XCTFail("expected satisfied") }
    }

    func testNestedAndOfOrPartial() {
        // (CS 159 or CS 149) and MATH 235. Has CS 159 only.
        let expr: PrereqExpr = .all([
            .any([.course("cs-159"), .course("cs-149")]),
            .course("math-235")
        ])
        let e = PrereqEvaluator(completedBefore: ["cs-159"], scheduledThisTerm: [])
        if case .unmet(let missing, _) = e.evaluate(expr, mode: .prereq) {
            XCTAssertEqual(missing, .course("math-235"))
        } else { XCTFail("expected unmet") }
    }

    func testUnknownIsNeverSatisfied() {
        let e = PrereqEvaluator(completedBefore: ["cs-159"], scheduledThisTerm: [])
        if case .unmet(let missing, _) = e.evaluate(.unknown("instructor permission"), mode: .prereq) {
            XCTAssertEqual(missing, .unknown("instructor permission"))
        } else { XCTFail("expected unmet") }
    }
}

final class PrereqEvaluatorCoreqModeTests: XCTestCase {
    func testCoreqSatisfiedBySameTerm() {
        let e = PrereqEvaluator(completedBefore: [], scheduledThisTerm: ["math-235"])
        if case .satisfied = e.evaluate(.course("math-235"), mode: .coreq) { /* ok */ }
        else { XCTFail("expected satisfied") }
    }

    func testCoreqSatisfiedByEarlierTerm() {
        let e = PrereqEvaluator(completedBefore: ["math-235"], scheduledThisTerm: [])
        if case .satisfied = e.evaluate(.course("math-235"), mode: .coreq) { /* ok */ }
        else { XCTFail("expected satisfied") }
    }

    func testCoreqUnsatisfiedWhenAbsent() {
        let e = PrereqEvaluator(completedBefore: [], scheduledThisTerm: ["cs-159"])
        if case .unmet(let missing, _) = e.evaluate(.course("math-235"), mode: .coreq) {
            XCTAssertEqual(missing, .course("math-235"))
        } else { XCTFail("expected unmet") }
    }

    func testPrereqDoesNotAcceptSameTerm() {
        let e = PrereqEvaluator(completedBefore: [], scheduledThisTerm: ["cs-159"])
        if case .unmet = e.evaluate(.course("cs-159"), mode: .prereq) { /* ok */ }
        else { XCTFail("expected unmet in prereq mode") }
    }
}
