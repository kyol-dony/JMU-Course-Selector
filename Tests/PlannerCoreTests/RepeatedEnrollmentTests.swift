import Foundation
import Testing
@testable import PlannerCore

@Suite("Repeated enrollments")
struct RepeatedEnrollmentTests {
    private func parse(_ remark: String) -> RepeatedEnrollment? {
        RepeatedEnrollment(remark: remark)
    }

    @Test("catalog remarks give the number of enrollments and their credits")
    func remarksGiveCountAndCredits() {
        // Special Education B.S., Licensure Requirements
        #expect(parse("Taken twice at 2 credits for a total of 4 credits") == RepeatedEnrollment(count: 2, creditsEach: 2))
        #expect(parse("Taken twice for a total of 8 credits") == RepeatedEnrollment(count: 2, creditsEach: 4))
        #expect(parse("Taken twice at 1 credit for a total of 2 credits") == RepeatedEnrollment(count: 2, creditsEach: 1))
        // Inclusive Early Childhood Education B.S.
        #expect(parse("Taken twice for 10 credits") == RepeatedEnrollment(count: 2, creditsEach: 5))
        // Music B.M.
        #expect(parse("Taken at two credit hours for six semesters for a total of 12 credit hours") == RepeatedEnrollment(count: 6, creditsEach: 2))
        #expect(parse("Taken for six semesters for a total of 6 credit hours in addition to the assigned ensemble requirement") == RepeatedEnrollment(count: 6, creditsEach: 1))
        #expect(parse("Taken twice") == RepeatedEnrollment(count: 2, creditsEach: nil))
        // Art B.A., Art Education
        #expect(parse("Taken concurrently with ARED 300 , ARED 302 and ARED 400 for 2 credits three times for a total of 6 credits.") == RepeatedEnrollment(count: 3, creditsEach: 2))
        // Theatre (Musical Theatre) B.A. footnotes
        #expect(parse("Two enrollments of one credit each.") == RepeatedEnrollment(count: 2, creditsEach: 1))
        #expect(parse("Four enrollments of one credit each.") == RepeatedEnrollment(count: 4, creditsEach: 1))
        // Music B.M.
        #expect(parse("One each semester for 8 semesters") == RepeatedEnrollment(count: 8, creditsEach: nil))
    }

    @Test("remarks without a repeat are not repeats")
    func singleEnrollmentRemarks() {
        #expect(parse("Taken once for 2 credits") == nil)
        #expect(parse("Must be taken for 3 credit hours") == nil)
        #expect(parse("Students may substitute 1 credit of MUS 243 or MUS 244 for 1 credit of MUS 143 rather than repeating the course.") == nil)
    }

    private func catalog(_ program: Program, courses: [(String, Int)]) -> Catalog {
        Catalog.fixture(
            courses: courses.map { id, credits in
                Course(id: id, code: "\(id.prefix(while: \.isLetter)) \(id.drop(while: \.isLetter))", title: id, credits: credits, availability: [.fall, .spring], prerequisites: [])
            },
            program: program
        )
    }

    private func enrollments(of courseID: String, in pathway: Pathway) -> [SemesterIdentity] {
        pathway.semesters.flatMap { semester in
            semester.courseIDs.filter { $0 == courseID || pathway.placeholders[$0]?.repeatOf == courseID }.map { _ in semester.id }
        }
    }

    @Test("a course taken twice gets a repeat slot in a later semester")
    func takenTwiceSchedulesARepeat() throws {
        // Special Education B.S. "Licensure Requirements"
        let program = Program.fixture(id: "sped", title: "Special Education", requirements: [
            RequirementCategory(
                id: "licensure", name: "Licensure Requirements", requiredCredits: 6,
                courseOptions: [["EXED478"], ["EXED480"]],
                courseRemarks: ["EXED478": ["Taken twice at 2 credits for a total of 4 credits"]]
            )
        ])
        let catalog = catalog(program, courses: [("EXED478", 2), ("EXED480", 2)])
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(for: "sped", workload: .standard, transferCredits: []).first)

