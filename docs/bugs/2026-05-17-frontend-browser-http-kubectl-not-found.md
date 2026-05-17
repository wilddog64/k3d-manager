# Bug: frontend-browser-http launchd agent fails — kubectl not found in root PATH

**Branch:** `k3d-manager-v1.4.6`
**Files:**
- `bin/acg-up` — Step 10g wrapper heredoc

---

## Before You Start

```
git pull origin k3d-manager-v1.4.6
```

Read this spec in full before touching any file.

---

## Problem

The `com.k3d-manager.frontend-browser-http` launchd system daemon runs as root.
Root's `PATH` does not include `/opt/homebrew/bin`, so `kubectl` is not found and
the port-forward loop fails immediately on every iteration:

```
kubectl: command not found
```

**Root cause:** The wrapper script heredoc in Step 10g writes `kubectl` as a bare
command name instead of baking in the absolute path at write-time.

---

## Fix

### Change 1 — `bin/acg-up`: bake kubectl absolute path into wrapper heredoc

**Exact old block (inside Step 10g, the wrapper heredoc):**
```bash
  cat > "${_frontend_browser_wrapper}" <<FRONTEND_WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG="${_frontend_browser_kubeconfig}"
_log="${_frontend_browser_log}"
while true; do
  printf '%s\n' "[\$(date)] starting frontend port-forward: svc/frontend → 127.0.0.2:80" >> "\${_log}"
  kubectl --context ubuntu-k3s port-forward --address=127.0.0.2 \
    svc/frontend 80:80 -n shopping-cart-apps >> "\${_log}" 2>&1 || true
  sleep 2
done
FRONTEND_WRAPPER
```

**Exact new block:**
```bash
  _kubectl_bin="$(command -v kubectl)"
  cat > "${_frontend_browser_wrapper}" <<FRONTEND_WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG="${_frontend_browser_kubeconfig}"
_log="${_frontend_browser_log}"
while true; do
  printf '%s\n' "[\$(date)] starting frontend port-forward: svc/frontend → 127.0.0.2:80" >> "\${_log}"
  ${_kubectl_bin} --context ubuntu-k3s port-forward --address=127.0.0.2 \
    svc/frontend 80:80 -n shopping-cart-apps >> "\${_log}" 2>&1 || true
  sleep 2
done
FRONTEND_WRAPPER
```

---

## After the Commit

The live wrapper at `~/.local/share/k3d-manager/frontend-browser-http.sh` must also
be patched manually (or `make up` re-run). To patch without `make up`:

```bash
sudo sed -i '' 's|  kubectl |  /opt/homebrew/bin/kubectl |g' \
  ~/.local/share/k3d-manager/frontend-browser-http.sh
sudo launchctl kickstart -k system/com.k3d-manager.frontend-browser-http
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add `_kubectl_bin` capture before heredoc; expand it inside heredoc |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files modified
- The heredoc delimiter `FRONTEND_WRAPPER` is unquoted — variable expansion inside is intentional; `_kubectl_bin` must expand at write-time

---

## Definition of Done

- [ ] `_kubectl_bin="$(command -v kubectl)"` added before the `cat > "${_frontend_browser_wrapper}"` line
- [ ] `kubectl` inside the heredoc replaced with `${_kubectl_bin}`
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

**Commit message (exact):**
```
fix(acg-up): bake absolute kubectl path into frontend-browser-http wrapper
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
