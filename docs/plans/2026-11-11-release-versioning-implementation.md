# Release Versioning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Apply approved SemVer policy to integration branches and every agent worktree.

**Architecture:** Integration PRs carry VERSION plus an impact/rationale receipt derived from the destination version. Required CI checks reject stale or invalid transitions; successful merged commits publish only eligible versions. Shared local commit hooks and tracked agent guidance cover ordinary worker commits.

**Tech Stack:** Python standard library, Git, GitHub CLI, GitHub Actions, shell.

## Task 1: Policy engine and validation

Create `script/release_policy.py`, `script/test_release_policy.py`, `VERSION`, `release-impact.json`, and `docs/RELEASING.md`. Test SemVer syntax, patch/minor/major resets, initial promotion, truthful impact receipts, and publication eligibility with `python3 -m unittest discover -s script -p 'test_release_policy.py'`. Add prepare/check commands and Conventional Commit validation. Confirm failed transitions reject changes before writing.

## Task 2: Integration checks and publishing

Create `.github/workflows/release-policy.yml` and `script/publish_release.py`. Validate integration PRs against current destination VERSION; run policy tests and Swift tests before release publication at exact push SHA. Existing tags must match SHA and release status; retries reuse matching tags. Patch pre-releases make no GitHub writes. Include a manual retry path and no token interpolation from PR text. Build packaging reads VERSION while preserving macOS numeric bundle version constraints.

## Task 3: Agent rollout

Track root `AGENTS.md` and `CLAUDE.md`, preserving existing Graphify instructions. Add policy references and commit requirements. Install shared hooks without replacing unrelated hooks. Commit only policy files, then apply isolated commit to all clean branches and the dirty audit worktree without staging its code. Verify policy files match across worktrees. Push policy-only changes, enable required strict policy check, and inspect remote results. Bootstrap installation must not publish a stable release. Record exceptions and tests in final handoff.
