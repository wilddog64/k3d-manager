# Web console captures, 2026-11-19 (part B C6, C11, C12 launchd states, C17)

Hosts: m4-air (macOS 26.5.2) and m5-air (macOS 26.5.1), OpenSSH_10.2p1, LibreSSL 3.3.6. Captured by Claude with a root
driver the operator started once with sudo; scratch sshd `com.k3d-manager.capture-sshd` on 127.0.0.1:42723 with
throwaway host key, CA and user keys (all deleted afterwards). Spec: `docs/plans/v1.45.0-web-console-b-captures.md`.
Redaction: login and home replaced by `<login>`/`~` (including 16-character-truncated process titles); entry
environment variable names dropped. Operator read these on 2026-11-19 before they were saved.

| Capture | Files | Result |
|---|---|---|
| C6 | `c6-m4-unpriv.txt`, `c6-m4-root.txt`, `c6-m5.txt`, `c6-lsof.txt` | Remote Login on both Macs; system sshd has password and keyboard-interactive auth on, `usepam yes`. Part A C8 reports `WARN` (umbrella decision 2: the `FROM=` pull uses the SSH login password). Scratch listener bound 127.0.0.1:42723 only, owned by root. |
| C11 | `c11-login1.txt`, `c12-unpriv.txt` | `SetEnv ZDOTDIR` takes effect before zsh startup files: the marker `.zshenv` ran with the marker dir and not with the empty dir. Entry runs `-IS` (isolated=1, no_site=1); parent is the user `sshd-session @notty`, then `[priv]` (uid 0), then the listener. |
| C12 | `c12-unpriv.txt`, `c12-lp-up.txt`, `c12-idle.txt`, `c12-lp-idle.txt`, `c12-absent.txt`, `c12-launchctl-sudo.txt`, `c12-chain.txt` | Unprivileged `launchctl print system/<label>` exits 0 with `state`, `pid`, `arguments`; an unloaded label exits 113 ("Could not find service"); a loaded idle job shows `state = not running`, no `pid`. Remote Login sessions have ppid 1, not the console listener. |
| C17a | `c17a-before.txt`, `c17a-after.txt`, `c17a2-before.txt`, `c17a2-after.txt` | `launchctl bootout` of the listener leaves a logged-in session alive (its `[priv]` reparents to pid 1, still ESTABLISHED at +35 s); its forced-command child also outlived the client disconnect. A pre-auth `[accepted]` connection survives bootout until `LoginGraceTime` (30 s). Revoke must kill sessions and the entry's process tree. |
| C17b | `c17b-enabled.txt`, `c17b-prod.txt`, `c17b-sftp-control.txt`, `c17-readback.txt` | Positive controls (forwarding enabled): `-L`, `-D`, `-R`, `-W`, stream-local `-L`, `-A` all carried data; sftp works without ForceCommand. Production profile: every one refused (`-W` "administratively prohibited", no `SSH_AUTH_SOCK`), sftp blocked by ForceCommand. `sshd -T -C` readback matches. X11 has no client on stock macOS; readback only. |

Driver log: `root-steps.log`; sshd logs per profile: `sshd-*.log`; root scratch layout: `r-layout.txt`.
