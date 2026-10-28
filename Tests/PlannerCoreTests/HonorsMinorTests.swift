import Foundation
import Testing
@testable import PlannerCore

@Suite struct HonorsMinorTests {
    @Test func approvedListsAreMenusAndScholarPathsAreOptional() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("_live_honors.html")
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(
            try String(contentsOf: file, encoding: .utf8), kind: .minor,
            sourceURL: URL(string: "https://catalog.jmu.edu/programs/honors-interdisciplinary-studies-minor/")!
        )
        #expect(parsed.requirements.count == 4)
        #expect(parsed.requirements.reduce(0) { $0 + $1.requiredCredits } == 19)
        #expect(parsed.totalCredits == 19)
        #expect(!parsed.concentrationSelectionRequired)
        #expect(parsed.concentrations.count == 2)
        for path in parsed.concentrations {
            #expect(path.requirements.reduce(0) { $0 + $1.requiredCredits } == 6)
        }
        for name in ["Civic, Cultural or Global Engagement Course", "Research or Experiential Learning Course"] {
            let category = try #require(parsed.requirements.first { $0.name == name })
            #expect(category.requiredCredits == 3)
            #expect(category.courseOptions.count == 1)
            #expect(category.courseOptions.first!.count > 50)
            #expect(category.selection == .chooseCredits(3))
        }
        #expect(!parsed.requirements.contains { $0.name.contains("Non-Minor") })
    }
}
