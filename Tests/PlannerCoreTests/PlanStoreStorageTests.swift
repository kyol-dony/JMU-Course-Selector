import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Plan store test storage")
@MainActor
struct PlanStoreStorageTests {
    @Test func temporaryStoreAutosavesIntoItsOwnDirectory() throws {
        let store = PlanStore.temporary()
        let directory = try #require(store.storageDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(directory.path.hasPrefix(FileManager.default.temporaryDirectory.path))

        store.startFresh()
        PlanStore.flushPendingAutosaves()

        let saved = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(saved == ["\(store.plan.id.uuidString).jmuplan.json"])
    }
}
