import SwiftUI

enum JMUStyle {
    static let purple = Color(red: 69 / 255, green: 0 / 255, blue: 132 / 255)
    static let gold = Color(red: 203 / 255, green: 182 / 255, blue: 119 / 255)
}

extension View {
    func panelStyle() -> some View {
        self
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
