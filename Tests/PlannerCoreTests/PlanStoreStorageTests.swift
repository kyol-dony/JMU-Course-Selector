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

    @Test func newestWorkspaceRestoresRegardlessOfDisplayName() {
        var older = SavedStudentPlan(name: "Autosave")
        older.updatedAt = Date(timeIntervalSince1970: 1)
        var newer = SavedStudentPlan(name: "Computer Science, B.S.")
        newer.updatedAt = Date(timeIntervalSince1970: 2)

        #expect(PlanStore.activeWorkspace(from: [older, newer])?.id == newer.id)
    }

    @Test func autosaveSetupFailureIsVisible() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("not a directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PlanStore(storageDirectory: root)

        store.startFresh()

        #expect(store.errorMessage?.hasPrefix("Autosave failed:") == true)
    }
}
