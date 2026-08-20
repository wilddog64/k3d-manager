# Bug: acg-up uses trycloudflare quick tunnels — URLs change on every run; ArgoCD SSO breaks via public URL

**Branch:** `k3d-manager-v1.4.8`
**File:** `bin/acg-up`

---

## Before You Start

Read this spec in full before touching any file.

```bash
cd ~/src/gitrepo/personal/k3d-manager
git pull origin k3d-manager-v1.4.8
```

Prerequisites already done (do NOT redo):
- Named tunnel created: `cloudflared tunnel create k3d-manager` → ID `bb7ece59-8680-4310-9437-232f862e2773`
- DNS routes created: `argocd.3ai-talk.org` and `frontend.3ai-talk.org` → tunnel
- `~/.cloudflared/config.yml` written with both ingress rules
- Credentials at `~/.cloudflared/bb7ece59-8680-4310-9437-232f862e2773.json`

---

## Problem

Step 10h uses `cloudflared tunnel --url <addr>` (quick tunnel) which:
1. Generates a random `trycloudflare.com` URL on every run — can't bookmark or configure Keycloak with it
2. Runs two separate launchd daemons (one per service) — but the named tunnel serves both via one process
3. ArgoCD SSO redirect fails when accessed via tunnel URL — `argocd-cm` `url` field and Keycloak redirect URIs are not updated

---

## Fix

### Change 1 — Step 10f: patch `argocd-cm` URL after applying it

After line 1011 (`kubectl apply ... argocd-cm.yaml ...`), add a patch to override the `url` field:

**Exact old block (lines 1007–1023):**
```bash
# Apply argocd-cm and argocd-rbac-cm from shopping-cart-infra (now using namespace: cicd)
_infra_root="${REPO_ROOT}/../shopping-carts/shopping-cart-infra"
kubectl apply --context k3d-k3d-cluster \
  -f "${_infra_root}/argocd/config/argocd-cm.yaml" \
  -f "${_infra_root}/argocd/config/argocd-rbac-cm.yaml"

# Patch argocd-secret directly with the OIDC client secret generated earlier in this run.
# The ExternalSecret (argocd-oidc-secret) will take over once ClusterSecretStore is Ready;
# this immediate patch ensures ArgoCD SSO works on first boot before ESO syncs.
kubectl patch secret argocd-secret -n cicd --context k3d-k3d-cluster \
  --type merge \
  --patch "{\"stringData\":{\"oidc.keycloak.clientSecret\":\"${_argocd_client_secret}\"}}"

# Restart argocd-server to pick up the updated argocd-cm and argocd-secret
kubectl rollout restart deployment/argocd-server -n cicd --context k3d-k3d-cluster
kubectl rollout status deployment/argocd-server -n cicd --context k3d-k3d-cluster --timeout=120s
_info "[acg-up] ArgoCD SSO wired: login at https://argocd.shopping-cart.local → Keycloak realm shopping-cart"
```

**Exact new block:**
```bash
# Apply argocd-cm and argocd-rbac-cm from shopping-cart-infra (now using namespace: cicd)
_infra_root="${REPO_ROOT}/../shopping-carts/shopping-cart-infra"
kubectl apply --context k3d-k3d-cluster \
  -f "${_infra_root}/argocd/config/argocd-cm.yaml" \
  -f "${_infra_root}/argocd/config/argocd-rbac-cm.yaml"

# Override ArgoCD URL to Cloudflare public domain (argocd-cm.yaml has local URL)
_argocd_public_url="${ARGOCD_PUBLIC_URL:-https://argocd.3ai-talk.org}"
kubectl patch configmap argocd-cm -n cicd --context k3d-k3d-cluster \
  --type merge -p "{\"data\":{\"url\":\"${_argocd_public_url}\"}}"

# Patch argocd-secret directly with the OIDC client secret generated earlier in this run.
# The ExternalSecret (argocd-oidc-secret) will take over once ClusterSecretStore is Ready;
# this immediate patch ensures ArgoCD SSO works on first boot before ESO syncs.
kubectl patch secret argocd-secret -n cicd --context k3d-k3d-cluster \
  --type merge \
  --patch "{\"stringData\":{\"oidc.keycloak.clientSecret\":\"${_argocd_client_secret}\"}}"

# Restart argocd-server to pick up the updated argocd-cm and argocd-secret
kubectl rollout restart deployment/argocd-server -n cicd --context k3d-k3d-cluster
kubectl rollout status deployment/argocd-server -n cicd --context k3d-k3d-cluster --timeout=120s
_info "[acg-up] ArgoCD SSO wired: login at ${_argocd_public_url} → Keycloak realm shopping-cart"
```

