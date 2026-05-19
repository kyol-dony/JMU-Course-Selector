import AppKit
import Foundation
import PlannerCore

@MainActor
struct ExportService {
    func exportPDF(planName: String, pathway: Pathway, catalog: Catalog) throws {
        guard let destination = savePanel(defaultName: "\(planName).pdf", allowedTypes: ["pdf"]) else { return }
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        view.string = printableSummary(planName: planName, pathway: pathway, catalog: catalog)
        view.font = NSFont.systemFont(ofSize: 12)
        view.textContainerInset = NSSize(width: 36, height: 36)
        let data = view.dataWithPDF(inside: view.bounds)
        try data.write(to: destination)
    }

    func exportICS(planName: String, pathway: Pathway, catalog: Catalog) throws {
        guard let destination = savePanel(defaultName: "\(planName).ics", allowedTypes: ["ics"]) else { return }
        let courses = catalog.coursesByID
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//JMUCoursePlanner//Schedule Export//EN"]

        for semester in pathway.semesters {
            let date = semester.id.term == .fall ? "\(semester.id.year)0820" : "\(semester.id.year)0110"
            for courseID in semester.courseIDs {
                guard let course = courses[courseID] else { continue }
                lines.append("BEGIN:VEVENT")
                lines.append("UID:\(UUID().uuidString)@jmu-course-planner")
                lines.append("DTSTAMP:\(Self.icsDate(Date()))")
                lines.append("DTSTART;VALUE=DATE:\(date)")
                lines.append("SUMMARY:\(course.code) \(course.title)")
                lines.append("DESCRIPTION:\(semester.id.displayName) placeholder course block. Confirm actual meeting times in MyMadison.")
                lines.append("END:VEVENT")
            }
        }

        lines.append("END:VCALENDAR")
        try lines.joined(separator: "\r\n").data(using: .utf8)?.write(to: destination)
    }

    private func printableSummary(planName: String, pathway: Pathway, catalog: Catalog) -> String {
        let courses = catalog.coursesByID
        var text = "\(planName)\nJMU Course Planner\n\n"
        for semester in pathway.semesters {
            let total = semester.courseIDs.compactMap { courses[$0]?.credits }.reduce(0, +)
            text += "\(semester.id.displayName) - \(total) credits\n"
            for courseID in semester.courseIDs {
                if let course = courses[courseID] {
                    text += "  \(course.code): \(course.title) (\(course.credits) credits)\n"
                }
            }
            text += "\n"
        }
        text += "Generated plan is an advising aid. Confirm all requirements and course availability with JMU before registering.\n"
        return text
    }

    private func savePanel(defaultName: String, allowedTypes: [String]) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedFileTypes = allowedTypes
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func icsDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
