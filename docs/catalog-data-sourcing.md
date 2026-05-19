# Catalog Data Sourcing

## Authoritative source used

The current catalog source used by this project is:

https://www.jmu.edu/catalog/pdfs/2025-2026-jmu-undergraduate-catalog.pdf

The PDF identifies itself as the `James Madison University 2025-2026 Undergraduate Catalog`, catalog issue May 2025.

The downloaded copy is stored at:

`Data/Sources/2025-2026-jmu-undergraduate-catalog.pdf`

The structured seed file used by the app is:

`Data/catalog_seed.json`

## HTML source used for refresh

After the first PDF-based seed was built, the app added an HTML refresh path:

- `https://catalog.jmu.edu/content.php?catoid=62&navoid=3541` is the official 2025-2026 Undergraduate Catalog `Programs of Study` page.
- It lists program records by section, including `Major`, `Minor`, and `General Education`.
- In the current catalog HTML checked on May 19, 2026, this page exposes 92 `Major` links, 112 `Minor`/`Cross Disciplinary Minor` links, and 5 `General Education` links.
- Each program link points to `preview_program.php?catoid=62&poid=...`.
- Adding `&print` to a program URL returns a print-friendly HTML page with structured `acalog-core` sections, requirement headings, course links, credit values, footnotes, and sample plans.
- Course links expose `coid` values. The allowed `preview_course.php?catoid=62&coid=...&print` endpoint returns official course description, credits, PeopleSoft Course ID, grading basis, and prerequisite text.

This path is preferable to PDF parsing because it preserves course links and requirement headings in HTML.

`catalog.jmu.edu/robots.txt` disallows `/search_advanced.php` and `/ajax/` for general crawlers and specifies a crawl delay. The HTML pipeline should therefore avoid those endpoints unless JMU grants explicit permission. The verified path uses allowed `content.php`, `preview_program.php`, and `preview_course.php` pages.

No catalog rule should be inferred from non-JMU sources.

## What is verified in the bundled seed

- Program names, degree types, colleges/departments, and catalog pages are taken from the catalog table of contents.
- Computer Science, B.S. requirements are seeded from the catalog section beginning on page 187.
- Information Technology, B.S. requirements are seeded from the catalog section beginning on page 190.
- The AP transfer rules included in `catalog_seed.json` are seeded from the Advanced Placement chart on catalog pages 14-16.

## What is not verified

- Concentration and track-specific rules.
- Complete General Education category choice lists.
- Course semester availability.
- Live registrar course descriptions.
- Rate My Professor ratings and professor lists.

All of these are surfaced as unverified or unavailable in the app.

## Refresh design

The app includes a **Refresh Requirements** action that fetches the official HTML catalog index and each major/minor print page into a structured local cache. The bundled PDF/seed remains the offline fallback.

The implemented HTML pipeline:

1. Fetches `content.php?catoid=62&navoid=3541`.
2. Parses `Major`, `Minor`, and `Cross Disciplinary Minor` program links with `catoid`, `poid`, title, degree type, and source URL.
3. Fetches each `preview_program.php?catoid=...&poid=...&print` page with a small delay between program pages.
4. Parses requirement headings, credit values, fixed course rows, course links, `coid` values, `or` choices, and `choose N` choice groups.
5. Caches a structured `Catalog` JSON in Application Support and loads it before falling back to `Data/catalog_seed.json`.
6. Marks parsed HTML requirements as `partial` because unrestricted electives, prose rules, concentrations, and advisor-selected choices still require human review.

The parser does not use `search_advanced.php` or `/ajax/` endpoints.
