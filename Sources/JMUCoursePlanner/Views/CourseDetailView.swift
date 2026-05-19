import SwiftUI
import PlannerCore

struct CourseDetailView: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss
    var course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(course.code)
                        .font(.largeTitle.bold())
                    Text(course.title)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }

            GroupBox("Course Summary") {
                VStack(alignment: .leading, spacing: 8) {
                    if let detail = store.courseDetail, let description = detail.description {
                        Text(description)
                    } else {
                        Text(store.courseDetail?.descriptionStatus ?? "Loading official course details...")
                            .foregroundStyle(.secondary)
                    }
                    Link("Open JMU course page", destination: course.registrarURL ?? URL(string: "https://www.jmu.edu/catalog/pdfs/2025-2026-jmu-undergraduate-catalog.pdf")!)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Semester Availability") {
                VStack(alignment: .leading, spacing: 6) {
                    if let availability = course.availability {
                        Text(availability.map(\.rawValue).sorted().joined(separator: " and "))
                    } else {
                        Label("Availability unknown in the verified catalog cache", systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                    }
                    Text("If you move this course into a semester where it is not usually offered, the warning remains visible until you change it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Difficulty and Professors") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.courseDetail?.rmpStatus ?? "Loading professor data...")
                        .foregroundStyle(.secondary)
                    if let professors = store.courseDetail?.professors, !professors.isEmpty {
                        ForEach(professors) { professor in
                            HStack {
                                Text(professor.name)
                                Spacer()
                                Text(professor.rating.map { String(format: "%.1f", $0) } ?? "No reviews yet")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(24)
    }
}
