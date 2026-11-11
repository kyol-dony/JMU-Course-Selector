import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Bundled AP credit rules")
struct APCreditRuleSeedTests {
    @MainActor
    @Test("no AP rule awards the same course twice")
    func noRuleAwardsDuplicateCourseIDs() throws {
        let rules = try CatalogRepository().loadBundledCatalog().apCreditRules
        #expect(!rules.isEmpty)

        for rule in rules {
            let ids = rule.awardedCourseIDs
            #expect(Set(ids).count == ids.count, "\(rule.sourceNote) awards \(ids)")
        }
    }
}
