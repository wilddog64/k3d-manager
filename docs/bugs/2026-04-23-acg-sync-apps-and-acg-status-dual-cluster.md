# Bug: acg-sync-apps fragile port-forward + acg-status Hub blind spot

**Branch:** `k3d-manager-v1.1.0`
**Files:** `bin/acg-sync-apps`, `bin/acg-status`

---

## Problems

### 1. `bin/acg-sync-apps` — `sleep 3` is fragile

`kubectl port-forward` is started in the background and the script waits a fixed 3 seconds before continuing.
On a loaded host the port-forward may not be listening yet; on a fast host 3 seconds is wasted.
The ArgoCD login that follows fails silently when the port is not yet open.

### 2. `bin/acg-sync-apps` — hardcoded `cicd/data-layer` app name

All three `argocd app` invocations hardcode `cicd/data-layer`.
The `cicd/` namespace prefix is only valid when ArgoCD app-in-any-namespace is enabled **and** the
Application resource lives in the `cicd` namespace.
If either condition is false the CLI returns "app not found" and the sync is silently skipped.
The app name must be configurable and the script must guard against "app not found" before syncing.

### 3. `bin/acg-status` — Hub cluster never checked

`acg-status` shows tunnel, nodes, pods, and ArgoCD apps for the **app cluster only**.
The local Hub (`k3d-k3d-cluster`) is never surfaced, so operators have no single-pane view of
both clusters' health after `acg-up`.

---

## Before You Start

1. Read `bin/acg-sync-apps` and `bin/acg-status` in full.
2. Run `shellcheck -S warning bin/acg-sync-apps bin/acg-status` — record the baseline warning count.
3. Do not install any new dependencies. All tools used (`curl`, `kubectl`, `argocd`, `k3d`, `aws`)
   are already available in the environment.
4. Do not change `INFRA_CONTEXT`, `APP_CONTEXT`, or `ARGOCD_NS` default values.

---

## Fix A — `bin/acg-sync-apps`

### Change 1: replace `sleep 3` with poll loop

**Old** (lines 34–38):
```bash
_info "[sync-apps] Starting argocd-server port-forward..."
kubectl port-forward svc/argocd-server -n "${ARGOCD_NS}" 8080:443 \
  --context "${INFRA_CONTEXT}" >/dev/null 2>&1 &
_pf_pid=$!
sleep 3
```

**New**:
```bash
_info "[sync-apps] Starting argocd-server port-forward..."
kubectl port-forward svc/argocd-server -n "${ARGOCD_NS}" 8080:443 \
  --context "${INFRA_CONTEXT}" >/dev/null 2>&1 &
_pf_pid=$!
_pf_ready=0
for _i in $(seq 1 15); do
  if curl -sk --max-time 1 https://localhost:8080/ >/dev/null 2>&1; then
    _pf_ready=1
    break
  fi
  sleep 1
done
if [[ "${_pf_ready}" -eq 0 ]]; then
  _info "[sync-apps] ERROR: argocd-server port-forward not ready after 15s — aborting"
  exit 1
fi
```

### Change 2: make app name configurable; add existence guard

Add `ARGOCD_APP` env var declaration alongside the other env vars (after line 23):

**Old** (lines 21–23):
```bash
INFRA_CONTEXT="${INFRA_CONTEXT:-k3d-k3d-cluster}"
APP_CONTEXT="${APP_CONTEXT:-ubuntu-k3s}"
ARGOCD_NS="${ARGOCD_NS:-cicd}"
```

**New**:
```bash
INFRA_CONTEXT="${INFRA_CONTEXT:-k3d-k3d-cluster}"
APP_CONTEXT="${APP_CONTEXT:-ubuntu-k3s}"
ARGOCD_NS="${ARGOCD_NS:-cicd}"
ARGOCD_APP="${ARGOCD_APP:-data-layer}"
```

Replace the terminate-op + wait-loop + sync block with app existence guard:

