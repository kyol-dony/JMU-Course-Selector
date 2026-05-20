# Requirement Choice Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let students choose one parsed course option for elective/open-ended requirements, persist that choice, and generate schedules/progress from that selected option.

**Architecture:** Store user choices in `SavedStudentPlan.requirementSelections` as scoped string keys mapped to selected course ID arrays. `PlanStore` owns scope/key translation, validation, and UI-facing helpers; `PlannerCore` receives a normalized per-requirement selection map and narrows scheduler/progress logic without knowing app storage details. `MyPlanView` adds the picker inside requirement progress cards so the student chooses from parsed catalog options before regenerating.

**Tech Stack:** Swift, SwiftUI, Swift Testing, Swift Package Manager, existing `PlannerCore` schedule/progress APIs.

---

## File Structure

- Modify `Sources/PlannerCore/PlannerCore.swift`
  - Add stable `RequirementCategory.selectionKey`.
  - Add optional `requirementSelections` arguments to `ScheduleGenerator.generatePathways` and `ProgressCalculator.progress`.
  - Use selected options when computing required course IDs and completed category progress.
- Modify `Sources/JMUCoursePlanner/Models/SavedStudentPlan.swift`
  - Persist `[String: [String]]` requirement selections.
  - Decode old saved plans with empty selections.
- Modify `Sources/JMUCoursePlanner/Stores/PlanStore.swift`
  - Build scoped storage keys.
  - Expose selected option, selectable options, display labels, remaining-course helpers, and mutation API.
  - Normalize selections for `PlannerCore`.
  - Clear generated pathways when a requirement selection changes.
  - Validate selections after loading catalog/plans and after major/concentration changes.
- Modify `Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift`
  - Replace the single button-wrapped requirement row with a row containing a clickable progress rail plus a picker for selectable requirements.
- Modify `Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift`
  - Show remaining courses from the selected option when present.
- Modify `Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift`
  - Highlight selected-option courses instead of all alternates when a category filter is active.
- Create `Tests/PlannerCoreTests/RequirementSelectionCoreTests.swift`
  - Core scheduler/progress tests for selected parsed options.
- Create `Tests/PlannerCoreTests/RequirementSelectionStoreTests.swift`
  - App/store tests for persistence, normalization, pathway invalidation, and stale-selection pruning.

## Task 1: Core Requirement Selection Logic

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift`
- Create: `Tests/PlannerCoreTests/RequirementSelectionCoreTests.swift`

- [ ] **Step 1: Write failing scheduler/progress tests**

Create `Tests/PlannerCoreTests/RequirementSelectionCoreTests.swift`:

```swift
import Testing
@testable import PlannerCore

@Suite
struct RequirementSelectionCoreTests {
    @Test
    func schedulerUsesSelectedRequirementOption() throws {
        let catalog = requirementSelectionCatalog()
        let selectionKey = catalog.programs[0].requirements[0].selectionKey

        let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cis-bba",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall),
            requirementSelections: [selectionKey: ["CIS-484"]]
        )

        let scheduled = Set(try #require(pathways.first).semesters.flatMap(\.courseIDs))
        #expect(scheduled.contains("CIS-484"))
        #expect(!scheduled.contains("CIS-464"))
    }

    @Test
    func schedulerSkipsSelectedOptionWhenTransferCreditAlreadyCompletesIt() throws {
        let catalog = requirementSelectionCatalog()
        let selectionKey = catalog.programs[0].requirements[0].selectionKey

        let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cis-bba",
            workload: .light,
            transferCredits: [
                TransferCredit(sourceDescription: "Transfer", courseIDs: ["CIS-484"], credits: 3)
            ],
            starting: SemesterIdentity(year: 2026, term: .fall),
            requirementSelections: [selectionKey: ["CIS-484"]]
        )

        let scheduled = Set(try #require(pathways.first).semesters.flatMap(\.courseIDs))
        #expect(!scheduled.contains("CIS-484"))
        #expect(!scheduled.contains("CIS-464"))
    }

