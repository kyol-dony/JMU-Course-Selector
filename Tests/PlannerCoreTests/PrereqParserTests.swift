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

final class PrereqDisplayStringTests: XCTestCase {
    private var coursesByID: [String: Course] {
        [
            "cs-159": Course(id: "cs-159", code: "CS 159", title: "", credits: 3, availability: nil, prerequisites: []),
            "cs-149": Course(id: "cs-149", code: "CS 149", title: "", credits: 3, availability: nil, prerequisites: []),
            "math-235": Course(id: "math-235", code: "MATH 235", title: "", credits: 3, availability: nil, prerequisites: [])
        ]
    }

    func testEmptyRendersEmpty() {
        XCTAssertEqual(PrereqExpr.empty.displayString(coursesByID: [:]), "")
    }

    func testCourseRendersCode() {
        XCTAssertEqual(PrereqExpr.course("cs-159").displayString(coursesByID: coursesByID), "CS 159")
    }

    func testUnresolvedCourseFallsBackToID() {
        XCTAssertEqual(PrereqExpr.course("does-not-exist").displayString(coursesByID: coursesByID), "does-not-exist")
    }

    func testUnknownRendersRawText() {
        XCTAssertEqual(PrereqExpr.unknown("instructor permission").displayString(coursesByID: [:]), "instructor permission")
    }

    func testAndJoins() {
        let expr: PrereqExpr = .all([.course("cs-159"), .course("math-235")])
        XCTAssertEqual(expr.displayString(coursesByID: coursesByID), "CS 159 and MATH 235")
    }

    func testOrJoins() {
        let expr: PrereqExpr = .any([.course("cs-159"), .course("cs-149")])
        XCTAssertEqual(expr.displayString(coursesByID: coursesByID), "CS 159 or CS 149")
    }

    func testNestedParens() {
        let expr: PrereqExpr = .all([
            .course("cs-159"),
            .any([.course("math-235"), .unknown("instructor permission")])
        ])
        XCTAssertEqual(expr.displayString(coursesByID: coursesByID), "CS 159 and (MATH 235 or instructor permission)")
    }
}

final class PrereqLexerTests: XCTestCase {
    func testCourseReferenceToken() {
        let tokens = PrereqLexer.tokenize("CS 159")
        XCTAssertEqual(tokens, [.courseRef("CS 159")])
    }

    func testBooleanAndParenTokens() {
        let tokens = PrereqLexer.tokenize("CS 159 and (MATH 235 or MATH 236)")
        XCTAssertEqual(tokens, [
            .courseRef("CS 159"),
            .and,
            .lparen,
            .courseRef("MATH 235"),
            .or,
            .courseRef("MATH 236"),
            .rparen
        ])
    }

    func testCommaAndSemicolonTokens() {
        let tokens = PrereqLexer.tokenize("CS 159, MATH 235; CS 240")
        XCTAssertEqual(tokens, [
            .courseRef("CS 159"),
            .comma,
            .courseRef("MATH 235"),
            .semicolon,
            .courseRef("CS 240")
        ])
    }

    func testUnknownRunBetweenCourseRefs() {
        let tokens = PrereqLexer.tokenize("CS 159 or instructor permission")
        XCTAssertEqual(tokens, [
            .courseRef("CS 159"),
            .or,
            .unknown("instructor permission")
        ])
    }

    func testTrailingPunctuationIgnored() {
        let tokens = PrereqLexer.tokenize("CS 159.")
        XCTAssertEqual(tokens, [.courseRef("CS 159")])
    }

    func testEmptyInputProducesNoTokens() {
        XCTAssertTrue(PrereqLexer.tokenize("").isEmpty)
        XCTAssertTrue(PrereqLexer.tokenize("   ").isEmpty)
    }
}

