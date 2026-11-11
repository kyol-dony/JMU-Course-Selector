import AppKit
import Foundation
import PlannerCore

@MainActor
struct ExportService {
    func exportPDF(planName: String, pathway: Pathway, catalog: Catalog, history: AcademicHistory? = nil) throws {
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
        textView.string = printableSummary(planName: planName, pathway: pathway, catalog: catalog, history: history)
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
        try calendarText(planName: planName, pathway: pathway, catalog: catalog).data(using: .utf8)?.write(to: destination)
    }

    func calendarText(planName: String, pathway: Pathway, catalog: Catalog) -> String {
        let courses = catalog.coursesByID
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//JMUCoursePlanner//Schedule Export//EN",
            "X-WR-CALNAME:\(planName)",
            "X-WR-CALDESC:Unofficial planning tool. Not affiliated with or endorsed by James Madison University."
        ]

        for semester in pathway.semesters {
            let date = semester.id.term == .fall ? "\(semester.id.year)0820" : "\(semester.id.year)0110"
            for courseID in semester.courseIDs {
                let item = exportItem(courseID, semester: semester, pathway: pathway, courses: courses)
                lines.append("BEGIN:VEVENT")
                lines.append("UID:\(UUID().uuidString)@jmu-course-planner")
                lines.append("DTSTAMP:\(Self.icsDate(Date()))")
                lines.append("DTSTART;VALUE=DATE:\(date)")
                lines.append("SUMMARY:\(item.code) \(item.title)")
                lines.append("DESCRIPTION:\(semester.id.displayName) planning block (\(CreditHoursFormatter.string(item.credits)) estimated credits). Confirm requirements and actual meeting times with JMU.")
                lines.append("END:VEVENT")
            }
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    func printableSummary(planName: String, pathway: Pathway, catalog: Catalog, history: AcademicHistory? = nil) -> String {
        let courses = catalog.coursesByID
        var text = "\(planName)\nJMU Course Planner\n\n"
        if let history {
            text += "Earned credit: \(CreditHoursFormatter.string(history.earnedHours)) hours\n"
            for credit in history.effectiveCredits {
                text += "  \(credit.source.label): \(credit.courseIDs.joined(separator: ", ")) \(credit.sourceDescription) (\(CreditHoursFormatter.string(credit.credits)) credits)\n"
            }
            text += "\nProjected coursework\n"
        }
        for semester in pathway.semesters {
            let total = AcademicCreditCalculator.projectedHours(
                in: [semester],
                placeholders: pathway.placeholders,
                transferCredits: [],
                catalog: catalog
            )
            text += "\(semester.id.displayName) - \(CreditHoursFormatter.string(total)) credits\n"
            for courseID in semester.courseIDs {
                let item = exportItem(courseID, semester: semester, pathway: pathway, courses: courses)
                text += "  \(item.code): \(item.title) (\(CreditHoursFormatter.string(item.credits)) credits)\n"
            }
            text += "\n"
        }
        text += "Unofficial planning tool. Not affiliated with or endorsed by James Madison University.\n"
        text += "Generated plan is an advising aid. Confirm all requirements and course availability with JMU before registering.\n"
        return text
    }

    private func exportItem(
        _ courseID: String,
        semester: SemesterPlan,
        pathway: Pathway,
        courses: [String: Course]
    ) -> (code: String, title: String, credits: Double) {
        if let course = courses[courseID] {
            return (
                course.code,
                semester.courseTitles[courseID] ?? course.title,
                semester.creditOverrides[courseID] ?? Double(course.credits)
            )
        }
        if let placeholder = pathway.placeholders[courseID] {
            return (
                "Unresolved requirement",
                placeholder.categoryName,
                semester.creditOverrides[courseID] ?? placeholder.credits
            )
        }
        return (
            "Unresolved course",
            semester.courseTitles[courseID] ?? "Course choice pending",
            semester.creditOverrides[courseID] ?? 0
        )
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
