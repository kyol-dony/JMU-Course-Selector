# Catalog correctness audit — 2026-10-16

## Scope and evidence

Offline audit of seven captured program pages, every parsed concentration, three pathway strategies, no-transfer and sampled-transfer scenarios. Four major fixtures were also stacked with both captured minors and all their concentration branches: 18 combinations × three strategies × two credit states = 108 stacked pathways. Standalone branches: 21 × three strategies × two credit states = 126 pathways. Total: 234 generated pathways.

This is an audit of the current working tree, which contains concurrent parser, repeated-enrollment, and UI edits. No production files were changed by this audit. Fixture pages mix catalog vintages and do not include the repository's full catalog-enrichment pipeline. Standalone totals below 120 are therefore not automatically graduation defects. Public program policies were not revalidated online; findings refer to the captured HTML only.

## Confirmed high-priority defects

### 1. ISAT minor alternatives become additive requirements

`_live_psyc.html` actually contains **Integrated Science and Technology Minor**, not Psychology. Its captured text states:

- Foundational courses: choose 9–11 credits.
- Choose **one** sequence: Energy, Environment and Sustainability, Industrial and Manufacturing Systems, Applied Computing, or Applied Biotechnology (6–7 credits).
- One additional upper-level ISAT course: 3 credits.
- Total: **18–20 credits**.

Current parse produces seven categories, all with `selection == .unknown`. All five sequence categories reach scheduling as additive work. Parsed declared credits total 45; generated planned credits total **69**, with no transfer credit. The foundation selection also expands excessively. The additional upper-level requirement has no course options and is not represented as a specific selectable pool.

This directly reproduces the reported extra-course failure in a minor. Correcting ranking alone cannot fix the parsed requirement tree.

### 2. Applied Physics suggested elective areas become mandatory work

`_live_nursing.html` actually contains **Physics, B.S.**, not Nursing. Applied Physics catalog text describes **9 credits** of advisor-approved additional courses and lists suggested coherent areas. Parser attaches all six suggestion areas as additive categories (16 + 36 + 16 + 17 + 50 + 3 declared credits), alongside two empty categories both associated with the nine-credit instruction.

Effective parsed declared credits total **218**; generated standalone branch totals **188** credits. Required-course alternatives and zero-credit seminar annotations also deserve separate review, but were not independently isolated here. Suggested-area accumulation is directly visible in the parse and contradicts the captured elective instruction.

## Credit accounting and minor coverage

- No duplicate schedule row IDs in 234 generated pathways.
- Sampled earned course IDs did not reappear as concrete scheduled courses.
- Political Science minor: both option branches produce 19 planned credits; neither branch schedules the other branch's first required course in existing option tests.
- These checks do not prove minimal course selection, correct assignment of each credit to each requirement, or valid sharing under program-specific overlap limits.
- Existing overlap tests cover required-course reuse, elective pools, and general 120-credit top-up. They do not provide a general independent requirement-allocation oracle.
- Only **two** captured minor requirement pages exist, one concealed by a misleading filename. This is insufficient coverage for all catalog minors.
- Some parsed requirements have positive credits but no options: Psychology electives/cognate, Math additional requirements, ISAT upper-level elective, and Physics advisor-approved work. Whether enrichment fills each hole needs a separate end-to-end check.
- Physics multidisciplinary standalone output totals 119 credits. This is a diagnostic signal, not a confirmed graduation defect, because this harness intentionally excludes normal Gen Ed merging and catalog normalization.

## Recommended fix order

1. Preserve nested **choose-one sequence** structure for ISAT before generation.
2. Model suggested elective lists as eligible alternatives for a single credit budget, not independent requirements.
3. Add course-credit provenance: each scheduled course/placeholder must explain the unmet requirement it serves; graduation top-up gets its own reason.
4. Independently validate allocation, distinct slots, actual earned hours versus nominal equivalence, and explicitly modeled cross-program sharing restrictions.
5. Expand minor snapshots and expected outputs. Only then consider ML-assisted interpretation of ambiguous text; deterministic validation must reject invalid interpretations.

## Reproduction

`Tests/PlannerCoreTests/CatalogCorrectnessAuditTests.swift` retains the fixture matrix and two expected failures using Swift Testing `withKnownIssue`. Passing matrix tests mean the stated internal invariants passed; the known issues remain defects, not fixes.

```sh
env CFFIXED_USER_HOME=/tmp/jmu-audit CLANG_MODULE_CACHE_PATH=/tmp/jmu-audit-clang SWIFTPM_MODULECACHE_OVERRIDE=/tmp/jmu-audit-modules swift test --disable-sandbox --filter CatalogCorrectnessAuditTests
```

## Captured output

