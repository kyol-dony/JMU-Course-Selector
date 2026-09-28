import Foundation
import Testing
@testable import JMUCoursePlanner

@Suite("Pathway selector labels")
struct PathwayLabelTests {
    @Test("generated names shorten in steps: full, without Path, keyword", arguments: [
        ("Gen Ed-First Path", ["Gen Ed-First Path", "Gen Ed-First", "Gen Ed"]),
        ("Major-First Path", ["Major-First Path", "Major-First", "Major"]),
        ("Balanced Path", ["Balanced Path", "Balanced"])
    ])
    func generatedNames(name: String, expected: [String]) {
        #expect(PathwayLabel.levels(for: name) == expected)
    }

    @Test("names without the suffixes keep fewer steps")
    func otherNames() {
        #expect(PathwayLabel.levels(for: "Custom Plan") == ["Custom Plan"])
        #expect(PathwayLabel.levels(for: "Path to Graduation") == ["Path to Graduation"])
        #expect(PathwayLabel.levels(for: "Pathfinder") == ["Pathfinder"])
    }

    @Test("a step past a name's shortest form keeps the shortest form")
    func clampedLevel() {
        #expect(PathwayLabel.label(for: "Balanced Path", level: 0) == "Balanced Path")
        #expect(PathwayLabel.label(for: "Balanced Path", level: 2) == "Balanced")
        #expect(PathwayLabel.label(for: "Custom Plan", level: 1) == "Custom Plan")
    }
}
