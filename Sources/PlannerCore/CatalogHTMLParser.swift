import Foundation

public struct HTMLProgramIndexEntry: Hashable, Sendable {
    public var title: String
    public var kind: ProgramKind
    public var sectionTitle: String
    public var sourceURL: URL
    public var printURL: URL
    public var catoid: String
    public var poid: String
    public var degreeType: String?

    public init(
        title: String,
        kind: ProgramKind,
        sectionTitle: String,
        sourceURL: URL,
        printURL: URL,
        catoid: String,
        poid: String,
        degreeType: String?
    ) {
        self.title = title
        self.kind = kind
        self.sectionTitle = sectionTitle
        self.sourceURL = sourceURL
        self.printURL = printURL
        self.catoid = catoid
        self.poid = poid
        self.degreeType = degreeType
    }
}

public struct HTMLProgramRequirements: Sendable {
    public var title: String?
    public var requirements: [RequirementCategory]
    public var concentrations: [Concentration]
    public var courses: [Course]
    public var totalCredits: Int?

    public init(
        title: String?,
        requirements: [RequirementCategory],
        concentrations: [Concentration] = [],
        courses: [Course],
        totalCredits: Int?
    ) {
        self.title = title
        self.requirements = requirements
        self.concentrations = concentrations
        self.courses = courses
        self.totalCredits = totalCredits
    }
}

public struct HTMLCourseDetail: Equatable, Sendable {
    public var description: String?
    public var prerequisiteText: String?

    public init(description: String?, prerequisiteText: String?) {
        self.description = description
        self.prerequisiteText = prerequisiteText
    }
}

public struct JMUHTMLCatalogParser: Sendable {
    private let baseURL = URL(string: "https://catalog.jmu.edu/")!

    public init() {}

    public func parseProgramsOfStudy(_ html: String) -> [HTMLProgramIndexEntry] {
        let sectionPattern = #"(?is)<p\b[^>]*>\s*<strong>(.*?)</strong>\s*</p>\s*<ul\s+class="program-list"\s*>(.*?)</ul>"#
        let linkPattern = #"(?is)<a\s+href="([^"]*preview_program\.php[^"]*)"[^>]*>(.*?)</a>"#
        var entries: [HTMLProgramIndexEntry] = []

        for section in html.matches(for: sectionPattern) {
            guard section.count >= 3 else { continue }
            let sectionTitle = HTMLCleaner.clean(section[1])
            guard let kind = programKind(forSectionTitle: sectionTitle) else { continue }

            for link in section[2].matches(for: linkPattern) {
                guard link.count >= 3 else { continue }
                let href = HTMLCleaner.decodeEntities(in: link[1])
                let title = HTMLCleaner.clean(link[2])
                guard let catoid = queryValue("catoid", in: href),
                      let poid = queryValue("poid", in: href),
                      let sourceURL = URL(string: "preview_program.php?catoid=\(catoid)&poid=\(poid)&returnto=3541", relativeTo: baseURL)?.absoluteURL,
                      let printURL = URL(string: "preview_program.php?catoid=\(catoid)&poid=\(poid)&returnto=3541&print", relativeTo: baseURL)?.absoluteURL
                else {
                    continue
                }

                entries.append(HTMLProgramIndexEntry(
                    title: title,
                    kind: kind,
                    sectionTitle: sectionTitle,
                    sourceURL: sourceURL,
                    printURL: printURL,
                    catoid: catoid,
                    poid: poid,
                    degreeType: degreeType(from: title, kind: kind)
                ))
            }
        }

        return entries
    }

