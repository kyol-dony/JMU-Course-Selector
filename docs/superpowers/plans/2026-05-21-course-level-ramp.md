# Course Level Ramp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make generated schedules prefer lower-level courses early and higher-level courses later, while keeping prerequisites, availability, transfer credit, and workload as hard constraints.

**Architecture:** Add a soft course-level sort inside `ScheduleGenerator.buildSemesters(...)` after current readiness gates. Course level comes from catalog course codes; placeholder/dropdown requirements use median level of their selectable alternates. Existing pathway variants stay intact because variant order remains a tiebreaker.

**Tech Stack:** Swift 6, PlannerCore, Swift Testing, SwiftPM. No new dependencies.

**Source spec:** [`docs/superpowers/specs/2026-05-21-course-level-ramp-design.md`](../specs/2026-05-21-course-level-ramp-design.md)

---

## File Structure

**Modify:**
- `Tests/PlannerCoreTests/ScheduleGeneratorTests.swift` - add level-ramp behavior tests.
- `Sources/PlannerCore/PlannerCore.swift` - add scheduler candidate sorting, course-level parsing, target-level ramp, and placeholder median-level helper.

**Read-only:**
- `docs/superpowers/specs/2026-05-21-course-level-ramp-design.md`
- Dirty `dist/` bundle files unless user explicitly asks to rebuild app bundle.

---

## Task 1: Add Level-Ramp Scheduler Tests

**Files:**
- Modify: `Tests/PlannerCoreTests/ScheduleGeneratorTests.swift`

- [ ] **Step 1: Write failing tests**

Append this suite to `Tests/PlannerCoreTests/ScheduleGeneratorTests.swift`:

```swift
@Suite("Schedule generator course level ramp")
struct ScheduleGeneratorLevelRampTests {
    @Test("scheduler prefers lower-level courses in earlier semesters")
    func schedulerPrefersLowerLevelCoursesEarlier() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS440", code: "CS 440", title: "Advanced Systems", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS340", code: "CS 340", title: "Databases", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS240", code: "CS 240", title: "Data Structures", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS140", code: "CS 140", title: "Intro Computing", credits: 7, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(
                        id: "core",
                        name: "Core",
                        requiredCredits: 28,
                        courseOptions: [["CS440"], ["CS340"], ["CS240"], ["CS140"]]
                    )
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cs-bs",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        #expect(pathway.semesters.map(\.courseIDs) == [["CS140"], ["CS240"], ["CS340"], ["CS440"]])
    }

    @Test("availability can still force an upper-level course into an early semester")
    func availabilityCanForceUpperLevelEarly() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS340", code: "CS 340", title: "Databases", credits: 7, availability: [.fall], prerequisites: []),
                Course(id: "CS140", code: "CS 140", title: "Intro Computing", credits: 7, availability: [.spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 14, courseOptions: [["CS340"], ["CS140"]])
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog, strictPrereqs: true).generatePathways(
            for: "cs-bs",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        #expect(pathway.semesters.map(\.courseIDs) == [["CS340"], ["CS140"]])
    }

    @Test("prerequisites still control high-level course placement")
    func prerequisitesStillControlHighLevelPlacement() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS440", code: "CS 440", title: "Advanced Systems", credits: 7, availability: [.fall, .spring], prerequisites: ["CS140"]),
                Course(id: "CS140", code: "CS 140", title: "Intro Computing", credits: 7, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 14, courseOptions: [["CS440"], ["CS140"]])
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog, strictPrereqs: true).generatePathways(
            for: "cs-bs",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        #expect(pathway.semesters.map(\.courseIDs) == [["CS140"], ["CS440"]])
    }

    @Test("placeholder level uses median level of dropdown alternates")
    func placeholderLevelUsesMedianAlternateLevel() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS440", code: "CS 440", title: "Advanced Systems", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS441", code: "CS 441", title: "Advanced Security", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "WRTC103", code: "WRTC 103", title: "Writing", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "HIST150", code: "HIST 150", title: "History", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "any-bs",
                title: "Any Major, B.S.",
                requirements: [
                    RequirementCategory(id: "upper-elective", name: "Upper Elective", requiredCredits: 7, courseOptions: [["CS440", "CS441", "MISSING400"]]),
                    RequirementCategory(id: "lower-gened", name: "Lower Gen Ed", requiredCredits: 7, courseOptions: [["WRTC103", "HIST150", "MISSING100"]])
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "any-bs",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        let firstPlaceholderID = try #require(pathway.semesters.first?.courseIDs.first)
        let firstSpec = try #require(pathway.placeholders[firstPlaceholderID])
        #expect(firstSpec.categoryName == "Lower Gen Ed")
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter ScheduleGeneratorLevelRampTests
```

