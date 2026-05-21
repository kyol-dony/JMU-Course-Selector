import Foundation

public indirect enum PrereqExpr: Codable, Hashable, Sendable {
    case empty
    case course(String)
    case unknown(String)
    case all([PrereqExpr])
    case any([PrereqExpr])

    private enum CodingKeys: String, CodingKey { case kind, value, children }
    private enum Kind: String, Codable { case empty, course, unknown, all, any }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .empty: self = .empty
        case .course: self = .course(try c.decode(String.self, forKey: .value))
        case .unknown: self = .unknown(try c.decode(String.self, forKey: .value))
        case .all: self = .all(try c.decode([PrereqExpr].self, forKey: .children))
        case .any: self = .any(try c.decode([PrereqExpr].self, forKey: .children))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .empty:
            try c.encode(Kind.empty, forKey: .kind)
        case .course(let id):
            try c.encode(Kind.course, forKey: .kind)
            try c.encode(id, forKey: .value)
        case .unknown(let text):
            try c.encode(Kind.unknown, forKey: .kind)
            try c.encode(text, forKey: .value)
        case .all(let children):
            try c.encode(Kind.all, forKey: .kind)
            try c.encode(children, forKey: .children)
        case .any(let children):
            try c.encode(Kind.any, forKey: .kind)
            try c.encode(children, forKey: .children)
        }
    }
}

public extension PrereqExpr {
    func displayString(coursesByID: [String: Course]) -> String {
        switch self {
        case .empty:
            return ""
        case .course(let id):
            return coursesByID[id]?.code ?? id
        case .unknown(let text):
            return text
        case .all(let children):
            return joinChildren(children, separator: " and ", coursesByID: coursesByID)
        case .any(let children):
            return joinChildren(children, separator: " or ", coursesByID: coursesByID)
        }
    }

    private func joinChildren(_ children: [PrereqExpr], separator: String, coursesByID: [String: Course]) -> String {
        children.map { child -> String in
            let rendered = child.displayString(coursesByID: coursesByID)
            switch child {
            case .all, .any:
                return "(\(rendered))"
            default:
                return rendered
            }
        }.joined(separator: separator)
    }
}
