# A project version directory above the k3d-manager release hides every k3d-manager task from `status` and `stalled`

**Status:** OPEN — captured 2026-11-18 from Fable's blind diff review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — latent; dirused versions are v0.0.x
**Introduced by:** 6972d10a (codex-dispatch multi-project M1, k3d-manager-v1.44.2)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (Argon, missed)
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Latent version-sorting defect where a project version higher than k3d-manager's release hides k3d-manager tasks in `status` and `stalled`.)
**Waiting on:** operator decision
**Prior art:** docs/bugs/2026-11-18-dispatch-stall-scan-skips-project-version-dirs.md — read; same helper, opposite direction (that one hides project tasks). `make find-similar-docs` not run (vector store unreachable).
**Filed:** 2026-11-18

## Symptom

`_dispatch_status` (`bin/k3dm-codex-dispatch:1258`) and `_dispatch_stalled` (`:1236`) walk only
`_dispatch_latest_version_dir` (`:1229`, highest `v*` by `sort -V`). Before M1 every directory was a k3d-manager release;
now a project directory can sort higher. Fable reproduced it in a scratch root: after `start --project dirused --version
v2.0.0`, `status` omitted the k3d-manager task in `v1.44.2` and printed the project task twice (once from each loop).

## Impact

Latent: dirused tags are v0.0.x. Any registered project at v1.45+ (or a `--version` above the release) blinds status and
stall detection for k3d-manager dispatches.

## Fix sketch

Walk the release version for k3d-manager tasks and each project's own version dirs separately (shared fix with the
stall-scan doc). Test: `v2.0.0` project dir plus `v1.44.2` k3d-manager task → both listed once.