    public func parseProgramRequirements(_ html: String, kind: ProgramKind, sourceURL: URL) -> HTMLProgramRequirements {
        let title = parseTitle(from: html)
        let catoid = queryValue("catoid", in: sourceURL.absoluteString) ?? "62"
        let requirementSlice = requirementsSlice(in: html, kind: kind) ?? ""
        var coursesByID: [String: Course] = [:]
        var usedCategoryIDs: Set<String> = []
        var categories: [RequirementCategory] = []
        let blocks = requirementBlocks(in: requirementSlice)
        let split = splitConcentrationBlocks(blocks)

        for block in split.shared {
            if let parsed = category(from: block, catoid: catoid, usedCategoryIDs: &usedCategoryIDs, coursesByID: &coursesByID) {
                categories.append(parsed)
            }
        }

        var usedConcentrationIDs: Set<String> = []
        let concentrations = split.concentrationRuns.compactMap { run -> Concentration? in
            var usedRequirementIDs: Set<String> = []
            var requirements: [RequirementCategory] = []
            for block in run.blocks {
                if let parsed = category(from: block, catoid: catoid, usedCategoryIDs: &usedRequirementIDs, coursesByID: &coursesByID) {
                    requirements.append(parsed)
                }
            }
            guard !requirements.isEmpty else { return nil }
            return Concentration(
                id: uniqueID(slug(from: run.name), used: &usedConcentrationIDs),
                name: run.name,
                requirements: requirements,
                verificationStatus: .partial
            )
        }

        return HTMLProgramRequirements(
            title: title,
            requirements: categories,
            concentrations: concentrations,
            courses: coursesByID.values.sorted { $0.code < $1.code },
            totalCredits: parseProgramTotal(from: html)
        )
    }

    public func parseCourseDetail(_ html: String) -> HTMLCourseDetail {
        // The live JMU `preview_course.php` popup format does not wrap the
        // description in `<p>` tags. Try the popup-format extractor first; if it
        // finds a description, return it. Otherwise fall through to the
        // `<acalog-page-content>` / `<p>` extractor that handles the print view.
        if let popupDetail = parsePopupCourseDetail(html) {
            return popupDetail
        }

        let content = courseDetailContent(in: html)
        let paragraphs = paragraphTexts(in: content)
        var descriptionParts: [String] = []
        var prerequisiteText: String?

        for paragraph in paragraphs {
            let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if isCourseDetailMetadata(text) {
                continue
            }

            if isPrerequisiteLine(text) {
                prerequisiteText = text
                continue
            }

            descriptionParts.append(text)
        }

        let description = descriptionParts
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return HTMLCourseDetail(
            description: description.isEmpty ? nil : description,
            prerequisiteText: prerequisiteText
        )
    }

