import Foundation
@testable import JMUCoursePlanner

extension PlanStore {
    /// A store that saves plans to a fresh temporary directory. `PlanStore()`
    /// saves to the user's Application Support folder, so tests use this.
    static func temporary() -> PlanStore {
        PlanStore(storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
}
