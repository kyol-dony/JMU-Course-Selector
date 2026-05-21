# Curated Prerequisite/Corequisite Overlay

**Status:** Approved design, awaiting implementation plan
**Date:** 2026-05-21
**Scope:** PlannerCore data model, catalog loading, schedule generation, conflict warnings, validation tests, and agent curation workflow

## Problem

JMU prerequisite/corequisite language is too inconsistent for a parser-only solution. Current parsing handles common boolean course references, but catalog prose mixes grade rules, major-specific branches, placement scores, standing requirements, and informal exceptions. Treating that prose as a source of hard scheduling truth creates false positives and false negatives.

The app still needs prereq/coreq-aware scheduling. The source of truth should become a curated rule overlay for courses the app actually schedules. The parser remains useful as a fallback and as a bootstrap aid, but curated data wins.

## Goals

- Add a separate curated prereq/coreq overlay file, `Data/prereq_coreq_overrides.json`.
- Scope curation to schedulable courses: courses that appear in parsed major, concentration, minor, or gen-ed requirement options and therefore can appear in generated pathways.
- Let agents write curated rules directly after reading catalog pages and applying discretionary reasoning.
- Let agents manually enter prereq/coreq rules when official/source-backed information strongly implies a course requirement, even if the catalog prose is not written as a clean prerequisite sentence.
- Preserve source evidence for every curated rule with `sourceURL`, `sourceText`, and optional `notes`.
- Use curated rules first during schedule generation and conflict detection.
- Fall back to parser output when no curated rule exists, marking that rule `parsed`/low-confidence in warnings and course details.
- Keep schedule generation best-effort: create schedules, then surface warnings when requirements are unmet or low-confidence.

## Non-Goals

- Build a manual review UI in the app.
- Curate every JMU course in the full catalog.
- Enforce grade thresholds, GPA rules, class standing, placement scores, or admission-to-major gates as scheduling blockers.
- Remove the existing parser. It remains a fallback and bootstrap tool.
- Make unsupported prose invisible. Unknown but relevant prose should surface as advisory notes when available.

## Data Model

Create `Data/prereq_coreq_overrides.json` as a compact JSON document:

```json
{
  "schemaVersion": 1,
  "rules": [
    {
      "courseID": "CS240",
      "prerequisiteExpr": {
        "kind": "course",
        "value": "CS159"
      },
      "corequisiteExpr": {
        "kind": "empty"
      },
      "confidence": "curated",
      "basis": "explicit",
      "sourceURL": "https://catalog.jmu.edu/preview_course.php?...",
      "sourceText": "Prerequisite: CS 159.",
      "notes": "Catalog prose normalized to course-only prerequisite."
    }
  ]
}
```

`confidence` values:

- `curated`: agent-created and source-backed. App may schedule from it as the trusted rule.
- `parsed`: generated from raw catalog prose by the parser. App may use it, but warnings and details should indicate catalog verification is recommended.
- `none`: no known rule. The app should not block scheduling for missing rule data.

Rules use the existing `PrereqExpr` representation:

- `.empty`
- `.course(id)`
- `.unknown(text)`
- `.all([PrereqExpr])`
- `.any([PrereqExpr])`

Course IDs in overlay must match catalog course IDs exactly.

Curated rules also include `basis`:

- `explicit`: source text directly states the course is a prereq/coreq.
- `inferred`: source text, program sequencing, or official catalog context strongly supports treating the course as a prereq/coreq even though it is not expressed in standard prereq/coreq prose.

`basis: "inferred"` requires `notes` explaining the reasoning. Inferred rules must still cite source-backed evidence with `sourceURL` and `sourceText`; agents should not infer requirements from convenience, common student behavior, or unsupported curriculum opinion.

## Runtime Priority

When the app needs prereq/coreq information for a course:

1. Use curated overlay rule when present.
2. Else parse `rawPrerequisiteText` and use parser output with confidence `parsed`.
3. Else use legacy flat `Course.prerequisites` as an `.all` expression with confidence `parsed`.
4. Else use `.empty` with confidence `none`.

This priority applies in:

- `ScheduleGenerator`
- `ConflictDetector`
- `CourseDetailSheet`
- any future export/advising summary that displays prereq/coreq information

## Agent Curation Workflow

Agents should curate only schedulable courses. A course is schedulable if it appears in:

- active catalog program requirements
- concentration requirements
- minor requirements
- general education injected requirement options
- generated pathway placeholders or resolved pathway choices

For each course, agent reads the JMU catalog course page and writes a normalized rule:

