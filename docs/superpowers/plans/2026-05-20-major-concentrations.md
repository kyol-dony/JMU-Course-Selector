# Major Concentrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Require users to choose one concentration for majors that have concentrations, and schedule only shared major requirements plus the selected concentration.

**Architecture:** Use existing `Program.concentrations` and add `SavedStudentPlan.concentrationID`. Parser splits JMU catalog concentration sections out of parent requirements. Core scheduling/progress APIs accept an optional concentration ID and build an effective program before calculating requirements.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Swift Package Manager.

---

## File Structure

- Modify `Sources/PlannerCore/CatalogHTMLParser.swift`: parse parent requirements and concentration requirements separately.
- Modify `Sources/PlannerCore/PlannerCore.swift`: add concentration-related planner errors, effective program helper, and concentration-aware schedule/progress APIs.
- Modify `Sources/JMUCoursePlanner/Models/SavedStudentPlan.swift`: persist `concentrationID`.
- Modify `Sources/JMUCoursePlanner/Stores/PlanStore.swift`: select/validate concentration and call concentration-aware core APIs.
- Modify `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`: save parsed concentrations to `Program` and bump HTML catalog cache schema.
- Modify `Sources/JMUCoursePlanner/Views/Setup/SetupStepMajor.swift`: show required concentration picker below selected major row.
- Modify `Sources/JMUCoursePlanner/Views/Setup/SetupSheet.swift`: block Next/Generate until required concentration selected.
- Modify `Sources/JMUCoursePlanner/Views/Tabs/CatalogView.swift`, `GraduationProgressView.swift`, `MyPlanView.swift`, and `ScheduleBoardView.swift`: read effective requirements where they display active-major requirement categories.
- Modify `LIMITATIONS.md`: document concentration support and partial parsing fallback.
- Test `Tests/PlannerCoreTests/CatalogHTMLParserTests.swift`: parser split behavior.
- Test `Tests/PlannerCoreTests/ScheduleGeneratorTests.swift`: selected concentration is scheduled, sibling concentration excluded.
- Test `Tests/PlannerCoreTests/ConflictAndProgressTests.swift`: progress includes selected concentration only.
- Test `Tests/PlannerCoreTests/PlanStoreConcentrationTests.swift`: app store selection and validation behavior.

---

### Task 1: Parser Splits Concentrations

**Files:**
- Modify: `Sources/PlannerCore/CatalogHTMLParser.swift`
- Test: `Tests/PlannerCoreTests/CatalogHTMLParserTests.swift`

- [ ] **Step 1: Write failing parser test**

Append this test inside `CatalogHTMLParserTests`:

