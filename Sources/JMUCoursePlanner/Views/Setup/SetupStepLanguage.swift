import SwiftUI
import PlannerCore

/// Setup step for a B.A.: which foreign language, and where placement
/// starts the 101 → 232 sequence.
struct SetupStepLanguage: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: DesignTokens.Spacing.m)]

    /// Languages JMU teaches through 232, by the catalog.
    private var languages: [String] {
        catalog.degreeEligibility.languageSubjects.filter { catalog.coursesByID["\($0)232"] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                Text("Language")
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    ForEach(languages, id: \.self) { subject in
                        languageCard(subject)
                    }
                }
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                Text("Placement")
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                ForEach(LanguagePlacement.allCases, id: \.self) { placement in
                    placementRow(placement)
                }
                Label("Not sure yet plans the full sequence from 101. You can change this once you take the placement test.", systemImage: "info.circle")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .opacity(store.plan.foreignLanguage == nil ? 0.45 : 1)
            .disabled(store.plan.foreignLanguage == nil)
        }
    }

    private func languageCard(_ subject: String) -> some View {
        let isSelected = store.plan.foreignLanguage?.subject == subject
        return Button {
            withAnimation(DesignTokens.Motion.step) {
                store.setForeignLanguage(ForeignLanguagePlan(subject: subject, placement: store.plan.foreignLanguage?.placement ?? .notSure))
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.languageName(subject))
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(subject)
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                SetupSelectionCheck(isSelected: isSelected)
            }
        }
        .buttonStyle(SetupOptionStyle(isSelected: isSelected))
        .accessibilityLabel(Self.languageName(subject))
    }

    private func placementRow(_ placement: LanguagePlacement) -> some View {
        let isSelected = store.plan.foreignLanguage?.placement == placement
        return Button {
            guard let language = store.plan.foreignLanguage else { return }
            store.setForeignLanguage(ForeignLanguagePlan(subject: language.subject, placement: placement))
        } label: {
            HStack {
                Text(Self.placementLabel(placement))
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer(minLength: 0)
                SetupSelectionCheck(isSelected: isSelected)
            }
        }
        .buttonStyle(SetupOptionStyle(isSelected: isSelected, chrome: .row))
    }

    static func placementLabel(_ placement: LanguagePlacement) -> String {
        switch placement {
        case .level101: "101 (beginning)"
        case .level102: "102"
        case .level231: "231 (intermediate)"
        case .level232: "232"
        case .placedOut: "Placed out / already complete"
        case .notSure: "Not sure yet"
        }
    }

    static func languageName(_ subject: String) -> String {
        [
            "ARAB": "Arabic", "ASL": "American Sign Language", "CHIN": "Chinese", "FR": "French",
            "GER": "German", "GRK": "Greek", "ITAL": "Italian", "JAPN": "Japanese", "KOR": "Korean",
            "LAT": "Latin", "PERS": "Persian", "PORT": "Portuguese", "RUS": "Russian", "SPAN": "Spanish"
        ][subject] ?? subject
    }
}
