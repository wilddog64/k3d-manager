# Bug: CI installs Copilot CLI as `latest`, so an upstream release in flight turns test jobs red

**Status:** OPEN — captured 2026-11-25, not triaged
**Priority:** P3 (operator, 2026-11-25: "yes" to filing) — hygiene / supply chain: CI red with no code cause; a rerun works.
**Triage:** patch → v1.46.1 (operator, 2026-11-25: "go with patch release v1.46.1"); Argon blind classification, Claude verified
**Branch:** `k3d-manager-v1.46.1` (not cut yet)
**Introduced by:** `0dfa5361` (2026-03-23, "Copilot CLI install + _copilot_auth_check integration test", #47)
**Should have been caught by:** review (the A08 rule pins every external tool; `VERSION=latest` breaks it)
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-25
**Prior art:** docs/bugs/ exact-slug glob (no match; the copilot-named docs are PR-review finding records); `make
find-similar-docs` not run — vector store unavailable (context `k3d-k3d-cluster` does not exist)

## Symptom

CI run 45660622977 on `k3d-manager-v1.45.1` at `c5bcf645` (2026-11-25): jobs `test (2)` and `test (4)` failed in the step
"Install Copilot CLI" at about 17:04 UTC with `Error: Checksum validation failed.`, before any test ran. The same step passed
in all four test jobs of the next commit (`65fd63f2`) minutes later, so the failure follows upstream release timing, not the
code.

## Where

`.github/workflows/ci.yml:119-133` and `:173-187` (two jobs): `curl … https://gh.io/copilot-install` then
`env VERSION=latest bash copilot-install.sh`. The installer script itself is fetched from a redirecting short link, also
unpinned.

## Not yet known

- Which Copilot CLI release was in flight at 17:04 UTC (not captured), and whether the installer accepts a pinned
  `VERSION=<x.y.z>`; prove with the installer source at a tag before dispatch.

## Acceptance (draft, for triage)

- must: both jobs install a pinned Copilot CLI version (and a pinned installer source), shown in the workflow.
- must_not: `VERSION=latest` or an unpinned installer URL remains in `.github/workflows/` (grep, red on today's file).
