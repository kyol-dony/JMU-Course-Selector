# Release versioning policy — approved design

Approved on 2026-11-11. Additional approved constraint: every updated version, tag, and release includes `+catalog.N`, derived from the shipped commit's `cacheSchemaVersion`. This build metadata does not affect precedence. Integration PRs carry validated metadata before merge; strict up-to-date checks serialize allocation. See docs/RELEASING.md for implemented commands and full catalog-bearing examples.

## Authority and scope

Semantic Versioning 2.0.0 (https://semver.org/spec/v2.0.0.html) is normative. Branch behavior and release triggers below are project policy, not requirements imposed by SemVer. Semantic-core examples below omit the mandatory catalog suffix for readability.

Versions use `MAJOR.MINOR.PATCH[-PRERELEASE]`. Git tags add `v`. Numeric identifiers have no leading zeros. Published versions and tags are immutable. Build metadata, when used, does not affect precedence.

## Development branch

`schedule-board-interaction` is the current integration branch. Before the first stable release, each merged branch advances the semantic core once, based on the combined effect of its changes. Individual working commits do not advance versions or create tags.

| Merge effect | Development version change | Tag / GitHub release |
| --- | --- | --- |
| Compatible correction, including parser realignment restoring documented catalog behavior | `0.X.Y` → `0.X.(Y+1)` | Neither |
| New compatible functionality or substantial new capability | `0.X.Y` → `0.(X+1).0` | Tag and GitHub pre-release |
| Incompatible change during initial development | `0.X.Y` → `0.(X+1).0` | Tag and GitHub pre-release, with migration notes |
| Documentation, tests, build, or maintenance without new functionality | Patch by project convention | Neither |

SemVer permits unstable contracts during `0.y.z`. Using a minor bump for incompatible pre-1.0 changes is this project's explicit convention. Reaching `1.0.0` is reserved for the first promotion to `main`.

The canonical `VERSION` metadata includes an explicit development suffix, initially `alpha.1`; for example, `0.2.0-alpha.1`. Patch-only integration produces `0.2.1-alpha.1` without a tag or release. A subsequent feature integration produces `0.3.0-alpha.1`, tag `v0.3.0-alpha.1`, and a GitHub pre-release. The changing semantic core establishes precedence; the numeric suffix need not increase on each merge.

Stages `alpha`, `beta`, and `rc`, and additional candidate numbers, change only through explicit release preparation. Patch merges never create tags or GitHub releases, even if the stage changes would otherwise be useful. An explicitly requested additional release candidate is a separate release operation.

## Classification requires judgment

Conventional Commit types provide evidence, not a substitute for evaluating compatibility and behavior. Evaluate all commits in the merged branch; apply the highest required impact once. A misleading commit prefix must not silently determine the version.

- Correcting a parser to honor already-supported catalog syntax is ordinarily a patch.
- Adding support for a previously unsupported requirement family or planning workflow is ordinarily a minor.
- Refactoring internals without changing the contract is ordinarily a patch under the per-merge metadata convention.
- Removing supported behavior or making saved plans unreadable requires an incompatible-change classification and migration guidance.
- Deprecating supported public functionality requires at least a minor bump.

Every merge records its classification and brief rationale in the PR or merge description. Unclear compatibility requires documenting the decision before integration.

## Public compatibility contract

Document the supported PlannerCore public interfaces, saved-plan and catalog interchange formats, and documented app/import/export behavior. Changes are assessed against that contract. A correction to behavior that contradicted the documented contract can be a patch; an intentional incompatible contract change cannot be hidden behind a `fix` prefix.

## First stable promotion

The first integration of `schedule-board-interaction` into `main` sets `VERSION` to `1.0.0`, creates immutable tag `v1.0.0` at the tested release commit, and creates the first stable GitHub release. Remove the development suffix. Existing `v0.0.0` and the draft `v0.1.0-alpha.1` remain historical/separate artifacts; do not retarget them or treat them as proof of development-branch version state.

## After 1.0.0

Stable integrations into `main` use the highest impact since the previous stable release:

- Backward-compatible fixes and maintenance: patch.
- Backward-compatible features or public deprecations: minor, resetting patch to zero.
- Incompatible public-contract changes (`!` or `BREAKING CHANGE`): major, resetting minor and patch to zero.

Stable releases use plain semantic versions and matching `v` tags. Later development versions must be based on a future stable target, such as `1.1.0-alpha.1`, rather than continuing the `0.x` sequence. The special patch-versus-minor publication rule above applies to the initial `0.x` development period.

## Enforcement design

1. Commit guidance in `AGENTS.md` and `CLAUDE.md` requires Conventional Commits, impact rationale, and use of one shared version tool for integration. Workers do not independently bump versions while working on feature branches.
2. A version policy tool validates SemVer, computes the transition from the merge's prior version and recorded impact, and updates canonical `VERSION`. Build packaging reads the same source.
3. CI checks classifications and transitions, including zero resets, pre-release status, and release/tag agreement. Integration processing is serialized and idempotent so retries and concurrent merges cannot allocate duplicate versions.
4. Metadata updates are committed with a recognizable automation marker and do not recursively count as another merged change.
5. Release creation occurs only after applicable checks pass, at an exact commit SHA. A failed release job can retry without changing or moving an existing tag. Patch integration jobs are tested to perform no tag or release writes.
6. Local hooks provide quick feedback; CI supplies repository enforcement. Existing unrelated hooks are preserved.

## Dissemination design

Create one isolated policy/enforcement commit and apply that same change to every local branch and active worktree after checking their instructions and dirty state. Preserve in-progress edits and avoid merging unrelated application code. Include `main`, `schedule-board-interaction`, and the active audit/logic branches discovered during implementation; enumerate again before rollout because worktrees may change.

Install shared repository hooks for existing worktrees and document setup for future clones. Verify each branch contains the policy and each worktree resolves the intended hooks. Push updated branches as authorized by the rollout request; protected-branch restrictions require a policy-only PR rather than rewriting branch history. Remote rules and CI must be active on the integration branches for enforcement to apply to remote workers.

## Acceptance checks

- Parser correction advances patch metadata and makes zero release/tag API calls.
- New parser capability advances minor, clears patch, and creates exactly one tagged pre-release.
- Mixed merges use the highest impact once.
- First stable promotion produces exactly `1.0.0` and a stable release.
- Post-stable fixes/features/breaks produce patch/minor/major respectively.
- Malformed versions, leading zeros, version regression, tag movement, duplicate processing, and mismatched release status are rejected.
- Existing dirty worktrees and unrelated hooks remain intact during dissemination.
