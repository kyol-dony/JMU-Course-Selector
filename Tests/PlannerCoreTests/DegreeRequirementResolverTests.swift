import Foundation
import Testing
@testable import PlannerCore

/// Which degree requirements a plan meets, with which course, and what it
/// still needs: the Gen Ed exclusion, one course per requirement, and where
/// the foreign-language sequence starts.
@Suite("Degree requirement resolver")
struct DegreeRequirementResolverTests {
    private static func course(_ id: String, title: String? = nil, credits: Int = 3) -> Course {
        Course(id: id, code: id, title: title ?? id, credits: credits, availability: [.fall, .spring], prerequisites: [])
    }

    private func resolver(without missing: Set<String> = []) throws -> DegreeRequirementResolver {
        let ids = ["PHIL101", "PHIL120", "MATH231", "ISAT151", "BIO140", "SPAN101", "SPAN102", "SPAN231", "SPAN232"]
        var catalog = Catalog.fixture(
            courses: ids.filter { !missing.contains($0) }.map { Self.course($0) } + [
                Self.course("MATH220", title: "Elementary Statistics [C3QR]"), Self.course("CHEM131"), Self.course("CHEM131L", credits: 1)
            ],
            program: Program.fixture(id: "p", title: "P", requirements: [])
        )
        catalog.degreeEligibility = try DegreeEligibility.load(from: DegreeEligibilityTests.bundledURL)
        return DegreeRequirementResolver(catalog: catalog)
    }

    private func resolve(
        _ kinds: [DegreeRequirementKind],
        planned: [String] = [],
        completed: Set<String> = [],
        genEd: Set<String> = [],
        language: ForeignLanguagePlan? = nil,
        missing: Set<String> = []
    ) throws -> DegreeResolution {
        try resolver(without: missing).resolve(kinds: kinds, plannedCourseIDs: planned, completedCourseIDs: completed,
                                               genEdCourseIDs: genEd, languagePlan: language)
    }

    @Test func majorCourseMeetsQuantitative() throws {
        let result = try resolve([.quantitative], planned: ["MATH231"])
        #expect(result.satisfiedBy[.quantitative] == "MATH231")
        #expect(result.placeholdersNeeded.isEmpty)
    }

    @Test func genEdCourseDoesNotCount() throws {
        let result = try resolve([.quantitative], planned: ["MATH220"], genEd: ["MATH220"])
        #expect(result.satisfiedBy[.quantitative] == nil)
        #expect(result.placeholdersNeeded == [.quantitative])
    }

    @Test func oneCourseMeetsOneKindOnly() throws {
        // ISAT 151 is on both the Scientific Literacy and Quantitative lists
        let result = try resolve([.scientificLiteracy, .quantitative], planned: ["ISAT151"])
        #expect(result.satisfiedBy.values.filter { $0 == "ISAT151" }.count == 1)
        #expect(result.placeholdersNeeded.count == 1)
    }

    @Test func oneCreditLabDoesNotMeetScientificLiteracy() throws {
        // Scientific Literacy needs at least 3 credits; CHEM 131L is a 1-credit lab
        #expect(try resolve([.scientificLiteracy], planned: ["CHEM131L"]).placeholdersNeeded == [.scientificLiteracy])
        #expect(try resolve([.scientificLiteracy], planned: ["CHEM131L", "CHEM131"]).satisfiedBy[.scientificLiteracy] == "CHEM131")
    }

    @Test func dualEligibleCourseGoesWhereItIsNeeded() throws {
        // ISAT 151 meets either; CHEM 131 only Scientific Literacy — both requirements are met
        let result = try resolve([.scientificLiteracy, .quantitative], planned: ["ISAT151", "CHEM131"])
        #expect(result.satisfiedBy[.scientificLiteracy] == "CHEM131")
        #expect(result.satisfiedBy[.quantitative] == "ISAT151")
        #expect(result.placeholdersNeeded.isEmpty)
    }

    @Test func openGenEdSlotDoesNotClaimACourse() throws {
        // The Gen Ed QR placeholder is still unresolved, so MATH 231 is free for the degree requirement
        let quantitative = RequirementCategory(id: "gened-c3qr", name: "General Education - Quantitative Reasoning [C3QR]",
                                               requiredCredits: 3, courseOptions: [["MATH231", "COB191"]])
        let genEd = GenEdAssignment.courses(categories: [quantitative],
                                            courseIDs: [PathwayPlaceholder.id(categoryID: "gened-c3qr", optionIndex: 0), "MATH231"],
                                            fixed: [:], degreeKinds: [.quantitative],
                                            eligibility: try DegreeEligibility.load(from: DegreeEligibilityTests.bundledURL))
        #expect(genEd.isEmpty)
    }

    @Test func philosophy120DoesNotCount() throws {
        #expect(try resolve([.philosophy], planned: ["PHIL120"]).placeholdersNeeded == [.philosophy])
        #expect(try resolve([.philosophy], completed: ["PHIL101"]).satisfiedBy[.philosophy] == "PHIL101")
    }

    @Test func notSureSchedulesFullSequence() throws {
        let result = try resolve([.foreignLanguage], language: ForeignLanguagePlan(subject: "SPAN", placement: .notSure))
        #expect(result.languageCoursesToAdd == ["SPAN101", "SPAN102", "SPAN231", "SPAN232"])
        #expect(!result.languageComplete)
    }

