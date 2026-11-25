# Web Console TOTP Gate and Fail-Closed Idle Re-Gate

This guide documents the setup, enrolment, rotation, recovery, and security model of the Web Console TOTP gate (Part C of the loopback console behind Cloudflare Access).

## Overview

Cloudflare Access and GitHub 2FA authenticate the remote browser connection. The TOTP gate provides a local second factor directly in front of the operator's shell session on the Mac.
The login shell must be zsh. After completing the console sshd installation, run `make install-web-console-totp` from the Mac. Logins remain closed until enrolment succeeds.

The gate does not rely on tmux's built-in locking. The deviation from tmux locking is that the gate owns the pty of the tmux client as a pty proxy; the idle layer ends only the gate's own tmux client and requires a code again without setting any global tmux options.

SIP not relied on: runtime files and directories are protected by root ownership and strict Unix modes only, not by SIP.

## Enrolment and Status

Enrolment is performed by the operator directly at the machine:
```bash
make web-console-totp-enroll
```
or
```bash
bin/k3dm-web-console-totp enroll
```

Enrolment refused under tmux: for accident prevention, enrolment and rotation refuse to run when `$TMUX`, `$TMUX_PANE` or `$STY` is set, over SSH (`$SSH_CONNECTION` or `$SSH_TTY`), without an interactive terminal, or as root.

During enrolment, the root helper prints the base32 secret and `otpauth://totp/` URI to `/dev/tty` only. It never writes the secret to disk, logs, environment, or command arguments until the first valid 6-digit code is confirmed via `ENROLL_COMMIT`.
The QR code appears above the secret. Enlarge the Terminal window if needed, scan it with the phone camera or an authenticator app, then type the 6-digit code. Save the recovery codes when they appear and press Enter to clear the screen. Do not click the URI.

To check enrolment status:
```bash
make web-console-totp-status
```
Outputs `enrolled`, `not enrolled`, or `state damaged`.

## Login Flow and Timing

Each console login requires a 6-digit TOTP code. After two minutes without input, the gate closes its tmux client, clears the screen, and asks again. A valid code reattaches the `work` session. Jobs in its panes and other tmux clients keep running.
A second login in the same 30 s step waits for the next code because the verifier accepts each counter at most once to prevent replay.

### Lockout Rule, Escalating Lock, and Decay

The exact lockout rule enforces an escalating schedule (see parent [`docs/bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md`](../bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md), section B1):
- `failures` counts consecutive failed attempts (`NO` responses).
- The 5th consecutive failure increments `lock_level` (from 1 to 4) and sets `locked_until = now + LOCK_SECONDS[level-1]`:
  - Level 1: 300 s (5 minutes)
  - Level 2: 1,800 s (30 minutes)
  - Level 3: 14,400 s (4 hours)
  - Level 4: 86,400 s (24 hours)
- At level 4, each further run of 5 consecutive failures re-locks for 86,400 s (~5 guesses per day).
- While locked (`now < locked_until`), requests receive `WAIT <remaining_seconds>`. The gate displays:
  `Too many attempts; try again later (<n> s)`
  showing the remaining seconds. The verifier does not evaluate candidates or increment failures while locked.
- Expiry and escalation: When a lock expires, `failures` resets to 0 upon the next request, but `lock_level` is retained on disk so subsequent failures escalate to the next tier.
- Decay: While no lock is active and `lock_level > 0`, the level drops by one for each full 86,400 s (24 hours) elapsed since the last lock expired (`locked_until`). Decay is evaluated at daemon start and on TOTP verification requests (not on recovery-code entries, and not while a lock is still active). When `lock_level` reaches 0, the state returns to the 5-key format with `locked_until: 0`.
- Clearing: A correct TOTP code, a valid recovery code, `totpctl unlock`, enrol, or rotate resets `failures`, `locked_until`, and `lock_level` to 0.

The guess rate: at most 5 guesses per about 300 s initially (under 1,440 per day at level 1, dropping to about 5 guesses per day at level 4), against 3 valid codes in 10^6. A malformed line counts against the gate's ten-prompt limit. Only a well-formed code sent to the verifier can increment its persistent failure counter.

### macOS Sleep and Monotonic Clock

The running daemon enforces active locks against `time.monotonic()` with an in-process deadline established when the lock is set or at startup (see parent [`docs/bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md`](../bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md), section B2).

On macOS, `time.monotonic()` pauses during system sleep. Consequently, a lock imposed before sleep runs for its full awake duration after waking; it never shortens.

## Recovery and Maintenance

### Lost Phone / Secret Rotation

Rotate for a lost phone using:
```bash
make web-console-totp-rotate
```
Rotation keeps the current secret valid until the first code from the new secret is successfully committed.

### Unlock and Recovery Codes

Every unlock path shipped by parts A1 and A2 (see parent [`docs/bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md`](../bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md), sections B4 and B8):

