# Major Concentrations Design

## Goal

Majors with concentrations should behave as one parent major plus one required concentration choice. The planner must schedule shared major requirements and only the selected concentration requirements, not every concentration listed under the major.

## Decisions

- Keep the parent major as the selected `Program`.
- Store the selected concentration separately as `concentrationID` on the saved plan.
- Require a concentration before plan generation when the selected major has concentrations.
- Split concentration requirements during catalog parsing so parent major requirements contain only shared core requirements.
- Do not create synthetic top-level programs for concentrations.

## Architecture

`PlannerCore.Program` already has `concentrations: [Concentration]`, so the feature should use that model instead of inventing parallel program records.

The catalog HTML parser will return parent requirement categories and concentration requirement groups separately. For JMU Acalog-style pages, the split starts at a `Concentrations` heading. Each course-bearing heading whose title ends in `Concentration` becomes a `Concentration`; umbrella headings without course rows are skipped. Parent `Program.requirements` receives only requirement blocks before the concentration section, plus GenEd requirements for majors.

`SavedStudentPlan` gains optional `concentrationID`. Existing saved plans decode with `nil`. `PlanStore` owns selection methods for both program and concentration, clears invalid concentration choices when the major changes, and exposes whether setup can continue.

Planner calculations will use effective requirements:

- major without concentrations: `program.requirements`
- major with selected concentration: `program.requirements + selectedConcentration.requirements`
- major with missing concentration: invalid setup state; no generated schedule

## Components

### Parser

`JMUHTMLCatalogParser.parseProgramRequirements` should return a richer result that includes:

- shared parent requirement categories
- concentration records with IDs, names, requirements, and verification status

The parser should not include concentration-specific categories in the parent requirement list. This is the core fix for the false all-concentrations assumption.

### Repository

`CatalogRepository.refreshCatalogFromHTML` should pass parsed concentrations into `Program`. The catalog cache schema should bump because cached catalogs produced by older versions have flattened concentration requirements in parent majors.

### Plan Storage

`SavedStudentPlan` should add:

```swift
public var concentrationID: String?
```

The field is optional for backward compatibility. Selecting a different major clears `concentrationID`. Selecting the same major preserves it only if the concentration still exists.

### Setup UI

`SetupStepMajor` should keep the current major selection list. When the selected major has concentrations, show a required dropdown directly under that selected major row.

The dropdown should:

- show a placeholder until selected
- list the major's concentrations by display name
- call `PlanStore.selectConcentration(_:)`
- visually mark the choice as required

The setup flow should block progression when a concentration-bearing major has no selected concentration.

### Planner Flow

Any code that reads `activeProgram.requirements` for requirement satisfaction or schedule generation should instead read effective requirements from `PlanStore` or a small helper in `PlannerCore`. This keeps the rule centralized and prevents future UI/progress screens from drifting.

## Data Flow

1. Catalog refresh parses a major page.
2. Parser splits shared requirements from concentration requirements.
3. Repository saves one `Program` with `concentrations`.
4. User selects a major in setup.
5. If the major has concentrations, setup shows a required dropdown.
6. User selects one concentration.
7. Saved plan stores `programID` and `concentrationID`.
8. Scheduler uses shared major requirements plus selected concentration requirements.
9. Progress views use the same effective requirement list.

## Error Handling

If a saved plan references a concentration that no longer exists after catalog refresh, the store should clear `concentrationID` and treat setup as incomplete until the user selects a current concentration.

If a parser sees a `Concentrations` section but cannot confidently create any course-bearing concentrations, it should leave the page as shared requirements and mark the program with the existing partial-verification/source-note behavior. It should not silently drop course rows.

If schedule generation is triggered without a required concentration, generation should fail early with a user-facing validation message instead of producing a misleading plan.

## Testing

- Parser test: a Physics-style page with `Concentrations` splits parent requirements from `Applied Physics Concentration` requirements.
- Parser test: parent requirements do not contain sibling concentration course categories.
- Store test: selecting a concentration stores `concentrationID`.
- Store test: changing majors clears invalid `concentrationID`.
- Planner test: effective requirements include selected concentration requirements.
- Planner test: effective requirements exclude unselected sibling concentration requirements.
- Setup validation test: concentration-bearing major cannot proceed without concentration.

## Non-Goals

- No synthetic top-level concentration programs.
- No support for selecting multiple concentrations at once.
- No attempt to infer unofficial concentrations from prose-only pages.
- No redesign of the full setup flow beyond the required dropdown.
- No Rate My Professors or course-description changes in this feature.

## Documentation Updates

Update `LIMITATIONS.md` during implementation:

- Concentrations are parsed into selectable tracks when the catalog page has course-bearing concentration sections.
- Majors with concentrations require concentration selection during setup.
- Pages whose concentration content cannot be safely split remain partially verified instead of dropping requirements.
