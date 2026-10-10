import Foundation

/// Reads a plan chronologically and works out which scheduled courses can
/// rely on unresolved placeholder slots, and which slot choices support
/// them.
///
/// Each scheduled course yields prerequisite, corequisite and lab-pairing
/// requests. One real work satisfies needs nothing. The rest are admitted
/// in schedule order, each only if it's compatible with every request
/// admitted before it; the whole set is re-solved each time, so no single
/// search witness is pinned as the plan's choice. A request that can't join
/// is unmet; one the budget can't decide is unconfirmed.
///
/// A slot option is marked as supporting a course only when forcing the
/// slot to that option still admits every admitted request and the proof
/// actually draws on the slot; merely compatible options get no mark.
public final class PlaceholderPrerequisiteAnalyzer {
    public let catalog: Catalog
    public let workLimitPerGroup: Int
    private let coursesByID: [String: Course]
    private let resolver: PrereqRuleResolver
    /// Shared with this analyzer's solves so rules are parsed and menus built
    /// once per pass or build, not per solve.
    private let cache: ConditionalSearchCache
    private let solver: ConditionalPrerequisiteSolver
    private var priorityCache: (key: Int, needed: Set<String>)?

    public init(catalog: Catalog, workLimitPerGroup: Int = 10_000) {
        self.catalog = catalog
        self.workLimitPerGroup = workLimitPerGroup
        coursesByID = catalog.coursesByID
        resolver = PrereqRuleResolver(catalog: catalog)
        cache = ConditionalSearchCache(catalog: catalog)
        solver = ConditionalPrerequisiteSolver(catalog: catalog, cache: cache)
    }

    public func analyze(_ input: ConditionalPrerequisiteInput) throws -> PlaceholderPrerequisiteAnalysis {
        let labPairing = cache.labPairing(input.activeProgramTitle)
        var budget = ConditionalSearchBudget(limitPerGroup: workLimitPerGroup)
        var status: [ConditionalDependencyKey: ConditionalPrerequisiteStatus] = [:]
        var admitted: [ConditionalPrerequisiteRequest] = []

        for request in requests(in: input, labPairing: labPairing) {
            try Task.checkCancellation()
            if satisfiedByRealWork(request, in: input) {
                status[request.key] = .satisfied
                continue
            }
            // Only the new request's group is re-solved; the rest were
            // proven when their own requests were admitted.
            switch try solver.solve(admitted + [request], in: input, forcedChoices: [:], focus: [request.key], budget: &budget) {
            case .feasible:
                status[request.key] = .conditional
                admitted.append(request)
            case .impossible:
                status[request.key] = .unmet
            case .unconfirmed:
                status[request.key] = .unconfirmed
            }
        }

        var supports: [String: [String: Set<ConditionalDependencyKey>]] = [:]
        if !admitted.isEmpty {
            // Only a course no real work already covers can be a slot's
            // supporting choice; those are the options worth probing.
            let planned = input.completedAtStart.union(input.unscheduledCourseIDs).union(
                input.pathway.semesters.flatMap(\.courseIDs).filter { !PathwayPlaceholder.isPlaceholder($0) }
            )
            let relevant = closure(of: admitted.flatMap(\.expression.courseLeaves), excluding: planned, activeProgramTitle: input.activeProgramTitle)
            for slot in openSlots(in: input.pathway) {
                guard let spec = input.pathway.placeholders[slot] else { continue }
                for option in PlaceholderCourseDomain.eligibleCourseIDs(for: spec, catalog: catalog) where relevant.contains(option) {
                    try Task.checkCancellation()
                    // A probe the budget can't finish proves nothing, so the
                    // option simply stays unmarked.
                    guard case .feasible(_, let uses) = try solver.solve(admitted, in: input, forcedChoices: [slot: option], focus: [], budget: &budget) else {
                        continue
                    }
                    let supported = Set(uses.filter { $0.placeholderID == slot && $0.supportingCourseID == option }.map(\.dependent))
                    if !supported.isEmpty {
                        supports[slot, default: [:]][option] = supported
                    }
                }
            }
        }
        return PlaceholderPrerequisiteAnalysis(statusByDependency: status, supportsByPlaceholder: supports)
    }

    // MARK: Requests