---

### Change 2 — Step 10f: add Keycloak redirect URI for public domain

Add this block immediately after the `kubectl rollout status deployment/argocd-server` line above (before the `_info` line):

**Exact new block to insert:**
```bash
# Add Cloudflare public URL to Keycloak argocd client redirect URIs
_keycloak_token=$(curl -sf \
  -d "client_id=admin-cli&username=admin&password=${_kc_admin_pass}&grant_type=password" \
  "http://keycloak.shopping-cart.local/realms/master/protocol/openid-connect/token" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || true)
if [[ -n "${_keycloak_token}" ]]; then
  _argocd_client_uuid=$(curl -sf \
    -H "Authorization: Bearer ${_keycloak_token}" \
    "http://keycloak.shopping-cart.local/admin/realms/shopping-cart/clients?clientId=argocd" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])" 2>/dev/null || true)
  if [[ -n "${_argocd_client_uuid}" ]]; then
    curl -sf -X PUT \
      -H "Authorization: Bearer ${_keycloak_token}" \
      -H "Content-Type: application/json" \
      "http://keycloak.shopping-cart.local/admin/realms/shopping-cart/clients/${_argocd_client_uuid}" \
      -d "{\"redirectUris\":[\"http://localhost:8080/*\",\"http://argocd.shopping-cart.local/*\",\"https://argocd.shopping-cart.local/*\",\"${_argocd_public_url}/*\"],\"webOrigins\":[\"+\"]}" \
      >/dev/null 2>&1 \
      && _info "[acg-up] Keycloak argocd client: added ${_argocd_public_url}/* to redirectUris" \
      || _warn "[acg-up] Keycloak argocd client redirect URI update failed — SSO via public URL may not work"
  fi
fi
```

Note: `_kc_admin_pass` is set at line 629 of `bin/acg-up` from Vault (`keycloak/admin` → `admin_password`).

---

### Change 3 — Step 10h: replace quick tunnels with named tunnel

