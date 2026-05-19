import SwiftUI
import PlannerCore

struct ProgramPickerView: View {
    var title: String
    var helper: String
    var programs: [Program]
    @Binding var selectedProgramID: String?
    @State private var searchText = ""

    private var filtered: [Program] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return programs }
        return programs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.college.localizedCaseInsensitiveContains(searchText)
            || $0.department.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var grouped: [(String, [(String, [Program])])] {
        let colleges = Dictionary(grouping: filtered, by: \.college)
        return colleges.keys.sorted().map { college in
            let departments = Dictionary(grouping: colleges[college] ?? [], by: \.department)
            return (college, departments.keys.sorted().map { ($0, (departments[$0] ?? []).sorted { $0.title < $1.title }) })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(helper)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search by major, college, or department", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(grouped, id: \.0) { college, departments in
                        DisclosureGroup(college) {
                            ForEach(departments, id: \.0) { department, items in
                                DisclosureGroup(department) {
                                    ForEach(items) { program in
                                        ProgramRow(program: program, isSelected: selectedProgramID == program.id) {
                                            selectedProgramID = program.id
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(minHeight: 220, maxHeight: 300)
        }
        .panelStyle()
    }
}

private struct ProgramRow: View {
    var program: Program
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.title)
                        .foregroundStyle(Color.primary)
                    Text(program.requirementDataComplete ? "Requirements available" : "Refresh or verify requirements")
                        .font(.caption)
                        .foregroundStyle(program.requirementDataComplete ? Color.secondary : Color.orange)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(JMUStyle.purple)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
