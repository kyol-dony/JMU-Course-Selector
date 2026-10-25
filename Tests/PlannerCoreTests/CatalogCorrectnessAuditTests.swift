import Foundation
import Testing
@testable import PlannerCore

/// Offline audit of captured catalog pages. This checks internal accounting,
/// not equivalence to catalog policies that the parser has not represented.
@Suite("Catalog correctness audit")
struct CatalogCorrectnessAuditTests {
    @Test(arguments: ["_live_cs.html", "_live_accounting.html", "_live_nursing.html", "_live_psyc.html", "_live_psyc_bs.html", "_live_math_bs.html", "_live_posc_minor.html"])
    func capturedPrograms(file: String) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(file)
        let kind: ProgramKind = (file.contains("minor") || file == "_live_psyc.html") ? .minor : .major
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(
            try String(contentsOf: url, encoding: .utf8), kind: kind,
            sourceURL: URL(string: "https://catalog.jmu.edu/programs/audit/")!)
        let raw = Program(id: file, title: file, degreeType: nil, kind: kind, college: "Audit", department: "Audit", catalogPage: nil,
                          totalCredits: nil, requirements: parsed.requirements, concentrations: parsed.concentrations,
                          concentrationSelectionRequired: parsed.concentrationSelectionRequired,
                          verificationStatus: .partial, requirementDataComplete: true, sourceNote: "Captured fixture")
        let catalog = Catalog.fixture(courses: parsed.courses, program: raw).resolvingElectivePools()
        let program = try #require(catalog.programsByID[file])
        let choices: [String?] = program.concentrations.isEmpty ? [nil] : program.concentrations.map { Optional($0.id) }
        for choice in choices {
            let effective = try program.effectiveProgram(concentrationID: choice)
            let plans = try ScheduleGenerator(catalog: catalog).generatePathways(for: file, concentrationID: choice, workload: .standard, transferCredits: [])
            #expect(plans.count == 3)
            for plan in plans {
                let ids = plan.semesters.flatMap(\.courseIDs)
                #expect(Set(ids).count == ids.count, "Duplicate enrollment rows: \(file)")
                #expect(ids.allSatisfy { catalog.coursesByID[$0] != nil || plan.placeholders[$0] != nil })
            }
            let first = try #require(plans.first)
            if let earnedID = first.semesters.flatMap(\.courseIDs).first(where: { catalog.coursesByID[$0] != nil }) {
                let earned = TransferCredit(sourceDescription: "Audit transfer", courseIDs: [earnedID], credits: Double(catalog.coursesByID[earnedID]!.credits))
                let transferred = try ScheduleGenerator(catalog: catalog).generatePathways(for: file, concentrationID: choice, workload: .standard, transferCredits: [earned])
                for plan in transferred {
                    #expect(!plan.semesters.flatMap(\.courseIDs).contains(earnedID), "Earned course rescheduled: \(file) \(earnedID)")
                }
            }
            let hours = AcademicCreditCalculator.projectedHours(in: first.semesters, placeholders: first.placeholders, transferCredits: [], catalog: catalog)
            if file == "_live_psyc.html" {
                withKnownIssue("Captured ISAT minor says 18–20 credits; alternative sequences currently accumulate") {
                    #expect(hours <= 20)
                }
            }
            if file == "_live_nursing.html", choice == "applied-physics" {
                withKnownIssue("Suggested Applied Physics elective areas currently accumulate as mandatory work") {
                    #expect(hours <= 120)
                }
            }
            let unknown = effective.requirements.filter { $0.selection == .unknown }.count
            let empty = effective.requirements.filter { $0.courseOptions.isEmpty && $0.requiredCredits > 0 }.map(\.name)
            if file == "_live_psyc.html" || (file == "_live_nursing.html" && choice == "applied-physics") {
                for category in effective.requirements {
                    print("DETAIL \(file) | \(category.name) | credits=\(category.requiredCredits) | slots=\(category.courseOptions.count) | rule=\(category.selection)")
                }
            }
            print("AUDIT \(file) | \(choice ?? "base") | declared=\(effective.requirements.reduce(0) { $0 + $1.requiredCredits }) | projected=\(hours) | unknown=\(unknown) | unmodeled=\(empty)")
        }
    }

    @Test(arguments: ["_live_cs.html", "_live_accounting.html", "_live_psyc_bs.html", "_live_math_bs.html"])
    func stackedMinor(file: String) throws {
        func load(_ name: String, kind: ProgramKind) throws -> (Program, [Course]) {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(name)
            let parsed = JMUHTMLCatalogParser().parseProgramRequirements(try String(contentsOf: url, encoding: .utf8), kind: kind,
                sourceURL: URL(string: "https://catalog.jmu.edu/programs/audit/")!)
            let p = Program(id: name, title: name, degreeType: nil, kind: kind, college: "Audit", department: "Audit", catalogPage: nil,
                totalCredits: nil, requirements: parsed.requirements, concentrations: parsed.concentrations,
                concentrationSelectionRequired: parsed.concentrationSelectionRequired, verificationStatus: .partial,
                requirementDataComplete: true, sourceNote: "Captured fixture")
            return (p, parsed.courses)
        }
        let (major, majorCourses) = try load(file, kind: .major)
        for minorFile in ["_live_posc_minor.html", "_live_psyc.html"] {
            let (minor, minorCourses) = try load(minorFile, kind: .minor)
            let courses = Array(Dictionary((majorCourses + minorCourses).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
            var catalog = Catalog.fixture(courses: courses, program: major)
            catalog.programs.append(minor)
            catalog = catalog.resolvingElectivePools()
            let resolvedMajor = try #require(catalog.programsByID[file])
            let resolvedMinor = try #require(catalog.programsByID[minorFile])
            let majors: [String?] = resolvedMajor.concentrations.isEmpty ? [nil] : resolvedMajor.concentrations.map { Optional($0.id) }
            let minors: [String?] = resolvedMinor.concentrations.isEmpty ? [nil] : resolvedMinor.concentrations.map { Optional($0.id) }
            for majorChoice in majors {
                for minorChoice in minors {
                    let effectiveMinor = try resolvedMinor.effectiveProgram(concentrationID: minorChoice)
                    let earned = Array(Set(effectiveMinor.requirements.flatMap { $0.courseOptions.flatMap { $0 } })).sorted().prefix(2)
                    let transfers = earned.compactMap { id -> TransferCredit? in
                        guard let course = catalog.coursesByID[id] else { return nil }
                        return TransferCredit(sourceDescription: "Audit transfer", courseIDs: [id], credits: Double(course.credits))
                    }
                    for credits in [[], transfers] {
                        let plans = try ScheduleGenerator(catalog: catalog).generatePathways(for: file, concentrationID: majorChoice,
                            workload: .standard, transferCredits: credits, additionalPrograms: [effectiveMinor])
                        for plan in plans {
                            let ids = plan.semesters.flatMap(\.courseIDs)
                            #expect(ids.count == Set(ids).count)
                            #expect(Set(ids).isDisjoint(with: Set(credits.flatMap(\.courseIDs))))
                        }
                    }
                    print("STACK \(file) | \(majorChoice ?? "base") | \(minorFile) | \(minorChoice ?? "base") | 3 strategies x 2 credit states")
                }
            }
        }
    }
}
