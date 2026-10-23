import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

/// Regenerating part of a B.A. plan that has no language answer asks for the
/// language only, then runs the regeneration the student asked for.
@Suite @MainActor struct DegreeLanguagePromptTests {
    @Test func regenerationAsksForLanguageThenResumes() async throws {
        let worker = SuspendedAnchoredGenerator()
        let store = PlanStorePartialRegenerationTests.makeStore(worker: worker)
        var catalog = try #require(store.catalog)
        catalog.programs = catalog.programs.map { program in
            var program = program
            if program.id == "cs" { program.degreeRequirements = [DegreeRequirement(kind: .foreignLanguage, creditsText: "0-12")] }
            return program
        }
        store.catalog = catalog
        let before = store.plan

        await store.regenerateActivePathway(after: PlanStorePartialRegenerationTests.fall)
        #expect(store.pendingLanguageAction == .regenerate(after: PlanStorePartialRegenerationTests.fall))
        #expect(store.setupSheetPresented && store.setupResumeStep == .language)
        #expect(store.plan == before)

        store.setupSheetPresented = false
        store.setForeignLanguage(ForeignLanguagePlan(subject: "SPAN", placement: .notSure))
        let task = Task { await store.continueAfterLanguageAnswer() }
        await worker.waitForCalls(1)
        #expect(await worker.request(0).languagePlan == ForeignLanguagePlan(subject: "SPAN", placement: .notSure))
        #expect(await worker.request(0).cutoff == PlanStorePartialRegenerationTests.fall)
        let source = try #require(store.activePathway)
        await worker.succeed(0, with: PlanStorePartialRegenerationTests.replacement(source))
        await task.value
        #expect(store.pendingLanguageAction == nil)
        #expect(store.plan.pathways.map(\.id) == before.pathways.map(\.id))
        #expect(store.plan.pathways.first { $0.id == "path-3" } == before.pathways.first { $0.id == "path-3" })
    }
}
