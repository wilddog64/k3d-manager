# Bug: acg-up — /etc/hosts update silently skipped + ArgoCD HTTPS listener timeout too short

**Date:** 2026-05-15
**File:** `bin/acg-up`
**Symptom:** `make up` fails at step 4c even after the /etc/hosts ordering fix:
```
ERROR: [argocd] Argo CD did not become reachable on argocd.shopping-cart.local:443 within 30s
make: *** [up] Error 1
```
`/etc/hosts` still shows `192.168.97.2` for both `argocd.shopping-cart.local` and
`keycloak.shopping-cart.local` after the run.

---

## Root Causes

### Bug 1 — /etc/hosts update uses non-interactive sudo

The `/etc/hosts` update block (line 248) calls:
```bash
_run_command --prefer-sudo --soft -- sh -c "..."
```

`--prefer-sudo` resolves to `sudo -n` (non-interactive, cached-credential only).
When the sudo session has expired, `sudo -n` fails; `_run_command` falls back to the
current user account, which cannot write `/etc/hosts`; `--soft` swallows the error
silently. The `_info "Updating /etc/hosts…"` message appears but the entry is never
actually written.

All other privileged operations in the same file (lines 306, 314, 323, 840, 848, 857)
correctly use `--interactive-sudo`, which presents a password prompt when needed.
The /etc/hosts block must match.

### Bug 2 — 30-second wait is too short for socat to become healthy

After `launchctl bootstrap` loads the new HTTPS wrapper, socat starts but the upstream
(ArgoCD on `localhost:8080`) may take longer than 30 seconds to be fully responsive.
The kubectl port-forward is reloaded earlier in the script; even after it is validated,
it can briefly drop and reconnect during the TLS issuance / launchctl bootout/bootstrap
sequence. `ARGOCD_BROWSER_LISTENER_WAIT_TIMEOUT:-30` (line 330) is too tight; in
production observations the socat listener becomes healthy within 3 minutes.

---

## Fix

**File:** `bin/acg-up`

### Change 1 — Use `--interactive-sudo` for the /etc/hosts update

**Old (line 248):**
```bash
    if _run_command --prefer-sudo --soft -- \
        sh -c "set -e
tmp=\$(mktemp)
grep -vE '^[0-9.]+[[:space:]]+${_h//./\\.}$' /etc/hosts > \"\$tmp\"
printf '%s\n' '${_desired_host_entry}' >> \"\$tmp\"
cat \"\$tmp\" > /etc/hosts
rm -f \"\$tmp\""; then
```

**New:**
```bash
    if _run_command --interactive-sudo --soft -- \
        sh -c "set -e
tmp=\$(mktemp)
grep -vE '^[0-9.]+[[:space:]]+${_h//./\\.}$' /etc/hosts > \"\$tmp\"
printf '%s\n' '${_desired_host_entry}' >> \"\$tmp\"
cat \"\$tmp\" > /etc/hosts
rm -f \"\$tmp\""; then
```

Only the `--prefer-sudo` → `--interactive-sudo` token changes. Everything else
(the heredoc, the `--soft`, the surrounding loop) is unchanged.

### Change 2 — Increase the HTTPS listener wait timeout from 30 to 120 seconds

**Old (line 330):**
```bash
    if _argocd_wait_for_browser_https "${_argocd_browser_log}" "${ARGOCD_BROWSER_LISTENER_WAIT_TIMEOUT:-30}"; then
```

**New:**
```bash
    if _argocd_wait_for_browser_https "${_argocd_browser_log}" "${ARGOCD_BROWSER_LISTENER_WAIT_TIMEOUT:-120}"; then
```

Only the default value changes from `30` to `120`. The env-var override still works.

---

## Definition of Done

- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Line 248 of `bin/acg-up` reads `--interactive-sudo --soft` (not `--prefer-sudo --soft`)
- [ ] Line 330 of `bin/acg-up` reads `ARGOCD_BROWSER_LISTENER_WAIT_TIMEOUT:-120` (not `:-30`)
- [ ] No other lines in `bin/acg-up` are modified
- [ ] Commit message: `fix(acg-up): use interactive-sudo for /etc/hosts and increase HTTPS listener timeout to 120s`
- [ ] Push: `git push origin k3d-manager-v1.4.6`
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `bin/acg-up`
- Do NOT commit to `main`
- Work on branch: `k3d-manager-v1.4.6`

## Before You Start

- `git pull origin k3d-manager-v1.4.6`
- Read this spec in full
- Read `bin/acg-up` lines 245–256 and 328–335 to confirm the exact strings before editing
