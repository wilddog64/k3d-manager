# Bug: ArgoCD renders a stale `$values` for a multi-source Helm app despite resolving the correct SHA

**Cluster:** hub `k3d-k3d-cluster` (ArgoCD ns `cicd`), app `acg-trivy-operator`
**Observed:** 2026-08-23
**Status:** OPEN — durable git fix is correct and in place; ArgoCD will not apply it.

## Symptom

`scripts/etc/helm/observability/trivy-operator-acg-values.yaml` was changed
(`trivy.resources.requests.cpu 50m→10m`, commit `8bfcbcc9`, on `k3d-manager-v1.27.0`).
The `observability-acg` ApplicationSet was reapplied so the multi-source app's `$values` ref
points at `k3d-manager-v1.27.0`. ArgoCD reports `Synced/Healthy`, and
`.status.sync.revisions` resolves the `$values` source to `b97c9dcd` (branch HEAD). Yet the
live ConfigMap `trivy-system/trivy-operator-trivy-config` key
`trivy.resources.requests.cpu` stays **50m** (resourceVersion never changes — ArgoCD applies a
no-op because its rendered desired == 50m).

## Proof the git content is correct (render input is 10m)

- GitHub API `contents/...trivy-operator-acg-values.yaml?ref=k3d-manager-v1.27.0` → `cpu: 10m`.
- `git ls-remote https://github.com/wilddog64/k3d-manager k3d-manager-v1.27.0` (run **inside the
  argocd-repo-server pod**) → `b97c9dcd`.
- `git clone --depth 1 --branch k3d-manager-v1.27.0 …` (inside the repo-server pod) →
  the values file reads `cpu: 10m`.
- `helm template … --version 0.34.0 -f <that values file>` locally → ConfigMap `10m`.

So the repo-server *can* fetch 10m, resolves the right SHA, and the chart maps the key correctly —
but ArgoCD's own render pipeline emits 50m.

## What was tried (none applied 10m)

- `argocd.argoproj.io/refresh=hard` (repeatedly).
- Restart `argocd-repo-server` (all volumes are emptyDir — no persistent git cache).
- Restart `argocd-application-controller`.
- Restart `argocd-redis` (twice — flushes the manifest cache).
- Force `Replace=true` sync targeted at the ConfigMap.
- Delete the Application non-cascading (resources preserved) → appset regenerates it → still 50m.
- Pin the appset `$values` `targetRevision` to the exact SHA `b97c9dcd` (not the branch) → still 50m,
  even after another redis+repo-server flush.
- Manual `kubectl patch` of the ConfigMap to 10m → **selfHeal reverts to 50m within ~10s**,
  confirming ArgoCD's rendered desired is genuinely 50m.

This matches the known ArgoCD multi-source **ref-source (`$values`) stale-render** class of bugs
(the `$values` source content used for rendering is resolved/cached separately from the reported
`sync.revisions`, and neither hard-refresh nor the standard cache flushes reliably invalidate it).

## Impact

CVE dashboard **panel ②** stays empty: the 50m scan-job request will not fit hostinger's
CPU-saturated 2-CPU node (see
`docs/bugs/2026-08-23-hostinger-trivy-scanjob-cpu-request-unschedulable.md`), so trivy produces no
`vulnerabilityreports`. The whole hub→hostinger exporter pipeline is otherwise proven working.

## Workaround (immediate)

`scratchpad/cve-panel2-unblock-scans.sh`: disable the appset's `syncPolicy.automated` (so selfHeal
stops reverting), `kubectl patch` the ConfigMap to 10m, restart the operator, clear stuck scan jobs.
Leave auto-sync off until this ArgoCD bug is resolved (git already carries 10m, so no divergence of
intent).

## Durable follow-ups to investigate

- Upgrade ArgoCD (this may be a version-specific ref-source cache bug — check the running version and
  changelog for multi-source `$values` cache fixes).
- Consider collapsing the multi-source pattern for these observability apps (inline the values, or
  use a single source) if the ref-source render stays unreliable.
- Add `argocd_check_values_branch` output to the release checklist so a stale `$values` ref is caught
  at reapply time.
