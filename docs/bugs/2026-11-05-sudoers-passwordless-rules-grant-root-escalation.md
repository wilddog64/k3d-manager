# Bug: passwordless sudoers rules let any same-user process gain root (self-update and /usr/local/bin wildcards)

**Status:** CLOSED: VERIFIED 2026-11-05. Fixed in `4c4f7dd1`. Independent verify PASS. Live E4 PASS on the M4. The fixed rules are reinstalled on M4, M5 and M2.
**Priority:** P1
**Severity:** high — local privilege escalation. Any process running as an `%admin` user (a dispatched Codex/agy agent, a compromised npm/pip postinstall, a malicious repo script) can become root with no password, on every Mac that ran `make install-sudoers`.
**Filed:** 2026-11-05
**Detected by:** Terra's abandoned Phase C worktree inventory (`docs/issues/2026-11-02-acg-phase-c-privileged-inventory.md`, archived 2026-11-05 in `~/.local/share/k3d-manager/archive/2026-11-02-acg-up-stalls-at-system-keychain-trust/untracked.tar.gz` after its worktree was abandoned), re-checked by Claude against `bin/install-sudoers.sh` on `k3d-manager-v1.43.14` (`7c9927e9`).
**Branch:** `k3d-manager-v1.43.14`
**Approval:** Operator, 2026-11-05: "please proceed with P1 bug that dispatch to Luna".
**Related:** `docs/bugs/2026-11-02-acg-up-stalls-at-system-keychain-trust.md`, `docs/bugs/2026-11-03-vault-ca-trust-target-and-headless-sudoers-probe.md`, `docs/plans/v1.45.4-*` (AI attack surface).

## Evidence

The installed rules in `bin/install-sudoers.sh` (`_SUDOERS_CONTENT`), as of `7c9927e9`:

- Line 48: `%admin ALL=(root) NOPASSWD: /usr/bin/install -m 0440 /tmp/k3d-manager-sudoers.* /etc/sudoers.d/k3d-manager`.
  Any user process writes `/tmp/k3d-manager-sudoers.x` containing `%admin ALL=(ALL) NOPASSWD: ALL` and installs it. That is passwordless root in one step.
- Line 47: `NOPASSWD: /usr/bin/install -m 0755 * /usr/local/bin/k3d-manager-update-hosts`, together with line 52, `NOPASSWD: /usr/local/bin/k3d-manager-update-hosts *`.
  The process replaces the root-run helper with its own script, then runs it as root.
- Lines 55–57: `NOPASSWD: /usr/bin/install -m [0-9][0-9][0-9] * /usr/local/bin/*`, `/bin/cp * /usr/local/bin/*`, `/bin/chmod [0-9][0-9][0-9] /usr/local/bin/*`.
  - A sudoers `*` matches `/` and spaces, so the destination can be `/usr/local/bin/../../etc/sudoers.d/x`.
  - Even without traversal, the process can overwrite `/usr/local/bin/k3s` or `k3d-manager-update-hosts`. Both have their own `NOPASSWD ... *` exec rules (lines 52 and 60), so the overwrite runs as root.
- `bin/update-hosts-entry.sh` runs as root with caller-chosen `$1`/`$2` and does not validate them.
  A hostname or IP containing a newline or whitespace writes arbitrary `/etc/hosts` lines, for example to redirect `github.com`.

Host state (M4, 2026-11-05): `/etc/sudoers.d/k3d-manager` is installed (Jun 4, root:wheel 0440), and so is `/usr/local/bin/k3d-manager-update-hosts`. `/usr/local/bin` and `/Library/LaunchDaemons` are root-owned, so the only way in is the rules above.

Legitimate callers of the removed rules:
- **Self-update.** `make install-sudoers` already runs both installs through `_run_command --interactive-sudo` (lines 125–127). It is an operator-at-the-keyboard action and needs no passwordless rule.
- **`/usr/local/bin` wildcards.** `_k3s_stage_file` (`scripts/lib/core.sh:129-135`) and the istioctl install (`scripts/lib/core.sh:486-488`) use `--prefer-sudo`. These are Linux k3s and first-time tool installs. A headless macOS run that needs them now fails fast through `sudo -n` instead of being silently root-capable. That trade-off is intended.