**Exact old block (lines 1149–1283):**
```bash
if _is_mac; then
  _info "[acg-up] Step 10h/14 — Installing Cloudflare Tunnels for public ArgoCD + frontend access..."
  _tunnel_dir="${HOME}/.local/share/k3d-manager"
  _tunnel_urls_file="${_tunnel_dir}/tunnel-urls.txt"
  mkdir -p "${_tunnel_dir}"

  if ! command -v cloudflared >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      _info "[acg-up] Installing cloudflared via Homebrew..."
      brew install cloudflared >/dev/null 2>&1 || _warn "[acg-up] cloudflared install failed — skipping tunnels"
    else
      _warn "[acg-up] cloudflared not found and brew unavailable — skipping tunnels"
    fi
  fi

  if command -v cloudflared >/dev/null 2>&1; then
    # ArgoCD tunnel: localhost:8080 (existing port-forward to k3d argocd-server)
    _argocd_tunnel_label="com.k3d-manager.argocd-tunnel"
    _argocd_tunnel_log="${_tunnel_dir}/argocd-tunnel.log"
    _argocd_tunnel_plist="/Library/LaunchDaemons/${_argocd_tunnel_label}.plist"
    _argocd_tunnel_plist_tmp="${_tunnel_dir}/argocd-tunnel.plist"
    _cloudflared_bin="$(command -v cloudflared)"

    cat > "${_argocd_tunnel_plist_tmp}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_argocd_tunnel_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_cloudflared_bin}</string>
    <string>tunnel</string>
    <string>--url</string>
    <string>http://localhost:8080</string>
    <string>--logfile</string>
    <string>${_argocd_tunnel_log}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_argocd_tunnel_log}</string>
  <key>StandardErrorPath</key>
  <string>${_argocd_tunnel_log}</string>
</dict>
</plist>
PLIST

    # Frontend tunnel: 127.0.0.2:80 (Step 10g port-forward to ubuntu-k3s)
    _frontend_tunnel_label="com.k3d-manager.frontend-tunnel"
    _frontend_tunnel_log="${_tunnel_dir}/frontend-tunnel.log"
    _frontend_tunnel_plist="/Library/LaunchDaemons/${_frontend_tunnel_label}.plist"
    _frontend_tunnel_plist_tmp="${_tunnel_dir}/frontend-tunnel.plist"

    cat > "${_frontend_tunnel_plist_tmp}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_frontend_tunnel_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_cloudflared_bin}</string>
    <string>tunnel</string>
    <string>--url</string>
    <string>http://127.0.0.2:80</string>
    <string>--logfile</string>
    <string>${_frontend_tunnel_log}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_frontend_tunnel_log}</string>
  <key>StandardErrorPath</key>
  <string>${_frontend_tunnel_log}</string>
</dict>
</plist>
PLIST

    for _tunnel_label_plist in \
        "${_argocd_tunnel_label}|${_argocd_tunnel_plist}|${_argocd_tunnel_plist_tmp}|${_argocd_tunnel_log}" \
        "${_frontend_tunnel_label}|${_frontend_tunnel_plist}|${_frontend_tunnel_plist_tmp}|${_frontend_tunnel_log}"; do
      _tl="${_tunnel_label_plist%%|*}"
      _rest="${_tunnel_label_plist#*|}"
      _tp="${_rest%%|*}"
      _rest="${_rest#*|}"
      _tpt="${_rest%%|*}"
      _tlog="${_rest#*|}"
      _tunnel_launchctl_log="${_tunnel_dir}/${_tl}-launchctl.log"

      : > "${_tunnel_launchctl_log}"
      _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_tp}" \
        >"${_tunnel_launchctl_log}" 2>&1 || true
      : > "${_tunnel_launchctl_log}"
      if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_tpt}" "${_tp}" \
          >"${_tunnel_launchctl_log}" 2>&1; then
        _warn "[acg-up] failed to install tunnel plist for ${_tl}"
        continue
      fi
      rm -f "${_tpt}"
      : > "${_tunnel_launchctl_log}"
      if ! _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_tp}" \
          >"${_tunnel_launchctl_log}" 2>&1; then
        _warn "[acg-up] failed to bootstrap tunnel for ${_tl}"
      fi
    done

    # Wait up to 30s for both tunnel URLs to appear in logs
    _info "[acg-up] Waiting for Cloudflare tunnel URLs..."
    : > "${_tunnel_urls_file}"
    _tunnel_deadline=$(( $(date +%s) + 30 ))
    while [[ $(date +%s) -lt "${_tunnel_deadline}" ]]; do
      _argocd_url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "${_argocd_tunnel_log}" 2>/dev/null | tail -1 || true)
      _frontend_url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "${_frontend_tunnel_log}" 2>/dev/null | tail -1 || true)
      if [[ -n "${_argocd_url}" && -n "${_frontend_url}" ]]; then
        break
      fi
      sleep 2
    done
    {
      printf 'argocd=%s\n' "${_argocd_url:-unavailable}"
      printf 'frontend=%s\n' "${_frontend_url:-unavailable}"
    } > "${_tunnel_urls_file}"
    _info "[acg-up] Cloudflare tunnel URLs written to ${_tunnel_urls_file}"
    _info "[acg-up] ArgoCD public URL:  ${_argocd_url:-unavailable (check ${_argocd_tunnel_log})}"
    _info "[acg-up] Frontend public URL: ${_frontend_url:-unavailable (check ${_frontend_tunnel_log})}"
    _info "[acg-up] NOTE: ArgoCD SSO requires argocd.shopping-cart.local; use admin credentials via tunnel URL"
  fi
fi
```

