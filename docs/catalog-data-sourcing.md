# Catalog Data Sourcing

## Current authoritative sources

The project targets JMU's 2026-2027 Undergraduate Catalog:

- Catalog root: `https://catalog.jmu.edu/`
- Programs: `https://catalog.jmu.edu/program-search/?filter=1`
- General Education: `https://catalog.jmu.edu/general-education/`
- Full PDF: `https://catalog.jmu.edu/pdf/JMU2026-2027UndergraduateCatalog.pdf`

The bundled PDF is stored at `Data/Sources/JMU2026-2027UndergraduateCatalog.pdf`. The structured offline fallback is `Data/catalog_seed.json`.

JMU replaced the previous Acalog PHP URLs with path-based pages for this edition. Program pages now use paths such as `/programs/computer-science-bs/`, and course pages use `/search/?P=CS%20149`. The old `content.php`, `preview_program.php`, and `preview_course.php` routes are not current catalog endpoints.

No catalog rule should be inferred from non-JMU sources.

## HTML refresh

The app's **Refresh Requirements** action:

1. Fetches the current program search page.
2. Keeps undergraduate bachelor's degree and minor records and deduplicates the site's alternate card/list views.
3. Fetches each path-based program page and parses its `sc_courselist` requirement tables.
4. Fetches all five General Education area pages and merges the 14 cluster course buckets into each major.
5. Uses each course's `/search/?P=...` page to cache its official description and prerequisite/corequisite text.
6. Stores the structured catalog in Application Support and loads it before the bundled seed.

The current site may challenge non-browser HTTP user agents, so catalog requests use a conventional browser user agent. Refreshes still use a small delay and limited concurrent detail requests to avoid unnecessary load.

## Verification boundaries

Program names, degrees, program requirements, course links, and General Education course buckets come from the current official HTML. Parsed requirements remain marked `partial` when prose, unrestricted electives, advisor-selected choices, or sequence alternatives cannot be represented exactly by the scheduling model.

The AP transfer rules in `catalog_seed.json` retain their explicit 2025-2026 source labels until the current AP chart is independently compared and re-verified. Their provenance should not be silently relabeled during a catalog URL migration.

Course semester availability and automatic Rate My Professor ratings are not supplied by the catalog and are not inferred.
