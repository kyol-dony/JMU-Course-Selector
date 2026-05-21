# Course Level Ramp Scheduling

**Status:** Approved design, awaiting implementation plan
**Date:** 2026-05-21
**Scope:** PlannerCore schedule generation and scheduler tests

## Problem

The scheduler currently respects prerequisites, semester availability, and credit load, but it does not prefer lower-level courses early in a plan. If several courses are ready at the same time, the generated pathway can place 300/400-level classes too early and leave 100/200-level classes for later terms, which feels unlike a normal academic progression.

## Goals

- Prefer 100/200-level courses in earlier semesters.
- Prefer 300/400-level courses in later semesters.
- Make class difficulty scale linearly across the generated pathway.
- Keep the rule soft: level preference should never override prerequisites, semester availability, transfer credit, or credit caps.
- Preserve existing three generated pathway variants.
- Keep behavior deterministic and testable.

## Non-Goals

- Do not add a UI setting for level ramp strength.
- Do not hard-block high-level courses from early semesters.
- Do not infer difficulty from title, department, credits, professor data, or Rate My Professors data.
- Do not reorder a completed/generated pathway after user edits it manually.

## Design

Add a course-level priority heuristic inside `ScheduleGenerator.buildSemesters(...)`.

The scheduler already loops term by term and considers courses that are still remaining. It should keep the existing hard gates:

1. Prerequisite expression must be satisfied.
2. Course must be available in the current term when availability is known.
3. Course must fit under the workload credit cap.

After those gates, the scheduler should prefer ready courses whose level best matches the semester's target level.

## Course Level

Course level is parsed from the numeric part of `Course.code`:

- `CS 149` -> `100`
- `CIS 221` -> `200`
- `COB 300A` -> `300`
- `CS 445` -> `400`

Implementation should use a small helper:

```swift
private func courseLevel(for courseID: String, placeholders: [String: PlaceholderSpec]) -> Int
```

Rules:

- Real catalog course: parse first three-digit number from `Course.code`.
- Return `(number / 100) * 100`.
- Placeholder course: use neutral `200`.
- Missing/unknown course: use neutral `200`.
- Clamp parsed result to `100...400` so odd catalog numbers do not dominate sorting.

## Target Level

Each semester gets an offset from the starting semester:

- first generated semester: `0`
- second generated semester: `1`
- third generated semester: `2`

Target level scales linearly from 100 to 400 across a typical eight-semester plan:

```swift
private func targetLevel(for semesterOffset: Int) -> Int
```

Recommended mapping:

- offset `0...1` -> near `100`
- offset `2...3` -> near `200`
- offset `4...5` -> near `300`
- offset `6+` -> near `400`

Implementation can compute this as:

```swift
let clampedOffset = min(max(semesterOffset, 0), 7)
let raw = 100.0 + (Double(clampedOffset) / 7.0) * 300.0
return Int((raw / 100.0).rounded()) * 100
```

This gives a simple linear ramp without needing program-specific degree length.

## Selection Sort

Inside each semester, collect ready candidates, then sort before packing them into the term.

Sort key:

1. Smaller absolute distance from target level first.
2. Lower course level first when distance ties.
3. Preserve current variant order when possible.
4. Course ID as final deterministic tiebreaker.

This keeps the heuristic soft. A 300-level course can still appear early if it is the only ready course, only offered that term, or needed to keep the plan moving.

## Interaction With Existing Variants

Existing variants remain:

- Balanced Path
- Major-First Path
- Flexible Path

Each variant still starts from its current `courseIDs` ordering. The level ramp only affects term-by-term candidate selection inside `buildSemesters(...)`.

Variant order still matters as a tie-breaker so each generated pathway can remain slightly different.

## Error Handling

If a course code cannot be parsed, treat it as neutral `200` rather than failing schedule generation.

If no course fits in a semester after hard gates and level sorting, keep existing empty-semester / best-effort behavior.

## Tests

Add focused scheduler tests:

- When 100/200/300/400-level courses are all available with no prereqs, earlier semesters contain lower-level courses first.
- When a 300-level course is only available early and lower-level alternatives are unavailable, scheduler still places the 300-level course.
- When a high-level course depends on a low-level prereq, the high-level course never appears before the prereq.
- Placeholder courses use neutral level and do not crash sorting.

## Acceptance Criteria

- `swift test --filter ScheduleGeneratorTests` passes.
- Full `swift test` passes.
- Generated plans remain deterministic.
- No code path clears generated pathways when this heuristic runs; it only affects future schedule generation.
