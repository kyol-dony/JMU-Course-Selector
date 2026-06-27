import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case myPlan
    case schedule
    case catalog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myPlan: "My Plan"
        case .schedule: "Schedule"
        case .catalog: "Catalog"
        }
    }

    var systemImage: String {
        switch self {
        case .myPlan: "graduationcap.fill"
        case .schedule: "calendar"
        case .catalog: "books.vertical.fill"
        }
    }
}
