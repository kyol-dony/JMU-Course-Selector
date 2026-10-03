import AppKit
import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

private actor FirstLocalThenSuspendedGenerator: AnchoredScheduleGenerating {
    var first = true
    let suspended: SuspendedAnchoredGenerator
    init(_ suspended: SuspendedAnchoredGenerator) { self.suspended = suspended }
    func regenerate(_ request: PartialRegenerationRequest, progress: @escaping @Sendable (ScheduleGenerationProgress) -> Void) async throws -> Pathway {
        if first {
            first = false
            return try await LocalAnchoredScheduleGenerator().regenerate(request, progress: progress)
        }
        return try await suspended.regenerate(request, progress: progress)
    }
}

@Suite @MainActor struct PartialRegenerationWorkflowTests {
    @Test func editedPrefixUndoRedoSaveReopenAndRepeat() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { PlanStore.flushPendingAutosaves(); try? FileManager.default.removeItem(at: root) }
        let store = PlanStore(storageDirectory: root)
        var catalog = AnchoredRegenerationFixtures.degreeCatalog()
        catalog.courses.append(.init(id: "EL101", code: "EL 101", title: "Extra elective", credits: 3, availability: nil, prerequisites: []))
        store.catalog = catalog
        let fall = SemesterIdentity(year: 2026, term: .fall)
        let open = "__pl::open-elective::0"
        let source = Pathway(id: "path-1", name: "Crafted balanced", semesters: [
            .init(id: fall, courseIDs: ["REQ2", "ZZZ123", open],
                  creditOverrides: ["REQ2": 1.5, "ZZZ123": 1.5], courseTitles: ["ZZZ123": "Independent study"]),
            .init(id: fall.next, courseIDs: []),
            .init(id: fall.next.next, courseIDs: ["REQ9", "__pl::open-elective::2"])
        ], placeholders: [
            open: .init(categoryID: "open-elective", categoryName: "Open Elective", alternates: [], credits: 3),
            "__pl::open-elective::1": .init(categoryID: "open-elective", categoryName: "Open Elective", alternates: [], credits: 3),
            "__pl::open-elective::2": .init(categoryID: "open-elective", categoryName: "Open Elective", alternates: [], credits: 3)
        ], resolvedPlaceholders: ["__pl::open-elective::1": "REQ9"])
        var plan = SavedStudentPlan(programID: "degree", pathways: [
            source, .init(id: "path-2", name: "Major", semesters: source.semesters),
            .init(id: "path-3", name: "Gen Ed", semesters: source.semesters)
        ], activePathwayID: "path-1")
        plan.studentYear = .sophomore
        plan.currentSemester = source.semesters[0]
        plan.academicRecords = [
            .init(code: "REQ1", title: "Partial award", courseIDs: ["REQ1"], earnedCredits: 1.5, status: .earned, source: .transcriptResident, matchConfirmed: true),
            .init(code: "GENERAL", title: "General credit", earnedCredits: 10.5, status: .earned, source: .manual, matchConfirmed: true),
            .init(code: "REQ2", title: "Current", courseIDs: ["REQ2"], attemptedCredits: 1.5, status: .inProgress, source: .transcriptResident, matchConfirmed: true),
            .init(code: "ZZZ123", title: "Independent study", attemptedCredits: 1.5, status: .inProgress, source: .manual, matchConfirmed: true)
        ]
        store.plan = plan
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        store.moveCourse("ZZZ123", to: fall, at: 0)
        let old = store.activePathway!
        let anchors = Array(old.semesters.prefix(2))
        let alternatives = Array(store.plan.pathways.dropFirst())
        let history = store.effectiveAcademicHistory
        await store.regenerateActivePathway(after: fall.next)
        let generated = try #require(store.activePathway)
        #expect(Array(generated.semesters.prefix(2)) == anchors)
        #expect(Array(store.plan.pathways.dropFirst()) == alternatives)
        #expect(store.effectiveAcademicHistory == history)
        #expect(AcademicCreditCalculator.projectedHours(in: generated.semesters, placeholders: generated.placeholders, transferCredits: history.effectiveCredits, catalog: catalog) == 120)
        #expect(!generated.semesters.dropFirst(2).flatMap(\.courseIDs).contains(open))
        #expect(generated.resolvedPlaceholders.isEmpty)
        undo.undo()
        #expect(store.activePathway == old)
        undo.redo()
        #expect(store.activePathway == generated)
        let slot = try #require(generated.semesters.dropFirst(2).flatMap(\.courseIDs).first(where: PathwayPlaceholder.isPlaceholder))
        store.resolvePlaceholder(slot, with: "EL101")
        #expect(store.activePathway?.resolvedPlaceholders[slot] == "EL101")
        await store.regenerateActivePathway(after: fall.next)
        #expect(store.activePathway?.resolvedPlaceholders[slot] == nil)
        #expect(Array(store.activePathway!.semesters.prefix(2)) == anchors)
        #expect(store.effectiveAcademicHistory == history)
        PlanStore.flushPendingAutosaves()
        let data = try Data(contentsOf: root.appendingPathComponent("\(store.plan.id.uuidString).jmuplan.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode(SavedStudentPlan.self, from: data)
        #expect(saved.pathways == store.plan.pathways)
        let reopened = PlanStore(storageDirectory: root)
        reopened.catalog = catalog
        reopened.resume(saved)
        let beforeLast = reopened.activePathway!
        await reopened.regenerateActivePathway(after: beforeLast.semesters.last!.id)
        let afterLast = reopened.activePathway!
        #expect(afterLast.semesters == beforeLast.semesters)
        #expect(afterLast.placeholders == beforeLast.placeholders)
        #expect(Array(reopened.plan.pathways.dropFirst()) == alternatives)
        #expect(reopened.effectiveAcademicHistory == history)
        #expect(AcademicCreditCalculator.projectedHours(in: afterLast.semesters, placeholders: afterLast.placeholders, transferCredits: history.effectiveCredits, catalog: catalog) == 120)
        #expect(Set(afterLast.semesters.flatMap(\.courseIDs).filter(PathwayPlaceholder.isPlaceholder)).count == afterLast.semesters.flatMap(\.courseIDs).filter(PathwayPlaceholder.isPlaceholder).count)
    }
    @Test(arguments: [false, true]) func contextChangeAfterSuccessRejectsNextResult(_ changeCatalog: Bool) async {
        let suspended = SuspendedAnchoredGenerator()
        let store = PlanStorePartialRegenerationTests.makeStore(worker: FirstLocalThenSuspendedGenerator(suspended))
        let fall = PlanStorePartialRegenerationTests.fall
        await store.regenerateActivePathway(after: fall)
        let successful = store.activePathway!
        let pending = Task { await store.regenerateActivePathway(after: fall) }
        await suspended.waitForCalls(1)
        if changeCatalog { store.catalog?.courses[0].credits = 4 }
        else { store.plan.programID = "other" }
        let changed = store.plan
        await suspended.report(0)
        await suspended.succeed(0, with: successful)
        await pending.value
        #expect(store.plan == changed)
        #expect(store.activePathway == successful)
        #expect(store.partialRegeneration == nil)
    }
    @Test func semesterOverrideSurvivesOnlyWhenItsSemesterStillExists() async {
        let worker = SuspendedAnchoredGenerator()
        let store = PlanStorePartialRegenerationTests.makeStore(worker: worker)
        let fall = PlanStorePartialRegenerationTests.fall
        store.plan.pathways[1].semesters.append(.init(id: fall.next.next, courseIDs: []))
        let old = store.activePathway!
        let retained = ConflictOverride(courseID: ConflictWarning.semesterSubjectID, semester: fall.next, kind: .lightLoad)
        let removed = ConflictOverride(courseID: ConflictWarning.semesterSubjectID, semester: fall.next.next, kind: .lightLoad)
        store.plan.overrides = [retained, removed]
        let pending = Task { await store.regenerateActivePathway(after: fall) }
        await worker.waitForCalls(1)
        await worker.succeed(0, with: PlanStorePartialRegenerationTests.replacement(old))
        await pending.value
        #expect(store.plan.overrides == [retained])
    }
}
