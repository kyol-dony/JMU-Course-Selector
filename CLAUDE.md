## Release and commit policy

Every version update and release includes `+catalog.N`, derived from the shipped CatalogRepository.cacheSchemaVersion. Never copy another branch's catalog revision blindly.

Read and follow `AGENTS.md` and `docs/RELEASING.md` before every commit and integration. All workers use Conventional Commits; integration PRs prepare VERSION and release-impact.json using script/release_policy.py. Dev 0.x patch merges are metadata-only; minor merges create tagged pre-releases. First product promotion to main is 1.0.0. Do not allocate a version per working commit or move published tags. Install shared hooks with `bash script/install_release_hooks.sh`.

<!-- graphify-rules-start (managed by `graphify init`) -->
## Use Graphify before grep

This repository is indexed by Graphify: a code graph over its call, dependency, and test structure, exposed through a connected Graphify MCP server. Before reaching for grep or reading files, use the Graphify tools your MCP client lists for symbol definitions, behavior, call relationships, change impact, tests, dependencies, and dependents.

Fall back to grep or file reads only for literal strings or comments, non-indexed files, or files already located. If no Graphify tools are listed, check the MCP server connection.
<!-- graphify-rules-end -->
