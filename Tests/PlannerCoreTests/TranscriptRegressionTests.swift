import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite @MainActor struct TranscriptRegressionTests {
    @Test func splitTermHeadingRetainsCorrectSemester() throws {
        let parsed = try JMUTranscriptParser.parse(pages: ["James Madison University\nUnofficial Transcript\nSpring Semester 2026\nCS 149 Intro 3.00 3.00 A 0.000\nFall Semester", "Page 2 of 2\nJames Madison University\nUnofficial Transcript\n2026\nCS 159 Advanced 3.00 0.00 0.000"])
        #expect(parsed.latestPrintedTerm == "Fall Semester 2026")
        #expect(parsed.records.last?.printedTerm == "Fall Semester 2026")
        let draft = TranscriptReconciler.makeDraft(parsed: parsed, catalog: TranscriptTestFixtures.prerequisiteCatalog(), existingRecords: [], existingCredits: [], defaultSemester: .current())
        #expect(draft.currentSemester == .init(year: 2026, term: .fall))
    }
    @Test(arguments: [AcademicCourseStatus.earned, .inProgress])
    func correctedRequirementsStillReachDegreeMinimum(_ status: AcademicCourseStatus) throws {
        let catalog = TranscriptTestFixtures.degreeCatalog()
        let credits: [TransferCredit] = status == .earned ? [.init(sourceDescription: "Corrected", courseIDs: ["REQ1"], credits: 1.5)] : []
        let current = SemesterPlan(id: .init(year: 2026, term: .fall), courseIDs: status == .inProgress ? ["REQ1"] : [], creditOverrides: ["REQ1": 1.5])
        let paths = try ScheduleGenerator(catalog: catalog).generatePathways(for: "degree", workload: .standard, transferCredits: credits, preservedSemester: current, earnedHoursAtStart: status == .earned ? 1.5 : 0)
        for path in paths {
            let courseHours = path.semesters.reduce(0.0) { $0 + AcademicCreditCalculator.hours(in: $1, catalog: catalog) }
            let electives = path.placeholders.values.reduce(0.0) { $0 + $1.credits }
            #expect(courseHours + electives + credits.reduce(0.0) { $0 + $1.credits } == 120)
        }
    }
    @Test func increasedCurrentCreditsReduceRemainingHours() throws {
        let catalog = TranscriptTestFixtures.degreeCatalog()
        let current = SemesterPlan(id: .init(year: 2026, term: .fall), courseIDs: ["REQ1"], creditOverrides: ["REQ1": 4.5])
        let paths = try ScheduleGenerator(catalog: catalog).generatePathways(for: "degree", workload: .standard, transferCredits: [], preservedSemester: current, earnedHoursAtStart: 0)
        for path in paths {
            #expect(path.semesters.reduce(0.0) { $0 + AcademicCreditCalculator.hours(in: $1, catalog: catalog) } + path.placeholders.values.reduce(0.0) { $0 + $1.credits } == 120)
        }
    }
    @Test(arguments: [1.5, 3.0])
    func currentDuplicatesRequireDecision(_ manualAmount: Double) {
        let catalog = TranscriptTestFixtures.prerequisiteCatalog()
        let imported = AcademicCourseRecord(code: "CS149", title: "Programming", courseIDs: ["CS149"], attemptedCredits: 3, status: .inProgress, source: .transcriptResident, matchConfirmed: true)
        let manual = AcademicCourseRecord(code: "CS149", title: "Programming", courseIDs: ["CS149"], attemptedCredits: manualAmount, status: .inProgress, source: .manual, matchConfirmed: true)
        let draft = TranscriptReconciler.makeDraft(parsed: nil, catalog: catalog, existingRecords: [imported, manual], existingCredits: [], defaultSemester: .current())
        #expect(TranscriptReconciler.validate(draft, catalog: catalog).contains { $0.kind == .repeatedCourse && $0.isBlocking })
    }
    @Test func backAndResumePreserveEdits() {
        let catalog = TranscriptTestFixtures.prerequisiteCatalog()
        let controller = TranscriptImportController()
        controller.beginManual(catalog: catalog, existingRecords: [], existingCredits: [], defaultSemester: .current())
        controller.draft?.add(course: catalog.coursesByID["CS149"]!, status: .earned)
        var row = controller.draft!.records[0]; row.earnedCredits = 1.5; controller.draft?.update(record: row)
        var flow = SetupFlow(); flow.selectYear(.junior); flow.advance(majorSelectionComplete: true); flow.advance(majorSelectionComplete: true); flow.advance(majorSelectionComplete: true); flow.skipUpload(); flow.back()
        controller.beginManual(catalog: catalog, existingRecords: [], existingCredits: [], defaultSemester: .current())
        flow.skipUpload()
        #expect(flow.step == .review)
        #expect(controller.draft?.records.first?.earnedCredits == 1.5)
        #expect(controller.draft?.records.first?.id == row.id)
    }
    @Test(arguments: ["UNKNOWN", "CS149"])
    func movePreviewCarriesCorrectedCredits(_ code: String) throws {
        let catalog = TranscriptTestFixtures.prerequisiteCatalog()
        let origin = SemesterIdentity(year: 2026, term: .fall), target = origin.next
        let path = Pathway(id: "p", name: "P", semesters: [.init(id: origin, courseIDs: [code], creditOverrides: [code: 10], courseTitles: [code: "Study"]), .init(id: target, courseIDs: ["OTHER"], creditOverrides: ["OTHER": 9])])
        let verdict = try #require(DropVerdictCalculator(catalog: catalog).verdicts(moving: code, in: path, overrides: [], workload: .standard)[target])
        #expect(verdict.newWarnings.contains { $0.kind == .heavyLoad && $0.semester == target && $0.detail.contains("19 credits") })
    }
    @Test func legacyAPHistoryRemapsWithoutRetainingOldEquivalent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = TranscriptTestFixtures.prerequisiteCatalog()
        let program = Program.fixture(id: "new", title: "New major", requirements: [.init(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["CS159"]])])
        let rules = ["CS149", "CS159"].map { TransferCreditRule(source: .apExam(name: "Computer Science A", minimumScore: 5), awardedCourseIDs: [$0], credits: 3, meetsGeneralEducation: false, sourceNote: "Fixture") }
        let catalog = Catalog.fixture(courses: base.courses, program: program, apRules: rules)
        let store = PlanStore(storageDirectory: root); store.catalog = catalog
        store.plan.apScores = [.init(examName: "Computer Science A", score: 5)]
        let legacy = TransferCredit(sourceDescription: "AP Computer Science A score 5", courseIDs: ["CS149"], credits: 3)
        let draft = TranscriptReconciler.makeDraft(parsed: nil, catalog: catalog, existingRecords: [], existingCredits: [legacy], defaultSemester: .current())
        try store.confirmAcademicHistory(TranscriptReconciler.confirm(draft, catalog: catalog))
        store.selectProgram(program)
        #expect(store.effectiveAcademicHistory.completedCourseIDs == ["CS159"])
        #expect(store.effectiveAcademicHistory.earnedHours == 3)
        #expect(store.plan.academicRecords.allSatisfy { $0.source == .apMapped })
    }
}
