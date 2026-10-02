import Testing
@testable import JMUCoursePlanner
import PlannerCore

@Suite("Gen Ed cluster credits")
@MainActor
struct GenEdClusterCreditTests {
    private let credits = CatalogRepository.genEdClusterCredits

    private func areaTotal(_ prefix: String) -> Int {
        credits.filter { $0.key.hasPrefix(prefix) }.values.reduce(0, +)
    }

    @Test("cluster credits add up to the catalog's 41-credit Gen Ed total")
    func totalMatchesCatalog() {
        #expect(credits.values.reduce(0, +) == 41)
    }

    @Test("each area matches the catalog's credit hours", arguments: [
        ("C1", 9),  // Madison Foundations
        ("C2", 9),  // Arts and Humanities
        ("C3", 10), // The Natural World
        ("C4", 7),  // American and Global Perspectives
        ("C5", 6)   // Sociocultural and Wellness
    ])
    func areaMatchesCatalog(prefix: String, expected: Int) {
        #expect(areaTotal(prefix) == expected)
    }

    @Test("Physical Principles takes three credits, like most of its courses")
    func physicalPrinciples() {
        #expect(credits["C3PP"] == 3)
    }
}

@Suite("Gen Ed credits on cached catalogs")
@MainActor
struct GenEdCachedCatalogCreditTests {
    @Test("a catalog cached with stale Gen Ed credits picks up the current table")
    func cachedCatalogUsesCurrentCredits() throws {
        let stale = Catalog.fixture(
            courses: [],
            program: Program.fixture(id: "p", title: "P", requirements: [
                RequirementCategory(id: "gened-c3pp", name: "General Education - Physical Principles [C3PP]", requiredCredits: 4, courseOptions: [["PHYS140", "PHYS121"]]),
                RequirementCategory(id: "core", name: "Core", requiredCredits: 4, courseOptions: [["CS149"]])
            ])
        )
        let updated = CatalogRepository.applyingCurrentGenEdCredits(to: stale)
        let requirements = try #require(updated.programsByID["p"]).requirements
        #expect(requirements.first { $0.id == "gened-c3pp" }?.requiredCredits == 3)
        #expect(requirements.first { $0.id == "core" }?.requiredCredits == 4)
    }
}