Expected: `schedulerPrefersLowerLevelCoursesEarlier` fails because current scheduler follows requirement order. `placeholderLevelUsesMedianAlternateLevel` also fails because placeholders currently follow requirement order, not median alternate level.

- [ ] **Step 3: Keep failing tests unstaged until implementation passes**

Do not commit yet. These tests intentionally fail until Task 2.

---

## Task 2: Implement Soft Level-Aware Candidate Sort

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift`

- [ ] **Step 1: Add private candidate type**

Inside `public struct ScheduleGenerator`, below the initializer, add:

```swift
    private struct ScheduleCandidate: Sendable {
        var courseID: String
        var credits: Int
        var variantOrder: Int
    }
```

- [ ] **Step 2: Replace `buildSemesters(...)` with level-aware version**

In `Sources/PlannerCore/PlannerCore.swift`, replace the full existing `private func buildSemesters(...)` with:

```swift
    private func buildSemesters(
        courseIDs: [String],
        completedAtStart: Set<String>,
        workload: WorkloadPreference,
        starting start: SemesterIdentity,
        placeholders: [String: PlaceholderSpec] = [:],
        activeProgramTitle: String? = nil
    ) throws -> [SemesterPlan] {
        var remaining = courseIDs
        var completed = completedAtStart
        var semester = start
        var semesterOffset = 0
        var result: [SemesterPlan] = []
        var emptySemesterCount = 0
        let resolver = PrereqRuleResolver(catalog: catalog)

        while !remaining.isEmpty {
            var selected: [String] = []
            var credits = 0
            let maxCredits = workload.creditRange.upperBound
            let target = targetLevel(for: semesterOffset)

            let ready = remaining.enumerated().compactMap { order, courseID -> ScheduleCandidate? in
                let courseCredits: Int
                let courseAvailability: Set<SemesterTerm>?
                let prerequisiteExpr: PrereqExpr
                if let spec = placeholders[courseID] {
                    courseCredits = spec.credits
                    courseAvailability = nil
                    prerequisiteExpr = .empty
                } else if let course = catalog.coursesByID[courseID] {
                    courseCredits = course.credits
                    courseAvailability = course.availability
                    prerequisiteExpr = resolver.rule(for: course, activeProgramTitle: activeProgramTitle).prerequisiteExpr
                } else {
                    return nil
                }
                guard case .satisfied = PrereqEvaluator(
                    completedBefore: completed,
                    scheduledThisTerm: []
                ).evaluate(prerequisiteExpr, mode: .prereq) else { return nil }
                if let availability = courseAvailability, !availability.contains(semester.term) { return nil }
                return ScheduleCandidate(courseID: courseID, credits: courseCredits, variantOrder: order)
            }
            .sorted { lhs, rhs in
                compare(lhs, rhs, targetLevel: target, placeholders: placeholders)
            }

            for candidate in ready {
                guard credits + candidate.credits <= maxCredits else { continue }
                selected.append(candidate.courseID)
                credits += candidate.credits
            }

            if selected.isEmpty {
                emptySemesterCount += 1
                guard emptySemesterCount <= 8 else {
                    if !strictPrereqs {
                        if result.isEmpty {
                            result.append(SemesterPlan(id: semester, courseIDs: remaining))
                        } else {
                            result[result.count - 1].courseIDs.append(contentsOf: remaining)
                        }
                        return result
                    }
                    throw PlannerError.impossibleSchedule("Could not place the remaining courses while respecting prerequisites and semester availability.")
                }
                semester = semester.next
                semesterOffset += 1
                continue
            }

            result.append(SemesterPlan(id: semester, courseIDs: selected))
            remaining.removeAll { selected.contains($0) }
            completed.formUnion(selected)
            semester = semester.next
            semesterOffset += 1
        }

        return result
    }