**Old** (lines 47–63):
```bash
_info "[sync-apps] Terminating any in-progress operation on data-layer..."
argocd app terminate-op cicd/data-layer 2>/dev/null || true

_info "[sync-apps] Waiting for operation to clear..."
for _i in $(seq 1 20); do
  _phase=$(argocd app get cicd/data-layer --output json 2>/dev/null \
    | grep -o '"phase":"[^"]*"' | head -1 | grep -o '[^"]*$' || echo "none")
  if [[ "$_phase" == "none" || "$_phase" == "Succeeded" || \
        "$_phase" == "Failed"  || "$_phase" == "Error" ]]; then
    break
  fi
  _info "[sync-apps] Operation still ${_phase}, waiting... (${_i}/20)"
  sleep 3
done

_info "[sync-apps] Syncing data-layer (async)..."
argocd app sync cicd/data-layer --async
```

**New**:
```bash
if ! argocd app get "${ARGOCD_APP}" >/dev/null 2>&1; then
  _info "[sync-apps] ERROR: ArgoCD app '${ARGOCD_APP}' not found — is bootstrap complete?"
  exit 1
fi

_info "[sync-apps] Terminating any in-progress operation on ${ARGOCD_APP}..."
argocd app terminate-op "${ARGOCD_APP}" 2>/dev/null || true

_info "[sync-apps] Waiting for operation to clear..."
for _i in $(seq 1 20); do
  _phase=$(argocd app get "${ARGOCD_APP}" --output json 2>/dev/null \
    | grep -o '"phase":"[^"]*"' | head -1 | grep -o '[^"]*$' || echo "none")
  if [[ "$_phase" == "none" || "$_phase" == "Succeeded" || \
        "$_phase" == "Failed"  || "$_phase" == "Error" ]]; then
    break
  fi
  _info "[sync-apps] Operation still ${_phase}, waiting... (${_i}/20)"
  sleep 3
done

_info "[sync-apps] Syncing ${ARGOCD_APP} (async)..."
argocd app sync "${ARGOCD_APP}" --async
```

Also update the final pod-status line to match:

**Old** (line 65):
```bash
_info "[sync-apps] Pod status (${APP_CONTEXT}):"
```

**New** (no change needed — leave as-is):
```bash
_info "[sync-apps] Pod status (${APP_CONTEXT}):"
```

---

## Fix B — `bin/acg-status`

Add Hub cluster section **before** the `=== Tunnel ===` block.

**Old** (lines 23–28):
```bash
echo "=== Tunnel ==="
if curl -sf --max-time 3 http://localhost:6443 >/dev/null 2>&1; then
  echo "SSH tunnel: UP (port 6443 reachable)"
else
  echo "SSH tunnel: DOWN (port 6443 not reachable)"
fi
```

**New**:
```bash
echo "=== Hub Cluster (${INFRA_CONTEXT}) ==="
kubectl get nodes --context "${INFRA_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach Hub cluster — is k3d running?"

echo ""
echo "=== Pods — all namespaces (${INFRA_CONTEXT}) ==="
kubectl get pods -A --context "${INFRA_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach Hub cluster"

echo ""
echo "=== Tunnel ==="
if curl -sf --max-time 3 http://localhost:6443 >/dev/null 2>&1; then
  echo "SSH tunnel: UP (port 6443 reachable)"
else
  echo "SSH tunnel: DOWN (port 6443 not reachable)"
fi
```

---

## Rules

- `shellcheck -S warning bin/acg-sync-apps bin/acg-status` must produce **zero new warnings** compared
  to baseline (pre-edit warning count recorded in Before You Start step 2).
- Do not add `--no-verify` to any git command.
- Do not touch any file other than `bin/acg-sync-apps` and `bin/acg-status`.

---

## Definition of Done

1. `bin/acg-sync-apps` diff matches Fix A exactly — no extra hunks.
2. `bin/acg-status` diff matches Fix B exactly — no extra hunks.
3. `shellcheck -S warning bin/acg-sync-apps bin/acg-status` exits 0 with no new warnings.
4. Both files committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-sync-apps,acg-status): poll port-forward readiness; configurable app name; show Hub cluster
   ```
5. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
6. `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with real commit SHA.

---

## What NOT To Do

- Do not create a PR.
- Do not skip pre-commit hooks (`--no-verify`).
- Do not change `sleep 3` inside the operation-wait loop (lines 59/60) — that poll is intentional.
- Do not rename `INFRA_CONTEXT` or `APP_CONTEXT`.
- Do not add `--app-namespace` flags — the app name env var handles the naming concern.
- Do not touch `scripts/plugins/argocd.sh`.
- Do not modify files outside `bin/acg-sync-apps` and `bin/acg-status`.
- Do not commit to `main`.
