import Foundation
import Testing
@testable import PlannerCore

@Suite struct ContinuingStudentScheduleTests {
    @Test func currentPreservedAndPrerequisiteWorksLater() throws {
        let c = TranscriptTestFixtures.prerequisiteCatalog()
        let current = SemesterPlan(id: .init(year: 2026, term: .fall), courseIDs: ["CS149", "UNKNOWN"], creditOverrides: ["UNKNOWN": 1.5], courseTitles: ["UNKNOWN": "Study"])
        let paths = try ScheduleGenerator(catalog: c).generatePathways(for: "cs", workload: .light, transferCredits: [], preservedSemester: current, earnedHoursAtStart: 49)
        #expect(paths.count == 3)
        #expect(paths.allSatisfy { $0.semesters.first == current })
        #expect(paths.allSatisfy { $0.semesters.dropFirst().first?.id == .init(year: 2027, term: .spring) })
        #expect(paths.allSatisfy { $0.semesters.flatMap(\.courseIDs).filter { $0 == "CS149" }.count == 1 })
        #expect(!ConflictDetector(catalog: c).warnings(for: paths[0], overrides: [], earnedHoursAtStart: 49).contains { $0.kind == .missingPrerequisite })
        #expect(AcademicCreditCalculator.hours(in: current, catalog: c) == 4.5)
    }
    @Test func correctedAwardAndCurrentAmountsAffectProgress() throws {
        let c = TranscriptTestFixtures.prerequisiteCatalog()
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: .init(year: 2026, term: .fall), courseIDs: ["CS159"], creditOverrides: ["CS159": 1.5])])
        let result = try ProgressCalculator(catalog: c).progress(programID: "cs", pathway: p, transferCredits: [.init(sourceDescription: "Partial", courseIDs: ["CS149"], credits: 1.5)])
        #expect(result.categories.first?.completedCredits == 3)
        #expect(result.earnedHours == 1.5)
        #expect(result.projectedHours == 3)
    }
    @Test func legacyProgressDecodes() throws {
        let data = Data("{\"categories\":[]}".utf8)
        let result = try JSONDecoder().decode(GraduationProgress.self, from: data)
        #expect(result.earnedHours == 0)
    }
    @Test func sameTermPrerequisiteStillWarns() {
        let c = TranscriptTestFixtures.prerequisiteCatalog()
        let p = Pathway(id: "p", name: "P", semesters: [.init(id: .init(year: 2026, term: .fall), courseIDs: ["CS149", "CS159"])])
        #expect(ConflictDetector(catalog: c).warnings(for: p, overrides: [], earnedHoursAtStart: 49).contains { $0.kind == .missingPrerequisite && $0.courseID == "CS159" })
    }
    @Test func emptyAndCompletedCurrentRetained() throws {
        let c = TranscriptTestFixtures.prerequisiteCatalog()
        let current = SemesterPlan(id: .init(year: 2026, term: .fall), courseIDs: [])
        let paths = try ScheduleGenerator(catalog: c).generatePathways(for: "cs", workload: .light, transferCredits: [.init(sourceDescription: "Done", courseIDs: ["CS149", "CS159"], credits: 6)], preservedSemester: current, earnedHoursAtStart: 6)
        #expect(paths.allSatisfy { $0.semesters == [current] })
    }
    @Test func generalCreditShrinksElectivesWithoutDoubleCounting() throws {
        let c = TranscriptTestFixtures.degreeCatalog()
        let general = TransferCredit(sourceDescription: "General", courseIDs: [], credits: 10.5)
        let required = TransferCredit(sourceDescription: "Required", courseIDs: ["REQ1"], credits: 3)
        let paths = try ScheduleGenerator(catalog: c).generatePathways(for: "degree", workload: .standard, transferCredits: [general, required], preservedSemester: .init(id: .init(year: 2026, term: .fall), courseIDs: []), earnedHoursAtStart: 13.5)
        #expect(paths[0].placeholders.values.filter { $0.categoryID == ScheduleGenerator.openElectiveCategoryID }.reduce(0.0) { $0 + $1.credits } == 19.5)
        let progress = try ProgressCalculator(catalog: c).progress(programID: "degree", pathway: paths[0], transferCredits: [general, required])
        #expect(progress.earnedHours == 13.5)
    }
    @Test(arguments: [(27.5, ClassStanding.firstYear), (28.0, .sophomore), (59.5, .sophomore), (60.0, .junior), (89.5, .junior), (90.0, .senior)])
    func standingBoundary(_ pair: (Double, ClassStanding)) { #expect(ClassStanding.forEarnedCredits(pair.0) == pair.1) }
}
