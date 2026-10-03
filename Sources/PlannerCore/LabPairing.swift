import Foundation

/// Lecture/lab pairs that must be taken in the same semester, read from the
/// coreqs. A lecture needs a lab when its coreqs name its own lab ("BIO
/// 140L" for BIO 140), along with any labs offered as alternatives to it
/// (CHEM 132: "CHEM 132L or CHEM 136L"). A lab needs its lecture: the
/// same-number course its coreqs name, the single course they name (CHEM
/// 136L: "CHEM 132"), or a lecture that lists the lab. Lectures whose lab
/// is optional (PHYS 140, whose coreqs don't name PHYS 140L) stand alone.
public struct LabPairing: Sendable {
    private let coursesByID: [String: Course]
    private let resolver: PrereqRuleResolver
    private let activeProgramTitle: String?

    /// Pairs are computed per course on demand, so building one is cheap.
    public init(catalog: Catalog, activeProgramTitle: String? = nil) {
        self.coursesByID = catalog.coursesByID
        self.resolver = PrereqRuleResolver(catalog: catalog)
        self.activeProgramTitle = activeProgramTitle
    }

    /// Labs that satisfy `lectureID`'s lab requirement; empty when the
    /// lecture can be taken without one.
    public func labOptions(forLecture lectureID: String) -> [String] {
        guard !Self.isLab(lectureID), let coreq = corequisites(of: lectureID) else { return [] }
        return Self.labGroup(containing: lectureID + "L", in: coreq) ?? []
    }

    /// Lectures `labID` must be taken alongside.
    public func lectures(forLab labID: String) -> [String] {
        guard Self.isLab(labID), let coreq = corequisites(of: labID) else { return [] }
        let named = Set(coreq.courseLeaves.filter { !Self.isLab($0) })
        let ownLecture = String(labID.dropLast())
        var lectures: Set<String> = []
        if named.contains(ownLecture) {
            lectures.insert(ownLecture)
        } else if named.count == 1, let lecture = named.first {
            lectures.insert(lecture)
        }
        // A lecture can name the lab without the lab naming it back (CHEM
        // 132 lists CHEM 132L).
        for candidate in named.union([ownLecture]) where labOptions(forLecture: candidate).contains(labID) {
            lectures.insert(candidate)
        }
        return lectures.sorted()
    }

    private func corequisites(of courseID: String) -> PrereqExpr? {
        guard let course = coursesByID[courseID] else { return nil }
        return resolver.rule(for: course, activeProgramTitle: activeProgramTitle).corequisiteExpr
    }

    /// The schedule item that travels with `itemID`: a lecture's lab (or
    /// lab placeholder), a lab's lecture, or a lab placeholder's lecture.
    /// Prefers one in the same semester. Empty when nothing pairs with it.
    public func partners(of itemID: String, in pathway: Pathway) -> [String] {
        let candidates: [String]
        if let lecture = Self.lecture(forLabPlaceholder: itemID) {
            candidates = [lecture]
        } else if Self.isLab(itemID) {
            candidates = lectures(forLab: itemID)
        } else {
            let labs = labOptions(forLecture: itemID)
            candidates = labs.isEmpty ? [] : labs + [Self.labPlaceholderID(forLecture: itemID)]
        }
        guard !candidates.isEmpty else { return [] }
        let semesters = pathway.semesters.sorted { $0.id < $1.id }
        let home = semesters.first { $0.courseIDs.contains(itemID) }
        if let match = home?.courseIDs.first(where: candidates.contains) { return [match] }
        for semester in semesters {
            if let match = semester.courseIDs.first(where: candidates.contains) { return [match] }
        }
        return []
    }

    /// `pathway` with `itemID` and its partners moved into `semester`, the
    /// item at `index` (counted after removing it) and its partners right
    /// after it.
    public func moving(_ itemID: String, to semester: SemesterIdentity, at index: Int?, in pathway: Pathway) -> Pathway {
        Self.moving([itemID] + partners(of: itemID, in: pathway), to: semester, at: index, in: pathway)
    }

    /// `pathway` with `group` moved, in order, into `semester` at `index`
    /// (counted after removing them).
    public static func moving(_ group: [String], to semester: SemesterIdentity, at index: Int?, in pathway: Pathway) -> Pathway {
        // Per-item credit and title overrides travel with the item.
        var creditOverrides: [String: Double] = [:]
        var courseTitles: [String: String] = [:]
        var result = pathway
        for semesterIndex in result.semesters.indices {
            for item in group {
                if let credits = result.semesters[semesterIndex].creditOverrides.removeValue(forKey: item) {
                    creditOverrides[item] = credits
                }
                if let title = result.semesters[semesterIndex].courseTitles.removeValue(forKey: item) {
                    courseTitles[item] = title
                }
            }
            result.semesters[semesterIndex].courseIDs.removeAll(where: group.contains)
        }
        if let target = result.semesters.firstIndex(where: { $0.id == semester }) {
            let count = result.semesters[target].courseIDs.count
            let position = min(max(index ?? count, 0), count)
            result.semesters[target].courseIDs.insert(contentsOf: group, at: position)
        } else {
            result.semesters.append(SemesterPlan(id: semester, courseIDs: group))
            result.semesters.sort { $0.id < $1.id }
        }
        if let target = result.semesters.firstIndex(where: { $0.id == semester }) {
            result.semesters[target].creditOverrides.merge(creditOverrides) { _, moved in moved }
            result.semesters[target].courseTitles.merge(courseTitles) { _, moved in moved }
        }
        return result
    }

