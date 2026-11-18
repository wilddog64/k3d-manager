# `codex-dispatch start --project` uses the branch name as the version for a `scheme=branch` project

**Status:** OPEN — captured 2026-11-18 from Argon's blind review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — latent; no registered project uses `scheme=branch` today
**Introduced by:** 6972d10a (codex-dispatch multi-project M1, k3d-manager-v1.44.2)
**Should have been caught by:** spec
**Introducing change reviewed:** no
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-18

## Symptom

For a project registered with `scheme=branch`, `start` sets `version` to the project's `branch` field
(`bin/k3dm-codex-dispatch:1011`), for example `main`. The worktree goes under `<root>/main/`, but every reader that
walks versions (`_dispatch_resolve_version` `:58`, `_dispatch_status`, `_dispatch_stalled`, stall-watch) globs `v*`
or matches `^v[0-9]+\.`, so the task is invisible to `status`, `resume`, `land` without `--version`, and the stall scan.

## Impact

None today: the only registered non-k3d-manager project (dirused) uses `scheme=tag`. The first `scheme=branch`
project would dispatch, then vanish from every reader.

## Fix sketch

Either map `scheme=branch` to a `v`-prefixed directory, or teach the readers a project-version directory list.
Test: register a `scheme=branch` project in a scratch registry, `start`, then `status <slug>` shows it (positive control:
the `scheme=tag` case already passes).
