# Bug: the hub-to-sandbox SSH tunnel cannot reconnect while an orphaned sandbox sshd holds port 8200

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN. The fix is specified below (options 2+3) and dispatched to Codex on 2026-10-04.
**Severity:** high while it lasts. The hub ArgoCD loses `ubuntu-k3s` (`host.k3d.internal:6443`), so
no sandbox app can sync, and nothing heals by itself.

## Observed (about 02:40 UTC)

- The LaunchAgent `com.k3d-manager.ssh-tunnel` runs
  `autossh -M 0 ... -o ExitOnForwardFailure=yes -L 0.0.0.0:6443:localhost:6443 -R 8200:127.0.0.1:18200 -N ubuntu`.
- `/tmp/k3d-manager-tunnel.err` shows `client_loop: send disconnect: Broken pipe` at about 19:38 PDT,
  which is when k3s on the sandbox was restarted. After that it shows repeated
  `Error: remote port forwarding failed for listen port 8200`.
- autossh (PID 35898) is alive but has no ssh child, and nothing on the Mac listens on 6443.
- On the sandbox, `127.0.0.1:8200` and `[::1]:8200` are still LISTEN. The old session from
  02:23:53Z (sshd PID 51046, the autossh start time) is still attached to the client's previous
  public IP, with a send queue of 273 KB that is never drained. The client side is gone, but sshd
  has not noticed, so it keeps the remote forward bound.
- Hub ArgoCD `acg-kube-prometheus-stack`: `read: connection reset by peer` on
  `host.k3d.internal:6443`. `make fix-sync` failed with every resource `Unknown/Missing`.

## Root cause

`ExitOnForwardFailure=yes` combined with a remote forward. When the client drops without a clean
close, the server sshd keeps the session, and so `-R 8200`, until TCP gives up. sshd has no
`ClientAliveInterval`, so that takes hours. Every autossh retry then fails on 8200, and the `-L 6443`
forward that ArgoCD depends on never comes back.

## Manual recovery

The operator kills the orphaned sandbox sshd, then kickstarts the agent:
`ssh ubuntu kill 51046 && launchctl kickstart -k gui/$(id -u)/com.k3d-manager.ssh-tunnel`

## Fix options

1. Add `-o ClientAliveInterval=30 -o ClientAliveCountMax=3` on the sandbox sshd (cloud-init or
   `cluster-up`), so the server drops dead sessions in about 90 s.
2. Before (re)starting the tunnel, kill any sandbox sshd that holds 8200
   (`fuser -k 8200/tcp` as ubuntu).
3. Split the `-R 8200` forward into its own autossh agent, so a stuck remote forward can no
   longer take down the `-L 6443` ArgoCD path.

## Decision (2026-10-04): options 3 + 2, and not 1

- **Option 3:** move the `-R` forward into its own launchd agent. The k3s API forward (`-L 6443`)
  that ArgoCD depends on then can no longer be held hostage by a stale remote listener. This is
  the part that caused the outage.
- **Option 2:** the new Vault agent clears any stale holder of remote 8200 every time it starts.
  It runs under launchd `KeepAlive`, so every reconnect attempt clears it again. On the sandbox,
  8200 is used only by this reverse forward. If the agent is restarting, any holder is by
  definition a stale session.
- **Option 1 is dropped for now.** It would change sshd config across both provisioning paths
  (SSH and SSM). With 2+3 in place it is not needed. `fuser` and `ss` are both present on the
  Ubuntu 22.04.5 sandbox image (checked 2026-10-04).

## Fix spec

All the code changes are in `scripts/plugins/tunnel.sh`. Its callers (`bin/cluster-up` Step 3,
`bin/cluster-refresh`, `bin/cluster-down`) go only through `tunnel_start` and `tunnel_stop`,
and need no change.

1. **New defaults**, after the existing `TUNNEL_PLIST_PATH` default:

   ```bash
   : "${TUNNEL_VAULT_LAUNCHD_LABEL:=com.k3d-manager.ssh-tunnel-vault}"
   : "${TUNNEL_VAULT_PLIST_PATH:=${HOME}/Library/LaunchAgents/${TUNNEL_VAULT_LAUNCHD_LABEL}.plist}"
   : "${TUNNEL_VAULT_WRAPPER_PATH:=${HOME}/Library/LaunchAgents/${TUNNEL_VAULT_LAUNCHD_LABEL}.sh}"
   ```

2. **`_tunnel_write_plist`:** delete the two `ProgramArguments` entries
   `<string>-R</string>` and
   `<string>${TUNNEL_VAULT_REMOTE_PORT}:127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT}</string>`.
   Leave everything else unchanged.

