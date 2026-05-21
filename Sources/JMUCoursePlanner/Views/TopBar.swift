import SwiftUI
import PlannerCore

struct TopBar: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.l) {
            leadingCluster
            Spacer(minLength: DesignTokens.Spacing.l)
            tabBar
            Spacer(minLength: DesignTokens.Spacing.l)
            trailingCluster
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.m)
        .frame(height: 64)
        .background(DesignTokens.Colors.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 1)
        }
    }

    private var leadingCluster: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DesignTokens.Colors.brandPurple)
                Text("J")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.brandGold)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.activeProgram?.title ?? "JMU Course Planner")
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                if let degree = store.activeProgram?.degreeType {
                    Text(degree)
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .textCase(.uppercase)
                } else {
                    Text("No plan yet")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isActive = store.selectedTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                store.selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.title)
                    .font(DesignTokens.Typography.label)
            }
            .foregroundStyle(isActive ? DesignTokens.Colors.brandGold : DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isActive ? DesignTokens.Colors.brandPurple : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var trailingCluster: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            if let progress = store.progress {
                StatChip(label: "Done", value: "\(Int(progress.overallFraction * 100))%", emphasized: true)
                StatChip(label: "Grad", value: progress.projectedGraduation?.displayName ?? "-")
            }
            if store.isRefreshingCatalog {
                StatusPill(text: "Refreshing", tone: .info, systemImage: "arrow.triangle.2.circlepath")
            }

            Menu {
                Button("Edit Setup") { store.setupSheetPresented = true }
                Button("Save") { store.saveCurrentPlan() }
                Menu("Export") {
                    Button("PDF") { store.exportPDF() }
                    Button("Calendar (.ics)") { store.exportICS() }
                }
                Divider()
                Button("Refresh Requirements") { store.refreshCatalog() }
                Button("Start Over") {
                    store.startFresh()
                    store.setupSheetPresented = true
                }
                Divider()
                Button("Reset App Data", role: .destructive) { store.resetAppData() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .frame(maxWidth: 320, alignment: .trailing)
    }
}
