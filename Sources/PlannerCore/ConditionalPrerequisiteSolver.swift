import Foundation

/// Decides whether unresolved placeholder slots can supply what scheduled
/// courses still need from real work.
///
/// Each open slot (an unresolved placeholder actually in the schedule) is a
/// variable over its picker menu. A request's expression is first checked
/// against real work; whatever is still missing is bound to slots in the
/// allowed window: earlier semesters for prerequisites, the same or
/// earlier for corequisites, the same semester for lab partners. "and"
/// branches share bindings and "or" branches are tried one at a time. One
/// slot holds one course, one hypothetical course fills at most one slot,
/// and no slot duplicates a course already in the plan. Every bound course
/// must itself be feasible where it sits: its prerequisites (from real
/// work or earlier slots), corequisites, standing, known availability,
/// lab partner, and the semester's credit cap with its hypothetical
/// credits in place of the slot's reservation.
///
/// The search is deterministic and memoized. It explores each connected
/// group of slots and requests independently, against that group's share
/// of the budget; running out makes the result `.unconfirmed`, never
/// feasible or impossible.
public struct ConditionalPrerequisiteSolver: @unchecked Sendable {
    public let catalog: Catalog
    /// Parsed course needs and slot menus, reused across this solver's
    /// solves. Not shared between threads.
    let cache: ConditionalSearchCache

    public init(catalog: Catalog) {
        self.init(catalog: catalog, cache: ConditionalSearchCache(catalog: catalog))
    }

    init(catalog: Catalog, cache: ConditionalSearchCache) {
        self.catalog = catalog
        self.cache = cache
    }

    public func solve(
        _ requests: [ConditionalPrerequisiteRequest],
        in input: ConditionalPrerequisiteInput,
        forcedChoices: [String: String] = [:],
        budget: inout ConditionalSearchBudget
    ) throws -> ConditionalFeasibility {
        try solve(requests, in: input, forcedChoices: forcedChoices, focus: nil, budget: &budget)
    }

    /// `focus` limits the search to the connected groups holding those
    /// requests or a forced slot; the rest are taken as already proven. The
    /// analyzer uses it so admitting one request doesn't re-spend other
    /// groups' budgets.
    func solve(
        _ requests: [ConditionalPrerequisiteRequest],
        in input: ConditionalPrerequisiteInput,
        forcedChoices: [String: String],
        focus: Set<ConditionalDependencyKey>?,
        budget: inout ConditionalSearchBudget
    ) throws -> ConditionalFeasibility {
        let context = SolverContext(catalog: catalog, input: input, cache: cache)
        return try context.solve(requests, forcedChoices: forcedChoices, focus: focus, budget: &budget)
    }
}

/// What a course needs in turn, parsed once.
struct ConditionalCourseNeeds {
    let prerequisite: PrereqExpr
    let corequisite: PrereqExpr
    let labs: [String]
    let lectures: [String]
    /// Every course the needs name: prerequisites, corequisites, lab partners.
    let leaves: Set<String>
}

/// Parsed course needs, slot menus and upstream reach, reused across the
/// many solves of one analysis pass or schedule build. Parsing rules and
/// building 2,700-course Open Elective menus per solve made each one cost
/// tens of milliseconds. Not thread-safe: one owner at a time.
final class ConditionalSearchCache {
    let catalog: Catalog
    let coursesByID: [String: Course]
    private let resolver: PrereqRuleResolver
    private var labPairings: [String?: LabPairing] = [:]
    private var needsByCourse: [String?: [String: ConditionalCourseNeeds?]] = [:]
    private var menus: [PlaceholderSpec: Set<String>] = [:]
    /// Upstream slot reach for one schedule, keyed by course.
    private var reachKey: Int?
    private var reachByCourse: [String: Set<String>] = [:]

    init(catalog: Catalog) {
        self.catalog = catalog
        coursesByID = catalog.coursesByID
        resolver = PrereqRuleResolver(catalog: catalog)
    }

    func labPairing(_ activeProgramTitle: String?) -> LabPairing {
        if let cached = labPairings[activeProgramTitle] { return cached }
        let pairing = LabPairing(catalog: catalog, activeProgramTitle: activeProgramTitle)
        labPairings[activeProgramTitle] = pairing
        return pairing
    }

