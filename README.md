# JMU Course Planner

A native macOS SwiftUI application for James Madison University undergraduate schedule planning.

The app lets students:

- choose a JMU undergraduate major from a catalog-organized list,
- add AP and dual enrollment transfer credit,
- refresh official JMU catalog HTML to gather current major and minor requirement rows,
- generate three semester-by-semester draft pathways for programs with parsed course requirements,
- drag courses between semesters,
- see prerequisite and availability warnings,
- track graduation progress in a persistent side panel,
- save and resume plans locally,
- export a plan to PDF or `.ics`.

## Quick Start

For normal use, open:

`dist/JMU Course Planner.app`

If that app is not present yet, read [BUILD_AND_LAUNCH_GUIDE.md](BUILD_AND_LAUNCH_GUIDE.md).

## Important Data Notice

The project includes the official JMU 2026-2027 Undergraduate Catalog PDF and a structured seed file at [Data/catalog_seed.json](Data/catalog_seed.json). The app refreshes from JMU's current path-based `catalog.jmu.edu` pages, parses major and minor requirement sections, and caches the result locally for schedule generation.

The app does not invent missing catalog rules, course availability, course descriptions, or Rate My Professor ratings. Broad prose requirements, advisor-selected choices, and unknown data are shown as partial or unavailable.

See [LIMITATIONS.md](LIMITATIONS.md) and [docs/catalog-data-sourcing.md](docs/catalog-data-sourcing.md) before relying on generated plans.
