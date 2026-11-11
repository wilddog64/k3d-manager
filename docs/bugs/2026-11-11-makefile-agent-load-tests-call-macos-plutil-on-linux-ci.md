# Bug: makefile_agent_load.bats runs the real `plutil`, so CI on Linux has been red since bc09f24f

**Status:** LANDED 2026-11-11 — test stub for `plutil` (Claude, test-only); CI confirmation pending
**Priority:** P1
**Waiting on:** live check — since 2026-11-11 (CI green on the release branch)
**Severity:** CI red on every push to `k3d-manager-v1.43.15` since 2026-11-11 17:13Z. `make hub-promote` refuses commits without green checks, so no commit after `bc09f24f` could be promoted (blocks today's promote of the Keycloak, hub-promote and frontend-pin fixes). No product effect.
**Introduced by:** `bc09f24f` (K3DM_AGENT_LOAD=0 fix, new `scripts/tests/bin/makefile_agent_load.bats`)
**Should have been caught by:** review (the fix was landed and marked VERIFIED on local macOS runs; its own CI runs were cancelled by newer pushes and nobody checked a completed run)
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run (vector store context missing on the M4).
**Approval:** Claude, 2026-11-11 (found when the operator asked about three "Run failed: CI" emails)
**Filed:** 2026-11-11

## What happened

`lint` job, `make test-bin`: `not ok 884/889 E1` and `not ok 885/890 E2` in `makefile_agent_load.bats`, with
`/bin/bash: line 1: plutil: command not found` / `make[1]: *** [Makefile:819: install-cloud-bridge] Error 127`
(runs 43066090583 on `dfc35911` through 43087050057 on `d0a93399`; the only failing tests). `install-cloud-bridge` runs
`plutil -lint` (`Makefile:831`), a macOS-only tool; the test stubs `launchctl`, `security`, `git` and `id`, not `plutil`.

## Fix

The test now puts a `plutil` stub first on PATH (output captured from the real `plutil -lint` on m4-air, macOS 26.5.2) and
asserts `command -v plutil` resolves to it. Proof on m4-air with a `plutil` that exits 127 first on PATH (simulating Linux):
the old test file fails E1 and E2 with `plutil: command not found`; the new file passes both, and passes with the real PATH.

## Lesson

A "VERIFIED" mark needs a completed CI run on the landed commit (or a later one), not only local runs: macOS-only tools
pass locally and fail on the Linux runner.
