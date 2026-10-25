import Foundation
import PlannerCore

enum StudentYear: String, Codable, Hashable, CaseIterable {
    case incomingFreshman = "Incoming freshman"
    case enrolledFreshman = "Freshman (already enrolled)"
    case sophomore = "Sophomore", junior = "Junior", senior = "Senior"
    case fifthYearOrBeyond = "Fifth year or beyond"
}
extension SemesterIdentity {
    static func current(date: Date = Date(), calendar: Calendar = .current) -> SemesterIdentity {
        .init(year: calendar.component(.year, from: date), term: calendar.component(.month, from: date) >= 8 ? .fall : .spring)
    }
}

enum SetupStep: String, CaseIterable { case year, major, minor, language, transfer, transcript, review, workload }
struct SetupFlow {
    private(set) var step: SetupStep = .year
    private(set) var visited: [SetupStep] = []
    private(set) var year: StudentYear?
    /// A declared B.A. major needs the student's language and placement.
    var needsLanguage = false
    /// Setup opened only to ask the language before a generation resumes.
    var languageOnly = false
    var route: [SetupStep] {
        if languageOnly { return [.language] }
        let language: [SetupStep] = needsLanguage ? [.language] : []
        return year == .incomingFreshman
            ? [.year, .major, .minor] + language + [.transfer, .workload]
            : [.year, .major, .minor] + language + [.transcript, .review, .workload]
    }
    static func needsInitialSetup(plan: SavedStudentPlan) -> Bool { plan.programID == nil && !plan.setupCompleted }
    mutating func selectYear(_ year: StudentYear) { self.year = year }
    private mutating func go(_ next: SetupStep) { guard next != step else { return }; visited.append(step); step = next }
    mutating func advance(majorSelectionComplete: Bool) {
        switch step {
        case .year: if year != nil { go(.major) }
        case .major: if majorSelectionComplete { go(.minor) }
        case .minor: go(needsLanguage ? .language : year == .incomingFreshman ? .transfer : .transcript)
        case .language: go(year == .incomingFreshman ? .transfer : .transcript)
        case .transfer: go(.workload)
        default: break
        }
    }
    mutating func skipUpload() { if step == .transcript { go(.review) } }
    mutating func importReady() { if step == .transcript { go(.review) } }
    mutating func reviewConfirmed() { if step == .review { go(.workload) } }
    mutating func back() { if let previous = visited.popLast() { step = previous } }
    /// Returns to a step already visited, dropping it and everything after it from history.
    mutating func jumpBack(to target: SetupStep) {
        guard let index = visited.lastIndex(of: target) else { return }
        visited.removeSubrange(index...)
        step = target
    }
    /// Opens setup partway through, as if every earlier step on the route
    /// had been visited (a saved plan generated without a language answer).
    mutating func resume(at target: SetupStep) {
        guard let index = route.firstIndex(of: target) else { return }
        visited = Array(route[..<index])
        step = target
    }

    /// One-based position of the current step within the route.
    var position: Int { (route.firstIndex(of: step) ?? 0) + 1 }
}
