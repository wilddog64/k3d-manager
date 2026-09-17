# Bug: `bin/smoke-test-cluster-health` checks pods on a different cluster than the ArgoCD apps it checks

**Filed:** 2026-09-13
**Branch:** `k3d-manager-v1.33.0`
**Status:** FIXED (APP_CONTEXT → INFRA_CONTEXT; CHANGELOG v1.33.0)

---

## Problem

`77008edb` (spec `2026-09-13-smoke-test-cluster-health-stale-defaults-silent-exit.md`) changed the `APP_CONTEXT` default to `ubuntu-hostinger`. That default is still wrong for the live topology. As a result, the gate's 9/9 PASS does not prove the hub's shopping-cart pods are healthy.

Live read-only checks on 2026-09-13:

- The hub has one app-cluster registration: `cicd/ubuntu-k3s-app-cluster`, name `ubuntu-k3s`, server `https://kubernetes.default.svc`. The hub is its own app cluster.
- The apps the script checks, `ubuntu-k3s-shopping-cart-*`, have destination `{"name":"ubuntu-k3s"}`. Their pods run on hub nodes (`k3d-k3d-cluster-agent-2`), carrying label `argocd.argoproj.io/instance=ubuntu-k3s-shopping-cart-basket`. `ghcr-pull-secret` exists on the hub in all three namespaces.
- `ubuntu-hostinger` also runs shopping-cart pods. Their tracking id is `ubuntu-hostinger-shopping-cart-basket`, and no Application with that name exists on the hub. The script never checks those apps.

Section 2 (ArgoCD sync) reads the hub apps. Sections 1 (pull secrets) and 3 (pods) read `ubuntu-hostinger`. A hub pod crash-loop passes the gate as long as hostinger stays up.

## Fix

The pod and secret checks must target the cluster the checked apps deploy to. The hub is its own app cluster, so `APP_CONTEXT` defaults to `INFRA_CONTEXT`. An explicit `APP_CONTEXT` still wins.

### Before You Start

- `git pull origin k3d-manager-v1.33.0`; read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- Read `bin/smoke-test-cluster-health` in full (99 lines).
- Read `scripts/tests/bin/smoke_test_cluster_health.bats` in full.

### S1 — header comment (line 15)

Old:

```bash
#   APP_CONTEXT        kubectl context for app cluster   (default: ubuntu-hostinger)
```

New:

```bash
#   APP_CONTEXT        kubectl context for app cluster   (default: $INFRA_CONTEXT — the hub is its own app cluster)
```

### S2 — default (line 27)

Old:

```bash
APP_CONTEXT="${APP_CONTEXT:-ubuntu-hostinger}"
```

New:

```bash
APP_CONTEXT="${APP_CONTEXT:-${INFRA_CONTEXT}}"
```

Line 26 (`INFRA_CONTEXT=...`) already comes before it; keep that order. Nothing else in the script changes.

### Tests — `scripts/tests/bin/smoke_test_cluster_health.bats`

1. **Replace test 2's body.** Rename test 2 to `defaults check pods on the infra context and use prefixed ArgoCD names`. With the defaults, assert:
   - status 0
   - `grep -E -- '--context=k3d-k3d-cluster get pods' "${KUBECTL_CALL_LOG}"` succeeds
   - `grep -E -- '--context=k3d-k3d-cluster get secret ghcr-pull-secret' "${KUBECTL_CALL_LOG}"` succeeds
   - `grep -F -- 'ubuntu-k3s-shopping-cart-basket' "${KUBECTL_CALL_LOG}"` succeeds
   - `grep -F -- 'ubuntu-hostinger' "${KUBECTL_CALL_LOG}"` fails

   Before writing the regexes, check how `_kubectl` passes the arguments by looking at the call-log line format in a run. If a separator such as `--` appears between `--context=...` and `get`, adjust the regex to allow it (for example `--context=k3d-k3d-cluster( --)? get pods`). Do not weaken the assertion to the context alone.
2. **New test `INFRA_CONTEXT override flows to pod checks when APP_CONTEXT is unset`.** Set `INFRA_CONTEXT=hub-x`. Assert status 0, a `get pods` call with `--context=hub-x`, and no `k3d-k3d-cluster` anywhere in the call log.
3. **New test `explicit APP_CONTEXT is honored for pods and secrets`.** Set `APP_CONTEXT=remote-y`. Assert status 0, `get pods` and `get secret` calls use `--context=remote-y`, and `get application` still uses `--context=k3d-k3d-cluster`.

Assert on tokens, not whole source lines. Leave tests 1, 3 and 4 unchanged.

## Definition of Done

- [ ] S1-S2 implemented exactly; only `bin/smoke-test-cluster-health`, `scripts/tests/bin/smoke_test_cluster_health.bats` and `CHANGELOG.md` changed
- [ ] `grep -c 'ubuntu-hostinger' bin/smoke-test-cluster-health` outputs `0`
- [ ] `shellcheck -x bin/smoke-test-cluster-health`: rc 0
- [ ] `bats scripts/tests/bin/smoke_test_cluster_health.bats` green (6 tests); paste the summary
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "`bin/smoke-test-cluster-health` checks pull secrets and pods on the same cluster its ArgoCD apps deploy to (`APP_CONTEXT` defaults to `INFRA_CONTEXT`, since the hub is its own app cluster)"
- [ ] Commit message verbatim: `fix(smoke): cluster-health pod checks target the hub the checked apps deploy to`
- [ ] Pushed to `origin/k3d-manager-v1.33.0`; `git rev-parse origin/k3d-manager-v1.33.0` equals the commit SHA; report the SHA

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, or use `--no-verify`
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, `Makefile`, or any file outside the targets
- Do NOT replace `_kubectl` with bare `kubectl`
- Do NOT run anything against a live cluster
- Do NOT use `grep -F` on whole source lines
