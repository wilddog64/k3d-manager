# Bug: `make install-web-console-sshd` always fails on macOS: it calls `/usr/bin/chmod`, which does not exist

**Status:** OPEN — spec rev 1, 2026-11-24
**Priority:** P1 (blocks the v1.45.1 first install of part A, so the TOTP and RevokedKeys live checks cannot run; no workaround without editing the installer)
**Triage:** patch → v1.45.1 (blocks the open release)
**Branch:** k3d-manager-v1.45.1
**Introduced by:** `d6e1e7a6` (totp-b, "enforce RevokedKeys KRL for console certificates")
**Should have been caught by:** offline test (the fixture resolves every tool by basename, `scripts/lib/web_console_common.sh:26`, so an absolute path that does not exist on macOS can never fail a test)
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-24 (intent approval, then dispatch)
**Intent approved:** pending
**Prior art:** `ls docs/bugs/*chmod*` none; `make find-similar-docs` returned no rows (vector store not reachable from m4) — none above threshold
**Detected by:** operator, first `make install-web-console-sshd CA_FILE=…` on m5-air (the hub), 2026-11-24; exit 8 after `web-console-sshd: rolled back an interrupted install`

## Evidence

- Operator trace on m5-air, 2026-11-24 (`bash -x bin/k3dm-web-console-sshd install --ca-file …`, read by Claude over SSH,
  `/tmp/k3dm-wc-trace.log` lines 2394–2399): `_wc_priv /usr/bin/ssh-keygen -k -f …/.stage.*/revoked_keys` succeeds, then
  `_wc_priv /usr/bin/chmod 0644 …/.stage.*/revoked_keys` fails and `_wc_stage_keys` returns 8
  (`bin/k3dm-web-console-sshd:471`). The `2>/dev/null` on that line hid the "No such file or directory".
  The EXIT trap then rolled the half-done install back; m5-air was left clean (no `/etc/k3dm-web-console`, no
  `/Library/PrivilegedHelperTools/k3dm-web-console`, no `/var/db/k3dm-web-console.txn`).
- m5-air (macOS 26.5.1, OpenSSH_10.2p1) and m4-air, read-only, 2026-11-24: `/usr/bin/chmod` does not exist; `/bin/chmod`
  exists (root:wheel 0755). An empty KRL from `/usr/bin/ssh-keygen -k -f <tmp>/revoked_keys` succeeds (rc 0, 44 bytes).
- Every absolute tool path in `bin/k3dm-web-console-sshd`, `bin/k3dm-web-console-totp` and
  `scripts/lib/web_console_common.sh`, checked with `[ -x ]` on m5-air 2026-11-24: all exist except `/usr/bin/chmod`
  (and `/usr/bin/tmux`, which is one of four probed candidates in `bin/k3dm-web-console-totp:36`, not a hard call).

## Fix

`bin/k3dm-web-console-sshd:471`: `/usr/bin/chmod` → `/bin/chmod`. Nothing else in the installers changes.

## Files

| File | Change |
|---|---|
| `bin/k3dm-web-console-sshd` | line 471 only |
| `scripts/tests/bin/web_console_tool_paths.bats` (new) | E1 below |

## Acceptance

```yaml
must:
  - M1: bin/k3dm-web-console-sshd calls chmod as /bin/chmod; no other line of the three web-console scripts changes.
  - M2: Every absolute tool path invoked in bin/k3dm-web-console-sshd, bin/k3dm-web-console-totp and
        scripts/lib/web_console_common.sh (any /bin/, /usr/bin/, /usr/sbin/, /sbin/ or /usr/libexec/ path word, except
        the tmux candidate list in bin/k3dm-web-console-totp) is in the m5-air capture list below.
must_not:
  - N1: Must not reference /usr/bin/chmod anywhere in the three scripts.
        Red today: bin/k3dm-web-console-sshd:471.
evidence:
  - {id: E1, proves: [M2, N1], kind: offline, intent: "A test fails whenever the web-console installers call a system tool at a path that does not exist on the hub's macOS, so this class of install failure is caught before a live install", command: "bats scripts/tests/bin/web_console_tool_paths.bats", red_control: "fails on k3d-manager-v1.45.1@fd5812a0 naming /usr/bin/chmod; positive control in the same file: the scan finds at least 20 paths, and a temp copy of the sshd script with an added /usr/bin/doesnotexist call is reported"}
  - {id: E2, proves: [M1], kind: live, intent: "The console sshd installs on the hub from a normal first install", command: "operator on m5-air: make install-web-console-sshd CA_FILE=$HOME/.ssh/k3dm-console-test-ca.pub, then make web-console-sshd-check", red_control: "the 2026-11-24 run above (exit 8 after the rollback line)"}
interface:
  - "no interface change"
```

Capture list for E1 (m5-air, macOS 26.5.1, `[ -x ]` each, 2026-11-24; put it in the test with this comment):
`/bin/bash /bin/cp /bin/chmod /bin/date /bin/kill /bin/launchctl /bin/ls /bin/mkdir /bin/mv /bin/ps /bin/rm /bin/sleep
/bin/zsh /usr/bin/head /usr/bin/id /usr/bin/install /usr/bin/mktemp /usr/bin/plutil /usr/bin/shasum /usr/bin/ssh-keygen
/usr/bin/stat /usr/bin/tee /usr/bin/uname /usr/sbin/netstat /usr/sbin/sshd`.
The test reads the scripts as text only. It runs nothing from them, needs no macOS, and passes on the Linux CI runner.

## Worker definition of done

- Change only the two files above. Offline only: no sudo, no install, nothing under `/etc` or `/Library`.
- Show E1 red against `fd5812a0` before the fix, then green; `bats scripts/tests/bin/web_console_sshd.bats` stays green.
