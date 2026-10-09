# Hostinger istio-cni stuck Progressing for 6 days: generic CNI dirs, and no alert

**Filed:** 2026-10-09, Claude (operator saw `istio-cni-ubuntu-hostinger` spinning in ArgoCD)
**Branch:** k3d-manager-v1.42.0 (bug docs are exempt from the 5-plan cap)
**Status:** OPEN — recovered 2026-10-09 by `make refresh`; root cause of the bad apply not yet traced, no alert yet
**Priority:** P2 — ambient still works, but the CNI plugin is not chained, and nothing alerts
**Severity:** Medium
**Component:**
- The `istio-ambient` ApplicationSet apply paths (`scripts/plugins/argocd.sh`
  `_argocd_appset_live_overrides`, the hub rebuild / bootstrap path)
- `argocd-degraded` PrometheusRule

**Related (a recurrence of this class):**
- `docs/bugs/2026-07-17-ambient-istio-cni-conf-bin-dir-mismatch.md`
- `docs/bugs/2026-07-21-istio-ambient-cni-dirs-not-substrate-aware.md`
- `docs/bugs/2026-09-23-appset-live-overrides-lock-in-stale-cni-dirs.md` (FIXED v1.37.0)
- `docs/bugs/2026-09-23-hostinger-registration-never-sets-provider-label.md` (FIXED `834149ea`)

## Symptom

1. In ArgoCD, `istio-cni-ubuntu-hostinger` has been `Progressing` / `Synced` since
   2026-10-03 16:09 UTC.
2. On Hostinger, DaemonSet `istio-system/istio-cni-node` reports 1 desired, 0 ready.
   - Pod `istio-cni-node-kfz8t` is 0/1 Running.
   - Its `/readyz` has returned 503 53,275 times over 5d19h.
3. The pod log, right after start:
   ```
   warn cni-agent Istio CNI is configured as chained plugin, but cannot find existing CNI network config: no networks found in /host/etc/cni/net.d
   ```
4. The Application's Helm values are `cniConfDir: /etc/cni/net.d`, `cniBinDir: /opt/cni/bin`.
   These are the generic (Cilium) defaults from `scripts/etc/argocd/vars.sh`. Hostinger is k3s
   with flannel and needs `/var/lib/rancher/k3s/agent/etc/cni/net.d` and
   `/var/lib/rancher/k3s/data/cni` (`_istio_ambient_cni_dirs k3s-hostinger`).
5. The ambient node agent still enrolls pods through ztunnel ("sending pod add to ztunnel",
   2026-10-08). The CNI plugin, however, is not chained into the k3s CNI config.
   - New pods therefore rely on the agent's informer path instead of the CNI hook.
   - The readiness gate never passes.

## Why the guard did not catch it

`_argocd_appset_live_overrides` refuses generic dirs only when `_istio_ambient_target_provider`
resolves a specific provider. The ApplicationSet was **created 2026-10-03 15:58 UTC, during the
hub rebuild**, when no live set existed to fall back on. It was updated again on
2026-10-06 14:04 UTC. Its destination is `ubuntu-hostinger`, and the registration Secret now
carries `k3d-manager/provider: k3s-hostinger`. So on the path that applied it, either:
- the provider lookup ran against a different `APP_CLUSTER_NAME` (default `ubuntu-k3s`, which is
  `k3s-aws` and maps to the generic dirs), or
- that path bypassed `_argocd_appset_live_overrides` entirely.

**Trace this first.** Find which caller applied `istio-ambient` at those two times (the hub
rebuild, or the ACG `make up` on 10-06), and with which `APP_CLUSTER_NAME`.

## No alert (Grafana tracks it, nothing fires)

- `argocd_app_info{name="istio-cni-ubuntu-hostinger", health_status="Progressing"} == 1` is in
  Prometheus, so a Grafana panel can show it.
- `ArgoCDAppDegraded` only matches an allowlist of app names (it does not include `istio-*`), and
  only `health_status="Degraded"`. A **stuck `Progressing`** never fires.
- `KubeDaemonSetRolloutStuck` runs on the hub's kube-state-metrics. The hub does not have the
  Hostinger DaemonSet metrics (`kube_daemonset_status_number_ready{daemonset="istio-cni-node"}`
  is empty).

## Fix direction (to spec)

1. Make every `istio-ambient` apply path derive the CNI dirs from the destination's provider
   label, and refuse generic dirs for a k3s destination. BATS: the hub-rebuild / bootstrap
   path with no live set and destination `ubuntu-hostinger` must render the rancher dirs.
   RED first.
2. Alerting:
   - Add `ArgoCDAppProgressingStuck`: `argocd_app_info{health_status="Progressing"} == 1` for 30m
     (or longer), severity warning, email.
   - Widen or drop the name allowlist so platform apps (`istio-*`) are covered.
   - Keep sandbox (`ubuntu-k3s-*`) apps email-only.

## Immediate recovery (operator)

Reapplying the Hostinger ApplicationSets renders the correct dirs
(`_hostinger_reapply_gitops_applicationsets` sets them explicitly, at
`scripts/lib/providers/k3s-hostinger.sh:875`):
```
make refresh CLUSTER_PROVIDER=k3s-hostinger
```
Verify afterwards:
- The Application values show `/var/lib/rancher/...`.
- `istio-cni-node` is 1/1.
- The app is Healthy.

### Recovery result (2026-10-09)

The operator ran `make refresh CLUSTER_PROVIDER=k3s-hostinger`. Claude verified:
- The Application values are now `cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d` and
  `cniBinDir: /var/lib/rancher/k3s/data/cni`.
- The app is `Synced` / `Healthy`.
- DaemonSet `istio-cni-node` is 1/1 (new pod `istio-cni-node-rv94s`, 0 restarts).

The next hub rebuild can reintroduce the generic dirs until fix item 1 lands.

## What NOT to do

- Do not patch the Application or DaemonSet by hand: the ApplicationSet / self-heal reverts it.
- Do not change the `vars.sh` defaults to the rancher paths. Cilium substrates need the generic
  pair.
