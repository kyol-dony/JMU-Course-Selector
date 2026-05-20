import Foundation
import PlannerCore

/// One minor (or second major) the student wants tracked alongside the
/// primary program, optionally paired with the concentration / option
/// pathway the student picked for that minor.
struct MinorSelection: Codable, Hashable, Identifiable {
    var programID: String
    var concentrationID: String?

    var id: String { programID }

    init(programID: String, concentrationID: String? = nil) {
        self.programID = programID
        self.concentrationID = concentrationID
    }
}

struct SavedStudentPlan: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var programID: String?
    var concentrationID: String?
    var minors: [MinorSelection]
    var workload: WorkloadPreference
    var apScores: [APScore]
    var transferCredits: [TransferCredit]
    var pathways: [Pathway]
    var activePathwayID: String?
    var overrides: [ConflictOverride]
    var requirementSelections: [String: [String]]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "My JMU Plan",
        programID: String? = nil,
        concentrationID: String? = nil,
        minors: [MinorSelection] = [],
        workload: WorkloadPreference = .standard,
        apScores: [APScore] = [],
        transferCredits: [TransferCredit] = [],
        pathways: [Pathway] = [],
        activePathwayID: String? = nil,
        overrides: [ConflictOverride] = [],
        requirementSelections: [String: [String]] = [:],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.programID = programID
        self.concentrationID = concentrationID
        self.minors = minors
        self.workload = workload
        self.apScores = apScores
        self.transferCredits = transferCredits
        self.pathways = pathways
        self.activePathwayID = activePathwayID
        self.overrides = overrides
        self.requirementSelections = requirementSelections
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, programID, concentrationID, minors, minorProgramIDs
        case workload, apScores, transferCredits, pathways, activePathwayID, overrides, requirementSelections, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.programID = try container.decodeIfPresent(String.self, forKey: .programID)
        self.concentrationID = try container.decodeIfPresent(String.self, forKey: .concentrationID)
        // Migration: prefer the new `minors` key, fall back to the legacy
        // `minorProgramIDs` flat array so saved plans from older builds keep
        // loading. Concentration is nil for legacy rows; user can pick later
        // from the Setup sheet.
        if let modern = try container.decodeIfPresent([MinorSelection].self, forKey: .minors) {
            self.minors = modern
        } else if let legacy = try container.decodeIfPresent([String].self, forKey: .minorProgramIDs) {
            self.minors = legacy.map { MinorSelection(programID: $0) }
        } else {
            self.minors = []
        }
        self.workload = try container.decode(WorkloadPreference.self, forKey: .workload)
        self.apScores = try container.decode([APScore].self, forKey: .apScores)
        self.transferCredits = try container.decode([TransferCredit].self, forKey: .transferCredits)
        self.pathways = try container.decode([Pathway].self, forKey: .pathways)
        self.activePathwayID = try container.decodeIfPresent(String.self, forKey: .activePathwayID)
        self.overrides = try container.decode([ConflictOverride].self, forKey: .overrides)
        self.requirementSelections = try container.decodeIfPresent([String: [String]].self, forKey: .requirementSelections) ?? [:]
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(programID, forKey: .programID)
        try container.encodeIfPresent(concentrationID, forKey: .concentrationID)
        try container.encode(minors, forKey: .minors)
        try container.encode(workload, forKey: .workload)
        try container.encode(apScores, forKey: .apScores)
        try container.encode(transferCredits, forKey: .transferCredits)
        try container.encode(pathways, forKey: .pathways)
        try container.encodeIfPresent(activePathwayID, forKey: .activePathwayID)
        try container.encode(overrides, forKey: .overrides)
        try container.encode(requirementSelections, forKey: .requirementSelections)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
