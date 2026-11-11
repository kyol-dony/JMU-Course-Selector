# Psychology and Art prose-requirement audit — 2026-11-11

## Scope and evidence

Captured 2026–2027 official catalog pages:

- `Tests/PlannerCoreTests/_live_psyc_bs.html`, source: <https://catalog.jmu.edu/programs/psychology-bs/>
- `Tests/PlannerCoreTests/_live_art_ba.html`, source: <https://catalog.jmu.edu/programs/art-ba/>
- `Tests/PlannerCoreTests/_live_art_bfa.html`, source: <https://catalog.jmu.edu/programs/art-bfa/>

Relevant catalog statements:

- Psychology: “Choose three credit hours of psychology electives.” No prefix, level, exclusions, or fixed list is stated.
- B.F.A. Art and Art-Related Electives: 15 credits may come from art, graphic design, architectural design, art education, industrial design, independent study, internships, and study-abroad studio coursework; studio-concentration courses cannot count again.
- B.F.A. Art Education: students complete two concentrations — one studio area plus Art Education — and the full program totals 143 credits.
- B.A. Studio Art Emphasis: six credits of 300–400-level ART coursework must stay within one studio area.

## Implemented mapping

### Psychology Electives

`PsychologyCoursework` converts the prose row into one 3-credit `CourseworkApproval` obligation. Generation reserves one pending slot. No ordinary PSYC course, transfer course, placeholder picker, or prerequisite search can satisfy it without future approval evidence. Cached catalog snapshots receive the same overlay.

### B.F.A. Art and Art-Related Electives

Five 3-credit slots use current catalog subject pools for `ART`, `GRPH`, `ARCD`, `ARED`, and `INDU`. Pool resolution uses full catalog course inventory and excludes courses required outright elsewhere. Scheduler deduplication prevents one physical course from appearing twice. Catalog prohibition against reusing studio-concentration coursework remains visible in requirement note.

### B.F.A. Art Education

Standalone Art Education is removed from B.F.A. choices. Seven valid studio choices remain, plus seven composed choices such as `Painting + Art Education`. Each composed choice carries studio and Art Education requirements and a reviewed 143-credit degree minimum.

### Studio Art Emphasis

Generic “any upper-level ART” slots become one explicit option per studio area. Each option uses area membership from B.F.A. concentration course lists and requires two slots / six credits from that one area. Option selection prevents mixing areas.

## Limits

- Psychology approval is intentionally unresolved. Catalog text cannot support an automatic course list.
- Art-related independent study, internship, and study-abroad eligibility may still require departmental approval even when a course appears under one of the five subject prefixes.
- 15 Art Education credits may overlap B.F.A. art-related electives. Current generator deduplicates scheduled courses and reaches the reviewed 143-credit minimum; full requirement-allocation evidence remains future manifest/validator work.

## Verification

- `ArtProgramParsingTests`: 11 passed.
- `PsychologyCourseworkTests`: 1 passed.
- `PlaceholderPrerequisiteAnalyzerTests`: 14 passed.
- `PrereqRuleOverlayTests`: 7 passed.
- Real cache, `psychology-bs + honors-interdisciplinary-studies-minor`: 120 credits, 8 terms, no dropped program, Psychology pending slot retained.
- Real cache, `art-bfa[painting-art-education]`: 143 credits, both concentration requirement sets scheduled.
- Real cache, `art-ba[art-education]`: 120 credits; Studio Art Emphasis option model participates in generation.
- Full real-cache Psychology/Art/Honors stack matrix passed in 68.5 seconds with no missing prerequisite/corequisite failure.
- Full suite: 681 tests in 92 suites passed; two pre-existing catalog-correctness known issues remain (`_live_psyc.html` minor-hour bound and mislabeled `_live_nursing.html` program-hour bound).

## Additional blocker fixed during matrix audit

The full stack matrix exposed an existing Computer Science + Psychology B.A. failure. Concrete prerequisite courses had no urgency, and a discrete-math placeholder could be seated before its pending concrete prerequisite. `PlaceholderPrerequisiteAnalyzer` now prioritizes pending concrete providers and delays a slot when one of its eligible choices needs another pending concrete course.

CS 240 also states `MATH 231 or equivalent`; the Computer Science B.S. catalog footnote identifies `MATH 235` as the one-course calculus alternative. Bundled prerequisite overlay now records `MATH 231` or `MATH 235` for that clause. Resulting stack schedules CS 149, CS 159, discrete mathematics, CS 240/261, then CS 327/361/430 in prerequisite order.
