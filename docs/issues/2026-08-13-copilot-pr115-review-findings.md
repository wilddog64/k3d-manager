# Copilot PR #115 Review Findings — v1.24.1

**PR:** #115 — `feat: v1.24.1 — concise provider-aware cluster status + Slack summary`
**Fix commit:** `68fe1b88`
**Date:** 2026-08-13

Three findings, one security + two doc-staleness. All addressed.

## 1. Makefile — `SERVICE` shell injection (line 50, 57)

**Finding:** `SERVICE` was interpolated unquoted into the `status` / `status-json`
recipes, allowing shell injection (`make status SERVICE='x; rm -rf /'`).

**Before:**
```make
bin/cluster-status --summary $(if $(SERVICE),--service $(SERVICE),)
```

**After:**
```make
bin/cluster-status --summary $(if $(SERVICE),--service "$(SERVICE)",)
```

**Verify:** `make -n status SERVICE='x; touch /tmp/INJECTED'` now renders
`--service "x; touch /tmp/INJECTED"` — a single quoted argument, no injection.

**Root cause:** New Make recipe added a passthrough flag without quoting the
interpolated value — violates the CLAUDE.md shell-injection rule (always
double-quote variable expansions).

## 2. docs/roadmap.md — stale pre-rename branch/doc references

**Finding:** The v1.24.1 milestone bullet still pointed at the pre-rename
`k3d-manager-v1.25.0` branch and old `v1.25.0-*` doc paths.

**Fix:** Repointed to `k3d-manager-v1.24.1` (PR #115) and the `v1.24.1-*` doc paths.

**Root cause:** The branch rename + doc renumbering (v1.25.0 → v1.24.1) did not
sweep the roadmap's own milestone-scope references.

## 3. docs/plans/v1.24.1-status-output-contract.md — stale status line

**Finding:** Plan header said "SCOPED — implementation not started" while the PR
ships the full implementation.

**Fix:** Header now reads "IMPLEMENTED — shipped on `k3d-manager-v1.24.1` (PR #115)".

**Root cause:** Living-contract plan doc header not updated when implementation landed.

## Process note

Doc-rename sweeps must include `docs/roadmap.md` milestone-scope references and the
plan doc's own status header — both are living documents that lag a rename unless
explicitly checked. New Make passthrough flags carrying user input must be quoted at
authoring time (same rule as shell `"$var"`).
