# Bug: Hostinger data layer stuck Pending — orphaned green1 vcluster squats on the 2-CPU node

**Date:** 2026-06-25
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`
**Affects:** `k3d-manager` (`scripts/plugins/vcluster.sh`), live `ubuntu-hostinger` host
**Files (code):** `scripts/plugins/vcluster.sh`, `scripts/tests/plugins/vcluster.bats`
**Operator runbook (live, Claude-run):** `ubuntu-hostinger` host context, `vclusters` namespace

> This is **Discovery 2 (D2)** from the cutover spec
> `docs/bugs/2026-06-25-hostinger-cutover-app-cluster-role-and-green1-retire.md`.
> The cutover (Part A) moved the app-cluster role to `ubuntu-hostinger` and retired green1
> from the **hub** ArgoCD, but the green1 **vcluster itself is still running on the host**
> and is the reason the data layer cannot schedule.

---

## Symptom

After the cutover, on `ubuntu-hostinger`:

```
shopping-cart-data: minio-0, postgresql-orders-0, postgresql-payment-0  → Pending (23m+)
  FailedScheduling: 0/1 nodes are available: 1 Insufficient cpu
https://frontend.3ai-talk.org  → 502 (frontend depends on the unscheduled data layer)
```

Grafana (symptom C) is already 200 after the cutover; **only the data layer + frontend
remain red, and the cause is node CPU exhaustion, not GitOps wiring.**

---

## Root cause (verified live, 2026-06-25)

The `ubuntu-hostinger` k3s node has **2 CPU** (2000m allocatable) and is already at **96%
requested** (1930m). The largest consumer is an **orphaned preflight vcluster** sharing the
same node:

```
ns vclusters → StatefulSet/green1 (helm release "green1", chart vcluster-0.32.1, age 8d)
  Running pods holding CPU on the host:
    green1-0                                 300m
    basket-service-…-x-green1                100m
    frontend-…-x-green1                       50m
    coredns-…-x-green1                        20m
  ≈ 470m held by green1 (plus its own pending/succeeded pods)
```

The three Pending data pods need only 100m each (300m total) but there is ~70m free. green1
is the ephemeral **v1.7.1 PR preflight** vcluster (branch deleted); the preflight CI run that
created it never tore it down, so it has squatted on the host for 8 days. We removed its hub
ArgoCD registration during the cutover, but nothing removed the host-side Helm release.

### Why this slipped through

`vcluster_destroy` (`scripts/plugins/vcluster.sh:40`) tears down only the **host** vcluster
(`vcluster delete`). It never deregisters the vcluster from the **hub** ArgoCD (cluster
secret + `<name>-preflight-*` ApplicationSets/Applications). Conversely, the cutover Part A
removed the hub side by hand but not the host vcluster. There is **no single command that
retires a preflight vcluster end-to-end**, so orphans on either side are easy to create.

---

## Part A — Operator runbook (LIVE, Claude-run — frees CPU now)

> Context: `ubuntu-hostinger`. green1 is an ephemeral preflight vcluster pinned to a deleted
> branch — safe to delete. This frees ~470m CPU so the data layer can schedule.

1. **Tear down the orphaned green1 vcluster:**
   ```
   helm --kube-context ubuntu-hostinger -n vclusters uninstall green1
   # (equivalent: ./scripts/k3d-manager vcluster_destroy green1, once the active
   #  kube-context is ubuntu-hostinger)
   ```
2. **Confirm CPU is freed and the data layer schedules:**
   ```
   kubectl --context ubuntu-hostinger -n shopping-cart-data get pods   # minio-0 / postgresql-orders-0 / postgresql-payment-0 → Running
   kubectl --context ubuntu-hostinger describe node | grep -A6 'Allocated resources'
   ```
3. **Verify the edge:**
   ```
   curl -s -o /dev/null -w '%{http_code}\n' https://frontend.3ai-talk.org   # expect 200
   ```

---

## Part B — Code change (Codex): make `vcluster_destroy` a complete teardown

**This change SUPERSEDES Change 2 of the cutover spec** (`…-app-cluster-role-and-green1-retire.md`).
Implement preflight hub-cleanup **here in `vcluster.sh`** (where it belongs), not in the
hostinger provider.

### Change 1 — `scripts/plugins/vcluster.sh`: deregister from the hub during destroy

Add a private helper that removes the vcluster's hub ArgoCD footprint, and call it from
`vcluster_destroy`. The hub ArgoCD lives on a **different** cluster/context than the vcluster
host, so the helper MUST target the hub context explicitly — **reuse the hub-context resolver
introduced in the cutover spec's Part B Change 1** (do not rely on the ambient `_kubectl`
context). Namespace is `${ARGOCD_NAMESPACE:-cicd}`. Naming pattern (verified live): cluster
secret `cluster-<name>`; ApplicationSets/Applications prefixed `<name>-preflight-`.

**Exact old block (`vcluster_destroy`, lines 40–62):**

```bash
function vcluster_destroy() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "Usage: vcluster_destroy <name>"
  fi

  _vcluster_check_prerequisites
  _vcluster_ensure_exists "$name"
  local kubeconfig_path
  kubeconfig_path="$(_vcluster_kubeconfig_path "$name")"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'DRY_RUN: vcluster delete %s in namespace %s\n' "$name" "$VCLUSTER_NAMESPACE"
    printf 'DRY_RUN: kubeconfig %s would be removed\n' "$kubeconfig_path"
    return 0
  fi

  _run_command -- vcluster delete "$name" -n "$VCLUSTER_NAMESPACE" --wait
  if [[ -f "$kubeconfig_path" ]]; then
    _run_command -- rm -f "$kubeconfig_path"
  fi
  _info "Deleted vCluster '$name'"
}
```

**Exact new block:**

```bash
function vcluster_destroy() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "Usage: vcluster_destroy <name>"
  fi

  _vcluster_check_prerequisites
  _vcluster_ensure_exists "$name"
  local kubeconfig_path
  kubeconfig_path="$(_vcluster_kubeconfig_path "$name")"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'DRY_RUN: vcluster delete %s in namespace %s\n' "$name" "$VCLUSTER_NAMESPACE"
    printf 'DRY_RUN: kubeconfig %s would be removed\n' "$kubeconfig_path"
    printf 'DRY_RUN: deregister %s from hub ArgoCD (cluster-%s + %s-preflight-* appsets/apps)\n' "$name" "$name" "$name"
    return 0
  fi

  _vcluster_deregister_from_hub "$name"
  _run_command -- vcluster delete "$name" -n "$VCLUSTER_NAMESPACE" --wait
  if [[ -f "$kubeconfig_path" ]]; then
    _run_command -- rm -f "$kubeconfig_path"
  fi
  _info "Deleted vCluster '$name'"
}

