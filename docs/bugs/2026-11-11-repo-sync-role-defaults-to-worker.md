# repo-sync treats a missing machine-role file as worker (fails open)

**Status:** OPEN — found 2026-11-11 by the Fable pre-PR review of v1.43.15; confirmed by Claude by reading
**Priority:** P3
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (Degraded fail-open fallback that only triggers if the `machine-role` config file is lost, with keeping or restoring the file serving as a simple workaround); Claude proposed P3. Higher stands until the operator decides.
**Triage:** carry → v1.44.0 (deploy/hub batch) — grooming 2026-11-12, operator. Priority: operator kept Claude's P3 over Argon's P2.
**Waiting on:** dispatch — since 2026-11-12
**Introduced by:** `f310b4d4` (v1.43.15 checkout-auto-sync)
**Should have been caught by:** review
**Prior art:** none above threshold — exact-slug glob empty; `find-similar-docs` unavailable (vector store context missing)
**Approval:** pending

## Symptom and root cause

`bin/k3dm-repo-sync:82-87` `role()` returns `worker` when `~/.config/k3d-manager/machine-role` cannot be read. On a hub
that lost the file, the timer fast-forwards the k3d-manager checkout to its upstream release branch, past `deploy/hub`,
and pushes no hub metrics. `bin/k3dm-require-role` treats the same case as `missing` and fails closed.

## Impact

Needs the file lost after `bin/k3dm-machine-setup` wrote it (fresh HOME, restore, other `XDG_CONFIG_HOME`). Then the
hub checkout runs unpromoted code silently. Workaround: none needed while the file exists.

## Fix direction

Return `missing` and skip the k3d-manager checkout with a logged error, as `bin/k3dm-require-role` does.
