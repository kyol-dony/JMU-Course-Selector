# Course Detail Cache Design

## Goal

Course clicks in the JMU course schedule creator should show useful local course details. The course detail sheet should display official JMU course descriptions cached during catalog refresh, plus responsible Rate My Professors navigation without scraping or fabricating ratings.

## Decisions

- Course descriptions are fetched and cached during the catalog HTML refresh, not fetched live on click.
- Rate My Professors support is links/status only. The app does not scrape RMP and does not show ratings unless a future curated dataset is added.
- The existing course-detail click flow stays in place. `CourseDetailService` becomes a local mapper from cached course data to sheet data.
- Missing data is shown explicitly instead of inferred.

## Architecture

Extend `PlannerCore.Course` with cached official-detail fields:

- `description: String?`
- `descriptionSourceURL: URL?`
- `detailRetrievedAt: Date?`

`CatalogRepository.refreshCatalogFromHTML` already discovers `registrarURL` values from JMU `coid` links while parsing program requirement pages. After deduping courses, it will fetch course-detail pages for courses that have a `registrarURL`, parse official description content, and save the enriched `Catalog` into the existing JSON cache.

The bundled seed can keep descriptions empty. Courses from the bundled seed remain clickable but show an unavailable state until HTML refresh discovers registrar URLs and detail text.

## Components

### PlannerCore

`Course` carries cached detail data because course descriptions are part of official catalog course metadata. This keeps click-time behavior simple and makes the catalog cache self-contained.

`JMUHTMLCatalogParser` gains a course-detail parser for official JMU course pages. It extracts:

- official course description
- prerequisite text when clearly present
- optional source metadata if cheap to parse

### JMUCoursePlanner

`CatalogRepository` fetches and merges course detail pages during refresh. Merge logic preserves existing course title, credits, prerequisite IDs, and registrar URL while filling missing description fields from official course pages.

`CourseDetailService` uses only local cached course data. It returns cached description text when present, otherwise an unavailable status and source link.

`CourseDetailSheet` keeps the current layout. The Description section renders cached official text. The Rate My Professors section renders a neutral status and a link to the James Madison University professor search page:

`https://www.ratemyprofessors.com/search/professors/457?q=%2A`

## Data Flow

1. User refreshes catalog or first launch triggers refresh.
2. Repository fetches official JMU program pages.
3. Program parser discovers course rows and registrar `coid` URLs.
4. Repository dedupes courses by ID.
5. Repository fetches course-detail pages for courses with registrar URLs.
6. Course-detail parser extracts descriptions.
7. Repository saves enriched catalog cache.
8. User clicks course chip in Schedule or Catalog.
9. Store opens `CourseDetailSheet`.
10. Detail service maps cached `Course` fields into `CourseDetail`.

## Refresh Behavior

Course-detail fetches should use bounded concurrency so refresh stays practical without hammering catalog.jmu.edu. A limit of 4 concurrent course-detail requests is a reasonable starting point.

Failures are per-course. A failed course-detail request should not fail the whole catalog refresh. The course remains in the catalog with its registrar URL and unavailable description state.

## Error Handling

If a course has cached description text, show it.

If a course has a registrar URL but no cached description, show:

> Description unavailable in cached catalog. Open the JMU registrar page to verify details.

If a course has no registrar URL, show:

> Description unavailable until the catalog refresh discovers the official JMU course page.

The RMP section always avoids unsupported claims:

> Automatic Rate My Professors ratings are unavailable because the app does not use unstable scraping. Search JMU professors on Rate My Professors.

## Testing

- Parser test: sample JMU course-detail HTML parses official description and prerequisite text.
- Merge test: existing `Course` values survive enrichment, while missing description fields are filled.
- Service test: cached course descriptions appear in `CourseDetail`; missing descriptions produce unavailable status.
- UI smoke path: course chips still call `store.showCourse`, and sheet can render cached description plus RMP search link.

## Non-Goals

- No live description network fetch on click.
- No RMP scraping.
- No automatic professor-rating display.
- No broad redesign of the course detail sheet.

## Documentation Updates

Update `LIMITATIONS.md` during implementation:

- Official descriptions are cached during catalog refresh when JMU course pages are reachable.
- Courses without discovered registrar URLs show an unavailable state.
- RMP uses search links only; ratings are not automatically populated.
