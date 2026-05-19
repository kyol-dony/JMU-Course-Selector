import SwiftUI
import PlannerCore

struct ProgressPanel: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Graduation Progress")
                .font(.title3.bold())

            if let progress = store.progress {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Int(progress.overallFraction * 100))% complete")
                        .font(.largeTitle.bold())
                    ProgressView(value: progress.overallFraction)
                    Text("Projected graduation: \(progress.projectedGraduation?.displayName ?? "Unavailable")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(progress.categories) { category in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(category.name)
                                .font(.subheadline.bold())
                            Spacer()
                            if category.verificationStatus != .verified {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .help("This requirement needs advisor verification.")
                            }
                        }
                        ProgressView(value: category.fraction)
                            .tint(category.verificationStatus == .verified ? JMUStyle.purple : .orange)
                        Text("\(category.completedCredits) completed, \(category.remainingCredits) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Progress appears after you choose a major and generate a pathway.")
                    .foregroundStyle(.secondary)
                if let program = store.activeProgram, !program.requirementDataComplete {
                    Text("This selected program is listed in the catalog, but fixed course requirements are not available in the local cache.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Added Programs")
                    .font(.headline)
                if store.plan.minorProgramIDs.isEmpty {
                    Text("No minors or second majors added.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.plan.minorProgramIDs, id: \.self) { id in
                        Text(catalog.programsByID[id]?.title ?? id)
                            .font(.caption)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .background(.thinMaterial)
    }
}
