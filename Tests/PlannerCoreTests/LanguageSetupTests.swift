import Foundation
import Testing
@testable import JMUCoursePlanner
@testable import PlannerCore

/// The B.A. foreign-language answer: when setup asks for it, where the
/// sequence starts, and plans saved before it existed.
@Suite("Language setup")
struct LanguageSetupTests {
    @Test func languageStepFollowsMinorWhenNeeded() {
        var flow = SetupFlow()
        flow.needsLanguage = true
        flow.selectYear(.incomingFreshman)
        #expect(flow.route == [.year, .major, .minor, .language, .transfer, .workload])
        for _ in 0..<3 { flow.advance(majorSelectionComplete: true) }
        #expect(flow.step == .language)
        flow.advance(majorSelectionComplete: true)
        #expect(flow.step == .transfer)
        flow.back()
        #expect(flow.step == .language)
    }

    @Test func noLanguageStepForBS() {
        var flow = SetupFlow()
        flow.selectYear(.junior)
        #expect(flow.route == [.year, .major, .minor, .transcript, .review, .workload])
        for _ in 0..<3 { flow.advance(majorSelectionComplete: true) }
        #expect(flow.step == .transcript)
    }

    @Test func resumeAtLanguage() {
        // Generating an older B.A. plan with no language answer opens setup at the language step
        var flow = SetupFlow()
        flow.needsLanguage = true
        flow.selectYear(.junior)
        flow.resume(at: .language)
        #expect(flow.step == .language)
        #expect(flow.visited == [.year, .major, .minor])
        flow.advance(majorSelectionComplete: true)
        #expect(flow.step == .transcript)
    }

    @Test func languageOnlyRouteIsJustTheLanguageStep() {
        // A regeneration that needs the answer asks only for the language, then resumes
        var flow = SetupFlow()
        flow.needsLanguage = true
        flow.languageOnly = true
        flow.selectYear(.junior)
        #expect(flow.route == [.language])
        flow.resume(at: .language)
        #expect(flow.step == .language && flow.visited.isEmpty)
    }

    @Test func notSureStartsAt101() {
        #expect(LanguagePlacement.notSure.startingNumber == 101)
        #expect(LanguagePlacement.level231.startingNumber == 231)
        #expect(LanguagePlacement.placedOut.startingNumber == nil)
    }

    @Test func languageIsRequiredByABAMajorOnly() {
        var ba = Program.fixture(id: "soc", title: "Sociology, B.A.", requirements: [])
        ba.degreeRequirements = [DegreeRequirement(kind: .foreignLanguage, creditsText: "0-12"), DegreeRequirement(kind: .philosophy, creditsText: "3")]
        var bs = Program.fixture(id: "psyc", title: "Psychology, B.S.", requirements: [])
        bs.degreeRequirements = [DegreeRequirement(kind: .quantitative, creditsText: "3")]
        var minor = ba
        minor.kind = .minor
        #expect(ForeignLanguagePlan.isRequired(by: [bs, ba]))
        #expect(!ForeignLanguagePlan.isRequired(by: [bs]))
        #expect(!ForeignLanguagePlan.isRequired(by: [bs, minor]))
    }

    @Test func oldPlanDecodesWithoutLanguage() throws {
        var plan = SavedStudentPlan(programID: "soc")
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        json["foreignLanguage"] = nil
        let decoded = try JSONDecoder().decode(SavedStudentPlan.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.foreignLanguage == nil)
        plan.foreignLanguage = ForeignLanguagePlan(subject: "SPAN", placement: .level102)
        #expect(try JSONDecoder().decode(SavedStudentPlan.self, from: JSONEncoder().encode(plan)).foreignLanguage == plan.foreignLanguage)
    }
}
