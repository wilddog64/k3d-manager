# Feature: Cloudflare Tunnel for public ArgoCD + frontend access

**Branch:** `k3d-manager-v1.4.6`
**Files:**
- `bin/acg-up` — add Step 10h after Step 10g

---

## Before You Start

```
git pull origin k3d-manager-v1.4.6
```

Read this spec in full before touching any file.
This spec depends on `docs/bugs/2026-05-17-frontend-serviceentry-blocked-replace-with-direct-portforward.md`
being committed first. The new Step 10h goes after the Step 10g from that fix.

---

## Problem

ArgoCD (`https://argocd.shopping-cart.local`) and the frontend (`http://frontend.shopping-cart.local`)
are only accessible from the Mac that ran `make up`. There is no way to share these URLs with
another device, a teammate, or a phone browser.

Let's Encrypt is not suitable (`.local` TLS hostnames require DNS-01 challenge against a public
domain; the ACG public IP also changes on every sandbox rebuild). Cloudflare Tunnel is the correct
solution: `cloudflared` initiates an outbound connection to Cloudflare's edge (no firewall changes
needed), and Cloudflare provides a stable HTTPS URL for the session.

---

## Design

| Service | Local endpoint | Public URL |
|---------|---------------|------------|
| ArgoCD | `http://localhost:8080` (existing launchd port-forward to k3d argocd-server) | `https://<random>.trycloudflare.com` |
| Frontend | `http://127.0.0.2:80` (Step 10g launchd port-forward to ubuntu-k3s) | `https://<random>.trycloudflare.com` |

- Uses **trycloudflare.com** (no Cloudflare account, no config file, no token required)
- Each tunnel URL is random and changes if the launchd agent restarts or the Mac reboots
- ArgoCD is accessible with admin credentials or local Keycloak SSO (SSO callback URLs are
  tied to `argocd.shopping-cart.local`; SSO will not work via the tunnel URL — admin login works)
- The tunnel URLs are logged at the end of `acg-up` and written to
  `~/.local/share/k3d-manager/tunnel-urls.txt` so they can be retrieved later

---

## Fix

Add **Step 10h** immediately after the `_is_mac` closing `fi` of Step 10g, before `_info "[acg-up] Step 11/14"`.

### Exact insertion point

**After (end of Step 10g block):**
```bash
  _info "[acg-up] Frontend HTTP listener active: http://frontend.shopping-cart.local → ubuntu-k3s svc/frontend via 127.0.0.2 (launchd: ${_frontend_browser_label})"
fi
```

**Before:**
```bash
_info "[acg-up] Step 11/14 — Verifying ClusterSecretStore..."
```

### Exact new block (insert between the two lines above):

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

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add Step 10h after Step 10g `fi`, before `_info "[acg-up] Step 11/14"` |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files modified
- cloudflared install is best-effort; if it fails, tunnels are skipped with `_warn` (never `_err`)
- The tunnel log grep uses `/dev/null` fallback so it never fails on missing log file

---

## Definition of Done

- [ ] Step 10h block inserted after Step 10g `fi`, before Step 11 line (exact new block above)
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

**Commit message (exact):**
```
feat(acg-up): add Cloudflare Tunnel launchd agents for public ArgoCD + frontend access
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT use a Cloudflare account or config file — trycloudflare.com requires no credentials
- Do NOT make tunnel failures block `acg-up` — always use `_warn`, never `_err` for tunnel steps
