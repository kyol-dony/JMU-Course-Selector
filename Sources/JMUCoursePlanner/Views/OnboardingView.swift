import SwiftUI
import PlannerCore

struct OnboardingView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var selectedProgram: Program?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ProgramPickerView(
                    title: "Choose your major",
                    helper: "Pick the exact major and degree type from the current JMU catalog. This version does not generate undecided plans.",
                    programs: catalog.programs.filter { $0.kind == .major },
                    selectedProgramID: Binding(
                        get: { store.plan.programID },
                        set: { id in
                            if let id, let program = catalog.programsByID[id] {
                                store.selectProgram(program)
                                selectedProgram = program
                            }
                        }
                    )
                )

                if let program = store.activeProgram {
                    VerificationCallout(program: program)
                } else {
                    AdvisingCallout()
                }

                ProgramPickerView(
                    title: "Optional minor or second major",
                    helper: "You can add more programs to track. Refreshed catalog HTML adds requirement rows for majors and minors when JMU publishes fixed course lists.",
                    programs: catalog.programs.filter { $0.kind == .minor || $0.kind == .major },
                    selectedProgramID: Binding(
                        get: { nil },
                        set: { id in
                            if let id, let program = catalog.programsByID[id] {
                                store.addMinor(program)
                            }
                        }
                    )
                )

                TransferCreditView(catalog: catalog)

                WorkloadPicker()

                HStack {
                    Button {
                        store.generateSchedules()
                    } label: {
                        Label("Generate 3 Pathways", systemImage: "sparkles")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.plan.programID == nil)

                    Button("Start Fresh") {
                        store.startFresh()
                    }

                    Text(store.statusMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(24)
            .frame(maxWidth: 940, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Build a semester-by-semester JMU plan")
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
            Text("Choose a catalog program, add transfer credit, then generate draft paths you can edit.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AdvisingCallout: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(JMUStyle.purple)
            VStack(alignment: .leading, spacing: 4) {
                Text("No undecided mode in this version")
                    .font(.headline)
                Text("If you have not chosen a major yet, talk with JMU University Advising before generating a plan.")
                    .foregroundStyle(.secondary)
                Link("Open JMU advising resources", destination: URL(string: "https://www.jmu.edu/advising/")!)
            }
        }
        .panelStyle()
    }
}

private struct VerificationCallout: View {
    var program: Program

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: program.requirementDataComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(program.requirementDataComplete ? .green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(program.requirementDataComplete ? "HTML requirements available" : "Requirements need review")
                    .font(.headline)
                Text(program.requirementDataComplete ? "This program has parsed requirements from the local catalog cache. Courses with unknown semester availability will stay flagged." : "This program is listed from the catalog, but fixed course rows were not parsed. Refresh requirements or verify the page with an advisor.")
                    .foregroundStyle(.secondary)
                Text(program.sourceNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }
}

private struct WorkloadPicker: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workload")
                .font(.headline)
            Picker("Workload", selection: Binding(
                get: { store.plan.workload },
                set: { store.setWorkload($0) }
            )) {
                ForEach(WorkloadPreference.allCases, id: \.self) { workload in
                    Text(workload.displayName).tag(workload)
                }
            }
            .pickerStyle(.segmented)
            Text("The generator tries to stay within this range while keeping prerequisites in order.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}
