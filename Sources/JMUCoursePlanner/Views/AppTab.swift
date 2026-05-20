import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case myPlan
    case schedule
    case catalog
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myPlan: "My Plan"
        case .schedule: "Schedule"
        case .catalog: "Catalog"
        case .progress: "Progress"
        }
    }

    var systemImage: String {
        switch self {
        case .myPlan: "graduationcap.fill"
        case .schedule: "calendar"
        case .catalog: "books.vertical.fill"
        case .progress: "chart.bar.fill"
        }
    }
}
