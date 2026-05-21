# Requirement Choice Picker Design

## Goal

Students should be able to choose preferred courses for requirements that already expose parsed catalog options. The scheduler should honor those choices instead of always picking the first parsed option, while prose-only requirements remain advisor-needed.

## Decisions

- Choices are limited to parsed catalog options. No free-form course assignment in this feature.
- Store choices on the saved plan, not on the catalog.
- A choice applies to one effective requirement in the selected major/concentration/minor context.
- Changing a requirement choice must not clear generated pathways or hide existing schedule/progress/catalog views. The choice is staged and applied only when the student clicks regenerate.
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

`PlanStore` owns selection updates and validation. PlannerCore receives the committed selection map during pathway generation and applies it while building required course IDs.

## Components

### PlannerCore

`ScheduleGenerator.generatePathways` gains an optional requirement-selection map. During `requiredCourseIDs`, each requirement category first checks whether it has a selected option. If the selected option still exists in `category.courseOptions`, the scheduler uses it instead of the default first option. If transfer credit already satisfies any alternate in that option, the scheduler skips it as already complete.

Invalid selections should not crash. If a saved selected option no longer matches parsed options, scheduler ignores it. `PlanStore` separately cleans invalid choices after catalog refresh.

### Plan Storage

`SavedStudentPlan` adds `requirementSelections` with default empty dictionary and Codable migration support. Existing saved plans decode as empty.

Changing major, concentration, minors, minor pathway, or transfer credit should clear generated pathways where existing pathways could become stale. Requirement selections should not clear generated pathways; they remain pending until the student regenerates.

### Store

`PlanStore` provides:

- stable key builder for major/minor requirement selections
- `selectedOption(for:)`
- `selectRequirementOption(key:courseIDs:)`
- `clearRequirementSelection(key:)`
- validation that removes selections for requirements or options no longer present in the effective plan

My Plan can show pending selected options, but Schedule and Progress must continue to reflect the currently generated pathway until the student regenerates. Schedule generation uses the pending/committed selection map when regeneration is explicitly requested.

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

Progress should still count completion by category based on the currently generated pathway. Pending selected options should not change Progress or Schedule before regeneration. During regeneration, a selected option narrows what the scheduler queues, but transfer credit or manually scheduled matching alternates still satisfy the requirement.

Schedule highlighting should continue to use effective requirement categories from the current generated pathway. Pending selections should not change Schedule highlighting before regeneration.

## Data Flow

1. User opens My Plan after selecting major/concentration.
2. App renders requirement progress.
3. For choice requirements, app shows picker from parsed options.
4. User selects one parsed option.
5. Store stages the selected course IDs without mutating generated pathways.
6. Schedule, Progress, and Catalog remain viewable and unchanged.
7. User can stage additional requirement choices.
8. User clicks `Regenerate pathways`.
9. Store commits staged choices and scheduler applies selected options while building the required course list.
10. Generated schedule includes selected electives and excludes unselected parsed alternatives.

## Error Handling

If selected option no longer exists after catalog refresh, remove the selection. Do not clear existing generated pathways solely because a requirement selection changed.

If selected option contains courses missing from `catalog.coursesByID`, ignore missing course IDs and surface existing partial-verification status; do not fail the whole schedule.

If all parsed options for a requirement become unavailable or empty, remove the picker and leave the requirement partial/advisor-needed.

## Testing

- Scheduler test: selected option is scheduled instead of first parsed option.
- Scheduler test: unselected alternatives are excluded.
- Scheduler test: transfer credit for selected option prevents duplicate scheduling.
- Store test: selecting a requirement option stages a pending choice and leaves pathways unchanged.
- Store test: regenerating commits staged choices and applies them to the generated pathway.
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
- Requirement choices are staged until the student explicitly regenerates pathways.
