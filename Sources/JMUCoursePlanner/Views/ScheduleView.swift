import SwiftUI
import PlannerCore

struct ScheduleView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            warnings
            if let pathway = store.activePathway {
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(pathway.semesters) { semester in
                            SemesterColumn(semester: semester, catalog: catalog)
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.activeProgram?.title ?? "Plan")
                    .font(.title2.bold())
                Text(store.activePathway?.projectedGraduation?.displayName ?? "Projected date unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Pathway", selection: Binding(
                get: { store.plan.activePathwayID ?? store.plan.pathways.first?.id ?? "" },
                set: { store.plan.activePathwayID = $0 }
            )) {
                ForEach(store.plan.pathways) { pathway in
                    Text(pathway.name).tag(pathway.id)
                }
            }
            .frame(width: 190)

            Button {
                store.generateSchedules()
            } label: {
                Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                store.saveCurrentPlan()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                store.startFresh()
            } label: {
                Label("Start Over", systemImage: "arrow.uturn.backward")
            }
            .help("Clear the current major, transfer credits, and generated pathways. Saved plans are kept.")

            Menu {
                Button("PDF") { store.exportPDF() }
                Button("Calendar (.ics)") { store.exportICS() }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var warnings: some View {
        if !store.warnings.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.warnings) { warning in
                        HStack(spacing: 6) {
                            Image(systemName: warning.isOverridden ? "exclamationmark.triangle" : "exclamationmark.triangle.fill")
                            Text(warning.message)
                                .lineLimit(1)
                            if !warning.isOverridden {
                                Button("Keep anyway") { store.override(warning) }
                                    .buttonStyle(.borderless)
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct SemesterColumn: View {
    @EnvironmentObject private var store: PlanStore
    var semester: SemesterPlan
    var catalog: Catalog

    private var coursesByID: [String: Course] { catalog.coursesByID }
    private var totalCredits: Int {
        semester.courseIDs.compactMap { coursesByID[$0]?.credits }.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(semester.id.displayName)
                        .font(.headline)
                    Text("\(totalCredits) credits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(catalog.courses.sorted { $0.code < $1.code }) { course in
                        Button("\(course.code) \(course.title)") {
                            store.moveCourse(course.id, to: semester.id)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
            }

            ForEach(semester.courseIDs, id: \.self) { courseID in
                if let course = coursesByID[courseID] {
                    CourseCard(course: course, semester: semester.id)
                        .draggable(courseID)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 245)
        .frame(minHeight: 500, alignment: .top)
        .panelStyle()
        .dropDestination(for: String.self) { items, _ in
            guard let courseID = items.first else { return false }
            store.moveCourse(courseID, to: semester.id)
            return true
        }
    }
}

private struct CourseCard: View {
    @EnvironmentObject private var store: PlanStore
    var course: Course
    var semester: SemesterIdentity

    private var courseWarnings: [ConflictWarning] {
        store.warnings.filter { $0.courseID == course.id && $0.semester == semester }
    }

    var body: some View {
        Button {
            store.showCourse(course.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(course.code)
                        .font(.headline)
                    Spacer()
                    Text("\(course.credits)")
                        .font(.caption.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(JMUStyle.gold.opacity(0.25), in: Capsule())
                }
                Text(course.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !courseWarnings.isEmpty {
                    ForEach(courseWarnings) { warning in
                        Text(warning.kind.displayName)
                            .font(.caption2)
                            .foregroundStyle(warning.isOverridden ? Color.secondary : Color.orange)
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        store.removeCourse(course.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this course from the plan")
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(JMUStyle.purple)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .buttonStyle(.plain)
    }
}
