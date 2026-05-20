import Foundation
import PlannerCore

@MainActor
struct CatalogRepository {
    private let fileManager = FileManager.default
    private let htmlParser = JMUHTMLCatalogParser()

    func loadCatalog() throws -> Catalog {
        if let cached = try? loadCachedHTMLCatalog() {
            return cached
        }
        return try loadBundledCatalog()
    }

    func loadBundledCatalog() throws -> Catalog {
        let url = try bundledCatalogURL()
        let data = try Data(contentsOf: url)
        let seed = try SeedCatalog.decode(from: data)
        return seed.catalog()
    }

    func refreshCatalogFromHTML(progress: ((CatalogRefreshProgress) -> Void)? = nil) async throws -> Catalog {
        let seed = try SeedCatalog.decode(from: try Data(contentsOf: bundledCatalogURL()))
        let programsURL = URL(string: "https://catalog.jmu.edu/content.php?catoid=62&navoid=3541")!
        let indexHTML = try await Self.fetchHTML(from: programsURL)
        let entries = htmlParser.parseProgramsOfStudy(indexHTML)
        let seedProgramsByTitle = Dictionary(uniqueKeysWithValues: seed.programs.map { ($0.title.normalizedProgramTitle, $0) })
        var programIDsByTitle: [String: String] = [:]
        var usedProgramIDs: Set<String> = []
        var refreshedPrograms: [Program] = []
        var coursesByID = Dictionary(uniqueKeysWithValues: seed.courses.map { ($0.course.id, $0.course) })
        var failedPrograms: [String] = []

        // Pull JMU General Education clusters once up-front. Used to enrich every
        // major's requirement list — JMU program pages reference Gen Ed by name
        // but don't repeat the cluster course buckets, so we have to inject them.
        let genEd = (try? await fetchGeneralEducation(coursesByID: &coursesByID)) ?? []

        for (index, entry) in entries.enumerated() {
            progress?(CatalogRefreshProgress(current: index + 1, total: entries.count, programTitle: entry.title))

            let seedProgram = seedProgramsByTitle[entry.title.normalizedProgramTitle]
            let id = programID(for: entry, seedProgram: seedProgram, used: &usedProgramIDs, cachedByTitle: &programIDsByTitle)
            var requirements: HTMLProgramRequirements?

            do {
                let html = try await Self.fetchHTML(from: entry.printURL)
                requirements = htmlParser.parseProgramRequirements(html, kind: entry.kind, sourceURL: entry.sourceURL)
                for course in requirements?.courses ?? [] {
                    coursesByID[course.id] = merge(existing: coursesByID[course.id], parsed: course)
                }
            } catch {
                failedPrograms.append(entry.title)
            }

            var parsedRequirements = requirements?.requirements ?? []
            // Majors at JMU all require General Education unless the parsed page
            // already includes its own gen ed category. Append the shared cluster
            // set so progress tracking and schedule generation can see it.
            if entry.kind == .major,
               !genEd.isEmpty,
               !parsedRequirements.contains(where: { $0.id.contains("gened") || $0.name.lowercased().contains("general education") }) {
                parsedRequirements.append(contentsOf: genEd)
            }
            let hasSchedulableCourses = parsedRequirements.contains { !$0.courseOptions.isEmpty }
            let totalCredits = requirements?.totalCredits
                ?? seedProgram.flatMap { existing in existing.kind == .major ? 120 : nil }
                ?? (entry.kind == .major ? 120 : nil)

            refreshedPrograms.append(Program(
                id: id,
                title: requirements?.title ?? seedProgram?.title ?? entry.title,
                degreeType: seedProgram?.degreeType ?? entry.degreeType,
                kind: seedProgram?.kind ?? entry.kind,
                college: seedProgram?.college ?? "JMU Programs of Study",
                department: seedProgram?.department ?? entry.sectionTitle,
                catalogPage: seedProgram?.catalogPage,
                totalCredits: totalCredits,
                requirements: parsedRequirements,
                verificationStatus: parsedRequirements.isEmpty ? .unverified : .partial,
                requirementDataComplete: hasSchedulableCourses,
                sourceNote: sourceNote(for: entry, parsedRequirements: parsedRequirements, failed: failedPrograms.contains(entry.title))
            ))

            if index + 1 < entries.count {
                try await Task.sleep(for: .milliseconds(150))
            }
        }

        let detailEnrichments = try await fetchCourseDetailEnrichments(for: Array(coursesByID.values))
        for enrichment in detailEnrichments.values {
            guard var course = coursesByID[enrichment.courseID] else { continue }
            course.description = enrichment.description
            course.descriptionSourceURL = enrichment.sourceURL
            course.detailRetrievedAt = enrichment.retrievedAt
            coursesByID[enrichment.courseID] = course
        }
        try Task.checkCancellation()

        let catalogSource = CatalogSource(
            catalogYear: seed.source.catalogYear,
            issueDate: seed.source.issueDate,
            retrievedDate: Date(),
            sourceURLs: [programsURL],
            retrievalNotes: [
                "Program and requirement rows were parsed from official JMU catalog HTML pages.",
                "Parsed \(refreshedPrograms.filter { $0.kind == .major }.count) majors and \(refreshedPrograms.filter { $0.kind == .minor }.count) minors from Programs of Study.",
                "Sections that depend on prose, unrestricted electives, concentrations, or advisor-selected choices are marked partial instead of inferred."
            ] + (failedPrograms.isEmpty ? [] : ["Failed to parse \(failedPrograms.count) program pages during the latest refresh."])
        )

        let catalog = Catalog(
            source: catalogSource,
            programs: refreshedPrograms.sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.title < rhs.title
            },
            courses: coursesByID.values.sorted { $0.code < $1.code },
            apCreditRules: seed.apCreditRules
        )