    @Test
    func progressUsesSelectedRequirementOption() throws {
        let catalog = requirementSelectionCatalog()
        let selectionKey = catalog.programs[0].requirements[0].selectionKey
        let pathway = Pathway(
            id: "path-1",
            name: "Path",
            semesters: [
                SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CIS-484"])
            ]
        )

        let progress = try ProgressCalculator(catalog: catalog).progress(
            programID: "cis-bba",
            pathway: pathway,
            transferCredits: [],
            requirementSelections: [selectionKey: ["CIS-484"]]
        )

        let category = try #require(progress.categories.first)
        #expect(category.completedCredits == 3)
        #expect(progress.overallCompletedCredits == 3)
    }

    @Test
    func invalidSelectionFallsBackToCatalogDefault() throws {
        let catalog = requirementSelectionCatalog()
        let selectionKey = catalog.programs[0].requirements[0].selectionKey

        let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cis-bba",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall),
            requirementSelections: [selectionKey: ["NOT-A-COURSE"]]
        )

        let scheduled = Set(try #require(pathways.first).semesters.flatMap(\.courseIDs))
        #expect(scheduled.contains("CIS-464"))
        #expect(!scheduled.contains("CIS-484"))
    }
}

private func requirementSelectionCatalog() -> Catalog {
    let courses = [
        Course(id: "CIS-464", code: "CIS 464", title: "Information Security", credits: 3),
        Course(id: "CIS-484", code: "CIS 484", title: "Cyber Defense", credits: 3)
    ]
    let requirement = RequirementCategory(
        id: "cis-elective",
        name: "CIS Elective",
        requiredCredits: 3,
        courseOptions: [["CIS-464"], ["CIS-484"]]
    )
    let program = Program.fixture(id: "cis-bba", title: "Computer Information Systems", requirements: [requirement])
    return Catalog.fixture(courses: courses, program: program)
}
```

- [ ] **Step 2: Run failing core tests**

Run:

```bash
swift test --filter RequirementSelectionCoreTests
```

Expected: FAIL because `RequirementCategory.selectionKey`, `ScheduleGenerator.generatePathways` with `requirementSelections`, and `ProgressCalculator.progress` with `requirementSelections` do not exist.

- [ ] **Step 3: Add `selectionKey` to `RequirementCategory`**

In `Sources/PlannerCore/PlannerCore.swift`, inside `RequirementCategory`, add:

```swift
    public var selectionKey: String {
        "\(id)::\(name)"
    }
```

The full struct should include:

```swift
public struct RequirementCategory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var requiredCredits: Int
    public var courseOptions: [[String]]
    public var verificationStatus: VerificationStatus
    public var note: String?

    public var selectionKey: String {
        "\(id)::\(name)"
    }

    public init(
        id: String,
        name: String,
        requiredCredits: Int,
        courseOptions: [[String]],
        verificationStatus: VerificationStatus = .verified,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.requiredCredits = requiredCredits
        self.courseOptions = courseOptions
        self.verificationStatus = verificationStatus
        self.note = note
    }
}
```

- [ ] **Step 4: Update `ScheduleGenerator.generatePathways` signature and required-course logic**

Replace `generatePathways` signature with:

```swift
    public func generatePathways(
        for programID: String,
        concentrationID: String? = nil,
        workload: WorkloadPreference,
        transferCredits: [TransferCredit],
        starting start: SemesterIdentity = SemesterIdentity(year: Calendar.current.component(.year, from: Date()), term: .fall),
        requirementSelections: [String: [String]] = [:]
    ) throws -> [Pathway] {
        let program = try programForScheduling(programID, concentrationID: concentrationID)
        let completed = Set(transferCredits.flatMap(\.courseIDs))
        let required = requiredCourseIDs(for: program, completed: completed, requirementSelections: requirementSelections)
        guard !required.isEmpty else {
            return (1...3).map { index in
                Pathway(id: "path-\(index)", name: pathwayName(index), semesters: [])
            }
        }

        var pathways: [Pathway] = []
        let variants = [
            required,
            required.sorted { lhs, rhs in
                (catalog.coursesByID[lhs]?.credits ?? 0, lhs) > (catalog.coursesByID[rhs]?.credits ?? 0, rhs)
            },
            required.sorted()
        ]

        for (index, variant) in variants.enumerated() {
            let semesters = try buildSemesters(courseIDs: variant, completedAtStart: completed, workload: workload, starting: start)
            pathways.append(Pathway(id: "path-\(index + 1)", name: pathwayName(index + 1), semesters: semesters))
        }

        return pathways
    }
