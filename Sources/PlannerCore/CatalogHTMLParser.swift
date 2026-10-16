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
    public var concentrationSelectionRequired: Bool
    public var courses: [Course]
    public var totalCredits: Int?

    public init(
        title: String?,
        requirements: [RequirementCategory],
        concentrations: [Concentration] = [],
        concentrationSelectionRequired: Bool = false,
        courses: [Course],
        totalCredits: Int?
    ) {
        self.title = title
        self.requirements = requirements
        self.concentrations = concentrations
        self.concentrationSelectionRequired = concentrationSelectionRequired
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
        if html.contains("filter-items") && html.contains("/programs/") {
            return parseModernProgramsOfStudy(html)
        }

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

    private func parseModernProgramsOfStudy(_ html: String) -> [HTMLProgramIndexEntry] {
        let itemPattern = #"(?is)<li\b[^>]*class="[^"]*\bitem\b[^"]*"[^>]*>\s*<a\s+href="(/programs/[^"]+/)"[^>]*>(.*?)</a>\s*</li>"#
        var seenPaths: Set<String> = []
        var entries: [HTMLProgramIndexEntry] = []

        for item in html.matches(for: itemPattern) {
            guard item.count >= 3 else { continue }
            let path = HTMLCleaner.decodeEntities(in: item[1])
            guard seenPaths.insert(path).inserted else { continue }
            let body = item[2]
            let keywords = body.matches(for: #"(?is)<span\b[^>]*class="[^"]*\bkeyword\b[^"]*"[^>]*>(.*?)</span>"#)
                .compactMap { $0.count > 1 ? HTMLCleaner.clean($0[1]) : nil }
            guard keywords.contains("Undergraduate") else { continue }

            let kind: ProgramKind
            if keywords.contains("Bachelor's Degrees") {
                kind = .major
            } else if keywords.contains("Minors") || keywords.contains("Cross-Disciplinary Minors") {
                kind = .minor
            } else {
                continue
            }

            guard let titleMatch = body.firstMatch(for: #"(?is)<span\b[^>]*class="[^"]*\btitle\b[^"]*"[^>]*>(.*?)</span>"#),
                  titleMatch.count > 1,
                  let url = URL(string: path, relativeTo: baseURL)?.absoluteURL
            else { continue }

            let title = HTMLCleaner.clean(titleMatch[1])
            let slug = path.split(separator: "/").last.map(String.init) ?? title
            entries.append(HTMLProgramIndexEntry(
                title: title,
                kind: kind,
                sectionTitle: "Undergraduate Programs",
                sourceURL: url,
                printURL: url,
                catoid: "2026-2027",
                poid: slug,
                degreeType: degreeType(from: title, kind: kind)
            ))
        }

        return entries
    }

    public func parseProgramRequirements(_ html: String, kind: ProgramKind, sourceURL: URL) -> HTMLProgramRequirements {
        let title = parseTitle(from: html)
        let catoid = queryValue("catoid", in: sourceURL.absoluteString) ?? "62"
        let requirementSlice = modernRequirementsSlice(in: html) ?? requirementsSlice(in: html, kind: kind) ?? ""
        var coursesByID: [String: Course] = [:]
        var usedCategoryIDs: Set<String> = []
        var categories: [RequirementCategory] = []
        let blocks = requirementBlocks(in: requirementSlice)
        var split = splitConcentrationBlocks(blocks)

        // "Choose one of the following options" groups of "Option N:" blocks
        // are alternatives: each option becomes its own track, inside the
        // concentration that holds it or, with none, beside the shared core.
        if split.concentrationRuns.isEmpty {
            if let options = optionVariants(in: split.shared) {
                split.shared = options.common
                split.concentrationRuns = options.variants
                split.concentrationSelectionRequired = true
            }
        } else {
            split.concentrationRuns = split.concentrationRuns.flatMap { run in
                guard let options = optionVariants(in: run.blocks) else { return [run] }
                return options.variants.map { variant in
                    (name: "\(run.name) - \(variant.name)", blocks: options.common + variant.blocks)
                }
            }
        }

        for block in split.shared {
            if let parsed = category(from: block, catoid: catoid, usedCategoryIDs: &usedCategoryIDs, coursesByID: &coursesByID) {
                // Once requirements split into tracks, a course-less row that
                // points at them ("two options ... listed below") is covered
                // by each track's own requirements.
                if !split.concentrationRuns.isEmpty,
                   parsed.courseOptions.isEmpty,
                   parsed.name.lowercased().contains("option") {
                    continue
                }
                categories.append(parsed)
            }
        }

        var usedConcentrationIDs: Set<String> = []
        let concentrations = split.concentrationRuns.compactMap { run -> Concentration? in
            var usedRequirementIDs: Set<String> = []
            var parsedRequirements: [(block: RequirementBlock, category: RequirementCategory)] = []
            for block in run.blocks {
                if let parsed = category(from: block, catoid: catoid, usedCategoryIDs: &usedRequirementIDs, coursesByID: &coursesByID) {
                    parsedRequirements.append((block, parsed))
                }
            }
            // The track's own heading with no course list ("Additional
            // Requirements for Students Not Seeking ...") only restates what
            // the requirements under it add up to.
            if parsedRequirements.count > 1,
               let first = parsedRequirements.first,
               first.block.isStructuralHeading,
               first.category.courseOptions.isEmpty,
               run.blocks.first?.heading == first.block.heading {
                parsedRequirements.removeFirst()
            }
            let requirements = adjustedConcentrationRequirements(
                from: mergingOptionGroups(parsedRequirements),
                totalCredits: concentrationTotalCredits(in: run.blocks)
            )
            guard !requirements.isEmpty else { return nil }
            let cleanName = JMUHTMLCatalogParser.cleanConcentrationName(run.name)
            let displayName = cleanName.isEmpty ? run.name : cleanName
            return Concentration(
                id: uniqueID(slug(from: displayName), used: &usedConcentrationIDs),
                name: displayName,
                requirements: requirements,
                verificationStatus: .partial
            )
        }

        return HTMLProgramRequirements(
            title: title,
            requirements: categories,
            concentrations: concentrations,
            concentrationSelectionRequired: split.concentrationSelectionRequired,
            courses: coursesByID.values.sorted { $0.code < $1.code },
            totalCredits: parseProgramTotal(from: html)
        )
    }

    private func adjustedConcentrationRequirements(
        from parsed: [(block: RequirementBlock, category: RequirementCategory)],
        totalCredits: Int?
    ) -> [RequirementCategory] {
        var requirements = parsed.map(\.category)
        guard let totalCredits, totalCredits > 0 else { return requirements }
        guard requirements.reduce(0, { $0 + $1.requiredCredits }) > totalCredits else { return requirements }

        let adjustable = parsed.indices.filter { index in
            let lowerName = parsed[index].category.name.lowercased()
            return lowerName.contains("elective") && parseCredits(from: parsed[index].block.heading) == nil
        }
        guard !adjustable.isEmpty else { return requirements }

        let fixedCredits = parsed.indices.reduce(0) { total, index in
            adjustable.contains(index) ? total : total + requirements[index].requiredCredits
        }
        let remainingCredits = totalCredits - fixedCredits
        guard remainingCredits > 0 else { return requirements }

        if adjustable.count == 1, let index = adjustable.first {
            requirements[index].requiredCredits = min(requirements[index].requiredCredits, remainingCredits)
            return requirements
        }

        let perAdjustable = max(remainingCredits / adjustable.count, 1)
        for index in adjustable {
            requirements[index].requiredCredits = min(requirements[index].requiredCredits, perAdjustable)
        }
        return requirements
    }

    private func concentrationTotalCredits(in blocks: [RequirementBlock]) -> Int? {
        let tableTotals = blocks.compactMap { block -> Int? in
            guard block.heading.lowercased().hasPrefix("catalog table total") else { return nil }
            return parseCredits(from: block.heading)
        }
        if !tableTotals.isEmpty {
            return tableTotals.reduce(0, +)
        }

        return blocks.compactMap { block -> Int? in
            let lower = block.heading.lowercased()
            guard lower.contains("concentration"), lower.contains("total") else { return nil }
            return parseCredits(from: block.heading)
        }.last
    }

    public func parseCourseDetail(_ html: String) -> HTMLCourseDetail {
        if let modernDetail = parseModernCourseDetail(html) {
            return modernDetail
        }

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

    private func parseModernCourseDetail(_ html: String) -> HTMLCourseDetail? {
        guard html.contains("search-courseresult"),
              let article = html.firstMatch(for: #"(?is)<article\b[^>]*class="[^"]*\bsearch-courseresult\b[^"]*"[^>]*>(.*?)</article>"#),
              article.count > 1
        else { return nil }

        let description = article[1]
            .firstMatch(for: #"(?is)<div\b[^>]*class="[^"]*\bcourseblockdesc\b[^"]*"[^>]*>(.*?)</div>"#)
            .flatMap { $0.count > 1 ? HTMLCleaner.clean($0[1]) : nil }
        let prerequisiteText = article[1]
            .firstMatch(for: #"(?is)<div\b[^>]*class="[^"]*\bcourseblockextra\b[^"]*"[^>]*>(.*?)</div>"#)
            .flatMap { $0.count > 1 ? HTMLCleaner.clean($0[1]) : nil }

        guard description?.isEmpty == false || prerequisiteText?.isEmpty == false else { return nil }
        return HTMLCourseDetail(description: description, prerequisiteText: prerequisiteText)
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
        guard let match = html.firstMatch(for: #"(?is)<h1\b[^>]*(?:id="acalog-content"|class="[^"]*\bpage-title\b[^"]*")[^>]*>(.*?)</h1>"#),
              match.count > 1
        else {
            return nil
        }
        return HTMLCleaner.clean(match[1])
    }

    private func modernRequirementsSlice(in html: String) -> String? {
        guard let start = html.range(of: #"<div\b[^>]*id="requirementstextcontainer"[^>]*>"#, options: [.regularExpression, .caseInsensitive]) else {
            return html.contains("sc_courselist") ? html : nil
        }
        let remainder = html[start.upperBound...]
        let end = remainder.range(of: #"<div\b[^>]*id="recommendedscheduletextcontainer""#, options: [.regularExpression, .caseInsensitive])?.lowerBound
            ?? html.endIndex
        return String(html[start.upperBound..<end])
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

        // Most pages name an anchor we recognize. When they don't (common on
        // minors that drop the umbrella "Minor Requirements" heading and just
        // list "Required Courses", "Electives" blocks directly), fall back to
        // the first <h2 ...>Requirements</h2>, and finally to the first
        // `<div class="acalog-core">` so we never give up on parseable pages.
        let start = anchors.compactMap { anchorStart(named: $0, in: html) }.min()
            ?? firstRequirementHeading(in: html)
            ?? firstAcalogCoreBlock(in: html)
        guard let start else { return nil }

        let remainder = html[start..<html.endIndex]
        let end = stopHeadingStart(in: remainder).map { html.index(start, offsetBy: $0) } ?? html.endIndex
        return String(html[start..<end])
    }

    private func firstAcalogCoreBlock(in html: String) -> String.Index? {
        html.range(of: #"<div\s+class="acalog-core""#, options: [.regularExpression, .caseInsensitive])?.lowerBound
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
        var isStructuralHeading: Bool = true
        /// The "Total Credits" of the block's only course table, when that
        /// table has no sub-requirements. More reliable than credit hours
        /// mentioned in the block's prose ("complete the 22-24 credit hours
        /// of the education program").
        var tableTotal: Int? = nil
        /// The footnotes printed under this block's course table, by number.
        var footnotes: [String: String] = [:]
        /// Set on the blocks of one "Option N:" group, which merge into a
        /// single requirement named for the option.
        var optionGroup: String? = nil
        /// The option's credit hours, from the "Choose one of the following
        /// options" row that introduces the group.
        var optionCredits: Int? = nil
        /// The table's area-header row this requirement sits under ("Methodology Core").
        var areaHeader: String? = nil
        /// The text the requirement's ID and legacy calculations come from: the
        /// instruction line that used to be the heading, so IDs stay stable.
        var idSource: String? = nil
        /// Instruction and prose rows under the area header, in order.
        var descriptionLines: [String] = []
        /// Footnote numbers attached to those rows.
        var instructionMarks: [String] = []
        /// Credits from the hours column of the instruction or header row.
        var rowHours: Int? = nil
        /// Credits from the section's "Subtotal" row.
        var subtotal: Int? = nil
        /// The page heading the table sits under, for naming prose-only rows.
        var enclosingHeading: String? = nil
    }

    private func requirementBlocks(in html: String) -> [RequirementBlock] {
        if html.contains("sc_courselist") {
            return modernRequirementBlocks(in: html)
        }

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

    private func modernRequirementBlocks(in html: String) -> [RequirementBlock] {
        let headingPattern = #"(?is)<h([2-5])\b[^>]*>(.*?)</h\1>"#
        let headings = html.matchesWithRanges(for: headingPattern)
        var blocks: [RequirementBlock] = []
        var clusterParents: [(level: Int, heading: String)] = []

        for (index, headingMatch) in headings.enumerated() {
            guard let parts = headingMatch.match.firstMatch(for: headingPattern), parts.count >= 3 else { continue }
            let level = Int(parts[1]) ?? 3
            let rawHeading = HTMLCleaner.clean(parts[2])
            guard !rawHeading.isEmpty else { continue }
            clusterParents.removeAll { $0.level >= level }
            if rawHeading.range(of: #"\[C\d[A-Z]+\]"#, options: .regularExpression) != nil {
                clusterParents.append((level, rawHeading))
            }
            // C2L places its course table below an explanatory h4. Keep the
            // bracketed h3 cluster name so Gen Ed refresh still recognizes it.
            let heading = rawHeading.range(of: #"\[C\d[A-Z]+\]"#, options: .regularExpression) != nil
                ? rawHeading
                : (clusterParents.last?.heading ?? rawHeading)

            let bodyStart = headingMatch.range.upperBound
            let bodyEnd = index + 1 < headings.count ? headings[index + 1].range.lowerBound : html.endIndex
            let segment = String(html[bodyStart..<bodyEnd])
            let tables = segment.matchesWithRanges(for: #"(?is)<table\b[^>]*class="[^"]*\bsc_courselist\b[^"]*"[^>]*>(.*?)</table>"#)

            guard !tables.isEmpty else {
                blocks.append(RequirementBlock(level: level, heading: heading, body: segment))
                continue
            }

            var baseBody = String(segment[..<tables[0].range.lowerBound])
            var commentBlocks: [RequirementBlock] = []
            var baseFootnotes: [String: String] = [:]
            var tableTotals: [Int] = []
            var hasCommentRequirements = false

            for (tableIndex, table) in tables.enumerated() {
                let tableFootnotes = Self.footnotes(
                    after: table.range.upperBound,
                    before: tableIndex + 1 < tables.count ? tables[tableIndex + 1].range.lowerBound : segment.endIndex,
                    in: segment
                )
                baseFootnotes.merge(tableFootnotes, uniquingKeysWith: { first, _ in first })
                let firstCommentBlock = commentBlocks.count
                var currentCommentHeading: String?
                var currentCommentBody = ""
                var currentAreaHeader: String?
                var currentHasCourses = false
                var currentLines: [String] = []
                var currentMarks: [String] = []
                var currentIDSource: String?
                var currentRowHours: Int?
                var currentSubtotal: Int?
                // An instruction under a concentration heading with no course
                // rows, only plain list rows ("Choose one of the following:" over
                // the concentration names), picks a concentration; it is not a
                // requirement. Without plain rows it is an "Option N:" chooser
                // that option merging still reads.
                var underConcentrationHeader = false
                var currentIsConcentrationChooser = false
                var currentHasPlainItems = false
                // "9 credits of MATH electives" rows stand alone, but the
                // course rows after them still belong to the requirement
                // above ("Option 1:"); emit them right after it.
                var pendingAllowances: [RequirementBlock] = []

                func flushComment() {
                    if let heading = currentCommentHeading, !(currentIsConcentrationChooser && currentHasPlainItems && !currentHasCourses) {
                        var block = RequirementBlock(
                            level: min(level + 1, 5),
                            heading: heading,
                            body: currentCommentBody,
                            isStructuralHeading: false
                        )
                        block.areaHeader = currentAreaHeader
                        block.idSource = currentIDSource
                        block.descriptionLines = currentLines
                        block.instructionMarks = currentMarks
                        block.rowHours = currentRowHours
                        block.subtotal = currentSubtotal
                        block.enclosingHeading = heading == rawHeading ? nil : rawHeading
                        commentBlocks.append(block)
                    }
                    commentBlocks.append(contentsOf: pendingAllowances)
                    pendingAllowances = []
                    currentCommentHeading = nil
                    currentCommentBody = ""
                    currentAreaHeader = nil
                    currentHasCourses = false
                    currentLines = []
                    currentMarks = []
                    currentIDSource = nil
                    currentRowHours = nil
                    currentSubtotal = nil
                    currentIsConcentrationChooser = false
                    currentHasPlainItems = false
                }

                for row in table.match.matches(for: #"(?is)<tr\b[^>]*>(.*?)</tr>"#) {
                    guard row.count > 1 else { continue }
                    let rowHTML = row[0]
                    if rowHTML.range(of: #"class="[^"]*\blistsum\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                        flushComment()
                        if let credits = parseLeadingCredits(HTMLCleaner.clean(rowHTML).replacingOccurrences(of: "Total Credits", with: "")) {
                            tableTotals.append(credits)
                            commentBlocks.append(RequirementBlock(
                                level: min(level + 1, 5),
                                heading: "Catalog Table Total: \(credits) Credit Hours",
                                body: "",
                                isStructuralHeading: false
                            ))
                        }
                        continue
                    }
                    if let comment = rowHTML.firstMatch(for: #"(?is)<span\b[^>]*class="[^"]*\bcourselistcomment\b[^"]*"[^>]*>(.*?)</span>"#),
                       comment.count > 1 {
                        // The marker can sit inside or just after the comment span.
                        let commentMarks = rowHTML.matches(for: #"(?is)<sup\b[^>]*>(.*?)</sup>"#)
                            .flatMap { $0.count > 1 ? HTMLCleaner.clean($0[1]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } : [] }
                            .filter { !$0.isEmpty }
                        let commentHeading = HTMLCleaner.clean(
                            comment[1].replacingOccurrences(of: #"(?is)<sup\b[^>]*>.*?</sup>"#, with: " ", options: .regularExpression)
                        )
                        let hours = rowHTML
                            .firstMatch(for: #"(?is)<td\b[^>]*class="[^"]*\bhourscol\b[^"]*"[^>]*>(.*?)</td>"#)
                            .flatMap { $0.count > 1 ? HTMLCleaner.clean($0[1]) : nil }
                        let isSectionHeader = rowHTML.contains("areaheader") || rowHTML.contains("areasubheader")
                        // A 0-credit row ("Assessment Milestone 0") is an item, not
                        // the section's credits.
                        let rowCredits = hours.flatMap(Self.hoursColumnCredits)
                        let isZeroHourRow = hours?.isEmpty == false && rowCredits == nil
                        let isChoiceLine = choiceSelectionCount(heading: commentHeading, body: "") != nil
                            || Self.selectionRule(text: commentHeading, hasMultiCourseGroups: false) != nil
                        // "Subtotal" rows carry the section's real credits.
                        if commentHeading.lowercased().hasPrefix("subtotal") {
                            if currentCommentHeading != nil { currentSubtotal = rowCredits }
                            flushComment()
                            continue
                        }
                        if isSectionHeader { underConcentrationHeader = !canNameRequirement(areaHeader: commentHeading) }
                        // An area header ("Methodology Core") names the requirement;
                        // the instruction rows under it become its description.
                        if isSectionHeader, canNameRequirement(areaHeader: commentHeading) {
                            flushComment()
                            hasCommentRequirements = true
                            currentCommentHeading = commentHeading
                            currentAreaHeader = commentHeading
                            currentCommentBody = rowHTML
                            currentRowHours = rowCredits
                            continue
                        }
                        if let areaHeader = currentAreaHeader, !isSectionHeader, !Self.isCreditAllowanceText(commentHeading) {
                            if !currentHasCourses {
                                currentLines.append(commentHeading)
                                currentMarks += commentMarks
                                if currentIDSource == nil, hours?.isEmpty == false || isChoiceLine {
                                    currentIDSource = commentHeading
                                }
                                if let rowCredits { currentRowHours = rowCredits }
                                currentCommentBody += rowHTML
                                continue
                            }
                            if rowCredits != nil || isChoiceLine {
                                // A second instruction under the same header is its own requirement.
                                flushComment()
                                hasCommentRequirements = true
                                currentCommentHeading = "\(areaHeader): \(commentHeading)"
                                currentAreaHeader = areaHeader
                                currentLines = [commentHeading]
                                currentMarks = commentMarks
                                currentIDSource = commentHeading
                                currentRowHours = rowCredits
                                currentCommentBody = rowHTML
                                continue
                            }
                            if isZeroHourRow {
                                currentLines.append(commentHeading)
                                currentCommentBody += rowHTML
                                continue
                            }
                        }
                        let startsRequirement = isSectionHeader
                            || hours?.isEmpty == false
                            || choiceSelectionCount(heading: commentHeading, body: "") != nil
                            || currentCommentHeading == nil
                        if Self.isCreditAllowanceText(commentHeading), currentCommentHeading != nil {
                            hasCommentRequirements = true
                            pendingAllowances.append(RequirementBlock(
                                level: min(level + 1, 5),
                                heading: commentHeading,
                                body: rowHTML,
                                isStructuralHeading: false
                            ))
                        } else if startsRequirement {
                            flushComment()
                            hasCommentRequirements = true
                            currentCommentHeading = commentHeading
                            currentCommentBody = rowHTML
                            currentIsConcentrationChooser = underConcentrationHeader && !isSectionHeader && isChoiceLine
                        } else {
                            currentCommentBody += rowHTML
                            currentHasPlainItems = true
                        }
                    } else if currentCommentHeading != nil {
                        currentCommentBody += rowHTML
                        if rowHTML.contains("codecol") { currentHasCourses = true } else { currentHasPlainItems = true }
                    } else {
                        baseBody += rowHTML
                    }
                }
                flushComment()
                for index in firstCommentBlock..<commentBlocks.count {
                    commentBlocks[index].footnotes = tableFootnotes
                }
            }

            blocks.append(RequirementBlock(
                level: level,
                heading: heading,
                body: baseBody,
                tableTotal: tables.count == 1 && !hasCommentRequirements ? tableTotals.first : nil,
                footnotes: baseFootnotes
            ))
            blocks.append(contentsOf: commentBlocks)
        }

        return blocks
    }

    /// `<dl class="sc_footnotes">` entries between a course table and the next
    /// one: `<dt><sup>N</sup></dt><dd>text</dd>`.
    private static func footnotes(after start: String.Index, before end: String.Index, in segment: String) -> [String: String] {
        guard start < end else { return [:] }
        let between = String(segment[start..<end])
        guard let list = between.firstMatch(for: #"(?is)<dl\b[^>]*class="[^"]*\bsc_footnotes\b[^"]*"[^>]*>(.*?)</dl>"#),
              list.count > 1
        else { return [:] }
        var notes: [String: String] = [:]
        for entry in list[1].matches(for: #"(?is)<dt\b[^>]*>(.*?)</dt>\s*<dd\b[^>]*>(.*?)</dd>"#) where entry.count > 2 {
            let number = HTMLCleaner.clean(entry[1])
            let text = HTMLCleaner.clean(entry[2])
            if !number.isEmpty, !text.isEmpty { notes[number] = text }
        }
        return notes
    }

    /// Folds the requirements of one "Option N:" group into a single
    /// requirement named for the option, so the option reads as the one
    /// 12-credit choice the catalog describes rather than several pieces.
    private func mergingOptionGroups(
        _ parsed: [(block: RequirementBlock, category: RequirementCategory)]
    ) -> [(block: RequirementBlock, category: RequirementCategory)] {
        var result: [(block: RequirementBlock, category: RequirementCategory)] = []
        for entry in parsed {
            guard let group = entry.block.optionGroup else {
                result.append(entry)
                continue
            }
            if let last = result.last, last.block.optionGroup == group {
                var merged = last.category
                let offset = merged.courseOptions.count
                merged.courseOptions += entry.category.courseOptions
                merged.courseRemarks.merge(entry.category.courseRemarks, uniquingKeysWith: +)
                let slots = (merged.electivePoolSlots ?? []) + (entry.category.electivePoolSlots ?? []).map { $0 + offset }
                merged.electivePoolSlots = slots.isEmpty ? nil : slots
                merged.requiredCredits = entry.block.optionCredits ?? merged.requiredCredits + entry.category.requiredCredits
                merged.note = optionNote(merged.note, adding: entry)
                result[result.count - 1].category = merged
            } else {
                var category = entry.category
                category.id = slug(from: group)
                category.name = group
                category.requiredCredits = entry.block.optionCredits ?? category.requiredCredits
                category.note = optionNote(nil, adding: entry)
                result.append((entry.block, category))
            }
        }
        return result
    }

    private func optionNote(_ existing: String?, adding entry: (block: RequirementBlock, category: RequirementCategory)) -> String? {
        // "Choose two of the following: ... Or take both of the following
        // courses: MATH 426, MATH 427" can't be expressed as slots; say so.
        guard HTMLCleaner.clean(entry.block.body).lowercased().contains("or take both") else { return existing }
        let note = "Instead of choosing two, you can take both courses of the last listed pair. Other mixes may not count, so confirm with an advisor."
        return [existing, note].compactMap { $0 }.joined(separator: " ")
    }

    /// "9 credits of MATH electives at MATH 310 or above" (also "or
    /// higher", "at the 300-level or above").
    private static let electivePoolPattern = #"(?i)^\s*(\d+)\s+credits?\s+of\s+([A-Z]{2,5})\s+electives?\s+at\s+(?:the\s+)?(?:[A-Z]{2,5}\s+)?(\d{3})(?:-level)?\s+or\s+(?:above|higher)"#

    private func electivePoolCategory(from block: RequirementBlock, usedCategoryIDs: inout Set<String>) -> RequirementCategory? {
        guard let match = block.heading.firstMatch(for: Self.electivePoolPattern), match.count > 3,
              let credits = Int(match[1]), let minimum = Int(match[3])
        else { return nil }
        let slotCredits = ScheduleGenerator.electivePoolSlotCredits
        let slots = max(Int(ceil(Double(credits) / Double(slotCredits))), 1)
        let token = ElectivePool.token(subject: match[2], minimumNumber: minimum)
        return RequirementCategory(
            id: uniqueID(slug(from: block.heading), used: &usedCategoryIDs),
            name: block.heading,
            requiredCredits: credits,
            courseOptions: Array(repeating: [token], count: slots),
            verificationStatus: .partial,
            note: "Any \(match[2].uppercased()) course numbered \(minimum) or above that isn't already required.",
            electivePoolSlots: Array(0..<slots)
        )
    }

    /// "Option 1:", "Option 2:" sub-headings inside a course table.
    private func isOptionHeading(_ block: RequirementBlock) -> Bool {
        !block.isStructuralHeading
            && block.heading.range(of: #"(?i)^\s*option\s+(?:\d+|[a-z])\s*:?\s*$"#, options: .regularExpression) != nil
    }

    /// Splits blocks holding two or more "Option N:" groups into one variant
    /// per option. `common` is everything outside the groups (minus the
    /// "Choose one of the following options" intro); each variant holds its
    /// option's blocks, up to the next option or the end of the table.
    private func optionVariants(in blocks: [RequirementBlock]) -> (common: [RequirementBlock], variants: [(name: String, blocks: [RequirementBlock])])? {
        let optionStarts = blocks.indices.filter { isOptionHeading(blocks[$0]) }
        guard optionStarts.count >= 2, let first = optionStarts.first, let last = optionStarts.last else { return nil }
        let groupEnd = blocks[(last + 1)...].firstIndex { block in
            let lower = block.heading.lowercased()
            return block.isStructuralHeading
                || lower.hasPrefix("catalog table total")
                || lower.hasPrefix("subtotal")
        } ?? blocks.endIndex

        let isIntro: (RequirementBlock) -> Bool = { $0.heading.lowercased().contains("one of the following options") }
        let optionCredits = blocks[..<first].last(where: isIntro)
            .flatMap { $0.body.firstMatch(for: #"(?is)<td\b[^>]*class="[^"]*\bhourscol\b[^"]*"[^>]*>(.*?)</td>"#) }
            .flatMap { $0.count > 1 ? parseLeadingCredits(HTMLCleaner.clean($0[1])) : nil }
        let common = blocks[..<first].filter { !isIntro($0) } + blocks[groupEnd...]
        let variants = optionStarts.enumerated().map { offset, start in
            let end = offset + 1 < optionStarts.count ? optionStarts[offset + 1] : groupEnd
            let name = blocks[start].heading
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            let groupBlocks = blocks[start..<end].map { block in
                var block = block
                block.optionGroup = name
                block.optionCredits = optionCredits
                return block
            }
            return (name: name, blocks: groupBlocks)
        }
        return (common, variants)
    }

    private func splitConcentrationBlocks(_ blocks: [RequirementBlock]) -> (shared: [RequirementBlock], concentrationRuns: [(name: String, blocks: [RequirementBlock])], concentrationSelectionRequired: Bool) {
        // Two layouts in the catalog:
        //
        // 1. Explicit umbrella section ("Concentrations" / "Required Concentration")
        //    followed by N concrete concentration sub-blocks.
        // 2. No umbrella: each concentration sits as a sibling heading inside
        //    the major's requirement list (Physics B.S. uses this shape).
        //
        // First-try the umbrella path; if absent, fall back to scanning for
        // sibling concrete-concentration headings and treating the first such
        // heading as the partition point.
        if let umbrellaIndex = blocks.firstIndex(where: { $0.isStructuralHeading && isConcentrationSectionHeading($0) }) {
            if blocks.contains(where: { !$0.isStructuralHeading }) {
                let partition = partitionModernHierarchyAfter(umbrellaIndex: umbrellaIndex, blocks: blocks)
                return (
                    shared: partition.shared,
                    concentrationRuns: partition.concentrationRuns,
                    concentrationSelectionRequired: isRequiredConcentrationSectionHeading(blocks[umbrellaIndex])
                        || !allowsBaseMajorWithoutConcentration(in: partition.shared)
                )
            }
            let partition = partitionAfter(umbrellaIndex: umbrellaIndex, blocks: blocks)
            return (
                shared: partition.shared,
                concentrationRuns: partition.concentrationRuns,
                concentrationSelectionRequired: isRequiredConcentrationSectionHeading(blocks[umbrellaIndex])
                    || !allowsBaseMajorWithoutConcentration(in: partition.shared)
            )
        }
        guard let firstConcentration = blocks.firstIndex(where: { $0.isStructuralHeading && isConcreteConcentrationHeading($0.heading) }) else {
            return (blocks, [], false)
        }
        let partition = partitionInline(firstConcentration: firstConcentration, blocks: blocks)
        return (partition.shared, partition.concentrationRuns, !allowsBaseMajorWithoutConcentration(in: partition.shared))
    }

    private func partitionModernHierarchyAfter(
        umbrellaIndex: Int,
        blocks: [RequirementBlock]
    ) -> (shared: [RequirementBlock], concentrationRuns: [(name: String, blocks: [RequirementBlock])]) {
        let umbrellaLevel = blocks[umbrellaIndex].level
        let sectionEnd = blocks[(umbrellaIndex + 1)...].firstIndex {
            $0.isStructuralHeading && $0.level <= umbrellaLevel
        } ?? blocks.endIndex
        let shared = Array(blocks[..<umbrellaIndex]).filter { !isConcentrationSummaryBlock($0) }

        let directHeadings = blocks.indices.filter { index in
            index > umbrellaIndex
                && index < sectionEnd
                && blocks[index].isStructuralHeading
                && blocks[index].level == umbrellaLevel + 1
        }
        var runs: [(name: String, blocks: [RequirementBlock])] = []
        for (offset, index) in directHeadings.enumerated() {
            let end = offset + 1 < directHeadings.count ? directHeadings[offset + 1] : sectionEnd
            runs.append(contentsOf: modernLeafRuns(
                nodeIndex: index,
                endIndex: end,
                inherited: [],
                pathHeadings: [],
                blocks: blocks
            ))
        }
        return (shared, runs)
    }

    private func modernLeafRuns(
        nodeIndex: Int,
        endIndex: Int,
        inherited: [RequirementBlock],
        pathHeadings: [String],
        blocks: [RequirementBlock]
    ) -> [(name: String, blocks: [RequirementBlock])] {
        let node = blocks[nodeIndex]
        let childCandidates = blocks.indices.filter { index in
            index > nodeIndex
                && index < endIndex
                && blocks[index].isStructuralHeading
                && blocks[index].level > node.level
                && isConcreteConcentrationHeading(blocks[index].heading)
        }
        guard let childLevel = childCandidates.map({ blocks[$0].level }).min() else {
            return [(modernConcentrationName(pathHeadings + [node.heading]), inherited + Array(blocks[nodeIndex..<endIndex]))]
        }

        let children = childCandidates.filter { blocks[$0].level == childLevel }
        let localSharedEnd = children.first ?? endIndex
        let localShared = inherited + Array(blocks[nodeIndex..<localSharedEnd])
        var runs: [(name: String, blocks: [RequirementBlock])] = []
        for (offset, childIndex) in children.enumerated() {
            let childEnd = offset + 1 < children.count ? children[offset + 1] : endIndex
            runs.append(contentsOf: modernLeafRuns(
                nodeIndex: childIndex,
                endIndex: childEnd,
                inherited: localShared,
                pathHeadings: pathHeadings + [node.heading],
                blocks: blocks
            ))
        }
        return runs
    }

    private func modernConcentrationName(_ headings: [String]) -> String {
        guard var name = headings.first.map(JMUHTMLCatalogParser.cleanConcentrationName) else { return "Concentration" }
        for heading in headings.dropFirst() {
            var child = heading
                .replacingOccurrences(of: #"(?i)\s+Requirements$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if child.lowercased().hasPrefix(name.lowercased()) {
                name = child
            } else {
                child = child.replacingOccurrences(of: #"(?i)^Subtrack in\s+"#, with: "", options: .regularExpression)
                name += " - \(child)"
            }
        }
        return name
    }

    private func isConcentrationSummaryBlock(_ block: RequirementBlock) -> Bool {
        guard !block.isStructuralHeading else { return false }
        let lower = block.heading.lowercased()
        return lower == "concentrations" || lower.contains("following concentrations")
    }

    private func partitionAfter(umbrellaIndex: Int, blocks: [RequirementBlock]) -> (shared: [RequirementBlock], concentrationRuns: [(name: String, blocks: [RequirementBlock])]) {
        let sectionLevel = blocks[umbrellaIndex].level
        let shared = Array(blocks[..<umbrellaIndex])
        let tail = Array(blocks[(umbrellaIndex + 1)...])
        var runs: [(name: String, blocks: [RequirementBlock])] = []
        var currentName: String?
        var currentCleanName: String?
        var currentBlocks: [RequirementBlock] = []
        // Level of the first run-starting heading. Under an explicit umbrella
        // ("Concentrations"), every sibling heading at this level is its own
        // concentration even when the heading is a plain name with no
        // "concentration"/"track" noun — Music B.M. lists all 15 that way
        // ("Composition", "Jazz Studies", ...). Deeper headings and generic
        // sub-headings ("Required Courses", electives) fold into the open run.
        var runLevel: Int?

        for block in tail {
            guard block.level > sectionLevel else { break }
            let startsRun: Bool
            if isConcreteConcentrationHeading(block.heading) {
                startsRun = true
            } else if isGenericConcentrationSubHeading(block.heading) {
                startsRun = false
            } else if let runLevel {
                startsRun = block.level == runLevel
            } else {
                // First child heading under the umbrella opens the first run
                // even without a concentration noun.
                startsRun = true
            }

            if startsRun {
                let candidateClean = JMUHTMLCatalogParser.cleanConcentrationName(block.heading)
                if let cleaned = currentCleanName,
                   !candidateClean.isEmpty,
                   candidateClean.lowercased().hasPrefix(cleaned.lowercased()) {
                    currentBlocks.append(block)
                    continue
                }
                if let currentName, !currentBlocks.isEmpty {
                    runs.append((currentName, currentBlocks))
                }
                currentName = block.heading
                currentCleanName = candidateClean.isEmpty ? block.heading : candidateClean
                currentBlocks = [block]
                if runLevel == nil { runLevel = block.level }
            } else if currentName != nil {
                currentBlocks.append(block)
            }
        }

        if let currentName, !currentBlocks.isEmpty {
            runs.append((currentName, currentBlocks))
        }
        return (shared, runs)
    }

    /// Headings that are structural sub-blocks of a concentration rather than
    /// a new concentration: required-course lists, electives, choose-from
    /// buckets, ensembles, totals. Compared lowercase.
    private func isGenericConcentrationSubHeading(_ heading: String) -> Bool {
        let lower = heading.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let markers = [
            "required course", "required credit", "elective", "choose", "select",
            "total", "additional course", "additional requirement", "core course",
            "ensemble", "recital", "audition", "capstone"
        ]
        return markers.contains { lower.contains($0) }
    }

    private func partitionInline(firstConcentration: Int, blocks: [RequirementBlock]) -> (shared: [RequirementBlock], concentrationRuns: [(name: String, blocks: [RequirementBlock])]) {
        let shared = Array(blocks[..<firstConcentration])
        let tail = Array(blocks[firstConcentration...])
        var runs: [(name: String, blocks: [RequirementBlock])] = []
        var currentName: String?
        var currentCleanName: String?
        var currentBlocks: [RequirementBlock] = []

        for block in tail {
            if isConcreteConcentrationHeading(block.heading), !isOptionHeading(block) {
                let candidateClean = JMUHTMLCatalogParser.cleanConcentrationName(block.heading)
                if let cleaned = currentCleanName,
                   !candidateClean.isEmpty,
                   candidateClean.lowercased().hasPrefix(cleaned.lowercased()) {
                    // Sub-block of the currently-open concentration (e.g.,
                    // "Information and Cybersecurity Management Concentration
                    // Electives" rolling up under "Information and Cybersecurity
                    // Management Concentration"). Fold in, don't start new run.
                    currentBlocks.append(block)
                    continue
                }
                if let name = currentName, !currentBlocks.isEmpty {
                    runs.append((name, currentBlocks))
                }
                currentName = block.heading
                currentCleanName = candidateClean.isEmpty ? block.heading : candidateClean
                currentBlocks = [block]
            } else if currentName != nil {
                // Append non-concentration sibling (electives, sub-options) to
                // the currently-open concentration. Keeps "Choose from the
                // following research courses" with its parent concentration.
                currentBlocks.append(block)
            }
        }
        if let name = currentName, !currentBlocks.isEmpty {
            runs.append((name, currentBlocks))
        }
        return (shared, runs)
    }

    private func isConcentrationSectionHeading(_ block: RequirementBlock) -> Bool {
        let lower = block.heading.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "concentrations"
            || lower == "tracks"
            || lower == "areas of emphasis"
            || lower == "required concentration"
            || lower == "required concentrations"
            || lower == "concentration options"
            || lower == "concentration areas"
            || lower == "areas of study"
            || lower == "degree options"
            || lower == "program options"
            || lower == "choose a concentration"
            || lower == "select a concentration"
    }

    private func isRequiredConcentrationSectionHeading(_ block: RequirementBlock) -> Bool {
        let lower = block.heading.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "required concentration" || lower == "required concentrations"
    }

    private func allowsBaseMajorWithoutConcentration(in blocks: [RequirementBlock]) -> Bool {
        let text = blocks
            .map { "\($0.heading) \($0.body)" }
            .joined(separator: " ")
            .lowercased()
        return text.contains("standard") && text.contains("major") && text.contains("concentration")
            || text.contains("do not elect") && text.contains("concentration")
            || text.contains("may choose either") && text.contains("concentration")
            || text.contains("may be fulfilled by completing a concentration")
    }

    private func isConcreteConcentrationHeading(_ heading: String) -> Bool {
        let lower = heading.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let umbrellas = ["concentrations", "tracks", "areas of emphasis", "options", "paths", "routes"]
        guard !umbrellas.contains(lower) else { return false }
        // Catalog headings carry the noun anywhere in the line, often before
        // "Required Courses" or a credit-hour suffix.
        if lower.contains("concentration") { return true }
        if lower.contains("emphasis") { return true }
        if lower.contains("specialization") { return true }
        if lower.contains("subtrack") { return true }
        if lower.contains(" track") || lower.hasSuffix("track") { return true }
        // "Additional Requirements for Students (Not) Seeking Secondary
        // Teaching Licensure": mutually exclusive tracks.
        if lower.range(of: #"\bstudents\s+(?:who\s+are\s+)?(?:not\s+)?seeking\b"#, options: .regularExpression) != nil { return true }
        // Match "Option N", "Path N", "Route N" word boundaries. Avoid
        // matching every "Course Options" sub-heading by requiring the noun
        // to be followed by a digit / colon / dash / end-of-line.
        if lower.range(of: #"(?i)\b(option|path|route)\s*\d"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"(?i)\b(option|path|route)\s*[:\-]"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Strip catalog boilerplate ("Required Courses", credit-hour suffix,
    /// "(in addition to core requirements)") and the concentration noun itself
    /// so the picker shows clean labels like "Applied Physics".
    public static func cleanConcentrationName(_ raw: String) -> String {
        var name = raw
        let strippers: [String] = [
            #"(?i)\s*:\s*\d+(?:\s*-\s*\d+)?\s+Credit\s+Hours.*$"#,
            #"(?i)\s*\(in addition to[^)]*\)\s*$"#,
            #"(?i)\s*Required Courses.*$"#,
            #"(?i)^Concentration in\s+"#,
            #"(?i)^(?:Additional\s+)?Requirements\s+for\s+Students\s+(?:who\s+are\s+)?"#,
            #"(?i)\s*Concentration\s*$"#,
            #"(?i)\s*Track\s*$"#,
            #"(?i)\s*Emphasis\s*$"#,
            #"(?i)\s*Specialization\s*$"#
        ]
        for pattern in strippers {
            name = name.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func category(
        from block: RequirementBlock,
        catoid: String,
        usedCategoryIDs: inout Set<String>,
        coursesByID: inout [String: Course]
    ) -> RequirementCategory? {
        if let pool = electivePoolCategory(from: block, usedCategoryIDs: &usedCategoryIDs) {
            return pool
        }
        let courseItems = courseItems(in: block.body, catoid: catoid)
        let annotated = annotatedCourses(courseItems)
        let courses = annotated.map(\.course)
        // Everything the parser used to derive from the heading keeps using the
        // text that was the heading (the instruction line), so IDs, drops and
        // credit fallbacks are unchanged; only the displayed name moves.
        let legacyHeading = block.idSource ?? block.heading

        // Skip non-requirement sections (descriptions, totals, admission, etc).
        // Umbrella headings like "Major Requirements" are skipped ONLY when their
        // body has no course rows — some catalog pages place the core required
        // courses directly under the umbrella heading with no child acalog-core div.
        guard !shouldIgnoreRequirementHeading(legacyHeading, hasCourses: !courses.isEmpty) else {
            return nil
        }

        for course in courses {
            coursesByID[course.id] = course
        }

        let groups = courseGroups(courseItems)
        let hasMultiCourseGroups = groups.contains { $0.count > 1 }
        let ruleText = block.areaHeader != nil ? block.descriptionLines.joined(separator: " ") : legacyHeading
        let selection: RequirementSelection
        if let rule = Self.selectionRule(text: ruleText, hasMultiCourseGroups: hasMultiCourseGroups) {
            selection = rule
        } else if !courses.isEmpty,
                  (block.areaHeader != nil && block.descriptionLines.isEmpty) || legacyHeading.lowercased().contains("required") {
            selection = .allRequired
        } else {
            selection = .unknown
        }

        let selectedCreditHours = choiceCreditHours(heading: legacyHeading, body: block.body)
        let selectionCount = selectedCreditHours.map { creditHours in
            choiceCourseCount(for: creditHours, courses: courses)
        } ?? choiceSelectionCount(heading: legacyHeading, body: block.body)
        let ruleCredits: Int? = {
            switch selection {
            case .chooseCredits(let credits): return credits
            case .chooseCourses(let count): return inferredCredits(for: courseItems, selectionCount: count)
            default: return nil
            }
        }()
        let requiredCredits = block.rowHours
            ?? block.subtotal
            ?? selectedCreditHours
            ?? ruleCredits
            ?? parseCredits(from: legacyHeading)
            ?? block.tableTotal
            ?? parseTotalCreditsFromBody(block.body)
            ?? inferredCredits(for: courseItems, selectionCount: selectionCount)

        guard requiredCredits > 0 || !courses.isEmpty else { return nil }

        let creditsByID = Dictionary(courses.map { ($0.id, $0.credits) }, uniquingKeysWith: { first, _ in first })
        let isChoice: Bool = {
            switch selection {
            case .chooseCourses, .chooseCredits, .chooseGroups: return true
            case .allRequired, .unknown: return false
            }
        }()
        let options = isChoice
            ? RequirementSelection.slots(choices: groups, selection: selection, credits: { creditsByID[$0] ?? 3 }) ?? []
            : courseOptions(from: courseItems, selectionCount: selectionCount)
        let categoryID = uniqueID(slug(from: legacyHeading), used: &usedCategoryIDs)
        let note = note(for: block, options: options, courses: courses)
        var remarks: [String: [String]] = [:]
        for (course, annotation) in annotated {
            let notes = annotation.remarks + annotation.footnoteMarks.compactMap { block.footnotes[$0] }
            if !notes.isEmpty { remarks[course.id, default: []].append(contentsOf: notes) }
        }

        // A paragraph that the catalog put where a heading goes reads as the
        // requirement's description, under the heading it sits beneath.
        var name = block.heading
        var descriptionLines = block.descriptionLines
        if block.areaHeader == nil, Self.isProse(block.heading), let enclosing = block.enclosingHeading {
            name = enclosing
            descriptionLines = [block.heading]
        }
        descriptionLines += block.instructionMarks.compactMap { block.footnotes[$0] }
        let description = descriptionLines.isEmpty ? nil : descriptionLines.joined(separator: " ")

        return RequirementCategory(
            id: categoryID,
            name: name,
            requiredCredits: requiredCredits,
            courseOptions: options,
            verificationStatus: .partial,
            note: note,
            selection: selection,
            choices: groups,
            catalogDescription: description,
            courseRemarks: remarks
        )
    }

    /// Course groups in catalog order: one per row, a pair row as one group.
    private func courseGroups(_ items: [CourseItem]) -> [[String]] {
        var seen: Set<String> = []
        return items.compactMap { item -> [String]? in
            switch item {
            case .course(let course, _):
                return seen.insert(course.id).inserted ? [course.id] : nil
            case .pair(let courses, _):
                let ids = courses.map(\.id)
                return seen.insert(ids.joined(separator: "&")).inserted ? ids : nil
            case .marker:
                return nil
            }
        }
    }

    /// A sentence or paragraph rather than a heading.
    private static func isProse(_ text: String) -> Bool {
        text.count > 120 || text.range(of: #"[.!?]\s+[A-Z]"#, options: .regularExpression) != nil
    }

    /// Area headers that start concentrations, tracks or options keep their
    /// own block so concentration and option splitting see them as before.
    private func canNameRequirement(areaHeader: String) -> Bool {
        let lower = areaHeader.lowercased()
        guard !lower.contains("option"), !lower.contains("concentration"),
              !lower.contains("track"), !lower.contains("emphasis"), !lower.contains("specialization")
        else { return false }
        return !isConcreteConcentrationHeading(areaHeader)
    }

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "eighteen": 18
    ]

    /// The catalog's selection rule from an instruction line, or nil when the
    /// text does not state one.
    static func selectionRule(text: String, hasMultiCourseGroups: Bool) -> RequirementSelection? {
        let lower = text.lowercased()
        let number = #"(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|eighteen)"#
        func value(_ token: String) -> Int? { Int(token) ?? numberWords[token] }

        let atLeast = #"(?:(?:at\s+least|a\s+minimum\s+of|any)\s+)?"#
        if let match = lower.firstMatch(for: #"(?:choose|select|complete|take|earn)\s+"# + atLeast + number + #"\s+(?:additional\s+)?credit"#),
           match.count > 1, let credits = value(match[1]) {
            return .chooseCredits(credits)
        }
        if lower.contains("one of the following") || lower.range(of: #"\bselect one\b"#, options: .regularExpression) != nil {
            return hasMultiCourseGroups ? .chooseGroups(1) : .chooseCourses(1)
        }
        if let match = lower.firstMatch(for: #"(?:choose|select)\s+"# + atLeast + number + #"\b"#)
            ?? lower.firstMatch(for: #"complete\s+"# + atLeast + number + #"\s+(?:of\b|courses?\b)"#),
           match.count > 1, let count = value(match[1]) {
            return hasMultiCourseGroups ? .chooseGroups(count) : .chooseCourses(count)
        }
        return nil
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
        case course(Course, CourseAnnotation)
        /// Courses on one catalog row that are taken together ("PSYC 210 & PSYC 211").
        case pair([Course], [CourseAnnotation])
        case marker(String)
    }

    /// What a course row says besides the course itself: catalog remarks
    /// ("Offered every semester") and footnote numbers to resolve.
    private struct CourseAnnotation {
        var remarks: [String] = []
        var footnoteMarks: [String] = []
    }

    /// Pairs as separate course items, the way every consumer saw them before
    /// pairs were recognized.
    private func flattened(_ items: [CourseItem]) -> [CourseItem] {
        items.flatMap { item -> [CourseItem] in
            if case .pair(let courses, let annotations) = item {
                return zip(courses, annotations).map { CourseItem.course($0, $1) }
            }
            return [item]
        }
    }

    private func annotatedCourses(_ items: [CourseItem]) -> [(course: Course, annotation: CourseAnnotation)] {
        flattened(items).compactMap { item in
            if case .course(let course, let annotation) = item { return (course, annotation) }
            return nil
        }
    }

    /// Splits a course title cell into its title and what the catalog hangs
    /// on it: `<sup>` footnote numbers, parenthetical remarks, stray markers.
    /// Bracketed Gen Ed cluster codes ("[C5SD]") stay in the title.
    static func cleanCourseTitle(_ html: String) -> (title: String, remarks: [String], footnoteMarks: [String]) {
        var marks: [String] = []
        for sup in html.matches(for: #"(?is)<sup\b[^>]*>(.*?)</sup>"#) where sup.count > 1 {
            marks += HTMLCleaner.clean(sup[1])
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .map(String.init)
                .filter { !$0.isEmpty }
        }
        var title = HTMLCleaner.clean(
            html.replacingOccurrences(of: #"(?is)<sup\b[^>]*>.*?</sup>"#, with: " ", options: .regularExpression)
        )
        title = title.replacingOccurrences(of: #"(?i)^and\s+"#, with: "", options: .regularExpression)
        var remarks: [String] = []
        for paren in title.matches(for: #"\(([^()]*)\)"#) where paren.count > 1 {
            let remark = paren[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remark.isEmpty else { continue }
            remarks.append(remark.prefix(1).uppercased() + remark.dropFirst())
        }
        // Repeat so nested parentheses ("((taken for 3 credits))") leave nothing behind.
        while title.range(of: #"\([^()]*\)"#, options: .regularExpression) != nil {
            title = title.replacingOccurrences(of: #"\s*\([^()]*\)"#, with: "", options: .regularExpression)
        }
        title = title.replacingOccurrences(of: #"\s?\*+[\d,]*$"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\s[\d,]+$"#, with: "", options: .regularExpression)
        return (title.trimmingCharacters(in: .whitespacesAndNewlines), remarks, marks)
    }

    private func courseItems(in html: String, catoid: String) -> [CourseItem] {
        if html.contains("<tr") && html.contains("/search/?P=") {
            return modernCourseItems(in: html)
        }

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

            guard var course = parseCourse(fromListItem: body, catoid: catoid) else {
                return nil
            }
            let cleaned = Self.cleanCourseTitle(course.title)
            course.title = cleaned.title
            return .course(course, CourseAnnotation(remarks: cleaned.remarks, footnoteMarks: cleaned.footnoteMarks))
        }
    }

    private func modernCourseItems(in html: String) -> [CourseItem] {
        var items: [CourseItem] = []
        for row in html.matches(for: #"(?is)<tr\b[^>]*>(.*?)</tr>"#) {
            guard row.count > 1,
                  !row[0].contains("courselistcomment"),
                  !row[0].contains("listsum"),
                  let codeCell = row[1].firstMatch(for: #"(?is)<td\b[^>]*class="[^"]*\bcodecol\b[^"]*"[^>]*>(.*?)</td>"#),
                  codeCell.count > 1
            else { continue }

            let cells = row[1].matches(for: #"(?is)<td\b[^>]*>(.*?)</td>"#)
            let titleCell = cells.count > 1 && cells[1].count > 1 ? cells[1][1] : ""
            // A pair row lists one title per course, separated by <br/>.
            let titleParts = titleCell.components(separatedBy: #"<br"#).map { part -> String in
                part.replacingOccurrences(of: #"(?is)^\s*/?>"#, with: "", options: .regularExpression)
            }
            let hoursText = row[1]
                .firstMatch(for: #"(?is)<td\b[^>]*class="[^"]*\bhourscol\b[^"]*"[^>]*>(.*?)</td>"#)
                .flatMap { $0.count > 1 ? HTMLCleaner.clean($0[1]) : nil }
            let links = codeCell[1].matches(for: #"(?is)<a\b[^>]*href="([^"]*/search/\?P=[^"]+)"[^>]*>(.*?)</a>"#)
            // "or MATH 431" rows (class "orclass") are alternatives to the
            // course above. A row offering a pair ("or MATH 229 & MATH 329")
            // can't be expressed as a single-course alternative, so its
            // courses stay separate requirements.
            let rowTag = row[0].firstMatch(for: #"(?is)^<tr\b[^>]*>"#)?.first ?? ""
            if rowTag.range(of: #"class="[^"]*\borclass\b"#, options: .regularExpression) != nil, links.count == 1 {
                items.append(.marker("or"))
            }
            let rowCredits = hoursText.flatMap(parseLeadingCredits)
            let perCourseCredits = rowCredits.map { max(Int(ceil(Double($0) / Double(max(links.count, 1)))), 1) } ?? 3

            var rowCourses: [Course] = []
            var rowAnnotations: [CourseAnnotation] = []
            for (position, link) in links.enumerated() where link.count >= 3 {
                let code = HTMLCleaner.clean(link[2])
                // Cross-listed codes ("PSYC/BIO 385") are the first subject's course.
                guard let parsedCode = code.firstMatch(for: #"^([A-Z]{2,5})(?:/[A-Z]{2,5})*\s+(\d{3}[A-Z]?)$"#), parsedCode.count >= 3 else { continue }
                let subject = parsedCode[1]
                let number = parsedCode[2]
                let url = URL(string: HTMLCleaner.decodeEntities(in: link[1]), relativeTo: baseURL)?.absoluteURL
                let titleHTML = links.count > 1 && titleParts.count == links.count ? titleParts[position] : titleCell
                let cleaned = Self.cleanCourseTitle(titleHTML)
                rowCourses.append(Course(
                    id: "\(subject)\(number)",
                    code: "\(subject) \(number)",
                    title: cleaned.title,
                    credits: perCourseCredits,
                    availability: nil,
                    prerequisites: [],
                    verificationStatus: .partial,
                    registrarURL: url
                ))
                rowAnnotations.append(CourseAnnotation(remarks: cleaned.remarks, footnoteMarks: cleaned.footnoteMarks))
            }
            if rowCourses.count > 1 {
                items.append(.pair(rowCourses, rowAnnotations))
            } else if let course = rowCourses.first, let annotation = rowAnnotations.first {
                items.append(.course(course, annotation))
            }
        }
        return items
    }

    /// Credits from a table's hours column: "3"; for a range the lower bound,
    /// or the upper one when the lower is 0 ("0-3" -> 3, "46-54" -> 46).
    /// Nil for "0" and for text without a number.
    static func hoursColumnCredits(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.firstMatch(for: #"^(\d+)(?:\s*[-–]\s*(\d+))?"#), match.count > 1,
              let lower = Int(match[1])
        else { return nil }
        if lower > 0 { return lower }
        return match.count > 2 ? Int(match[2]).flatMap { $0 > 0 ? $0 : nil } : nil
    }

    private func parseLeadingCredits(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.firstMatch(for: #"^(\d+)(?:\s*-\s*\d+)?"#), match.count > 1 else { return nil }
        return Int(match[1])
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
            #"(?i)(\d+)(?:\s*-\s*\d+)?\s+Credit\s+Hours"#,
            Self.creditAllowancePattern
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

    /// "9 credits of MATH electives at MATH 310 or above": a credit
    /// allowance with no course list, its own requirement.
    private static let creditAllowancePattern = #"(?i)^\s*(\d+)\s+credits?\s+(?:of|in)\b"#

    private static func isCreditAllowanceText(_ text: String) -> Bool {
        text.range(of: creditAllowancePattern, options: .regularExpression) != nil
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
        let items = flattened(items)
        let courses = annotatedCourses(items).map(\.course)

        if let selectionCount {
            return courses.prefix(selectionCount).reduce(0) { $0 + $1.credits }
        }

        return courseOptions(from: items, selectionCount: nil).reduce(0) { total, option in
            total + (option.compactMap { courseID in courses.first(where: { $0.id == courseID })?.credits }.max() ?? 0)
        }
    }

    private func isChoiceRequirement(heading: String, body: String) -> Bool {
        choiceCreditHours(heading: heading, body: body) != nil
            || choiceSelectionCount(heading: heading, body: body) != nil
    }

    private func choiceCreditHours(heading: String, body: String) -> Int? {
        let text = HTMLCleaner.clean("\(heading) \(body)").lowercased()
        if let match = text.firstMatch(for: #"(?i)(?:choose|select)\s+(\d+)\s+credit\s*hours?"#),
           match.count > 1,
           let credits = Int(match[1]) {
            return credits
        }

        let wordValues = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "twelve": 12, "fifteen": 15, "eighteen": 18, "twenty-one": 21,
            "twenty-four": 24
        ]
        for (word, value) in wordValues {
            if text.range(
                of: "(?:choose|select)\\s+\(word)\\s+credit\\s*hours?",
                options: .regularExpression
            ) != nil {
                return value
            }
        }
        return nil
    }

    private func choiceCourseCount(for requiredCredits: Int, courses: [Course]) -> Int {
        let slotCredits = max(courses.map(\.credits).max() ?? 3, 1)
        return max(Int(ceil(Double(requiredCredits) / Double(slotCredits))), 1)
    }

    private func choiceSelectionCount(heading: String, body: String) -> Int? {
        let text = HTMLCleaner.clean("\(heading) \(body)").lowercased()
        if text.contains("one of the following") || text.contains("select one") {
            return 1
        }

        let wordValues = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6]

        // "Two courses at the 400-level", "three courses at the 300/400-level",
        // "two 400-level courses", etc. — the body lists every eligible course
        // at that level, but only N of them are required. Without this we
        // treat the whole pool as mandatory and the category balloons to 50+
        // credits.
        for (word, value) in wordValues {
            let levelPatterns = [
                "\(word) courses at the",
                "\(word) additional courses at the",
                "\(word) \\d{3}-level",
                "\(word) \\d{3}/\\d{3}-level",
                "\(word) courses at \\d{3}-level"
            ]
            for pattern in levelPatterns {
                if text.range(of: pattern, options: .regularExpression) != nil {
                    return value
                }
            }
        }
        if let match = text.firstMatch(for: #"(?i)(\d+)\s+(?:additional\s+)?courses?\s+at\s+the\s+\d{3}"#),
           match.count > 1,
           let n = Int(match[1]) {
            return n
        }
        if let match = text.firstMatch(for: #"(?i)(\d+)\s+\d{3}-level\s+courses?"#),
           match.count > 1,
           let n = Int(match[1]) {
            return n
        }

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
        let items = flattened(items)
        let courseIDs = annotatedCourses(items).map(\.course.id)
        guard !courseIDs.isEmpty else { return [] }

        if selectionCount == 1 {
            return [unique(courseIDs)]
        }

        if let selectionCount, selectionCount > 1 {
            // Pick N of the listed alternates: emit N parallel options, each
            // exposing the full alternate pool, so the schedule produces N
            // placeholder slots the student fills from the same menu.
            // The previous behavior — `prefix(selectionCount).map { [$0] }` —
            // hard-coded the first N catalog entries as required, which broke
            // for "two courses at the 400-level" style requirements.
            let alternates = unique(courseIDs)
            return Array(repeating: alternates, count: selectionCount)
        }

        var options: [[String]] = []
        var index = 0
        while index < items.count {
            guard case .course(let course, _) = items[index] else {
                index += 1
                continue
            }

            var group = [course.id]
            var cursor = index
            while cursor + 2 < items.count,
                  case .marker(let marker) = items[cursor + 1],
                  marker.lowercased() == "or",
                  case .course(let nextCourse, _) = items[cursor + 2] {
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
        let cleaned = HTMLCleaner.clean(html)
        let patterns = [
            #"(?i)(?:Program\s+)?Total:\s*(\d+)(?:\s*-\s*\d+)?\s+Credit\s+Hours"#,
            #"(?i)\bTotal\s+(\d+)(?:\s*-\s*\d+)?\b"#
        ]
        for pattern in patterns {
            if let match = cleaned.firstMatch(for: pattern), match.count > 1 {
                return Int(match[1])
            }
        }
        return nil
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
