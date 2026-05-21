#!/usr/bin/env swift
import Foundation

let seedURL = URL(fileURLWithPath: "Data/catalog_seed.json")
let data = try Data(contentsOf: seedURL)
guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      var courses = root["courses"] as? [[String: Any]] else {
    throw CocoaError(.coderInvalidValue)
}

func emptyExpr() -> [String: Any] {
    ["kind": "empty"]
}

func courseExpr(_ id: String) -> [String: Any] {
    ["kind": "course", "value": id]
}

func allExpr(_ children: [[String: Any]]) -> [String: Any] {
    ["kind": "all", "children": children]
}

for index in courses.indices {
    let prerequisites = courses[index]["prerequisites"] as? [String] ?? []
    switch prerequisites.count {
    case 0:
        courses[index]["prerequisiteExpr"] = emptyExpr()
    case 1:
        courses[index]["prerequisiteExpr"] = courseExpr(prerequisites[0])
    default:
        courses[index]["prerequisiteExpr"] = allExpr(prerequisites.map(courseExpr))
    }
    courses[index]["corequisiteExpr"] = emptyExpr()
    courses[index]["hasUnknownPrereqTokens"] = false
}

root["courses"] = courses
let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
try output.write(to: seedURL)

let parsedCount = courses.filter { course in
    guard let expr = course["prerequisiteExpr"] as? [String: Any],
          let kind = expr["kind"] as? String else { return false }
    return kind != "empty"
}.count
print("Wrote Data/catalog_seed.json (\(courses.count) courses, \(parsedCount) with parsed prereqs).")
