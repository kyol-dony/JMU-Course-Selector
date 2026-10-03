import Testing
@testable import PlannerCore

@Suite struct JMUTranscriptParserTests {
    @Test(arguments: [
        ("CS149", "CS 149"),
        ("MATH236", "MATH 236"),
        ("BIO140L", "BIO 140L"),
        ("CSOOO", "CS OOO"),
        ("CS 149", "CS 149"),
        ("XYZ", "XYZ"),
    ])
    func displayCodeSeparatesSubjectAndNumber(_ code: String, _ expected: String) {
        #expect(JMUTranscriptParser.displayCode(code) == expected)
    }
    @Test func sample() throws {
        let parsed = try JMUTranscriptParser.parse(pages: [TranscriptTestFixtures.sampleText()])
        #expect(parsed.records.filter { $0.status == .earned }.count == 19)
        #expect(parsed.records.filter { $0.status == .earned }.reduce(0) { $0 + $1.earnedCredits } == 49)
        #expect(parsed.records.filter { $0.status == .inProgress }.reduce(0) { $0 + $1.attemptedCredits } == 16)
        #expect(parsed.latestPrintedTerm == "Fall Semester 2026")
        #expect(parsed.records.contains { $0.code == "CSOOO" && $0.earnedCredits == 3 })
    }
    @Test func latestTermIsChronological() throws {
        let p = try JMUTranscriptParser.parse(pages: ["James Madison University\nUnofficial Transcript\nFall Semester 2026\nCS 149 Intro 3.00 0.00 0.000\nSpring Semester 2026\nCS 159 Advanced 3.00 3.00 A 0.000"])
        #expect(p.latestPrintedTerm == "Fall Semester 2026")
    }
    @Test func multiPageContinuation() throws {
        let p = try JMUTranscriptParser.parse(pages: ["James Madison University\nUnofficial Transcript\nFall Semester 2026\nCHEM132L Lab", "Page 2 of 2\nCourse Description Attempted Earned Grade Points\n1.50 1.50 A 6.000"])
        #expect(p.records.count == 1)
        #expect(p.records.first?.earnedCredits == 1.5)
        #expect(p.records.first?.code == "CHEM132L")
    }
    @Test func failedWithdrawnIncompleteAreExcluded() throws {
        let p = try JMUTranscriptParser.parse(pages: ["James Madison University\nUnofficial Transcript\nFall Semester 2026\nCS 149 Intro 3.00 0.00 F 0.000\nCS 159 Advanced 3.00 0.00 W 0.000\nMATH 235 Calculus 4.00 0.00 I 0.000"])
        #expect(p.records.count == 3)
        #expect(p.records.allSatisfy { $0.status == .excluded })
    }
    @Test func unknownGradeNeedsReview() throws {
        let p = try JMUTranscriptParser.parse(pages: ["James Madison University\nUnofficial Transcript\nFall Semester 2026\nCS 149 Intro 3.00 3.00 XX 0.000"])
        #expect(p.records.first?.status == .needsReview)
        #expect(p.issues.contains { $0.kind == .unknownGrade && $0.isBlocking })
    }
    @Test func unsupportedSummerTerm() throws {
        let p = try JMUTranscriptParser.parse(pages: ["James Madison University\nUnofficial Transcript\nSummer Semester 2026\nCS 149 Intro 3.00 0.00 0.000"])
        #expect(p.latestPrintedTerm == "Summer Semester 2026")
        #expect(p.issues.contains { $0.kind == .unsupportedTerm })
    }
    @Test func totalsAndProgramHeadersAreNotCourses() throws {
        #expect(throws: TranscriptParserError.self) { try JMUTranscriptParser.parse(pages: ["Other college\nCS 149 Intro 3.00 3.00 A 0.000"]) }
        #expect(throws: TranscriptParserError.self) { try JMUTranscriptParser.parse(pages: ["James Madison University\nUnofficial Transcript\nComputer Info Systems - BBA Major\nCum Totals 0.00 49.00 0.000"]) }
    }
}
