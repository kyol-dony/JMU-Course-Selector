import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

/// Art B.A. and Art B.F.A. pages captured from the 2026-2027 catalog.
@Suite("Art program parsing")
struct ArtProgramParsingTests {
    @Test @MainActor func cachedArtBSAllowsBaseDegreeAndRetainsOptionalConcentration() throws {
        let core = RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["ART100"]])
        let education = RequirementCategory(id: "education", name: "Education", requiredCredits: 3, courseOptions: [["ARED300"]])
        let track = Concentration(id: "art-education", name: "Art Education", requirements: [education])
        var bs = Program.fixture(id: "art-bs", title: "Art, B.S.", requirements: [core], concentrations: [track])
        bs.concentrationSelectionRequired = true // Legacy cached value.
        var bfa = bs
        bfa.id = "art-bfa"
        var catalog = Catalog.fixture(courses: [
            Course(id: "ART100", code: "ART 100", title: "Art", credits: 3, availability: nil, prerequisites: []),
            Course(id: "ARED300", code: "ARED 300", title: "Education", credits: 3, availability: nil, prerequisites: [])
        ], program: bs)
        catalog.programs.append(bfa)
        catalog = ArtConcentrationPolicy.applying(to: catalog)
        let corrected = try #require(catalog.programsByID["art-bs"])
        #expect(!corrected.concentrationSelectionRequired)
        #expect(corrected.concentrations == [track])
        #expect(catalog.programsByID["art-bfa"]?.concentrationSelectionRequired == true)
        let store = PlanStore.temporary()
        store.catalog = catalog
        store.selectProgram(corrected)
        #expect(store.majorSelectionComplete)
        #expect(!store.requiresConcentrationSelection)
        let base = try corrected.effectiveProgram(concentrationID: nil)
        #expect(base.requirements == [core])
        #expect(try corrected.effectiveProgram(concentrationID: track.id).requirements.contains(education))
        let paths = try ScheduleGenerator(catalog: catalog).generatePathways(for: corrected.id, workload: .standard, transferCredits: [])
        #expect(paths.count == 3)
        #expect(paths.allSatisfy { !$0.semesters.flatMap(\.courseIDs).contains("ARED300") })
    }

    private static func parse(_ file: String, slug: String, kind: ProgramKind = .major) throws -> HTMLProgramRequirements {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(file)
        return JMUHTMLCatalogParser().parseProgramRequirements(
            try String(contentsOf: url, encoding: .utf8), kind: kind,
            sourceURL: URL(string: "https://catalog.jmu.edu/programs/\(slug)/")!
        )
    }

    private static func requirement(_ name: String, in parsed: HTMLProgramRequirements) throws -> RequirementCategory {
        try #require(parsed.requirements.first { $0.name == name }, "\(name) missing")
    }

    private static func program(_ parsed: HTMLProgramRequirements, id: String) -> Program {
        var program = Program.fixture(id: id, title: parsed.title ?? id, requirements: parsed.requirements, concentrations: parsed.concentrations)
        program.concentrationSelectionRequired = parsed.concentrationSelectionRequired
        program.totalCredits = parsed.totalCredits
        return program
    }

    private static func artCatalog(resolved: Bool = true) throws -> Catalog {
        let ba = try Self.parse("_live_art_ba.html", slug: "art-ba")
        let bfa = try Self.parse("_live_art_bfa.html", slug: "art-bfa")
        var coursesByID: [String: Course] = [:]
        for course in ba.courses + bfa.courses { coursesByID[course.id] = course }
        var catalog = Catalog.fixture(courses: Array(coursesByID.values), program: program(ba, id: "art-ba"))
        catalog.programs.append(program(bfa, id: "art-bfa"))
        catalog = ArtConcentrationPolicy.applying(to: catalog)
        return resolved ? catalog.resolvingElectivePools() : catalog
    }

    @Test func degreeTotalIgnoresItsFootnoteMark() throws {
        // "Total<sup>3</sup> 120" read as 3 credits before.
        #expect(try Self.parse("_live_art_ba.html", slug: "art-ba").totalCredits == 120)
        #expect(try Self.parse("_live_art_bfa.html", slug: "art-bfa").totalCredits == 120)
    }

    @Test func artEducationIsOptionalForTheBAButAStudioAreaIsRequiredForTheBFA() throws {
        let ba = try Self.parse("_live_art_ba.html", slug: "art-ba")
        #expect(ba.concentrations.map(\.name) == ["Art Education"])
        #expect(!ba.concentrationSelectionRequired)
        #expect(try Self.parse("_live_art_bfa.html", slug: "art-bfa").concentrationSelectionRequired)
    }

    @Test func studioConcentrationsTakeTwelveCreditsFromTheirLists() throws {
        let bfa = try Self.parse("_live_art_bfa.html", slug: "art-bfa")
        for name in ["Ceramics", "Fibers", "Metals", "Painting", "Printmaking", "Sculpture", "Photography"] {
            let concentration = try #require(bfa.concentrations.first { $0.name == name })
            #expect(concentration.requirements.reduce(0) { $0 + $1.requiredCredits } == 12, "\(name)")
        }
        let painting = try #require(bfa.concentrations.first { $0.name == "Painting" }?.requirements.first)
        #expect(painting.selection == .chooseCredits(12))
        #expect(Set(painting.courseOptions.flatMap { $0 }) == ["ART352", "ART452", "ART459"])
        // Art Education is not one of the listed studio media.
        let education = try #require(bfa.concentrations.first { $0.name == "Art Education" })
        #expect(education.requirements.reduce(0) { $0 + $1.requiredCredits } == 42)
    }

    @Test func photographyChooseThreeIsNineNamedCredits() throws {
        let photography = try #require(try Self.parse("_live_art_bfa.html", slug: "art-bfa").concentrations.first { $0.name == "Photography" })
        let choose = try #require(photography.requirements.first { $0.selection == .chooseCourses(3) })
        // The row's hours read "3-9".
        #expect(choose.requiredCredits == 9)
        #expect(choose.name == "Photography Concentration: Choose three of the following")
        #expect(choose.courseOptions.count == 3)
    }

    @Test func studioAndArtHistoryElectivesBecomePools() throws {
        let ba = try Self.parse("_live_art_ba.html", slug: "art-ba")
        let studio = try Self.requirement("Studio Art Electives", in: ba)
        #expect(studio.courseOptions.count == 6)
        #expect(studio.courseOptions[0] == [
            ElectivePool.token(subject: "ART", minimumNumber: 100, excluding: ["ART200", "ART105", "ART304", "ART305", "ART405", "ART491", "ART493", "ART496"]),
            ElectivePool.token(subject: "FDS", minimumNumber: 100)
        ])
        let emphasis = try Self.requirement("Studio Art Emphasis", in: ba)
        #expect(emphasis.requiredCredits == 6)
        #expect(emphasis.courseOptions == Array(repeating: [ElectivePool.token(subject: "ART", minimumNumber: 300)], count: 2))
        let history = try Self.requirement("Art History Elective", in: ba)
        #expect(history.courseOptions == [[ElectivePool.token(subject: "ARTH", minimumNumber: 300, excluding: ["ARTH397", "ARTH490", "ARTH495", "ARTH497", "ARTH499"])]])

        let bfaHistory = try Self.requirement("Art History Electives (300-400 Level)", in: try Self.parse("_live_art_bfa.html", slug: "art-bfa"))
        #expect(bfaHistory.courseOptions.count == 2)
        #expect(bfaHistory.electivePoolSlots == [0, 1])
    }

    @Test func bfaArtRelatedElectivesExposeFiveCatalogSubjectAreas() throws {
        let catalog = try Self.artCatalog(resolved: false)
        let bfa = try #require(catalog.programsByID["art-bfa"])
        let electives = try #require(bfa.requirements.first { $0.name == "Art and Art-Related Electives" })
        #expect(electives.requiredCredits == 15)
        #expect(electives.courseOptions.count == 5)
        #expect(electives.electivePoolSlots == [0, 1, 2, 3, 4])
        #expect(electives.courseOptions[0] == ["ART", "GRPH", "ARCD", "ARED", "INDU"].map {
            ElectivePool.token(subject: $0, minimumNumber: 100)
        })
        #expect(electives.courseOptions.allSatisfy { $0 == electives.courseOptions[0] })
    }

    @Test func bfaArtEducationAddsToEveryStudioArea() throws {
        let bfa = try #require(try Self.artCatalog().programsByID["art-bfa"])
        #expect(bfa.concentrationSelectionRequired)
        #expect(!bfa.concentrations.contains { $0.name == "Art Education" })
        #expect(bfa.concentrations.filter { Self.studioNames.contains($0.name) }.count == 7)
        let combined = bfa.concentrations.filter { $0.name.hasSuffix(" + Art Education") }
        #expect(combined.count == 7)
        let ceramics = try #require(combined.first { $0.name == "Ceramics + Art Education" })
        let ids = Set(ceramics.requirements.flatMap { $0.courseOptions.flatMap { $0 } })
        #expect(ids.contains("ART320"))
        #expect(ids.contains("ARED300"))
        #expect(ceramics.requirements.reduce(0) { $0 + $1.requiredCredits } == 54)
        #expect(ceramics.totalCredits == 143)
        #expect(try bfa.effectiveProgram(concentrationID: ceramics.id).totalCredits == 143)
    }

    @Test func studioArtEmphasisRequiresOneNamedArea() throws {
        let catalog = try Self.artCatalog()
        let ba = try #require(catalog.programsByID["art-ba"])
        let emphasis = try #require(ba.requirements.first { $0.name == "Studio Art Emphasis" })
        let options = try #require(emphasis.options)
        #expect(emphasis.selection == .chooseGroups(1))
        #expect(emphasis.courseOptions.isEmpty)
        #expect(options.map(\.label) == Self.studioNames)
        for option in options {
            let part = try #require(option.parts.first)
            #expect(part.requiredCredits == 6)
            #expect(part.courseOptions.count == 2)
            #expect(part.courseOptions.flatMap { $0 }.allSatisfy { id in
                guard let course = catalog.coursesByID[id],
                      let parsed = ElectivePool.subjectAndNumber(of: course.code)
                else { return false }
                return parsed.subject == "ART" && (300...499).contains(parsed.number)
            })
        }
        let ceramics = try #require(options.first { $0.label == "Ceramics" }?.parts.first)
        let painting = try #require(options.first { $0.label == "Painting" }?.parts.first)
        #expect(Set(ceramics.courseOptions[0]).isDisjoint(with: painting.courseOptions[0]))
    }

    @Test func psychologyElectiveRemainsVisibleAndAdvisorOnly() throws {
        let parsed = try Self.parse("_live_psyc_bs.html", slug: "psychology-bs")
        let elective = try Self.requirement("Psychology Electives", in: parsed)
        #expect(elective.requiredCredits == 3)
        #expect(elective.courseOptions.isEmpty)
        #expect(elective.approval == .psychologyElective)

        var raw = elective
        raw.approval = nil
        let program = Program.fixture(id: PsychologyCoursework.programID, title: "Psychology", requirements: [raw])
        let cached = PsychologyCoursework.applying(to: Catalog.fixture(courses: [], program: program))
        #expect(cached.programsByID[PsychologyCoursework.programID]?.requirements.first?.approval == .psychologyElective)
    }

    private static let studioNames = [
        "Ceramics", "Fibers", "Metals", "Painting", "Photography", "Printmaking", "Sculpture"
    ]

    @Test func overlappingArtCoursesCannotClaimCompletionBeforeAllocationReview() throws {
        let catalog = try Self.artCatalog()
        for programID in ["art-ba", "art-bfa"] {
            let program = try #require(catalog.programsByID[programID])
            let concentration = programID == "art-bfa" ? "painting-art-education" : nil
            let allCourses = catalog.courses.map(\.id)
            let pathway = Pathway(id: "all", name: "All eligible courses", semesters: [
                SemesterPlan(id: .init(year: 2026, term: .fall), courseIDs: allCourses)
            ])
            let progress = try ProgressCalculator(catalog: catalog).progress(
                programID: program.id, concentrationID: concentration,
                pathway: pathway, transferCredits: []
            )
            let name = programID == "art-ba" ? "Studio Art Emphasis" : "Art and Art-Related Electives"
            let row = try #require(progress.categories.first { $0.name.hasPrefix(name) })
            #expect(row.name.contains("allocation review pending"))
            #expect(row.completedCredits == 0)
            #expect(progress.overallFraction < 1)
            let extra = try program.effectiveProgram(concentrationID: concentration)
            let stacked = try ProgressCalculator(catalog: catalog).progress(
                programID: program.id, concentrationID: concentration,
                pathway: Pathway(id: "empty", name: "Transferred", semesters: []),
                transferCredits: allCourses.map { TransferCredit(sourceDescription: $0, courseIDs: [$0], credits: 3) },
                additionalPrograms: [extra]
            )
            #expect(stacked.categories.filter { $0.name.contains("allocation review pending") }.allSatisfy { $0.completedCredits == 0 })
        }
        let encoded = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(Catalog.self, from: encoded)
        #expect(decoded.programsByID["art-bfa"]?.requirements.first { $0.name == "Art and Art-Related Electives" }?.allocationReview != nil)
    }

    @Test @MainActor func legacyArtEducationPlanRequestsStudioWithoutDiscardingSchedule() throws {
        let store = PlanStore.temporary()
        store.catalog = try Self.artCatalog()
        store.plan.programID = "art-bfa"
        store.plan.concentrationID = "art-education"
        let pathway = Pathway(id: "saved", name: "Saved schedule", semesters: [
            SemesterPlan(id: .init(year: 2026, term: .fall), courseIDs: ["ARED300"])
        ])
        store.plan.pathways = [pathway]
        store.plan.activePathwayID = pathway.id
        store.reconcilePlanWithCatalog()
        #expect(store.plan.pathways == [pathway])
        #expect(store.plan.activePathwayID == pathway.id)
        #expect(!store.majorSelectionComplete)
        #expect(store.setupSheetPresented)
        #expect(store.errorMessage?.contains("studio area") == true)
    }

    @Test func artHistoryMinorRowBecomesAPool() throws {
        let text = "Required Courses: Art history courses (300-400 level) Art history courses (300-400 level) For studio art, graphic design and architectural design majors, required ARTH courses in the art emphasis program may count toward the art history minor. Excludes ARTH 390 , ARTH 490 , ARTH 495 and ARTH 499 ."
        let pool = try #require(JMUHTMLCatalogParser.levelOrPrefixPool(in: text, subjects: ["ARTH"]))
        #expect(pool.tokens == [ElectivePool.token(subject: "ARTH", minimumNumber: 300, excluding: ["ARTH390", "ARTH490", "ARTH495", "ARTH499"])])
        // No level and no prefix: left for an advisor.
        #expect(JMUHTMLCatalogParser.levelOrPrefixPool(in: "Complete 3 credit hours of psychology electives", subjects: ["PSYC"]) == nil)
    }
}
