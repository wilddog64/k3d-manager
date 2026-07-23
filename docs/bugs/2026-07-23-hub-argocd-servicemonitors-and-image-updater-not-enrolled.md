# Bugfix: hub — ArgoCD ServiceMonitors + image-updater not enrolled (Grafana "No data")

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/plugins/argocd.sh` (primary). A BATS test under `scripts/tests/plugins/`.

---

## Why this spec exists (read first)

The hub Grafana dashboard **"ArgoCD Apps & Image Updater Hub"** showed **"No data"** on every panel.
Claude live-diagnosed on `k3d-k3d-cluster` (hub) and applied an **operational remediation** on
2026-07-23 — but it is NOT durable across a hub rebuild. This spec makes the fix survive
`deploy_argocd` from scratch.

**Live findings (all verified):**
- Hub Prometheus is healthy (52 `up` targets) but scraped **no `argocd` job** — `argocd_app_info` = 0
  series — so the "Watched App Sync / Health / Flapping" panels had nothing to read.
- The hub `argocd` Helm release (rev 1) **has** `*.metrics.serviceMonitor.enabled: true` with
  `additionalLabels.release: kube-prometheus-stack` (which matches the Prometheus
  `serviceMonitorSelector`), yet **zero argocd ServiceMonitors existed** on the cluster. The
  ServiceMonitor CRD has existed since before argocd was installed, so it is not a simple CRD-ordering
  miss at the surface — but the chart's SM templates are gated on
  `.Capabilities.APIVersions.Has "monitoring.coreos.com/v1"`, and the initial render did not emit them.
- `argocd-image-updater` was **never deployed** on this hub. It is defined at
  `scripts/etc/argocd/image-updater/kustomization.yaml` and installed **only** by
  `_argocd_deploy_image_updater` (`scripts/plugins/argocd.sh:1138`), which runs **only** inside
  `deploy_argocd`'s `enable_bootstrap` branch (`scripts/plugins/argocd.sh:552`). That branch was not
  exercised on this hub. `ghcr-pull-secret` was also absent in `cicd`.

**Operational remediation already applied live (do NOT redo — it is done, just not durable):**
1. `kubectl apply -k scripts/etc/argocd/image-updater/` → deployment `2/2 Running`.
2. A full `helm upgrade` of argocd **fails** with a field-ownership conflict on `argocd-cm` /
   `argocd-rbac-cm` (`.data.oidc.config`, `.data.url`, `.data.policy.csv`, `.data.scopes` are owned by
   the post-install `kubectl` patches, not helm). **Do NOT force or `--take-ownership`** — it would
   clobber the OIDC/RBAC config and break Keycloak login to ArgoCD. Instead Claude rendered ONLY the
   ServiceMonitors and applied them:
   ```
   helm template argocd argo/argo-cd --version 10.1.4 -n cicd \
     -f <(helm get values argocd -n cicd -o yaml) \
     --api-versions monitoring.coreos.com/v1 \
     | yq eval-all 'select(.kind == "ServiceMonitor")' - \
     | kubectl apply -f -
   ```
   Result: 4 argocd ServiceMonitors created; 4 targets `up=1`; `argocd_app_info` 0 → 40 series;
   image-updater `ready=1 / desired=1`.

---

## Before You Start

- Read `memory-bank/activeContext.md` — the "Hub Grafana No-data" section records the live fix.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/plugins/argocd.sh` — `deploy_argocd` (~395), the `enable_bootstrap` block (~552),
    `_argocd_deploy_image_updater` (1138), `_argocd_ensure_ghcr_pull_secret`.
- **Do NOT** attempt a full `helm upgrade` of the argocd release anywhere in the deploy path that
  would re-apply `argocd-cm`/`argocd-rbac-cm` — those are intentionally kubectl-patched with OIDC/RBAC
  after install.

---

## Fix — two durable changes in `scripts/plugins/argocd.sh`

### Change 1 — idempotent "ensure argocd ServiceMonitors" step

Add a private function `_argocd_ensure_servicemonitors` that is CRD-guarded and renders **only** the
ServiceMonitor objects from the chart (with `--api-versions monitoring.coreos.com/v1` so the SM
templates are emitted regardless of what the live-cluster capability probe returned at install), then
`kubectl apply`s them. This is idempotent, avoids the `argocd-cm` field-ownership conflict entirely,
and is order-independent w.r.t. the monitoring CRD.

Behavior:
- If the `servicemonitors.monitoring.coreos.com` CRD is absent → log and `return 0` (no-op; a
  mesh/monitoring-less install must not fail).
- Render: `_helm template "$ARGOCD_HELM_RELEASE" "$ARGOCD_HELM_CHART_REF" -n "$ARGOCD_NAMESPACE"
  --api-versions monitoring.coreos.com/v1` plus the same values/version args the install used, filter
  to `kind == ServiceMonitor` (use `yq`, matching the existing repo pattern), and `_kubectl apply -f -`.

**Chart version — read this carefully, there are two decoy variables:**

- `ARGOCD_CHART_VERSION` (`scripts/plugins/argocd.sh:53`, default `7.8.1`) is **NOT** the install
  version. It is used only as an annotation at line 1317. **Do NOT use it here.**
