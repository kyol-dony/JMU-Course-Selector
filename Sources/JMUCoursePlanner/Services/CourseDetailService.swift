import Foundation
import PlannerCore

struct CourseDetail: Identifiable {
    var id: String { course.id }
    var course: Course
    var descriptionStatus: String
    var description: String?
    var rmpStatus: String
    var professors: [ProfessorRating]
}

struct ProfessorRating: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var rating: Double?
    var difficulty: Double?
    var reviewCount: Int
    var profileURL: URL?
}

struct CourseDetailService {
    func detail(for course: Course) async -> CourseDetail {
        CourseDetail(
            course: course,
            descriptionStatus: "Official registrar description is not cached yet. Use the catalog link and verify details before registering.",
            description: nil,
            rmpStatus: "Rate My Professor data is unavailable. The app does not fabricate ratings when live data cannot be retrieved responsibly.",
            professors: []
        )
    }
}
