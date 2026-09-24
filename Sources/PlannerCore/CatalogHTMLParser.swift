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
        let split = splitConcentrationBlocks(blocks)

        for block in split.shared {
            if let parsed = category(from: block, catoid: catoid, usedCategoryIDs: &usedCategoryIDs, coursesByID: &coursesByID) {
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
            let requirements = adjustedConcentrationRequirements(
                from: parsedRequirements,
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

            for table in tables {
                var currentCommentHeading: String?
                var currentCommentBody = ""

                func flushComment() {
                    guard let heading = currentCommentHeading else { return }
                    commentBlocks.append(RequirementBlock(
                        level: min(level + 1, 5),
                        heading: heading,
                        body: currentCommentBody,
                        isStructuralHeading: false
                    ))
                    currentCommentHeading = nil
                    currentCommentBody = ""
                }

                for row in table.match.matches(for: #"(?is)<tr\b[^>]*>(.*?)</tr>"#) {
                    guard row.count > 1 else { continue }
                    let rowHTML = row[0]
                    if rowHTML.range(of: #"class="[^"]*\blistsum\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                        flushComment()
                        if let credits = parseLeadingCredits(HTMLCleaner.clean(rowHTML).replacingOccurrences(of: "Total Credits", with: "")) {
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
                        let commentHeading = HTMLCleaner.clean(comment[1])
                        let hours = rowHTML
                            .firstMatch(for: #"(?is)<td\b[^>]*class="[^"]*\bhourscol\b[^"]*"[^>]*>(.*?)</td>"#)
                            .flatMap { $0.count > 1 ? HTMLCleaner.clean($0[1]) : nil }
                        let isSectionHeader = rowHTML.contains("areaheader") || rowHTML.contains("areasubheader")
                        let startsRequirement = isSectionHeader
                            || hours?.isEmpty == false
                            || choiceSelectionCount(heading: commentHeading, body: "") != nil
                            || currentCommentHeading == nil
                        if startsRequirement {
                            flushComment()
                            currentCommentHeading = commentHeading
                            currentCommentBody = rowHTML
                        } else {
                            currentCommentBody += rowHTML
                        }
                    } else if currentCommentHeading != nil {
                        currentCommentBody += rowHTML
                    } else {
                        baseBody += rowHTML
                    }
                }
                flushComment()
            }

            blocks.append(RequirementBlock(level: level, heading: heading, body: baseBody))
            blocks.append(contentsOf: commentBlocks)
        }

        return blocks
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
            if isConcreteConcentrationHeading(block.heading) {
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

        let selectedCreditHours = choiceCreditHours(heading: block.heading, body: block.body)
        let selectionCount = selectedCreditHours.map { creditHours in
            choiceCourseCount(for: creditHours, courses: courses)
        } ?? choiceSelectionCount(heading: block.heading, body: block.body)
        let requiredCredits = selectedCreditHours
            ?? parseCredits(from: block.heading)
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

            guard let course = parseCourse(fromListItem: body, catoid: catoid) else {
                return nil
            }
            return .course(course)
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
            let title = cells.count > 1 && cells[1].count > 1 ? HTMLCleaner.clean(cells[1][1]) : ""
            let hoursText = row[1]
                .firstMatch(for: #"(?is)<td\b[^>]*class="[^"]*\bhourscol\b[^"]*"[^>]*>(.*?)</td>"#)
                .flatMap { $0.count > 1 ? HTMLCleaner.clean($0[1]) : nil }
            let links = codeCell[1].matches(for: #"(?is)<a\b[^>]*href="([^"]*/search/\?P=[^"]+)"[^>]*>(.*?)</a>"#)
            let rowCredits = hoursText.flatMap(parseLeadingCredits)
            let perCourseCredits = rowCredits.map { max(Int(ceil(Double($0) / Double(max(links.count, 1)))), 1) } ?? 3

            for link in links where link.count >= 3 {
                let code = HTMLCleaner.clean(link[2])
                guard let parsedCode = code.firstMatch(for: #"^([A-Z]{2,5})\s+(\d{3}[A-Z]?)$"#), parsedCode.count >= 3 else { continue }
                let subject = parsedCode[1]
                let number = parsedCode[2]
                let url = URL(string: HTMLCleaner.decodeEntities(in: link[1]), relativeTo: baseURL)?.absoluteURL
                items.append(.course(Course(
                    id: "\(subject)\(number)",
                    code: "\(subject) \(number)",
                    title: title,
                    credits: perCourseCredits,
                    availability: nil,
                    prerequisites: [],
                    verificationStatus: .partial,
                    registrarURL: url
                )))
            }
        }
        return items
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
        let courseIDs = items.compactMap { item -> String? in
            if case .course(let course) = item { return course.id }
            return nil
        }
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
