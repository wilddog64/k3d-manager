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

---
---

# ROUND 2 — required follow-up to `aef82f5a` (READ THIS, it supersedes Change 2 above)

Round 1 landed as `aef82f5a`. Claude verified it independently: every mechanical gate passed
(shellcheck warning+error 0, bats 2/2, `_agent_audit` 0, exactly 3 files, exact commit message,
memory-bank in a separate commit `aa5690bd`), and all three amendments in Change 1 were honored
correctly. **But two defects make the fix inert in production.** Round 2 fixes both.

Round 1's `_argocd_ensure_servicemonitors` function body is **correct and stays** — do not rewrite it.
Only the two changes below are in scope.

## Blocker A — Change 2 edited dead code; image-updater is still never deployed

`aef82f5a` hoisted `_argocd_deploy_image_updater` out of the `enable_bootstrap` block inside
`_argocd_configure_post_deploy`. **That function has zero callers anywhere in the repo:**

```
$ grep -rn '_argocd_configure_post_deploy' scripts/     # excluding scripts/lib/foundation
scripts/plugins/argocd.sh:576:function _argocd_configure_post_deploy() {     ← definition only
```

The live path is `deploy_argocd` → `_argocd_helm_deploy_release` → wait → `_argocd_ensure_logged_in`
→ `deploy_argocd_bootstrap`, and `deploy_argocd_bootstrap` deploys only AppProject +
ApplicationSets. So the hoist changed nothing.

(Round 1's spec text said the bootstrap branch "was not exercised on this hub." That was wrong —
the whole containing function is orphaned, which is why image-updater was never deployed anywhere.)

### A1 — revert the Round 1 hoist (put the dead-code hunk back exactly as it was)

`_argocd_configure_post_deploy` is dead; do not leave a stray call in it. Pure revert of that hunk.

**Exact old block:**

```bash
   _argocd_deploy_image_updater

   if (( enable_bootstrap )); then
      _info "[argocd] Deploying GitOps bootstrap resources"
      if (( ! skip_appproject )); then
```

**Exact new block:**

```bash
   if (( enable_bootstrap )); then
      _info "[argocd] Deploying GitOps bootstrap resources"
      _argocd_deploy_image_updater
      if (( ! skip_appproject )); then
```

Do NOT delete `_argocd_configure_post_deploy` in this round — dead-code removal is a separate
owner decision, flagged below.

### A2 — add the call to the LIVE path: `deploy_argocd_bootstrap`

`deploy_argocd_bootstrap` already has its own `CLUSTER_ROLE=app` early return at the top of the
function, so this stays hub-only. Place the call after the two "ArgoCD must already be deployed"
precondition checks and before the AppProject block.

**Exact old block:**

```bash
   # Deploy AppProject
   if (( ! skip_appproject )); then
      _argocd_deploy_appproject
   fi
```

**Exact new block:**

```bash
   _argocd_deploy_image_updater

   # Deploy AppProject
   if (( ! skip_appproject )); then
      _argocd_deploy_appproject
   fi
```

Do NOT add a `CLUSTER_ROLE` guard. Do NOT touch the `ARGOCD_SKIP_IMAGE_UPDATER=1` opt-out.

## Blocker B — the CRD guard aborts the deploy instead of skipping

```bash
if ! _kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
```

`_kubectl` → `_run_command` → non-zero exit → `_run_command_handle_failure` → `soft=0` → `_err` →
**`exit 1`**. On a cluster without the ServiceMonitor CRD, `deploy_argocd` dies instead of no-op'ing
— the opposite of the requirement above ("a mesh/monitoring-less install must not fail"). The `if !`
never gets to evaluate. `--no-exit` is what sets `soft=1`; every sibling guard in this file already
uses it (`scripts/plugins/argocd.sh:417`, `:421`, `:443`).

**Exact old block:**

```bash
   if ! _kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
```

**Exact new block:**

```bash
   if ! _kubectl --no-exit get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
```

## Blocker B2 — the Round 1 test locks the bug in and must be updated

