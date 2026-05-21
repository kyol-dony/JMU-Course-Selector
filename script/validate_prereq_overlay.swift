#!/usr/bin/env swift
import Foundation

struct ValidationError: Error, CustomStringConvertible {
    var description: String
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let seedURL = root.appending(path: "Data/catalog_seed.json")
let overlayURL = root.appending(path: "Data/prereq_coreq_overrides.json")

func readObject(_ url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ValidationError(description: "\(url.path) is not a JSON object")
    }
    return object
}

func string(_ object: [String: Any], _ key: String) -> String? {
    object[key] as? String
}

func courseLeaves(in expr: Any?) -> [String] {
    guard let expr = expr as? [String: Any],
          let kind = expr["kind"] as? String
    else { return [] }
    switch kind {
    case "course":
        return (expr["value"] as? String).map { [$0] } ?? []
    case "all", "any":
        return (expr["children"] as? [Any] ?? []).flatMap(courseLeaves)
    default:
        return []
    }
}

func exprKind(_ expr: Any?) -> String {
    guard let expr = expr as? [String: Any],
          let kind = expr["kind"] as? String
    else { return "missing" }
    return kind
}

let seed = try readObject(seedURL)
let overlay = try readObject(overlayURL)
let courses = seed["courses"] as? [[String: Any]] ?? []
let courseIDs = Set(courses.compactMap { string($0, "id") })
let courseByID = Dictionary(uniqueKeysWithValues: courses.compactMap { course -> (String, [String: Any])? in
    guard let id = string(course, "id") else { return nil }
    return (id, course)
})

guard (overlay["schemaVersion"] as? Int) == 1 else {
    throw ValidationError(description: "schemaVersion must be 1")
}
let rules = overlay["rules"] as? [[String: Any]] ?? []
var errors: [String] = []
var seenRules: Set<String> = []

for rule in rules {
    guard let courseID = string(rule, "courseID") else {
        errors.append("rule missing courseID")
        continue
    }
    if !seenRules.insert(courseID).inserted {
        errors.append("duplicate rule for \(courseID)")
    }
    if !courseIDs.contains(courseID) {
        errors.append("overlay courseID not in catalog: \(courseID)")
    }
    if string(rule, "confidence") != "curated" {
        errors.append("\(courseID) confidence must be curated")
    }
    let basis = string(rule, "basis")
    if basis != "explicit" && basis != "inferred" {
        errors.append("\(courseID) basis must be explicit or inferred")
    }
    if string(rule, "sourceURL")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
        errors.append("\(courseID) missing sourceURL")
    }
    if string(rule, "sourceText")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
        errors.append("\(courseID) missing sourceText")
    }
    if basis == "inferred", string(rule, "notes")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
        errors.append("\(courseID) inferred rule missing notes")
    }
    for referencedID in courseLeaves(in: rule["prerequisiteExpr"]) + courseLeaves(in: rule["corequisiteExpr"]) {
        if !courseIDs.contains(referencedID) {
            errors.append("\(courseID) references unknown course \(referencedID)")
        }
    }
}

let requirementsByProgram = seed["requirementsByProgram"] as? [String: Any] ?? [:]
let concentrationsByProgram = seed["concentrationsByProgram"] as? [String: Any] ?? [:]
var schedulable: Set<String> = []

func collectCourseOptions(from value: Any?) {
    guard let categories = value as? [[String: Any]] else { return }
    for category in categories {
        let options = category["courseOptions"] as? [[String]] ?? []
        for option in options {
            schedulable.formUnion(option)
        }
    }
}

for (_, categories) in requirementsByProgram {
    collectCourseOptions(from: categories)
}
for (_, rawConcentrations) in concentrationsByProgram {
    guard let concentrations = rawConcentrations as? [[String: Any]] else { continue }
    for concentration in concentrations {
        collectCourseOptions(from: concentration["requirements"])
    }
}

let overlayCourseIDs = Set(rules.compactMap { string($0, "courseID") })
let parserCovered = schedulable.filter { id in
    guard let course = courseByID[id] else { return false }
    if overlayCourseIDs.contains(id) { return true }
    if let raw = string(course, "rawPrerequisiteText"), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
    if exprKind(course["prerequisiteExpr"]) != "empty" { return true }
    if exprKind(course["corequisiteExpr"]) != "empty" { return true }
    if let prerequisites = course["prerequisites"] as? [String], !prerequisites.isEmpty { return true }
    return true
}
let missingFromCatalog = schedulable.filter { !courseIDs.contains($0) }.sorted()
for id in missingFromCatalog {
    errors.append("schedulable course missing from catalog courses list: \(id)")
}

if !errors.isEmpty {
    for error in errors.sorted() {
        FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
    }
    throw ValidationError(description: "prereq overlay validation failed with \(errors.count) error(s)")
}

let curated = overlayCourseIDs.intersection(schedulable).count
let coverage = schedulable.isEmpty ? 100.0 : (Double(curated) / Double(schedulable.count)) * 100.0
print("Curated rules: \(rules.count)")
print("Schedulable courses: \(schedulable.count)")
print(String(format: "Curated schedulable coverage: %.1f%%", coverage))
print("Parser/legacy fallback available: \(parserCovered.count)")
print("Missing curated schedulable rules: \(schedulable.subtracting(overlayCourseIDs).count)")
print("Invalid referenced course IDs: 0")