```swift
@Test("major concentrations are split out of parent requirements")
func parsesConcentrationsSeparatelyFromParentRequirements() throws {
    let html = """
    <h1 id="acalog-content">Physics, B.S.</h1>
    <div class="acalog-core"><h2><a name="DegreeAndMajorRequirements"></a>Degree and Major Requirements</h2><hr></div>
    <div class="acalog-core"><h3><a name="PhysicsCore"></a>Physics Core: 4 Credit Hours</h3><hr>
      <ul>
        <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '1',this, 'x'); return false;">PHYS 240. University Physics I</a> <em><strong>Credits:</strong></em> <em>4.00</em></span></li>
      </ul>
    </div>
    <div class="acalog-core"><h2><a name="Concentrations"></a>Concentrations</h2><hr></div>
    <div class="acalog-core"><h3><a name="AppliedPhysicsConcentration"></a>Applied Physics Concentration</h3><hr></div>
    <div class="acalog-core"><h4><a name="AppliedPhysicsRequiredCourses"></a>Applied Physics Required Courses: 3 Credit Hours</h4><hr>
      <ul>
        <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '2',this, 'x'); return false;">PHYS 360. Modern Physics</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
      </ul>
    </div>
    <div class="acalog-core"><h3><a name="FundamentalStudiesConcentration"></a>Fundamental Studies Concentration</h3><hr></div>
    <div class="acalog-core"><h4><a name="FundamentalStudiesRequiredCourses"></a>Fundamental Studies Required Courses: 3 Credit Hours</h4><hr>
      <ul>
        <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '3',this, 'x'); return false;">PHYS 390. Advanced Seminar</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
      </ul>
    </div>
    <div class="acalog-core"><h2><a name="RecommendedScheduleForMajors"></a>Recommended Schedule for Majors</h2><hr></div>
    """

    let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27000&returnto=3541"))
    let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

    #expect(parsed.requirements.map(\.name) == ["Physics Core: 4 Credit Hours"])
    #expect(parsed.requirements.flatMap(\.courseOptions).flatMap { $0 } == ["PHYS240"])
    #expect(parsed.concentrations.map(\.name) == ["Applied Physics Concentration", "Fundamental Studies Concentration"])
    #expect(parsed.concentrations[0].requirements.map(\.name) == ["Applied Physics Required Courses: 3 Credit Hours"])
    #expect(parsed.concentrations[0].requirements.flatMap(\.courseOptions).flatMap { $0 } == ["PHYS360"])
    #expect(parsed.concentrations[1].requirements.flatMap(\.courseOptions).flatMap { $0 } == ["PHYS390"])
    #expect(parsed.courses.map(\.id).sorted() == ["PHYS240", "PHYS360", "PHYS390"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter CatalogHTMLParserTests/parsesConcentrationsSeparatelyFromParentRequirements
```

Expected: compile fails because `HTMLProgramRequirements` has no `concentrations`, or assertion fails because concentration blocks remain parent requirements.

- [ ] **Step 3: Add concentrations to parser result**

In `HTMLProgramRequirements`, add field and init parameter:

```swift
public struct HTMLProgramRequirements: Sendable {
    public var title: String?
    public var requirements: [RequirementCategory]
    public var concentrations: [Concentration]
    public var courses: [Course]
    public var totalCredits: Int?

    public init(
        title: String?,
        requirements: [RequirementCategory],
        concentrations: [Concentration] = [],
        courses: [Course],
        totalCredits: Int?
    ) {
        self.title = title
        self.requirements = requirements
        self.concentrations = concentrations
        self.courses = courses
        self.totalCredits = totalCredits
    }
}
```

- [ ] **Step 4: Make requirement blocks carry heading level**

Replace `RequirementBlock` and update `requirementBlocks(in:)` so each block knows `h2`/`h3`/`h4` depth:

```swift
private struct RequirementBlock {
    var level: Int
    var heading: String
    var body: String
}
```

Inside `requirementBlocks(in:)`, parse level from the marker with:

```swift
let markerMatch = String(html[markerRange]).firstMatch(for: #"(?is)<h([2-5])\b"#)
let level = markerMatch?.dropFirst().first.flatMap(Int.init) ?? 3
```

Return `RequirementBlock(level: level, heading: heading, body: body)`.

- [ ] **Step 5: Extract category-building helper**

Move the existing per-block parsing logic from `parseProgramRequirements` into helper:

```swift
private func category(
    from block: RequirementBlock,
    catoid: String,
    usedCategoryIDs: inout Set<String>,
    coursesByID: inout [String: Course]
) -> RequirementCategory? {
    let courseItems = courseItems(in: block.body, catoid: catoid)
    let courses = courseItems.compactMap { item -> Course? in
        if case .course(let course) = item { return course }
        return nil
    }

    guard !shouldIgnoreRequirementHeading(block.heading, hasCourses: !courses.isEmpty) else {
        return nil
    }

    for course in courses {
        coursesByID[course.id] = course
    }

    let selectionCount = choiceSelectionCount(heading: block.heading, body: block.body)
    let requiredCredits = parseCredits(from: block.heading)
        ?? parseTotalCreditsFromBody(block.body)
        ?? inferredCredits(for: courseItems, selectionCount: selectionCount)

    guard requiredCredits > 0 || !courses.isEmpty else { return nil }

    let options = courseOptions(from: courseItems, selectionCount: selectionCount)
    let categoryID = uniqueID(slug(from: block.heading), used: &usedCategoryIDs)
    let note = note(for: block, options: options, courses: courses)

    return RequirementCategory(
        id: categoryID,
        name: block.heading,
        requiredCredits: requiredCredits,
        courseOptions: options,
        verificationStatus: .partial,
        note: note
    )
}
```

