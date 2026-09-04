# Dispatcher `deploy_*` guard: signal confirmation via `K3DM_DEPLOY_CONFIRMED`

**Filed:** 2026-08-29
**Area:** `scripts/k3d-manager` (`__k3dm_deploy_guard_args`); `scripts/plugins/shopping_cart.sh` (`deploy_app_cluster`)
**Type:** bugfix
**Resolves:** `docs/issues/2026-08-21-dispatcher-strips-confirm-deploy-app-cluster.md` (Finding 2b)

## Problem

The dispatcher's shared `deploy_*` guard (`__k3dm_deploy_guard_args`) consumes and strips
`--confirm`/`-y`/`--yes` from the argument list before the plugin function runs. It sets a
`confirm=1` local but never signals that decision downstream. `deploy_app_cluster` then
independently re-checks `--confirm` as its own `${1}`, which is gone, so
`scripts/k3d-manager deploy_app_cluster --confirm` aborts with
`deploy_app_cluster requires --confirm`.

## Fix (issue option 1 — additive, zero blast radius)

The guard keeps stripping `--confirm` exactly as today; it ALSO sets a shell global
`K3DM_DEPLOY_CONFIRMED` (`1` when a confirm flag was seen, `0` otherwise). Consumers honor
that flag instead of re-parsing `--confirm`. Only `deploy_app_cluster` is updated in this
patch — every other in-tree `deploy_*` continues to work unchanged, and the flag is now
available for future adopters.

The five other `--confirm`-as-`$1` sites are all private
`_provider_*_destroy_cluster` helpers in `scripts/lib/` subtrees — NOT `deploy_*` dispatch
entry points, so the guard never touches them and they are out of scope here (subtree,
edit-upstream-first).

### 1. `scripts/k3d-manager` — `__k3dm_deploy_guard_args`

After the arg sweep, publish the decision as a global before returning:

```bash
K3DM_DEPLOY_CONFIRMED="${confirm}"
__K3DM_DEPLOY_SANITIZED_ARGS=("${sanitized[@]}")
```

(Plain global, not `export` — `deploy_*` runs in-process as a function call, and a plain
global avoids leaking the flag into child processes the deploy function may spawn.)

### 2. `scripts/plugins/shopping_cart.sh` — `deploy_app_cluster`

Honor the guard flag OR the direct `--confirm` (so the lib-sourcing wrapper path and a
direct in-process call both still work):

```bash
  if [[ "${1:-}" != "--confirm" && "${K3DM_DEPLOY_CONFIRMED:-0}" != "1" ]]; then
    _err "[shopping_cart] deploy_app_cluster requires --confirm to prevent accidental runs"
    return 1
  fi
```

## Constraints

- Minimal patch: guard gains one assignment line; `deploy_app_cluster` gate gains one
  `&&` clause. No other behavior change. Keep `${var}` quoting, indentation, LF, no inline
  comments.
- Do NOT touch `scripts/lib/` or `scripts/lib/acg/` subtrees.
- The guard still exits on the un-confirmed, no-args invocation exactly as before.

## BATS (`scripts/tests/deploy_confirm_flag.bats`, pure logic — no cluster)

Source `scripts/k3d-manager`? No — it runs the dispatcher. Instead unit-test the two
observable contracts by extracting the predicate logic:

1. Guard sets `K3DM_DEPLOY_CONFIRMED=1` when `--confirm` (and `-y`, `--yes`) present, `0`
   otherwise. (Re-implement the sweep in the test, or assert via a thin harness sourcing
   the function.)
2. `deploy_app_cluster` confirm-gate predicate: passes when `${1}=="--confirm"`; passes
   when `K3DM_DEPLOY_CONFIRMED=1` and `$1` empty; fails when neither.

Keep it pure (no `kubectl`, no `k3sup`, no live cluster) — mirror
`scripts/tests/observability_keep_list.bats` sourcing style.

## Live verification — CLAUDE ONLY (out of band, app cluster)

`scripts/k3d-manager deploy_app_cluster --confirm` reaches the confirmed path (does not
abort at the gate); the bare `scripts/k3d-manager deploy_app_cluster` still hits the
guard's safety-gate usage exit.

## Out of scope

Adopting `K3DM_DEPLOY_CONFIRMED` in the subtree `_provider_*_destroy_cluster` helpers
(they are not guard-gated) and any other `deploy_*` function that does not re-parse
`--confirm`.