        let terms = enrollments(of: "EXED478", in: pathway)
        #expect(terms.count == 2)
        #expect(terms.count == 2 && terms[0] < terms[1])
        let repeatSlot = try #require(pathway.placeholders.values.first { $0.repeatOf == "EXED478" })
        #expect(repeatSlot.credits == 2)
        #expect(repeatSlot.categoryID == "licensure")
        // The slot is that course again: it offers no choice, and can't stand
        // in for another course's prerequisite.
        #expect(PlaceholderCourseDomain.eligibleCourseIDs(for: repeatSlot, catalog: catalog).isEmpty)
        #expect(AcademicCreditCalculator.projectedHours(in: pathway.semesters, placeholders: pathway.placeholders, transferCredits: [], catalog: catalog) == 6)

        let progress = try ProgressCalculator(catalog: catalog).progress(programID: "sped", pathway: pathway, transferCredits: [])
        #expect(progress.categories.first { $0.id == "licensure" }?.completedCredits == 6)
    }

    @Test("two requirements that each take a course several times each get their enrollments")
    func lessonsInTwoRequirements() throws {
        // Music B.M.: lessons in the primary instrument and in jazz.
        let program = Program.fixture(id: "music", title: "Music", requirements: [
            RequirementCategory(id: "primary", name: "Applied Music Lesson in Primary Instrument", requiredCredits: 4, courseOptions: [["MUAP300"]],
                                courseRemarks: ["MUAP300": ["Taken at two credit hours for two semesters for a total of 4 credit hours"]]),
            RequirementCategory(id: "jazz", name: "Applied Music Lesson in Jazz", requiredCredits: 6, courseOptions: [["MUAP300"]],
                                courseRemarks: ["MUAP300": ["Taken at two credit hours for three semesters for a total of 6 credit hours"]])
        ])
        let catalog = catalog(program, courses: [("MUAP300", 2)])
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(for: "music", workload: .standard, transferCredits: []).first)

        let terms = enrollments(of: "MUAP300", in: pathway)
        #expect(terms.count == 5)
        #expect(Set(terms).count == 5, "one lesson per semester")
        #expect(AcademicCreditCalculator.projectedHours(in: pathway.semesters, placeholders: pathway.placeholders, transferCredits: [], catalog: catalog) == 10)
    }

    @Test("plans saved before repeats still load")
    func oldPlaceholderSpecsDecode() throws {
        let json = #"{"categoryID":"core","categoryName":"Core","alternates":["A"],"credits":3}"#
        let spec = try JSONDecoder().decode(PlaceholderSpec.self, from: Data(json.utf8))
        #expect(spec.repeatOf == nil)
        let encoded = String(decoding: try JSONEncoder().encode(spec), as: UTF8.self)
        #expect(!encoded.contains("repeatOf"))
    }

    @Test("a repeat slot knows which enrollment it is")
    func enrollmentNumbers() {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2027, term: .fall), courseIDs: ["MUAP300"]),
            SemesterPlan(id: SemesterIdentity(year: 2028, term: .spring), courseIDs: ["__pl::jazz-repeat::0"]),
            SemesterPlan(id: SemesterIdentity(year: 2028, term: .fall), courseIDs: ["__pl::jazz-repeat::1"])
        ], placeholders: [
            "__pl::jazz-repeat::0": PlaceholderSpec(categoryID: "jazz", categoryName: "Jazz", alternates: [], credits: 2, repeatOf: "MUAP300"),
            "__pl::jazz-repeat::1": PlaceholderSpec(categoryID: "jazz", categoryName: "Jazz", alternates: [], credits: 2, repeatOf: "MUAP300")
        ])
        #expect(pathway.enrollmentNumber(of: "__pl::jazz-repeat::0") == 2)
        #expect(pathway.enrollmentNumber(of: "__pl::jazz-repeat::1") == 3)
        #expect(pathway.enrollmentNumber(of: "MUAP300") == nil)
    }
}