## Out of scope (separate bug, design pending)

Do **not** change these in this fix:
- **LaunchDaemon rules.** `install -m 644 * /Library/LaunchDaemons/com.k3d-manager.*.plist` plus `launchctl bootstrap system ...` is also a root escalation, because the caller picks the plist's `ProgramArguments`. Headless `acg-up` depends on it today (`bin/cluster-up:906,1573,1748,1813`), so fixing it needs a design, which this narrow fix does not attempt. Tracked as `docs/bugs/2026-11-05-sudoers-launchdaemon-plist-rule-is-root-equivalent.md`, to be filed.
- **Wildcard rules that need no write rule to abuse:** `k3s *`, `systemctl *`, `apt-get *`, `dnf *`, `yum *`, `microdnf *`, `ifconfig lo0 ...`, `rm -f /Library/LaunchDaemons/... *`. Same follow-up bug.
- The webhook, `cluster-up`, the LaunchDaemon listeners, privileged helpers and supervisors. Phase C attempted these and they are explicitly **not** wanted here.

## Fix

In `bin/install-sudoers.sh` `_SUDOERS_CONTENT`:
1. Delete the three self-update rules (lines 46–49 block: the `update-hosts` install, the `/tmp/k3d-manager-sudoers.*` install, and the `update-hosts` rm). Uninstall already uses `--interactive-sudo`.
2. Delete the three `/usr/local/bin/*` binary install, cp and chmod rules (lines 54–57 block).
3. Leave every other rule byte-for-byte unchanged.

In `bin/update-hosts-entry.sh`: before touching `/etc/hosts`, reject the call (exit non-zero, `/etc/hosts` untouched) unless:
- the hostname matches `^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$`
- the IP is a dotted IPv4 with four octets of 0–255
- exactly two arguments were given

Keep the existing replace-and-append behaviour for valid input.

Tests: extend `scripts/tests/bin/install_sudoers.bats` (dry-run output) and add `scripts/tests/bin/update_hosts_entry.bats`. The helper must take its hosts file path from a test-only env override, `K3DM_HOSTS_FILE`, defaulting to `/etc/hosts`, so tests never touch the real file. Each fixture first asserts that it is pointed at the scratch file.

Live remediation (operator, after merge): rerun `make install-sudoers` on M4, M5 and M2. It prompts for a password once and overwrites the old file.

## Files

- `bin/install-sudoers.sh`
- `bin/update-hosts-entry.sh`
- `scripts/tests/bin/install_sudoers.bats`
- `scripts/tests/bin/update_hosts_entry.bats`
- `docs/bugs/2026-11-05-sudoers-passwordless-rules-grant-root-escalation.md`

## Acceptance

```yaml
must:
  - id: M1
    text: "`bin/install-sudoers.sh --dry-run` still prints the rules and exits 0 after `visudo -c` succeeds."
  - id: M2
    text: "Every rule line other than the six removed ones is still present, unchanged."
  - id: M3
    text: "`bin/install-sudoers.sh` install mode still installs both files through `_run_command --interactive-sudo`."
  - id: M4
    text: "update-hosts-entry with a valid hostname and IPv4 replaces the existing line for that hostname and appends `<ip> <host>`."
must_not:
  - id: N1
    text: "No NOPASSWD rule has a command whose arguments name /etc/sudoers.d (no passwordless sudoers rewrite)."
  - id: N2
    text: "No NOPASSWD rule lets install, cp or chmod write under /usr/local/bin, including the update-hosts helper path."
  - id: N3
    text: "update-hosts-entry must not modify the hosts file when the hostname or IP contains whitespace, a newline or other invalid characters, when an octet is above 255, or when the argument count is not 2."
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    text: "BATS on `--dry-run` output: N1/N2 red on 7c9927e9, green on fix; M2 compares remaining rule lines to the pre-fix set minus the six."
  - id: E2
    proves: [M4, N3]
    kind: offline
    text: "BATS on update-hosts-entry with K3DM_HOSTS_FILE pointed at a scratch file (fixture asserts the target is not /etc/hosts); N3 cases red on 7c9927e9; M4 is the paired positive control."
  - id: E3
    proves: [M3]
    kind: offline
    text: "Static check that both install calls in install mode still use `_run_command --interactive-sudo`."
  - id: E4
    proves: [N1, N2]
    kind: live
    text: "Operator reruns `make install-sudoers` on M4; Claude runs `sudo -n -l /usr/bin/install -m 0440 /tmp/k3d-manager-sudoers.x /etc/sudoers.d/k3d-manager` and expects it refused."
interface:
  - "bin/install-sudoers.sh --dry-run"
  - "bin/update-hosts-entry.sh <hostname> <ip>  (env K3DM_HOSTS_FILE overrides /etc/hosts)"
```