    @Test func placementStartsMidSequence() throws {
        let result = try resolve([.foreignLanguage], language: ForeignLanguagePlan(subject: "SPAN", placement: .level231))
        #expect(result.languageCoursesToAdd == ["SPAN231", "SPAN232"])
    }

    @Test func placedOutAddsNothing() throws {
        let result = try resolve([.foreignLanguage], language: ForeignLanguagePlan(subject: "SPAN", placement: .placedOut))
        #expect(result.languageCoursesToAdd.isEmpty)
        #expect(result.languageComplete)
    }

    @Test func transferRaisesTheStartingLevel() throws {
        let spanish101 = ForeignLanguagePlan(subject: "SPAN", placement: .level101)
        #expect(try resolve([.foreignLanguage], completed: ["SPAN231"], language: spanish101).languageCoursesToAdd == ["SPAN232"])
        let intensive = try resolve([.foreignLanguage], completed: ["SPAN212"], language: spanish101)
        #expect(intensive.languageComplete && intensive.languageCoursesToAdd.isEmpty)
        #expect(try resolve([.foreignLanguage], completed: ["SPAN111"], language: spanish101).languageCoursesToAdd == ["SPAN231", "SPAN232"])
    }

    @Test func plannedSequenceCoursesAreNotAddedAgain() throws {
        let result = try resolve([.foreignLanguage], planned: ["SPAN101", "SPAN102"], language: ForeignLanguagePlan(subject: "SPAN", placement: .level101))
        #expect(result.languageCoursesToAdd == ["SPAN231", "SPAN232"])
    }

    @Test func missingSequenceCourseBecomesPlaceholder() throws {
        let result = try resolve([.foreignLanguage], language: ForeignLanguagePlan(subject: "SPAN", placement: .notSure), missing: ["SPAN231"])
        #expect(result.missingLanguageLevels == [231])
        #expect(result.languageCoursesToAdd == ["SPAN101", "SPAN102", "SPAN232"])
        #expect(result.placeholdersNeeded == [.foreignLanguage])
    }

    @Test func noLanguageAnswerAddsNothing() throws {
        let result = try resolve([.foreignLanguage])
        #expect(result.languageCoursesToAdd.isEmpty && !result.languageComplete && result.placeholdersNeeded.isEmpty)
    }

    @Test func genEdAssignmentPrefersNonDegreeCourse() throws {
        // Gen Ed QR accepts MATH 231 or COB 191; MATH 231 is better kept for the B.S. Quantitative requirement
        let quantitative = RequirementCategory(id: "gened-c3qr", name: "General Education - Quantitative Reasoning [C3QR]",
                                               requiredCredits: 3, courseOptions: [["MATH231", "COB191"]])
        let eligibility = try DegreeEligibility.load(from: DegreeEligibilityTests.bundledURL)
        let genEd = GenEdAssignment.courses(categories: [quantitative], courseIDs: ["MATH231", "COB191"], fixed: [:],
                                            degreeKinds: [.quantitative], eligibility: eligibility)
        #expect(genEd == ["COB191"])
        // Two MATH courses both qualify: Gen Ed takes one, the other still meets Quantitative
        let bothMath = RequirementCategory(id: "gened-c3qr", name: "General Education - Quantitative Reasoning [C3QR]",
                                           requiredCredits: 3, courseOptions: [["MATH231", "MATH220"]])
        let shared = GenEdAssignment.courses(categories: [bothMath], courseIDs: ["MATH231", "MATH220"], fixed: [:],
                                             degreeKinds: [.quantitative], eligibility: eligibility)
        #expect(shared.count == 1)
        #expect(try resolve([.quantitative], planned: ["MATH231", "MATH220"], genEd: shared).satisfiedBy[.quantitative] != nil)
        // A Gen Ed placeholder the student resolved keeps the course they chose
        let fixed = GenEdAssignment.courses(categories: [quantitative], courseIDs: ["MATH231", "COB191"],
                                            fixed: [PathwayPlaceholder.id(categoryID: "gened-c3qr", optionIndex: 0): "MATH231"],
                                            degreeKinds: [.quantitative], eligibility: eligibility)
        #expect(fixed == ["MATH231"])
    }

    @Test func kindsUnionAcrossMajors() {
        var bs = Program.fixture(id: "bs", title: "B.S.", requirements: [])
        bs.degreeRequirements = [DegreeRequirement(kind: .quantitative, creditsText: "3"), DegreeRequirement(kind: .scientificLiteracy, creditsText: "3")]
        var ba = Program.fixture(id: "ba", title: "B.A.", requirements: [])
        ba.degreeRequirements = [DegreeRequirement(kind: .foreignLanguage, creditsText: "0-12"), DegreeRequirement(kind: .philosophy, creditsText: "3"),
                                 DegreeRequirement(kind: .quantitative, creditsText: "3")]
        var minor = ba
        minor.kind = .minor
        #expect(DegreeRequirementResolver.kinds(for: [bs, ba]) == [.philosophy, .foreignLanguage, .scientificLiteracy, .quantitative])
        #expect(DegreeRequirementResolver.kinds(for: [bs, minor]) == [.scientificLiteracy, .quantitative])
    }
}
