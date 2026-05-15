# Bug: ArgoCD browser HTTPS listener — healthz fails because /etc/hosts update runs too late

**Date:** 2026-05-15
**File:** `bin/acg-up`
**Symptom:** `make up` fails at step 4c — socat starts, healthz loops for 30s then times out:
```
ERROR: [argocd] Argo CD did not become reachable on argocd.shopping-cart.local:443 within 30s
[argocd-browser] healthz did not become reachable — restarting
```

---

## Root cause

The `/etc/hosts` update block that writes `127.0.0.1 argocd.shopping-cart.local` is at line ~881 of `bin/acg-up` — AFTER step 4c (browser HTTPS listener, line 229).

During step 4c's 30-second healthz wait:
- `/etc/hosts` still has `192.168.97.2 argocd.shopping-cart.local` (written by a previous run with a different IP)
- socat is bound to `127.0.0.1:443`
- The healthz check resolves `argocd.shopping-cart.local` → `192.168.97.2` → tries `192.168.97.2:443` → socat is NOT there
- healthz fails every second for 30s → socat gets killed → `make up` exits with 1

The `/etc/hosts` update block at line 881 uses **hardcoded `127.0.0.1`** for both `argocd.shopping-cart.local` and `keycloak.shopping-cart.local` — it has no cluster state dependency and can safely run earlier.

---

## Fix

**File:** `bin/acg-up`

### Change 1 — Move the `/etc/hosts` update block to BEFORE step 4c

**Remove this exact block from its current location (lines ~881–911):**

```bash
# Add /etc/hosts entries on the Mac host for local browser access
_argocd_host_ip="127.0.0.1"
_kc_browser_ip="127.0.0.1"
_HOSTS_LIST=(
  "argocd.shopping-cart.local|${_argocd_host_ip}"
  "keycloak.shopping-cart.local|${_kc_browser_ip}"
)
for _host_ip_pair in "${_HOSTS_LIST[@]}"; do
  _h="${_host_ip_pair%%|*}"
  _desired_ip="${_host_ip_pair#*|}"
  if [[ -z "${_desired_ip}" ]]; then
    _warn "[acg-up] could not determine the ingressgateway IP for ${_h} — browser login may fail"
    continue
  fi
  _desired_host_entry="${_desired_ip} ${_h}"
  _current_host_entry=$(grep -E "^[0-9.]+[[:space:]]+${_h//./\\.}$" /etc/hosts | tail -n 1 || true)
  if [[ "${_current_host_entry}" != "${_desired_host_entry}" ]]; then
    _info "[acg-up] Updating /etc/hosts for ${_h} → ${_desired_ip} (requires sudo)..."
    if _run_command --prefer-sudo --soft -- \
        sh -c "set -e
tmp=\$(mktemp)
grep -vE '^[0-9.]+[[:space:]]+${_h//./\\.}$' /etc/hosts > \"\$tmp\"
printf '%s\n' '${_desired_host_entry}' >> \"\$tmp\"
cat \"\$tmp\" > /etc/hosts
rm -f \"\$tmp\""; then
      _info "[acg-up] /etc/hosts: ${_h} → ${_desired_ip}"
    else
      _warn "could not update /etc/hosts for ${_h} — please add manually: ${_desired_host_entry}"
    fi
  fi
done
```

**And insert it (verbatim, with the comment) immediately BEFORE the `if _is_mac; then` line (currently line ~229):**

The line to insert before looks like:
```bash
if _is_mac; then
  _info "[acg-up] Step 4c/12 — Installing ArgoCD browser HTTPS listener..."
```

