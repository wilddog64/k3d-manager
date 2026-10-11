# Bug: `make appsets-reapply` fails its own confirmation before ArgoCD regenerates the Applications

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** FIXED `8bd03a4f` 2026-10-09 (Codex via parallel worktree dispatch; Claude fixed first-check output, timing validation, if-count refactor; 6/6 BATS, 2 mutations red)
**Priority:** P3 — false failure on a required release step; the real state is correct
**Severity:** low

## Symptom

First reapply on `k3d-manager-v1.43.0`, right after the v1.42.0 release:

```
INFO: [argocd] Successfully deployed 13/13 ApplicationSet(s)
INFO: [argocd] Confirming values-branch pin (k3d-manager-v1.43.0)
WARN: [argocd] Applications on a stale values branch:
  acg-kube-prometheus-stack k3d-manager-v1.42.0
  acg-trivy-operator k3d-manager-v1.42.0
  loki k3d-manager-v1.42.0
make: *** [appsets-reapply] Error 1
```

`make appsets-check` run straight after it reported
`All Applications reference values branch k3d-manager-v1.43.0`.

## Cause

`deploy_argocd_applicationsets` (`scripts/plugins/argocd.sh`, the verify block after
`_argocd_deploy_applicationsets`) calls `argocd_check_values_branch` once, immediately after the
`kubectl apply`. The ApplicationSet controller regenerates the Applications asynchronously, so
the first read can still show the previous branch. One read and no wait turns that lag into a hard
failure. The earlier bug doc `2026-09-30-release-config-inert-until-applicationsets-reapplied.md`
already names this reconcile lag for the drift sensor. The confirmation step added later does
not allow for it.

## Fix

In the verify block, retry `argocd_check_values_branch` until it passes or a bounded timeout
expires. Do not loosen the check itself.

- `K3DM_APPSET_CONFIRM_TIMEOUT` (default `90` seconds) and `K3DM_APPSET_CONFIRM_INTERVAL`
  (default `5` seconds).
- Retries print one `_info` line each, such as
  `[argocd] waiting for ApplicationSet controller to regenerate Applications (Ns/90s)`, with the
  check's own output suppressed while retrying.
- The last attempt runs unsuppressed, so if it still fails the operator sees the stale list and
  the function returns 1, exactly as today.
- `appsets-check` (`argocd_check_values_branch` called directly) stays a single read-only pass.

## Tests

New `scripts/tests/plugins/argocd_appset_reapply_confirm_wait.bats`. Stub `argocd_check_values_branch`
and `sleep`, and stub `_argocd_deploy_applicationsets` to return 0:

1. Fails twice, then passes: `deploy_argocd_applicationsets` returns 0, and the stub was called 3 times.
2. Always fails, with timeout 10 and interval 5: returns 1, and the stale list from the last call is in the output.
3. Passes first time: called once, no wait line.
4. `--no-verify`: never called.
5. DRY_RUN: never called (the existing message is kept).

Mutation check: remove the retry loop. Test 1 must go red.

## Docs

`docs/howto/makefile.md`, `appsets-reapply` row: say that the confirmation waits up to 90s for
the controller, and name the two env vars.

## Files

| File | Change |
|---|---|
| `scripts/plugins/argocd.sh` | bounded retry in `deploy_argocd_applicationsets`'s verify block |
| `scripts/tests/plugins/argocd_appset_reapply_confirm_wait.bats` | new |
| `docs/howto/makefile.md` | `appsets-reapply` row |

## Rules

- `shellcheck scripts/plugins/argocd.sh`: no new warnings.
- `bats scripts/tests/plugins/argocd_appset_reapply_confirm_wait.bats`: all green. Paste the output.
- Do not commit. `.git` is read-only in the sandbox.