**Exact new block:**
```bash
if _is_mac; then
  _info "[acg-up] Step 10h/14 — Installing Cloudflare named tunnel (argocd.3ai-talk.org + frontend.3ai-talk.org)..."
  _tunnel_dir="${HOME}/.local/share/k3d-manager"
  _tunnel_urls_file="${_tunnel_dir}/tunnel-urls.txt"
  _cloudflared_config="${HOME}/.cloudflared/config.yml"
  mkdir -p "${_tunnel_dir}"

  if ! command -v cloudflared >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      _info "[acg-up] Installing cloudflared via Homebrew..."
      brew install cloudflared >/dev/null 2>&1 || _warn "[acg-up] cloudflared install failed — skipping tunnel"
    else
      _warn "[acg-up] cloudflared not found and brew unavailable — skipping tunnel"
    fi
  fi

  if command -v cloudflared >/dev/null 2>&1 && [[ -f "${_cloudflared_config}" ]]; then
    _named_tunnel_label="com.k3d-manager.cloudflare-tunnel"
    _named_tunnel_log="${_tunnel_dir}/cloudflare-tunnel.log"
    _named_tunnel_plist="/Library/LaunchDaemons/${_named_tunnel_label}.plist"
    _named_tunnel_plist_tmp="${_tunnel_dir}/cloudflare-tunnel.plist"
    _cloudflared_bin="$(command -v cloudflared)"

    cat > "${_named_tunnel_plist_tmp}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_named_tunnel_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_cloudflared_bin}</string>
    <string>tunnel</string>
    <string>--config</string>
    <string>${_cloudflared_config}</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_named_tunnel_log}</string>
  <key>StandardErrorPath</key>
  <string>${_named_tunnel_log}</string>
</dict>
</plist>
PLIST

    _tunnel_launchctl_log="${_tunnel_dir}/cloudflare-tunnel-launchctl.log"
    : > "${_tunnel_launchctl_log}"
    _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_named_tunnel_plist}" \
      >"${_tunnel_launchctl_log}" 2>&1 || true
    : > "${_tunnel_launchctl_log}"
    if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_named_tunnel_plist_tmp}" "${_named_tunnel_plist}" \
        >"${_tunnel_launchctl_log}" 2>&1; then
      _warn "[acg-up] failed to install tunnel plist — skipping"
    else
      rm -f "${_named_tunnel_plist_tmp}"
      : > "${_tunnel_launchctl_log}"
      if ! _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_named_tunnel_plist}" \
          >"${_tunnel_launchctl_log}" 2>&1; then
        _warn "[acg-up] failed to bootstrap cloudflare tunnel"
      fi
    fi

    _argocd_public_url="${ARGOCD_PUBLIC_URL:-https://argocd.3ai-talk.org}"
    _frontend_public_url="${FRONTEND_PUBLIC_URL:-https://frontend.3ai-talk.org}"
    {
      printf 'argocd=%s\n' "${_argocd_public_url}"
      printf 'frontend=%s\n' "${_frontend_public_url}"
    } > "${_tunnel_urls_file}"
    _info "[acg-up] Cloudflare tunnel URLs written to ${_tunnel_urls_file}"
    _info "[acg-up] ArgoCD public URL:   ${_argocd_public_url}"
    _info "[acg-up] Frontend public URL: ${_frontend_public_url}"
  elif [[ ! -f "${_cloudflared_config}" ]]; then
    _warn "[acg-up] ~/.cloudflared/config.yml not found — skipping named tunnel (run: cloudflared tunnel login && cloudflared tunnel create k3d-manager)"
  fi
fi
```

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched
- Do NOT remove the old argocd-tunnel or frontend-tunnel plist files from `/Library/LaunchDaemons/` — that is a runtime concern, not a code concern
- The variable name for Keycloak admin password must match what is already used in the file — check with grep before writing

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | 3 targeted edits: ArgoCD URL patch, Keycloak redirect URI update, named tunnel replacing quick tunnels |

---

## Definition of Done

- [ ] Step 10f patches `argocd-cm` `url` to `${ARGOCD_PUBLIC_URL:-https://argocd.3ai-talk.org}` after applying it from shopping-cart-infra
- [ ] Step 10f adds `${_argocd_public_url}/*` to Keycloak argocd client `redirectUris` via Admin API
- [ ] Step 10h uses `cloudflared tunnel --config ~/.cloudflared/config.yml run` (single daemon, named tunnel)
- [ ] Step 10h falls back with `_warn` if `~/.cloudflared/config.yml` is missing
- [ ] `tunnel-urls.txt` contains static `argocd=https://argocd.3ai-talk.org` and `frontend=https://frontend.3ai-talk.org`
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.8`
- [ ] `git push origin k3d-manager-v1.4.8` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

**Commit message (exact):**
```
fix(acg-up): replace trycloudflare quick tunnels with named cloudflare tunnel; wire ArgoCD URL + Keycloak redirect
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.8`
- Do NOT hardcode the tunnel ID — use `cloudflared tunnel run` which reads `~/.cloudflared/config.yml`
- Do NOT remove the bootout of the OLD plist names (`com.k3d-manager.argocd-tunnel`, `com.k3d-manager.frontend-tunnel`) — those are separate runtime cleanup, not part of this spec
