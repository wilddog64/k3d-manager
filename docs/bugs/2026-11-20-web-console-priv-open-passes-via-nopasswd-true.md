# Bug: `_wc_priv_open` reports a sudo ticket that does not exist on Macs with k3d-manager's sudoers

**Status:** OPEN — captured 2026-11-20 during the web-console part A live check (E11 prerequisite P3), not triaged
**Priority:** P2 (proposed; install fails partway on a Mac with k3d-manager's sudoers, workaround: `sudo -v` first)
**Introduced by:** 8faebd87 (web-console part A)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (both)
**Waiting on:** operator decision — since 2026-11-20
**Prior art:** `docs/bugs/2026-11-03-vault-ca-trust-target-and-headless-sudoers-probe.md` (exact-slug glob none; `make find-similar-docs` unavailable, no cluster context; found by `grep -il "usr/bin/true"`) — read, different root cause: that bug added the `NOPASSWD: /usr/bin/true` rule on purpose so headless `sudo -n true` probes pass

## Symptom

On m4-air, 2026-11-20 15:09 PST, operator's tmux pane, checkout `388a660f` (clean): after `sudo -k`,
`_wc_priv_open` returned 0 in under a second with no password prompt. `sudo -n -v` reported "a password is required"
both before and after it. The next piped call, `_wc_priv /usr/bin/tee <root dir>/probe-1m < file`, ran as
`sudo -n /usr/bin/tee ...` and failed with "a password is required" (rc 1). Reproduced the same day in Claude's
session under `script` (a pty) with a logging `sudo` shell function: `sudo /usr/bin/true` rc 0 and
`sudo -n /usr/bin/true` rc 0, with no ticket.

## Cause

`scripts/lib/web_console_common.sh:47-59`, `_wc_priv_open`, checks the ticket with `_wc_priv /usr/bin/true`, then the
same command with stdin from `/dev/null`. `bin/install-sudoers.sh:39` installs `%admin ALL=(root) NOPASSWD: /usr/bin/true`
in `/etc/sudoers.d/k3d-manager` (present on m4-air, `sudo -n -l`, 2026-11-20). Both checks therefore pass without a
ticket and without a prompt. Every later `_wc_priv` call whose stdin or stdout is not a terminal (the `tee` streaming
of config and plist, `_wc_stage_put`) is resolved to `sudo -n` (`scripts/lib/foundation/scripts/lib/system.sh`,
`_run_command_resolve_sudo`) and fails. Calls with both on a terminal prompt one by one instead, so the first
password prompt comes from a later command rather than from `_wc_priv_open`.

Part A's Proof section (P3) planned this capture but it was still owed at dispatch. The fixtures stub `sudo`, so no
offline test could see the host's sudoers.

## Workaround

Run `sudo -v` in the same terminal before `make install-web-console-sshd`, `revoke-web-console-sshd` or
`uninstall-web-console-sshd`.

## Fix direction (for triage)

Check the ticket with something the k3d-manager sudoers does not grant passwordless, for example `sudo -v` then
`sudo -n -v </dev/null`, routed through `_run_command` or a new lib-foundation helper, never `sudo` directly. Add an
offline test whose fake sudoers grants `NOPASSWD: /usr/bin/true` (red on `8faebd87`), and rerun part A P3 live.
