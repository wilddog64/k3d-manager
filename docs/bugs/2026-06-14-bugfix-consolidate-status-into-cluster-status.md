# Bugfix: v1.7.1 — consolidate status into one provider-aware `bin/cluster-status`

**Branch:** `k3d-manager-v1.7.1`
**Files:** `bin/cluster-status`, `Makefile`, `bin/k3dm-webhook`, **delete** `bin/hostinger-status`

---

## Problem

There are two parallel status scripts. `bin/cluster-status` is already provider-aware
(`_acg_resolve_provider` + `_acg_provider_context`, AWS-creds section already gated) and is the
richer of the two — it has the `Service Health` section (per-endpoint HTTP + ESO ClusterSecretStore
+ ESO ExternalSecrets via webhook `/api/v1/health`). `bin/hostinger-status` is a thinner
duplicate that omits Service Health/ESO but adds two sections cluster-status lacks: **API Health**
(`/healthz` on the app context) and **Hub ArgoCD Registration** (the `cluster-<context>` secret).

`make status CLUSTER_PROVIDER=k3s-hostinger` routes to `bin/hostinger-status`, so the Hostinger
report has no endpoint/ESO health. The fix is **not** to enhance the duplicate — it is to fold the
two useful sections into `bin/cluster-status`, make it the single status tool for all providers,
and delete `bin/hostinger-status`.

**Root cause:** duplication. `bin/cluster-status` is already provider-aware; `ubuntu-hostinger` is
resolved correctly for `k3s-hostinger` (verified: `_acg_provider_context k3s-hostinger` →
`ubuntu-hostinger`). Only the unconditional `Tunnel` section is hostinger-hostile (Hostinger uses a
direct kubeconfig, no SSH tunnel on `localhost:6443`).

---

## Reproduction

```bash
make status CLUSTER_PROVIDER=k3s-hostinger   # → bin/hostinger-status: no endpoint/ESO health
```

After: `make status CLUSTER_PROVIDER=k3s-hostinger` runs `bin/cluster-status`, skips the SSH-tunnel
section, and shows API Health + Hub ArgoCD Registration + Service Health (endpoints + ESO).

---

## Fix

### Change 1 — `bin/cluster-status`: add `ARGOCD_NAMESPACE` var

**Exact old block (lines 22–23):**
```bash
APP_CONTEXT="${APP_CONTEXT:-$(_acg_provider_context "${CLUSTER_PROVIDER}")}"
INFRA_CONTEXT="${INFRA_CONTEXT:-k3d-k3d-cluster}"
```
**Exact new block:**
```bash
APP_CONTEXT="${APP_CONTEXT:-$(_acg_provider_context "${CLUSTER_PROVIDER}")}"
INFRA_CONTEXT="${INFRA_CONTEXT:-k3d-k3d-cluster}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-cicd}"
```

### Change 2 — `bin/cluster-status`: gate the Tunnel section to tunneled providers only

**Exact old block (lines 34–40):**
```bash
echo ""
echo "=== Tunnel ==="
if curl -sf --max-time 3 http://localhost:6443 >/dev/null 2>&1; then
  echo "SSH tunnel: UP (port 6443 reachable)"
else
  echo "SSH tunnel: DOWN (port 6443 not reachable)"
fi
```
**Exact new block:**
```bash
case "${CLUSTER_PROVIDER}" in
  k3s-aws|k3s-gcp|k3s-az)
    echo ""
    echo "=== Tunnel ==="
    if curl -sf --max-time 3 http://localhost:6443 >/dev/null 2>&1; then
      echo "SSH tunnel: UP (port 6443 reachable)"
    else
      echo "SSH tunnel: DOWN (port 6443 not reachable)"
    fi
    ;;
esac
```

### Change 3 — `bin/cluster-status`: add API Health + Hub ArgoCD Registration (after app Pods, before ArgoCD Apps)