    func needs(of courseID: String, activeProgramTitle: String?) -> ConditionalCourseNeeds? {
        if let cached = needsByCourse[activeProgramTitle]?[courseID] { return cached }
        var result: ConditionalCourseNeeds?
        if let course = coursesByID[courseID] {
            let rule = resolver.rule(for: course, activeProgramTitle: activeProgramTitle)
            let pairing = labPairing(activeProgramTitle)
            let paired = pairing.pairedCourses(of: courseID)
            let labs = pairing.labOptions(forLecture: courseID)
            let lectures = pairing.lectures(forLab: courseID)
            result = ConditionalCourseNeeds(
                prerequisite: rule.prerequisiteExpr.treatingAsSatisfied(paired),
                corequisite: rule.corequisiteExpr.treatingAsSatisfied(paired),
                labs: labs,
                lectures: lectures,
                leaves: Set(rule.prerequisiteExpr.courseLeaves + rule.corequisiteExpr.courseLeaves + labs + lectures)
            )
        }
        needsByCourse[activeProgramTitle, default: [:]][courseID] = .some(result)
        return result
    }

    /// Whether the slot's menu offers `courseID`. Empty menus (Open
    /// Electives) offer any catalog course without building the set.
    func offers(_ spec: PlaceholderSpec, _ courseID: String) -> Bool {
        if spec.alternates.isEmpty { return coursesByID[courseID] != nil }
        return menu(of: spec).contains(courseID)
    }

    func menu(of spec: PlaceholderSpec) -> Set<String> {
        if let cached = menus[spec] { return cached }
        let menu = Set(PlaceholderCourseDomain.eligibleCourseIDs(for: spec, catalog: catalog))
        menus[spec] = menu
        return menu
    }

    func reach(_ courseID: String, schedule key: Int, compute: () -> Set<String>) -> Set<String> {
        if reachKey != key {
            reachKey = key
            reachByCourse = [:]
        }
        if let cached = reachByCourse[courseID] { return cached }
        let result = compute()
        reachByCourse[courseID] = result
        return result
    }
}

// MARK: - Search

/// When a provider may sit relative to the semester index it serves.
private enum SearchWindow: Hashable {
    case before(Int)
    case through(Int)
    case same(Int)

    func admits(_ index: Int) -> Bool {
        switch self {
        case .before(let limit): index < limit
        case .through(let limit): index <= limit
        case .same(let target): index == target
        }
    }
}

/// Something still to satisfy, on behalf of `root`.
private struct SearchGoal: Hashable {
    var expression: PrereqExpr
    var window: SearchWindow
    var standing: ClassStanding?
    var root: ConditionalDependencyKey
}

private struct SearchState {
    var assignments: [String: String] = [:]
    var uses: Set<ConditionalProviderUse> = []
    /// Forced slots whose own needs are checked when a request first draws
    /// on them, so the chain is credited to that request.
    var unvalidated: Set<String> = []
}

private struct FailureKey: Hashable {
    var goals: [SearchGoal]
    var assignments: [String: String]
    var unvalidated: Set<String>
}

private struct BudgetExhausted: Error {}

private final class SolverContext {
    let catalog: Catalog
    let input: ConditionalPrerequisiteInput
    let coursesByID: [String: Course]
    let cache: ConditionalSearchCache
    let semesters: [SemesterPlan]
    let semesterIndex: [SemesterIdentity: Int]
    /// Open slots in chronological, then in-semester, order.
    let slots: [(id: String, semester: Int)]
    let slotSemester: [String: Int]
    /// Real courses anywhere in the plan or earned before it.
    let allReal: Set<String>
    private var failures: Set<FailureKey> = []
    /// The slots the current group's search may bind.
    private var groupSlots: Set<String> = []
    private let scheduleKey: Int