    /// `pathway` with `lectureID`'s lab in `semester`: unchanged when one is
    /// there, an already-planned lab moved in, or else the lab added — the
    /// course when only one lab fits, a lab placeholder when several do.
    public func addingLab(for lectureID: String, in semester: SemesterIdentity, to pathway: Pathway) -> Pathway {
        let labs = labOptions(forLecture: lectureID)
        guard !labs.isEmpty,
              let target = pathway.semesters.firstIndex(where: { $0.id == semester })
        else { return pathway }
        let placeholder = Self.labPlaceholderID(forLecture: lectureID)
        let candidates = labs + [placeholder]
        guard !pathway.semesters[target].courseIDs.contains(where: candidates.contains) else { return pathway }

        var result = pathway
        let item: String
        if let existing = candidates.first(where: { candidate in pathway.semesters.contains { $0.courseIDs.contains(candidate) } }) {
            item = existing
            for semesterIndex in result.semesters.indices {
                result.semesters[semesterIndex].courseIDs.removeAll { $0 == existing }
            }
        } else if labs.count == 1 {
            item = labs[0]
        } else {
            item = placeholder
            result.placeholders[placeholder] = labPlaceholderSpec(forLecture: lectureID)
        }
        let courseIDs = result.semesters[target].courseIDs
        let position = courseIDs.firstIndex(of: lectureID).map { $0 + 1 } ?? courseIDs.count
        result.semesters[target].courseIDs.insert(item, at: position)
        return result
    }

    /// The "Lab for CHEM 132" placeholder's choices.
    public func labPlaceholderSpec(forLecture lectureID: String) -> PlaceholderSpec {
        let labs = labOptions(forLecture: lectureID)
        return PlaceholderSpec(
            categoryID: Self.labPlaceholderCategoryPrefix + lectureID,
            categoryName: "Lab for \(coursesByID[lectureID]?.code ?? lectureID)",
            alternates: labs,
            credits: labs.compactMap { coursesByID[$0]?.credits }.max() ?? 1
        )
    }

    /// Courses that pair with `courseID`: a lecture's labs or a lab's
    /// lectures. Taken in the same semester, each satisfies the other's
    /// listed prerequisite (BIO 140 and BIO 140L list each other).
    public func pairedCourses(of courseID: String) -> Set<String> {
        Set(labOptions(forLecture: courseID) + lectures(forLab: courseID))
    }

    /// "CHEM 132L", "BIO 140L": a course number ending in L.
    public static func isLab(_ courseID: String) -> Bool {
        guard courseID.last == "L", courseID.count > 1 else { return false }
        return courseID.dropLast().last?.isNumber == true
    }

    private static let labPlaceholderCategoryPrefix = "lab-"

    /// Placeholder for a lecture's lab when more than one lab satisfies it.
    public static func labPlaceholderID(forLecture lectureID: String) -> String {
        PathwayPlaceholder.id(categoryID: labPlaceholderCategoryPrefix + lectureID, optionIndex: 0)
    }

    /// The lecture a lab placeholder belongs to, or nil for other items.
    public static func lecture(forLabPlaceholder itemID: String) -> String? {
        guard PathwayPlaceholder.isPlaceholder(itemID) else { return nil }
        let categoryID = itemID.dropFirst(PathwayPlaceholder.prefix.count)
            .components(separatedBy: "::")
            .first ?? ""
        guard categoryID.hasPrefix(labPlaceholderCategoryPrefix) else { return nil }
        return String(categoryID.dropFirst(labPlaceholderCategoryPrefix.count))
    }

    /// The labs offered together with `lab` in `expr`: the "or" group it
    /// sits in, or just `lab`. Nil when `expr` doesn't name `lab`.
    private static func labGroup(containing lab: String, in expr: PrereqExpr) -> [String]? {
        switch expr {
        case .course(let id):
            return id == lab ? [lab] : nil
        case .any(let children) where children.contains(.course(lab)):
            return children.compactMap { child in
                if case .course(let id) = child, isLab(id) { return id }
                return nil
            }
        case .all(let children), .any(let children):
            return children.lazy.compactMap { labGroup(containing: lab, in: $0) }.first
        default:
            return nil
        }
    }
}

extension PrereqExpr {
    /// The expression with each course in `courseIDs` counted as met, so an
    /// "or" naming one of them is satisfied and an "and" no longer needs it.
    func treatingAsSatisfied(_ courseIDs: Set<String>) -> PrereqExpr {
        guard !courseIDs.isEmpty else { return self }
        switch self {
        case .course(let id) where courseIDs.contains(id):
            return .empty
        case .all(let children):
            return .all(children.map { $0.treatingAsSatisfied(courseIDs) })
        case .any(let children):
            return .any(children.map { $0.treatingAsSatisfied(courseIDs) })
        default:
            return self
        }
    }
}
