import Testing
@testable import JMUCoursePlanner

@Suite("Course classification palette")
struct CourseClassificationPaletteTests {
    @Test("extracts leading subject classification from a course code")
    func extractsClassification() {
        #expect(CourseClassificationPalette.classification(forCode: "CIS 221") == "CIS")
        #expect(CourseClassificationPalette.classification(forCode: "BUS160") == "BUS")
        #expect(CourseClassificationPalette.classification(forCode: "MATH-235") == "MATH")
    }

    @Test("assigns distinct palette slots to classifications in one schedule")
    func assignsDistinctSlots() {
        let mapping = CourseClassificationPalette.slotMap(for: ["CIS", "BUS", "MATH", "WRTC"])

        #expect(Set(mapping.values).count == 4)
        #expect(mapping["BUS"] != mapping["CIS"])
    }
}
