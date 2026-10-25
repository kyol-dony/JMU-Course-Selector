import Foundation
import Testing
@testable import PlannerCore

/// Progress shows one row per B.A./B.S. degree requirement, met by a planned
/// or earned course that isn't used for Gen Ed.
@Suite("Degree requirement progress")
struct DegreeProgressTests {
    private static func course(_ id: String, title: String? = nil) -> Course {
        Course(id: id, code: id, title: title ?? id, credits: 3, availability: [.fall, .spring], prerequisites: [])
    }

    private func progress(
        kinds: [DegreeRequirementKind],
        requirements: [RequirementCategory] = [],
        semesterCourses: [String],
        placeholders: [String: PlaceholderSpec] = [:],
        resolved: [String: String] = [:],
        language: ForeignLanguagePlan? = nil
    ) throws -> [String: CategoryProgress] {
        var program = Program.fixture(id: "p", title: "P", requirements: requirements)
        program.degreeRequirements = kinds.map { DegreeRequirement(kind: $0, creditsText: "3") }
        var catalog = Catalog.fixture(
            courses: ["C01", "PHIL101", "MATH231", "SPAN101", "SPAN102", "SPAN231", "SPAN232"].map { Self.course($0) }
                + [Self.course("MATH220", title: "Elementary Statistics [C3QR]")],
            program: program
        )
        catalog.degreeEligibility = try DegreeEligibility.load(from: DegreeEligibilityTests.bundledURL)
        let pathway = Pathway(
            id: "p", name: "P",
            semesters: [SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: semesterCourses)],
            placeholders: placeholders, resolvedPlaceholders: resolved
        )
        let rows = try ProgressCalculator(catalog: catalog).progress(
            programID: "p", pathway: pathway, transferCredits: [], languagePlan: language
        ).categories
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @Test func resolvedPhilosophyPlaceholderCompletesTheRow() throws {
        let rows = try progress(kinds: [.philosophy], semesterCourses: ["PHIL101"],
                                resolved: [PathwayPlaceholder.id(categoryID: "degree-philosophy", optionIndex: 0): "PHIL101"])
        let row = try #require(rows["degree-philosophy"])
        #expect(row.name == "Degree: Philosophy")
        #expect(row.completedCredits == 3 && row.requiredCredits == 3)
    }

    @Test func unresolvedPlaceholderLeavesTheRowOpen() throws {
        let id = PathwayPlaceholder.id(categoryID: "degree-philosophy", optionIndex: 0)
        let rows = try progress(kinds: [.philosophy], semesterCourses: [id],
                                placeholders: [id: PlaceholderSpec(categoryID: "degree-philosophy", categoryName: "Philosophy (B.A.)", alternates: ["PHIL101"], credits: 3)])
        #expect(rows["degree-philosophy"]?.completedCredits == 0)
    }

    @Test func oldPlanShowsDegreeRowsUnmet() throws {
        // A B.A. plan saved before degree requirements existed: no language answer, no degree courses
        let rows = try progress(kinds: [.foreignLanguage, .philosophy], semesterCourses: ["C01"])
        let language = try #require(rows["degree-foreignLanguage"])
        #expect(language.name == "Degree: Foreign Language through 232")
        #expect(language.completedCredits == 0 && language.requiredCredits == 12)
        #expect(rows["degree-philosophy"]?.completedCredits == 0)
    }

    @Test func languageRowCountsPlannedSequence() throws {
        let rows = try progress(kinds: [.foreignLanguage], semesterCourses: ["SPAN231", "SPAN232"],
                                language: ForeignLanguagePlan(subject: "SPAN", placement: .level231))
        let row = try #require(rows["degree-foreignLanguage"])
        #expect(row.requiredCredits == 6 && row.completedCredits == 6)
        let placedOut = try progress(kinds: [.foreignLanguage], semesterCourses: ["C01"],
                                     language: ForeignLanguagePlan(subject: "SPAN", placement: .placedOut))
        #expect(placedOut["degree-foreignLanguage"]?.requiredCredits == 0)
    }

    @Test func genEdCourseLeavesQuantitativeUnmet() throws {
        let genEdQuantitative = RequirementCategory(id: "gened-c3qr", name: "General Education - Quantitative Reasoning [C3QR]",
                                                    requiredCredits: 3, courseOptions: [["MATH220"]])
        let rows = try progress(kinds: [.quantitative], requirements: [genEdQuantitative], semesterCourses: ["MATH220"])
        #expect(rows["degree-quantitative"]?.completedCredits == 0)
        let met = try progress(kinds: [.quantitative], requirements: [genEdQuantitative], semesterCourses: ["MATH220", "MATH231"])
        #expect(met["degree-quantitative"]?.completedCredits == 3)
    }
}
