# Release and commit policy

This project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). `VERSION` is the canonical semantic version. Git release tags prefix it with `v`. Published tags and release contents must never be moved or replaced.

Every version update, Git tag, and release title MUST include `+catalog.N`, where N is the parsed catalog revision shipped by that exact commit (`cacheSchemaVersion` in `CatalogRepository.swift`). The preparation tool derives it from source; CI rejects mismatches or omission. Examples: `0.2.1-alpha.1+catalog.28`, tag `v0.3.0-alpha.1+catalog.28`, stable tag `v1.0.0+catalog.28`. This is build metadata and does not affect SemVer precedence. A catalog-only correction still receives the appropriate semantic patch/minor bump; changing catalog metadata alone cannot trigger a release. Different branches may ship different catalog revisions. Numbers below describe the semantic core unless a full version is shown.

## Every agent and contributor

Use Conventional Commits: `fix(parser): restore documented requirement grouping`, `feat: support another requirement family`, or `feat!: replace saved-plan format`. Mark incompatible changes with `!` or a `BREAKING CHANGE:` footer. Choose the highest actual impact of the entire merge, not merely its commit prefixes.

Ordinary work commits do not change VERSION or create tags. Immediately before integration, sync the destination and prepare one version update with a reason:

```sh
git fetch origin
python3 script/release_policy.py prepare --base-ref origin/schedule-board-interaction --target schedule-board-interaction --impact patch --reason 'Restore documented parser grouping for existing catalog syntax'
git add VERSION release-impact.json
git commit -m 'chore: prepare integration version'
python3 script/release_policy.py check --base-ref origin/schedule-board-interaction --target schedule-board-interaction
```

For promotion, substitute `origin/main` and `main`. Commit VERSION and receipt together. If destination advances, sync and prepare again. Required strict Version policy checks prevent two accepted PRs sharing a version. Merge through PRs; direct pushes bypass pre-merge validation and can fail after landing. Initial policy dissemination is the single bootstrap exception and creates no release.

## Initial development

Integration branch: `schedule-board-interaction`.

| Merge impact | Transition | Publication |
| --- | --- | --- |
| Compatible bug fix, parser realignment, maintenance | `0.2.0-alpha.1+catalog.27` → `0.2.1-alpha.1+catalog.28` | Metadata only |
| New capability or public deprecation | `0.2.1-alpha.1+catalog.28` → `0.3.0-alpha.1+catalog.28` | `v0.3.0-alpha.1+catalog.28` tag and GitHub pre-release |
| Incompatible pre-1.0 change | Next minor, patch reset | Tagged pre-release plus migration notes |

The pre-1.0 breaking-change minor bump and maintenance patch bump are project conventions permitted by SemVer's unstable 0.y.z contract. A numeric prerelease counter does not increment on every merge; the semantic core changes. The initial stage stays `alpha.1`. Explicit stage/candidate changes need a separately reviewed policy-tool change; do not manually bypass validation.

A parser correction restoring documented behavior is normally patch. Supporting previously unsupported requirement kinds is normally minor. Refactoring without public behavior changes is patch. Compatibility impact overrides commit-label assumptions. Explain decisions in the receipt and PR. Bug fixes may change incorrect output without constituting a public contract break.

## Stable promotion and later releases

First development promotion into main becomes **1.0.0**, with tag **v1.0.0** and stable GitHub release. Bootstrap installation on main is not a product promotion. Existing v0.0.0 and the separate draft v0.1.0-alpha.1 remain unchanged.

After 1.0.0, stable fixes/maintenance bump patch, compatible features/deprecations bump minor, and incompatible contracts bump major. Minor resets patch; major resets both. Stable main integrations publish matching tags/releases after checks pass. Development integrations retain `alpha.1`; sync main after promotion to start from the stable baseline. Promoting a future development target removes its suffix without another semantic-core bump. Incompatible pre-1.0 changes use minor; incompatible post-1.0 changes use major.

## Compatibility contract

Public compatibility includes documented supported app behavior, import/export formats, saved `.jmuplan.json` data, catalog interchange data, and PlannerCore public declarations. Backward-compatible releases preserve existing documented workflows and readability of saved plans; intentional removals, incompatible serialized data, or incompatible public signatures are breaking changes. Unverified catalog prose is not promised to be fully schedulable. Changes to official JMU rules must distinguish correcting stale/incorrect source data from removing supported app functionality. Maintain migration notes for breaks and document new public behavior with its implementation.

## Release artifacts

Public distribution includes dev prereleases, but never developer-tool builds. `Reset App Data` UI and deletion entry points compile only with `JMU_DEV_TOOLS`; public release packaging rejects binaries containing the reset action or entry-point names. Removing the reset action from public builds is an intentional pre-1.0 workflow removal: existing saved plans remain readable, but testers must use ordinary setup/plan workflows rather than resetting the app. Version 0.4.0 exposed this control and is superseded by the corrective prerelease; do not distribute that version.

Each new release also ships the static, plain-language guide in `docs/INSTALLATION.txt`: inside the ZIP as `START HERE - Installation Guide.txt` and as a separate release asset with that display label (download filename `INSTALLATION.txt`). Keep these copies identical by copying/uploading this source, not maintaining separate versions. The guide covers macOS requirements, Applications installation, Apple's per-app Privacy & Security approval, first launch, updates, and troubleshooting. It does not instruct users to disable Gatekeeper or bypass malware warnings. Review the linked Apple instructions when macOS changes. Retry logic adds missing assets without rebuilding an already-uploaded app or replacing existing assets.

Every published release, pre-release or stable, attaches exactly one app archive named after the release: `JMU Course Planner v<version>.zip`, containing a folder of the same name that holds `JMU Course Planner.app`. Build it only with `script/package_release.sh "<release title>" <output-dir>`, which produces the default public build (universal, optimized, ad-hoc signed). Public builds perform the automatic first-launch catalog refresh but expose no on-demand refresh or live catalog fetching. Never attach any other build. The publish job packages and attaches the archive automatically; a retry uploads it only when missing and never replaces an existing asset.

## Automation and recovery

PR checks validate versions, impact receipts, and new Conventional Commits. Historical commits before policy installation are exempt. CI runs policy tests; publication runs Swift tests against the exact merge SHA first. Patch development merges return before any GitHub write. Minor development versions create pre-releases; stable main versions create stable releases.

Metadata is prepared in the integration PR, so no bot commits or recursive workflow bumps are needed. Concurrent PRs must update to the latest target before passing strict checks. Version allocation is serialized by merge acceptance; per-SHA publication concurrency avoids dropping unrelated queued merge events.

Release jobs resolve existing tags and reject SHA/status conflicts. Retrying a successful job returns the existing release; existing drafts are never silently published. Use Actions **Run workflow** on the integration branch to retry its current tip, or rerun the failed original run to retry an older merge SHA. Do not move tags or rewrite published versions to repair errors.

Install local commit validation with `bash script/install_release_hooks.sh`. Hooks are shared across linked worktrees; future clones must run setup. Existing unrelated hooks must be retained. CI is authoritative; hooks can be bypassed locally. VERSION and impact files must only be changed via the preparation tool during integration.