- Convert explicit course prereqs/coreqs into `PrereqExpr`.
- Manually enter inferred prereqs/coreqs when official source evidence is strong enough to justify the rule.
- Preserve `and` as `.all`.
- Preserve `or`, `one of the following`, and equivalent choice phrasing as `.any`.
- Ignore grade threshold language for scheduling, but note it in `notes`.
- Ignore class standing, permission, placement score, GPA, or admission gates as hard scheduling blockers unless they also name required courses.
- For major-specific branches, include only the branch matching the active major when a curated rule is scoped later. For the first overlay version, prefer non-major/default branches unless a course is only used by that named major.
- Put non-course requirements that may matter into `notes`, not into blocking expressions, unless they cannot be separated from course requirements.
- If evidence is weak, conflicting, or based only on typical ordering, do not create a blocking inferred rule. Keep it as a note or leave parser fallback in place.

Every curated entry must include:

- `courseID`
- `prerequisiteExpr`
- `corequisiteExpr`
- `confidence: "curated"`
- `basis`
- `sourceURL`
- `sourceText`

`notes` is optional for explicit rules, but required when `basis` is `inferred` or when agent drops grade, standing, placement, permission, or major-specific prose.

## App Components

Add PlannerCore types:

- `PrereqRuleOverlay`
- `PrereqRule`
- `PrereqRuleConfidence`
- `ResolvedPrereqRule`
- `PrereqRuleResolver`

`PrereqRuleResolver` owns runtime priority and exposes:

```swift
func rule(for course: Course, activeProgramTitle: String?) -> ResolvedPrereqRule
```

`ResolvedPrereqRule` includes:

- `prerequisiteExpr`
- `corequisiteExpr`
- `confidence`
- `sourceText`
- `sourceURL`
- `notes`

The resolver should be pure and testable. It depends only on `Catalog`, overlay rules, and active program title.

`CatalogRepository` loads bundled `prereq_coreq_overrides.json` beside `catalog_seed.json`. If missing or invalid, the app should continue with parser fallback and surface a non-fatal status message.

## Scheduling Behavior

`ScheduleGenerator` uses `PrereqRuleResolver` instead of reading `Course.prerequisites` directly.

Behavior:

- `curated` rules are used for placement ordering.
- `parsed` rules are used for best-effort ordering but should not cause a hard failure.
- `none` rules impose no prereq/coreq scheduling constraint.
- Coreqs can be placed in the same term when both courses are required.
- If a curated/coreq target is not in the required course pool, the schedule should still generate and warnings should show the missing coreq.
- Existing best-effort fallback remains: unplaceable courses are still placed, and warnings explain unmet requirements.

## Warnings And Details

`ConflictDetector` uses the same resolver.

Warnings:

- Curated unmet prereq: show normal missing requirement copy.
- Parsed unmet prereq: show normal copy plus “Parsed from catalog text; verify before registering.”
- Unknown prose in notes: append concise “Catalog note: …” if it affects registration but was not enforced.
- Missing coreq: show “Take alongside or before this course: …”

`CourseDetailSheet` shows:

- Prereqs
- Coreqs
- Confidence label: `Curated` or `Parsed from catalog`
- Source text
- Notes

Do not make source text the dominant UI. It is supporting evidence.

## Validation And Tests

Add tests that verify:

- Overlay JSON decodes.
- Every overlay `courseID` exists in catalog.
- Every `.course(id)` leaf in overlay exists in catalog.
- Every curated rule has `sourceURL` and `sourceText`.
- Every curated rule has `basis`.
- Every inferred rule has non-empty `notes`.
- No duplicate rules for the same `courseID`.
- Every schedulable course has either a curated rule or parser fallback coverage.
- Overlay wins over parser when both exist.
- Scheduler uses curated `.any` rules correctly.
- ConflictDetector uses curated major/default rules consistently.
- Missing/invalid overlay is non-fatal.

Add a script:

```bash
swift script/validate_prereq_overlay.swift
```

The script should report:

- total curated rules
- total schedulable courses
- coverage percentage
- missing curated rules
- invalid referenced course IDs

## Migration

Initial implementation ships with a small overlay covering high-risk/high-frequency schedulable courses:

- CS core
- CIS core
- COB core
- common math/stat courses
- common lab/coreq pairs in gen ed science

The overlay can grow incrementally. Parser fallback keeps the app usable while coverage increases.

Existing generated schedules remain valid as saved plans. Warnings may change after overlay coverage improves.

## Open Risk

Agent-authored rules can still be wrong, especially inferred rules. Mitigation is source-backed entries, required notes for inferred rules, validation tests, and focused coverage on schedulable courses rather than all catalog courses.