```

- [ ] **Step 3: Add level helpers**

Add these helper methods below `buildSemesters(...)` and above `pathwayName(_:)`:

```swift
    private func compare(
        _ lhs: ScheduleCandidate,
        _ rhs: ScheduleCandidate,
        targetLevel: Int,
        placeholders: [String: PlaceholderSpec]
    ) -> Bool {
        let lhsLevel = courseLevel(for: lhs.courseID, placeholders: placeholders)
        let rhsLevel = courseLevel(for: rhs.courseID, placeholders: placeholders)
        let lhsDistance = abs(lhsLevel - targetLevel)
        let rhsDistance = abs(rhsLevel - targetLevel)
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }
        if lhsLevel != rhsLevel {
            return lhsLevel < rhsLevel
        }
        if lhs.variantOrder != rhs.variantOrder {
            return lhs.variantOrder < rhs.variantOrder
        }
        return lhs.courseID < rhs.courseID
    }

    private func courseLevel(for courseID: String, placeholders: [String: PlaceholderSpec]) -> Int {
        if let spec = placeholders[courseID] {
            return medianAlternateLevel(for: spec.alternates)
        }
        guard let course = catalog.coursesByID[courseID],
              let level = Self.courseLevel(fromCode: course.code)
        else { return 200 }
        return level
    }

    private func medianAlternateLevel(for alternates: [String]) -> Int {
        let levels = alternates.compactMap { id -> Int? in
            guard let course = catalog.coursesByID[id] else { return nil }
            return Self.courseLevel(fromCode: course.code)
        }
        .sorted()

        guard !levels.isEmpty else { return 200 }
        let middle = levels.count / 2
        if levels.count % 2 == 1 {
            return levels[middle]
        }
        let median = Double(levels[middle - 1] + levels[middle]) / 2.0
        return Self.roundToNearestHundred(median)
    }

    private func targetLevel(for semesterOffset: Int) -> Int {
        let clampedOffset = min(max(semesterOffset, 0), 7)
        let raw = 100.0 + (Double(clampedOffset) / 7.0) * 300.0
        return Self.roundToNearestHundred(raw)
    }

    private static func courseLevel(fromCode code: String) -> Int? {
        guard let range = code.range(of: #"\d{3}"#, options: .regularExpression),
              let number = Int(code[range])
        else { return nil }
        let bucket = (number / 100) * 100
        return min(max(bucket, 100), 400)
    }

    private static func roundToNearestHundred(_ value: Double) -> Int {
        Int((value / 100.0).rounded()) * 100
    }
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --filter ScheduleGeneratorLevelRampTests
```

Expected: all tests in `ScheduleGeneratorLevelRampTests` pass.

- [ ] **Step 5: Run scheduler tests**

Run:

```bash
swift test --filter ScheduleGeneratorTests
```

Expected: scheduler tests pass.

- [ ] **Step 6: Commit tests and implementation**

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/ScheduleGeneratorTests.swift
git commit -m "feat: prefer lower-level courses early"
```

---

## Task 3: Full Verification

**Files:**
- No planned edits.

- [ ] **Step 1: Run full test suite**

Run:

```bash
swift test
```

Expected: full test suite passes.

- [ ] **Step 2: Check git state**

Run:

```bash
git status --short
```

Expected: no unstaged source/test changes from this feature. Existing `dist/` dirt may remain:

```text
 M "dist/JMU Course Planner.app/Contents/MacOS/JMUCoursePlanner"
 M "dist/JMU Course Planner.app/Contents/Resources/catalog_seed.json"
?? "dist/JMU Course Planner.app/Contents/Resources/prereq_coreq_overrides.json"
```

- [ ] **Step 3: Optional app bundle rebuild**

Only run if user explicitly wants `dist/` refreshed:

```bash
script/build_and_run.sh --no-launch
```

Expected: app bundle rebuilds. Track or discard resulting `dist/` changes only per user instruction.

---

## Self-Review Notes

- Spec coverage: lower-first behavior, soft availability exception, prereq hard gate, linear target level, placeholder median alternate level, deterministic tie-breakers, and no UI changes are covered.
- Scope is single subsystem: `ScheduleGenerator`.
- Existing generated pathways are not mutated; heuristic only affects future calls to `generatePathways(...)`.
