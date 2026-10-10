import Foundation
import Testing
@testable import PlannerCore

@Suite("Placeholder prerequisite warnings")
struct PlaceholderConflictTests {
    typealias F = PlaceholderPrerequisiteFixtures

    private func warnings(_ pathway: Pathway, catalog: Catalog, overrides: [ConflictOverride] = [], analysis: PlaceholderPrerequisiteAnalysis? = nil) -> [ConflictWarning] {
        ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: overrides, prerequisiteAnalysis: analysis)
    }

    /// The pathway with slot 0 replaced by `course`, as choosing it does.
    private func resolving(_ pathway: Pathway, with course: String) -> Pathway {
        var resolved = pathway
        for index in resolved.semesters.indices {
            resolved.semesters[index].courseIDs = resolved.semesters[index].courseIDs.map { $0 == F.slotID(0) ? course : $0 }
        }
        resolved.resolvedPlaceholders[F.slotID(0)] = course
        return resolved
    }

    @Test func feasibleEarlierSlotShowsAPendingNoticeInsteadOfAConflict() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let warnings = ConflictDetector(catalog: f.catalog).warnings(for: f.input.pathway, overrides: [])
        let notice = try #require(warnings.first { $0.courseID == F.slotID(0) && $0.kind == .pendingPrerequisiteChoice })
        #expect(notice.semester == F.fall)
        #expect(notice.summary == "Prerequisite choice needed")
        #expect(notice.kind.title == "Prerequisite choice needed")
        #expect(notice.kind.severity == .worthALook)
        #expect(notice.detail == "Choose MATH 300 here to support MATH 410 in Spring 2027.")
        #expect(!warnings.contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
        #expect(f.input.pathway.resolvedPlaceholders.isEmpty)
    }

    @Test func pendingNoticeCannotBeKept() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let override = ConflictOverride(courseID: F.slotID(0), semester: F.fall, kind: .pendingPrerequisiteChoice)
        let notice = try #require(warnings(f.input.pathway, catalog: f.catalog, overrides: [override]).first { $0.kind == .pendingPrerequisiteChoice })
        #expect(!notice.isOverridden)
    }

    @Test func pendingSlotGrantsNoCompletion() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let progress = try ProgressCalculator(catalog: f.catalog).progress(programID: F.programID, pathway: f.input.pathway, transferCredits: [])
        #expect(progress.categories.first { $0.id == F.categoryID }?.completedCredits == 0)
    }

    @Test func incompatibleChoiceKeepsPlacementsAndRaisesTheOrdinaryConflict() {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let resolved = resolving(f.input.pathway, with: "B")
        let result = warnings(resolved, catalog: f.catalog)
        #expect(result.contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
        #expect(!result.contains { $0.kind == .pendingPrerequisiteChoice })
    }

    @Test func compatibleChoiceClearsTheNoticeAndTheConflict() {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let result = warnings(resolving(f.input.pathway, with: "A"), catalog: f.catalog)
        #expect(!result.contains { $0.kind == .pendingPrerequisiteChoice })
        #expect(!result.contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
    }

    @Test func oneSlotCannotCoverTwoChoices() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A"), .course("B")])
        let result = warnings(f.input.pathway, catalog: f.catalog)
        #expect(!result.contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
        #expect(result.contains { $0.courseID == "D1" && $0.kind == .missingPrerequisite })
        let notice = try #require(result.first { $0.kind == .pendingPrerequisiteChoice })
        #expect(notice.detail == "Choose MATH 300 here to support MATH 410 in Spring 2027.")
    }

    @Test func sameTermSlotDoesNotQuietThePrerequisite() {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")], slotSemesterOffset: 1, dependentSemesterOffset: 1)
        let result = warnings(f.input.pathway, catalog: f.catalog)
        #expect(result.contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
        #expect(!result.contains { $0.kind == .pendingPrerequisiteChoice })
    }

    @Test func unconfirmedAnalysisKeepsTheConflictAndSaysSo() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let analysis = PlaceholderPrerequisiteAnalysis(statusByDependency: [f.requests[0].key: .unconfirmed], supportsByPlaceholder: [:])
        let result = warnings(f.input.pathway, catalog: f.catalog, analysis: analysis)
        let conflict = try #require(result.first { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
        #expect(conflict.notes.contains { $0.contains("couldn't confirm") })
        #expect(!result.contains { $0.kind == .pendingPrerequisiteChoice })
    }

    @Test func pendingNoticeHasNoFixSuggestion() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let notice = try #require(warnings(f.input.pathway, catalog: f.catalog).first { $0.kind == .pendingPrerequisiteChoice })
        #expect(FixSuggester(catalog: f.catalog).suggestions(for: notice, verdicts: [:], in: f.input.pathway).isEmpty)
    }

    // MARK: Drag previews

    @Test func draggingTheSlotIntoItsDependentsTermBlocks() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let verdicts = DropVerdictCalculator(catalog: f.catalog).verdicts(moving: F.slotID(0), in: f.input.pathway, overrides: [])
        #expect(verdicts[F.fall] == .neutral)
        let later = try #require(verdicts[F.spring])
        #expect(later.level == .blocking)
        #expect(later.affectedCourseIDs == ["D0"])
        // The preview matches the warnings after the move.
        let moved = LabPairing(catalog: f.catalog).moving(F.slotID(0), to: F.spring, at: nil, in: f.input.pathway)
        #expect(warnings(moved, catalog: f.catalog).contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
    }

    @Test func draggingTheSlotEarlierRestoresSupport() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")], slotSemesterOffset: 1, dependentSemesterOffset: 1)
        let verdicts = DropVerdictCalculator(catalog: f.catalog).verdicts(moving: F.slotID(0), in: f.input.pathway, overrides: [])
        let earlier = try #require(verdicts[F.fall])
        #expect(earlier.fixedCount == 1)
        #expect(earlier.level == .caution)
        #expect(earlier.newWarnings.map(\.kind) == [.pendingPrerequisiteChoice])
    }
}