- **Root unlock (local host):**
  From a root terminal on the machine:
  ```bash
  sudo /Library/PrivilegedHelperTools/k3dm-web-console/totpctl unlock
  ```
  Sends `UNLOCK` over `admin.sock` (restricted to peer UID 0). It resets `failures`, `locked_until`, and `lock_level` to 0, commits state in the clean 5-key format, and prints `unlocked`. Non-root callers are refused.
- **Console-side no-root unlock (recovery codes):**
  When travelling or without root access to the hub, the operator can unlock directly at the console `Code:` prompt using a one-time recovery code:
  - Enter one 16-character code (e.g. `XXXX-XXXX-XXXX-XXXX`).
  - Formatting and input handling: The prompt does not show what you type. A recovery code can be pasted or typed, with or without dashes or spaces, in any case. Codes are uppercase letters A-Z and digits 2-7 only; there is no digit 0, 1, 8 or 9, and 0, 1, 8 typed for O, I, B are accepted. When an input is refused, the gate prints one of two messages: "Invalid code (6 digits, or a 16-character recovery code: letters A-Z, digits 2-7)" indicates a local format rejection (input was neither 6 digits nor 16 recovery characters, or overflowed the 20-character cap); while "Invalid code" without a hint indicates that a well-formed code was refused by the verifier.
  - Single use and commit order: A valid recovery code is burned on disk (`recovery.json`) atomically before state reset is committed. If the server replies "unavailable" (for example, due to a state commit error), that recovery code is spent — use another.
  - Session and attempt limits: While the daemon imposes no attempt limit on recovery codes (wrong recovery codes return `NO` and never increment `failures` or alter `lock_level` or `locked_until`), the console gate counts each wrong entry against its ten-prompt session limit (closing the SSH session after ten failed attempts) and pauses about 2 s after each attempt.
  - Reset effect: A valid recovery code immediately resets `failures`, `locked_until`, and `lock_level` to 0.
- **Managing recovery codes (root, at home):**
  - Ten single-use recovery codes are displayed once on `/dev/tty` during enrolment (`make web-console-totp-enroll`) and rotation (`make web-console-totp-rotate`). After a successful commit, they stay visible until you press Enter to clear the screen. Enrolment and rotation provide a 300 s window; regeneration provides 600 s. Have a safe storage location ready before starting.
  - Codes printed during enrol, rotate, or recovery-regen are void if the confirming TOTP code fails (the command output notes when codes are void); store them only after the command reports success.
  - Keep the ten recovery codes safely off the travel device.
  - Inspect remaining recovery codes:
    ```bash
    sudo /Library/PrivilegedHelperTools/k3dm-web-console/totpctl recovery-status
    ```
    Outputs `<n> recovery codes remaining`.
  - Regenerate recovery codes:
    ```bash
    sudo /Library/PrivilegedHelperTools/k3dm-web-console/totpctl recovery-regen
    ```
    Prompts `Replace all recovery codes? Type yes: ` (600 s timeout). Type `yes`, then enter a valid 6-digit TOTP code. The ten new codes are displayed on `/dev/tty`; press Enter after saving them to clear the screen. Regenerate when two or fewer codes remain (`totp-recovery-low` is logged when remaining <= 2).
  - Also, entering a correct TOTP code, enrol, or rotate resets any active lockout.
- **Code exhaustion under sustained attack (parent B8):**
  An attacker holding a console certificate cannot use a recovery code they do not know, but could repeatedly trigger TOTP lockouts, costing the operator one recovery code per login. The remedy is to revoke that certificate using `ssh-keygen -k -u` (see [`docs/howto/web-console-sshd.md`](web-console-sshd.md) and parent section B7) and regenerate recovery codes with `totpctl recovery-regen` at home.

### Structured Audit Logging

Event lines are appended to `/var/log/k3dm-web-console-totp.log` (see parent [`docs/bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md`](../bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md), section B5).

The structured format `<UTC ISO-8601> event=<name> key=value ...` applies only to:
- `event=totp-failure failures=<n> lock_level=<l>`: recorded on each failed authentication attempt.
- `event=totp-lock lock_level=<l> seconds=<s>`: recorded when a lockout is imposed (with numeric seconds).
- `event=totp-locked-reply lock_level=<l>`: recorded on the first refused attempt per lock and again after a daemon restart.
- `event=totp-unlock source=<admin|success|recovery|enrol|rotate|decay>`: recorded when a lockout is cleared (`source=decay` is logged only when decay reaches level 0).
- `event=totp-recovery-used remaining=<n>`: recorded when a recovery code is redeemed.
- `event=totp-recovery-low remaining=<n>`: recorded when two or fewer recovery codes remain.

In addition, recovery failure and corruption events are logged as bare lines without the timestamp or `event=` prefix:
- `totp-recovery-failure count=<n>`: summary of wrong recovery code attempts (throttled to at most one line per 60 s).
- `totp-recovery-damaged`: recorded on recovery file corruption or invalid permissions.

