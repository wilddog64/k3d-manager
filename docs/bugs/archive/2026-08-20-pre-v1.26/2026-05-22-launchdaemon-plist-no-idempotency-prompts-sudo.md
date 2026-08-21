# Bug: LaunchDaemon Plist Install Prompts for sudo Password on Every make up

**Date:** 2026-05-22
**File:** `bin/acg-up`
**Symptom:** `make up` prompts for a password mid-run at steps installing ArgoCD browser listener, Keycloak browser listener, loopback alias, frontend browser listener, and named tunnel — even when nothing has changed since the last run.

## Root Cause

Five `/Library/LaunchDaemons/` plist install sequences in `bin/acg-up` call
`--interactive-sudo` unconditionally on every run (bootout + install + bootstrap), with no
check against the already-installed plist. On a fresh run the sudo cache is warm; by step 10g
it has expired (5-minute default) and the script prompts again.

The loopback alias `ifconfig` call (line ~1089) already has an idempotency guard — but the
plist install that follows does not.

## Fix

Wrap each bootout/install/bootstrap block with a plist-diff check. If the installed plist
already matches the desired one, skip all three sudo calls and remove the temp file.

**Pattern (apply identically to all 5 blocks):**

Before each block, the plist has already been written to `${_..._plist_tmp}` via a `cat <<PLIST` heredoc.
The existing block starts with `: > "${_..._launchctl_log}"`.

### Block 1 — ArgoCD browser HTTPS listener (lines ~326–350)

**Old:**
```bash
    : > "${_argocd_browser_launchctl_log}"
    if _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_argocd_browser_plist}" \
        >"${_argocd_browser_launchctl_log}" 2>&1; then
      _info "[acg-up] Stopped existing ArgoCD browser HTTPS listener"
    elif [[ -s "${_argocd_browser_launchctl_log}" ]]; then
      tail -n 20 "${_argocd_browser_launchctl_log}" >&2 || true
      _warn "[acg-up] existing ArgoCD browser HTTPS listener was not loaded; continuing"
    fi
    : > "${_argocd_browser_launchctl_log}"
    if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_argocd_browser_plist_tmp}" "${_argocd_browser_plist}" \
        >"${_argocd_browser_launchctl_log}" 2>&1; then
      if [[ -s "${_argocd_browser_launchctl_log}" ]]; then
        tail -n 20 "${_argocd_browser_launchctl_log}" >&2 || true
      fi
      _err "[acg-up] failed to install ArgoCD browser HTTPS listener plist; see ${_argocd_browser_launchctl_log}"
    fi
    rm -f "${_argocd_browser_plist_tmp}"
    : > "${_argocd_browser_launchctl_log}"
    if ! _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_argocd_browser_plist}" \
        >"${_argocd_browser_launchctl_log}" 2>&1; then
      if [[ -s "${_argocd_browser_launchctl_log}" ]]; then
        tail -n 20 "${_argocd_browser_launchctl_log}" >&2 || true
      fi
      _err "[acg-up] failed to bootstrap ArgoCD browser HTTPS listener; see ${_argocd_browser_launchctl_log}"
    fi
```

**New:**
```bash
    if [[ -f "${_argocd_browser_plist}" ]] && diff -q "${_argocd_browser_plist_tmp}" "${_argocd_browser_plist}" >/dev/null 2>&1; then
      rm -f "${_argocd_browser_plist_tmp}"
      _info "[acg-up] ArgoCD browser HTTPS listener LaunchDaemon unchanged — skipping reinstall"
    else
      : > "${_argocd_browser_launchctl_log}"
      if _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_argocd_browser_plist}" \
          >"${_argocd_browser_launchctl_log}" 2>&1; then
        _info "[acg-up] Stopped existing ArgoCD browser HTTPS listener"
      elif [[ -s "${_argocd_browser_launchctl_log}" ]]; then
        tail -n 20 "${_argocd_browser_launchctl_log}" >&2 || true
        _warn "[acg-up] existing ArgoCD browser HTTPS listener was not loaded; continuing"
      fi
      : > "${_argocd_browser_launchctl_log}"
      if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_argocd_browser_plist_tmp}" "${_argocd_browser_plist}" \
          >"${_argocd_browser_launchctl_log}" 2>&1; then
        if [[ -s "${_argocd_browser_launchctl_log}" ]]; then
          tail -n 20 "${_argocd_browser_launchctl_log}" >&2 || true
        fi
        _err "[acg-up] failed to install ArgoCD browser HTTPS listener plist; see ${_argocd_browser_launchctl_log}"
      fi
      rm -f "${_argocd_browser_plist_tmp}"
      : > "${_argocd_browser_launchctl_log}"
      if ! _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_argocd_browser_plist}" \
          >"${_argocd_browser_launchctl_log}" 2>&1; then
        if [[ -s "${_argocd_browser_launchctl_log}" ]]; then
          tail -n 20 "${_argocd_browser_launchctl_log}" >&2 || true
        fi
        _err "[acg-up] failed to bootstrap ArgoCD browser HTTPS listener; see ${_argocd_browser_launchctl_log}"
      fi
    fi
```

