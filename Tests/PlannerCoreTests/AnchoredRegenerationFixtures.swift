import PlannerCore

enum AnchoredRegenerationFixtures {
    static func prerequisiteCatalog() -> Catalog { TranscriptTestFixtures.prerequisiteCatalog() }
    static func degreeCatalog() -> Catalog { TranscriptTestFixtures.degreeCatalog() }
    static func pathway(id: String = "path-1") -> Pathway {
        Pathway(id: id, name: "My balanced plan", semesters: [
            .init(id: .init(year: 2026, term: .fall), courseIDs: ["ZZZ123", "__pl::choice::0", "CS149"],
                  creditOverrides: ["ZZZ123": 1.5], courseTitles: ["ZZZ123": "Independent study"]),
            .init(id: .init(year: 2027, term: .spring), courseIDs: []),
            .init(id: .init(year: 2027, term: .fall), courseIDs: ["CS159", "__pl::suffix::0"])
        ], placeholders: [
            "__pl::choice::0": .init(categoryID: "choice", categoryName: "Choice", alternates: ["CS149", "CS159"], credits: 3),
            "__pl::choice::1": .init(categoryID: "choice", categoryName: "Choice", alternates: ["CS149", "CS159"], credits: 3),
            "__pl::suffix::0": .init(categoryID: "suffix", categoryName: "Suffix", alternates: ["CS159"], credits: 3)
        ], resolvedPlaceholders: ["__pl::choice::1": "CS149", "__pl::suffix::1": "CS159"])
    }
}
