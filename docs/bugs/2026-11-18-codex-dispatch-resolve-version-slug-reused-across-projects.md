# `_dispatch_resolve_version` resolves a slug reused in k3d-manager and a project to the project version

**Status:** OPEN — captured 2026-11-18 from Argon's blind review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — edge case; slugs are unique by convention
**Introduced by:** 6972d10a (codex-dispatch multi-project M1, k3d-manager-v1.44.2)
**Should have been caught by:** review
**Introducing change reviewed:** no
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Edge-case version resolution flaw when a task slug is reused across k3d-manager and another project, avoidable by unique slugs or passing `--version`.)
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-18

## Symptom

`_dispatch_resolve_version` (`bin/k3dm-codex-dispatch:58`) skips every directory whose `.run/project` is
`k3d-manager`, so when the same slug exists in a k3d-manager release and a project version, it finds one match (the
project) and returns it without the "pass --version" error. A `resume` or `land` meant for the k3d-manager task acts
on the project task.

## Impact

Needs a slug reused across repos; none exist today.

## Fix sketch

Count the k3d-manager match too and refuse when there is more than one candidate. Test: same slug in `v1.44.2`
(k3d-manager) and `v0.0.3` (dirused) → error naming `--version`; slug only in `v0.0.3` → resolves (control).

## Fable confirmation (2026-11-18)

Fable reproduced it: `a1` in `v0.0.11` (dirused) and `v1.44.2`, `abandon --slug a1` → `would record: abandon v0.0.11/a1`. The same resolver serves `land`, `resume`, `verify` and `handoff`.
