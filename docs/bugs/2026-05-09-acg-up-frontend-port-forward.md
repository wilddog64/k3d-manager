# Bugfix: acg-up missing frontend port-forward launchd agent

**Branch:** `k3d-manager-v1.4.5`
**File:** `bin/acg-up` (after step 12, before final log line)

---

## Before You Start

1. `git pull origin k3d-manager-v1.4.5` in the k3d-manager repo
2. Read `bin/acg-up` lines 670–673 (end of file) in full before touching anything
3. Read step 4b (lines 158–199) — the frontend launchd block must follow the same pattern exactly

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.5`
- Do NOT change the ArgoCD or Keycloak launchd blocks — only add the new frontend block

---

## Problem

`acg-up` sets up auto-restarting launchd port-forwards for ArgoCD (step 4b, `localhost:8080`) and a
temporary port-forward for Keycloak (step 10d, `localhost:18080`), but does not set up a persistent
port-forward for the shopping-cart frontend. The frontend is a `ClusterIP` service on the remote
`ubuntu-k3s` cluster (namespace `shopping-cart-apps`, service `frontend`, port 80). Users have no
way to reach it without running a manual `kubectl port-forward` after every `acg-up`.

---

## Fix

Add a new step after step 12 (sandbox TTL watcher) that installs a launchd agent for the frontend,
following the same pattern as the ArgoCD port-forward (step 4b).

### Change — `bin/acg-up` (after step 12)

Insert after the line:
```bash
_info "[acg-up] Cluster is up."
```

Wait, actually insert BEFORE the `_info "[acg-up] Cluster is up."` line, as a new step 13:

```bash
_info "[acg-up] Step 13/14 — Installing frontend port-forward launchd agent (localhost:3000, auto-restart)..."
_frontend_pf_label="com.k3d-manager.frontend-port-forward"
_frontend_pf_plist="${HOME}/Library/LaunchAgents/${_frontend_pf_label}.plist"
_frontend_pf_log="${HOME}/.local/share/k3d-manager/frontend-pf.log"
mkdir -p "$(dirname "${_frontend_pf_log}")" "$(dirname "${_frontend_pf_plist}")"
cat > "${_frontend_pf_plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_frontend_pf_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/kubectl</string>
    <string>port-forward</string>
    <string>svc/frontend</string>
    <string>--namespace</string>
    <string>shopping-cart-apps</string>
    <string>--context</string>
    <string>ubuntu-k3s</string>
    <string>3000:80</string>
  </array>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_frontend_pf_log}</string>
  <key>StandardErrorPath</key>
  <string>${_frontend_pf_log}</string>
</dict>
</plist>
PLIST
if launchctl list "${_frontend_pf_label}" >/dev/null 2>&1; then
  launchctl unload "${_frontend_pf_plist}" 2>/dev/null || true
fi
launchctl load "${_frontend_pf_plist}"
sleep 2
if curl -sf --max-time 5 http://localhost:3000 >/dev/null 2>&1; then
  _info "[acg-up] Frontend reachable at http://localhost:3000 (launchd: ${_frontend_pf_label})"
else
  _info "[acg-up] Frontend launchd agent loaded — UI may take a moment to be ready at http://localhost:3000"
fi
```

**Insertion point:** after the `acg_watch_start` call (step 12), before `_info "[acg-up] Cluster is up."`.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add step 13: frontend launchd port-forward (`localhost:3000 → ubuntu-k3s/shopping-cart-apps/frontend:80`) |

---

## Definition of Done

- [ ] New step 13 block added to `bin/acg-up` after `acg_watch_start`
- [ ] Plist written to `~/Library/LaunchAgents/com.k3d-manager.frontend-port-forward.plist`
- [ ] Log at `~/.local/share/k3d-manager/frontend-pf.log`
- [ ] `launchctl list | grep frontend` shows agent loaded after `make up`
- [ ] `curl -s http://localhost:3000` returns non-empty HTML (frontend is reachable)
- [ ] Committed and pushed to `k3d-manager-v1.4.5`

**Commit message (exact):**
```
fix(acg-up): add frontend port-forward launchd agent (localhost:3000, ubuntu-k3s)
```
