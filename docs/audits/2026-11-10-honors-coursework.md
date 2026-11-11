# Honors Courses: prose-only credit requirement

Scope: the 12-credit Honors Courses category in the 2026–2027 Honors
Interdisciplinary Studies minor. The captured current catalog fixture
`Tests/PlannerCoreTests/_live_honors.html` states the requirement in prose,
without an enumerated course menu.

## Evidence

- [JMU Honors academics](https://www.jmu.edu/honors/current-students/academics.shtml)
  describes the 19-hour core and permits Honors coursework to also meet
  General Education, major, or other minor requirements.
- [Teaching for Honors](https://www.jmu.edu/honors/faculty/teaching-for-honors.shtml)
  identifies HON 200 and HON 300 interdisciplinary seminars, Honors sections
  of General Education, and Honors sections of departmental courses. Honors
  sections use the same course numbers as ordinary sections and an H
  designation on transcripts. A bare catalog course ID cannot establish
  section-level Honors eligibility.
- [Honors advising](https://www.jmu.edu/honors/current-students/advising.shtml)
  directs students to the catalog and Honors advisors for curriculum planning
  and Honors options.

The current catalog URL returned a JavaScript/bot challenge during research.
The current captured fixture and the user's screenshot supply the exact
12-credit obligation; the live Honors pages supply its interpretation.
Older advising forms are not treated as 2026–2027 authority.

## Implementation

An explicit, persisted approval obligation retains 12 credits in progress and
generates four provisional three-credit reservations. These are planning
budgets, not a rule that exactly four courses must be taken. The requirement
shows course-type examples and official links in Catalog. Approval tasks have
no unrestricted course picker, cannot resolve through ordinary course
selection, and cannot conditionally supply prerequisites. A cache overlay
applies the fix to existing Honors snapshots without a network refresh.

Progress stays at zero confirmed credits for this obligation. These changes
do not invent evidence or implement advisor sign-off. Section/option evidence
and within-minor allocation remain necessary before automated fulfillment or
overlap can be established. Existing saved pathways need regeneration to gain
the new reservations. Provisional reserved hours may overstate additional
coursework until overlap is reviewed.

## Verification

Honors tests cover parsing, cached-data overlay, all three pathway strategies,
the twelve-credit progress denominator, preservation through regeneration,
Codable persistence, blocked ordinary-course resolution, and prerequisite
ineligibility. Existing audit-worktree edits are preserved separately.

Results: standard suite passed 673 tests in 91 Swift Testing suites with two
pre-existing historical known issues. A real cached Psychology B.S. + Honors
stack generated eight semesters and 120 projected credits, retained all four
Honors Courses reservations, and showed this category as 0/12 rather than
omitting it. No prerequisite or corequisite failure was reported by the audit.