- [ ] **Step 6: Split concentration blocks**

Add helpers:

```swift
private func splitConcentrationBlocks(_ blocks: [RequirementBlock]) -> (shared: [RequirementBlock], concentrationRuns: [(name: String, blocks: [RequirementBlock])]) {
    guard let concentrationIndex = blocks.firstIndex(where: { $0.heading.caseInsensitiveCompare("Concentrations") == .orderedSame }) else {
        return (blocks, [])
    }

    let shared = Array(blocks[..<concentrationIndex])
    let tail = Array(blocks[(concentrationIndex + 1)...])
    var runs: [(name: String, blocks: [RequirementBlock])] = []
    var currentName: String?
    var currentBlocks: [RequirementBlock] = []

    for block in tail {
        if isConcreteConcentrationHeading(block.heading) {
            if let currentName, !currentBlocks.isEmpty {
                runs.append((currentName, currentBlocks))
            }
            currentName = block.heading
            currentBlocks = [block]
        } else if currentName != nil {
            currentBlocks.append(block)
        }
    }

    if let currentName, !currentBlocks.isEmpty {
        runs.append((currentName, currentBlocks))
    }

    return (shared, runs)
}

private func isConcreteConcentrationHeading(_ heading: String) -> Bool {
    let lower = heading.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return lower != "concentrations" && lower.hasSuffix("concentration")
}
```

- [ ] **Step 7: Build parsed requirements and concentrations**

Update `parseProgramRequirements`:

```swift
let blocks = requirementBlocks(in: requirementSlice)
let split = splitConcentrationBlocks(blocks)
var categories: [RequirementCategory] = []
for block in split.shared {
    if let parsed = category(from: block, catoid: catoid, usedCategoryIDs: &usedCategoryIDs, coursesByID: &coursesByID) {
        categories.append(parsed)
    }
}

var usedConcentrationIDs: Set<String> = []
let concentrations = split.concentrationRuns.compactMap { run -> Concentration? in
    var usedRequirementIDs: Set<String> = []
    var requirements: [RequirementCategory] = []
    for block in run.blocks {
        if let parsed = category(from: block, catoid: catoid, usedCategoryIDs: &usedRequirementIDs, coursesByID: &coursesByID) {
            requirements.append(parsed)
        }
    }
    guard !requirements.isEmpty else { return nil }
    return Concentration(
        id: uniqueID(slug(from: run.name), used: &usedConcentrationIDs),
        name: run.name,
        requirements: requirements,
        verificationStatus: .partial
    )
}
```

Return:

```swift
return HTMLProgramRequirements(
    title: title,
    requirements: categories,
    concentrations: concentrations,
    courses: coursesByID.values.sorted { $0.code < $1.code },
    totalCredits: parseProgramTotal(from: html)
)
```

- [ ] **Step 8: Run parser tests**

Run:

```bash
swift test --filter CatalogHTMLParserTests
```

Expected: all parser tests pass.

- [ ] **Step 9: Commit parser split**

```bash
git add Sources/PlannerCore/CatalogHTMLParser.swift Tests/PlannerCoreTests/CatalogHTMLParserTests.swift
git commit -m "feat: parse major concentrations"
```

---

