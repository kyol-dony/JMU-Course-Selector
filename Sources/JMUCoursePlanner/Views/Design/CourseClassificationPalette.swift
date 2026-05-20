import SwiftUI

enum CourseClassificationPalette {
    static let colors: [Color] = [
        Color(red: 0.91, green: 0.70, blue: 0.18),
        Color(red: 0.36, green: 0.72, blue: 0.45),
        Color(red: 0.16, green: 0.56, blue: 0.83),
        Color(red: 0.72, green: 0.38, blue: 0.84),
        Color(red: 0.89, green: 0.42, blue: 0.39),
        Color(red: 0.20, green: 0.68, blue: 0.64),
        Color(red: 0.57, green: 0.47, blue: 0.88),
        Color(red: 0.86, green: 0.55, blue: 0.22),
        Color(red: 0.47, green: 0.62, blue: 0.19),
        Color(red: 0.18, green: 0.45, blue: 0.73),
        Color(red: 0.81, green: 0.32, blue: 0.56),
        Color(red: 0.41, green: 0.63, blue: 0.31),
        Color(red: 0.13, green: 0.62, blue: 0.74),
        Color(red: 0.67, green: 0.54, blue: 0.18),
        Color(red: 0.50, green: 0.50, blue: 0.76),
        Color(red: 0.74, green: 0.46, blue: 0.30),
        Color(red: 0.31, green: 0.65, blue: 0.54),
        Color(red: 0.62, green: 0.39, blue: 0.66)
    ]

    static func classification(forCode code: String) -> String {
        let prefix = code.prefix { character in
            character.isLetter
        }
        if prefix.isEmpty {
            return code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        return prefix.uppercased()
    }

    static func slotMap(for classifications: [String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: Set(classifications).sorted().enumerated().map { index, classification in
            (classification, index)
        })
    }

    static func color(for classification: String, slotMap: [String: Int]) -> Color {
        guard let slot = slotMap[classification] else {
            return colors[stableSlot(for: classification)]
        }
        if slot < colors.count {
            return colors[slot]
        }
        let hue = Double((slot * 137) % 360) / 360
        return Color(hue: hue, saturation: 0.62, brightness: 0.78)
    }

    private static func stableSlot(for classification: String) -> Int {
        let value = classification.unicodeScalars.reduce(0) { partial, scalar in
            partial &* 31 &+ Int(scalar.value)
        }
        return abs(value) % colors.count
    }
}
