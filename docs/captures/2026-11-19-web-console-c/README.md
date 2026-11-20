# Web console captures, 2026-11-19 (part B C12 admission/restart, C14, C16 for part C)

Host: m4-air (macOS 26.5.2), OpenSSH_10.2p1, CLT python3 3.9. Captured by Claude 2026-11-20 03:40-03:50Z with a root
driver (`cap-root.sh`) the operator started once with sudo; scratch sshd `com.k3d-manager.capture-sshd` on
127.0.0.1:42723 (ForceCommand = scratch entry, throwaway host key, CA and user cert) and scratch verifier
`com.k3d-manager.capture-totpd` (`KeepAlive` true, `ThrottleInterval` 10) under `/private/var/db/k3dm-capture-2026-11-19c`,
all removed at teardown (`root-steps.log` last line). Spec: `docs/plans/v1.45.0-web-console-b-captures.md`; closes part C
proofs in `docs/plans/v1.45.0-web-console-c-totp-gate.md` (Proof owed). Redaction: login replaced by `<login>`, home by
`~`; the off-chain parent's `args` (Claude's harness shell command line) elided. Operator read these on 2026-11-19 before
they were saved.

| Capture | Proof | Files | Result |
|---|---|---|---|
| C12 admit | P4, P12 | `c12-admit-session.txt`, `c12-admit-offchain.txt`, `totpd.log` | Through sshd: `ADMIT yes`, chain listener 90707 → `sshd-session: <login> [priv]` (uid 0) → `sshd-session: <login>@ttys006` (uid 501) → peer `comm=…/Python.app/Contents/MacOS/Python`, `args=… -IS <R>/entry`. Same entry run by the same user outside sshd: `ADMIT no c: parent … /bin/zsh`. |
| C12 layout | P9 | `c12-totpd-layout.txt`, `c12-eacces.txt` | `state/` 0700, `run/` and `state/run/` 0755, `totp.sock` 0666, `admin.sock` 0600. As uid 501: `admin.sock` and `state/run/totp.sock` connect errno 13; `ls state` denied. |
| C12 restart | P13 | `c12-restart.txt`, `c12-totpd-launchctl.txt` | `EXIT1` on `admin.sock` → at +0.5 s `runs = 2`, new pid, `last exit code = 1`; the throttle bounds launch spacing, not delay after a long-lived exit. The restarted socket answers (root peer refused by rule a, `peer uid 0 != 501`). |
| C14 tty | P6 (partial), P7 | `c14-tty-tmux-root.txt`, `c14-sudotty-sshd.txt`, `c14-raw.txt` | sudo-run `PY -IS` writes `/dev/tty` rc=0 from a tmux pane and over the scratch sshd session (sudo prompted for the password there although the operator's pane had a cached timestamp). Raw mode `isig=0`; `^C ^Z ^\ ^D` arrive as bytes `03,1a,1c,04`. The plain-terminal (non-tmux) P6 case is run by hand. |
| C14 disconnect | P7 | `c14-sig-driver.txt`, `c14-sig-*-client.log` | Client killed with SIGTERM, SIGHUP or SIGKILL: the session process logs `SIGHUP`, then `EOF`, then `exit`, all at 1.01 s (1 s after start, when the client was killed). |
| C16 tmux | P10 | `c16-gate.txt`, `c16-desk-cmp.txt` | tmux server started inside the console session: `security show-keychain-info` rc=36 (interaction not allowed); desk-started server rc=0. Attribute-only `find-generic-password` (no `-w`) rc=0 and `launchctl print gui/501` rc=0 in both; both report `managername=Background`. |
| C16 lldb | P11 | `c16-lldb.txt` | `lldb` as the operator against a process started through the console: `attach failed: this is a non-interactive debug session, cannot get permission to debug processes` (SIP disabled on this Mac). Both tmux servers killed afterwards (`has-session rc=1`). |

Driver log: `root-steps.log`; scratch sshd log: `sshd.log`.
