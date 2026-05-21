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

final class PrereqIrregularTextTests: XCTestCase {
    private static let stubCatalog: [String: Course] = [
        "cs-149": Course(id: "cs-149", code: "CS 149", title: "", credits: 3, availability: nil, prerequisites: []),
        "cs-159": Course(id: "cs-159", code: "CS 159", title: "", credits: 3, availability: nil, prerequisites: []),
        "math-220": Course(id: "math-220", code: "MATH 220", title: "", credits: 3, availability: nil, prerequisites: []),
        "math-235": Course(id: "math-235", code: "MATH 235", title: "", credits: 3, availability: nil, prerequisites: [])
    ]

    func testGradePhraseBeforeOneOfFollowingDoesNotBecomeUnknown() {
        let r = PrereqParser(coursesByID: Self.stubCatalog)
            .parse("Prerequisite: a grade of C or better in one of the following: CS 149, MATH 235.")

        XCTAssertEqual(r.prerequisiteExpr, .any([.course("cs-149"), .course("math-235")]))
        XCTAssertFalse(r.hasUnknownTokens)
    }

    func testCoreqGradePhraseBeforeOneOfFollowingParsesCourseList() {
        let r = PrereqParser(coursesByID: Self.stubCatalog)
            .parse("Corequisite: a grade of C or better in one of the following: CS 149 or MATH 235.")

        XCTAssertEqual(r.corequisiteExpr, .any([.course("cs-149"), .course("math-235")]))
        XCTAssertFalse(r.hasUnknownTokens)
    }

    func testMatchingMajorUsesMajorSpecificClause() {
        let r = PrereqParser(coursesByID: Self.stubCatalog, activeProgramTitle: "Computer Science, B.S.")
            .parse("Prerequisite: For Computer Science majors: CS 159. For non Computer Science majors: MATH 235.")

        XCTAssertEqual(r.prerequisiteExpr, .course("cs-159"))
    }

    func testNonMatchingMajorUsesNonMajorClause() {
        let r = PrereqParser(coursesByID: Self.stubCatalog, activeProgramTitle: "Computer Information Systems, B.B.A.")
            .parse("Prerequisite: For Computer Science majors: CS 159. For non Computer Science majors: MATH 235.")

        XCTAssertEqual(r.prerequisiteExpr, .course("math-235"))
    }

    func testNoActiveMajorPrefersNonMajorClause() {
        let r = PrereqParser(coursesByID: Self.stubCatalog)
            .parse("Prerequisite: For Computer Science majors: CS 159. For non Computer Science majors: MATH 235.")

        XCTAssertEqual(r.prerequisiteExpr, .course("math-235"))
    }

    func testUnrelatedMajorSpecificClauseIsIgnoredWhenNoNonMajorClauseExists() {
        let r = PrereqParser(coursesByID: Self.stubCatalog, activeProgramTitle: "Psychology, B.S.")
            .parse("Prerequisite: For Computer Science majors: CS 159.")

        XCTAssertEqual(r.prerequisiteExpr, .empty)
        XCTAssertFalse(r.hasUnknownTokens)
    }
}

/// Regression suite mirroring the prereq-text patterns observed in JMU's
/// course detail pages. The `_live_*.html` fixtures are program-listing
/// HTML and do not embed prereq sentences themselves; the catalog parses
/// prereqs from separate course detail pages. The lines below are
/// representative of the patterns documented in CourseDetailCacheTests
/// (e.g., "Prerequisite(s): MATH 155 or sufficient ALEKS score.") and in
/// the live CS/MATH/ACTG catalog.
final class PrereqLiveFixtureTests: XCTestCase {
    private struct Case: Sendable {
        let label: String
        let input: String
        let assert: @Sendable (ParseResult) -> Void
    }

