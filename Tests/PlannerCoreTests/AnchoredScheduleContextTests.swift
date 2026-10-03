import Testing
@testable import PlannerCore

@Suite struct AnchoredScheduleContextTests {
    @Test func includesSelectedSemesterAndPreservesMetadata() throws {
        let source = AnchoredRegenerationFixtures.pathway()
        let context = try AnchoredScheduleContext(source: source, through: .init(year: 2027, term: .spring))
        #expect(context.semesters == Array(source.semesters.prefix(2)))
        #expect(context.startingSemester == .init(year: 2027, term: .fall))
        #expect(context.standingSemesterOffset == 2)
        #expect(context.preferenceSemesterOffset == 2)
        #expect(context.completedCourseIDs == ["ZZZ123", "CS149"])
        #expect(context.reservedPlaceholderIDs == ["__pl::choice::0", "__pl::choice::1"])
        #expect(context.placeholders.count == 2)
    }
    @Test func resolutionsBelongToAnchors() throws {
        var source = AnchoredRegenerationFixtures.pathway()
        source.semesters[1].id = .init(year: 2028, term: .spring)
        source.semesters[2].id = .init(year: 2028, term: .fall)
        let context = try AnchoredScheduleContext(source: source, through: source.semesters[1].id)
        #expect(context.resolvedPlaceholders == ["__pl::choice::1": "CS149"])
        #expect(context.preferenceSemesterOffset == 4)
        #expect(context.standingSemesterOffset == 2)
        #expect(context.semesters[0].creditOverrides["ZZZ123"] == 1.5)
        #expect(context.semesters[0].courseTitles["ZZZ123"] == "Independent study")
    }
    @Test func invalidCutoffThrows() {
        #expect(throws: AnchoredRegenerationError.invalidCutoff) {
            try AnchoredScheduleContext(source: AnchoredRegenerationFixtures.pathway(), through: .init(year: 2029, term: .fall))
        }
    }
    @Test func strategyResolution() {
        #expect(ScheduleGenerationStrategy.resolve(pathwayID: "path-2", index: 0) == .majorFirst)
        #expect(ScheduleGenerationStrategy.resolve(pathwayID: "path-3", index: 0) == .genEdFirst)
        #expect(ScheduleGenerationStrategy.resolve(pathwayID: "custom", index: 2) == .genEdFirst)
        #expect(ScheduleGenerationStrategy.resolve(pathwayID: "custom", index: 20) == .balanced)
    }
}
