# Hostinger istio-cni stuck Progressing for 6 days: generic CNI dirs, and no alert

**Filed:** 2026-10-09, Claude (operator saw `istio-cni-ubuntu-hostinger` spinning in ArgoCD)
**Branch:** k3d-manager-v1.42.0 (bug docs are exempt from the 5-plan cap)
**Status:** FIXED — `350fac28` (Claude-verified: RED on old code, 68/68 BATS); live after the next istio-ambient apply, and the alert after platform-ops is reapplied at release. Release decision 2026-10-09: verified as a **v1.42.0 release step** (`make appsets-reapply` + the next istio-ambient apply), not left to chance
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

---

## Root cause (traced 2026-10-09, Claude)

There is **one** `istio-ambient` ApplicationSet on the hub (its name is not templated), and
`_argocd_appset_live_overrides` (`scripts/plugins/argocd.sh`) resolves its two inputs from
**different clusters**:

- `APP_CLUSTER_NAME` (the destination) comes from the **live** set: `ubuntu-hostinger`.
- The CNI provider is looked up with the **shell's** `${APP_CLUSTER_NAME:-ubuntu-k3s}`. On any
  apply that is not the Hostinger reapply (`make up` for ACG on 2026-10-06, the hub rebuild), that
  is `ubuntu-k3s`, whose registration says `k3d-manager/provider: k3s-aws`. That maps to the
  generic `/etc/cni/net.d` + `/opt/cni/bin`, and `k3s-aws` is not a "specific" provider, so the
  refusal guard does not fire either.

Result: the destination stays Hostinger, but it gets the sandbox's CNI dirs. The existing BATS
never caught it because no test template contains `${APP_CLUSTER_NAME}`.

## Implementation spec (Codex, 2026-10-09)

**Branch:** `k3d-manager-v1.42.0`.
**Files (only these):**
- `scripts/plugins/argocd.sh`
- `scripts/tests/plugins/argocd_appset_cni_dir_precedence.bats` (add one test)
- `scripts/etc/argocd/platform-ops/prometheusrule.yaml` (add one rule)
- `scripts/tests/plugins/argocd_metrics_servicemonitor.bats` (add one assertion block)
- `docs/howto/argocd-alerts.md` (list the new alert and its window)
- `CHANGELOG.md` (`[Unreleased]` → `### Fixed`, one bullet for each change)
- this doc's Status line

### Change 1 — look the provider up for the destination actually being written

In `_argocd_appset_live_overrides`:

**OLD:**
```bash
   local file="$1" name live value conf bin provider dirs
```
**NEW:**
```bash
   local file="$1" name live value conf bin provider dirs target
```

**OLD:**
```bash
   if grep -q '\${APP_CLUSTER_NAME}' "$file" && [[ -n "${live}" ]]; then
      value="$(printf '%s' "${live}" | jq -r '.spec.template.spec.destination.name // ""')"
      [[ -z "${value}" || "${value}" == *'{{'* || "${value}" == *'$'* ]] || printf 'APP_CLUSTER_NAME=%s\n' "${value}"
   fi
```
**NEW:**
```bash
   target="${APP_CLUSTER_NAME:-ubuntu-k3s}"
   if grep -q '\${APP_CLUSTER_NAME}' "$file" && [[ -n "${live}" ]]; then
      value="$(printf '%s' "${live}" | jq -r '.spec.template.spec.destination.name // ""')"
      if [[ -n "${value}" && "${value}" != *'{{'* && "${value}" != *'$'* ]]; then
         printf 'APP_CLUSTER_NAME=%s\n' "${value}"
         target="${value}"
      fi
   fi
```

**OLD:**
```bash
         provider="${AMBIENT_CNI_PROVIDER:-$(_istio_ambient_target_provider "${ARGOCD_CONTEXT:-k3d-k3d-cluster}" "${ARGOCD_NAMESPACE:-cicd}" "${APP_CLUSTER_NAME:-ubuntu-k3s}")}"
```
**NEW:**
```bash
         provider="${AMBIENT_CNI_PROVIDER:-$(_istio_ambient_target_provider "${ARGOCD_CONTEXT:-k3d-k3d-cluster}" "${ARGOCD_NAMESPACE:-cicd}" "${target}")}"
```
Nothing else in the function changes.