### Task 2: Core Uses Effective Concentration Requirements

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift`
- Test: `Tests/PlannerCoreTests/ScheduleGeneratorTests.swift`
- Test: `Tests/PlannerCoreTests/ConflictAndProgressTests.swift`

- [ ] **Step 1: Write failing schedule test**

Append to `ScheduleGeneratorTests`:

```swift
@Test("scheduler includes selected concentration and excludes siblings")
func schedulerUsesSelectedConcentrationOnly() throws {
    let program = Program(
        id: "physics-bs",
        title: "Physics, B.S.",
        degreeType: "B.S.",
        kind: .major,
        college: "College of Science and Mathematics",
        department: "Physics and Astronomy",
        catalogPage: nil,
        totalCredits: 120,
        requirements: [
            RequirementCategory(id: "core", name: "Physics Core", requiredCredits: 4, courseOptions: [["PHYS240"]])
        ],
        concentrations: [
            Concentration(id: "applied-physics-concentration", name: "Applied Physics Concentration", requirements: [
                RequirementCategory(id: "applied", name: "Applied Physics Required Courses", requiredCredits: 3, courseOptions: [["PHYS360"]])
            ]),
            Concentration(id: "fundamental-studies-concentration", name: "Fundamental Studies Concentration", requirements: [
                RequirementCategory(id: "fundamental", name: "Fundamental Studies Required Courses", requiredCredits: 3, courseOptions: [["PHYS390"]])
            ])
        ],
        verificationStatus: .partial,
        requirementDataComplete: true,
        sourceNote: "Fixture"
    )
    let catalog = Catalog.fixture(
        courses: [
            Course(id: "PHYS240", code: "PHYS 240", title: "University Physics I", credits: 4, availability: [.fall, .spring], prerequisites: []),
            Course(id: "PHYS360", code: "PHYS 360", title: "Modern Physics", credits: 3, availability: [.fall, .spring], prerequisites: []),
            Course(id: "PHYS390", code: "PHYS 390", title: "Advanced Seminar", credits: 3, availability: [.fall, .spring], prerequisites: [])
        ],
        program: program
    )

    let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
        for: "physics-bs",
        concentrationID: "applied-physics-concentration",
        workload: .standard,
        transferCredits: [],
        starting: SemesterIdentity(year: 2026, term: .fall)
    )

    let scheduled = pathways.first?.semesters.flatMap(\.courseIDs) ?? []
    #expect(scheduled.contains("PHYS240"))
    #expect(scheduled.contains("PHYS360"))
    #expect(!scheduled.contains("PHYS390"))
}
```

- [ ] **Step 2: Write failing progress test**

Append to `ConflictAndProgressTests`:

```swift
@Test("progress includes selected concentration and excludes siblings")
func progressUsesSelectedConcentrationOnly() throws {
    let program = Program(
        id: "physics-bs",
        title: "Physics, B.S.",
        degreeType: "B.S.",
        kind: .major,
        college: "College of Science and Mathematics",
        department: "Physics and Astronomy",
        catalogPage: nil,
        totalCredits: 120,
        requirements: [
            RequirementCategory(id: "core", name: "Physics Core", requiredCredits: 4, courseOptions: [["PHYS240"]])
        ],
        concentrations: [
            Concentration(id: "applied-physics-concentration", name: "Applied Physics Concentration", requirements: [
                RequirementCategory(id: "applied", name: "Applied Physics Required Courses", requiredCredits: 3, courseOptions: [["PHYS360"]])
            ]),
            Concentration(id: "fundamental-studies-concentration", name: "Fundamental Studies Concentration", requirements: [
                RequirementCategory(id: "fundamental", name: "Fundamental Studies Required Courses", requiredCredits: 3, courseOptions: [["PHYS390"]])
            ])
        ],
        verificationStatus: .partial,
        requirementDataComplete: true,
        sourceNote: "Fixture"
    )
    let catalog = Catalog.fixture(
        courses: [
            Course(id: "PHYS240", code: "PHYS 240", title: "University Physics I", credits: 4, availability: nil, prerequisites: []),
            Course(id: "PHYS360", code: "PHYS 360", title: "Modern Physics", credits: 3, availability: nil, prerequisites: []),
            Course(id: "PHYS390", code: "PHYS 390", title: "Advanced Seminar", credits: 3, availability: nil, prerequisites: [])
        ],
        program: program
    )
    let pathway = Pathway(id: "p", name: "Path", semesters: [
        SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["PHYS240", "PHYS360"])
    ])

    let progress = try ProgressCalculator(catalog: catalog).progress(
        programID: "physics-bs",
        concentrationID: "applied-physics-concentration",
        pathway: pathway,
        transferCredits: []
    )

    #expect(progress.categories.map(\.id) == ["core", "applied"])
    #expect(progress.overallRequiredCredits == 7)
    #expect(progress.overallCompletedCredits == 7)
}
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
swift test --filter ScheduleGeneratorTests/schedulerUsesSelectedConcentrationOnly
swift test --filter ConflictAndProgressTests/progressUsesSelectedConcentrationOnly
```

Expected: compile fails because core APIs do not accept `concentrationID`.

- [ ] **Step 4: Add planner errors**

In `PlannerError`, add:

```swift
case concentrationRequired(String)
case concentrationNotFound(programTitle: String, concentrationID: String)
```

Add descriptions:

```swift
case .concentrationRequired(let title):
    "\(title) requires a concentration before generating a plan."