final class PrereqGrammarTests: XCTestCase {
    private static let stubCatalog: [String: Course] = [
        "cs-159": Course(id: "cs-159", code: "CS 159", title: "", credits: 3, availability: nil, prerequisites: []),
        "cs-149": Course(id: "cs-149", code: "CS 149", title: "", credits: 3, availability: nil, prerequisites: []),
        "math-235": Course(id: "math-235", code: "MATH 235", title: "", credits: 3, availability: nil, prerequisites: []),
        "math-236": Course(id: "math-236", code: "MATH 236", title: "", credits: 3, availability: nil, prerequisites: [])
    ]

    private func parse(_ text: String, coursesByID: [String: Course] = stubCatalog) -> ParseResult {
        PrereqParser(coursesByID: coursesByID).parse(text)
    }

    func testAtomic() {
        XCTAssertEqual(parse("Prerequisite: CS 159.").prerequisiteExpr, .course("cs-159"))
    }

    func testAnd() {
        XCTAssertEqual(parse("CS 159 and MATH 235").prerequisiteExpr,
                       .all([.course("cs-159"), .course("math-235")]))
    }

    func testOr() {
        XCTAssertEqual(parse("CS 159 or CS 149").prerequisiteExpr,
                       .any([.course("cs-159"), .course("cs-149")]))
    }

    func testNested() {
        XCTAssertEqual(parse("CS 159 and (MATH 235 or MATH 236)").prerequisiteExpr,
                       .all([.course("cs-159"), .any([.course("math-235"), .course("math-236")])]))
    }

    func testCommaIsAnd() {
        XCTAssertEqual(parse("CS 159, MATH 235").prerequisiteExpr,
                       .all([.course("cs-159"), .course("math-235")]))
    }

    func testSemicolonIsAnd() {
        XCTAssertEqual(parse("CS 159; MATH 235").prerequisiteExpr,
                       .all([.course("cs-159"), .course("math-235")]))
    }

    func testUnknownToken() {
        let result = parse("CS 159 or instructor permission")
        XCTAssertEqual(result.prerequisiteExpr, .any([.course("cs-159"), .unknown("instructor permission")]))
        XCTAssertTrue(result.hasUnknownTokens)
    }

    func testUnresolvedCourseRefBecomesUnknown() {
        let result = parse("CS 159 or MATH 100")
        XCTAssertEqual(result.prerequisiteExpr, .any([.course("cs-159"), .unknown("MATH 100")]))
        XCTAssertTrue(result.hasUnknownTokens)
    }

    func testEmptyInput() {
        XCTAssertEqual(parse("").prerequisiteExpr, .empty)
        XCTAssertFalse(parse("").hasUnknownTokens)
    }

    func testNormalizationFlattensNestedAnd() {
        XCTAssertEqual(parse("CS 159 and MATH 235 and MATH 236").prerequisiteExpr,
                       .all([.course("cs-159"), .course("math-235"), .course("math-236")]))
    }
}

final class PrereqCoreqTests: XCTestCase {
    private static let stubCatalog: [String: Course] = [
        "cs-159": Course(id: "cs-159", code: "CS 159", title: "", credits: 3, availability: nil, prerequisites: []),
        "math-235": Course(id: "math-235", code: "MATH 235", title: "", credits: 3, availability: nil, prerequisites: []),
        "math-236": Course(id: "math-236", code: "MATH 236", title: "", credits: 3, availability: nil, prerequisites: [])
    ]

    func testCoreqSegmentSplits() {
        let r = PrereqParser(coursesByID: Self.stubCatalog).parse("Prerequisite: CS 159. Corequisite: MATH 235.")
        XCTAssertEqual(r.prerequisiteExpr, .course("cs-159"))
        XCTAssertEqual(r.corequisiteExpr, .course("math-235"))
    }

    func testCoreqWithBooleanGroup() {
        let r = PrereqParser(coursesByID: Self.stubCatalog).parse("Prerequisite: CS 159. Corequisite(s): MATH 235 or MATH 236.")
        XCTAssertEqual(r.corequisiteExpr, .any([.course("math-235"), .course("math-236")]))
    }

    func testNoCoreqLeavesEmpty() {
        let r = PrereqParser(coursesByID: Self.stubCatalog).parse("Prerequisite: CS 159.")
        XCTAssertEqual(r.corequisiteExpr, .empty)
    }
}
