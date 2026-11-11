# JMU Course Planner

A native macOS SwiftUI application for James Madison University undergraduate schedule planning.

The app lets students:

- choose a JMU undergraduate major from a catalog-organized list,
- add AP and dual enrollment transfer credit,
- plan against bundled major and minor requirement rows parsed from official JMU catalog HTML,
- generate three semester-by-semester draft pathways for programs with parsed course requirements,
- drag courses between semesters,
- see prerequisite and availability warnings,
- track graduation progress in a persistent side panel,
- save and resume plans locally,
- export a plan to PDF or `.ics`.

## Quick Start

Download the latest `.zip` from [GitHub Releases](https://github.com/kyol-dony/JMU-Course-Selector/releases), unzip it, and open `JMU Course Planner.app`.

To build from source instead, read [BUILD_AND_LAUNCH_GUIDE.md](BUILD_AND_LAUNCH_GUIDE.md).

## Important Data Notice

The project includes the official JMU 2026-2027 Undergraduate Catalog PDF and a structured seed file at [Data/catalog_seed.json](Data/catalog_seed.json). Each release bundles a catalog snapshot at [Data/catalog_snapshot.json](Data/catalog_snapshot.json), parsed from JMU's current path-based `catalog.jmu.edu` pages. The app plans from that snapshot offline and does not download or modify catalog data.

The app does not invent missing catalog rules, course availability, course descriptions, or Rate My Professor ratings. Broad prose requirements, advisor-selected choices, and unknown data are shown as partial or unavailable.

See [LIMITATIONS.md](LIMITATIONS.md) and [docs/catalog-data-sourcing.md](docs/catalog-data-sourcing.md) before relying on generated plans.

## License

Copyright 2026 Kyle Doney. Released under the [PolyForm Noncommercial License 1.0.0](LICENSE.md): free to use, change, and share for noncommercial purposes, including personal use and use by schools and nonprofits. Commercial use requires separate permission.

JMU catalog material in this repo belongs to James Madison University and is not covered by this license. This project is not affiliated with or endorsed by JMU. See [LICENSE.md](LICENSE.md) for details.
