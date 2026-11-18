# Stall detection scans only the highest `v*` directory, so project tasks are never sampled

**Status:** OPEN — captured 2026-11-18 from Argon's blind review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — monitoring gap for project dispatches
**Introduced by:** 6972d10a (codex-dispatch multi-project M1, k3d-manager-v1.44.2)
**Should have been caught by:** spec
**Introducing change reviewed:** no
**Waiting on:** operator decision
**Prior art:** docs/bugs/2026-11-17-stall-watch-ledger-events-lack-project.md (keyword) — read, different root cause (ledger field, not the scan). Exact slug: no match. `make find-similar-docs` not run (vector store unreachable).
**Filed:** 2026-11-18

## Symptom

`_dispatch_stalled` (`bin/k3dm-codex-dispatch:1237`) and `bin/k3dm-dispatch-stall-watch:87` pick the newest `v*`
directory by `sort -V` and scan only that one. dirused tasks live under `v0.0.x`, which never sorts above the
k3d-manager release (`v1.44.x`), so a stalled dirused run is never flagged.

## Impact

A stalled project dispatch is only noticed by hand. k3d-manager tasks are unaffected.

## Fix sketch

Scan every `v*` directory that holds a task without `exit`/`landed`, not just the newest. Test: a stalled task under
`v0.0.3` while `v1.44.2` exists is reported; a finished one there is not (control).

## Fable confirmation (2026-11-18)

Fable (blind diff review, same PR) reproduced this in a scratch root and rated it high: a live-pid task in `v0.0.5` with an empty `v1.44.2/` beside it printed nothing from `stalled --live`. The reverse case is `docs/bugs/2026-11-18-codex-dispatch-project-version-above-release-hides-k3d-manager-tasks.md`.