    /// Every scheduled course's prerequisite, corequisite and lab-pairing
    /// needs that name courses, in schedule order.
    func requests(in input: ConditionalPrerequisiteInput, labPairing: LabPairing) -> [ConditionalPrerequisiteRequest] {
        var result: [ConditionalPrerequisiteRequest] = []
        for semester in input.pathway.semesters.sorted(by: { $0.id < $1.id }) {
            let items = Set(semester.courseIDs)
            for courseID in semester.courseIDs where !PathwayPlaceholder.isPlaceholder(courseID) {
                guard let course = coursesByID[courseID] else { continue }
                let rule = resolver.rule(for: course, activeProgramTitle: input.activeProgramTitle)
                let paired = labPairing.pairedCourses(of: courseID)
                var needs: [(ConditionalDependencyKind, PrereqExpr)] = [
                    (.prerequisite, rule.prerequisiteExpr.treatingAsSatisfied(paired)),
                    (.corequisite, rule.corequisiteExpr.treatingAsSatisfied(paired))
                ]
                let labs = labPairing.labOptions(forLecture: courseID)
                if !labs.isEmpty, !items.contains(LabPairing.labPlaceholderID(forLecture: courseID)) {
                    needs.append((.labPairing, .any(labs.map(PrereqExpr.course))))
                }
                let lectures = labPairing.lectures(forLab: courseID)
                if !lectures.isEmpty {
                    needs.append((.labPairing, .any(lectures.map(PrereqExpr.course))))
                }
                for (kind, expression) in needs where !expression.courseLeaves.isEmpty {
                    result.append(ConditionalPrerequisiteRequest(
                        key: ConditionalDependencyKey(courseID: courseID, semester: semester.id, kind: kind),
                        expression: expression
                    ))
                }
            }
        }
        return result
    }

    private func satisfiedByRealWork(_ request: ConditionalPrerequisiteRequest, in input: ConditionalPrerequisiteInput) -> Bool {
        let real = { (semester: SemesterPlan) in semester.courseIDs.filter { !PathwayPlaceholder.isPlaceholder($0) } }
        let target = request.key.semester
        var pool: Set<String> = []
        switch request.key.kind {
        case .prerequisite:
            pool = input.completedAtStart.union(input.pathway.semesters.filter { $0.id < target }.flatMap(real))
        case .corequisite:
            pool = input.completedAtStart.union(input.pathway.semesters.filter { $0.id <= target }.flatMap(real))
        case .labPairing:
            pool = Set(input.pathway.semesters.filter { $0.id == target }.flatMap(real))
        }
        let outcome = PrereqEvaluator(completedBefore: pool, scheduledThisTerm: [], standing: input.standingBySemester[target])
            .evaluate(request.expression, mode: .prereq)
        return outcome == .satisfied
    }

    /// Unresolved placeholders still in the schedule, in schedule order.
    private func openSlots(in pathway: Pathway) -> [String] {
        var seen: Set<String> = []
        return pathway.semesters.sorted { $0.id < $1.id }.flatMap(\.courseIDs).filter { item in
            PathwayPlaceholder.isPlaceholder(item)
                && pathway.placeholders[item] != nil
                && pathway.resolvedPlaceholders[item] == nil
                && seen.insert(item).inserted
        }
    }

    /// `courseIDs` plus the courses they need in turn (prerequisites,
    /// corequisites, lab partners), cycle-safe and bounded. Courses in
    /// `excluding` are already real work: dropped, and not followed further.
    private func closure(of courseIDs: [String], excluding planned: Set<String>, activeProgramTitle: String?) -> Set<String> {
        var pending = Array(Set(courseIDs)).sorted()
        var visited: Set<String> = []
        while let courseID = pending.popLast(), visited.count < 2_000 {
            guard !planned.contains(courseID), visited.insert(courseID).inserted else { continue }
            let upstream = cache.needs(of: courseID, activeProgramTitle: activeProgramTitle)?.leaves ?? []
            pending.append(contentsOf: upstream.subtracting(visited).sorted())
        }
        return visited
    }

    // MARK: Generation support

