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

Build the app with `Build App.command`, then open `dist/JMU Course Planner.app`.
The generated app is kept out of Git; release builds will be distributed separately.
See [BUILD_AND_LAUNCH_GUIDE.md](BUILD_AND_LAUNCH_GUIDE.md) for requirements and steps.

## Important Data Notice

The project includes a structured seed file at [Data/catalog_seed.json](Data/catalog_seed.json). The app refreshes from JMU's current path-based `catalog.jmu.edu` pages, parses major and minor requirement sections, and caches the result locally for schedule generation. The catalog PDF is available from JMU when needed; it is not stored in this repository.

The app does not invent missing catalog rules, course availability, course descriptions, or Rate My Professor ratings. Broad prose requirements, advisor-selected choices, and unknown data are shown as partial or unavailable.

See [LIMITATIONS.md](LIMITATIONS.md) and [docs/catalog-data-sourcing.md](docs/catalog-data-sourcing.md) before relying on generated plans.

## License

Copyright 2026 Kyle Doney. Released under the [PolyForm Noncommercial License 1.0.0](LICENSE.md): free to use, change, and share for noncommercial purposes, including personal use and use by schools and nonprofits. Commercial use requires separate permission.

JMU catalog material in this repo belongs to James Madison University and is not covered by this license. This project is not affiliated with or endorsed by JMU. See [LICENSE.md](LICENSE.md) for details.
