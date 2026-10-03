import Testing
@testable import JMUCoursePlanner

@Suite struct SetupFlowTests {
    @Test func incomingAndConcentrationGate() {
        var flow = SetupFlow()
        #expect(flow.step == .year)
        flow.advance(majorSelectionComplete: true)
        #expect(flow.step == .year)
        flow.selectYear(.incomingFreshman)
        flow.advance(majorSelectionComplete: false)
        #expect(flow.step == .major)
        flow.advance(majorSelectionComplete: false)
        #expect(flow.step == .major)
        flow.advance(majorSelectionComplete: true)
        #expect(flow.step == .minor)
        flow.advance(majorSelectionComplete: true)
        #expect(flow.step == .transfer)
        flow.advance(majorSelectionComplete: true)
        #expect(flow.step == .workload)
    }
    @Test(arguments: StudentYear.allCases.filter { $0 != .incomingFreshman })
    func continuingRequiresReview(_ year: StudentYear) {
        var flow = SetupFlow()
        flow.selectYear(year)
        for _ in 0..<3 { flow.advance(majorSelectionComplete: true) }
        #expect(flow.step == .transcript)
        flow.skipUpload()
        #expect(flow.step == .review)
        flow.advance(majorSelectionComplete: true)
        #expect(flow.step == .review)
        flow.reviewConfirmed()
        #expect(flow.step == .workload)
        flow.back()
        #expect(flow.step == .review)
        flow.back()
        #expect(flow.step == .transcript)
    }
    @Test func jumpBackReturnsToVisitedStepAndTrimsHistory() {
        var flow = SetupFlow()
        flow.selectYear(.incomingFreshman)
        for _ in 0..<3 { flow.advance(majorSelectionComplete: true) }
        #expect(flow.step == .transfer)
        flow.jumpBack(to: .major)
        #expect(flow.step == .major)
        #expect(flow.visited == [.year])
        flow.jumpBack(to: .workload)
        #expect(flow.step == .major)
        flow.back()
        #expect(flow.step == .year)
        #expect(flow.visited.isEmpty)
    }
    @Test func stepPositionFollowsRoute() {
        var flow = SetupFlow()
        flow.selectYear(.junior)
        flow.advance(majorSelectionComplete: true)
        #expect(flow.position == 2)
        #expect(flow.route.count == 6)
    }
    @Test func startupPolicyDoesNotForceLegacyPlan() {
        #expect(SetupFlow.needsInitialSetup(plan: SavedStudentPlan()))
        #expect(!SetupFlow.needsInitialSetup(plan: SavedStudentPlan(programID: "cs")))
    }
}