`scripts/tests/plugins/argocd_servicemonitors_ensure.bats` stubs `_kubectl` with a plain function
that `return 1`s, so `_run_command`/`_err` are never reached — the test passes while production
would `exit 1`. Worse, both tests assert the exact argv **without** `--no-exit`, so they will FAIL
once Blocker B is fixed.

In **both** test cases, update the stub matcher and the assertion:

**Exact old (stub, appears twice — once per test):**

```bash
    if [[ "$*" == "get crd servicemonitors.monitoring.coreos.com" ]]; then
```

**Exact new (both sites):**

```bash
    if [[ "$*" == "--no-exit get crd servicemonitors.monitoring.coreos.com" ]]; then
```

**Exact old (assertion, appears twice — once per test):**

```bash
  [ "${kubectl_calls[0]}" = "get crd servicemonitors.monitoring.coreos.com" ]
```

**Exact new (both sites):**

```bash
  [ "${kubectl_calls[0]}" = "--no-exit get crd servicemonitors.monitoring.coreos.com" ]
```

### B3 — add a regression test that the call site is LIVE, not orphaned

The entire Round 1 failure was an unverified call site. Add one more test to the same bats file that
asserts `_argocd_deploy_image_updater` is invoked from inside the body of `deploy_argocd_bootstrap`
— extract the function body statically and grep it, so it cannot pass against dead code:

```bash
@test "deploy_argocd_bootstrap calls _argocd_deploy_image_updater" {
  run awk '/^function deploy_argocd_bootstrap\(\)/,/^}$/' \
    "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_deploy_image_updater"* ]]
}
```

Use `${BATS_TEST_DIRNAME}/../../plugins/argocd.sh` — that is the exact path form `setup()` already
uses at line 6 of this file. Do NOT introduce a new repo-root variable or path helper.

## Round 2 Rules

- Do NOT rewrite `_argocd_ensure_servicemonitors` — its body is correct as landed in `aef82f5a`.
- Do NOT delete `_argocd_configure_post_deploy` (dead-code removal = separate owner decision).
- `shellcheck -S warning` AND `-S error` on `scripts/plugins/argocd.sh` → zero warnings; paste output.
- `bats scripts/tests/plugins/argocd_servicemonitors_ensure.bats` → must pass standalone (3 tests
  now); paste output. Capture the exit code on its OWN line, never after `; echo`.
- `./scripts/k3d-manager _agent_audit` → exit 0; paste it.
- No live `helm`/`kubectl`/`argocd` against any cluster — static/stub only.

## Round 2 Definition of Done

- [ ] A1 — Round 1 hoist reverted inside `_argocd_configure_post_deploy` (hunk restored verbatim).
- [ ] A2 — `_argocd_deploy_image_updater` called from `deploy_argocd_bootstrap` before the AppProject
      block; no new `CLUSTER_ROLE` guard.
- [ ] B — `--no-exit` added to the `get crd` guard in `_argocd_ensure_servicemonitors`.
- [ ] B2 — both stub matchers and both assertions in the bats file updated to expect `--no-exit`.
- [ ] B3 — new "deploy_argocd_bootstrap calls _argocd_deploy_image_updater" test added and passing.
- [ ] `grep -c '_argocd_deploy_image_updater' scripts/plugins/argocd.sh` → **3**
      (the function definition, the dead-code call restored by A1, the new live call from A2).
- [ ] `git show <sha> --stat` shows **exactly two files** — `scripts/plugins/argocd.sh` and
      `scripts/tests/plugins/argocd_servicemonitors_ensure.bats`. `.github/workflows/ci.yml` is
      already wired from Round 1 — do NOT touch it again.
- [ ] Pushed to `k3d-manager-v1.16.0`; verified with `git log origin/k3d-manager-v1.16.0 --oneline -1`.
- [ ] memory-bank updated with the SHA — as a **separate commit**.

**Round 2 commit message (exact):**
```
fix(argocd): call image-updater from live bootstrap path + no-exit CRD guard
```

## Flagged for owner — NOT in scope for Round 2

`_argocd_configure_post_deploy` (`scripts/plugins/argocd.sh:576`) has been orphaned since
`aef115a0`/`e013d23b`. It still contains Istio VirtualService creation and the Vault/ESO
configuration call, none of which run. Worth a separate audit: either wire it back in or delete it.