### Test for Change 1 (add to `argocd_appset_cni_dir_precedence.bats`)

`@test "provider is resolved for the live destination, not the shell APP_CLUSTER_NAME"`:
- Write a template that contains **both** `${APP_CLUSTER_NAME}` and the two CNI placeholders
  (e.g. append a line `  destination: ${APP_CLUSTER_NAME}` to the file `setup()` creates).
- `APP_CLUSTER_NAME=ubuntu-k3s` (the shell side).
- `LIVE_JSON` with `"spec":{"template":{"spec":{"destination":{"name":"ubuntu-hostinger"}}},"generators":[ ...istio-cni with /etc/cni/net.d and /opt/cni/bin... ]}` and `"kind":"ApplicationSet"`.
- Stub `_istio_ambient_target_provider` to print `k3s-hostinger` when `$3 == ubuntu-hostinger`
  and `k3s-aws` otherwise. Use the **real** `_istio_ambient_cni_dirs` (re-source
  `istio_ambient.sh` or do not stub it in this test).
- Assert the output contains `APP_CLUSTER_NAME=ubuntu-hostinger`,
  `AMBIENT_CNI_CONF_DIR=/var/lib/rancher/k3s/agent/etc/cni/net.d` and
  `AMBIENT_CNI_BIN_DIR=/var/lib/rancher/k3s/data/cni`, and does **not** contain the line
  `AMBIENT_CNI_CONF_DIR=/etc/cni/net.d` (use `run grep -Fqx ...; [ "$status" -ne 0 ]`).

**RED gate:** this test must fail on the pre-fix `argocd.sh`. Do NOT `git stash`/`git checkout`:
write `git show HEAD:scripts/plugins/argocd.sh` to a temp file, source that copy once by hand in
the same harness, and paste the failing output.

### Change 2 — alert on an app stuck `Progressing`

In `scripts/etc/argocd/platform-ops/prometheusrule.yaml`, add directly after the
`ArgoCDAppOutOfSync` rule (same indentation as its siblings):
```yaml
        - alert: ArgoCDAppProgressingStuck
          expr: |
            argocd_app_info{health_status="Progressing"} == 1
          for: 30m
          labels:
            group: argocd
            severity: warning
          annotations:
            summary: "ArgoCD app {{ $labels.name }} has been Progressing for 30 minutes"
            description: "App {{ $labels.name }} (destination {{ $labels.dest_server }}, namespace {{ $labels.dest_namespace }}) has been Progressing for 30 minutes. A DaemonSet or Deployment is not becoming ready; check its pods on the destination cluster."
```
No name allowlist: this must cover platform apps such as `istio-cni-*`. `severity: warning`
routes to email (`platform-warning`), never SMS. Do **not** edit `alertmanager-config.yaml`.

Test: in `argocd_metrics_servicemonitor.bats`, in the existing test that greps the rule file for
`ArgoCDAppDegraded`, add assertions that the rule file contains `alert: ArgoCDAppProgressingStuck`
and `health_status="Progressing"`.

### Gates
- `shellcheck -S warning scripts/plugins/argocd.sh` — no new warnings
- `bats scripts/tests/plugins/argocd_appset_cni_dir_precedence.bats scripts/tests/plugins/argocd_appset_live_overrides.bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats scripts/tests/plugins/argocd.bats`
- `python3 -c 'import yaml,sys; list(yaml.safe_load_all(open("scripts/etc/argocd/platform-ops/prometheusrule.yaml")))'`

### Status line
`**Status:** IMPLEMENTED — provider resolved for the live destination + ArgoCDAppProgressingStuck; awaiting Claude verification`

### Commit message (exact)
```
fix(argocd): resolve istio-cni dirs for the live destination; alert on stuck Progressing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

### What NOT to do
- Do not rename or template the `istio-ambient` ApplicationSet name (separate design question).
- Do not change `scripts/etc/argocd/vars.sh` defaults or `_istio_ambient_cni_dirs`.
- Do not touch `scripts/lib/providers/k3s-hostinger.sh`.
- Do not apply anything to a cluster.