---

### Block 2 — Keycloak browser HTTP listener (lines ~948–972)

**Old:**
```bash
    : > "${_keycloak_browser_launchctl_log}"
    if _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_keycloak_browser_plist}" \
        >"${_keycloak_browser_launchctl_log}" 2>&1; then
      _info "[acg-up] Stopped existing Keycloak browser HTTP listener"
    elif [[ -s "${_keycloak_browser_launchctl_log}" ]]; then
      tail -n 20 "${_keycloak_browser_launchctl_log}" >&2 || true
      _warn "[acg-up] existing Keycloak browser HTTP listener was not loaded; continuing"
    fi
    : > "${_keycloak_browser_launchctl_log}"
    if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_keycloak_browser_plist_tmp}" "${_keycloak_browser_plist}" \
        >"${_keycloak_browser_launchctl_log}" 2>&1; then
      if [[ -s "${_keycloak_browser_launchctl_log}" ]]; then
        tail -n 20 "${_keycloak_browser_launchctl_log}" >&2 || true
      fi
      _err "[acg-up] failed to install Keycloak browser HTTP listener plist; see ${_keycloak_browser_launchctl_log}"
    fi
    rm -f "${_keycloak_browser_plist_tmp}"
    : > "${_keycloak_browser_launchctl_log}"
    if ! _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_keycloak_browser_plist}" \
        >"${_keycloak_browser_launchctl_log}" 2>&1; then
      if [[ -s "${_keycloak_browser_launchctl_log}" ]]; then
        tail -n 20 "${_keycloak_browser_launchctl_log}" >&2 || true
      fi
      _err "[acg-up] failed to bootstrap Keycloak browser HTTP listener; see ${_keycloak_browser_launchctl_log}"
    fi
```

**New:**
```bash
    if [[ -f "${_keycloak_browser_plist}" ]] && diff -q "${_keycloak_browser_plist_tmp}" "${_keycloak_browser_plist}" >/dev/null 2>&1; then
      rm -f "${_keycloak_browser_plist_tmp}"
      _info "[acg-up] Keycloak browser HTTP listener LaunchDaemon unchanged — skipping reinstall"
    else
      : > "${_keycloak_browser_launchctl_log}"
      if _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_keycloak_browser_plist}" \
          >"${_keycloak_browser_launchctl_log}" 2>&1; then
        _info "[acg-up] Stopped existing Keycloak browser HTTP listener"
      elif [[ -s "${_keycloak_browser_launchctl_log}" ]]; then
        tail -n 20 "${_keycloak_browser_launchctl_log}" >&2 || true
        _warn "[acg-up] existing Keycloak browser HTTP listener was not loaded; continuing"
      fi
      : > "${_keycloak_browser_launchctl_log}"
      if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_keycloak_browser_plist_tmp}" "${_keycloak_browser_plist}" \
          >"${_keycloak_browser_launchctl_log}" 2>&1; then
        if [[ -s "${_keycloak_browser_launchctl_log}" ]]; then
          tail -n 20 "${_keycloak_browser_launchctl_log}" >&2 || true
        fi
        _err "[acg-up] failed to install Keycloak browser HTTP listener plist; see ${_keycloak_browser_launchctl_log}"
      fi
      rm -f "${_keycloak_browser_plist_tmp}"
      : > "${_keycloak_browser_launchctl_log}"
      if ! _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_keycloak_browser_plist}" \
          >"${_keycloak_browser_launchctl_log}" 2>&1; then
        if [[ -s "${_keycloak_browser_launchctl_log}" ]]; then
          tail -n 20 "${_keycloak_browser_launchctl_log}" >&2 || true
        fi
        _err "[acg-up] failed to bootstrap Keycloak browser HTTP listener; see ${_keycloak_browser_launchctl_log}"
      fi
    fi
```

