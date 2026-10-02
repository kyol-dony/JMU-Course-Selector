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