```

Replace `requiredCourseIDs` with:

```swift
    private func requiredCourseIDs(
        for program: Program,
        completed: Set<String>,
        requirementSelections: [String: [String]]
    ) -> [String] {
        let completedClusterTags = Set(completed.compactMap { TransferCreditMapper.genEdCreditClusterTag(for: $0) })
        var seen: Set<String> = []
        var result: [String] = []
        for category in program.requirements {
            let categorySatisfiedByCluster = completedClusterTags.contains(where: category.name.contains)
            for option in courseOptions(for: category, requirementSelections: requirementSelections) {
                if categorySatisfiedByCluster { continue }
                if option.contains(where: completed.contains) { continue }
                guard let pick = option.first else { continue }
                if seen.insert(pick).inserted {
                    result.append(pick)
                }
            }
        }
        return result
    }

    private func courseOptions(
        for category: RequirementCategory,
        requirementSelections: [String: [String]]
    ) -> [[String]] {
        guard let selected = requirementSelections[category.selectionKey],
              category.courseOptions.contains(selected)
        else {
            return category.courseOptions
        }
        return [selected]
    }
```

- [ ] **Step 5: Update `ProgressCalculator.progress` signature and category credits**

Replace `ProgressCalculator.progress` with:

```swift
    public func progress(
        programID: String,
        concentrationID: String? = nil,
        pathway: Pathway,
        transferCredits: [TransferCredit],
        requirementSelections: [String: [String]] = [:]
    ) throws -> GraduationProgress {
        guard let program = catalog.programsByID[programID] else {
            throw PlannerError.programNotFound(programID)
        }
        let effectiveProgram = try program.effectiveProgram(concentrationID: concentrationID)

        let completedCourseIDs = Set(pathway.semesters.flatMap(\.courseIDs)).union(transferCredits.flatMap(\.courseIDs))
        let coursesByID = catalog.coursesByID
        let categories = effectiveProgram.requirements.map { category in
            let completedCredits = courseOptions(for: category, requirementSelections: requirementSelections).reduce(0) { total, options in
                guard let completed = options.first(where: completedCourseIDs.contains),
                      let course = coursesByID[completed] else {
                    return total
                }
                return total + course.credits
            }
            return CategoryProgress(
                id: category.id,
                name: category.name,
                completedCredits: min(completedCredits, category.requiredCredits),
                requiredCredits: category.requiredCredits,
                verificationStatus: category.verificationStatus
            )
        }

        return GraduationProgress(categories: categories, projectedGraduation: pathway.projectedGraduation)
    }

    private func courseOptions(
        for category: RequirementCategory,
        requirementSelections: [String: [String]]
    ) -> [[String]] {
        guard let selected = requirementSelections[category.selectionKey],
              category.courseOptions.contains(selected)
        else {
            return category.courseOptions
        }
        return [selected]
    }
```

- [ ] **Step 6: Run core tests**

Run:

```bash
swift test --filter RequirementSelectionCoreTests
```

Expected: PASS.

- [ ] **Step 7: Run existing tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 8: Commit**

Run:

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/RequirementSelectionCoreTests.swift
git commit -m "feat: honor requirement choices in core planner"
```

## Task 2: Persist Requirement Choices In PlanStore

**Files:**
- Modify: `Sources/JMUCoursePlanner/Models/SavedStudentPlan.swift`
- Modify: `Sources/JMUCoursePlanner/Stores/PlanStore.swift`
- Create: `Tests/PlannerCoreTests/RequirementSelectionStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Create `Tests/PlannerCoreTests/RequirementSelectionStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import JMUCoursePlanner
@testable import PlannerCore

@Suite
@MainActor
struct RequirementSelectionStoreTests {
    @Test
    func savedStudentPlanDecodesMissingRequirementSelectionsAsEmpty() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Autosave",
          "programID": "cis-bba",
          "workload": "standard",
          "apScores": [],
          "transferCredits": [],
          "pathways": [],
          "overrides": [],
          "updatedAt": "2026-05-20T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let plan = try decoder.decode(SavedStudentPlan.self, from: Data(json.utf8))

