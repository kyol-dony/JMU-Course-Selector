import AppKit
import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Option choice in the plan")
@MainActor
struct OptionChoicePlanTests {
    static let req = "choose-one-of-the-following-options"
    static let majorID = "math-bs"
    static let minorID = "math-minor"
    static let fall26 = SemesterIdentity(year: 2026, term: .fall)
    static let spring27 = SemesterIdentity(year: 2027, term: .spring)
    static let fall27 = SemesterIdentity(year: 2027, term: .fall)
    static let electives = ["MATH310", "MATH450", "MATH499"]
    static let chooseTwo = ["MATH440", "MATH441", "MATH426", "MATH427"]

    /// Option 1: an elective slot and two required courses. Option 2: two
    /// elective slots, then "choose two" with an "or take both 426 and 427".
    static func optionRequirement(id: String = req) -> RequirementCategory {
        let option1 = RequirementOption(id: "option-1", label: "Option 1", parts: [
            RequirementCategory(id: "electives", name: "Electives", requiredCredits: 3, courseOptions: [electives], electivePoolSlots: [0]),
            RequirementCategory(id: "required-courses", name: "Required courses", requiredCredits: 6,
                                courseOptions: [["MATH411"], ["MATH431"]], selection: .allRequired)
        ])
        let option2 = RequirementOption(id: "option-2", label: "Option 2", parts: [
            RequirementCategory(id: "electives", name: "Electives", requiredCredits: 6, courseOptions: [electives, electives], electivePoolSlots: [0, 1]),
            RequirementCategory(id: "choose-two", name: "Choose two", requiredCredits: 6,
                                courseOptions: [["MATH440", "MATH441"], ["MATH440", "MATH441"]],
                                selection: .chooseCourses(2), alternativeGroup: ["MATH426", "MATH427"])
        ])
        return RequirementCategory(
            id: id, name: "Choose one of the following options", requiredCredits: 9,
            courseOptions: [electives, ["MATH411"], ["MATH431"]], selection: .allRequired,
            options: [option1, option2]
        )
    }

