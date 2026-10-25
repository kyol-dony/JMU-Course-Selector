import Foundation

/// "9 credits of MATH electives at MATH 310 or above": a slot any
/// sufficiently advanced course in a subject can fill. The catalog parser
/// only sees one program page, so it writes a pool token into the slot;
/// `Catalog.resolvingElectivePools()` swaps the token for the real course
/// menu once every course is known.
public enum ElectivePool {
    private static let prefix = "pool:"

    /// Highest course number a pool reaches: 500+ are graduate courses.
    public static let maximumNumber = 499

    /// "pool:ENG:300", or "pool:ENG:300:399" when the pool stops below the
    /// graduate range ("four courses from the 300 level").
    public static func token(subject: String, minimumNumber: Int, maximumNumber: Int = maximumNumber) -> String {
        let base = "\(prefix)\(subject.uppercased()):\(minimumNumber)"
        return maximumNumber < Self.maximumNumber ? "\(base):\(maximumNumber)" : base
    }

    public static func isToken(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    static func rule(from token: String) -> (subject: String, minimumNumber: Int, maximumNumber: Int)? {
        guard isToken(token) else { return nil }
        let parts = token.dropFirst(prefix.count).split(separator: ":")
        guard parts.count == 2 || parts.count == 3, let minimum = Int(parts[1]) else { return nil }
        let maximum = parts.count == 3 ? Int(parts[2]) ?? Self.maximumNumber : Self.maximumNumber
        return (String(parts[0]), minimum, min(maximum, Self.maximumNumber))
    }

    /// Subject and number of a course code ("MATH 411" -> MATH, 411).
    static func subjectAndNumber(of code: String) -> (subject: String, number: Int)? {
        guard let match = code.range(of: #"^[A-Z]{2,5}\s+\d{3}"#, options: .regularExpression) else { return nil }
        let parts = code[match].split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, let number = Int(parts[1]) else { return nil }
        return (String(parts[0]), number)
    }
}

public extension Catalog {
    /// Replaces elective-pool tokens with every catalog course in the pool's
    /// subject and number range, minus courses the program (or the pool's
    /// concentration) already requires outright: core courses aren't
    /// electives. Records the slots in `electivePoolSlots`. Idempotent.
    func resolvingElectivePools() -> Catalog {
        let sortedCourses = courses
            .compactMap { course in ElectivePool.subjectAndNumber(of: course.code).map { (course.id, $0.subject, $0.number) } }
            .sorted { $0.0 < $1.0 }

        func requiredOutright(_ requirements: [RequirementCategory]) -> Set<String> {
            Set(requirements.flatMap { $0.courseOptions.filter { $0.count == 1 }.flatMap { $0 } }.filter { !ElectivePool.isToken($0) })
        }

        func resolve(_ requirements: [RequirementCategory], excluding required: Set<String>) -> [RequirementCategory] {
            requirements.map { category in
                var category = category
                var slots = Set(category.electivePoolSlots ?? [])
                category.courseOptions = category.courseOptions.enumerated().map { index, option in
                    // A pool token may lead a few named courses that also count.
                    guard let first = option.first, let rule = ElectivePool.rule(from: first) else { return option }
                    slots.insert(index)
                    let pool = sortedCourses
                        .filter { $0.1 == rule.subject && (rule.minimumNumber...max(rule.maximumNumber, rule.minimumNumber)).contains($0.2) }
                        .map(\.0)
                    let extras = option.dropFirst().filter { !pool.contains($0) }
                    return (pool + extras).filter { !required.contains($0) }
                }
                category.electivePoolSlots = slots.isEmpty ? category.electivePoolSlots : slots.sorted()
                return category
            }
        }

        var catalog = self
        catalog.programs = programs.map { program in
            var program = program
            let programRequired = requiredOutright(program.requirements)
            program.requirements = resolve(program.requirements, excluding: programRequired)
            program.concentrations = program.concentrations.map { concentration in
                var concentration = concentration
                concentration.requirements = resolve(
                    concentration.requirements,
                    excluding: programRequired.union(requiredOutright(concentration.requirements))
                )
                return concentration
            }
            return program
        }
        return catalog
    }
}
