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
    private let parser = JMUHTMLCatalogParser()

    /// Pure cache-mapping. Used as the initial detail render. Tests assert this
    /// returns the documented unavailable-state messaging when no cached
    /// description exists; the live network fetch lives in `liveDescription(for:)`.
    func detail(for course: Course) async -> CourseDetail {
        CourseDetail(
            course: course,
            descriptionStatus: descriptionStatus(for: course),
            description: course.description,
            rmpStatus: rmpStatusMessage,
            rmpSearchURL: rmpSearchURL,
            professors: []
        )
    }

    /// On-demand fetch of the JMU catalog search page for a
    /// course that has a `registrarURL` but no cached description. Returns nil
    /// when the network call fails, the page is empty, or there is no URL.
    /// Caller persists the result into the in-memory catalog so subsequent
    /// renders skip the network.
    func liveDescription(for course: Course) async -> (description: String, sourceURL: URL)? {
        guard let url = course.registrarURL else { return nil }

        var request = URLRequest(url: url)
        request.setValue(JMUCatalogConfiguration.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return nil
            }
            guard !data.isEmpty else { return nil }
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return nil
            }
            let parsed = parser.parseCourseDetail(html)
            guard let description = parsed.description, !description.isEmpty else { return nil }
            return (description, url)
        } catch {
            return nil
        }
    }

    private let rmpStatusMessage = "Automatic Rate My Professors ratings are unavailable because the app does not use unstable scraping."

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

    /// Convenience used by callers (`PlanStore`) once a live fetch succeeds.
    func descriptionStatus(forLiveFetched url: URL) -> String {
        "Fetched live from \(url.absoluteString)."
    }
}
