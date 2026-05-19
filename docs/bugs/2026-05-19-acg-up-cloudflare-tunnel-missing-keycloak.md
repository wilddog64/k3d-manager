# Bugfix: acg-up — Cloudflare tunnel missing Keycloak; config not generated

**Branch:** `k3d-manager-v1.4.9`
**Files:** `bin/acg-up`, `scripts/etc/cloudflared-config.yml.tmpl` (new)

---

## Problem

`keycloak.3ai-talk.org` is inaccessible from outside the local network because:

1. `bin/acg-up` Step 10h does not generate or update `~/.cloudflared/config.yml` — it
   only restarts the launchd service with whatever config already exists. On a fresh
   machine the config has no Keycloak entry, so Cloudflare never proxies to Keycloak.
2. Step 10h's log message and `tunnel-urls.txt` only advertise ArgoCD + Frontend; Keycloak
   is not listed, making it invisible in `make up` output.

**Symptom:** Browsing from outside the home network redirects the OAuth flow to
`keycloak.shopping-cart.local`, which does not resolve externally
(`ERR_NAME_NOT_RESOLVED`).

**Root cause:** No template for `~/.cloudflared/config.yml` exists in the repo; Step 10h
never writes the file — it depends on it already being present with the correct entries.

---

## Reproduction

1. Delete `~/.cloudflared/config.yml`.
2. Run `make up`.
3. Try to log in to the frontend from a machine outside the home network.
4. Browser redirects to `keycloak.shopping-cart.local` and fails to resolve.

---

## Fix

### Change 1 — `scripts/etc/cloudflared-config.yml.tmpl` (new file)

Create a config template with all three ingress entries. `CLOUDFLARE_TUNNEL_ID` is
resolved at provision time from the first credentials JSON in `~/.cloudflared/`.

```yaml
tunnel: ${CLOUDFLARE_TUNNEL_ID}
credentials-file: ${CLOUDFLARE_CREDENTIALS_FILE}

ingress:
  - hostname: argocd.${CLOUDFLARE_DOMAIN}
    service: http://localhost:8080
  - hostname: frontend.${CLOUDFLARE_DOMAIN}
    service: http://127.0.0.2:80
  - hostname: keycloak.${CLOUDFLARE_DOMAIN}
    service: http://localhost:80
  - service: http_status:404
```

### Change 2 — `bin/acg-up` Step 10h: generate config from template when missing

After the `cloudflared` binary check (line 1218), before launching the daemon, add a
block that:
1. Detects `CLOUDFLARE_TUNNEL_ID` from the first `*.json` file in `~/.cloudflared/` (the
   credentials JSON filename is the tunnel UUID).
2. Resolves `CLOUDFLARE_DOMAIN` from `${CF_DOMAIN:-3ai-talk.org}`.
3. Generates `~/.cloudflared/config.yml` from the template if the file is missing OR if
   the keycloak entry is absent.

**Exact old block (lines 1218–1219 area — the `if` guard opening):**
```bash
  if command -v cloudflared >/dev/null 2>&1 && [[ -f "${_cloudflared_config}" ]]; then
```

**Exact new block:**
```bash
  _cf_domain="${CF_DOMAIN:-3ai-talk.org}"
  _cf_template="${REPO_ROOT}/scripts/etc/cloudflared-config.yml.tmpl"
  if command -v cloudflared >/dev/null 2>&1; then
    if [[ ! -f "${_cloudflared_config}" ]] || \
        ! grep -q "keycloak.${_cf_domain}" "${_cloudflared_config}" 2>/dev/null; then
      _cf_tunnel_id=""
      _cf_creds_file=""
      for _f in "${HOME}/.cloudflared/"*.json; do
        [[ -f "${_f}" ]] || continue
        _cf_tunnel_id="$(basename "${_f}" .json)"
        _cf_creds_file="${_f}"
        break
      done
      if [[ -n "${_cf_tunnel_id}" ]] && [[ -f "${_cf_template}" ]]; then
        mkdir -p "$(dirname "${_cloudflared_config}")"
        CLOUDFLARE_TUNNEL_ID="${_cf_tunnel_id}" \
        CLOUDFLARE_CREDENTIALS_FILE="${_cf_creds_file}" \
        CLOUDFLARE_DOMAIN="${_cf_domain}" \
          envsubst < "${_cf_template}" > "${_cloudflared_config}"
        _info "[acg-up] Generated ~/.cloudflared/config.yml (tunnel ${_cf_tunnel_id})"
      elif [[ -z "${_cf_tunnel_id}" ]]; then
        _warn "[acg-up] No Cloudflare tunnel credentials found in ~/.cloudflared/ — skipping config generation (run: cloudflared tunnel login && cloudflared tunnel create k3d-manager)"
      else
        _warn "[acg-up] ${_cf_template} not found — skipping config generation"
      fi
    fi
  fi
  if command -v cloudflared >/dev/null 2>&1 && [[ -f "${_cloudflared_config}" ]]; then
```