**Exact old block (lines 47–53):**
```bash
echo ""
echo "=== Pods — all namespaces (${APP_CONTEXT}) ==="
kubectl get pods -A --context "${APP_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach app cluster"

echo ""
echo "=== ArgoCD Apps ==="
```
**Exact new block:**
```bash
echo ""
echo "=== Pods — all namespaces (${APP_CONTEXT}) ==="
kubectl get pods -A --context "${APP_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach app cluster"

echo ""
echo "=== API Health (${APP_CONTEXT}) ==="
if kubectl get --raw='/healthz' --context "${APP_CONTEXT}" >/dev/null 2>&1; then
  echo "API server: UP (/healthz ok)"
else
  echo "API server: DOWN (/healthz unreachable)"
fi

echo ""
echo "=== Hub ArgoCD Registration (${INFRA_CONTEXT}, ns ${ARGOCD_NAMESPACE}) ==="
if kubectl get secret "cluster-${APP_CONTEXT}" -n "${ARGOCD_NAMESPACE}" \
     --context "${INFRA_CONTEXT}" >/dev/null 2>&1; then
  echo "Registered: secret cluster-${APP_CONTEXT} present"
else
  echo "NOT registered: secret cluster-${APP_CONTEXT} missing"
fi

echo ""
echo "=== ArgoCD Apps ==="
```

> The `Service Health` section (endpoints + ESO via webhook `/api/v1/health`) already exists at the
> end of `bin/cluster-status` (lines 73–93) — leave it untouched; it now runs for Hostinger too.

### Change 4 — `Makefile`: route `k3s-hostinger` status through `bin/cluster-status`

**Exact old block (lines 43–51):**
```make
## Show cluster nodes, pod status, tunnel health
status:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) CLUSTER_PROVIDER=k3s-oci KUBECONFIG=$(HOME)/.kube/k3s-oci.yaml \
	             kubectl get nodes,pods -A --no-headers 2>/dev/null \
	             || echo "OCI cluster unreachable" ;; \
	  k3s-hostinger) bin/hostinger-status ;; \
	  *)       $(if $(filter command line environment,$(origin APP_CONTEXT)),APP_CONTEXT=$(APP_CONTEXT) )$(if $(filter command line environment,$(origin CLUSTER_PROVIDER)),CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) )bin/cluster-status ;; \
	esac
```
**Exact new block:**
```make
## Show cluster nodes, pods, endpoint + ESO health (provider-aware)
status:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-oci) CLUSTER_PROVIDER=k3s-oci KUBECONFIG=$(HOME)/.kube/k3s-oci.yaml \
	             kubectl get nodes,pods -A --no-headers 2>/dev/null \
	             || echo "OCI cluster unreachable" ;; \
	  *)       $(if $(filter command line environment,$(origin APP_CONTEXT)),APP_CONTEXT=$(APP_CONTEXT) )$(if $(filter command line environment,$(origin CLUSTER_PROVIDER)),CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) )bin/cluster-status ;; \
	esac
```

### Change 5 — `bin/k3dm-webhook`: `_run_hostinger_status` invokes `bin/cluster-status`

**Exact old block (lines 1937–1942):**
```python
        status_bin = repo_root / "bin" / "hostinger-status"
        status_out, status_timeout = _posix_spawn_capture(
            ["/bin/bash", "-c",
             f"{_shlex_hs.quote(str(status_bin))} && echo __WEBHOOK_SUCCESS__"],
            timeout=180,
        )
```
**Exact new block:**
```python
        status_bin = repo_root / "bin" / "cluster-status"
        status_out, status_timeout = _posix_spawn_capture(
            ["/bin/bash", "-c",
             f"CLUSTER_PROVIDER=k3s-hostinger {_shlex_hs.quote(str(status_bin))} && echo __WEBHOOK_SUCCESS__"],
            timeout=180,
        )
```