These log lines never record entered codes, the secret, counter values, recovery codes, salts, or hashes.

### Rollback

In v1.45.0, `load_state` requires exactly 5 keys. If `lock_level` (levels 1–4) is recorded on disk, rolling back causes v1.45.0 `totpd` to fail to load state, displaying "console login unavailable". Furthermore, v1.45.0 still enforces `locked_until` without an unlock command, so an active 24 h lock would persist (see parent [`docs/bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md`](../bugs/2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md), section "Rollback").

Before reinstalling the older part C version, run `totpctl unlock` as root (recommended path):
```bash
sudo /Library/PrivilegedHelperTools/k3dm-web-console/totpctl unlock
```
This resets state to the 5-key format with `failures`, `locked_until`, and `lock_level` cleared.

If the older version was already reinstalled and reports "console login unavailable":
Reset `failures` and `locked_until` to 0 and remove `lock_level` in place using an atomic write, without printing `state.json` (which holds the TOTP secret):
```bash
sudo /Library/Developer/CommandLineTools/usr/bin/python3 -I -c '
import json, os
p = "/var/db/k3dm-web-console/state.json"
tmp = "/var/db/k3dm-web-console/state.json.tmp"
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
d["failures"] = 0
d["locked_until"] = 0
d.pop("lock_level", None)
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(d, f)
    f.flush()
    os.fsync(f.fileno())
os.replace(tmp, p)
'
```
Or purge the state and re-enrol:
```bash
make uninstall-web-console-totp PURGE_SECRET=1
make install-web-console-totp
make web-console-totp-enroll
```

`recovery.json` is ignored by v1.45.0. It remains untouched across rollback, survives non-purge uninstall, and becomes active again upon re-upgrade. `PURGE_SECRET=1` removes it.

### Damaged State

State files are committed atomically (`state.json.tmp` synced and renamed).
Repair of a damaged state: repair by uninstall --purge-secret and enrol again:
```bash
make uninstall-web-console-totp PURGE_SECRET=1
make install-web-console-totp
make web-console-totp-enroll
```

If the helper prints `commit not confirmed; run web-console-totp-status`, run `make web-console-totp-status`. After initial enrolment, `enrolled` means the displayed secret was saved. If status shows `not enrolled`, wait five minutes for the pending secret to expire, then enrol again.

After an unconfirmed rotation, try a fresh code from the new secret at the console. If status reports not enrolled or the old secret still works, wait five minutes for the pending secret to expire, then run rotate again. A rotate attempt refused during that pending window may print `state damaged`; wait for the same five-minute expiry and retry rotate. Use the purge and reinstall procedure above for a persistently damaged state.

### Command Line Tools Updates

Interpreter components reside in `/Library/Developer/CommandLineTools`.
Run `make install-web-console-totp` again after a Command Line Tools update to re-verify the new binaries. If a login fails after the update, the gate cannot start and console logins fail closed until installation succeeds. If the update moved the framework away from Versions/3.9, install exits 2 with `python interpreter missing` when its pinned Python executable is absent. A failed path trust check exits 8. The installer names a path when it identifies an untrusted path, but a missing framework component may only produce the general refusal. Use the local console until a release updates the pinned path.

### TMUX Environment

The gate drops ambient environment variables. TMUX_TMPDIR is dropped; a non-default TMUX_TMPDIR would give the console a different, empty server.

## Security Model and Named Residuals

- **R-INSIDER (runtime):** An authenticated operator inside the console is trusted: the idle layer protects an unattended screen, not the person who logged in.
- **R-ACTIVITY (runtime):** Terminal reply sequences that the filter does not recognize or bytes injected by a same-user process keep the session active. Pane output alone does not reset the timer.
- **R-DENIAL (runtime):** A same-user process outside the console cannot read secrets or reach lockout through the verifier socket, but that a flooded verifier closes a login, which is then repeated.
- **R-TTY (runtime):** The gate's outer terminal is an operator-owned pty. A process running as the operator can read terminal input, draw a fake prompt, or inject keystrokes. Replacing an operator-writable tmux executable gives the replacement the same terminal access after a valid login. A program running as the operator can inject wrong codes into a live genuine gate, that they count as failures and can reach the lockout, and that recovery is rotate or the local console.
- **R-SUSPEND (runtime):** A same-user `SIGSTOP` of the gate freezes the idle timer; not claimed against.
- **R-REVOKE-CODE (runtime):** Revoke and uninstall execute checkout code.
- **R-ENROL (trusted step):** Enrolment displays the secret on the operator's terminal from a root process.
- **R-INSTALL (trusted step):** Install runs checkout code and installs the tracked files after verifying the checkout against HEAD. Use a checkout you trust and watch the install at the machine.
- **R-SUDO (trusted step):** The operator opens a sudo ticket for the installation. Another process with access to that ticket during its lifetime is a residual risk.