---

### Block 3 — Loopback alias LaunchDaemon (lines ~1121–1134)

**Old:**
```bash
  : > "${_loopback_launchctl_log}"
  _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_loopback_plist}" \
    >"${_loopback_launchctl_log}" 2>&1 || true
  : > "${_loopback_launchctl_log}"
  if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_loopback_plist_tmp}" "${_loopback_plist}" \
      >"${_loopback_launchctl_log}" 2>&1; then
    _warn "[acg-up] failed to install loopback alias plist — frontend may fail after reboot"
  else
    rm -f "${_loopback_plist_tmp}"
    : > "${_loopback_launchctl_log}"
    _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_loopback_plist}" \
      >"${_loopback_launchctl_log}" 2>&1 || \
      _warn "[acg-up] failed to bootstrap loopback alias agent"
  fi
```

**New:**
```bash
  if [[ -f "${_loopback_plist}" ]] && diff -q "${_loopback_plist_tmp}" "${_loopback_plist}" >/dev/null 2>&1; then
    rm -f "${_loopback_plist_tmp}"
    _info "[acg-up] Loopback alias LaunchDaemon unchanged — skipping reinstall"
  else
    : > "${_loopback_launchctl_log}"
    _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_loopback_plist}" \
      >"${_loopback_launchctl_log}" 2>&1 || true
    : > "${_loopback_launchctl_log}"
    if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_loopback_plist_tmp}" "${_loopback_plist}" \
        >"${_loopback_launchctl_log}" 2>&1; then
      _warn "[acg-up] failed to install loopback alias plist — frontend may fail after reboot"
    else
      rm -f "${_loopback_plist_tmp}"
      : > "${_loopback_launchctl_log}"
      _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_loopback_plist}" \
        >"${_loopback_launchctl_log}" 2>&1 || \
        _warn "[acg-up] failed to bootstrap loopback alias agent"
    fi
  fi
```

---

### Block 4 — Frontend browser HTTP listener (lines ~1173–1197)

**Old:**
```bash
  : > "${_frontend_browser_launchctl_log}"
  if _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_frontend_browser_plist}" \
      >"${_frontend_browser_launchctl_log}" 2>&1; then
    _info "[acg-up] Stopped existing frontend browser HTTP listener"
  elif [[ -s "${_frontend_browser_launchctl_log}" ]]; then
    tail -n 20 "${_frontend_browser_launchctl_log}" >&2 || true
    _warn "[acg-up] existing frontend browser HTTP listener was not loaded; continuing"
  fi
  : > "${_frontend_browser_launchctl_log}"
  if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_frontend_browser_plist_tmp}" "${_frontend_browser_plist}" \
      >"${_frontend_browser_launchctl_log}" 2>&1; then
    if [[ -s "${_frontend_browser_launchctl_log}" ]]; then
      tail -n 20 "${_frontend_browser_launchctl_log}" >&2 || true
    fi
    _err "[acg-up] failed to install frontend browser HTTP listener plist"
  fi
  rm -f "${_frontend_browser_plist_tmp}"
  : > "${_frontend_browser_launchctl_log}"
  if ! _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_frontend_browser_plist}" \
      >"${_frontend_browser_launchctl_log}" 2>&1; then
    if [[ -s "${_frontend_browser_launchctl_log}" ]]; then
      tail -n 20 "${_frontend_browser_launchctl_log}" >&2 || true
    fi
    _err "[acg-up] failed to bootstrap frontend browser HTTP listener"
  fi
```