## Review notes (Claude, 2026-11-05)

- Luna's diff removes exactly the six rules. Every other rule is unchanged: the dry-run comparison test checks this.
- **Claude hardening 1.** `update-hosts-entry` now ignores `K3DM_HOSTS_FILE` when `EUID` is 0. The helper runs as root under sudo, and env_reset strips the variable today, but a future `env_keep` or `SETENV` would otherwise turn it into an arbitrary root file write.
- **Claude hardening 2.** IPv4 octets are limited to `[0-9]{1,3}`. `18446744073709551616.1.1.1` wrapped to 0 in Bash arithmetic and passed the `> 255` check. A mutation check showed the new test fails on Luna's regex.
- **Pre-fix red.**
  - N1 and N2: the dry-run tests fail on `7c9927e9`.
  - N3: 7 of 8 cases fail on `7c9927e9` once the pre-fix helper's `/etc/hosts` is replaced by the test seam. The argument-count case was already guarded by `${1:?}`.
  - M4 passes on the pre-fix seam copy, as the positive control.

## Independent verification (2026-11-05)

A Sonnet verifier wrote 15 BATS tests from the Acceptance block only. Claude reran them:
- Fix `4c4f7dd1`: rc 0, 15 of 15 pass.
- Pre-fix `7c9927e9`: rc 1, with 11 red (N1, N2, N2b, N3a–N3h).
- M1–M4 pass on both versions, as the positive controls.

The evidence is recorded with `k3dm-codex-dispatch verify`. Its verifier header was normalised to `claude-sonnet-independent`, because the validator rejects spaces and parentheses.

## Live verification E4 (Claude, M4, 2026-11-05)

The operator ran `make install-sudoers` on the M4 and the M5; both succeeded. `/etc/sudoers.d/k3d-manager` on the M4 is dated Nov 5 15:54, 1823 bytes.

**Correction to E4 as written.** `sudo -n -l <cmd>` is not a valid check. It returned rc 0 for the removed commands and for `/usr/bin/true` alike, even after `sudo -k`. With the default `listpw=any`, it reports a command as permitted when any rule allows it, including the admin group's password-required `(ALL) ALL`. The check that does tell them apart is the full `sudo -n -l` listing, which shows each rule's `NOPASSWD` tag.

Result on the M4: the listing has `(ALL) ALL` plus exactly the 16 expected `NOPASSWD` rules, the same lines as the M2 dry-run test. None of the six removed rules appears: no `/etc/sudoers.d` target, and no install/cp/chmod rule under `/usr/local/bin`. **N1 and N2 PASS live.**

The M2 is pending until the bash 3.2 crash is fixed, or until it is installed with Homebrew bash (`/opt/homebrew/bin/bash bin/install-sudoers.sh`).

## Remediation complete (2026-11-05)

- **M2.** The operator ran `eval "$(brew shellenv)"`, then `make install-sudoers` on `k3d-manager-v1.43.14`. The output shows `Installed /etc/sudoers.d/k3d-manager` and `Installed /usr/local/bin/k3d-manager-update-hosts`. Claude cannot reach the M2, so the full `sudo -n -l` listing was checked on the M4 only.
- **M5.** `make install-sudoers` succeeded (operator report).
