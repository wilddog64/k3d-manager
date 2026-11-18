# `codex-dispatch status` shows a running project task as `state: unknown`

**Status:** OPEN — captured 2026-11-18 from Argon's blind review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — display only
**Introduced by:** 6972d10a (codex-dispatch multi-project M1, k3d-manager-v1.44.2)
**Should have been caught by:** offline test
**Introducing change reviewed:** no
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-18

## Symptom

The second loop of `_dispatch_status` (`bin/k3dm-codex-dispatch:1300-1310`), which lists non-k3d-manager project
tasks, starts with `state=unknown` and only upgrades to `landed` or `exited (<rc>)`. It never checks for a live
process, so a running dirused task prints `state: unknown`. The first loop (k3d-manager tasks) reports `running`
correctly.

## Impact

Operator reads `unknown` for a task that is working; Claude counts WIP from `open`, which is unaffected.

## Fix sketch

Reuse the first loop's running check (pid file / process probe) in the second loop. Test: a project task with a live
pid and no `exit` shows `state: running`; with `exit` present it shows `exited (0)` (control).