3. **New helpers:**

   ```bash
   _tunnel_vault_is_running() {
     pgrep -f "ssh -N .*-R ${TUNNEL_VAULT_REMOTE_PORT}:127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT}" >/dev/null 2>&1
   }

   _tunnel_vault_launchd_loaded() {
     [[ "$(uname)" == "Darwin" ]] || return 1
     launchctl list "${TUNNEL_VAULT_LAUNCHD_LABEL}" >/dev/null 2>&1
   }

   _tunnel_plist_has_reverse() {
     [[ -f "${TUNNEL_PLIST_PATH}" ]] && grep -q '<string>-R</string>' "${TUNNEL_PLIST_PATH}"
   }

   _tunnel_write_vault_agent() {
     local ssh_bin
     ssh_bin="$(command -v ssh)"
     mkdir -p "$(dirname "${TUNNEL_VAULT_WRAPPER_PATH}")" "$(dirname "${TUNNEL_VAULT_PLIST_PATH}")"
     cat > "${TUNNEL_VAULT_WRAPPER_PATH}" <<WRAPPER
   #!/bin/bash
   "${ssh_bin}" -o BatchMode=yes -o ConnectTimeout=10 "${TUNNEL_SSH_HOST}" \\
     "sudo fuser -k -n tcp ${TUNNEL_VAULT_REMOTE_PORT} >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
   exec "${ssh_bin}" -N -o BatchMode=yes -o ExitOnForwardFailure=yes \\
     -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \\
     -R ${TUNNEL_VAULT_REMOTE_PORT}:127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT} "${TUNNEL_SSH_HOST}"
   WRAPPER
     chmod 0755 "${TUNNEL_VAULT_WRAPPER_PATH}"
     cat > "${TUNNEL_VAULT_PLIST_PATH}" <<PLIST
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>Label</key>
     <string>${TUNNEL_VAULT_LAUNCHD_LABEL}</string>
     <key>ProgramArguments</key>
     <array>
       <string>/bin/bash</string>
       <string>${TUNNEL_VAULT_WRAPPER_PATH}</string>
     </array>
     <key>RunAtLoad</key>
     <true/>
     <key>KeepAlive</key>
     <true/>
     <key>ThrottleInterval</key>
     <integer>10</integer>
     <key>StandardOutPath</key>
     <string>/tmp/k3d-manager-tunnel-vault.out</string>
     <key>StandardErrorPath</key>
     <string>/tmp/k3d-manager-tunnel-vault.err</string>
   </dict>
   </plist>
   PLIST
   }
   ```

4. **`tunnel_start`:** replace

   ```bash
     if _tunnel_is_running; then
       echo "[tunnel] already running"
       return 0
     fi

     _tunnel_write_plist
     if [[ "$(uname)" == "Darwin" ]]; then
       launchctl load -w "${TUNNEL_PLIST_PATH}"
     fi
   ```

   with

   ```bash
     if _tunnel_is_running && ! _tunnel_plist_has_reverse && _tunnel_vault_launchd_loaded; then
       echo "[tunnel] already running"
       return 0
     fi

     _tunnel_write_plist
     _tunnel_write_vault_agent
     if [[ "$(uname)" == "Darwin" ]]; then
       launchctl unload -w "${TUNNEL_PLIST_PATH}" 2>/dev/null || true
       launchctl load -w "${TUNNEL_PLIST_PATH}"
       launchctl unload -w "${TUNNEL_VAULT_PLIST_PATH}" 2>/dev/null || true
       launchctl load -w "${TUNNEL_VAULT_PLIST_PATH}"
     fi
   ```

   This also migrates existing installs: a running tunnel whose plist still carries `-R` is
   rewritten and reloaded instead of being reported as "already running".

5. **`tunnel_stop`:** after the existing autossh `pkill` block, add:

   ```bash
     if _tunnel_vault_launchd_loaded; then
       launchctl unload -w "${TUNNEL_VAULT_PLIST_PATH}"
     fi
     if _tunnel_vault_is_running; then
       pkill -f "ssh -N .*-R ${TUNNEL_VAULT_REMOTE_PORT}:127.0.0.1:${TUNNEL_VAULT_LOCAL_PORT}" || true
     fi
   ```

6. **`tunnel_status`:** before the `reverse:` echo, compute `vault_state` (`running` or
   `not running`) from `_tunnel_vault_is_running`. Change the `reverse:` line to end with
   `(Vault, agent ${TUNNEL_VAULT_LAUNCHD_LABEL}: ${vault_state})`. Keep the return code driven
   by the main tunnel only.

### BATS (`scripts/tests/plugins/tunnel.bats`)

- `setup` also exports `TUNNEL_VAULT_PLIST_PATH` and `TUNNEL_VAULT_WRAPPER_PATH` under
  `${BATS_TEST_TMPDIR}`. **No test may reach the real `launchctl` or `pgrep`.** Stub them in
  every test that can call them.
- Update `tunnel_start is idempotent when already running` to also stub
  `_tunnel_vault_launchd_loaded() { return 0; }`.
- New tests:
  1. The main plist written by `_tunnel_write_plist` contains `-L` and does **not** contain
     `<string>-R</string>`.
  2. The vault wrapper contains `fuser -k -n tcp 8200`, `ExitOnForwardFailure=yes` and
     `-R 8200:127.0.0.1:18200`. The vault plist has `KeepAlive` and points at the wrapper.
  3. `tunnel_start` with `_tunnel_is_running` true but a main plist that contains
     `<string>-R</string>` does NOT print `already running`. With `launchctl` stubbed to record
     its arguments, it loads both plists.
  4. `tunnel_stop` unloads the vault plist when `_tunnel_vault_launchd_loaded` returns true.

### Rollout (operator, after merge or on the next `make up`)

Step 3 calls `tunnel_start`, which migrates the agent automatically. To migrate immediately
without `make up`, run:
`./scripts/k3d-manager tunnel_start`
Then confirm both `launchctl list | grep ssh-tunnel` and `nc -z localhost 6443`.

## Review follow-up R3 (Claude, 2026-10-04, on `d49e5eb8`)

The wrapper writes `"su""do"` so that the pre-commit bare-sudo audit misses the remote `fuser`. Root is
genuinely needed there: the sandbox's 8200 listener belongs to a non-dumpable `sshd`. The operator
chose an explicit audit exemption, built upstream first in lib-foundation PR #57 (`44e7e8d`). The
tunnel change is Commit 2 of
[`2026-10-04-pre-commit-hook-loads-stale-local-agent-rigor-fork.md`](2026-10-04-pre-commit-hook-loads-stale-local-agent-rigor-fork.md),
because k3d-manager's hook did not load the upstream library until Commit 1 of that spec.
