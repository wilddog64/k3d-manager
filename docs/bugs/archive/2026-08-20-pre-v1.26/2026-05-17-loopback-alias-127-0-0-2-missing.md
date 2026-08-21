# Bug: 127.0.0.2 loopback alias missing on macOS — frontend port-forward cannot bind

**Branch:** `k3d-manager-v1.4.6`
**Files:**
- `bin/acg-up` — Step 10g block (add alias setup before launchd agent install)

---

## Before You Start

```
git pull origin k3d-manager-v1.4.6
```

Read this spec in full before touching any file.

---

## Problem

macOS does not automatically expose the full `127.0.0.0/8` range on `lo0`. Only `127.0.0.1`
exists by default. Binding `kubectl port-forward --address=127.0.0.2` fails with:

```
unable to create listener: Error listen tcp4 127.0.0.2:80: bind: can't assign requested address
```

The alias must be added with `ifconfig lo0 alias 127.0.0.2` before the port-forward starts.
This alias is not persistent across reboots — it must be re-added by a launchd system daemon.

---

## Fix

Add two things to `bin/acg-up` Step 10g, both inside the `if _is_mac; then` block,
**before** the wrapper script write and launchd agent install.

### Change 1 — add loopback alias immediately + launchd agent for persistence

**Exact insertion point — after this line in Step 10g:**
```bash
  mkdir -p "$(dirname "${_frontend_browser_log}")"
```

**Insert this block (before the `cat > "${_frontend_browser_wrapper}"` line):**
```bash
  # Ensure 127.0.0.2 loopback alias exists (macOS does not expose 127.0.0.0/8 automatically)
  if ! ifconfig lo0 | grep -q '127\.0\.0\.2'; then
    _run_command --interactive-sudo --quiet -- ifconfig lo0 alias 127.0.0.2 || \
      _warn "[acg-up] failed to add 127.0.0.2 loopback alias — frontend port-forward will fail to bind"
  fi

  # Install persistent loopback alias launchd agent (survives reboots)
  _loopback_label="com.k3d-manager.loopback-alias"
  _loopback_plist="/Library/LaunchDaemons/${_loopback_label}.plist"
  _loopback_plist_tmp="${HOME}/.local/share/k3d-manager/loopback-alias.plist"
  _loopback_launchctl_log="${HOME}/.local/share/k3d-manager/loopback-alias-launchctl.log"
  cat > "${_loopback_plist_tmp}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_loopback_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/sbin/ifconfig</string>
    <string>lo0</string>
    <string>alias</string>
    <string>127.0.0.2</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/dev/null</string>
  <key>StandardErrorPath</key>
  <string>/dev/null</string>
</dict>
</plist>
PLIST
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

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Step 10g: add 127.0.0.2 alias setup + persistent launchd agent before wrapper install |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files modified
- Alias setup is best-effort — failure warns but never blocks (`_warn`, never `_err`)
- The plist uses `/sbin/ifconfig` (absolute path) — no PATH dependency

---

## Definition of Done

- [ ] Loopback alias block inserted in Step 10g after `mkdir -p` line, before wrapper heredoc
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

**Commit message (exact):**
```
fix(acg-up): add 127.0.0.2 loopback alias launchd agent for frontend port-forward
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT use `KeepAlive: true` on the loopback plist — `ifconfig` exits immediately; KeepAlive would respawn it in a tight loop
