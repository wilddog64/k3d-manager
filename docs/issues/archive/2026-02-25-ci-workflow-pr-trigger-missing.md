# CI Workflow Does Not Run on Pull Requests

**Date:** 2026-02-25
**Status:** Fixed

## Description

PR #2 (`ldap-develop` → `main`) did not trigger the Stage 1 "CI" workflow, so the
required `lint` status check never appeared. The workflow was configured to run on
`push` events only, and the most recent commits were markdown/docs-only changes that
match `paths-ignore`, so no job was enqueued when the PR opened.

## Impact

- Branch protection cannot be satisfied because the `lint` check is missing, blocking
  merges.
- Contributors get no automated shellcheck/bash/yamllint feedback when they open a PR.

## Root Cause

`.github/workflows/ci.yml` only declared a `push` trigger (with docs/memory-bank
exclusions). PRs that touched only ignored paths after the last lintable commit
produced no workflow run even though a PR was open.

## Resolution

- Added a `pull_request` trigger (limited to the `main` base branch) with the same
  `paths-ignore` list so every PR to `main` runs Stage 1 linting regardless of which
  files changed in the latest push.
- Verified by pushing commit `$(git rev-parse --short HEAD)` which touched the workflow
  itself and observing that GitHub Actions queued a new `CI / lint` run for PR #2.

## Follow-up

- None. Stage 1 now runs on both pushes and PRs; Stage 2 work remains tracked in
  `docs/plans/ci-workflow.md`.