    private static let cases: [Case] = [
        Case(label: "atomic_prereq_with_dot",
             input: "Prerequisite: CS 159.") { r in
            if case .unknown = r.prerequisiteExpr {
                // Empty catalog: course ref unresolved → unknown. Expected.
            } else { XCTFail("expected unknown when catalog empty") }
        },
        Case(label: "or_with_alternate_score",
             input: "Prerequisite(s): MATH 155 or sufficient ALEKS score.") { r in
            if case .any(let xs) = r.prerequisiteExpr {
                XCTAssertEqual(xs.count, 2)
                if case .unknown = xs[0] { /* MATH 155 unresolved */ } else { XCTFail() }
                if case .unknown(let text) = xs[1] {
                    XCTAssertTrue(text.contains("ALEKS"))
                } else { XCTFail("expected unknown for 'ALEKS score'") }
            } else { XCTFail("expected .any") }
            XCTAssertTrue(r.hasUnknownTokens)
        },
        Case(label: "and_pair",
             input: "Prerequisite: CS 149 and MATH 235.") { r in
            if case .all(let xs) = r.prerequisiteExpr {
                XCTAssertEqual(xs.count, 2)
            } else { XCTFail("expected .all") }
        },
        Case(label: "nested_and_of_or",
             input: "Prerequisite: CS 240 and (MATH 235 or MATH 245).") { r in
            if case .all(let outer) = r.prerequisiteExpr {
                XCTAssertEqual(outer.count, 2)
                if case .any = outer[1] { /* ok */ } else { XCTFail("inner not .any") }
            } else { XCTFail("expected .all outer") }
        },
        Case(label: "comma_chain",
             input: "Prerequisites: CS 149, CS 227, MATH 235.") { r in
            if case .all(let xs) = r.prerequisiteExpr {
                XCTAssertEqual(xs.count, 3)
            } else { XCTFail("expected 3-element .all from comma chain") }
        },
        Case(label: "semicolon_chain",
             input: "Prerequisite: CS 159; MATH 220.") { r in
            if case .all(let xs) = r.prerequisiteExpr {
                XCTAssertEqual(xs.count, 2)
            } else { XCTFail("expected 2-element .all") }
        },
        Case(label: "instructor_permission_only",
             input: "Prerequisite: Permission of instructor.") { r in
            if case .unknown(let text) = r.prerequisiteExpr {
                XCTAssertTrue(text.lowercased().contains("permission"))
            } else { XCTFail("expected pure unknown") }
            XCTAssertTrue(r.hasUnknownTokens)
        },
        Case(label: "coreq_lab_lecture_pair",
             input: "Prerequisite: BIO 140. Corequisite: BIO 140L.") { r in
            // BIO 140 unresolved → .unknown leaf. Same for BIO 140L.
            if case .unknown = r.prerequisiteExpr { /* ok */ } else { XCTFail() }
            if case .unknown = r.corequisiteExpr { /* ok */ } else { XCTFail() }
        },
        Case(label: "junior_standing_clause",
             input: "Prerequisite: CS 240 and junior standing.") { r in
            if case .all(let xs) = r.prerequisiteExpr {
                XCTAssertEqual(xs.count, 2)
                if case .unknown(let text) = xs[1] {
                    XCTAssertTrue(text.lowercased().contains("junior standing"))
                } else { XCTFail("expected 'junior standing' as unknown") }
            } else { XCTFail("expected .all") }
            XCTAssertTrue(r.hasUnknownTokens)
        },
        Case(label: "minimum_grade_qualifier_falls_to_unknown",
             input: "Prerequisite: C- or better in CS 149.") { r in
            // We intentionally don't parse 'C- or better'; the whole prefix
            // becomes part of the .unknown stream. The expression must still
            // surface the unknown clause so the warning can prompt the
            // student to verify with the catalog.
            XCTAssertTrue(r.hasUnknownTokens)
        },
        Case(label: "test_score_only",
             input: "Prerequisite: SAT mathematics score of 600 or higher.") { r in
            // No course refs; the literal "or" in the catalog text gets
            // recognized as an OR connector, producing a 2-element .any of
            // .unknown leaves. The student-visible behavior is correct: the
            // warning will surface the entire 'verify with catalog' prompt.
            XCTAssertTrue(r.hasUnknownTokens)
            switch r.prerequisiteExpr {
            case .unknown, .any:
                break  // both shapes are acceptable
            default:
                XCTFail("expected .unknown or .any of .unknown leaves")
            }
        },
        Case(label: "empty_string",
             input: "") { r in
            XCTAssertEqual(r.prerequisiteExpr, .empty)
            XCTAssertFalse(r.hasUnknownTokens)
        }
    ]

    func testAllLiveFixtureCasesParse() {
        let parser = PrereqParser(coursesByID: [:])
        for c in Self.cases {
            let result = parser.parse(c.input)
            c.assert(result)
        }
    }
}
