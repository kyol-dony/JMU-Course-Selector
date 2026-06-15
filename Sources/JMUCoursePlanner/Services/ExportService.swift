import AppKit
import Foundation
import PlannerCore

@MainActor
struct ExportService {
    func exportPDF(planName: String, pathway: Pathway, catalog: Catalog) throws {
        guard let destination = savePanel(defaultName: "\(planName).pdf", allowedTypes: ["pdf"]) else { return }

        // Build a text view sized to its content height. The previous
        // implementation rendered `view.bounds` straight to a single PDF
        // page via `dataWithPDF(inside:)`, which clipped anything past the
        // first 8.5"x11". Route through NSPrintOperation instead so AppKit
        // paginates automatically; any number of semesters fit across as
        // many pages as needed.
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 36

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        textView.textContainerInset = NSSize(width: margin, height: margin)
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.string = printableSummary(planName: planName, pathway: pathway, catalog: catalog)
        textView.isEditable = false

        // Force layout so we can size the view to fit all the content
        // vertically before handing it to the print operation.
        if let container = textView.textContainer, let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).size
            let height = max(ceil(used.height) + margin * 2, pageHeight)
            textView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: height)
        }

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: pageWidth, height: pageHeight)
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        let dict = printInfo.dictionary()
        dict[NSPrintInfo.AttributeKey.jobDisposition] = NSPrintInfo.JobDisposition.save
        dict[NSPrintInfo.AttributeKey.jobSavingURL] = destination

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        if !operation.run() {
            throw NSError(
                domain: "JMUCoursePlanner.ExportService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Print operation could not write the PDF."]
            )
        }
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
