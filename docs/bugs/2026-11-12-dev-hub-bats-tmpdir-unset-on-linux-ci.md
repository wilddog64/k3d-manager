# dev_hub.bats fails on Linux CI: `${TMPDIR}` unset, so mktemp targets `/`

**Status:** LANDED — test-only one-line fix on `k3d-manager-v1.44.0`, 2026-11-12 (Claude)
**Priority:** P1 (proposed: CI red on the release branch since dev-hub A landed; blocks `make hub-promote`, which needs green checks)
**Classified:** pending second-agent classification
**Introduced by:** `b2067ad3` (dev-hub Part A)
**Should have been caught by:** review (Claude verified the land on macOS only, where `TMPDIR` is always set)
**Prior art:** `docs/bugs/2026-11-12-v1-44-0-ci-red-linux-script-syntax-and-squash-dated-specs.md` (exact-slug glob, read) — same escape class (macOS-only land check), different root cause
**Waiting on:** live check

## Symptom

Every CI run on `k3d-manager-v1.44.0` since `b2067ad3` is red in lint, "Run the full offline suite": all 12
`dev_hub.bats` tests fail in setup (`scripts/tests/plugins/dev_hub.bats:9`):
`mktemp: failed to create directory via template '/dev-hub-bats.XXXXXX': Permission denied`.
The GitHub Linux runner does not set `TMPDIR`; macOS does.

## Fix (landed)

`"${TMPDIR}/dev-hub-bats.XXXXXX"` → `"${TMPDIR:-/tmp}/dev-hub-bats.XXXXXX"`. Checked on macOS:
`env -u TMPDIR bats scripts/tests/plugins/dev_hub.bats` 12 not ok before, 12 ok after; 12 ok with `TMPDIR` set.
No other suite uses a bare `"${TMPDIR}/`. The dev-hub Part B worktree carries the same line and must take this
on rebase. Live check: the next CI run on the branch is green in lint.

## Note for triage

Second macOS-only escape today. A land-time check that runs the touched suites with `env -u TMPDIR` (or in
`ubuntu:24.04`) would have caught both.
