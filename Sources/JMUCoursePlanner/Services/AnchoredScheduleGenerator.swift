import Foundation
import PlannerCore

protocol AnchoredScheduleGenerating: Sendable {
    func regenerate(_ request: PartialRegenerationRequest,
                    progress: @escaping @Sendable (ScheduleGenerationProgress) -> Void) async throws -> Pathway
}

struct LocalAnchoredScheduleGenerator: AnchoredScheduleGenerating {
    func regenerate(_ request: PartialRegenerationRequest,
                    progress: @escaping @Sendable (ScheduleGenerationProgress) -> Void) async throws -> Pathway {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try ScheduleGenerator(catalog: request.catalog).regeneratePathway(
                from: request.source, through: request.cutoff, for: request.programID,
                concentrationID: request.concentrationID, strategy: request.strategy,
                workload: request.workload, transferCredits: request.transferCredits,
                additionalPrograms: request.additionalPrograms, earnedHoursAtStart: request.earnedHoursAtStart,
                languagePlan: request.languagePlan, optionChoices: request.optionChoices,
                progress: { current, total, name in progress(.init(current: current, total: total, pathwayName: name)) })
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }
}
