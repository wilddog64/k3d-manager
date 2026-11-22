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

To check enrolment status:
```bash
make web-console-totp-status
```
Outputs `enrolled`, `not enrolled`, or `state damaged`.

## Login Flow and Timing

Each console login requires a 6-digit TOTP code. After two minutes without input, the gate closes its tmux client, clears the screen, and asks again. A valid code reattaches the `work` session. Jobs in its panes and other tmux clients keep running.
A second login in the same 30 s step waits for the next code because the verifier accepts each counter at most once to prevent replay.

### Lockout Rule and Guess Rate

The exact lockout rule:
- `failures` counts consecutive failed attempts (`NO` responses).
- The 5th consecutive failure sets `locked_until = now + 300` (a 5-minute lockout).
- While locked (`now < locked_until`), requests receive `WAIT <remaining_seconds>`. The verifier does not evaluate candidates or increment failures while locked.
- At the first request when `now >= locked_until`, failures and locked_until are reset to 0 before evaluating the code.
- A successful code resets failures to 0.

The guess rate: at most 5 guesses per about 300 s, under 1,440 per day, against 3 valid codes in 10^6 (about 0.43 percent per day of sustained guessing, only through a real gate, so only past Access and the certificate). A malformed line counts against the gate’s ten-prompt limit. Only a well-formed code sent to the verifier can increment its persistent failure counter.

## Recovery and Maintenance

### Lost Phone / Secret Rotation

Rotate for a lost phone using:
```bash
make web-console-totp-rotate
```
Rotation keeps the current secret valid until the first code from the new secret is successfully committed.

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