        #expect(plan.requirementSelections.isEmpty)
    }

    @Test
    func selectingRequirementOptionPersistsChoiceAndClearsGeneratedPathways() {
        let store = PlanStore()
        store.catalog = requirementSelectionStoreCatalog()
        store.plan.programID = "cis-bba"
        store.plan.pathways = [
            Pathway(id: "path-1", name: "Old", semesters: [
                SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CIS-464"])
            ])
        ]
        store.plan.activePathwayID = "path-1"
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!

        store.selectRequirementOption(key: key, courseIDs: ["CIS-484"])

        #expect(store.plan.requirementSelections[key] == ["CIS-484"])
        #expect(store.plan.pathways.isEmpty)
        #expect(store.plan.activePathwayID == nil)
    }

    @Test
    func normalizedSelectionsUseRequirementSelectionKeyOnlyForCurrentProgram() {
        let store = PlanStore()
        store.catalog = requirementSelectionStoreCatalog()
        store.plan.programID = "cis-bba"
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!
        store.plan.requirementSelections = [
            key: ["CIS-484"],
            "major:other:no-concentration:cis-elective::CIS Elective": ["CIS-464"]
        ]

        let normalized = store.activeRequirementSelectionsByRequirementKey()

        #expect(normalized == [requirement.selectionKey: ["CIS-484"]])
    }

    @Test
    func validationRemovesSelectionsWhoseOptionNoLongerExists() {
        let store = PlanStore()
        store.catalog = requirementSelectionStoreCatalog()
        store.plan.programID = "cis-bba"
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!
        store.plan.requirementSelections = [key: ["CIS-999"]]

        store.validateRequirementSelections()

        #expect(store.plan.requirementSelections.isEmpty)
    }
}

private func requirementSelectionStoreCatalog() -> Catalog {
    let courses = [
        Course(id: "CIS-464", code: "CIS 464", title: "Information Security", credits: 3),
        Course(id: "CIS-484", code: "CIS 484", title: "Cyber Defense", credits: 3)
    ]
    let requirement = RequirementCategory(
        id: "cis-elective",
        name: "CIS Elective",
        requiredCredits: 3,
        courseOptions: [["CIS-464"], ["CIS-484"]]
    )
    let program = Program.fixture(id: "cis-bba", title: "Computer Information Systems", requirements: [requirement])
    return Catalog.fixture(courses: courses, program: program)
}
```

- [ ] **Step 2: Run failing store tests**

Run:

```bash
swift test --filter RequirementSelectionStoreTests
```

Expected: FAIL because `SavedStudentPlan.requirementSelections` and `PlanStore` helper methods do not exist.

- [ ] **Step 3: Add persisted selections to `SavedStudentPlan`**

In `Sources/JMUCoursePlanner/Models/SavedStudentPlan.swift`, add property:

```swift
    var requirementSelections: [String: [String]]
```

Update initializer signature and body:

```swift
        requirementSelections: [String: [String]] = [:],
```

```swift
        self.requirementSelections = requirementSelections
```

Update `CodingKeys`:

```swift
        case workload, apScores, transferCredits, pathways, activePathwayID, overrides, requirementSelections, updatedAt
```

In `init(from:)`, after `overrides` decode:

```swift
        self.requirementSelections = try container.decodeIfPresent([String: [String]].self, forKey: .requirementSelections) ?? [:]
```

In `encode(to:)`, after `overrides` encode:

```swift
        try container.encode(requirementSelections, forKey: .requirementSelections)