        try saveHTMLCatalog(catalog)
        return catalog
    }

    func refreshCatalogPDF() async throws -> URL {
        let source = URL(string: "https://www.jmu.edu/catalog/pdfs/2025-2026-jmu-undergraduate-catalog.pdf")!
        let (temporaryURL, _) = try await URLSession.shared.download(from: source)
        let directory = try supportDirectory().appending(path: "Catalog", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "2025-2026-jmu-undergraduate-catalog.pdf")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    func supportDirectory() throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appending(path: "JMUCoursePlanner", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func loadCachedHTMLCatalog() throws -> Catalog {
        let url = try cachedHTMLCatalogURL()
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Catalog.self, from: data)
    }

    private func saveHTMLCatalog(_ catalog: Catalog) throws {
        let url = try cachedHTMLCatalogURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(catalog).write(to: url)
    }

    /// Bump this whenever the cached catalog schema or the way we synthesize
    /// requirements changes. Old cache files (e.g., the pre-Gen-Ed format) are
    /// then ignored automatically and the app falls back to the bundled seed,
    /// which in turn triggers a fresh HTML refresh on launch.
    private static let cacheSchemaVersion = 3

    private func cachedHTMLCatalogURL() throws -> URL {
        let directory = try supportDirectory().appending(path: "Catalog", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "catalog_html_cache_v\(Self.cacheSchemaVersion).json")
    }

    /// Wipe the cached HTML catalog and all saved plans. Called when the user
    /// hits "Reset App Data" — gets them back to a true first-launch state.
    func resetAppData() throws {
        let support = try supportDirectory()
        try? fileManager.removeItem(at: support.appending(path: "Catalog", directoryHint: .isDirectory))
        try? fileManager.removeItem(at: support.appending(path: "Plans", directoryHint: .isDirectory))
    }

    private func bundledCatalogURL() throws -> URL {
        let candidates = [
            Bundle.main.url(forResource: "catalog_seed", withExtension: "json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "Data/catalog_seed.json")
        ].compactMap { $0 }

        guard let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    /// JMU 2025-2026 Catalog: Gen Ed credit allocation per cluster tag, sourced
    /// from the catalog narrative. Used as overrides because the cluster headings
    /// on the Gen Ed program page (e.g. "Critical Thinking [C1CT]") don't repeat
    /// the credit count, so we can't parse it.
    private static let genEdClusterCredits: [String: Int] = [
        "C1CT": 3, "C1HC": 3, "C1W": 3,
        "C2HQC": 3, "C2VPA": 3, "C2L": 3,
        "C3QR": 3, "C3PP": 4, "C3NS": 3, "C3L": 1,
        "C4AE": 3, "C4GE": 3,
        "C5SD": 3, "C5W": 3
    ]

    private func fetchCourseDetailEnrichments(for courses: [Course]) async throws -> [String: CourseDetailEnrichment] {
        let candidates = courses
            .filter { $0.registrarURL != nil }
            .filter { ($0.description ?? "").isEmpty }
            .sorted { $0.code < $1.code }

        guard !candidates.isEmpty else { return [:] }

        let parser = htmlParser
        let limit = 4

        return try await withThrowingTaskGroup(
            of: CourseDetailEnrichment?.self,
            returning: [String: CourseDetailEnrichment].self
        ) { group in
            var nextIndex = 0

            func enqueueNext() {
                guard nextIndex < candidates.count else { return }
                let course = candidates[nextIndex]
                nextIndex += 1

                group.addTask {
                    guard let url = course.registrarURL else { return nil }

                    do {
                        let html = try await Self.fetchHTML(from: url)
                        let detail = parser.parseCourseDetail(html)
                        guard let description = detail.description, !description.isEmpty else {
                            return nil
                        }
                        return CourseDetailEnrichment(
                            courseID: course.id,
                            description: description,
                            sourceURL: url,
                            retrievedAt: Date()
                        )
                    } catch let error as CancellationError {
                        throw error
                    } catch {
                        return nil
                    }
                }
            }

            for _ in 0..<min(limit, candidates.count) {
                enqueueNext()
            }

            var results: [String: CourseDetailEnrichment] = [:]
            while let enrichment = try await group.next() {
                if let enrichment {
                    results[enrichment.courseID] = enrichment
                }
                enqueueNext()
            }

            return results
        }
    }

    private func fetchGeneralEducation(coursesByID: inout [String: Course]) async throws -> [RequirementCategory] {
        // JMU Gen Ed program page (poid=26976) lists every course in every cluster.
        let url = URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=26976&returnto=3541&print")!
        let html = try await Self.fetchHTML(from: url)
        let parsed = htmlParser.parseProgramRequirements(html, kind: .major, sourceURL: url)
        for course in parsed.courses {
            coursesByID[course.id] = merge(existing: coursesByID[course.id], parsed: course)
        }

        // Override the parser-inferred credit numbers using the official Gen Ed
        // cluster allocation. Match by bracketed code in the cluster heading.
        return parsed.requirements.compactMap { category in
            guard let tag = extractClusterTag(from: category.name),
                  let credits = Self.genEdClusterCredits[tag]
            else {
                // Skip non-cluster blocks (e.g., "Madison Foundations" umbrella).
                return nil
            }
            // Each cluster is "choose one from the following N courses": one option
            // group with N alternatives, NOT N separate options.
            let alternatives = category.courseOptions.flatMap { $0 }
            let courseOptions: [[String]] = alternatives.isEmpty ? [] : [alternatives]
            return RequirementCategory(
                id: "gened-\(tag.lowercased())",
                name: "General Education — \(category.name)",
                requiredCredits: credits,
                courseOptions: courseOptions,
                verificationStatus: .partial,
                note: "Choose one course from this Gen Ed cluster (\(alternatives.count) eligible options in the JMU 2025-2026 catalog)."
            )
        }
    }

    private func extractClusterTag(from heading: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\[(C\d[A-Z]+)\]"#) else { return nil }
        let range = NSRange(heading.startIndex..<heading.endIndex, in: heading)
        guard let match = regex.firstMatch(in: heading, range: range),
              match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: heading)
        else { return nil }
        return String(heading[group])
    }

    nonisolated private static func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("JMUCoursePlanner/1.0 (+https://catalog.jmu.edu/)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return html
    }

    private func sourceNote(for entry: HTMLProgramIndexEntry, parsedRequirements: [RequirementCategory], failed: Bool) -> String {
        if failed {
            return "Listed in the JMU catalog HTML index, but the program page could not be parsed during the latest refresh: \(entry.sourceURL.absoluteString)"
        }
        if parsedRequirements.isEmpty {
            return "Listed in the JMU catalog HTML index. The program page did not expose fixed requirement rows that this parser could schedule: \(entry.sourceURL.absoluteString)"
        }
        return "Requirements parsed from the official JMU catalog HTML page: \(entry.sourceURL.absoluteString)"
    }

    private func programID(
        for entry: HTMLProgramIndexEntry,
        seedProgram: SeedProgram?,
        used: inout Set<String>,
        cachedByTitle: inout [String: String]
    ) -> String {
        let normalizedTitle = entry.title.normalizedProgramTitle
        if let cached = cachedByTitle[normalizedTitle] {
            return cached
        }

        let baseID = seedProgram?.id ?? entry.title.programSlug
        var candidate = baseID
        var suffix = 2
        while used.contains(candidate) {
            candidate = "\(baseID)-\(entry.poid)"
            if used.contains(candidate) {
                candidate = "\(baseID)-\(suffix)"
                suffix += 1
            }
        }

        used.insert(candidate)
        cachedByTitle[normalizedTitle] = candidate
        return candidate
    }

    func merge(existing: Course?, parsed: Course) -> Course {
        guard var existing else { return parsed }
        if existing.registrarURL == nil {
            existing.registrarURL = parsed.registrarURL
        }
        if existing.title.isEmpty {
            existing.title = parsed.title
        }
        if existing.credits == 0 {
            existing.credits = parsed.credits
        }
        if existing.prerequisites.isEmpty {
            existing.prerequisites = parsed.prerequisites
        }
        if (existing.description ?? "").isEmpty {
            existing.description = parsed.description
        }
        if existing.descriptionSourceURL == nil {
            existing.descriptionSourceURL = parsed.descriptionSourceURL
        }
        if existing.detailRetrievedAt == nil {
            existing.detailRetrievedAt = parsed.detailRetrievedAt
        }
        return existing
    }
}

struct CatalogRefreshProgress: Sendable {
    var current: Int
    var total: Int
    var programTitle: String
}

private struct CourseDetailEnrichment: Sendable {
    var courseID: String
    var description: String
    var sourceURL: URL
    var retrievedAt: Date
}

private struct SeedCatalog: Decodable {
    var source: SeedSource
    var programs: [SeedProgram]
    var courses: [SeedCourse]
    var requirementsByProgram: [String: [RequirementCategory]]
    var concentrationsByProgram: [String: [Concentration]]?
    var apCreditRules: [TransferCreditRule]

    static func decode(from data: Data) throws -> SeedCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SeedCatalog.self, from: data)
    }

    func catalog() -> Catalog {
        let catalogSource = CatalogSource(
            catalogYear: source.catalogYear,
            issueDate: source.issueDate,
            retrievedDate: source.retrievedDate,
            sourceURLs: source.sourceURLs,
            retrievalNotes: source.retrievalNotes
        )

        let mappedPrograms = programs.map { seed -> Program in
            let reqs = requirementsByProgram[seed.id] ?? []
            let concentrations = concentrationsByProgram?[seed.id] ?? []
            return Program(
                id: seed.id,
                title: seed.title,
                degreeType: seed.degreeType,
                kind: seed.kind,
                college: seed.college,
                department: seed.department,
                catalogPage: seed.catalogPage,
                totalCredits: seed.kind == .major ? 120 : nil,
                requirements: reqs,
                concentrations: concentrations,
                verificationStatus: seed.verificationStatus ?? (reqs.isEmpty ? .unverified : .partial),
                requirementDataComplete: seed.requirementDataComplete ?? false,
                sourceNote: seed.sourceNote ?? "Listed in the JMU 2025-2026 Undergraduate Catalog table of contents."
            )
        }

        return Catalog(source: catalogSource, programs: mappedPrograms, courses: courses.map(\.course), apCreditRules: apCreditRules)
    }
}

private struct SeedSource: Decodable {
    var catalogYear: String
    var issueDate: Date
    var retrievedDate: Date
    var sourceURLs: [URL]
    var retrievalNotes: [String]
}

private struct SeedProgram: Decodable {
    var id: String
    var title: String
    var degreeType: String?
    var kind: ProgramKind
    var college: String
    var department: String
    var catalogPage: Int?
    var requirementDataComplete: Bool?
    var verificationStatus: VerificationStatus?
    var sourceNote: String?
}

private struct SeedCourse: Decodable {
    var id: String
    var code: String
    var title: String
    var credits: Int
    var availability: Set<SemesterTerm>?
    var prerequisites: [String]
    var verificationStatus: VerificationStatus?

    var course: Course {
        Course(
            id: id,
            code: code,
            title: title,
            credits: credits,
            availability: availability,
            prerequisites: prerequisites,
            verificationStatus: verificationStatus ?? .unverified,
            registrarURL: nil
        )
    }
}

private extension String {
    var normalizedProgramTitle: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var programSlug: String {
        let lower = normalizedProgramTitle
        let allowed = lower.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(allowed)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "program" : collapsed
    }
}
