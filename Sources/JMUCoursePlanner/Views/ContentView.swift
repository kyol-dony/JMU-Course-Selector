import SwiftUI
import PlannerCore

struct ContentView: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        Group {
            if let catalog = store.catalog {
                NavigationSplitView {
                    PlanSidebar(catalog: catalog)
                } detail: {
                    MainWorkspace(catalog: catalog)
                }
            } else {
                LoadingView()
            }
        }
        .tint(JMUStyle.purple)
        .sheet(item: $store.selectedCourse) { course in
            CourseDetailView(course: course)
                .environmentObject(store)
                .frame(minWidth: 520, minHeight: 520)
        }
        .alert("Planner Notice", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct LoadingView: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(store.statusMessage)
                .foregroundStyle(.secondary)
            if store.errorMessage != nil {
                Button("Retry") {
                    Task { await store.load() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlanSidebar: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        List {
            Section("Current Plan") {
                Label(store.activeProgram?.title ?? "Choose a major", systemImage: "graduationcap")
                Label(store.plan.workload.rawValue, systemImage: "speedometer")
                if !store.plan.transferCredits.isEmpty {
                    Label("\(store.plan.transferCredits.reduce(0) { $0 + $1.credits }) transfer credits", systemImage: "checkmark.seal")
                }
            }

            if !store.savedPlans.isEmpty {
                Section("Saved Plans") {
                    ForEach(store.savedPlans) { saved in
                        Button {
                            store.resume(saved)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.name)
                                    .lineLimit(1)
                                Text(saved.updatedAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Catalog") {
                Text(catalog.source.catalogYear)
                if catalog.source.isOlderThanSixMonths() {
                    Label("Verify with your advisor", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Button {
                    store.refreshCatalog()
                } label: {
                    Label(store.isRefreshingCatalog ? "Refreshing..." : "Refresh Requirements", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshingCatalog)

                Button(role: .destructive) {
                    store.resetAppData()
                } label: {
                    Label("Reset App Data", systemImage: "trash")
                }
                .disabled(store.isRefreshingCatalog)
                .help("Delete all saved plans and cached catalog data, then reload from the bundled seed.")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("JMU Planner")
    }
}

private struct MainWorkspace: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if store.plan.programID == nil || store.plan.pathways.isEmpty {
                    OnboardingView(catalog: catalog)
                } else {
                    ScheduleView(catalog: catalog)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ProgressPanel(catalog: catalog)
                .frame(width: 310)
        }
    }
}