- `ARGOCD_HELM_CHART_VERSION` (`scripts/plugins/argocd.sh:465-467`) is the real one. It is **unset by
  default**, so the install floats — which is why the live hub release is chart `10.1.4`, not `7.8.1`.

The render MUST mirror the install's version logic exactly, or you will render ServiceMonitors from a
different chart version than the release that is actually deployed (wrong label/port selectors):

```bash
   local -a sm_args=()
   if [[ -n "${ARGOCD_HELM_CHART_VERSION:-}" ]]; then
      sm_args+=(--version "$ARGOCD_HELM_CHART_VERSION")
   fi
```

Do NOT hardcode a version. Do NOT substitute `ARGOCD_CHART_VERSION`.

**Call site — `deploy_argocd` cannot see the values file:**

The values file is a `local` built inside `_argocd_helm_deploy_release` and is `rm -f`'d at the end of
that function (`scripts/plugins/argocd.sh:559-561`). Therefore call `_argocd_ensure_servicemonitors`
**from inside `_argocd_helm_deploy_release`, after the `helm upgrade --install` block and BEFORE the
`rm -f "$values_file"` cleanup**, passing it the same `helm_args`/values the install used. Do NOT add a
second values path, and do NOT call it from `deploy_argocd` — the file is gone by then.

### Change 2 — ensure image-updater (+ ghcr-pull-secret) is deployed on the standard hub bootstrap

`_argocd_deploy_image_updater` already calls `_argocd_ensure_ghcr_pull_secret` and `apply -k`s the
kustomization. The gap is that its only call site is inside the `if (( enable_bootstrap ))` block at
`scripts/plugins/argocd.sh:550`.

**The fix is exactly one thing: hoist that call out of the `enable_bootstrap` block** so it runs on
every hub `deploy_argocd`, placed immediately before the `if (( enable_bootstrap ))` line. Leave the
rest of the bootstrap block untouched — do NOT restructure it.

**Do NOT add a `CLUSTER_ROLE` guard.** `deploy_argocd` already returns early for app clusters at
`scripts/plugins/argocd.sh:408`, so anything reached inside it is hub-only by construction. A second
guard inside `_argocd_deploy_image_updater` is redundant scope creep.

Do not change the `ARGOCD_SKIP_IMAGE_UPDATER=1` opt-out — it already lives at the top of the function.

Keep both changes minimal and hub-scoped; do not alter app-cluster behavior.

---

## Rules

- `shellcheck -S warning scripts/plugins/argocd.sh` → zero new warnings (also `-S error`, CI parity).
- Add/extend a BATS test under `scripts/tests/plugins/` that stubs `helm`/`kubectl` and asserts:
  - `_argocd_ensure_servicemonitors` renders with `--api-versions monitoring.coreos.com/v1` and applies
    only `kind: ServiceMonitor` objects;
  - it is a no-op (returns 0, applies nothing) when the ServiceMonitor CRD is absent.
  Add the new file to the CI `bats` invocation in `.github/workflows/ci.yml` (it must pass standalone).
- Do NOT run any live `helm`/`kubectl`/`argocd` against a real cluster — static/stub only. Claude did
  the live remediation already and will re-verify durability on the next hub rebuild.
- Do NOT `helm upgrade` the argocd release in a way that re-applies `argocd-cm`/`argocd-rbac-cm`.

---

## Definition of Done

- [ ] `_argocd_ensure_servicemonitors` added (CRD-guarded, `--api-versions`, applies only SM kinds).
- [ ] It is called from **inside `_argocd_helm_deploy_release`**, after the `helm upgrade --install`
      block and before the `rm -f "$values_file"` cleanup — NOT from `deploy_argocd`.
- [ ] Version logic mirrors the install: `--version` only when `ARGOCD_HELM_CHART_VERSION` is set.
      `ARGOCD_CHART_VERSION` (7.8.1) is NOT referenced anywhere in the new code.
- [ ] `_argocd_deploy_image_updater` call hoisted out of the `if (( enable_bootstrap ))` block; no new
      `CLUSTER_ROLE` guard added.
- [ ] New/extended BATS test passes standalone and is wired into CI; `shellcheck` clean (warning+error)
      — paste the actual output of `shellcheck -S warning`, `shellcheck -S error`, and the `bats` run.
- [ ] `git show <sha> --stat` shows **exactly three files** — `scripts/plugins/argocd.sh`, the new test
      file, and `.github/workflows/ci.yml` — and nothing else.
- [ ] Committed + pushed to `k3d-manager-v1.16.0`; push verified with
      `git log origin/k3d-manager-v1.16.0 --oneline -1`.
- [ ] memory-bank updated with the commit SHA and task status — as a **separate commit**.

**Commit message (exact):**
```
fix(argocd): ensure hub argocd ServiceMonitors + image-updater on deploy
```

### Live re-verify — Claude runs this after the push (NOT Codex)

On the next hub `deploy_argocd` (or rebuild), confirm the 4 argocd ServiceMonitors and the
image-updater deployment come up without manual intervention, `argocd_app_info` is non-zero, and the
Grafana dashboard populates.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT `helm upgrade`/force/`--take-ownership` the argocd release against `argocd-cm`/`argocd-rbac-cm`.
- Do NOT modify files other than `scripts/plugins/argocd.sh`, the new test, and `.github/workflows/ci.yml`.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT change app-cluster (`CLUSTER_ROLE=app`) behavior.