    /// Handles the live JMU popup-style `preview_course.php` page. Format:
    ///
    ///     <h1 id='course_preview_title'>CODE 123. Title</h1>
    ///     <br><em><strong>Credits</strong></em> <em>3.00</em> ... <hr>
    ///     The actual course description as bare text, possibly with
    ///     <a> links to other programs or courses.
    ///     <br><br><br><hr>
    ///
    /// Returns nil if the popup-style markers are not present, so the caller
    /// can fall back to the print-view parser.
    private func parsePopupCourseDetail(_ html: String) -> HTMLCourseDetail? {
        let pattern = #"(?is)<h1[^>]*id=['\"]course_preview_title['\"][^>]*>.*?</h1>(.*?)(?:<hr\b[^>]*>\s*<div|<hr\b[^>]*>\s*$|</body>)"#
        guard let match = html.firstMatch(for: pattern), match.count > 1 else {
            return nil
        }
        var segment = match[1]
        // Drop the leading metadata block: <br><em><strong>Credits</strong></em>...<hr>
        if let metaEnd = segment.range(of: #"(?is)<hr\b[^>]*>"#, options: .regularExpression) {
            segment = String(segment[metaEnd.upperBound...])
        }
        // Strip trailing print/share button blocks that sit after the description.
        if let printStart = segment.range(of: #"(?is)<div[^>]*float:\s*right"#, options: .regularExpression) {
            segment = String(segment[..<printStart.lowerBound])
        }

        let cleaned = HTMLCleaner.clean(segment)
        var description: String? = cleaned.isEmpty ? nil : cleaned
        var prerequisiteText: String?

        // If a prerequisite sentence is embedded inline, split it out.
        if let desc = description,
           let range = desc.range(of: #"(?is)Prerequisite\(s\)?:.*?(?=\.|$)"#, options: .regularExpression) {
            let preq = String(desc[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            prerequisiteText = preq
            let stripped = desc.replacingCharacters(in: range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            description = stripped.isEmpty ? nil : stripped
        }

        guard description != nil || prerequisiteText != nil else { return nil }
        return HTMLCourseDetail(description: description, prerequisiteText: prerequisiteText)
    }

    private func courseDetailContent(in html: String) -> String {
        if let match = html.firstMatch(for: #"(?is)<td\b[^>]*id="acalog-page-content"[^>]*>(.*?)</td>"#),
           match.count > 1 {
            return match[1]
        }

        if let match = html.firstMatch(for: #"(?is)<body\b[^>]*>(.*?)</body>"#),
           match.count > 1 {
            return match[1]
        }

        return html
    }

    private func paragraphTexts(in html: String) -> [String] {
        let paragraphs = html.matches(for: #"(?is)<p\b[^>]*>(.*?)</p>"#)
            .compactMap { match -> String? in
                guard match.count > 1 else { return nil }
                let text = HTMLCleaner.clean(match[1])
                return text.isEmpty ? nil : text
            }

        if !paragraphs.isEmpty {
            return paragraphs
        }

        let fallback = HTMLCleaner.clean(html)
        return fallback.isEmpty ? [] : [fallback]
    }

    private func isCourseDetailMetadata(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("credits:")
            || lower.hasPrefix("credit hours:")
            || lower.hasPrefix("repeat status:")
            || lower.hasPrefix("grading basis:")
            || lower.hasPrefix("course id:")
            || lower.hasPrefix("peoplesoft course id:")
    }

    private func isPrerequisiteLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("prerequisite")
            || lower.hasPrefix("prerequisites")
            || lower.hasPrefix("prerequisite(s)")
    }

    private func programKind(forSectionTitle title: String) -> ProgramKind? {
        let normalized = title.lowercased()
        if normalized == "major" { return .major }
        if normalized == "minor" || normalized.contains("minor") { return .minor }
        return nil
    }

    private func queryValue(_ name: String, in text: String) -> String? {
        let pattern = #"(?i)(?:\?|&|&amp;)\#(name)=([^&#"]+)"#
        return text.firstMatch(for: pattern)?.dropFirst().first
    }

    private func degreeType(from title: String, kind: ProgramKind) -> String? {
        guard kind == .major else { return nil }
        let knownDegrees = [
            "B.B.A.", "B.S.N.", "B.S.W.", "B.I.S.", "B.F.A.", "B.M.",
            "B.A.", "B.S.", "Dual Degree"
        ]
        return knownDegrees.first { title.hasSuffix($0) || title.contains(", \($0)") }
    }

    private func parseTitle(from html: String) -> String? {
        guard let match = html.firstMatch(for: #"(?is)<h1\b[^>]*id="acalog-content"[^>]*>(.*?)</h1>"#),
              match.count > 1
        else {
            return nil
        }
        return HTMLCleaner.clean(match[1])
    }

    private func requirementsSlice(in html: String, kind: ProgramKind) -> String? {
        let anchors: [String]
        switch kind {
        case .major:
            anchors = ["DegreeAndMajorRequirements", "MajorRequirements", "DegreeRequirements"]
        case .minor:
            anchors = ["MinorRequirements", "Requirements"]
        case .certificate:
            anchors = ["CertificateRequirements", "Requirements"]
        }

        let start = anchors.compactMap { anchorStart(named: $0, in: html) }.min()
            ?? firstRequirementHeading(in: html)
        guard let start else { return nil }

        let remainder = html[start..<html.endIndex]
        let end = stopHeadingStart(in: remainder).map { html.index(start, offsetBy: $0) } ?? html.endIndex
        return String(html[start..<end])
    }

    private func anchorStart(named name: String, in html: String) -> String.Index? {
        html.range(of: #"<a\s+name="\#(name)""#, options: [.regularExpression, .caseInsensitive])?.lowerBound
    }

    private func firstRequirementHeading(in html: String) -> String.Index? {
        let headingPattern = #"(?is)<h2\b[^>]*>.*?</h2>"#
        for match in html.matchesWithRanges(for: headingPattern) {
            let text = HTMLCleaner.clean(match.match)
            let lower = text.lowercased()
            if lower.contains("requirements") && !lower.contains("admission") && !lower.contains("retention") {
                return match.range.lowerBound
            }
        }
        return nil
    }

    private func stopHeadingStart(in html: Substring) -> Int? {
        let source = String(html)
        let headingPattern = #"(?is)<h2\b[^>]*>.*?</h2>"#
        for match in source.matchesWithRanges(for: headingPattern) {
            let text = HTMLCleaner.clean(match.match).lowercased()
            if text.contains("recommended schedule")
                || text.contains("sample plan")
                || text.contains("additional information")
                || text.contains("program total") {
                return source.distance(from: source.startIndex, to: match.range.lowerBound)
            }
        }
        return nil
    }

    private struct RequirementBlock {
        var level: Int
        var heading: String
        var body: String
    }

    private func requirementBlocks(in html: String) -> [RequirementBlock] {
        let markerPattern = #"(?is)<div\s+class="acalog-core"\s*>\s*<h[2-5]\b[^>]*>"#
        let markers = html.matchesWithRanges(for: markerPattern).map(\.range)

        return markers.enumerated().compactMap { index, markerRange in
            let segmentEnd = index + 1 < markers.count ? markers[index + 1].lowerBound : html.endIndex
            let segment = String(html[markerRange.upperBound..<segmentEnd])
            guard let headingEnd = segment.range(of: #"(?is)</h[2-5]>"#, options: .regularExpression) else {
                return nil
            }

            let markerMatch = String(html[markerRange]).firstMatch(for: #"(?is)<h([2-5])\b"#)
            let level = markerMatch?.dropFirst().first.flatMap(Int.init) ?? 3
            let heading = HTMLCleaner.clean(String(segment[..<headingEnd.lowerBound]))
            guard !heading.isEmpty else { return nil }
            let body = String(segment[headingEnd.upperBound...])
                .replacingOccurrences(of: #"(?is)^\s*<hr\s*/?>"#, with: "", options: .regularExpression)
            return RequirementBlock(level: level, heading: heading, body: body)
        }
    }

    private func splitConcentrationBlocks(_ blocks: [RequirementBlock]) -> (shared: [RequirementBlock], concentrationRuns: [(name: String, blocks: [RequirementBlock])]) {
        guard let concentrationIndex = blocks.firstIndex(where: isConcentrationSectionHeading) else {
            return (blocks, [])
        }

        let sectionLevel = blocks[concentrationIndex].level
        let shared = Array(blocks[..<concentrationIndex])
        let tail = Array(blocks[(concentrationIndex + 1)...])
        var runs: [(name: String, blocks: [RequirementBlock])] = []
        var currentName: String?
        var currentBlocks: [RequirementBlock] = []

        for block in tail {
            guard block.level > sectionLevel else { break }
            if isConcreteConcentrationHeading(block.heading) {
                if let currentName, !currentBlocks.isEmpty {
                    runs.append((currentName, currentBlocks))
                }
                currentName = block.heading
                currentBlocks = [block]
            } else if currentName != nil {
                currentBlocks.append(block)
            }
        }

        if let currentName, !currentBlocks.isEmpty {
            runs.append((currentName, currentBlocks))
        }

        return (shared, runs)
    }

    private func isConcentrationSectionHeading(_ block: RequirementBlock) -> Bool {
        let lower = block.heading.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "concentrations" || lower == "required concentration" || lower == "required concentrations"
    }

    private func isConcreteConcentrationHeading(_ heading: String) -> Bool {
        let lower = heading.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower != "concentrations" && lower.hasSuffix("concentration")
    }

    private func category(
        from block: RequirementBlock,
        catoid: String,
        usedCategoryIDs: inout Set<String>,
        coursesByID: inout [String: Course]
    ) -> RequirementCategory? {
        let courseItems = courseItems(in: block.body, catoid: catoid)
        let courses = courseItems.compactMap { item -> Course? in
            if case .course(let course) = item { return course }
            return nil
        }

        // Skip non-requirement sections (descriptions, totals, admission, etc).
        // Umbrella headings like "Major Requirements" are skipped ONLY when their
        // body has no course rows — some catalog pages place the core required
        // courses directly under the umbrella heading with no child acalog-core div.
        guard !shouldIgnoreRequirementHeading(block.heading, hasCourses: !courses.isEmpty) else {
            return nil
        }

        for course in courses {
            coursesByID[course.id] = course
        }

        let selectionCount = choiceSelectionCount(heading: block.heading, body: block.body)
        let requiredCredits = parseCredits(from: block.heading)
            ?? parseTotalCreditsFromBody(block.body)
            ?? inferredCredits(for: courseItems, selectionCount: selectionCount)

        guard requiredCredits > 0 || !courses.isEmpty else { return nil }

        let options = courseOptions(
            from: courseItems,
            selectionCount: selectionCount
        )
        let categoryID = uniqueID(slug(from: block.heading), used: &usedCategoryIDs)
        let note = note(for: block, options: options, courses: courses)

        return RequirementCategory(
            id: categoryID,
            name: block.heading,
            requiredCredits: requiredCredits,
            courseOptions: options,
            verificationStatus: .partial,
            note: note
        )
    }

    private func shouldIgnoreRequirementHeading(_ heading: String, hasCourses: Bool) -> Bool {
        let lower = heading.lowercased()
        if lower.contains("footnote") { return true }
        if lower.contains("program description") { return true }
        if lower.contains("admission") || lower.contains("retention") { return true }
        if lower.contains("progressing in the major") { return true }
        if lower.contains("recommended schedule") || lower.contains("sample plan") { return true }
        if lower.contains("first year") || lower.contains("second year") || lower.contains("third year") || lower.contains("fourth year") {
            return true
        }
        if lower.contains("semester") && (lower.contains("fall") || lower.contains("spring")) { return true }
        if lower.contains("total") && lower.contains("credit") { return true }
        if lower.contains("additional information") { return true }
        if lower.contains("u.s. government requirements") { return true }
        if lower.contains("certificates") { return true }
        // Umbrella headings: skip only when they have no inline course list.
        // Some pages tuck the entire core course list directly under these.
        if !hasCourses {
            if lower == "major requirements" || lower == "minor requirements" { return true }
            if lower == "degree and major requirements" { return true }
        }
        return false
    }

    private enum CourseItem {
        case course(Course)
        case marker(String)
    }

    private func courseItems(in html: String, catoid: String) -> [CourseItem] {
        let listItemPattern = #"(?is)<li\b([^>]*)>(.*?)</li>"#
        return html.matches(for: listItemPattern).compactMap { match in
            guard match.count >= 3 else { return nil }
            let attributes = match[1]
            let body = match[2]
            let text = HTMLCleaner.clean(body).lowercased()

            if text == "or" {
                return .marker("or")
            }

            guard attributes.contains("acalog-course") else {
                return text == "or" ? .marker("or") : nil
            }

            guard let course = parseCourse(fromListItem: body, catoid: catoid) else {
                return nil
            }
            return .course(course)
        }
    }

    private func parseCourse(fromListItem html: String, catoid: String) -> Course? {
        guard let labelMatch = html.firstMatch(for: #"(?is)<a\b[^>]*>(.*?)</a>"#),
              labelMatch.count > 1
        else {
            return nil
        }

        let label = HTMLCleaner.clean(labelMatch[1])
        guard let parsedLabel = parseCourseLabel(label) else { return nil }
        let credits = parseCredits(from: html)
        let coid = html.firstMatch(for: #"(?i)showCourse\('\d+',\s*'(\d+)'"#)?.dropFirst().first
            ?? html.firstMatch(for: #"(?i)coid=(\d+)"#)?.dropFirst().first
        let registrarURL = coid.flatMap { URL(string: "preview_course.php?catoid=\(catoid)&coid=\($0)&print", relativeTo: baseURL)?.absoluteURL }

        return Course(
            id: parsedLabel.id,
            code: parsedLabel.code,
            title: parsedLabel.title,
            credits: credits ?? 3,
            availability: nil,
            prerequisites: [],
            verificationStatus: .partial,
            registrarURL: registrarURL
        )
    }

    private func parseCourseLabel(_ label: String) -> (id: String, code: String, title: String)? {
        let stripped = label.replacingOccurrences(of: #"\s+\[[^\]]+\]"#, with: "", options: .regularExpression)
        guard let match = stripped.firstMatch(for: #"^([A-Z]{2,5})\s+(\d{3}[A-Z]?)\.\s*(.+)$"#),
              match.count >= 4
        else {
            return nil
        }
        let subject = match[1]
        let number = match[2]
        let title = match[3].trimmingCharacters(in: .whitespacesAndNewlines)
        return ("\(subject)\(number)", "\(subject) \(number)", title)
    }

    private func parseCredits(from text: String) -> Int? {
        let cleaned = HTMLCleaner.clean(text)
        let patterns = [
            #"(?i):\s*(\d+)(?:\s*-\s*\d+)?\s+Credit\s+Hours"#,
            #"(?i)Credits?:\s*(\d+(?:\.\d+)?)"#,
            #"(?i)(\d+)(?:\s*-\s*\d+)?\s+Credit\s+Hours"#
        ]

        for pattern in patterns {
            guard let match = cleaned.firstMatch(for: pattern),
                  match.count > 1,
                  let value = Double(match[1])
            else {
                continue
            }
            return max(Int(value.rounded(.up)), 0)
        }
        return nil
    }

    /// Block-body credit parser. Excludes the per-course "Credits: 3.00" pattern
    /// so we never mistake a course row's credit field for the section total.
    private func parseTotalCreditsFromBody(_ body: String) -> Int? {
        let cleaned = HTMLCleaner.clean(body)
        let patterns = [
            #"(?i):\s*(\d+)(?:\s*-\s*\d+)?\s+Credit\s+Hours"#,
            #"(?i)(\d+)(?:\s*-\s*\d+)?\s+Credit\s+Hours"#
        ]
        for pattern in patterns {
            guard let match = cleaned.firstMatch(for: pattern),
                  match.count > 1,
                  let value = Double(match[1])
            else { continue }
            return max(Int(value.rounded(.up)), 0)
        }
        return nil
    }

    private func inferredCredits(for items: [CourseItem], selectionCount: Int?) -> Int {
        let courses = items.compactMap { item -> Course? in
            if case .course(let course) = item { return course }
            return nil
        }

        if let selectionCount {
            return courses.prefix(selectionCount).reduce(0) { $0 + $1.credits }
        }

        return courseOptions(from: items, selectionCount: nil).reduce(0) { total, option in
            total + (option.compactMap { courseID in courses.first(where: { $0.id == courseID })?.credits }.max() ?? 0)
        }
    }

    private func isChoiceRequirement(heading: String, body: String) -> Bool {
        choiceSelectionCount(heading: heading, body: body) != nil
    }

    private func choiceSelectionCount(heading: String, body: String) -> Int? {
        let text = HTMLCleaner.clean("\(heading) \(body)").lowercased()
        if text.contains("one of the following") || text.contains("select one") {
            return 1
        }

        let wordValues = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5]
        for (word, value) in wordValues where text.contains("choose \(word)") || text.contains("select \(word)") {
            return value
        }

        guard let match = text.firstMatch(for: #"(?i)(?:choose|select)\s+(\d+)"#),
              match.count > 1
        else {
            return nil
        }
        return Int(match[1])
    }

    private func courseOptions(from items: [CourseItem], selectionCount: Int?) -> [[String]] {
        let courseIDs = items.compactMap { item -> String? in
            if case .course(let course) = item { return course.id }
            return nil
        }
        guard !courseIDs.isEmpty else { return [] }

        if selectionCount == 1 {
            return [unique(courseIDs)]
        }

        if let selectionCount, selectionCount > 1 {
            return unique(courseIDs).prefix(selectionCount).map { [$0] }
        }

        var options: [[String]] = []
        var index = 0
        while index < items.count {
            guard case .course(let course) = items[index] else {
                index += 1
                continue
            }

            var group = [course.id]
            var cursor = index
            while cursor + 2 < items.count,
                  case .marker(let marker) = items[cursor + 1],
                  marker.lowercased() == "or",
                  case .course(let nextCourse) = items[cursor + 2] {
                group.append(nextCourse.id)
                cursor += 2
            }

            options.append(unique(group))
            index = cursor + 1
        }

        return uniqueOptions(options)
    }

    private func note(for block: RequirementBlock, options: [[String]], courses: [Course]) -> String? {
        let text = HTMLCleaner.clean(block.body)
        if options.isEmpty, !text.isEmpty {
            return "Catalog text did not provide a fixed course list. Review this requirement with an advisor."
        }
        if isChoiceRequirement(heading: block.heading, body: block.body) || options.contains(where: { $0.count > 1 }) {
            return "Parsed from JMU catalog HTML as a choice requirement. Confirm eligible choices with an advisor."
        }
        if courses.isEmpty {
            return "Parsed from JMU catalog HTML."
        }
        return nil
    }

    private func parseProgramTotal(from html: String) -> Int? {
        guard let match = HTMLCleaner.clean(html).firstMatch(for: #"(?i)(?:Program\s+)?Total:\s*(\d+)(?:\s*-\s*\d+)?\s+Credit\s+Hours"#),
              match.count > 1
        else {
            return nil
        }
        return Int(match[1])
    }

    private func slug(from text: String) -> String {
        let lower = text.lowercased()
        let allowed = lower.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(allowed)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "requirement" : collapsed
    }

    private func uniqueID(_ base: String, used: inout Set<String>) -> String {
        var candidate = base
        var suffix = 2
        while used.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        used.insert(candidate)
        return candidate
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private func uniqueOptions(_ options: [[String]]) -> [[String]] {
        var seen: Set<[String]> = []
        return options.filter { seen.insert($0).inserted }
    }
}

private enum HTMLCleaner {
    static func clean(_ html: String) -> String {
        let withoutScripts = html
            .replacingOccurrences(of: #"(?is)<script\b.*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<span\s+style="display:\s*none\s*!important"[^>]*>.*?</span>"#, with: " ", options: .regularExpression)
        let withoutTags = withoutScripts.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        let decoded = decodeEntities(in: withoutTags)
        return decoded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(in text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#8220;", with: "\"")
            .replacingOccurrences(of: "&#8221;", with: "\"")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&rsquo;", with: "'")
            .replacingOccurrences(of: "&ndash;", with: "-")
            .replacingOccurrences(of: "&mdash;", with: "-")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        let numericPattern = #"&#(\d+);"#
        for match in result.matches(for: numericPattern).reversed() {
            guard match.count > 1,
                  let value = UInt32(match[1]),
                  let scalar = UnicodeScalar(value)
            else {
                continue
            }
            result = result.replacingOccurrences(of: match[0], with: String(Character(scalar)))
        }

        return result
    }
}

private extension String {
    func matches(for pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: self) else { return nil }
                return String(self[range])
            }
        }
    }

    func firstMatch(for pattern: String) -> [String]? {
        matches(for: pattern).first
    }

    func matchesWithRanges(for pattern: String) -> [(match: String, range: Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: self) else { return nil }
            return (String(self[swiftRange]), swiftRange)
        }
    }
}