```

- [ ] **Step 4: Add selection helpers to `PlanStore`**

In `Sources/JMUCoursePlanner/Stores/PlanStore.swift`, after `completedCourseIDs`, add:

```swift
    func majorRequirementSelectionKey(for category: RequirementCategory) -> String? {
        guard let programID = plan.programID else { return nil }
        return requirementSelectionKey(
            scope: "major",
            programID: programID,
            concentrationID: plan.concentrationID,
            requirementKey: category.selectionKey
        )
    }

    func requirementSelectionKey(
        scope: String,
        programID: String,
        concentrationID: String?,
        requirementKey: String
    ) -> String {
        let concentration = concentrationID ?? "no-concentration"
        return "\(scope):\(programID):\(concentration):\(requirementKey)"
    }

    func selectedRequirementOption(for key: String, in category: RequirementCategory) -> [String]? {
        guard let selected = plan.requirementSelections[key],
              category.courseOptions.contains(selected)
        else {
            return nil
        }
        return selected
    }

    func selectableCourseOptions(in category: RequirementCategory) -> [[String]] {
        category.courseOptions.filter { !$0.isEmpty }
    }

    func canSelectRequirementOption(in category: RequirementCategory) -> Bool {
        selectableCourseOptions(in: category).count > 1
    }

    func selectRequirementOption(key: String, courseIDs: [String]?) {
        if let courseIDs {
            plan.requirementSelections[key] = courseIDs
        } else {
            plan.requirementSelections.removeValue(forKey: key)
        }
        plan.pathways = []
        plan.activePathwayID = nil
        autosave()
    }

    func activeRequirementSelectionsByRequirementKey() -> [String: [String]] {
        guard let effectiveActiveProgram else { return [:] }
        var result: [String: [String]] = [:]
        for category in effectiveActiveProgram.requirements {
            guard let storageKey = majorRequirementSelectionKey(for: category),
                  let selected = selectedRequirementOption(for: storageKey, in: category)
            else {
                continue
            }
            result[category.selectionKey] = selected
        }
        return result
    }

    func validateRequirementSelections() {
        guard let effectiveActiveProgram else {
            plan.requirementSelections = [:]
            return
        }
        let validMajorSelections = Set(effectiveActiveProgram.requirements.compactMap { category -> String? in
            guard let storageKey = majorRequirementSelectionKey(for: category),
                  selectedRequirementOption(for: storageKey, in: category) != nil
            else {
                return nil
            }
            return storageKey
        })
        plan.requirementSelections = plan.requirementSelections.filter { key, _ in
            validMajorSelections.contains(key)
        }
    }
```

- [ ] **Step 5: Update `progress` and schedule generation to pass normalized selections**

Replace `progress` computed property body with:

```swift
    var progress: GraduationProgress? {
        guard let catalog, let programID = plan.programID, let activePathway else { return nil }
        return try? ProgressCalculator(catalog: catalog).progress(
            programID: programID,
            concentrationID: plan.concentrationID,
            pathway: activePathway,
            transferCredits: plan.transferCredits,
            requirementSelections: activeRequirementSelectionsByRequirementKey()
        )
    }
```

In `generateSchedules()`, replace the `generatePathways` call with:

```swift
            plan.pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
                for: programID,
                concentrationID: plan.concentrationID,
                workload: plan.workload,
                transferCredits: plan.transferCredits,
                starting: SemesterIdentity(year: 2026, term: .fall),
                requirementSelections: activeRequirementSelectionsByRequirementKey()
            )
```

- [ ] **Step 6: Validate selections after catalog load and major/concentration changes**

In `load()`, after `validateSelectedConcentration()`, add:

```swift
                validateRequirementSelections()
```

In `selectProgram(_:)`, after concentration handling and before clearing pathways, add:

```swift
        validateRequirementSelections()
```

In `selectConcentration(id:)`, after concentration assignment and before clearing pathways, add:

```swift
        validateRequirementSelections()
```

- [ ] **Step 7: Run store tests**

Run:

```bash
swift test --filter RequirementSelectionStoreTests
```

Expected: PASS.

- [ ] **Step 8: Run all tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 9: Commit**

Run:

```bash
git add Sources/JMUCoursePlanner/Models/SavedStudentPlan.swift Sources/JMUCoursePlanner/Stores/PlanStore.swift Tests/PlannerCoreTests/RequirementSelectionStoreTests.swift
git commit -m "feat: persist requirement choices"
```

## Task 3: My Plan Requirement Picker UI

**Files:**
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift`

- [ ] **Step 1: Update requirement progress rows**

In `MyPlanView.categoryBreakdown`, replace the `ForEach(progress.categories)` row body with:

