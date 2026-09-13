# Bug: `bin/smoke-test-cluster-health` exits 1 silently on the live hub (stale defaults + `_kubectl` hard exit)

**Filed:** 2026-09-13
**Branch:** `k3d-manager-v1.33.0`
**Status:** READY FOR CODEX

---

## Problem

The live smoke run on 2026-09-13 printed only section headers and exited `rc=1` with no `[FAIL]` line and no `=== Result` summary. The cluster itself was healthy: `bin/smoke-test-webhook --require-all-ok` passed 13/13, and direct `kubectl` showed the pull secrets, Synced apps and Running pods.

There are three causes:

1. **`_kubectl` without `--no-exit` kills the script.** `_run_command` exits the whole shell when the command fails, unless `--no-exit` is passed. The `if _kubectl ...; then` and `$(_kubectl ... || echo NotFound)` fallbacks never run. Reproduced: with `--no-exit`, `$(_kubectl --no-exit --quiet -- ... get application missing ... || echo NotFound)` yields `NotFound` and the script continues.
2. **Stale default app context.** `APP_CONTEXT` defaults to `ubuntu-k3s`. That context no longer exists; the live app cluster context is `ubuntu-hostinger`.
3. **Stale ArgoCD app names.** The script checks `shopping-cart-basket` and the other four without a prefix. The live hub names are `ubuntu-k3s-shopping-cart-basket`, `ubuntu-k3s-shopping-cart-order`, `ubuntu-k3s-shopping-cart-payment`, `ubuntu-k3s-shopping-cart-product-catalog` and `ubuntu-k3s-shopping-cart-frontend`.

## Fix

### Before You Start

- `git pull origin k3d-manager-v1.33.0`; read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- Read `bin/smoke-test-cluster-health` in full (97 lines).
- Read `scripts/lib/system.sh` `_kubectl` (around line 926), and how `_run_command` handles `--no-exit`. Read only; do NOT edit `system.sh`.

### S1 — header comment block (lines 12-16)

Old:

```bash
#   INFRA_CONTEXT      kubectl context for infra cluster (default: k3d-k3d-cluster)
#   APP_CONTEXT        kubectl context for app cluster   (default: ubuntu-k3s)
#   ARGOCD_NAMESPACE   namespace ArgoCD runs in          (default: cicd)
```

New:

```bash
#   INFRA_CONTEXT      kubectl context for infra cluster (default: k3d-k3d-cluster)
#   APP_CONTEXT        kubectl context for app cluster   (default: ubuntu-hostinger)
#   ARGOCD_NAMESPACE   namespace ArgoCD runs in          (default: cicd)
#   ARGOCD_APP_PREFIX  prefix of the per-cluster ArgoCD apps (default: ubuntu-k3s-)
```

### S2 — defaults (around lines 25-27)

Old:

```bash
APP_CONTEXT="${APP_CONTEXT:-ubuntu-k3s}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-cicd}"
```

New:

```bash
APP_CONTEXT="${APP_CONTEXT:-ubuntu-hostinger}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-cicd}"
ARGOCD_APP_PREFIX="${ARGOCD_APP_PREFIX-ubuntu-k3s-}"
```

`ARGOCD_APP_PREFIX` uses `-` (not `:-`) on purpose, so an explicitly empty `ARGOCD_APP_PREFIX=""` is kept (test 4). `APP_CONTEXT` keeps `:-`.

### S3 — every `_kubectl --quiet --` call gets `--no-exit`

All 6 call sites (lines 45, 58, 73, 74, 77, 78) change from `_kubectl --quiet -- ` to `_kubectl --no-exit --quiet -- `. Nothing else on those lines changes.

### S4 — ArgoCD app lookup uses the prefix (line 58)

Old:

```bash
  sync_status=$(_kubectl --quiet -- --context="${INFRA_CONTEXT}" get application "${app}" \
```

New:

```bash
  sync_status=$(_kubectl --no-exit --quiet -- --context="${INFRA_CONTEXT}" get application "${ARGOCD_APP_PREFIX}${app}" \
```

Keep the `for app in shopping-cart-basket ...` list and the `_pass "${app}: Synced"` / `_fail` messages as they are.

### Tests — new `scripts/tests/bin/smoke_test_cluster_health.bats`

Put a stub `kubectl` executable on `PATH` in a `BATS_TEST_TMPDIR` dir. It reads env vars to decide its behaviour and appends its args to a call-log file. No real cluster.

1. **All healthy:** `get secret` exits 0; `get application` prints `Synced`; `get pods` prints 3 `Running` lines for `shopping-cart-apps` and 2 for `shopping-cart-payment`. Assert rc 0 and that output contains `11 passed, 0 failed`.
2. **Defaults:** with `APP_CONTEXT`, `INFRA_CONTEXT` and `ARGOCD_APP_PREFIX` unset, run the healthy stub. Assert the call log contains `--context=ubuntu-hostinger` and `ubuntu-k3s-shopping-cart-basket`, and does not contain `--context=ubuntu-k3s `.
3. **kubectl failure is reported, not silent:** the stub exits 1 on every call. Assert rc 1, output contains `=== Result:`, and output contains `NotFound (expected Synced)`.
4. **Override:** with `ARGOCD_APP_PREFIX=""`, the call log contains `get application shopping-cart-basket`.

Assert on tokens, not whole source lines.

## Definition of Done

- [ ] S1-S4 implemented exactly; only `bin/smoke-test-cluster-health`, the new BATS file and `CHANGELOG.md` changed
- [ ] `grep -c '_kubectl --quiet --' bin/smoke-test-cluster-health` outputs `0`, and `grep -c '_kubectl --no-exit --quiet --' bin/smoke-test-cluster-health` outputs `6`
- [ ] `shellcheck -x bin/smoke-test-cluster-health` — rc 0
- [ ] `bats scripts/tests/bin/smoke_test_cluster_health.bats` green — paste the summary
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "`bin/smoke-test-cluster-health` defaults to the live `ubuntu-hostinger` context and `ubuntu-k3s-` ArgoCD app names, and reports kubectl failures instead of exiting 1 silently"
- [ ] Commit message verbatim: `fix(smoke): cluster-health gate uses live context/app names and no longer exits silently`
- [ ] Pushed to `origin/k3d-manager-v1.33.0`; report the SHA

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, or any file outside the targets
- Do NOT replace `_kubectl` with bare `kubectl` in the script
- Do NOT run anything against a live cluster
