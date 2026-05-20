import SwiftUI
import PlannerCore

struct ContentView: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        Group {
            if let catalog = store.catalog {
                dashboard(catalog: catalog)
            } else {
                LoadingView()
            }
        }
        .tint(DesignTokens.Colors.brandPurple)
    }

    private func dashboard(catalog: Catalog) -> some View {
        VStack(spacing: 0) {
            TopBar(catalog: catalog)
            tabContent(catalog: catalog)
        }
        .background(DesignTokens.Colors.surface)
        .sheet(isPresented: $store.setupSheetPresented) {
            SetupSheet(catalog: catalog)
                .environmentObject(store)
        }
        .sheet(item: $store.selectedCourse) { course in
            CourseDetailSheet(course: course, catalog: catalog)
                .environmentObject(store)
        }
        .alert(
            "Planner Notice",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear {
            if store.activeProgram == nil {
                store.setupSheetPresented = true
            }
        }
    }

    @ViewBuilder
    private func tabContent(catalog: Catalog) -> some View {
        switch store.selectedTab {
        case .myPlan:
            MyPlanView(catalog: catalog)
        case .schedule:
            ScheduleBoardView(catalog: catalog)
        case .catalog:
            CatalogView(catalog: catalog)
        case .progress:
            GraduationProgressView(catalog: catalog)
        }
    }
}

private struct LoadingView: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.l) {
            ProgressView()
            Text(store.statusMessage)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if store.errorMessage != nil {
                Button("Retry") {
                    Task { await store.load() }
                }
                .buttonStyle(.dtPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.surface)
    }
}