```swift
                        ForEach(progress.categories) { category in
                            let requirement = lookup[category.id]
                            requirementProgressRow(category: category, requirement: requirement)
                        }
```

Add this view helper below `categoryBreakdown`:

```swift
    @ViewBuilder
    private func requirementProgressRow(category: CategoryProgress, requirement: RequirementCategory?) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Button {
                store.scheduleCategoryFilter = category.id
                withAnimation(.easeOut(duration: 0.15)) {
                    store.selectedTab = .schedule
                }
            } label: {
                ProgressRail(
                    category: category,
                    hasCourseOptions: !(requirement?.courseOptions.isEmpty ?? true),
                    remainingCourseCodes: remainingCodes(for: requirement)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let requirement,
               let key = store.majorRequirementSelectionKey(for: requirement),
               store.canSelectRequirementOption(in: requirement) {
                requirementChoicePicker(requirement: requirement, key: key)
            }
        }
    }
```

- [ ] **Step 2: Add picker helper**

Add below `requirementProgressRow`:

```swift
    private func requirementChoicePicker(requirement: RequirementCategory, key: String) -> some View {
        Picker("Choice", selection: requirementChoiceBinding(requirement: requirement, key: key)) {
            Text("Catalog default").tag("")
            ForEach(store.selectableCourseOptions(in: requirement), id: \.self) { option in
                Text(optionLabel(option))
                    .tag(optionTag(option))
            }
        }
        .pickerStyle(.menu)
        .font(DesignTokens.Typography.caption)
        .tint(DesignTokens.Colors.brandPurple)
        .accessibilityLabel("\(requirement.name) choice")
    }

    private func requirementChoiceBinding(requirement: RequirementCategory, key: String) -> Binding<String> {
        Binding(
            get: {
                guard let selected = store.selectedRequirementOption(for: key, in: requirement) else {
                    return ""
                }
                return optionTag(selected)
            },
            set: { tag in
                guard !tag.isEmpty else {
                    store.selectRequirementOption(key: key, courseIDs: nil)
                    return
                }
                guard let option = store.selectableCourseOptions(in: requirement).first(where: { optionTag($0) == tag }) else {
                    return
                }
                store.selectRequirementOption(key: key, courseIDs: option)
            }
        )
    }

    private func optionTag(_ option: [String]) -> String {
        option.joined(separator: "|")
    }

    private func optionLabel(_ option: [String]) -> String {
        option.compactMap { courseID in
            catalog.coursesByID[courseID]?.code
        }.joined(separator: " / ")
    }
```

- [ ] **Step 3: Update remaining codes to use selected option**

Replace `remainingCodes(for:)` with:

```swift
    private func remainingCodes(for category: RequirementCategory?) -> [String] {
        guard let category else { return [] }
        guard let key = store.majorRequirementSelectionKey(for: category) else {
            return store.remainingCourses(in: category)
        }
        return store.remainingCourses(in: category, selectionKey: key)
    }
```

- [ ] **Step 4: Run build**

Run:

```bash
swift build
```

Expected: FAIL because `PlanStore.remainingCourses(in:selectionKey:)` does not exist yet.

- [ ] **Step 5: Commit after Task 4 adds store helper**

Do not commit this task alone. Task 4 adds the helper required by this UI and commits both UI and helper together.

## Task 4: Remaining Courses, Progress Tab, And Schedule Highlight

**Files:**
- Modify: `Sources/JMUCoursePlanner/Stores/PlanStore.swift`
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift`
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift`
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift`

- [ ] **Step 1: Add selected-option remaining-course helper**

In `PlanStore`, replace `remainingCourses(in category: RequirementCategory) -> [String]` with:

```swift
    func remainingCourses(in category: RequirementCategory, selectionKey: String? = nil) -> [String] {
        guard let catalog else { return [] }
        let completed = completedCourseIDs
        let courses = catalog.coursesByID
        let options: [[String]]
        if let selectionKey,
           let selected = selectedRequirementOption(for: selectionKey, in: category) {
            options = [selected]
        } else {
            options = category.courseOptions
        }

        return options.compactMap { option in
            guard !option.contains(where: completed.contains) else { return nil }
            guard let firstID = option.first, let course = courses[firstID] else { return nil }
            return course.code
        }
    }