**Exact old block (line 1944):**
```python
            _log("\n❌ *Hostinger status timed out* after 180s — run `bin/hostinger-status` manually")
```
**Exact new block:**
```python
            _log("\n❌ *Hostinger status timed out* after 180s — run `make status CLUSTER_PROVIDER=k3s-hostinger` manually")
```

> Leave the function name `_run_hostinger_status`, the `/hostinger-status` Slack command, the
> `/api/v1/hostinger-status` endpoint, and the `hostinger-status` thread/standalone entries as-is —
> they now produce the unified report. Do NOT touch the report-body behavior (line 1948 "report
> gathered") — that is a separate, already-filed bug
> (`docs/bugs/2026-06-14-bugfix-hostinger-status-report-body.md`).

### Change 6 — delete the duplicate

```bash
git rm bin/hostinger-status
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/cluster-status` | add `ARGOCD_NAMESPACE`; gate Tunnel to tunneled providers; add API Health + Hub ArgoCD Registration sections |
| `Makefile` | remove `k3s-hostinger) bin/hostinger-status` branch (falls through to provider-aware `bin/cluster-status`); update comment |
| `bin/k3dm-webhook` | `_run_hostinger_status` runs `bin/cluster-status` with `CLUSTER_PROVIDER=k3s-hostinger`; update timeout hint |
| `bin/hostinger-status` | **deleted** (duplicate) |

---

## Rules

- `shellcheck -S warning bin/cluster-status` — zero new warnings
- `bash -n bin/cluster-status` — clean
- `python3 -m py_compile bin/k3dm-webhook` — clean
- `make -n status CLUSTER_PROVIDER=k3s-hostinger` resolves to `bin/cluster-status` (not hostinger-status)
- `grep -rn "bin/hostinger-status" bin/ scripts/ workers/ Makefile` — no reference to the deleted script (the `/hostinger-status` command + `/api/v1/hostinger-status` endpoint + `_run_hostinger_status` function remain)
- Do NOT touch `scripts/lib/acg/` or `scripts/lib/foundation/` (subtrees)

---

## Definition of Done

- [ ] `bin/cluster-status` shows, for `k3s-hostinger`: app nodes/pods on `ubuntu-hostinger`, **no** Tunnel section, API Health, Hub ArgoCD Registration, ArgoCD Apps/ApplicationSets, Service Health (endpoints + ESO)
- [ ] `bin/cluster-status` still shows Tunnel + AWS Credentials for `k3s-aws`
- [ ] `Makefile` `status` routes `k3s-hostinger` to `bin/cluster-status`
- [ ] `bin/k3dm-webhook` `_run_hostinger_status` calls `bin/cluster-status` with `CLUSTER_PROVIDER=k3s-hostinger`
- [ ] `bin/hostinger-status` deleted; no remaining reference to the script
- [ ] `shellcheck` + `bash -n` + `py_compile` clean
- [ ] Committed and pushed to `k3d-manager-v1.7.1`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
refactor(status): consolidate hostinger-status into provider-aware cluster-status
```

---

## What NOT to Do

- Do NOT keep `bin/hostinger-status` — delete it
- Do NOT remove the `/hostinger-status` Slack command, `/api/v1/hostinger-status` endpoint, or `_run_hostinger_status` function — only repoint the script it runs
- Do NOT change the report-body behavior (separate bug)
- Do NOT re-implement endpoint/ESO checks in shell — they stay in the webhook `/api/v1/health`
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the four listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.7.1`

---

## Operator follow-on (NOT part of this commit)

- `make restart-webhook` — reload `bin/k3dm-webhook` so `_run_hostinger_status` runs the new path.

---

## Known limitation (unchanged — separate task)

`_SMOKE_ENDPOINTS` and the data-layer readiness check in the webhook are still pointed at the
ACG/hub-local surface (`localhost:8080`, `frontend.shopping-cart.local`, data-layer on context
`ubuntu-k3s`). The **ESO** rows are hub-based and correct for Hostinger; the **HTTP endpoint** rows
and **Data layer** row read stale until re-pointed at the Hostinger app cluster — out of scope here.
