import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

/// Suspends only computation; the real store owns mutation, cancellation and persistence.
actor SuspendedAnchoredGenerator: AnchoredScheduleGenerating {
    private struct Call {
        var request: PartialRegenerationRequest
        var progress: @Sendable (ScheduleGenerationProgress) -> Void
        var continuation: CheckedContinuation<Pathway, any Error>
    }
    private var calls: [Call] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func regenerate(_ request: PartialRegenerationRequest, progress: @escaping @Sendable (ScheduleGenerationProgress) -> Void) async throws -> Pathway {
        try await withCheckedThrowingContinuation { continuation in
            calls.append(Call(request: request, progress: progress, continuation: continuation))
            let ready = waiters.filter { calls.count >= $0.0 }
            waiters.removeAll { calls.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForCalls(_ count: Int) async {
        if calls.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func succeed(_ index: Int, with pathway: Pathway) { calls[index].continuation.resume(returning: pathway) }
    func fail(_ index: Int) { calls[index].continuation.resume(throwing: Failure.synthetic) }
    func report(_ index: Int) { calls[index].progress(.init(current: 1, total: 1, pathwayName: "Late progress")) }
    func request(_ index: Int) -> PartialRegenerationRequest { calls[index].request }
    enum Failure: Error { case synthetic }
}

@Suite @MainActor struct PlanStorePartialRegenerationTests {
    static let fall = SemesterIdentity(year: 2026, term: .fall)
    static func makeStore(worker: any AnchoredScheduleGenerating, storageDirectory: URL? = nil) -> PlanStore {
        let store = PlanStore(storageDirectory: storageDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), anchoredGenerator: worker)
        store.catalog = AnchoredRegenerationFixtures.prerequisiteCatalog()
        let source = Pathway(id: "path-2", name: "Crafted major first", semesters: [
            .init(id: fall, courseIDs: ["CS149"]),
            .init(id: fall.next, courseIDs: ["OLD"], creditOverrides: ["OLD": 1.5], courseTitles: ["OLD": "Old elective"])
        ])
        store.plan = SavedStudentPlan(programID: "cs", pathways: [
            .init(id: "path-1", name: "Balanced", semesters: []), source,
            .init(id: "path-3", name: "Gen Ed", semesters: [.init(id: fall, courseIDs: ["CS159"])])
        ], activePathwayID: source.id)
        return store
    }
    static func replacement(_ source: Pathway) -> Pathway {
        Pathway(id: source.id, name: source.name, semesters: [source.semesters[0], .init(id: fall.next, courseIDs: ["CS159"])])
    }
    @Test func successChangesOnlyCapturedPathway() async throws {
        let worker = SuspendedAnchoredGenerator()
        let store = Self.makeStore(worker: worker)
        let before = store.plan
        let task = Task { await store.regenerateActivePathway(after: Self.fall) }
        await worker.waitForCalls(1)
        #expect(store.plan == before)
        #expect(store.partialRegeneration != nil && !store.canEditSchedule)
        #expect(store.scheduleGenerationProgress == nil)
        #expect(await worker.request(0).strategy == .majorFirst)
        await worker.succeed(0, with: Self.replacement(before.pathways[1]))
        await task.value
        #expect(store.plan.pathways[1] == Self.replacement(before.pathways[1]))
        #expect(store.plan.pathways[0] == before.pathways[0] && store.plan.pathways[2] == before.pathways[2])
        #expect(store.plan.academicRecords == before.academicRecords)
        #expect(store.plan.activePathwayID == before.activePathwayID)
        #expect(store.partialRegeneration == nil && store.canEditSchedule)
    }
    @Test(arguments: [false, true]) func failureAndCancelLeavePlanUntouched(_ cancel: Bool) async {
        let worker = SuspendedAnchoredGenerator()
        let store = Self.makeStore(worker: worker)
        let before = store.plan
        let task = Task { await store.regenerateActivePathway(after: Self.fall) }
        await worker.waitForCalls(1)
        if cancel {
            store.cancelPartialRegeneration()
            await worker.succeed(0, with: Self.replacement(before.pathways[1]))
        } else { await worker.fail(0) }
        await task.value
        #expect(store.plan == before)
        #expect(store.partialRegeneration == nil && store.canEditSchedule)
        #expect(cancel ? store.errorMessage == nil : store.errorMessage != nil)
    }
    @Test func lateResultCannotReplaceNewerOperation() async {
        let worker = SuspendedAnchoredGenerator()
        let store = Self.makeStore(worker: worker)
        let source = store.activePathway!
        let first = Task { await store.regenerateActivePathway(after: Self.fall) }
        await worker.waitForCalls(1)
        store.cancelPartialRegeneration()
        let second = Task { await store.regenerateActivePathway(after: Self.fall.next) }
        await worker.waitForCalls(2)
        let token = store.partialRegeneration?.operationID
        await worker.succeed(0, with: Self.replacement(source))
        await first.value
        #expect(store.activePathway == source)
        #expect(store.partialRegeneration?.operationID == token)
        await worker.succeed(1, with: source)
        await second.value
        #expect(store.partialRegeneration == nil)
    }
    @Test func lateProgressCannotReopenLoading() async {
        let worker = SuspendedAnchoredGenerator()
        let store = Self.makeStore(worker: worker)
        let task = Task { await store.regenerateActivePathway(after: Self.fall) }
        await worker.waitForCalls(1)
        store.cancelPartialRegeneration()
        await worker.report(0)
        await worker.fail(0)
        await task.value
        await Task.yield()
        #expect(store.partialRegeneration == nil)
    }
    @Test(arguments: ["plan", "catalog", "workload", "program", "credit", "pathway", "concentration", "minors"])
    func changedPlanOrCatalogRejectsResult(_ change: String) async {
        let worker = SuspendedAnchoredGenerator()
        let store = Self.makeStore(worker: worker)
        let source = store.activePathway!
        let task = Task { await store.regenerateActivePathway(after: Self.fall) }
        await worker.waitForCalls(1)
        switch change {
        case "plan": store.plan = SavedStudentPlan()
        case "catalog": store.catalog?.courses[0].credits = 4
        case "workload": store.plan.workload = .heavy
        case "program": store.plan.programID = "other"
        case "credit": store.plan.transferCredits = [.init(sourceDescription: "New", courseIDs: [], credits: 3)]
        case "pathway": store.plan.activePathwayID = "path-1"
        case "concentration": store.plan.concentrationID = "other"
        default: store.plan.minors = [.init(programID: "other")]
        }
        let changed = store.plan
        #expect(store.partialRegeneration == nil)
        await worker.report(0)
        await worker.succeed(0, with: Self.replacement(source))
        await task.value
        #expect(store.plan == changed)
        #expect(store.partialRegeneration == nil)
    }
    @Test func mutationsAndCompetingGenerationAreLocked() async {
        let worker = SuspendedAnchoredGenerator()
        let store = Self.makeStore(worker: worker)
        let before = store.plan
        let task = Task { await store.regenerateActivePathway(after: Self.fall) }
        await worker.waitForCalls(1)
        store.moveCourse("CS149", to: Self.fall.next)
        store.removeCourse("CS149")
        store.addSemester(Self.fall.next.next)
        store.deleteSemester(Self.fall.next)
        store.resolvePlaceholder("__pl::choice::0", with: "CS149")
        if let warning = store.warnings.first { store.override(warning); store.removeOverride(warning) }
        await store.generateSchedules()
        await store.regenerateActivePathway(after: Self.fall)
        #expect(store.plan == before)
        #expect(store.partialRegeneration != nil)
        store.cancelPartialRegeneration()
        await worker.fail(0)
        await task.value
    }
    @Test func invalidCutoffDoesNotStartOperation() async {
        let worker = SuspendedAnchoredGenerator()
        let store = Self.makeStore(worker: worker)
        let before = store.plan
        await store.regenerateActivePathway(after: .init(year: 2040, term: .fall))
        #expect(store.partialRegeneration == nil && store.canEditSchedule)
        #expect(store.plan == before)
        #expect(store.errorMessage != nil)
    }
}