```

- [ ] **Step 2: Update Graduation Progress remaining courses**

In `Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift`, replace calls to `store.remainingCourses(in: requirement)` with:

```swift
            if let key = store.majorRequirementSelectionKey(for: requirement) {
                return store.remainingCourses(in: requirement, selectionKey: key)
            }
            return store.remainingCourses(in: requirement)
```

For the fallback requirement path, use:

```swift
        if let key = store.majorRequirementSelectionKey(for: fallbackRequirement) {
            return store.remainingCourses(in: fallbackRequirement, selectionKey: key)
        }
        return store.remainingCourses(in: fallbackRequirement)
```

- [ ] **Step 3: Add course IDs helper for highlighted requirement**

In `PlanStore`, add after `remainingCourses`:

```swift
    func courseIDsForRequirementHighlight(in category: RequirementCategory) -> Set<String> {
        guard let key = majorRequirementSelectionKey(for: category),
              let selected = selectedRequirementOption(for: key, in: category)
        else {
            return Set(category.courseOptions.flatMap { $0 })
        }
        return Set(selected)
    }
```

- [ ] **Step 4: Update schedule highlight**

In `Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift`, replace the body of `isHighlighted(courseID:)` with:

```swift
    private func isHighlighted(courseID: String) -> Bool {
        guard let categoryID = store.scheduleCategoryFilter else { return false }
        guard let program = store.effectiveActiveProgram else { return false }
        guard let category = program.requirements.first(where: { $0.id == categoryID }) else { return false }
        return store.courseIDsForRequirementHighlight(in: category).contains(courseID)
    }
```

- [ ] **Step 5: Run build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 6: Run tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 7: Commit UI/helper changes**

Run:

```bash
git add Sources/JMUCoursePlanner/Stores/PlanStore.swift Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift
git commit -m "feat: add requirement choice picker"
```

## Task 5: Manual Verification

**Files:**
- Verify only; no planned edits.

- [ ] **Step 1: Build app**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 2: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 3: Launch app if local workflow supports it**

Run:

```bash
swift run JMUCoursePlanner
```

Expected: app launches or command reports the known SwiftPM macOS launch behavior for this target.

- [ ] **Step 4: Verify CIS cybersecurity flow manually**

Use the app:

1. Open setup.
2. Select `Computer Information Systems`.
3. Select cybersecurity concentration when prompted.
4. Generate pathways.
5. Go to My Plan.
6. Find a requirement with multiple parsed `courseOptions`.
7. Open `Choice` picker.
8. Pick a non-default option.
9. Confirm pathway list clears.
10. Click `Regenerate pathways`.
11. Confirm generated schedule contains selected option and does not schedule all alternate options for that requirement.

- [ ] **Step 5: Commit any final verification-only doc update**

If no files changed, skip commit. If a small doc note was added, run:

```bash
git add docs/superpowers/specs/2026-05-20-requirement-choice-picker-design.md
git commit -m "docs: clarify requirement choice verification"
```

## Self-Review

- Spec coverage:
  - Parsed-only option picker: Task 3 uses `courseOptions` only.
  - Persisted selections: Task 2 adds `SavedStudentPlan.requirementSelections`.
  - Scheduler honors selected option: Task 1 and Task 2 pass normalized selections into `ScheduleGenerator`.
  - Progress/remaining courses agree with scheduler: Task 1 and Task 4 update progress/remaining helpers.
  - Invalid selections cleared after catalog/program changes: Task 2 validation test and helper.
  - User can revert to catalog default: Task 3 picker includes `Catalog default`.
  - Prose-only requirements get no picker: Task 2 `selectableCourseOptions` filters empty options and Task 3 gates on `canSelectRequirementOption`.
- Placeholder scan:
  - No forbidden placeholder phrases or undefined helper names remain.
- Type consistency:
  - Storage key type is `[String: [String]]`.
  - Core normalized key is `RequirementCategory.selectionKey`.
  - App scoped key format is `scope:programID:concentrationID:requirementKey`.
  - `remainingCourses(in:selectionKey:)`, `majorRequirementSelectionKey(for:)`, and `activeRequirementSelectionsByRequirementKey()` names match across tasks.