function _vcluster_deregister_from_hub() {
  local name="${1:-}"
  [[ -z "$name" ]] && return 0
  local ns="${ARGOCD_NAMESPACE:-cicd}"

  # Hub ArgoCD runs on a different context than the vcluster host — target it explicitly.
  # Reuse the hub-context resolver from the cutover spec's Change 1.
  local -a hub_kubectl
  # shellcheck disable=SC2206
  hub_kubectl=( $(_argocd_hub_kubectl_cmd) )   # e.g. "kubectl --context k3d-k3d-cluster"
  command -v "${hub_kubectl[0]}" >/dev/null 2>&1 || return 0

  # Delete generating ApplicationSets first so apps are not recreated.
  "${hub_kubectl[@]}" -n "$ns" delete applicationset \
    -l "k3d-manager/preflight-cluster=${name}" --ignore-not-found >/dev/null 2>&1 || true
  while IFS= read -r _as; do
    [[ -z "$_as" ]] && continue
    "${hub_kubectl[@]}" -n "$ns" delete "$_as" --ignore-not-found >/dev/null 2>&1 || true
  done < <("${hub_kubectl[@]}" -n "$ns" get applicationset -o name 2>/dev/null | grep "/${name}-preflight-")

  # Strip finalizers, then delete the preflight Applications (avoid prune-hang on a dead vcluster).
  while IFS= read -r _app; do
    [[ -z "$_app" ]] && continue
    "${hub_kubectl[@]}" -n "$ns" patch "$_app" --type=merge \
      -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
    "${hub_kubectl[@]}" -n "$ns" delete "$_app" --ignore-not-found >/dev/null 2>&1 || true
  done < <("${hub_kubectl[@]}" -n "$ns" get application -o name 2>/dev/null | grep "/${name}-preflight-")

  # Remove the cluster registration secret.
  "${hub_kubectl[@]}" -n "$ns" delete secret "cluster-${name}" --ignore-not-found >/dev/null 2>&1 || true
  _info "Deregistered '${name}' from hub ArgoCD (${ns})"
}
```

> Codex: `_argocd_hub_kubectl_cmd` is the hub-context helper from the cutover spec Change 1.
> If that helper has a different final name, use whatever Change 1 actually introduces — do
> NOT invent a second hub-context mechanism. If selecting appsets by the
> `k3d-manager/preflight-cluster=<name>` label is not how they are generated, fall back to the
> name-prefix match only (the `grep "/${name}-preflight-"` loop already covers it) and drop the
> label selector line.

### Change 2 — `scripts/tests/plugins/vcluster.bats`

Add coverage:
- `vcluster_destroy` with `DRY_RUN=1` prints the new "deregister … from hub ArgoCD" line.
- `_vcluster_deregister_from_hub` issues hub-context deletes for `cluster-<name>`,
  `<name>-preflight-*` applicationsets, and `<name>-preflight-*` applications (mock
  `_argocd_hub_kubectl_cmd` / the hub kubectl).

---

## Definition of Done

- [ ] **Part A:** green1 Helm release uninstalled from `vclusters`; `minio-0` /
      `postgresql-orders-0` / `postgresql-payment-0` reach `Running`; `frontend.3ai-talk.org`
      returns 200.
- [ ] **Part B:** `vcluster_destroy` calls `_vcluster_deregister_from_hub` before the host
      delete; helper targets the hub context (not ambient `_kubectl`); DRY_RUN path documents
      the hub cleanup.
- [ ] `shellcheck -S warning scripts/plugins/vcluster.sh scripts/tests/plugins/vcluster.bats` — zero new warnings.
- [ ] `bats scripts/tests/plugins/vcluster.bats` passes.
- [ ] `./scripts/k3d-manager _agent_audit` exit 0.
- [ ] Committed + pushed to `feat/v1.8.0-acg-absorb-phase2-agy`; memory-bank updated with SHA.

**Commit message (exact):**
```
fix(vcluster): deregister preflight vcluster from hub ArgoCD on destroy
```

---

## What NOT to Do

- Do NOT remove or weaken the existing host-side `vcluster delete` path.
- Do NOT invent a second hub-context resolver — reuse Change 1's helper.
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the listed targets.
- Do NOT commit to `main` — work on `feat/v1.8.0-acg-absorb-phase2-agy`.
- Do NOT reduce data-layer CPU requests as a "fix" — the requests are already minimal (100m);
  the problem is the orphaned vcluster, not the data layer.
