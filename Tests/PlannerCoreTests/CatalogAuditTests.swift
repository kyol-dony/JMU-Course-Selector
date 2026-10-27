import Foundation
import Testing
@testable import JMUCoursePlanner
@testable import PlannerCore

/// Opt-in audit over a whole cached catalog: generates the first pathway for
/// every major and prints its total credits. Runs only when
/// `CATALOG_AUDIT_JSON` names a `catalog_html_cache_vN.json` file.
@Suite("Catalog audit")
struct CatalogAuditTests {
    private static let path = ProcessInfo.processInfo.environment["CATALOG_AUDIT_JSON"]

    /// History B.A. placing into SPAN 102 or 231 graduates on the same
    /// schedule as starting at 101, with the sequence early in the plan.
    @MainActor @Test(.enabled(if: path != nil))
    func languagePlacementKeepsGraduationOnTime() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(Self.path))))
        let catalog = CatalogRepository.applyingCurrentGenEdCredits(to: decoded).resolvingElectivePools()
        let history = try #require(catalog.programsByID["history-ba"])
        for placement in [LanguagePlacement.level102, .level231] {
            let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
                for: history.id, concentrationID: history.concentrations.first?.id, workload: .standard, transferCredits: [],
                starting: SemesterIdentity(year: 2026, term: .fall), languagePlan: ForeignLanguagePlan(subject: "SPAN", placement: placement)
            ).first)
            let first = pathway.semesters.firstIndex { $0.courseIDs.contains { $0.hasPrefix("SPAN") } }
            #expect(pathway.semesters.count <= 8, "\(placement): \(pathway.semesters.count) semesters")
            #expect((first ?? 99) <= 2, "\(placement): first SPAN course in semester \((first ?? 99) + 1)")
        }
    }

    /// Math B.S. (not seeking licensure) on Option 2 schedules Option 2's
    /// parts and none of Option 1's required MATH 411/431/434/435.
    @MainActor @Test(.enabled(if: path != nil))
    func mathBSOptionTwoSchedulesOnlyOptionTwo() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(Self.path))))
        let catalog = CatalogRepository.applyingCurrentGenEdCredits(to: decoded).resolvingElectivePools()
        let math = try #require(catalog.programsByID["mathematics-bs"])
        let track = try #require(math.concentrations.first { $0.id == "not-seeking-secondary-teaching-licensure" })
        let requirement = try #require(track.requirements.first { $0.options != nil })
        let choices = [RequirementOption.choiceKey(programID: math.id, requirementID: requirement.id): "option-2"]
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: math.id, concentrationID: track.id, workload: .standard, transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall), optionChoices: choices
        ).first)
        let scheduled = Set(pathway.semesters.flatMap(\.courseIDs))
        for id in ["MATH411", "MATH431", "MATH434", "MATH435"] {
            #expect(!scheduled.contains(id), "\(id) belongs to Option 1")
        }
        let option2 = pathway.placeholders.values.filter { $0.categoryID.hasPrefix("\(requirement.id)--option-2--") }
        #expect(option2.filter { $0.categoryID.hasSuffix("--0") }.count == 2, "two 6-credit elective slots")
        let chooseTwo = option2.filter { $0.categoryID.hasSuffix("--1") }
        #expect(chooseTwo.count == 2, "two choose-two slots")
        #expect(chooseTwo.allSatisfy { $0.alternates.contains("MATH426") && $0.alternates.contains("MATH427") })
        #expect(!pathway.placeholders.values.contains { $0.categoryID.contains("--option-1--") })
    }

    /// Every option of every option requirement in the catalog schedules only
    /// that option's parts. A major carries its own options (inside the first
    /// track that holds them); a minor's are added to a plain major.
    @MainActor @Test(.enabled(if: path != nil))
    func everyOptionGeneratesAndSchedulesOnlyItself() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(Self.path))))
        let catalog = CatalogRepository.applyingCurrentGenEdCredits(to: decoded).resolvingElectivePools()
        let generator = ScheduleGenerator(catalog: catalog)
        let base = try #require(catalog.programs.first {
            $0.kind == .major && $0.requirementDataComplete && !$0.concentrationSelectionRequired
                && !ForeignLanguagePlan.isRequired(by: [$0]) && !$0.requirements.contains { $0.options != nil }
        })
        var checked = 0
        for program in catalog.programs where program.kind != .certificate {
            let holders: [(concentrationID: String?, requirements: [RequirementCategory])] =
                [(nil, program.requirements)] + program.concentrations.map { ($0.id, $0.requirements) }
            for holder in holders {
                for requirement in holder.requirements {
                    for option in requirement.options ?? [] {
                        let choices = [RequirementOption.choiceKey(programID: program.id, requirementID: requirement.id): option.id]
                        let label = "\(program.id)/\(requirement.id)/\(option.id)"
                        do {
                            let pathway: Pathway
                            if program.kind == .major {
                                pathway = try #require(try generator.generatePathways(
                                    for: program.id, concentrationID: holder.concentrationID ?? (program.concentrationSelectionRequired ? program.concentrations.first?.id : nil),
                                    workload: .standard, transferCredits: [], starting: SemesterIdentity(year: 2026, term: .fall),
                                    languagePlan: ForeignLanguagePlan.isRequired(by: [program]) ? ForeignLanguagePlan(subject: "SPAN", placement: .notSure) : nil,
                                    optionChoices: choices
                                ).first)
                            } else {
                                pathway = try #require(try generator.generatePathways(
                                    for: base.id, workload: .standard, transferCredits: [], starting: SemesterIdentity(year: 2026, term: .fall),
                                    additionalPrograms: [program.choosingOptions(choices, programID: program.id)], optionChoices: [:]
                                ).first)
                            }
                            let others = Set(requirement.options?.map(\.id) ?? []).subtracting([option.id])
                            let stray = pathway.placeholders.values.filter { spec in
                                guard let parsed = OptionPartID.parse(spec.categoryID.components(separatedBy: "::").last ?? spec.categoryID),
                                      parsed.requirementID == requirement.id else { return false }
                                return others.contains(parsed.optionID)
                            }
                            #expect(stray.isEmpty, "\(label) schedules another option's parts")
                            // Required single courses of the option are on the schedule.
                            let scheduled = Set(pathway.semesters.flatMap(\.courseIDs))
                            for part in option.parts where part.selection == .allRequired {
                                for slot in part.courseOptions where slot.count == 1 {
                                    #expect(scheduled.contains(slot[0]), "\(label) lacks required \(slot[0])")
                                }
                            }
                            let slots = pathway.placeholders.values.filter { $0.categoryID.contains("\(requirement.id)--\(option.id)--") }.count
                            let hours = AcademicCreditCalculator.projectedHours(
                                in: pathway.semesters, placeholders: pathway.placeholders, transferCredits: [], catalog: catalog
                            )
                            print("OPTAUDIT\t\(label)\tslots=\(slots)\tsemesters=\(pathway.semesters.count)\thours=\(Int(hours.rounded()))")
                            checked += 1
                        } catch {
                            Issue.record("\(label): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        #expect(checked > 0)
    }

    @MainActor @Test(.enabled(if: path != nil))
    func everyMajorGeneratesAReasonablePlan() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(Self.path))))
        var catalog = CatalogRepository.applyingCurrentGenEdCredits(to: decoded).resolvingElectivePools()
        // CATALOG_AUDIT_NO_DEGREE gives the same catalog without B.A./B.S.
        // degree requirements, as a baseline for comparison.
        if ProcessInfo.processInfo.environment["CATALOG_AUDIT_NO_DEGREE"] != nil {
            catalog.programs = catalog.programs.map { var p = $0; p.degreeRequirements = []; return p }
        }
        let generator = ScheduleGenerator(catalog: catalog)
        for program in catalog.programs where program.kind == .major && program.requirementDataComplete {
            let concentrationID = program.concentrationSelectionRequired ? program.concentrations.first?.id : nil
            let needsLanguage = ForeignLanguagePlan.isRequired(by: [program])
            do {
                let pathway = try #require(try generator.generatePathways(
                    for: program.id,
                    concentrationID: concentrationID,
                    workload: .standard,
                    transferCredits: [],
                    starting: SemesterIdentity(year: 2026, term: .fall),
                    languagePlan: needsLanguage ? ForeignLanguagePlan(subject: "SPAN", placement: .notSure) : nil
                ).first)
                if needsLanguage {
                    let ids = Set(pathway.semesters.flatMap(\.courseIDs))
                    #expect(["SPAN101", "SPAN102", "SPAN231", "SPAN232"].allSatisfy(ids.contains), "\(program.title) lacks the Spanish sequence")
                }
                let hours = AcademicCreditCalculator.projectedHours(
                    in: pathway.semesters, placeholders: pathway.placeholders, transferCredits: [], catalog: catalog
                )
                print("AUDIT\t\(program.id)\t\(Int(hours.rounded()))")
                if ProcessInfo.processInfo.environment["CATALOG_AUDIT_PROGRAM"] == program.id {
                    for id in pathway.semesters.flatMap(\.courseIDs) {
                        let spec = pathway.placeholders[id]
                        print("COURSE\t\(spec.map { "\($0.categoryName) (\($0.credits))" } ?? id)\t\(catalog.coursesByID[id]?.credits ?? 0)")
                    }
                }
                #expect(hours <= 140, "\(program.title): \(hours) credits")
            } catch {
                print("AUDIT\t\(program.id)\tERROR \(error.localizedDescription)")
            }
        }
    }
}