    static let core = RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["MATH235"]])

    static func major(withTrack: Bool = false) -> Program {
        withTrack
            ? Program.fixture(id: majorID, title: "Math", requirements: [core], concentrations: [
                Concentration(id: "not-seeking-licensure", name: "Not Seeking Licensure", requirements: [optionRequirement()]),
                Concentration(id: "seeking-licensure", name: "Seeking Licensure", requirements: [
                    RequirementCategory(id: "licensure", name: "Licensure", requiredCredits: 3, courseOptions: [["MATH480"]])
                ])
            ])
            : Program.fixture(id: majorID, title: "Math", requirements: [core, optionRequirement()])
    }

    static func minor() -> Program {
        Program(
            id: minorID, title: "Math Minor", degreeType: nil, kind: .minor, college: "X", department: "X", catalogPage: nil,
            totalCredits: nil, requirements: [optionRequirement(id: "r")], verificationStatus: .verified,
            requirementDataComplete: true, sourceNote: "Fixture"
        )
    }

    /// `labs`: MATH 431 needs its lab, MATH 431L.
    static func catalog(programs: [Program], labs: Bool = false) -> Catalog {
        let codes = ["MATH 235", "MATH 310", "MATH 411", "MATH 426", "MATH 427", "MATH 431", "MATH 440", "MATH 441",
                     "MATH 450", "MATH 480", "MATH 499"] + (labs ? ["MATH 431L"] : [])
        let coreqs = labs ? ["MATH 431": "Corequisites: MATH 431L .", "MATH 431L": "Corequisites: MATH 431 ."] : [:]
        return Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: Date(timeIntervalSince1970: 0), retrievedDate: Date(timeIntervalSince1970: 0), sourceURLs: [], retrievalNotes: []),
            programs: programs,
            courses: codes.map {
                Course(id: $0.replacingOccurrences(of: " ", with: ""), code: $0, title: $0, credits: $0.hasSuffix("L") ? 1 : 3,
                       availability: [.fall, .spring], prerequisites: [], rawPrerequisiteText: coreqs[$0])
            },
            apCreditRules: []
        )
    }

    static func key(_ programID: String = majorID, _ requirementID: String = req) -> String {
        RequirementOption.choiceKey(programID: programID, requirementID: requirementID)
    }

    static func slot(_ option: String, part: Int, _ index: Int, requirement: String = req) -> String {
        PathwayPlaceholder.id(categoryID: "\(requirement)--\(option)--\(part)", optionIndex: index)
    }

    static func makeStore(programs: [Program] = [major()], labs: Bool = false) -> PlanStore {
        let store = PlanStore(storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                              anchoredGenerator: LocalAnchoredScheduleGenerator())
        store.catalog = catalog(programs: programs, labs: labs)
        return store
    }

    // MARK: - Migration

    /// A plan saved when option 2 was the concentration "<track>-option-2"
    /// and its slots were "__pl::option-2::<k>".
    static func legacyPlan() -> SavedStudentPlan {
        let oldSlot = "__pl::option-2::2"
        let pathway = Pathway(id: "path-1", name: "Balanced", semesters: [
            SemesterPlan(id: fall26, courseIDs: ["MATH235", "__pl::option-2::0"]),
            SemesterPlan(id: spring27, courseIDs: ["MATH440", "__pl::option-2::3"])
        ], placeholders: [
            "__pl::option-2::0": PlaceholderSpec(categoryID: "option-2", categoryName: "Option 2", alternates: electives, credits: 3),
            "__pl::option-2::1": PlaceholderSpec(categoryID: "option-2", categoryName: "Option 2", alternates: electives, credits: 3),
            oldSlot: PlaceholderSpec(categoryID: "option-2", categoryName: "Option 2", alternates: ["MATH440", "MATH441"], credits: 3),
            "__pl::option-2::3": PlaceholderSpec(categoryID: "option-2", categoryName: "Option 2", alternates: ["MATH440", "MATH441"], credits: 3)
        ], resolvedPlaceholders: [oldSlot: "MATH440"])
        var plan = SavedStudentPlan(programID: majorID, concentrationID: "not-seeking-licensure-option-2", pathways: [pathway], activePathwayID: "path-1")
        plan.setupCompleted = true
        return plan
    }

    @Test func migrationKeepsOptionAndResolvedSlots() {
        let store = Self.makeStore(programs: [Self.major(withTrack: true)])
        store.resume(Self.legacyPlan())
        let plan = store.plan
        #expect(plan.concentrationID == "not-seeking-licensure")
        #expect(plan.optionChoices[Self.key()] == "option-2")
        let pathway = plan.pathways[0]
        #expect(pathway.semesters[1].courseIDs.contains("MATH440"))
        #expect(pathway.resolvedPlaceholders == [Self.slot("option-2", part: 1, 0): "MATH440"])
        #expect(pathway.semesters[0].courseIDs == ["MATH235", Self.slot("option-2", part: 0, 0)])
        #expect(pathway.semesters[1].courseIDs == ["MATH440", Self.slot("option-2", part: 1, 1)])
        #expect(Set(pathway.placeholders.keys) == [
            Self.slot("option-2", part: 0, 0), Self.slot("option-2", part: 0, 1),
            Self.slot("option-2", part: 1, 0), Self.slot("option-2", part: 1, 1)
        ])
        #expect(pathway.placeholders[Self.slot("option-2", part: 1, 0)]?.categoryID == "\(Self.req)--option-2--1")
    }

    @Test func migrationIsIdempotent() {
        let catalog = Self.catalog(programs: [Self.major(withTrack: true)])
        let once = OptionChoiceMigration.migrate(Self.legacyPlan(), catalog: catalog, completed: [])
        let twice = OptionChoiceMigration.migrate(once, catalog: catalog, completed: [])
        #expect(once == twice)
        #expect(once != Self.legacyPlan())
    }

    @Test func migrationMovesAMinorOffItsOptionConcentration() {
        let catalog = Self.catalog(programs: [Self.major(), Self.minor()])
        var plan = SavedStudentPlan(programID: Self.majorID, minors: [MinorSelection(programID: Self.minorID, concentrationID: "option-2")])
        plan = OptionChoiceMigration.migrate(plan, catalog: catalog, completed: [])
        #expect(plan.minors.first?.concentrationID == nil)
        #expect(plan.optionChoices[Self.key(Self.minorID, "r")] == "option-2")
    }

    // MARK: - Real catalog pages

    static let mathTrack = RealCatalogFixtures.mathTrack

    static func realProgram(_ file: String, id: String, kind: ProgramKind) throws -> Program {
        try RealCatalogFixtures.program(file, id: id, kind: kind)
    }

    static func realCatalog(_ programs: [Program]) -> Catalog {
        RealCatalogFixtures.catalog(programs)
    }

    static func realMathRequirement(_ math: Program) throws -> RequirementCategory {
        try RealCatalogFixtures.mathRequirement(math)
    }

    /// The real Math B.S. and Political Science minor pages, with plans
    /// saved under the old parse's "Option N" concentrations.
    @Test func migrationMovesRealCatalogPlans() throws {
        let math = try Self.realProgram("_live_math_bs.html", id: "math-bs", kind: .major)
        let posc = try Self.realProgram("_live_posc_minor.html", id: "posc-minor", kind: .minor)
        let catalog = Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: Date(timeIntervalSince1970: 0), retrievedDate: Date(timeIntervalSince1970: 0), sourceURLs: [], retrievalNotes: []),
            programs: [math, posc], courses: [], apCreditRules: []
        )
        let track = Self.mathTrack
        let mathRequirement = try #require(math.concentrations.first { $0.id == track }?.requirements.first { $0.options != nil })
        let poscRequirement = try #require(posc.requirements.first { $0.options != nil })
        let oldSlot = "__pl::option-2::0"
        var plan = SavedStudentPlan(
            programID: "math-bs", concentrationID: "\(track)-option-2",
            minors: [MinorSelection(programID: "posc-minor", concentrationID: "option-1")],
            pathways: [Pathway(id: "path-1", name: "Balanced", semesters: [SemesterPlan(id: Self.fall26, courseIDs: [oldSlot])],
                               placeholders: [oldSlot: PlaceholderSpec(categoryID: "option-2", categoryName: "Option 2", alternates: [], credits: 3)])]
        )
        plan = OptionChoiceMigration.migrate(plan, catalog: catalog, completed: [])
        #expect(plan.concentrationID == track)
        #expect(plan.optionChoices[Self.key("math-bs", mathRequirement.id)] == "option-2")
        #expect(plan.minors.first?.concentrationID == nil)
        #expect(plan.optionChoices[Self.key("posc-minor", poscRequirement.id)] == "option-1")
        let newSlot = Self.slot("option-2", part: 0, 0, requirement: mathRequirement.id)
        #expect(plan.pathways[0].semesters[0].courseIDs == [newSlot])
        #expect(plan.pathways[0].placeholders[newSlot]?.categoryID == "\(mathRequirement.id)--option-2--0")
    }

    /// The old Option 1 listed its "one of MATH 411/431/434/435" slot
    /// before its three elective slots; the new Option 1 has the elective
    /// part first. Slots follow their courses, not their position.
    @Test func migrationMapsRealOptionOneSlotsByContent() throws {
        let math = try Self.realProgram("_live_math_bs.html", id: "math-bs", kind: .major)
        let catalog = Self.realCatalog([math])
        let requirement = try Self.realMathRequirement(try #require(catalog.programsByID["math-bs"]))
        let pool = try #require(requirement.options?[0].parts[0].courseOptions.first)
        let oneOf = ["MATH411", "MATH431", "MATH434", "MATH435"]
        func old(_ k: Int) -> String { "__pl::option-1::\(k)" }
        func spec(_ alternates: [String]) -> PlaceholderSpec {
            PlaceholderSpec(categoryID: "option-1", categoryName: "Option 1", alternates: alternates, credits: 3)
        }
        var plan = SavedStudentPlan(
            programID: "math-bs", concentrationID: "\(Self.mathTrack)-option-1",
            pathways: [Pathway(id: "path-1", name: "Balanced", semesters: [
                SemesterPlan(id: Self.fall26, courseIDs: ["MATH411", old(1)]),
                SemesterPlan(id: Self.spring27, courseIDs: [old(2), old(3)])
            ], placeholders: [old(0): spec(oneOf), old(1): spec(pool), old(2): spec(pool), old(3): spec(pool)],
               resolvedPlaceholders: [old(0): "MATH411"])]
        )
        plan = OptionChoiceMigration.migrate(plan, catalog: catalog, completed: [])
        let pathway = plan.pathways[0]
        func new(_ part: Int, _ index: Int) -> String { Self.slot("option-1", part: part, index, requirement: requirement.id) }
        #expect(pathway.resolvedPlaceholders == [new(1, 0): "MATH411"])
        #expect(pathway.placeholders[new(1, 0)]?.categoryID == "\(requirement.id)--option-1--1")
        #expect(pathway.placeholders[new(1, 0)]?.alternates == oneOf)
        #expect(pathway.semesters[0].courseIDs == ["MATH411", new(0, 0)])
        #expect(pathway.semesters[1].courseIDs == [new(0, 1), new(0, 2)])
        for index in 0..<3 {
            #expect(pathway.placeholders[new(0, index)]?.categoryID == "\(requirement.id)--option-1--0")
        }
    }

    /// An upgrade first opens the plan on the bundled seed, whose Math B.S.
    /// has no requirements or concentrations, then on the refreshed catalog.
    /// The old "Option 2" concentration must survive the seed so the
    /// migration can carry it over once the real catalog arrives.
    @Test func legacyPlanSurvivesTheSeedBeforeTheRealCatalog() throws {
        let math = try Self.realProgram("_live_math_bs.html", id: "math-bs", kind: .major)
        let requirement = try Self.realMathRequirement(math)
        let seed = Program(
            id: "math-bs", title: "Mathematics, B.S.", degreeType: "B.S.", kind: .major, college: "X", department: "X",
            catalogPage: 332, totalCredits: nil, requirements: [], verificationStatus: .unverified,
            requirementDataComplete: false, sourceNote: "Seed"
        )
        let oldSlot = "__pl::option-2::2"
        var legacy = SavedStudentPlan(
            programID: "math-bs", concentrationID: "\(Self.mathTrack)-option-2",
            pathways: [Pathway(id: "path-1", name: "Balanced", semesters: [SemesterPlan(id: Self.fall26, courseIDs: ["MATH440"])],
                               placeholders: [oldSlot: PlaceholderSpec(categoryID: "option-2", categoryName: "Option 2",
                                                                       alternates: ["MATH440", "MATH441", "MATH448", "MATH449"], credits: 3)],
                               resolvedPlaceholders: [oldSlot: "MATH440"])],
            activePathwayID: "path-1"
        )
        legacy.setupCompleted = true

        let store = Self.makeStore(programs: [seed])
        store.resume(legacy)
        #expect(store.plan.concentrationID == "\(Self.mathTrack)-option-2")
        #expect(store.plan.pathways.count == 1)

        store.catalog = Self.realCatalog([math])
        store.reconcilePlanWithCatalog()
        #expect(store.plan.concentrationID == Self.mathTrack)
        #expect(store.plan.optionChoices[Self.key("math-bs", requirement.id)] == "option-2")
        #expect(store.plan.pathways.count == 1)
        #expect(store.plan.activePathwayID == "path-1")
        let newSlot = Self.slot("option-2", part: 1, 0, requirement: requirement.id)
        #expect(store.plan.pathways.first?.resolvedPlaceholders == [newSlot: "MATH440"])
    }

    @Test func migrationFillsTheDefaultFromCompletedCourses() {
        let catalog = Self.catalog(programs: [Self.major()])
        let fresh = OptionChoiceMigration.migrate(SavedStudentPlan(programID: Self.majorID), catalog: catalog, completed: [])
        #expect(fresh.optionChoices[Self.key()] == "option-1")
        let taken = OptionChoiceMigration.migrate(SavedStudentPlan(programID: Self.majorID), catalog: catalog, completed: ["MATH440"])
        #expect(taken.optionChoices[Self.key()] == "option-2")
    }

    /// A plan on the real Math B.S. track without a stored choice: completed
    /// MATH 426 and 427 pick Option 2 although both options' pools list
    /// them; with nothing completed, the courses its schedule holds decide.
    @Test func migrationDefaultFollowsTheRealCatalogsDistinctCourses() throws {
        let math = try Self.realProgram("_live_math_bs.html", id: "math-bs", kind: .major)
        let catalog = Self.realCatalog([math])
        let key = Self.key("math-bs", try Self.realMathRequirement(math).id)
        let plan = SavedStudentPlan(programID: "math-bs", concentrationID: Self.mathTrack)
        #expect(OptionChoiceMigration.migrate(plan, catalog: catalog, completed: ["MATH426", "MATH427"]).optionChoices[key] == "option-2")
        #expect(OptionChoiceMigration.migrate(plan, catalog: catalog, completed: []).optionChoices[key] == "option-1")
        var scheduled = plan
        scheduled.pathways = [Pathway(id: "path-1", name: "Balanced", semesters: [SemesterPlan(id: Self.fall26, courseIDs: ["MATH448", "MATH449"])])]
        #expect(OptionChoiceMigration.migrate(scheduled, catalog: catalog, completed: []).optionChoices[key] == "option-2")
    }

    @Test func savedPlansWithoutChoicesStillDecode() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try #require(try JSONSerialization.jsonObject(with: encoder.encode(SavedStudentPlan())) as? [String: Any])
        json.removeValue(forKey: "optionChoices")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SavedStudentPlan.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.optionChoices.isEmpty)
        var plan = SavedStudentPlan()
        plan.optionChoices = [Self.key(): "option-2"]
        #expect(try decoder.decode(SavedStudentPlan.self, from: encoder.encode(plan)).optionChoices == plan.optionChoices)
    }

    // MARK: - Generation and switching

    @Test func generationUsesTheStoredChoice() async {
        let store = Self.makeStore()
        store.plan = SavedStudentPlan(programID: Self.majorID)
        store.plan.optionChoices = [Self.key(): "option-1"]
        await store.generateSchedules()
        let pathway = store.plan.pathways.first
        #expect(pathway != nil)
        let ids = pathway?.semesters.flatMap(\.courseIDs) ?? []
        #expect(ids.contains { $0.contains("--option-1--") })
        #expect(!ids.contains { $0.contains("--option-2--") })
        #expect(store.plan.optionChoices[Self.key()] == "option-1")
    }

    /// Option 1 chosen; MATH 411 taken this semester (Fall 2026); option 1's
    /// elective slot and MATH 431 planned for later.
    static func switchStore(pathwayIDs: [String] = ["path-1"]) -> (PlanStore, UndoManager) {
        let store = makeStore()
        var plan = SavedStudentPlan(programID: majorID)
        plan.optionChoices = [key(): "option-1"]
        plan.setupCompleted = true
        plan.currentSemester = SemesterPlan(id: fall26, courseIDs: ["MATH411"])
        plan.pathways = pathwayIDs.map { id in
            Pathway(id: id, name: id, semesters: [
                SemesterPlan(id: fall26, courseIDs: ["MATH411"]),
                SemesterPlan(id: spring27, courseIDs: ["MATH235", slot("option-1", part: 0, 0)]),
                SemesterPlan(id: fall27, courseIDs: ["MATH431"])
            ], placeholders: [
                slot("option-1", part: 0, 0): PlaceholderSpec(categoryID: "\(req)--option-1--0", categoryName: "Option 1: Electives", alternates: electives, credits: 3)
            ])
        }
        plan.activePathwayID = pathwayIDs.first
        store.plan = plan
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        store.undoManager = undoManager
        return (store, undoManager)
    }

    static func futureIDs(_ pathway: Pathway) -> [String] {
        pathway.semesters.filter { $0.id > fall26 }.flatMap(\.courseIDs)
    }

    @Test func switchKeepsTakenCourseAndWarns() async {
        let (store, undo) = Self.switchStore()
        let before = store.plan
        await store.switchOption(programID: Self.majorID, requirementID: Self.req, to: "option-2")
        let pathway = store.plan.pathways[0]
        #expect(store.plan.optionChoices[Self.key()] == "option-2")
        #expect(pathway.semesters.first { $0.id == Self.fall26 }?.courseIDs.contains("MATH411") == true)
        #expect(!Self.futureIDs(pathway).contains { $0.contains("--option-1--") })
        #expect(!Self.futureIDs(pathway).contains("MATH431"))
        #expect(Self.futureIDs(pathway).contains { $0.contains("--option-2--") })
        #expect(store.statusMessage.contains("MATH 411"))
        #expect(undo.undoActionName == "Switch to Option 2")
        undo.undo()
        #expect(store.plan == before)
    }

    @Test func switchUpdatesEveryPathway() async {
        let (store, _) = Self.switchStore(pathwayIDs: ["path-1", "path-2", "path-3"])
        await store.switchOption(programID: Self.majorID, requirementID: Self.req, to: "option-2")
        #expect(store.plan.pathways.map(\.id) == ["path-1", "path-2", "path-3"])
        for pathway in store.plan.pathways {
            #expect(!Self.futureIDs(pathway).contains { $0.contains("--option-1--") })
            #expect(!Self.futureIDs(pathway).contains("MATH431"))
            #expect(Self.futureIDs(pathway).contains { $0.contains("--option-2--") })
        }
    }

    /// Option 1 entirely taken this semester: nothing to remove, but the new
    /// option still goes into the plan's own future semesters.
    @Test func switchWithoutFutureItemsRegeneratesFromTheFuture() async throws {
        let store = Self.makeStore()
        let elective = Self.slot("option-1", part: 0, 0)
        var plan = SavedStudentPlan(programID: Self.majorID)
        plan.optionChoices = [Self.key(): "option-1"]
        plan.setupCompleted = true
        plan.currentSemester = SemesterPlan(id: Self.fall26, courseIDs: ["MATH411", "MATH431", "MATH310"])
        let spring28 = SemesterIdentity(year: 2028, term: .spring)
        plan.pathways = [Pathway(id: "path-1", name: "Balanced", semesters: [
            SemesterPlan(id: Self.fall26, courseIDs: ["MATH411", "MATH431", "MATH310"]),
            SemesterPlan(id: Self.spring27, courseIDs: ["MATH235"]),
            SemesterPlan(id: Self.fall27, courseIDs: []),
            SemesterPlan(id: spring28, courseIDs: [])
        ], placeholders: [
            elective: PlaceholderSpec(categoryID: "\(Self.req)--option-1--0", categoryName: "Option 1: Electives", alternates: Self.electives, credits: 3)
        ], resolvedPlaceholders: [elective: "MATH310"])]
        plan.activePathwayID = "path-1"
        store.plan = plan
        await store.switchOption(programID: Self.majorID, requirementID: Self.req, to: "option-2")
        let pathway = store.plan.pathways[0]
        #expect(pathway.semesters.first?.courseIDs == ["MATH411", "MATH431", "MATH310"])
        #expect(Self.futureIDs(pathway).contains { $0.contains("--option-2--") })
        #expect(Self.futureIDs(pathway).contains("MATH235"))
        // Regenerated after Fall 2026, not appended after Spring 2028.
        #expect(try #require(pathway.semesters.map(\.id).max()) <= spring28)
        #expect(store.statusMessage.contains("MATH 411, MATH 431"))
    }

    @Test func switchRemovesALecturesLab() async {
        let store = Self.makeStore(labs: true)
        var plan = SavedStudentPlan(programID: Self.majorID)
        plan.optionChoices = [Self.key(): "option-1"]
        plan.setupCompleted = true
        plan.currentSemester = SemesterPlan(id: Self.fall26, courseIDs: ["MATH411"])
        plan.pathways = [Pathway(id: "path-1", name: "Balanced", semesters: [
            SemesterPlan(id: Self.fall26, courseIDs: ["MATH411"]),
            SemesterPlan(id: Self.spring27, courseIDs: ["MATH235", "MATH431L"]),
            SemesterPlan(id: Self.fall27, courseIDs: ["MATH431"])
        ])]
        plan.activePathwayID = "path-1"
        store.plan = plan
        await store.switchOption(programID: Self.majorID, requirementID: Self.req, to: "option-2")
        let future = Self.futureIDs(store.plan.pathways[0])
        #expect(!future.contains("MATH431"))
        #expect(!future.contains("MATH431L"))
        #expect(future.contains { $0.contains("--option-2--") })
    }

    @Test func minorChoiceIsSeparate() async {
        let store = Self.makeStore(programs: [Self.optionMajor(requirementID: "r"), Self.minor()])
        var plan = SavedStudentPlan(programID: Self.majorID, minors: [MinorSelection(programID: Self.minorID)])
        plan.optionChoices = [Self.key(Self.majorID, "r"): "option-1", Self.key(Self.minorID, "r"): "option-1"]
        store.plan = plan
        #expect(Set(store.optionRequirements().map(\.programID)) == [Self.majorID, Self.minorID])
        await store.switchOption(programID: Self.minorID, requirementID: "r", to: "option-2")
        #expect(store.plan.optionChoices[Self.key(Self.minorID, "r")] == "option-2")
        #expect(store.plan.optionChoices[Self.key(Self.majorID, "r")] == "option-1")
        #expect(store.effectiveMinorProgram(for: plan.minors[0])?.requirements.map(\.id) == ["r--option-2--0", "r--option-2--1"])
    }

    static func optionMajor(requirementID: String) -> Program {
        Program.fixture(id: majorID, title: "Math", requirements: [core, optionRequirement(id: requirementID)])
    }

    // MARK: - "Or take both" linkage

    static func groupStore() -> PlanStore {
        let store = makeStore()
        var plan = SavedStudentPlan(programID: majorID)
        plan.optionChoices = [key(): "option-2"]
        let spec = PlaceholderSpec(categoryID: "\(req)--option-2--1", categoryName: "Option 2: Choose two", alternates: chooseTwo, credits: 3)
        plan.pathways = [Pathway(id: "path-1", name: "Balanced", semesters: [
            SemesterPlan(id: fall26, courseIDs: [slot("option-2", part: 1, 0)]),
            SemesterPlan(id: spring27, courseIDs: [slot("option-2", part: 1, 1)])
        ], placeholders: [slot("option-2", part: 1, 0): spec, slot("option-2", part: 1, 1): spec])]
        plan.activePathwayID = "path-1"
        store.plan = plan
        return store
    }

    @Test func pickingAGroupMemberFillsTheOtherSlot() {
        let store = Self.groupStore()
        store.resolvePlaceholder(Self.slot("option-2", part: 1, 0), with: "MATH426")
        let pathway = store.plan.pathways[0]
        #expect(pathway.semesters[0].courseIDs == ["MATH426"])
        #expect(pathway.semesters[1].courseIDs == ["MATH427"])
        #expect(pathway.resolvedPlaceholders[Self.slot("option-2", part: 1, 1)] == "MATH427")
    }

    @Test func pickingAGroupMemberReplacesARegularPick() {
        let store = Self.groupStore()
        store.resolvePlaceholder(Self.slot("option-2", part: 1, 1), with: "MATH440")
        store.resolvePlaceholder(Self.slot("option-2", part: 1, 0), with: "MATH426")
        let pathway = store.plan.pathways[0]
        #expect(pathway.semesters[0].courseIDs == ["MATH426"])
        #expect(pathway.semesters[1].courseIDs == ["MATH427"])
        #expect(pathway.resolvedPlaceholders[Self.slot("option-2", part: 1, 1)] == "MATH427")
        #expect(!pathway.semesters.flatMap(\.courseIDs).contains("MATH440"))
    }

    @Test func pickingOutsideTheGroupReopensTheOtherSlot() {
        let store = Self.groupStore()
        store.resolvePlaceholder(Self.slot("option-2", part: 1, 0), with: "MATH426")
        store.resolvePlaceholder(Self.slot("option-2", part: 1, 0), with: "MATH440")
        let pathway = store.plan.pathways[0]
        #expect(pathway.semesters[0].courseIDs == ["MATH440"])
        #expect(pathway.semesters[1].courseIDs == [Self.slot("option-2", part: 1, 1)])
        #expect(pathway.resolvedPlaceholders[Self.slot("option-2", part: 1, 1)] == nil)
        #expect(pathway.resolvedPlaceholders[Self.slot("option-2", part: 1, 0)] == "MATH440")
    }

    // MARK: - Requirement highlight

    @Test func myPlanRowShowsTheChosenOptionsCourses() throws {
        let store = Self.makeStore(programs: [Self.major(), Self.minor()])
        var plan = SavedStudentPlan(programID: Self.majorID, minors: [MinorSelection(programID: Self.minorID)])
        plan.optionChoices = [Self.key(): "option-2", Self.key(Self.minorID, "r"): "option-2"]
        plan.pathways = [Pathway(id: "path-1", name: "Balanced", semesters: [SemesterPlan(id: Self.fall26, courseIDs: ["MATH426"])])]
        plan.activePathwayID = "path-1"
        store.plan = plan

        let major = try #require(store.requirementForProgressRow(Self.req))
        let remaining = store.remainingCourses(in: major)
        #expect(remaining.contains("MATH 310"))
        #expect(remaining.contains("MATH 440"))
        #expect(!remaining.contains("MATH 411"))
        #expect(!remaining.contains("MATH 431"))
        let contributions = ProgressContributionBuilder.contributions(
            for: major, transferCredits: [], scheduled: ["MATH426": "Fall 2026"], coursesByID: store.catalog!.coursesByID
        )
        #expect(contributions.map(\.code) == ["MATH 426"])

        let minor = try #require(store.requirementForProgressRow("\(Self.minorID)::r"))
        let minorRemaining = store.remainingCourses(in: minor)
        #expect(!minorRemaining.isEmpty)
        #expect(minorRemaining.contains("MATH 440"))
        #expect(!minorRemaining.contains("MATH 411"))

        #expect(store.requirementForProgressRow("core")?.courseOptions == [["MATH235"]])
        #expect(store.requirementForProgressRow("\(Self.minorID)::missing") == nil)
    }

    @Test func foldedOptionRowHighlightsItsParts() {
        let store = Self.makeStore(programs: [Self.major(), Self.minor()])
        var plan = SavedStudentPlan(programID: Self.majorID, minors: [MinorSelection(programID: Self.minorID)])
        plan.optionChoices = [Self.key(): "option-2", Self.key(Self.minorID, "r"): "option-2"]
        let elective = Self.slot("option-2", part: 0, 0)
        let open = Self.slot("option-2", part: 1, 0)
        let minorSlot = Self.slot("option-2", part: 0, 0, requirement: "r")
        plan.pathways = [Pathway(id: "path-1", name: "Balanced", semesters: [
            SemesterPlan(id: Self.fall26, courseIDs: ["MATH499", open, "MATH411", minorSlot])
        ], placeholders: [
            elective: PlaceholderSpec(categoryID: "\(Self.req)--option-2--0", categoryName: "Option 2: Electives", alternates: Self.electives, credits: 3),
            open: PlaceholderSpec(categoryID: "\(Self.req)--option-2--1", categoryName: "Option 2: Choose two", alternates: Self.chooseTwo, credits: 3),
            minorSlot: PlaceholderSpec(categoryID: "r--option-2--0", categoryName: "Option 2: Electives", alternates: Self.electives, credits: 3)
        ], resolvedPlaceholders: [elective: "MATH499"])]
        plan.activePathwayID = "path-1"
        store.plan = plan

        let major = store.courseIDsForRequirementHighlight(rowID: Self.req)
        #expect(major.contains("MATH499"))
        #expect(major.contains(open))
        #expect(major.contains("MATH440"))
        #expect(major.contains("MATH426"))
        #expect(!major.contains("MATH411"))
        #expect(!major.contains(minorSlot))

        let minor = store.courseIDsForRequirementHighlight(rowID: "\(Self.minorID)::r")
        #expect(minor.contains(minorSlot))
        #expect(minor.contains("MATH427"))
        #expect(!minor.contains("MATH411"))

        #expect(store.courseIDsForRequirementHighlight(rowID: "core") == ["MATH235"])
    }
}