    init(catalog: Catalog, input: ConditionalPrerequisiteInput, cache: ConditionalSearchCache) {
        self.catalog = catalog
        self.input = input
        self.cache = cache
        coursesByID = cache.coursesByID
        var hasher = Hasher()
        hasher.combine(input.pathway)
        hasher.combine(input.completedAtStart)
        hasher.combine(input.unscheduledCourseIDs)
        hasher.combine(input.activeProgramTitle)
        scheduleKey = hasher.finalize()
        semesters = input.pathway.semesters.sorted { $0.id < $1.id }
        semesterIndex = Dictionary(uniqueKeysWithValues: semesters.enumerated().map { ($1.id, $0) })
        // Only placeholders still in the schedule are open: a resolved slot
        // was replaced by its course, and a removed one is gone, even when
        // its definition is retained for reversal.
        var slots: [(id: String, semester: Int)] = []
        var seen: Set<String> = []
        for (index, semester) in semesters.enumerated() {
            for item in semester.courseIDs
            where PathwayPlaceholder.isPlaceholder(item)
                && input.pathway.placeholders[item] != nil
                && input.pathway.resolvedPlaceholders[item] == nil
                && seen.insert(item).inserted {
                slots.append((item, index))
            }
        }
        self.slots = slots
        slotSemester = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0.semester) })
        allReal = input.completedAtStart.union(input.unscheduledCourseIDs).union(
            semesters.flatMap(\.courseIDs).filter { !PathwayPlaceholder.isPlaceholder($0) }
        )
    }

    // MARK: Entry

    func solve(
        _ requests: [ConditionalPrerequisiteRequest],
        forcedChoices: [String: String],
        focus: Set<ConditionalDependencyKey>?,
        budget: inout ConditionalSearchBudget
    ) throws -> ConditionalFeasibility {
        var start = SearchState()
        for (slot, course) in forcedChoices.sorted(by: { $0.key < $1.key }) {
            guard let semester = slotSemester[slot],
                  offers(slot, course),
                  !allReal.contains(course),
                  !start.assignments.values.contains(course),
                  locallyFeasible(course, at: semester, adding: [slot: course], to: start)
            else { return .impossible }
            start.assignments[slot] = course
            start.unvalidated.insert(slot)
        }

        let goals = requests.map(goal)
        let groups = partition(goals, forcedChoices: forcedChoices)
        var merged = start
        var unconfirmed = false
        for group in groups {
            try Task.checkCancellation()
            if let focus,
               !group.goalIndices.contains(where: { focus.contains(requests[$0].key) }),
               group.slots.isDisjoint(with: forcedChoices.keys) {
                continue
            }
            let groupGoals = group.goalIndices.map { goals[$0] }
            // A group binds only its own slots, so independently solved
            // groups can't hand the same slot two different courses.
            groupSlots = group.slots.union(forcedChoices.keys.filter { group.slots.contains($0) })
            do {
                guard let solved = try search(groupGoals, start, group: group.id, budget: &budget) else {
                    return .impossible
                }
                for (slot, course) in solved.assignments { merged.assignments[slot] = course }
                merged.uses.formUnion(solved.uses)
            } catch is BudgetExhausted {
                unconfirmed = true
            }
        }
        return unconfirmed ? .unconfirmed : .feasible(assignments: merged.assignments, uses: merged.uses)
    }

    private func goal(for request: ConditionalPrerequisiteRequest) -> SearchGoal {
        let index = semesterIndex[request.key.semester] ?? semesters.count
        let window: SearchWindow = switch request.key.kind {
        case .prerequisite: .before(index)
        case .corequisite: .through(index)
        case .labPairing: .same(index)
        }
        return SearchGoal(
            expression: request.expression,
            window: window,
            standing: input.standingBySemester[request.key.semester],
            root: request.key
        )
    }

    // MARK: Depth-first search

    private func search(_ goals: [SearchGoal], _ state: SearchState, group: String, budget: inout ConditionalSearchBudget) throws -> SearchState? {
        try Task.checkCancellation()
        guard budget.spend(group) else { throw BudgetExhausted() }
        guard let goal = goals.first else { return state }
        let failure = FailureKey(goals: goals, assignments: state.assignments, unvalidated: state.unvalidated)
        if failures.contains(failure) { return nil }
        let rest = Array(goals.dropFirst())

        // Real work first: only what it leaves missing needs a slot.
        let result: SearchState?
        switch PrereqEvaluator(completedBefore: realPool(goal.window), scheduledThisTerm: [], standing: goal.standing)
            .evaluate(goal.expression, mode: .prereq) {
        case .satisfied:
            result = try search(rest, state, group: group, budget: &budget)
        case .unmet(let missing, _):
            result = try expand(missing, goal, rest, state, group: group, budget: &budget)
        }
        if result == nil { failures.insert(failure) }
        return result
    }

    private func expand(
        _ expression: PrereqExpr,
        _ goal: SearchGoal,
        _ rest: [SearchGoal],
        _ state: SearchState,
        group: String,
        budget: inout ConditionalSearchBudget
    ) throws -> SearchState? {
        func child(_ expression: PrereqExpr) -> SearchGoal {
            SearchGoal(expression: expression, window: goal.window, standing: goal.standing, root: goal.root)
        }
        switch expression {
        case .empty:
            return try search(rest, state, group: group, budget: &budget)
        case .all(let children):
            return try search(children.map(child) + rest, state, group: group, budget: &budget)
        case .any(let children):
            for branch in children {
                if let found = try search([child(branch)] + rest, state, group: group, budget: &budget) {
                    return found
                }
            }
            return nil
        case .course(let courseID):
            return try provide(courseID, goal, rest, state, group: group, budget: &budget)
        case .standing, .unknown:
            // A slot can't stand in for standing or unparsed permission.
            return nil
        }
    }

    /// Supplies `courseID` from a slot in `goal`'s window: the slot already
    /// holding it, or else each eligible open slot in turn.
    private func provide(
        _ courseID: String,
        _ goal: SearchGoal,
        _ rest: [SearchGoal],
        _ state: SearchState,
        group: String,
        budget: inout ConditionalSearchBudget
    ) throws -> SearchState? {
        if let bound = state.assignments.first(where: { $0.value == courseID })?.key {
            guard let semester = slotSemester[bound], goal.window.admits(semester) else { return nil }
            var next = state
            next.uses.insert(ConditionalProviderUse(placeholderID: bound, supportingCourseID: courseID, dependent: goal.root))
            var needs: [SearchGoal] = []
            if next.unvalidated.remove(bound) != nil {
                needs = providerGoals(for: courseID, at: semester, root: goal.root, state: next)
            }
            return try search(needs + rest, next, group: group, budget: &budget)
        }
        guard !allReal.contains(courseID) else { return nil }
        for slot in slots where goal.window.admits(slot.semester) && state.assignments[slot.id] == nil && groupSlots.contains(slot.id) {
            guard offers(slot.id, courseID),
                  locallyFeasible(courseID, at: slot.semester, adding: [slot.id: courseID], to: state)
            else { continue }
            var next = state
            next.assignments[slot.id] = courseID
            next.uses.insert(ConditionalProviderUse(placeholderID: slot.id, supportingCourseID: courseID, dependent: goal.root))
            let needs = providerGoals(for: courseID, at: slot.semester, root: goal.root, state: next)
            if let found = try search(needs + rest, next, group: group, budget: &budget) {
                return found
            }
        }
        return nil
    }

    // MARK: Provider feasibility

    /// What a hypothetical `courseID` in semester `index` needs in turn.
    private func providerGoals(for courseID: String, at index: Int, root: ConditionalDependencyKey, state: SearchState) -> [SearchGoal] {
        guard let needs = cache.needs(of: courseID, activeProgramTitle: input.activeProgramTitle) else { return [] }
        let standing = input.standingBySemester[semesters[index].id]
        var goals = [
            SearchGoal(expression: needs.prerequisite, window: .before(index), standing: standing, root: root),
            SearchGoal(expression: needs.corequisite, window: .through(index), standing: standing, root: root)
        ]
        // A lecture needs its lab beside it, and a lab its lecture: real
        // work, the lecture's lab placeholder, or another slot there.
        let items = Set(semesters[index].courseIDs)
        if !needs.labs.isEmpty, !items.contains(LabPairing.labPlaceholderID(forLecture: courseID)) {
            goals.append(SearchGoal(expression: .any(needs.labs.map(PrereqExpr.course)), window: .same(index), standing: nil, root: root))
        }
        if !needs.lectures.isEmpty {
            goals.append(SearchGoal(expression: .any(needs.lectures.map(PrereqExpr.course)), window: .same(index), standing: nil, root: root))
        }
        return goals
    }

    /// Known availability and the semester's credit cap, with every bound
    /// slot there counted at its hypothetical course's credits.
    private func locallyFeasible(_ courseID: String, at index: Int, adding binding: [String: String], to state: SearchState) -> Bool {
        guard let course = coursesByID[courseID] else { return false }
        let semester = semesters[index]
        if let availability = course.availability, !availability.contains(semester.term) { return false }
        guard let workload = input.workload else { return true }
        let bound = state.assignments.merging(binding) { _, new in new }
        var reserved = 0.0
        var hypothetical = 0.0
        for item in semester.courseIDs {
            if let spec = input.pathway.placeholders[item], PathwayPlaceholder.isPlaceholder(item) {
                reserved += spec.credits
                if let choice = bound[item], let chosen = coursesByID[choice] {
                    hypothetical += Double(chosen.credits)
                } else {
                    hypothetical += spec.credits
                }
            } else {
                let credits = semester.creditOverrides[item] ?? Double(coursesByID[item]?.credits ?? 0)
                reserved += credits
                hypothetical += credits
            }
        }
        // Only a choice that pushes the term over the cap is ruled out; a
        // term already over it isn't the choice's doing.
        let cap = Double(workload.creditRange.upperBound)
        return hypothetical <= cap || hypothetical <= reserved
    }

    // MARK: Pools and domains

    private func realPool(_ window: SearchWindow) -> Set<String> {
        var pool: Set<String> = []
        if case .same = window {} else { pool = input.completedAtStart }
        for (index, semester) in semesters.enumerated() where window.admits(index) {
            pool.formUnion(semester.courseIDs.filter { !PathwayPlaceholder.isPlaceholder($0) })
        }
        return pool
    }

    func offers(_ slot: String, _ courseID: String) -> Bool {
        guard let spec = input.pathway.placeholders[slot] else { return false }
        return cache.offers(spec, courseID)
    }

    // MARK: Connected groups

    private struct Group {
        var id: String
        var goalIndices: [Int]
        var slots: Set<String>
    }

    /// Requests that could draw on the same slots, directly or through a
    /// provider chain, are searched together; the rest independently.
    private func partition(_ goals: [SearchGoal], forcedChoices: [String: String]) -> [Group] {
        // A forced choice draws on whatever its own course needs, too.
        let forced = forcedChoices.sorted { $0.key < $1.key }
        let relevant = goals.map { goal in relevantSlots(for: goal.expression) }
            + forced.map { slot, course in
                relevantSlots(for: .all((cache.needs(of: course, activeProgramTitle: input.activeProgramTitle)?.leaves ?? []).sorted().map(PrereqExpr.course)))
                    .union([slot])
            }
        let forcedSlots = Set(forcedChoices.keys)
        var groupOf = Array(relevant.indices)
        func find(_ index: Int) -> Int {
            var index = index
            while groupOf[index] != index { index = groupOf[index] }
            return index
        }
        var owner: [String: Int] = [:]
        for (index, slots) in relevant.enumerated() {
            for slot in slots.sorted() {
                if let other = owner[slot] {
                    groupOf[find(index)] = find(other)
                } else {
                    owner[slot] = index
                }
            }
        }
        var groups: [Int: Group] = [:]
        var order: [Int] = []
        for index in relevant.indices {
            let root = find(index)
            if groups[root] == nil {
                groups[root] = Group(id: "", goalIndices: [], slots: [])
                order.append(root)
            }
            if index < goals.count {
                groups[root]!.goalIndices.append(index)
            }
            groups[root]!.slots.formUnion(relevant[index])
        }
        var result = order.map { groups[$0]! }
        // A forced slot nothing draws on is still checked on its own.
        for slot in forcedSlots.sorted() where !result.contains(where: { $0.slots.contains(slot) }) {
            result.append(Group(id: "", goalIndices: [], slots: [slot]))
        }
        for index in result.indices {
            let slots = result[index].slots.sorted()
            result[index].id = slots.isEmpty
                ? "requests:" + result[index].goalIndices.map(String.init).joined(separator: ",")
                : slots.joined(separator: "|")
        }
        return result
    }

    /// Open slots whose menus hold a course the expression names, or a
    /// course those courses need in turn (bounded). Only a course a slot
    /// could supply leads further upstream: a planned or earned course
    /// never comes from a slot, so its own needs don't matter here.
    private func relevantSlots(for expression: PrereqExpr) -> Set<String> {
        Set(expression.courseLeaves).reduce(into: Set<String>()) { result, leaf in
            result.formUnion(cache.reach(leaf, schedule: scheduleKey) { reach(from: leaf) })
        }
    }

    private func reach(from courseID: String) -> Set<String> {
        var pending = [courseID]
        var visited: Set<String> = []
        var result: Set<String> = []
        while let current = pending.popLast(), visited.count < 2_000 {
            guard visited.insert(current).inserted, !allReal.contains(current) else { continue }
            let holders = slots.filter { offers($0.id, current) }.map(\.id)
            guard !holders.isEmpty else { continue }
            result.formUnion(holders)
            let upstream = cache.needs(of: current, activeProgramTitle: input.activeProgramTitle)?.leaves ?? []
            pending.append(contentsOf: upstream.subtracting(visited).sorted())
        }
        return result
    }
}
