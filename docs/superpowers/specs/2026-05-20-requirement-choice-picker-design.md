# Requirement Choice Picker Design

## Goal

Students should be able to choose preferred courses for requirements that already expose parsed catalog options. The scheduler should honor those choices instead of always picking the first parsed option, while prose-only requirements remain advisor-needed.

## Decisions

- Choices are limited to parsed catalog options. No free-form course assignment in this feature.
- Store choices on the saved plan, not on the catalog.
- A choice applies to one effective requirement in the selected major/concentration/minor context.
- Changing a requirement choice clears generated pathways, because the plan must regenerate.
- Transfer credit can still satisfy a requirement and prevent duplicate scheduling.

## Architecture

Add a saved-plan map:

```swift
var requirementSelections: [String: [String]]
```

The key is a stable requirement scope plus requirement ID, such as:

- `major:<programID>:<concentrationID-or-none>:<requirementID>`
- `minor:<programID>:<concentrationID-or-none>:<requirementID>`

The value is the selected parsed option course IDs. Using `[String]` supports single-course choices, OR groups, and future multi-course option groups without changing the schema.

`PlanStore` owns selection updates and validation. PlannerCore receives the selection map and applies it while building required course IDs.

## Components

### PlannerCore

`ScheduleGenerator.generatePathways` gains an optional requirement-selection map. During `requiredCourseIDs`, each requirement category first checks whether it has a selected option. If the selected option still exists in `category.courseOptions`, the scheduler uses it instead of the default first option. If transfer credit already satisfies any alternate in that option, the scheduler skips it as already complete.

Invalid selections should not crash. If a saved selected option no longer matches parsed options, scheduler ignores it. `PlanStore` separately cleans invalid choices after catalog refresh.

### Plan Storage

`SavedStudentPlan` adds `requirementSelections` with default empty dictionary and Codable migration support. Existing saved plans decode as empty.

Changing major, concentration, minors, minor pathway, transfer credit, or requirement selections should clear generated pathways where existing pathways could become stale.

### Store

`PlanStore` provides:

- stable key builder for major/minor requirement selections
- `selectedOption(for:)`
- `selectRequirementOption(key:courseIDs:)`
- `clearRequirementSelection(key:)`
- validation that removes selections for requirements or options no longer present in the effective plan

`remainingCourses(in:)`, progress display helpers, and schedule generation should use the selected option when present so the UI and scheduler agree.

### UI

Show the picker in requirement-facing surfaces, starting with My Plan requirement progress. A requirement gets a picker when:

- `courseOptions.count > 1`, or
- one option contains multiple alternatives

Picker rows show parsed options using course code and title. Example:

- `MATH 205 - Applied Calculus`
- `MATH 235 - Calculus I`

For option groups, show alternatives joined with `or`.

No picker appears for requirements with empty `courseOptions`; those remain partial/advisor-needed. No picker appears for requirements already represented as a single fixed course option.

### Progress and Schedule

Progress should still count completion by category. A selected option narrows what the app lists as remaining and what the scheduler queues, but transfer credit or manually scheduled matching alternates still satisfy the requirement.

Schedule highlighting should continue to use effective requirement categories. If a category has a selected option, highlighting should prioritize selected option courses.

## Data Flow

1. User opens My Plan after selecting major/concentration.
2. App renders requirement progress.
3. For choice requirements, app shows picker from parsed options.
4. User selects one parsed option.
5. Store writes `requirementSelections[key] = selectedCourseIDs`.
6. Store clears generated pathways.
7. User regenerates plan.
8. Scheduler applies selected option while building required course list.
9. Generated schedule includes selected elective and excludes unselected parsed alternatives.

## Error Handling

If selected option no longer exists after catalog refresh, remove the selection and clear generated pathways.

If selected option contains courses missing from `catalog.coursesByID`, ignore missing course IDs and surface existing partial-verification status; do not fail the whole schedule.

If all parsed options for a requirement become unavailable or empty, remove the picker and leave the requirement partial/advisor-needed.

## Testing

- Scheduler test: selected option is scheduled instead of first parsed option.
- Scheduler test: unselected alternatives are excluded.
- Scheduler test: transfer credit for selected option prevents duplicate scheduling.
- Store test: selecting a requirement option persists map entry and clears pathways.
- Store test: invalid requirement selection is removed after catalog/effective-plan validation.
- UI/store test: prose-only requirement has no selectable options.
- Progress/remaining test: remaining courses reflect selected option.

## Non-Goals

- No manual assignment from the full catalog.
- No custom course entry.
- No advisor approval workflow.
- No live section/time selection.
- No automatic ranking of electives by difficulty, professor, or availability.

## Documentation Updates

Update `LIMITATIONS.md` during implementation:

- Requirement choices are limited to parsed catalog options.
- Prose-only requirements still require advisor review.
- Generated pathways must be regenerated after changing a requirement choice.