    /// The prerequisite request `courseID` would make in `semester` when
    /// unresolved earlier slots can conditionally satisfy it alongside
    /// `admitted`; nil when nothing can (or the search can't decide).
    func conditionalPrerequisite(
        for courseID: String,
        in semester: SemesterIdentity,
        input: ConditionalPrerequisiteInput,
        admitted: [ConditionalPrerequisiteRequest],
        budget: inout ConditionalSearchBudget
    ) throws -> ConditionalPrerequisiteRequest? {
        guard let course = coursesByID[courseID] else { return nil }
        let labPairing = cache.labPairing(input.activeProgramTitle)
        let expression = resolver.rule(for: course, activeProgramTitle: input.activeProgramTitle).prerequisiteExpr
            .treatingAsSatisfied(labPairing.pairedCourses(of: courseID))
        let request = ConditionalPrerequisiteRequest(
            key: ConditionalDependencyKey(courseID: courseID, semester: semester, kind: .prerequisite),
            expression: expression
        )
        // Each course still missing must come from an earlier slot's menu;
        // when no slot offers any of them, skip the search.
        guard case .unmet(let missing, _) = PrereqEvaluator(
            completedBefore: realBefore(semester, in: input),
            scheduledThisTerm: [],
            standing: input.standingBySemester[semester]
        ).evaluate(expression, mode: .prereq) else { return nil }
        let earlierSlots = openSlots(in: input.pathway).filter { slot in
            input.pathway.semesters.contains { $0.id < semester && $0.courseIDs.contains(slot) }
        }
        let offered = missing.courseLeaves.contains { leaf in
            earlierSlots.contains { slot in
                input.pathway.placeholders[slot].map { cache.offers($0, leaf) } ?? false
            }
        }
        guard offered else { return nil }
        let result = try solver
            .solve(admitted + [request], in: input, forcedChoices: [:], focus: [request.key], budget: &budget)
        if case .feasible = result { return request }
        return nil
    }

    /// Whether a needed slot should wait: none of the courses pending work
    /// needs from its menu could sit in `semester` yet, but a later term
    /// would offer one, or another pending slot could supply what they lack
    /// once placed. Placing it now would put the course in a term it isn't
    /// offered, or before its own prerequisite.
    func slotShouldWait(
        _ slot: String,
        in semester: SemesterIdentity,
        input: ConditionalPrerequisiteInput,
        admitted: [ConditionalPrerequisiteRequest],
        pendingCourseIDs: [String],
        completedCourseIDs: Set<String>,
        placeholders: [String: PlaceholderSpec],
        budget: inout ConditionalSearchBudget
    ) throws -> Bool {
        guard let spec = placeholders[slot] else { return false }
        let needed = neededCourses(pendingCourseIDs: pendingCourseIDs, completedCourseIDs: completedCourseIDs, activeProgramTitle: input.activeProgramTitle)
        let options = Array(needed.sorted().filter { cache.offers(spec, $0) }.prefix(25))
        guard !options.isEmpty else { return false }
        let labPairing = cache.labPairing(input.activeProgramTitle)
        let pool = realBefore(semester, in: input)
        var lacking: Set<String> = []
        var offeredInAnotherTerm = false
        for option in options {
            guard let course = coursesByID[option] else { continue }
            if let availability = course.availability, !availability.contains(semester.term) {
                offeredInAnotherTerm = offeredInAnotherTerm || !availability.isEmpty
                continue
            }
            let expression = resolver.rule(for: course, activeProgramTitle: input.activeProgramTitle).prerequisiteExpr
                .treatingAsSatisfied(labPairing.pairedCourses(of: option))
            guard case .unmet(let missing, _) = PrereqEvaluator(
                completedBefore: pool, scheduledThisTerm: [], standing: input.standingBySemester[semester]
            ).evaluate(expression, mode: .prereq) else { return false }
            let request = ConditionalPrerequisiteRequest(
                key: ConditionalDependencyKey(courseID: option, semester: semester, kind: .prerequisite),
                expression: expression
            )
            if case .feasible = try solver
                .solve(admitted + [request], in: input, forcedChoices: [:], focus: [request.key], budget: &budget) {
                return false
            }
            lacking.formUnion(missing.courseLeaves)
        }
        if offeredInAnotherTerm { return true }
        let otherSlots = pendingCourseIDs.filter { $0 != slot && PathwayPlaceholder.isPlaceholder($0) }.compactMap { placeholders[$0] }
        return lacking.contains { leaf in otherSlots.contains { cache.offers($0, leaf) } }
    }

    private func realBefore(_ semester: SemesterIdentity, in input: ConditionalPrerequisiteInput) -> Set<String> {
        input.completedAtStart.union(
            input.pathway.semesters.filter { $0.id < semester }.flatMap(\.courseIDs).filter { !PathwayPlaceholder.isPlaceholder($0) }
        )
    }


    // MARK: Generation urgency

