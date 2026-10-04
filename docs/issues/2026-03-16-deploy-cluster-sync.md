# Issue: deploy_cluster Helpers Diverged Between k3d-manager and lib-foundation

**Date identified:** 2026-03-16  
**Functions:** `deploy_cluster`, `_deploy_cluster_prompt_provider`, `_deploy_cluster_resolve_provider`

---

## Problem

k3d-manager refactored `deploy_cluster` with helper extraction and bug fixes, but
lib-foundation never received those changes. Missing pieces:
- `_deploy_cluster_prompt_provider` helper (interactive selection loop duplicated inline)
- `_deploy_cluster_resolve_provider` helper (CLI/env/force/interactive logic inline)
- Duplicate mac+k3s guard
- `CLUSTER_NAME` positional arg propagation

Downstream consumers relying on lib-foundation lacked these fixes.

## Fix

- Added `_deploy_cluster_prompt_provider` and `_deploy_cluster_resolve_provider`
  before `deploy_cluster` (matching k3d-manager implementation).
- Replaced `deploy_cluster` body to use helpers, removed duplicate mac+k3s check,
  and propagated `CLUSTER_NAME` from positional arg.

## Verification

- `shellcheck scripts/lib/core.sh`
- `AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh scripts/lib/core.sh`
- `env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" HOME="$HOME" TMPDIR="$TMPDIR" \
  bash --norc --noprofile -c 'bats scripts/tests/lib/system.bats scripts/tests/lib/core.bats scripts/tests/lib/agent_rigor.bats'`

## Status

Fixed on `feat/v0.3.2` (commit `e2055d6`).
