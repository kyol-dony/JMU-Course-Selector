import Foundation
import PlannerCore

struct PartialRegenerationRequest: Sendable {
    let catalog: Catalog
    let source: Pathway
    let cutoff: SemesterIdentity
    let programID: String
    let concentrationID: String?
    let strategy: ScheduleGenerationStrategy
    let workload: WorkloadPreference
    let transferCredits: [TransferCredit]
    let additionalPrograms: [Program]
    let earnedHoursAtStart: Double?
    var languagePlan: ForeignLanguagePlan? = nil
    /// The student's picks for "choose one of the following options" requirements.
    var optionChoices: [String: String] = [:]
}

struct PartialRegenerationState: Equatable, Sendable {
    let operationID: UUID
    let pathwayID: String
    let cutoff: SemesterIdentity
    var progress: ScheduleGenerationProgress
}