    /// Scheduling urgency for `itemID` while `pendingCourseIDs` still wait
    /// to be placed: 0 for the slot designated to supply a course the
    /// pending courses still need (directly or through a chain), 1 for
    /// everything else. Lower values go earlier.
    ///
    /// Each needed course designates one slot: the first pending slot with
    /// a restricted menu offering it that isn't already designated, or else
    /// one Open Elective. Open Electives offer every course, so letting all
    /// of them rank urgent would crowd real requirements out of early terms.
    public func providerPriority(
        itemID: String,
        pendingCourseIDs: [String],
        completedCourseIDs: Set<String>,
        placeholders: [String: PlaceholderSpec],
        activeProgramTitle: String?
    ) -> Int {
        guard PathwayPlaceholder.isPlaceholder(itemID), placeholders[itemID] != nil else { return 1 }
        let urgent = urgentSlots(pendingCourseIDs: pendingCourseIDs, completedCourseIDs: completedCourseIDs, placeholders: placeholders, activeProgramTitle: activeProgramTitle)
        return urgent.contains(itemID) ? 0 : 1
    }

    private var urgencyCache: (key: Int, urgent: Set<String>)?

    private func urgentSlots(
        pendingCourseIDs: [String],
        completedCourseIDs: Set<String>,
        placeholders: [String: PlaceholderSpec],
        activeProgramTitle: String?
    ) -> Set<String> {
        var hasher = Hasher()
        hasher.combine(pendingCourseIDs)
        hasher.combine(completedCourseIDs)
        hasher.combine(placeholders)
        hasher.combine(activeProgramTitle)
        let key = hasher.finalize()
        if let cached = urgencyCache, cached.key == key { return cached.urgent }

        let needed = neededCourses(pendingCourseIDs: pendingCourseIDs, completedCourseIDs: completedCourseIDs, activeProgramTitle: activeProgramTitle)
        let slots = pendingCourseIDs.filter { PathwayPlaceholder.isPlaceholder($0) && placeholders[$0] != nil }
        let restricted = slots.filter { !(placeholders[$0]?.alternates.isEmpty ?? true) }
        let open = slots.filter { placeholders[$0]?.alternates.isEmpty ?? false }
        var urgent: Set<String> = []
        for course in needed.sorted() {
            let offering = restricted.filter { cache.offers(placeholders[$0]!, course) }
            if let slot = offering.first(where: { !urgent.contains($0) }) ?? offering.first {
                urgent.insert(slot)
            } else if let slot = open.first(where: { !urgent.contains($0) }) {
                urgent.insert(slot)
            }
        }
        urgencyCache = (key, urgent)
        return urgent
    }

    /// Courses the pending real courses still need and don't have, followed
    /// upstream through what those courses need in turn.
    private func neededCourses(pendingCourseIDs: [String], completedCourseIDs: Set<String>, activeProgramTitle: String?) -> Set<String> {
        var hasher = Hasher()
        hasher.combine(pendingCourseIDs)
        hasher.combine(completedCourseIDs)
        hasher.combine(activeProgramTitle)
        let key = hasher.finalize()
        if let cached = priorityCache, cached.key == key { return cached.needed }

        let labPairing = cache.labPairing(activeProgramTitle)
        let pending = Set(pendingCourseIDs)
        var missing: [String] = []
        for courseID in pendingCourseIDs where !PathwayPlaceholder.isPlaceholder(courseID) {
            guard let course = coursesByID[courseID] else { continue }
            let rule = resolver.rule(for: course, activeProgramTitle: activeProgramTitle)
            let paired = labPairing.pairedCourses(of: courseID)
            let expression = PrereqExpr.all([rule.prerequisiteExpr, rule.corequisiteExpr]).treatingAsSatisfied(paired)
            missing += expression.courseLeaves.filter { !completedCourseIDs.contains($0) && !pending.contains($0) }
        }
        var needed: Set<String> = []
        var queue = Array(Set(missing)).sorted()
        while let courseID = queue.popLast(), needed.count < 2_000 {
            guard needed.insert(courseID).inserted else { continue }
            let upstream = (cache.needs(of: courseID, activeProgramTitle: activeProgramTitle)?.leaves ?? [])
                .filter { !completedCourseIDs.contains($0) && !pending.contains($0) && !needed.contains($0) }
            queue.append(contentsOf: upstream.sorted())
        }
        priorityCache = (key, needed)
        return needed
    }
}
