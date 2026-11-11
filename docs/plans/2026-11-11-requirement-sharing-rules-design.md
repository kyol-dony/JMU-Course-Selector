# Requirement sharing rules and shared allocation — design

Date: 2026-11-11. Status: approved. Relates to PLAN.md findings B2 and B8 and work package B ("apply explicit rules when coursework satisfies multiple requirements").

## Problem

The app knows which courses qualify for each requirement, but has no general rule for which requirements may share the same course. A 3-credit course earns 3 credits once. It may satisfy two requirements only where the catalog permits, and the engine currently assumes it always may.

Example: a B.A. Art student completes 18 credits of Studio Art Electives, including two upper-level Painting courses (6 credits). The same two courses also fill Studio Art Emphasis. Both rows show as satisfied with 18 distinct credits, though the catalog requires 24.

The result is false requirement completion even when total degree hours are correct. Open electives added to reach 120 or 143 credits do not repair missing studio coursework.

This is a confirmed architectural gap with three explicit Art rules affected. It is not yet evidence that every generated Art plan underfills, or that other majors are wrong.

## Rules in scope

| Relationship | Required behavior |
|---|---|
| B.A./B.S. Studio Art Electives ↔ Studio Art Emphasis | 18 + 6 distinct credits; no sharing |
| B.F.A. studio concentration ↔ Art and Art-Related Electives | Concentration courses cannot count toward the 15-credit electives |
| B.F.A. Art Education ↔ Art and Art-Related Electives | 15 of the 42 Art Education credits count toward electives; the other 27 are additional |
| Major ↔ Gen Ed, second major, minor | Sharing stays allowed, as today |

These rules come from the catalog fixtures captured in the branch. Live catalog pages currently block automated retrieval, so the rules are not verified against the live site.

## Decisions

1. **No rule means free sharing, silently.** When two rows of the same program list a course and no rule covers the pair, the course counts for both, as today. Only explicit rules change behavior. No "needs review" warning is added.
2. **One shared allocator**, used by generation, progress, course menus, regeneration, transfer credit, and validation. Per-call-site rule checks were rejected because four copies would drift.
3. **Deterministic greedy allocation**, narrower menus claiming first. Optimal matching (max-flow) was rejected as unnecessary for the Art rules; the allocator's interface allows replacing the algorithm later.
4. **Rules are attached in code by `ArtConcentrationPolicy`** for now, matching how that type already repairs Art relationships that live in catalog prose. A rule data file waits for the broader audit.
5. **Allocation is computed, not chosen.** The student does not pick which requirement a course serves, and no allocation is stored in saved plans.

## Current behavior

- `ArtConcentrationPolicy` builds the B.F.A. elective pool and the B.A./B.S. emphasis options. The B.F.A. exclusion exists only as text in the row's `note`.
- Progress (`progressRows` in `PlannerCore.swift`) gives each independent category a fresh `consumed` set. Consumption is shared only between the parts of one option requirement.
- Generation (`appendSelectableElectivePlaceholders`) counts any completed or planned course toward any pool that lists it, and adds it to `reusedCredits`.
- Existing protections stay: one course cannot fill two slots of one ordinary category; option parts share consumption; pool resolution excludes courses a program requires outright.
- `GenEdAssignment` is an existing, narrower allocator for Gen Ed and degree requirements. It is not changed.

## Design

### Rule model

A new `RequirementSharingRule` value, held in a list on `Program`:

- two **requirement groups**. A group is either a set of category IDs, or "the rows of the selected concentration" (optionally narrowed to the rows that originate from a named concentration, for the combined "studio + Art Education" concentrations);
- `maxSharedCredits`: the most credits that may count toward both groups. `0` means exclusive.

The three Art rules:

| Program | Group A | Group B | `maxSharedCredits` |
|---|---|---|---|
| art-ba, art-bs | Studio Art Electives | Studio Art Emphasis | 0 |
| art-bfa | studio concentration rows | Art and Art-Related Electives | 0 |
| art-bfa (combined concentrations) | Art Education rows | Art and Art-Related Electives | 15 |

Rules apply within one program. Sharing across programs (major with Gen Ed, minor, second major) is not affected.

### Allocator

A pure function in PlannerCore, in its own file.

- **Input:** the active programs with options and concentrations already chosen; earned, transfer, and planned courses with their credits; resolved placeholders.
- **Output:** for each requirement row, the courses and credits that count there.

Behavior:

- Rows are processed in today's order: required rows, then choice rows, then elective pools; within those, narrower menus first. Studio Art Emphasis therefore claims its Painting courses before the Studio Art Electives pool.
- A row may claim a course unless a rule links the row's group to a group that already holds the course and the claim would push the shared credits above `maxSharedCredits`.
- Granularity is the whole course. A course that would cross the cap does not share.
- Within one row, and between the parts of one option requirement, a course counts once, as today. The allocator takes over this bookkeeping from `consumedByRequirement`.
- With no rules, the output equals today's counting.

### Consumers

- **Progress:** each row reads its completed credits from the allocation instead of counting on its own.
- **Generation:** fulfilled and reused credits for a row come from the allocation. A course blocked by a rule leaves a placeholder slot to fill.
- **Course menus:** a course already in the plan that cannot count for this row is left out of the row's alternates.
- **Regeneration and transfer credit:** the same function with the same inputs, so retained and transferred courses obey the same rules.
- **Validation:** a check that does not reuse the allocator: for each rule, the distinct credits across both groups must be at least the sum of both groups' required credits minus `maxSharedCredits`.

### Errors

A rule that refers to a row that does not exist is ignored at runtime and reported as a catalog validation issue. For bundled catalog data this fails the test suite. Nothing crashes.

## Tests

- **B.A.:** 18 elective credits including two upper-level Painting courses → Emphasis met, Electives 12 of 18. Both rows are met only with 24 distinct credits.
- **B.F.A.:** a studio concentration course never counts toward the 15-credit electives.
- **Art Education:** exactly 15 of the 42 credits count toward electives; adding a sixth shared course changes nothing.
- **Cross-program:** major ↔ Gen Ed, minor, and second-major sharing give the same results as before.
- **No-rule programs:** the allocator reproduces current progress numbers across the whole-catalog suite.
- **Generation:** a generated B.A., B.F.A., and B.F.A. + Art Education pathway each pass the validation check.
- **Bad rule:** a rule naming a missing row is reported and ignored.

## Out of scope

- Exclusive-by-default behavior within a program.
- Flagging un-ruled overlaps for review.
- Letting the student choose which requirement a course serves.
- A data file for authoring rules.
- Optimal matching.
- Auditing other programs for "additional", "excluding courses used for", "distinct credits", or limited-overlap wording. That audit follows this work and supplies further rules.

## Risks and open points

- Adding a field to `Program` may change cached catalog data. Check during planning whether `cacheSchemaVersion` must be bumped; if so the version metadata carries the new `+catalog.N` under `docs/RELEASING.md`.
- Release impact is likely *patch* (corrects incorrect output), to be confirmed at integration.
- Greedy allocation can misassign when several rules interlock. The Art rules do not; revisit if the audit finds such a case.
- The Art rules are unverified against live catalog pages.
