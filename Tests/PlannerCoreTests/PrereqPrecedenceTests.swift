import Foundation
import Testing
@testable import PlannerCore

/// JMU writes substitutable courses with "or" between them, so inside a
/// clause "or" binds tighter than "and": "X or Y and Z" is (X or Y) and Z.
@Suite("Prerequisite and/or precedence")
struct PrereqPrecedenceTests {
    private static let codes = [
        "MATH 300", "MATH 238", "MATH 321", "MATH 322", "COB 191", "MATH 220", "MATH 205",
        "BIO 245L", "BIO 103", "BIO 140", "CHEM 120", "CHEM 131", "ISCI 101",
        "PHYS 150", "PHYS 250", "ISAT 212", "STAD 171", "THEA 206", "THEA 306",
        "CS 149", "CS 159", "CS 227", "ARAB 102", "ARAB 109", "ARAB 111",
        "ENG 391", "ENG 392", "ENG 393", "GEOL 211", "GEOL 230", "BIO 354",
        "CIS 221", "ISAT 252", "MATH 231", "MATH 235", "MATH 318",
        "AAAD 200", "ARTH 206", "RUS 232", "RUS 212"
    ]

    private let parser = PrereqParser(coursesByID: Dictionary(uniqueKeysWithValues: codes.map { code in
        let id = code.replacingOccurrences(of: " ", with: "")
        return (id, Course(id: id, code: code, title: code, credits: 3, availability: nil, prerequisites: []))
    }))

    private func parse(_ text: String) -> PrereqExpr {
        parser.parse(text).prerequisiteExpr.enforcedCourseOnly
    }

    private func c(_ id: String) -> PrereqExpr { .course(id) }

    @Test("MATH 421: A or B and C or D is (A or B) and (C or D)")
    func twoChoices() {
        #expect(parse("Prerequisites: MATH 300 or MATH 238 and MATH 321 or MATH 322")
            == .all([.any([c("MATH300"), c("MATH238")]), .any([c("MATH321"), c("MATH322")])]))
    }

    @Test("COB 291: A or B and C or equivalent")
    func choiceThenCourse() {
        #expect(parse("Prerequisites: COB 191 or MATH 220 and MATH 205 or equivalent")
            == .all([.any([c("COB191"), c("MATH220")]), c("MATH205")]))
    }

    @Test("BIO 245: A and B or C or D ... is A and (B or C or D ...)")
    func courseThenChoice() {
        #expect(parse("Prerequisites: BIO 245L and BIO 103 or BIO 140 or CHEM 120 or CHEM 131 or ISCI 101 or equivalent")
            == .all([c("BIO245L"), .any([c("BIO103"), c("BIO140"), c("CHEM120"), c("CHEM131"), c("ISCI101")])]))
    }

    @Test("CHEM 375: A and B or C or D or permission")
    func choiceWithPermission() {
        #expect(parse("Prerequisites: CHEM 131 and PHYS 150 or PHYS 250 or ISAT 212 or permission of the instructor")
            == .all([c("CHEM131"), .any([c("PHYS150"), c("PHYS250"), c("ISAT212")])]))
    }

    @Test("THEA 331: ', or' stays an alternative to everything before it")
    func commaOrStaysLoose() {
        let result = parser.parse("Prerequisites: STAD 171 and THEA 206 or THEA 306 , or permission of the instructor").prerequisiteExpr
        #expect(result == .any([
            .all([c("STAD171"), .any([c("THEA206"), c("THEA306")])]),
            .unknown("permission of the instructor")
        ]))
    }

    @Test("parentheses still override: (A and B) or C")
    func parenthesesOverride() {
        #expect(parse("Prerequisites: (CS 149 and CS 159) or CS 227")
            == .any([.all([c("CS149"), c("CS159")]), c("CS227")]))
    }

    @Test("a comma list closed by 'or' is one choice, even inside a clause", arguments: [
        ("Prerequisites: ARAB 102 , ARAB 109 or ARAB 111 , or permission of the instructor.", ["ARAB102", "ARAB109", "ARAB111"]),
        ("Prerequisites: ENG 391 , ENG 392 or ENG 393 , as appropriate to course content.", ["ENG391", "ENG392", "ENG393"]),
        ("Prerequisites: GEOL 211 , GEOL 230 or BIO 354 , or permission of the instructor.", ["GEOL211", "GEOL230", "BIO354"])
    ])
    func commaListClosedByOr(input: String, choices: [String]) {
        #expect(parse(input) == .any(choices.map(c)))
    }

    @Test("a closing-'or' comma list after 'and' is one choice")
    func commaListAfterAnd() {
        #expect(parse("Prerequisites: Declared CIS major and CIS 221 , CS 149 or ISAT 252 .")
            == .any([c("CIS221"), c("CS149"), c("ISAT252")]))
        #expect(parse("Prerequisites: MATH 205 , MATH 231 , MATH 235 or equivalent; and either COB 191 , MATH 220 , MATH 318 or equivalent.")
            == .all([.any([c("MATH205"), c("MATH231"), c("MATH235")]), .any([c("COB191"), c("MATH220"), c("MATH318")])]))
    }

    @Test("a comma list whose last item isn't a choice stays required")
    func commaListWithoutChoice() {
        #expect(parse("Prerequisites: CS 149 , CS 159 and MATH 231 or MATH 235")
            == .all([c("CS149"), c("CS159"), .any([c("MATH231"), c("MATH235")])]))
    }

    @Test("'A , B or permission' keeps both courses; permission is an escape hatch", arguments: [
        ("Prerequisites: AAAD 200 , ARTH 206 or permission of the instructor.", ["AAAD200", "ARTH206"]),
        ("Prerequisites: RUS 232 , RUS 212 or by placement exam.", ["RUS232", "RUS212"])
    ])
    func escapeHatch(input: String, required: [String]) {
        #expect(parse(input) == .all(required.map(c)))
    }
}
