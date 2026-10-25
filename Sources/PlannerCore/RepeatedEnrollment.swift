import Foundation

/// A course a requirement takes more than once, as a catalog remark states
/// it: "Taken twice at 2 credits for a total of 4 credits", "Taken at two
/// credit hours for six semesters". The generator schedules the first
/// enrollment as the course and each later one as a repeat slot.
public struct RepeatedEnrollment: Equatable, Sendable {
    /// Enrollments in all, the first included. Always 2 or more.
    public var count: Int
    /// Credits per enrollment, when the remark gives them or a total.
    public var creditsEach: Int?

    public init(count: Int, creditsEach: Int?) {
        self.count = count
        self.creditsEach = creditsEach
    }

    /// Nil when the remark doesn't take the course more than once.
    public init?(remark: String) {
        let text = remark.lowercased()
        let number = #"(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"#
        let count: Int?
        if text.range(of: #"\btwice\b"#, options: .regularExpression) != nil {
            count = 2
        } else if let match = Self.match(#"\b"# + number + #"\s+(?:times|semesters|enrollments)\b"#, in: text), match.count > 1 {
            count = Self.value(of: match[1])
        } else {
            count = nil
        }
        guard let count, count >= 2 else { return nil }
        self.count = count

        if let match = Self.match(#"\b(?:at|(?<!total )of)\s+"# + number + #"\s+credits?(?:\s+hours?)?(?:\s+each)?\b"#, in: text), match.count > 1 {
            creditsEach = Self.value(of: match[1])
        } else if let match = Self.match(#"\bfor\s+"# + number + #"\s+credits?(?:\s+hours?)?\s+(?:twice|"# + number + #"\s+times)"#, in: text), match.count > 1 {
            // "for 2 credits three times"
            creditsEach = Self.value(of: match[1])
        } else if let match = Self.match(#"\b(?:a total of|(?:twice|times|semesters) for)\s+(\d+)\s+credit"#, in: text), match.count > 1,
                  let total = Int(match[1]) {
            creditsEach = max(total / count, 1)
        } else {
            creditsEach = nil
        }
    }

    /// The match's capture groups, the whole match first.
    private static func match(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    private static func value(of word: String) -> Int? {
        if let number = Int(word) { return number }
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return words.firstIndex(of: word).map { $0 + 1 }
    }
}

public extension Pathway {
    /// Which enrollment of its course a repeat slot is, counting the course
    /// itself and earlier repeats in semester order: 2 for the second time.
    /// A course already taken outside the plan counts as the first. Nil for
    /// anything that isn't a repeat slot.
    func enrollmentNumber(of itemID: String) -> Int? {
        guard let courseID = placeholders[itemID]?.repeatOf else { return nil }
        let items = semesters.flatMap(\.courseIDs)
        var number = items.contains(courseID) ? 0 : 1
        for id in items where id == courseID || placeholders[id]?.repeatOf == courseID {
            number += 1
            if id == itemID { return number }
        }
        return nil
    }
}
