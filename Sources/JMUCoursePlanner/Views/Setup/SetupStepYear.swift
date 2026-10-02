import SwiftUI

struct SetupStepYear: View {
    var selection: StudentYear?
    var onSelect: (StudentYear) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader("Your year in school", helper: "Choose where you are in your JMU journey. We'll tailor setup to your completed and current courses.")
            ForEach(StudentYear.allCases, id: \.self) { year in
                Button { onSelect(year) } label: {
                    HStack {
                        Image(systemName: selection == year ? "largecircle.fill.circle" : "circle")
                        Text(year.rawValue)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(DesignTokens.Spacing.l)
                    .background(selection == year ? DesignTokens.Colors.brandPurpleSoft : DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