```text
AUDIT _live_psyc.html | base | declared=45 | projected=69.0 | unknown=7 | unmodeled=["One additional Integrated Science and Technology course at the 300 or 400 level: 3 Credit Hours"]
AUDIT _live_cs.html | base | declared=40 | projected=41.0 | unknown=1 | unmodeled=[]
AUDIT _live_math_bs.html | not-seeking-secondary-teaching-licensure-option-1 | declared=55 | projected=49.0 | unknown=2 | unmodeled=["Additional Requirements"]
AUDIT _live_psyc_bs.html | base | declared=53 | projected=45.0 | unknown=1 | unmodeled=["Psychology Electives", "Cognate Requirement"]
AUDIT _live_posc_minor.html | option-1 | declared=19 | projected=19.0 | unknown=2 | unmodeled=[]
AUDIT _live_math_bs.html | not-seeking-secondary-teaching-licensure-option-2 | declared=55 | projected=49.0 | unknown=2 | unmodeled=["Additional Requirements"]
AUDIT _live_posc_minor.html | option-2 | declared=19 | projected=19.0 | unknown=2 | unmodeled=[]
AUDIT _live_math_bs.html | seeking-secondary-teaching-licensure | declared=55 | projected=49.0 | unknown=2 | unmodeled=["Additional Requirements"]
AUDIT _live_accounting.html | base | declared=69 | projected=120.0 | unknown=3 | unmodeled=[]
STACK _live_cs.html | base | _live_posc_minor.html | option-1 | 3 strategies x 2 credit states
STACK _live_cs.html | base | _live_posc_minor.html | option-2 | 3 strategies x 2 credit states
STACK _live_psyc_bs.html | base | _live_posc_minor.html | option-1 | 3 strategies x 2 credit states
STACK _live_accounting.html | base | _live_posc_minor.html | option-1 | 3 strategies x 2 credit states
STACK _live_math_bs.html | not-seeking-secondary-teaching-licensure-option-1 | _live_posc_minor.html | option-1 | 3 strategies x 2 credit states
STACK _live_psyc_bs.html | base | _live_posc_minor.html | option-2 | 3 strategies x 2 credit states
STACK _live_cs.html | base | _live_psyc.html | base | 3 strategies x 2 credit states
STACK _live_math_bs.html | not-seeking-secondary-teaching-licensure-option-1 | _live_posc_minor.html | option-2 | 3 strategies x 2 credit states
STACK _live_math_bs.html | not-seeking-secondary-teaching-licensure-option-2 | _live_posc_minor.html | option-1 | 3 strategies x 2 credit states
STACK _live_accounting.html | base | _live_posc_minor.html | option-2 | 3 strategies x 2 credit states
STACK _live_psyc_bs.html | base | _live_psyc.html | base | 3 strategies x 2 credit states
STACK _live_math_bs.html | not-seeking-secondary-teaching-licensure-option-2 | _live_posc_minor.html | option-2 | 3 strategies x 2 credit states
STACK _live_math_bs.html | seeking-secondary-teaching-licensure | _live_posc_minor.html | option-1 | 3 strategies x 2 credit states
STACK _live_math_bs.html | seeking-secondary-teaching-licensure | _live_posc_minor.html | option-2 | 3 strategies x 2 credit states
STACK _live_accounting.html | base | _live_psyc.html | base | 3 strategies x 2 credit states
STACK _live_math_bs.html | not-seeking-secondary-teaching-licensure-option-1 | _live_psyc.html | base | 3 strategies x 2 credit states
AUDIT _live_nursing.html | applied-physics | declared=218 | projected=188.0 | unknown=10 | unmodeled=["Additional courses approved by the head of the Department of Physics and Astronomy: 9 Credit Hours", "Suggested areas of interest to complete the 9 credit hours required (minimum)."]
STACK _live_math_bs.html | not-seeking-secondary-teaching-licensure-option-2 | _live_psyc.html | base | 3 strategies x 2 credit states
STACK _live_math_bs.html | seeking-secondary-teaching-licensure | _live_psyc.html | base | 3 strategies x 2 credit states
AUDIT _live_nursing.html | fundamental-studies | declared=68 | projected=120.0 | unknown=2 | unmodeled=[]
AUDIT _live_nursing.html | multidisciplinary | declared=86 | projected=119.0 | unknown=5 | unmodeled=[]
AUDIT _live_nursing.html | option-1 | declared=52 | projected=52.0 | unknown=2 | unmodeled=[]
AUDIT _live_nursing.html | option-2 | declared=48 | projected=48.0 | unknown=2 | unmodeled=[]
AUDIT _live_nursing.html | option-3 | declared=44 | projected=44.0 | unknown=2 | unmodeled=[]
AUDIT _live_nursing.html | option-4 | declared=51 | projected=51.0 | unknown=2 | unmodeled=[]
AUDIT _live_nursing.html | multidisciplinary-business | declared=58 | projected=58.0 | unknown=2 | unmodeled=[]
AUDIT _live_nursing.html | multidisciplinary-geophysics | declared=61 | projected=120.0 | unknown=4 | unmodeled=["Any other 300- or 400-level geology or physics course (Upon approval from advisor): 3 Credit Hours"]
AUDIT _live_nursing.html | multidisciplinary-secondary-education | declared=64 | projected=120.0 | unknown=3 | unmodeled=[]
AUDIT _live_nursing.html | multidisciplinary-technical-and-scientific-communication-tsc | declared=76 | projected=108.0 | unknown=2 | unmodeled=["Choose Six Credits: 6 Credit Hours"]
AUDIT _live_nursing.html | physics-and-engineering-combined-program | declared=45 | projected=46.0 | unknown=1 | unmodeled=[]
```

## Verification result

Isolated build (`--scratch-path /tmp/jmu-correctness-audit-build`): full suite passed, **539 tests in 74 suites, with two known issues**. The known issues are the ISAT and Applied Physics assertions above. Initial shared-build attempt encountered a transient missing API in another agent's repeated-enrollment work; later shared runs queued behind another SwiftPM process, so final verification used the isolated build. Graph refreshed with `graphify update .`.