**New:**
```bash
  if [[ -f "${_frontend_browser_plist}" ]] && diff -q "${_frontend_browser_plist_tmp}" "${_frontend_browser_plist}" >/dev/null 2>&1; then
    rm -f "${_frontend_browser_plist_tmp}"
    _info "[acg-up] Frontend browser HTTP listener LaunchDaemon unchanged — skipping reinstall"
  else
    : > "${_frontend_browser_launchctl_log}"
    if _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_frontend_browser_plist}" \
        >"${_frontend_browser_launchctl_log}" 2>&1; then
      _info "[acg-up] Stopped existing frontend browser HTTP listener"
    elif [[ -s "${_frontend_browser_launchctl_log}" ]]; then
      tail -n 20 "${_frontend_browser_launchctl_log}" >&2 || true
      _warn "[acg-up] existing frontend browser HTTP listener was not loaded; continuing"
    fi
    : > "${_frontend_browser_launchctl_log}"
    if ! _run_command --interactive-sudo --quiet -- install -m 644 "${_frontend_browser_plist_tmp}" "${_frontend_browser_plist}" \
        >"${_frontend_browser_launchctl_log}" 2>&1; then
      if [[ -s "${_frontend_browser_launchctl_log}" ]]; then
        tail -n 20 "${_frontend_browser_launchctl_log}" >&2 || true
      fi
      _err "[acg-up] failed to install frontend browser HTTP listener plist"
    fi
    rm -f "${_frontend_browser_plist_tmp}"
    : > "${_frontend_browser_launchctl_log}"
    if ! _run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_frontend_browser_plist}" \
        >"${_frontend_browser_launchctl_log}" 2>&1; then
      if [[ -s "${_frontend_browser_launchctl_log}" ]]; then
        tail -n 20 "${_frontend_browser_launchctl_log}" >&2 || true
      fi
      _err "[acg-up] failed to bootstrap frontend browser HTTP listener"
    fi
  fi
```

---

### Block 5 — Named tunnel LaunchDaemon (lines ~1317–1330)

**Old:**
```bash
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
```

**New:**
```bash
    if [[ -f "${_named_tunnel_plist}" ]] && diff -q "${_named_tunnel_plist_tmp}" "${_named_tunnel_plist}" >/dev/null 2>&1; then
      rm -f "${_named_tunnel_plist_tmp}"
      _info "[acg-up] Named tunnel LaunchDaemon unchanged — skipping reinstall"
    else
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
    fi
```

---

---

### Change 2 — `bin/acg-down`: pre-warm sudo before Mac launchd cleanup

`bin/acg-down` runs CloudFormation teardown (can take several minutes) before the Mac
launchd cleanup block. By the time lines 112–139 run, the sudo cache has expired, causing
one or more `Password:` prompts mid-teardown.

Fix: add a single `_run_command --interactive-sudo --quiet -- true` as the first statement
inside `if _is_mac;` — this warms the cache once, and all five subsequent `--interactive-sudo`
calls (bootout + rm × 3) stay within the 5-minute window.

**Exact old block (line 105):**

```bash
if _is_mac; then
  _info "[acg-down] Stopping Keycloak browser HTTP listener launchd daemon..."
```

**Exact new block:**

```bash
if _is_mac; then
  _run_command --interactive-sudo --quiet -- true
  _info "[acg-down] Stopping Keycloak browser HTTP listener launchd daemon..."
```

---

## Files Changed (both changes)

| File | Change |
|------|--------|
| `bin/acg-up` | 5 plist install blocks wrapped with `diff -q` idempotency guard |
| `bin/acg-down` | `_run_command --interactive-sudo --quiet -- true` pre-warm added at top of `if _is_mac` block |

---

## Before You Start

1. `git -C /Users/cliang/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.9`
2. Read this spec in full before touching any files
3. Read `bin/acg-up` — locate all 5 blocks by the anchor strings listed below:
   - Block 1 ArgoCD: `_argocd_browser_launchctl_log`
   - Block 2 Keycloak: `_keycloak_browser_launchctl_log`
   - Block 3 Loopback: `_loopback_launchctl_log`
   - Block 4 Frontend: `_frontend_browser_launchctl_log`
   - Block 5 Named tunnel: `_named_tunnel_plist_tmp`
4. Confirm you are on branch `k3d-manager-v1.4.9` — never commit to `main`

## Definition of Done

- [ ] All 5 blocks in `bin/acg-up` wrapped with the `diff -q` idempotency guard
- [ ] Each skip branch: `rm -f "${_..._plist_tmp}"` + `_info` message
- [ ] `bin/acg-down` — `_run_command --interactive-sudo --quiet -- true` inserted as first statement of `if _is_mac` block (before the `_info "[acg-down] Stopping Keycloak..."` line)
- [ ] `shellcheck -S warning bin/acg-up bin/acg-down` passes with zero new warnings
- [ ] Commit on branch `k3d-manager-v1.4.9`: `fix(acg-up,acg-down): skip LaunchDaemon plist reinstall when unchanged; pre-warm sudo in acg-down`
- [ ] Push to origin before reporting done

## What NOT to Do

- Do NOT change function body of any install block in `acg-up` — only wrap with the idempotency guard
- Do NOT add a helper function — apply the pattern inline at each site
- Do NOT modify any files other than `bin/acg-up` and `bin/acg-down`
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
