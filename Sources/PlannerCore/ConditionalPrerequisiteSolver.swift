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
public struct ConditionalPrerequisiteSolver: Sendable {
    public let catalog: Catalog

    public init(catalog: Catalog) {
        self.catalog = catalog
    }

    public func solve(
        _ requests: [ConditionalPrerequisiteRequest],
        in input: ConditionalPrerequisiteInput,
        forcedChoices: [String: String] = [:],
        budget: inout ConditionalSearchBudget
    ) throws -> ConditionalFeasibility {
        let context = SolverContext(catalog: catalog, input: input)
        return try context.solve(requests, forcedChoices: forcedChoices, budget: &budget)
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
}

private struct FailureKey: Hashable {
    var goals: [SearchGoal]
    var assignments: [String: String]
}

private struct BudgetExhausted: Error {}

private final class SolverContext {
    let catalog: Catalog
    let input: ConditionalPrerequisiteInput
    let coursesByID: [String: Course]
    let resolver: PrereqRuleResolver
    let labPairing: LabPairing
    let semesters: [SemesterPlan]
    let semesterIndex: [SemesterIdentity: Int]
    /// Open slots in chronological, then in-semester, order.
    let slots: [(id: String, semester: Int)]
    let slotSemester: [String: Int]
    /// Real courses anywhere in the plan or earned before it.
    let allReal: Set<String>
    private var domains: [String: Set<String>] = [:]
    private var failures: Set<FailureKey> = []
    private var dependencyLeaves: [String: Set<String>] = [:]

    init(catalog: Catalog, input: ConditionalPrerequisiteInput) {
        self.catalog = catalog
        self.input = input
        coursesByID = catalog.coursesByID
        resolver = PrereqRuleResolver(catalog: catalog)
        labPairing = LabPairing(catalog: catalog, activeProgramTitle: input.activeProgramTitle)
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
        allReal = input.completedAtStart.union(
            semesters.flatMap(\.courseIDs).filter { !PathwayPlaceholder.isPlaceholder($0) }
        )
    }

    // MARK: Entry

    func solve(
        _ requests: [ConditionalPrerequisiteRequest],
        forcedChoices: [String: String],
        budget: inout ConditionalSearchBudget
    ) throws -> ConditionalFeasibility {
        var start = SearchState()
        var forcedGoals: [String: [SearchGoal]] = [:]
        for (slot, course) in forcedChoices.sorted(by: { $0.key < $1.key }) {
            guard let semester = slotSemester[slot],
                  domain(of: slot).contains(course),
                  !allReal.contains(course),
                  !start.assignments.values.contains(course),
                  locallyFeasible(course, at: semester, adding: [slot: course], to: start)
            else { return .impossible }
            start.assignments[slot] = course
            let root = ConditionalDependencyKey(courseID: course, semester: semesters[semester].id, kind: .prerequisite)
            forcedGoals[slot] = providerGoals(for: course, at: semester, root: root, state: start)
        }

        let goals = requests.map(goal)
        let groups = partition(goals, forcedSlots: Set(forcedChoices.keys))
        var merged = start
        var unconfirmed = false
        for group in groups {
            try Task.checkCancellation()
            let groupGoals = group.goalIndices.map { goals[$0] }
                + group.slots.sorted().flatMap { forcedGoals[$0] ?? [] }
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
        let failure = FailureKey(goals: goals, assignments: state.assignments)
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
            return try search(rest, next, group: group, budget: &budget)
        }
        guard !allReal.contains(courseID) else { return nil }
        for slot in slots where goal.window.admits(slot.semester) && state.assignments[slot.id] == nil {
            guard domain(of: slot.id).contains(courseID),
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
        guard let course = coursesByID[courseID] else { return [] }
        let rule = resolver.rule(for: course, activeProgramTitle: input.activeProgramTitle)
        let paired = labPairing.pairedCourses(of: courseID)
        let standing = input.standingBySemester[semesters[index].id]
        var goals = [
            SearchGoal(expression: rule.prerequisiteExpr.treatingAsSatisfied(paired), window: .before(index), standing: standing, root: root),
            SearchGoal(expression: rule.corequisiteExpr.treatingAsSatisfied(paired), window: .through(index), standing: standing, root: root)
        ]
        // A lecture needs its lab beside it, and a lab its lecture: real
        // work, the lecture's lab placeholder, or another slot there.
        let items = Set(semesters[index].courseIDs)
        let labs = labPairing.labOptions(forLecture: courseID)
        if !labs.isEmpty, !items.contains(LabPairing.labPlaceholderID(forLecture: courseID)) {
            goals.append(SearchGoal(expression: .any(labs.map(PrereqExpr.course)), window: .same(index), standing: nil, root: root))
        }
        let lectures = labPairing.lectures(forLab: courseID)
        if !lectures.isEmpty {
            goals.append(SearchGoal(expression: .any(lectures.map(PrereqExpr.course)), window: .same(index), standing: nil, root: root))
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

    func domain(of slot: String) -> Set<String> {
        if let cached = domains[slot] { return cached }
        guard let spec = input.pathway.placeholders[slot] else { return [] }
        let domain = Set(PlaceholderCourseDomain.eligibleCourseIDs(for: spec, catalog: catalog))
        domains[slot] = domain
        return domain
    }

    // MARK: Connected groups

    private struct Group {
        var id: String
        var goalIndices: [Int]
        var slots: Set<String>
    }

    /// Requests that could draw on the same slots, directly or through a
    /// provider chain, are searched together; the rest independently.
    private func partition(_ goals: [SearchGoal], forcedSlots: Set<String>) -> [Group] {
        let relevant = goals.map { goal in relevantSlots(for: goal.expression) }
        var groupOf = Array(goals.indices)
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
        for index in goals.indices {
            let root = find(index)
            if groups[root] == nil {
                groups[root] = Group(id: "", goalIndices: [], slots: [])
                order.append(root)
            }
            groups[root]!.goalIndices.append(index)
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
    /// course those courses need in turn (bounded).
    private func relevantSlots(for expression: PrereqExpr) -> Set<String> {
        var pending = Array(Set(expression.courseLeaves)).sorted()
        var visited: Set<String> = []
        var result: Set<String> = []
        while let courseID = pending.popLast(), visited.count < 2_000 {
            guard visited.insert(courseID).inserted else { continue }
            let holders = slots.filter { domain(of: $0.id).contains(courseID) }.map(\.id)
            guard !holders.isEmpty else { continue }
            result.formUnion(holders)
            pending.append(contentsOf: leavesNeeded(by: courseID).subtracting(visited).sorted())
        }
        return result
    }

    private func leavesNeeded(by courseID: String) -> Set<String> {
        if let cached = dependencyLeaves[courseID] { return cached }
        var leaves: Set<String> = []
        if let course = coursesByID[courseID] {
            let rule = resolver.rule(for: course, activeProgramTitle: input.activeProgramTitle)
            leaves.formUnion(rule.prerequisiteExpr.courseLeaves)
            leaves.formUnion(rule.corequisiteExpr.courseLeaves)
            leaves.formUnion(labPairing.labOptions(forLecture: courseID))
            leaves.formUnion(labPairing.lectures(forLab: courseID))
        }
        dependencyLeaves[courseID] = leaves
        return leaves
    }
}
