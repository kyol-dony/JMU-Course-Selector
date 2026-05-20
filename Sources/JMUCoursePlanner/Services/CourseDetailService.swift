import Foundation
import PlannerCore

struct CourseDetail: Identifiable {
    var id: String { course.id }
    var course: Course
    var descriptionStatus: String
    var description: String?
    var rmpStatus: String
    var rmpSearchURL: URL?
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
    private let rmpSearchURL = URL(string: "https://www.ratemyprofessors.com/search/professors/457?q=%2A")!

    func detail(for course: Course) async -> CourseDetail {
        CourseDetail(
            course: course,
            descriptionStatus: descriptionStatus(for: course),
            description: course.description,
            rmpStatus: "Automatic Rate My Professors ratings are unavailable because the app does not use unstable scraping.",
            rmpSearchURL: rmpSearchURL,
            professors: []
        )
    }

    private func descriptionStatus(for course: Course) -> String {
        if let description = course.description, !description.isEmpty {
            if let source = course.descriptionSourceURL ?? course.registrarURL {
                return "Official JMU catalog description cached from \(source.absoluteString)."
            }
            return "Official JMU catalog description cached."
        }

        if course.registrarURL != nil {
            return "Description unavailable in cached catalog. Open the JMU registrar page to verify details."
        }

        return "Description unavailable until the catalog refresh discovers the official JMU course page."
    }
}