After the insert, the section should read:
```bash
# Add /etc/hosts entries on the Mac host for local browser access
_argocd_host_ip="127.0.0.1"
_kc_browser_ip="127.0.0.1"
_HOSTS_LIST=(
  "argocd.shopping-cart.local|${_argocd_host_ip}"
  "keycloak.shopping-cart.local|${_kc_browser_ip}"
)
for _host_ip_pair in "${_HOSTS_LIST[@]}"; do
  _h="${_host_ip_pair%%|*}"
  _desired_ip="${_host_ip_pair#*|}"
  if [[ -z "${_desired_ip}" ]]; then
    _warn "[acg-up] could not determine the ingressgateway IP for ${_h} — browser login may fail"
    continue
  fi
  _desired_host_entry="${_desired_ip} ${_h}"
  _current_host_entry=$(grep -E "^[0-9.]+[[:space:]]+${_h//./\\.}$" /etc/hosts | tail -n 1 || true)
  if [[ "${_current_host_entry}" != "${_desired_host_entry}" ]]; then
    _info "[acg-up] Updating /etc/hosts for ${_h} → ${_desired_ip} (requires sudo)..."
    if _run_command --prefer-sudo --soft -- \
        sh -c "set -e
tmp=\$(mktemp)
grep -vE '^[0-9.]+[[:space:]]+${_h//./\\.}$' /etc/hosts > \"\$tmp\"
printf '%s\n' '${_desired_host_entry}' >> \"\$tmp\"
cat \"\$tmp\" > /etc/hosts
rm -f \"\$tmp\""; then
      _info "[acg-up] /etc/hosts: ${_h} → ${_desired_ip}"
    else
      _warn "could not update /etc/hosts for ${_h} — please add manually: ${_desired_host_entry}"
    fi
  fi
done

if _is_mac; then
  _info "[acg-up] Step 4c/12 — Installing ArgoCD browser HTTPS listener..."
```

### Change 2 — Use `127.0.0.1` directly in the wrapper healthz URL (defensive)

In the `_argocd_write_browser_https_wrapper` call (line ~248), change the healthz URL from the hostname to the loopback IP so the internal wrapper check never depends on /etc/hosts.

**Old (line ~248):**
```bash
    _argocd_write_browser_https_wrapper "${_argocd_browser_wrapper}" "${_argocd_browser_log}" "$(command -v socat)" "$(command -v curl)" "127.0.0.1" "${ARGOCD_BROWSER_PORT:-443}" "127.0.0.1" "8080" "${_argocd_browser_tls_cert}" "${_argocd_browser_tls_key}" "https://${ARGOCD_BROWSER_HOST:-argocd.shopping-cart.local}:${ARGOCD_BROWSER_PORT:-443}/healthz"
```

**New:**
```bash
    _argocd_write_browser_https_wrapper "${_argocd_browser_wrapper}" "${_argocd_browser_log}" "$(command -v socat)" "$(command -v curl)" "127.0.0.1" "${ARGOCD_BROWSER_PORT:-443}" "127.0.0.1" "8080" "${_argocd_browser_tls_cert}" "${_argocd_browser_tls_key}" "https://127.0.0.1:${ARGOCD_BROWSER_PORT:-443}/healthz"
```

---

## Definition of Done

- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] The `/etc/hosts` update block appears BEFORE `if _is_mac; then` (step 4c) in `bin/acg-up`
- [ ] The `/etc/hosts` update block is REMOVED from its old location near line 881
- [ ] The `_argocd_write_browser_https_wrapper` call uses `https://127.0.0.1:${ARGOCD_BROWSER_PORT:-443}/healthz`
- [ ] Commit message: `fix(acg-up): move /etc/hosts update before step 4c so ArgoCD browser HTTPS healthz resolves correctly`
- [ ] Push: `git push origin k3d-manager-v1.4.6`
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status

## What NOT to do

- Do NOT create a PR
- Do NOT skip pre-commit hooks
- Do NOT modify files outside `bin/acg-up`
- Do NOT commit to `main`
- Work on branch: `k3d-manager-v1.4.6`

## Before you start

- `git pull origin k3d-manager-v1.4.6`
- Read this spec in full
- Read `bin/acg-up` in full before editing — confirm you can identify the exact block to move
