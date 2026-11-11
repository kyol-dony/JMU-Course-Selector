## Release and commit policy

All agentic workers must follow `docs/RELEASING.md` before committing or integrating code.

- Every new worker commit uses Conventional Commits (`fix(parser): ...`, `feat: ...`, `feat!: ...`). Mark incompatible contracts explicitly.
- Every version update, tag, and release includes `+catalog.N`, derived from the shipped commit's CatalogRepository.cacheSchemaVersion. Never guess or omit it. Example: `v0.3.0-alpha.1+catalog.28`. Build metadata does not alter SemVer impact or publication rules.
- Individual work commits do not allocate versions or create tags. Before an integration PR merges, use `script/release_policy.py prepare` against the latest destination and commit VERSION plus release-impact.json together. Record actual impact and rationale; highest impact across the merge wins.
- On schedule-board-interaction during 0.x: patch changes update metadata only; minor changes reset patch and create tagged GitHub pre-releases after CI. Pre-1.0 breaking changes use minor with migration notes.
- First product promotion to main becomes 1.0.0. Later stable fixes/features/breaks bump patch/minor/major. Published tags and versions are immutable.
- Install shared validation with `bash script/install_release_hooks.sh`. Do not overwrite unrelated hooks. PRs must pass Version policy against an up-to-date integration branch.
- Do not publish releases from ordinary feature branches or bypass version checks. Preserve other workers' edits during rollout and integration.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