### Change 3 — `bin/acg-up` Step 10h: add Keycloak to log + tunnel-urls.txt

**Exact old block (lines 1268–1276):**
```bash
    _argocd_url="${ARGOCD_PUBLIC_URL:-https://argocd.3ai-talk.org}"
    _frontend_url="${FRONTEND_PUBLIC_URL:-https://frontend.3ai-talk.org}"
    {
      printf 'argocd=%s\n' "${_argocd_url}"
      printf 'frontend=%s\n' "${_frontend_url}"
    } > "${_tunnel_urls_file}"
    _info "[acg-up] Cloudflare tunnel URLs written to ${_tunnel_urls_file}"
    _info "[acg-up] ArgoCD public URL:   ${_argocd_url}"
    _info "[acg-up] Frontend public URL: ${_frontend_url}"
```

**Exact new block:**
```bash
    _argocd_url="${ARGOCD_PUBLIC_URL:-https://argocd.${_cf_domain}}"
    _frontend_url="${FRONTEND_PUBLIC_URL:-https://frontend.${_cf_domain}}"
    _keycloak_public_url="${KEYCLOAK_PUBLIC_URL:-https://keycloak.${_cf_domain}}"
    {
      printf 'argocd=%s\n' "${_argocd_url}"
      printf 'frontend=%s\n' "${_frontend_url}"
      printf 'keycloak=%s\n' "${_keycloak_public_url}"
    } > "${_tunnel_urls_file}"
    _info "[acg-up] Cloudflare tunnel URLs written to ${_tunnel_urls_file}"
    _info "[acg-up] ArgoCD public URL:   ${_argocd_url}"
    _info "[acg-up] Frontend public URL: ${_frontend_url}"
    _info "[acg-up] Keycloak public URL: ${_keycloak_public_url}"
```

Also update the Step 10h log banner (line 1203):

**Exact old:**
```bash
  _info "[acg-up] Step 10h/14 — Installing Cloudflare named tunnel (argocd.3ai-talk.org + frontend.3ai-talk.org)..."
```

**Exact new:**
```bash
  _info "[acg-up] Step 10h/14 — Installing Cloudflare named tunnel (argocd + frontend + keycloak)..."
```

Also update the final summary lines (lines 1308–1309):

**Exact old:**
```bash
_info "[acg-up]   ArgoCD:   ${ARGOCD_PUBLIC_URL:-https://argocd.3ai-talk.org}"
_info "[acg-up]   Frontend: ${FRONTEND_PUBLIC_URL:-https://frontend.3ai-talk.org}"
```

**Exact new:**
```bash
_info "[acg-up]   ArgoCD:   ${ARGOCD_PUBLIC_URL:-https://argocd.${CF_DOMAIN:-3ai-talk.org}}"
_info "[acg-up]   Frontend: ${FRONTEND_PUBLIC_URL:-https://frontend.${CF_DOMAIN:-3ai-talk.org}}"
_info "[acg-up]   Keycloak: ${KEYCLOAK_PUBLIC_URL:-https://keycloak.${CF_DOMAIN:-3ai-talk.org}}"
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/cloudflared-config.yml.tmpl` | New template with argocd + frontend + keycloak ingress rules |
| `bin/acg-up` | Step 10h: generate config.yml from template; add keycloak to log + tunnel-urls.txt |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- Code change limited to `bin/acg-up` and `scripts/etc/cloudflared-config.yml.tmpl`; CHANGELOG and memory-bank updates are required documentation

---

## Definition of Done

- [ ] `scripts/etc/cloudflared-config.yml.tmpl` exists with argocd + frontend + keycloak ingress rules and `${CLOUDFLARE_TUNNEL_ID}` / `${CLOUDFLARE_CREDENTIALS_FILE}` / `${CLOUDFLARE_DOMAIN}` placeholders
- [ ] `bin/acg-up` Step 10h generates `~/.cloudflared/config.yml` from the template when the file is missing or missing the keycloak entry
- [ ] `bin/acg-up` Step 10h logs `Keycloak public URL` and writes `keycloak=` to `tunnel-urls.txt`
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA

**Commit message (exact):**
```
fix(acg-up): generate cloudflared config from template; add keycloak to Cloudflare tunnel
```

---

## What NOT to Do

- Do NOT check in `~/.cloudflared/config.yml` (machine-specific paths + tunnel UUID)
- Do NOT check in `~/.cloudflared/*.json` (contains Cloudflare credentials secrets)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
