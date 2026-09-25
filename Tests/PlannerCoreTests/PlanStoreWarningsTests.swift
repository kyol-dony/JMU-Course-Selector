import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Plan store warnings")
@MainActor
struct PlanStoreWarningsTests {
    static let fall26 = SemesterIdentity(year: 2026, term: .fall)
    static let spring27 = SemesterIdentity(year: 2027, term: .spring)
    static let fall27 = SemesterIdentity(year: 2027, term: .fall)

    func makeStore() -> PlanStore {
        let store = PlanStore()
        store.catalog = Catalog.fixture(
            courses: [
                Course(id: "MATH231", code: "MATH 231", title: "Calculus I", credits: 4, availability: [.fall, .spring], prerequisites: []),
                Course(id: "MATH232", code: "MATH 232", title: "Calculus II", credits: 4, availability: [.fall, .spring], prerequisites: ["MATH231"])
            ] + (1...5).map {
                Course(id: "F\($0)", code: "FILL \($0)", title: "Filler \($0)", credits: 3, availability: [.fall, .spring], prerequisites: [])
            },
            program: Program.fixture(id: "p", title: "P", requirements: [])
        )
        store.plan.pathways = [
            Pathway(id: "path", name: "Path", semesters: [
                SemesterPlan(id: Self.fall26, courseIDs: ["MATH232", "F1", "F2", "F3"]), // 13
                SemesterPlan(id: Self.spring27, courseIDs: ["MATH231", "F4", "F5"]),     // 10, final
                SemesterPlan(id: Self.fall27, courseIDs: [])
            ])
        ]
        store.plan.activePathwayID = "path"
        store.plan.workload = .standard
        return store
    }

    @Test("store warnings apply the student's workload")
    func workloadFlowsIntoWarnings() {
        let store = makeStore()
        #expect(!store.warnings.contains { $0.kind == .heavyLoad })
        store.setWorkload(.light) // 12...13 → heavy above 15
        store.plan.pathways[0].semesters[0].courseIDs.append("MATH231")
        store.plan.pathways[0].semesters[1].courseIDs.removeAll { $0 == "MATH231" }
        #expect(store.warnings.contains { $0.kind == .heavyLoad && $0.semester == Self.fall26 })
    }

    @Test("stop keeping restores an active warning")
    func removeOverrideRestores() throws {
        let store = makeStore()
        let warning = try #require(store.warnings.first { $0.kind == .missingPrerequisite })
        store.override(warning)
        #expect(store.warnings.first { $0.id == warning.id }?.isOverridden == true)
        store.removeOverride(warning)
        #expect(store.warnings.first { $0.id == warning.id }?.isOverridden == false)
        #expect(store.plan.overrides.isEmpty)
    }

    @Test("fix suggestions move the course past its prerequisite")
    func fixSuggestionsMove() async throws {
        let store = makeStore()
        let warning = try #require(store.warnings.first { $0.kind == .missingPrerequisite })
        let suggestions = await store.fixSuggestions(for: warning)
        #expect(suggestions == [.move(courseID: "MATH232", to: Self.fall27)])
    }

    @Test("no suggestions once the warning is gone")
    func fixSuggestionsAfterPlanChange() async throws {
        let store = makeStore()
        let warning = try #require(store.warnings.first { $0.kind == .missingPrerequisite })
        let request = Task { await store.fixSuggestions(for: warning) }
        store.moveCourse("MATH232", to: Self.fall27)
        #expect(await request.value.isEmpty)
    }
}