case .concentrationNotFound(let title, let concentrationID):
    "\(title) does not include concentration \(concentrationID). Choose a current concentration."
```

- [ ] **Step 5: Add effective program helper**

Add extension near `Program.fixture`:

```swift
public extension Program {
    func effectiveProgram(concentrationID: String?) throws -> Program {
        guard !concentrations.isEmpty else { return self }
        guard let concentrationID else {
            throw PlannerError.concentrationRequired(title)
        }
        guard let concentration = concentrations.first(where: { $0.id == concentrationID }) else {
            throw PlannerError.concentrationNotFound(programTitle: title, concentrationID: concentrationID)
        }
        var effective = self
        effective.requirements = requirements + concentration.requirements
        effective.sourceNote = "\(sourceNote) Selected concentration: \(concentration.name)."
        return effective
    }
}
```

- [ ] **Step 6: Update schedule API**

Change `generatePathways` signature:

```swift
public func generatePathways(
    for programID: String,
    concentrationID: String? = nil,
    workload: WorkloadPreference,
    transferCredits: [TransferCredit],
    starting start: SemesterIdentity = SemesterIdentity(year: Calendar.current.component(.year, from: Date()), term: .fall)
) throws -> [Pathway]
```

Change first line:

```swift
let program = try programForScheduling(programID, concentrationID: concentrationID)
```

Change helper:

```swift
private func programForScheduling(_ programID: String, concentrationID: String?) throws -> Program {
    guard let rawProgram = catalog.programsByID[programID] else {
        throw PlannerError.programNotFound(programID)
    }
    let program = try rawProgram.effectiveProgram(concentrationID: concentrationID)
    let hasAnyCourse = program.requirements.contains { !$0.courseOptions.isEmpty }
    guard hasAnyCourse else {
        throw PlannerError.programRequirementsUnavailable(program.title)
    }
    return program
}
```

- [ ] **Step 7: Update progress API**

Change `ProgressCalculator.progress` signature:

```swift
public func progress(
    programID: String,
    concentrationID: String? = nil,
    pathway: Pathway,
    transferCredits: [TransferCredit]
) throws -> GraduationProgress
```

After program lookup:

```swift
let effectiveProgram = try program.effectiveProgram(concentrationID: concentrationID)
```

Change categories source:

```swift
let categories = effectiveProgram.requirements.map { category in
```

- [ ] **Step 8: Update `Program.fixture` for concentration tests**

Add optional concentrations parameter:

```swift
static func fixture(id: String, title: String, requirements: [RequirementCategory], concentrations: [Concentration] = []) -> Program
```

Pass `concentrations: concentrations` to `Program(...)`.

- [ ] **Step 9: Run core tests**

Run:

```bash
swift test --filter ScheduleGeneratorTests
swift test --filter ConflictAndProgressTests
```

Expected: tests pass.

- [ ] **Step 10: Commit core effective requirements**

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/ScheduleGeneratorTests.swift Tests/PlannerCoreTests/ConflictAndProgressTests.swift
git commit -m "feat: apply selected concentration requirements"
```

---

### Task 3: Store Persists And Validates Concentration

**Files:**
- Modify: `Sources/JMUCoursePlanner/Models/SavedStudentPlan.swift`
- Modify: `Sources/JMUCoursePlanner/Stores/PlanStore.swift`
- Test: `Tests/PlannerCoreTests/PlanStoreConcentrationTests.swift`

- [ ] **Step 1: Write failing store tests**

Create `Tests/PlannerCoreTests/PlanStoreConcentrationTests.swift`:

```swift
import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Plan store concentration selection")
@MainActor
struct PlanStoreConcentrationTests {
    @Test("selecting a major with concentrations requires concentration")
    func majorWithConcentrationsRequiresSelection() {
        let store = PlanStore()
        store.catalog = Catalog.fixture(
            courses: [],
            program: Program.fixture(
                id: "physics-bs",
                title: "Physics, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["PHYS240"]])
                ],
                concentrations: [
                    Concentration(id: "applied-physics-concentration", name: "Applied Physics Concentration", requirements: [
                        RequirementCategory(id: "applied", name: "Applied", requiredCredits: 3, courseOptions: [["PHYS360"]])
                    ])
                ]
            )
        )

        store.selectProgram(try! #require(store.catalog?.programs.first))

        #expect(store.requiresConcentrationSelection)
        #expect(!store.majorSelectionComplete)
        store.selectConcentration(id: "applied-physics-concentration")
        #expect(store.plan.concentrationID == "applied-physics-concentration")
        #expect(store.majorSelectionComplete)
    }

    @Test("changing major clears invalid concentration")
    func changingMajorClearsInvalidConcentration() {
        let physics = Program.fixture(
            id: "physics-bs",
            title: "Physics, B.S.",
            requirements: [],
            concentrations: [
                Concentration(id: "applied-physics-concentration", name: "Applied Physics Concentration", requirements: [])
            ]
        )
        let chemistry = Program.fixture(id: "chemistry-bs", title: "Chemistry, B.S.", requirements: [])
        let store = PlanStore()
        store.catalog = Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: .distantPast, retrievedDate: .distantPast, sourceURLs: [], retrievalNotes: []),
            programs: [physics, chemistry],
            courses: [],
            apCreditRules: []
        )

        store.selectProgram(physics)
        store.selectConcentration(id: "applied-physics-concentration")
        store.selectProgram(chemistry)

        #expect(store.plan.programID == "chemistry-bs")
        #expect(store.plan.concentrationID == nil)
        #expect(store.majorSelectionComplete)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter PlanStoreConcentrationTests
```

Expected: compile fails because `SavedStudentPlan.concentrationID`, `requiresConcentrationSelection`, `majorSelectionComplete`, and `selectConcentration(id:)` do not exist.

- [ ] **Step 3: Add saved plan field**

In `SavedStudentPlan`, add stored property after `programID`:

```swift
var concentrationID: String?
```

Add init parameter after `programID`:

```swift
concentrationID: String? = nil,
```

Assign:

```swift
self.concentrationID = concentrationID
```

- [ ] **Step 4: Add store selection state**

In `PlanStore`, add:

```swift
var activeConcentration: Concentration? {
    guard let activeProgram, let concentrationID = plan.concentrationID else { return nil }
    return activeProgram.concentrations.first { $0.id == concentrationID }
}

var requiresConcentrationSelection: Bool {
    guard let activeProgram else { return false }
    return !activeProgram.concentrations.isEmpty
}

var majorSelectionComplete: Bool {
    guard let activeProgram else { return false }
    guard !activeProgram.concentrations.isEmpty else { return true }
    guard let concentrationID = plan.concentrationID else { return false }
    return activeProgram.concentrations.contains { $0.id == concentrationID }
}

var effectiveActiveProgram: Program? {
    guard let activeProgram else { return nil }
    return try? activeProgram.effectiveProgram(concentrationID: plan.concentrationID)
}
```

- [ ] **Step 5: Update `selectProgram` and add concentration selector**

Change `selectProgram(_:)`:

```swift
func selectProgram(_ program: Program) {
    let previousConcentrationID = plan.concentrationID
    plan.programID = program.id
    if let previousConcentrationID,
       program.concentrations.contains(where: { $0.id == previousConcentrationID }) {
        plan.concentrationID = previousConcentrationID
    } else {
        plan.concentrationID = nil
    }
    plan.pathways = []
    plan.activePathwayID = nil
    recomputeAPCredits()
    autosave()
}
```

Add:

```swift
func selectConcentration(id: String?) {
    guard let activeProgram else { return }
    if let id, activeProgram.concentrations.contains(where: { $0.id == id }) {
        plan.concentrationID = id
    } else {
        plan.concentrationID = nil
    }
    plan.pathways = []
    plan.activePathwayID = nil
    recomputeAPCredits()
    autosave()
}
```

- [ ] **Step 6: Use effective program in store calculations**

Change `progress`:

```swift
return try? ProgressCalculator(catalog: catalog).progress(
    programID: programID,
    concentrationID: plan.concentrationID,
    pathway: activePathway,
    transferCredits: plan.transferCredits
)
```

Change AP recompute:

```swift
program: effectiveActiveProgram,
```

Change `generateSchedules()` guard:

```swift
guard majorSelectionComplete else {
    if requiresConcentrationSelection {
        errorMessage = "Choose a concentration before generating a plan."
    } else {
        errorMessage = "Choose a major before generating a plan."
    }
    return
}
```

Change schedule generation:

```swift
plan.pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
    for: programID,
    concentrationID: plan.concentrationID,
    workload: plan.workload,
    transferCredits: plan.transferCredits,
    starting: SemesterIdentity(year: 2026, term: .fall)
)
```

- [ ] **Step 7: Run store tests**

Run:

```bash
swift test --filter PlanStoreConcentrationTests
```

Expected: tests pass.

- [ ] **Step 8: Commit store selection**

```bash
git add Sources/JMUCoursePlanner/Models/SavedStudentPlan.swift Sources/JMUCoursePlanner/Stores/PlanStore.swift Tests/PlannerCoreTests/PlanStoreConcentrationTests.swift
git commit -m "feat: store selected concentration"
```

---

### Task 4: UI Requires Concentration In Setup

**Files:**
- Modify: `Sources/JMUCoursePlanner/Views/Setup/SetupStepMajor.swift`
- Modify: `Sources/JMUCoursePlanner/Views/Setup/SetupSheet.swift`
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/CatalogView.swift`
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift`
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift`
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift`

- [ ] **Step 1: Add concentration picker under selected major**

In `SetupStepMajor.programRow(_:)`, wrap button and picker in a `VStack`:

```swift
private func programRow(_ program: Program) -> some View {
    let isSelected = store.plan.programID == program.id
    return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
        Button {
            store.selectProgram(program)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.title)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    HStack(spacing: DesignTokens.Spacing.s) {
                        if let degree = program.degreeType {
                            StatusPill(text: degree, tone: .info)
                        }
                        StatusPill(
                            text: program.requirementDataComplete ? "Verified" : "Partial",
                            tone: program.requirementDataComplete ? .success : .warning
                        )
                        if !program.concentrations.isEmpty {
                            StatusPill(text: "Concentration required", tone: .warning)
                        }
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.Colors.brandPurple)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.brandPurpleSoft : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if isSelected, !program.concentrations.isEmpty {
            concentrationPicker(for: program)
        }
    }
}
```

Add helper:

```swift
private func concentrationPicker(for program: Program) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("Concentration")
            .font(DesignTokens.Typography.label)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
        Picker("Concentration", selection: Binding(
            get: { store.plan.concentrationID ?? "" },
            set: { store.selectConcentration(id: $0.isEmpty ? nil : $0) }
        )) {
            Text("Select concentration").tag("")
            ForEach(program.concentrations) { concentration in
                Text(concentration.name).tag(concentration.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
    .padding(.leading, DesignTokens.Spacing.l)
    .padding(.bottom, DesignTokens.Spacing.s)
}
```

- [ ] **Step 2: Block setup navigation**

In `SetupSheet.footer`, change disabled states:

```swift
.disabled(step == 0 && !store.majorSelectionComplete)
```

and:

```swift
.disabled(!store.majorSelectionComplete)
```

for Generate Plan.

- [ ] **Step 3: Replace active-program requirement display with effective requirements**

Where views build requirement lookup from `program.requirements`, use:

```swift
let requirementProgram = store.effectiveActiveProgram ?? program
```

Then map `requirementProgram.requirements`.

Apply this to:

- `GraduationProgressView`
- `MyPlanView`
- `ScheduleBoardView`

For `CatalogView`, keep catalog browsing on raw `program.requirements`, but add a section below parent requirements when `program.concentrations` is non-empty:

```swift
ForEach(program.concentrations) { concentration in
    DisclosureGroup(concentration.name) {
        ForEach(concentration.requirements) { requirement in
            requirementRow(requirement)
        }
    }
}
```

Use existing local row helper names in `CatalogView`; do not invent duplicate row styling if a helper already exists.

- [ ] **Step 4: Build app**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 5: Commit setup UI**

```bash
git add Sources/JMUCoursePlanner/Views/Setup/SetupStepMajor.swift Sources/JMUCoursePlanner/Views/Setup/SetupSheet.swift Sources/JMUCoursePlanner/Views/Tabs/CatalogView.swift Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift
git commit -m "feat: require concentration in setup"
```

---

### Task 5: Repository Saves Concentrations And Cache Refreshes

**Files:**
- Modify: `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`
- Modify: `LIMITATIONS.md`
- Test: existing parser/core/store tests

- [ ] **Step 1: Pass concentrations into refreshed programs**

In `refreshCatalogFromHTML`, after `parsedRequirements`, add:

```swift
let parsedConcentrations = requirements?.concentrations ?? []
```

In `Program(...)`, add:

```swift
concentrations: parsedConcentrations,
```

- [ ] **Step 2: Update source notes**

Change retrieval note string from:

```swift
"Sections that depend on prose, unrestricted electives, concentrations, or advisor-selected choices are marked partial instead of inferred."
```

to:

```swift
"Course-bearing concentration sections are parsed as selectable concentrations. Prose-only, unrestricted elective, and advisor-selected sections are marked partial instead of inferred."
```

- [ ] **Step 3: Bump cache schema**

Change:

```swift
private static let cacheSchemaVersion = 2
```

to:

```swift
private static let cacheSchemaVersion = 3
```

Update comment to say v3 splits concentration requirements out of parent major requirements, so older flattened caches must not be reused.

- [ ] **Step 4: Update limitations**

In `LIMITATIONS.md`, replace concentration limitation text with:

```markdown
- Concentrations/tracks are supported for catalog pages where JMU exposes course-bearing concentration sections. The setup flow requires selecting one concentration for those majors, and generated plans include the shared major core plus the selected concentration only.
- Concentration sections that are prose-only or cannot be safely split remain partially verified; the parser does not infer advisor-selected or unofficial tracks.
```

- [ ] **Step 5: Run full verification**

Run:

```bash
swift test
swift build
```

Expected: both pass.

- [ ] **Step 6: Commit repository/docs**

```bash
git add Sources/JMUCoursePlanner/Services/CatalogRepository.swift LIMITATIONS.md
git commit -m "feat: refresh catalog concentration data"
```

---

## Final Verification

- [ ] Run:

```bash
swift test
swift build
```

- [ ] Manual app check:

```bash
swift run JMUCoursePlanner
```

Expected behavior:

- Major with no concentrations can proceed after major selection.
- Major with concentrations shows required dropdown below selected major.
- Next and Generate Plan stay disabled until concentration selected.
- Generated schedule includes parent core courses plus selected concentration courses.
- Generated schedule excludes sibling concentration courses.

- [ ] Final status check:

```bash
git status --short
```

Expected: only pre-existing unrelated files may remain dirty. Do not stage or revert unrelated dist artifacts.
