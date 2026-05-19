import Foundation
import PlannerCore

struct SavedStudentPlan: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var programID: String?
    var minorProgramIDs: [String]
    var workload: WorkloadPreference
    var apScores: [APScore]
    var transferCredits: [TransferCredit]
    var pathways: [Pathway]
    var activePathwayID: String?
    var overrides: [ConflictOverride]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "My JMU Plan",
        programID: String? = nil,
        minorProgramIDs: [String] = [],
        workload: WorkloadPreference = .standard,
        apScores: [APScore] = [],
        transferCredits: [TransferCredit] = [],
        pathways: [Pathway] = [],
        activePathwayID: String? = nil,
        overrides: [ConflictOverride] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.programID = programID
        self.minorProgramIDs = minorProgramIDs
        self.workload = workload
        self.apScores = apScores
        self.transferCredits = transferCredits
        self.pathways = pathways
        self.activePathwayID = activePathwayID
        self.overrides = overrides
        self.updatedAt = updatedAt
    }
}
