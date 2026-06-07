# Bug: acg-up Keycloak port-forward silently fails — port 18080 already occupied

**Branch:** `k3d-manager-v1.6.3`
**Files:** `bin/acg-up`

---

## Problem

Step 10d of `acg-up`/`acg-resume` starts a Keycloak port-forward on `localhost:18080`.
The port-forward is backgrounded and disowned — if port 18080 is already in use (e.g. by
a previous `kubectl port-forward svc/argocd-server 18080:443`), the new process fails to
bind and exits silently. All 5 curl attempts then hit whatever was already listening on
18080 (ArgoCD in this case), receive non-Keycloak responses, and fail to obtain an admin
token. Result: `ERROR: Could not get Keycloak admin token after 5 attempts`.

**Root cause:** `bin/acg-up` line 719 — the port-forward is started with no check for an
existing listener on `_kc_pf_port` (18080). The error is discarded because the process
is immediately disowned.

**Confirmed:** at time of failure, `lsof -i :18080` showed:
```
kubectl 24099 … kubectl port-forward svc/argocd-server 18080:443 -n cicd --context k3d-k3d-cluster
```

---

## Reproduction

1. Start an ArgoCD port-forward on 18080: `kubectl port-forward svc/argocd-server 18080:443 -n cicd --context k3d-k3d-cluster &`
2. Run `/acg-resume` in Slack.
3. Step 10d fails: `ERROR: Could not get Keycloak admin token after 5 attempts`.

---

## Fix

### Change 1 — `bin/acg-up`: kill any existing listener on `_kc_pf_port` before starting

**Exact old block (lines 718–722):**

```bash
  kubectl port-forward deployment/keycloak -n identity --context k3d-k3d-cluster "${_kc_pf_port}:8080" \
    >>"${_ACG_STATE_DIR}/logs/keycloak-pf.log" 2>&1 &
  _kc_pf_pid=$!
  disown "${_kc_pf_pid}"
```

**Exact new block:**

```bash
  _existing_pf_pid=$(lsof -ti :"${_kc_pf_port}" 2>/dev/null | head -1 || true)
  if [[ -n "${_existing_pf_pid}" ]]; then
    _info "[acg-up] Port ${_kc_pf_port} in use by PID ${_existing_pf_pid} — killing before Keycloak port-forward"
    kill "${_existing_pf_pid}" 2>/dev/null || true
    sleep 1
  fi
  kubectl port-forward deployment/keycloak -n identity --context k3d-k3d-cluster "${_kc_pf_port}:8080" \
    >>"${_ACG_STATE_DIR}/logs/keycloak-pf.log" 2>&1 &
  _kc_pf_pid=$!
  disown "${_kc_pf_pid}"
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Kill existing listener on `_kc_pf_port` before starting Keycloak port-forward |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `lsof -ti` check added before the Keycloak port-forward start
- [ ] Existing listener killed and 1s sleep given before new port-forward
- [ ] `shellcheck -S warning bin/acg-up` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.3`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-up): kill existing listener on kc_pf_port before starting Keycloak port-forward
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.3`
