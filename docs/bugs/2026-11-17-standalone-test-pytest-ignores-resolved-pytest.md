# Bug: standalone `make test-pytest` ignores `K3DM_RESOLVED_PYTEST`

**Status:** OPEN
**Priority:** P3 — hygiene; the two entry points can pick different pytest interpreters, with a workaround (`PYTEST=`).
**Introduced by:** 46ec5b36 (v1.44.0, `docs/plans/v1.44.0-parallel-offline-tests.md`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Test-runner hygiene issue where standalone `make test-pytest` ignores `K3DM_RESOLVED_PYTEST`, with a workaround of setting `PYTEST=`.)
**Waiting on:** operator decision
**Prior art:** `docs/bugs/2026-09-25-pytest-suites-unreachable-from-make.md` (exact-slug pass; `find-similar-docs` not run, no k3d-k3d-cluster context on the M4) — read, different root cause (suites not wired into make at all)
**Filed:** 2026-11-17 (found by the Part B independent verifier, 2026-11-15)

## What happened

`test-all` resolves pytest once and exports `K3DM_RESOLVED_PYTEST` so every stage uses the same interpreter (`Makefile:1747`, `1770`, `1889-1908`). The standalone `test-pytest` target (`Makefile:1629-1647`) has its own resolution chain (`PYTEST`, `pytest` on PATH, `python3 -m pytest`, pyenv shim) and never reads `K3DM_RESOLVED_PYTEST`. A caller that exports the resolved command (as `test-all` does for its children) still gets `test-pytest`'s own pick, which can be a different Python on a host with several.

## Fix

In `test-pytest`, check `K3DM_RESOLVED_PYTEST` first, before `PYTEST`, matching `Makefile:1889`. One branch added; nothing else changes.

## Acceptance

```yaml
must:
  - id: M1
    text: make test-pytest uses K3DM_RESOLVED_PYTEST when it is set, ahead of PYTEST and PATH
must_not:
  - id: N1
    text: with K3DM_RESOLVED_PYTEST pointing at a stub, test-pytest runs a different pytest (red today)
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: make test-pytest with K3DM_RESOLVED_PYTEST set to a recording stub (scratch dir) and PYTEST unset; positive control — unset, the existing chain still runs
    intent: "You will see the standalone pytest target use the same pytest that test-all chose, and fall back to its usual search when nothing was chosen."
interface: none
```

**Intent approved:** operator, 2026-11-17 ("approved")
