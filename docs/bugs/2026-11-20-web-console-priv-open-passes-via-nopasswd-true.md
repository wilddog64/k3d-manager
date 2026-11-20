# Bug: `_wc_priv_open` reports a sudo ticket that does not exist on Macs with k3d-manager's sudoers

**Status:** OPEN — captured 2026-11-20 during the web-console part A live check (E11 prerequisite P3); fix spec below, Fable review pending
**Priority:** P2 (Claude-owned per the P2/P3 split; install fails partway on a Mac with k3d-manager's sudoers, workaround: `sudo -v` first)
**Introduced by:** 8faebd87 (web-console part A)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (both)
**Waiting on:** dispatch — since 2026-11-20 (after Fable spec review)
**Prior art:** `docs/bugs/2026-11-03-vault-ca-trust-target-and-headless-sudoers-probe.md` (exact-slug glob none; `make find-similar-docs` unavailable, no cluster context; found by `grep -il "usr/bin/true"`) — read, different root cause: that bug added the `NOPASSWD: /usr/bin/true` rule on purpose so headless `sudo -n true` probes pass
**Approval:** operator, 2026-11-20: P2s are Claude's to finish, no grooming wait ("I thought P3 bugs are waiting for grooming not P2"); dispatch to Flash, Fable reviews the spec first ("intents approve and send to Fable for review"). Target branch `k3d-manager-v1.45.0`; part A is unreleased, so this is a fix inside v1.45.0, not a patch release.
**Intent approved:** operator, 2026-11-20 ("intents approve and send to Fable for review"; E1–E4). The approval came before Claude showed the text, so Claude showed the intents in the same session.

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

Same flaw, second site: the headless branch of `_wc_revoke` (`bin/k3dm-web-console-sshd:374-376`) decides "a ticket is
open" with `_wc_priv /usr/bin/true </dev/null`. That always passes under the NOPASSWD rule, so a headless revoke with
no ticket goes past the check and fails at its first real privileged step.

## Fix

1. `_wc_priv_open` (`scripts/lib/web_console_common.sh:47`) keeps its first two branches unchanged: in fixture mode
   it appends `priv_open` to `calls.log`, and with no terminal it prints the existing message and returns 10 without
   calling sudo. It then makes two `_wc_priv` calls. Neither command may be granted NOPASSWD by `bin/install-sudoers.sh`
   (today: `/usr/bin/true`, `k3d-manager-update-hosts`, `k3s*`, `systemctl`, `apt-get`, `dnf`, `yum`, `microdnf`).
   - **Open:** a call with fd 0 and fd 1 still on the terminal, so `_run_command` uses interactive `sudo` and the
     password prompt appears here. Suggested: `_wc_priv /usr/bin/id -u 1>&2 2>/dev/null`. The order matters:
     `1>&2` first, so fd 1 points at the terminal that stderr was on. It must not print anything except at most
     the uid.
   - **Confirm:** `out=$(_wc_priv /usr/bin/id -u </dev/null 2>/dev/null)`. Both fds are off the terminal, so this
     runs as `sudo -n` and needs a real ticket. Return 0 only if the call succeeds and `out` is exactly `0`.
     Otherwise keep the existing message ("cached admin ticket not usable from a pipe…") and return 10. A failed
     open also returns 10, as today.
2. `_wc_revoke`'s headless branch (`bin/k3dm-web-console-sshd:375`) uses the same confirm call as its test,
   ideally through a small shared helper in `web_console_common.sh` (for example `_wc_priv_ticket`). The message
   and return code 10 stay the same.
3. Fixture shim (`scripts/tests/bin/web_console_sshd.bats`, the python shim near line 440): `id` with `-u` prints
   `0`, so fixture-mode `_wc_priv_open` still passes.
4. Update the existing `[M3] tty opens a ticket…` test (line ~932). It pins the calls `/usr/bin/true` and
   `-n /usr/bin/true`, and its stub fails every `sudo -n`, which is the opposite of the real host. Re-pin it to the
   new calls.

## Contract readers

`_wc_priv_open` is internal to web-console, and its return contract (0 / 10) does not change.

- **Writer:** `scripts/lib/web_console_common.sh:47` (`_wc_priv_open`) — calls change from `/usr/bin/true` to the
  open and confirm calls.
- **Readers:**
  - `bin/k3dm-web-console-sshd:374` (revoke, terminal branch), `:707` and `:722` (install and uninstall): unchanged,
    still `|| return 10`.
  - `bin/k3dm-web-console-sshd:375` (revoke, headless branch): its check changes, per item 2.
  - `scripts/tests/bin/web_console_sshd.bats:117`, `:935` (heredoc caller), `:1424`, `:1426`: the no-terminal and
    fixture paths are unchanged; the `[M3]` test at about line 932 is re-pinned, per item 4.
- **Not changed:** the `NOPASSWD: /usr/bin/true` rule (`bin/install-sudoers.sh:39`) stays. Headless k3d probes
  depend on it (`docs/bugs/2026-11-03-vault-ca-trust-target-and-headless-sudoers-probe.md`).

## Acceptance

```yaml
must:
  - id: M1
    text: On a terminal, _wc_priv_open returns 0 only after a _wc_priv call that runs as sudo -n (stdin from /dev/null, stdout captured), uses a command bin/install-sudoers.sh does not grant NOPASSWD, succeeds, and prints exactly 0.
  - id: M2
    text: On a terminal with no ticket, under a sudoers that grants NOPASSWD /usr/bin/true, _wc_priv_open makes an interactive (non -n) sudo call for a non-NOPASSWD command before it returns, so the password prompt comes from _wc_priv_open.
  - id: M3
    text: Headless revoke (stdin or stdout not a terminal) continues past its ticket check only when the same sudo -n confirm call succeeds and prints 0; otherwise it exits 10 with "revoke needs an open sudo ticket or a terminal" and makes no other privileged call.
  - id: M4
    text: Every privileged call still goes through _wc_priv / _run_command; there is no direct sudo in web_console_common.sh or bin/k3dm-web-console-sshd.
  - id: M5
    text: Unchanged paths stay unchanged - no terminal and no fixture returns 10 with no sudo call; fixture mode appends priv_open to calls.log and passes.
must_not:
  - id: N1
    text: _wc_priv_open returns 0 when no sudo ticket exists and the sudoers grants NOPASSWD /usr/bin/true.
  - id: N2
    text: Headless revoke passes its ticket check when no ticket exists and the sudoers grants NOPASSWD /usr/bin/true.
evidence:
  - id: E1
    proves: [M1, M2, N1]
    kind: offline
    intent: On a Mac set up with make sudoers, the web-console install asks for your password at the start and only continues once sudo really works from a pipe, instead of skipping the prompt and failing halfway.
    check: BATS under wc_pty_run with a PATH sudo stub modelled on the m4-air capture (2026-11-20, sudo 1.9.17p2, sudo -n -l shows NOPASSWD /usr/bin/true; sudo -n /usr/bin/true rc 0 with no ticket; sudo -n -v "a password is required") - sudo -n /usr/bin/true exits 0 always; any other sudo -n exits 1 with "sudo: a password is required" unless a scratch ticket file exists; a non -n call creates the ticket file and runs the command, printing 0 for /usr/bin/id -u. Fixture asserts first that the stub is the sudo on PATH and the ticket file starts absent. No ticket -> rc 0, the call log shows a non -n call for a non-NOPASSWD command before the -n confirm. Positive control - a stub whose non -n call fails (wrong password) -> rc 10. Pre-fix red - the same test against 8faebd87's _wc_priv_open returns 0 with no non -n call for a non-NOPASSWD command, so the test fails.
  - id: E2
    proves: [M3, N2]
    kind: offline
    intent: A revoke run from a script with no open sudo session stops at once with a clear message, instead of starting and failing partway through.
    check: BATS - headless revoke (stdin /dev/null) with the E1 stub and no ticket file exits 10 with the message and calls.log/stub log shows no privileged call after the check; positive control - with the ticket file present the check passes and revoke proceeds into the fixture. Pre-fix red - on 8faebd87 the no-ticket case passes the check.
  - id: E3
    proves: [M4, M5]
    kind: offline
    intent: The fix changes only the ticket check; the rest of the web-console safety checks still pass.
    check: make test-bin-file or the full scripts/tests/bin/web_console_sshd.bats green, including the existing no-direct-sudo static test, the no-terminal test (line ~117) and fixture-mode install/revoke/uninstall tests; shellcheck clean on the touched files.
  - id: E4
    proves: [M1, M2, N1]
    kind: live
    intent: On your M4, after sudo -k, make install-web-console-sshd with a throwaway CA asks for your password once at the start and finishes, with no "a password is required" errors.
    check: operator on m4-air in tmux, Claude reading the pane - sudo -k, then the part A E11 install with a throwaway CA; one prompt at the start, install rc 0, make web-console-sshd-check rc 0; then the part A E11-E14 rerun and uninstall PURGE=1.
interface:
  - _wc_priv_open -> 0 | 10 (unchanged)
  - k3dm-web-console-sshd revoke headless -> exit 10 + "revoke needs an open sudo ticket or a terminal" (unchanged text)
```

## Files

- `scripts/lib/web_console_common.sh` — `_wc_priv_open`, plus the optional `_wc_priv_ticket` helper.
- `bin/k3dm-web-console-sshd` — the headless check in `_wc_revoke` only.
- `scripts/tests/bin/web_console_sshd.bats` — the shim's `id -u`, the re-pinned `[M3]` test, and new E1/E2 tests.
- `CHANGELOG.md` — one Fixed line under the v1.45.0 section.

## Worker definition of done

- The E1 and E2 tests exist and pass, and each was shown red against 8faebd87's `_wc_priv_open` and revoke check:
  record the command and the failing output in the commit message or the dispatch report.
- `scripts/tests/bin/web_console_sshd.bats` passes in full, and `shellcheck` is clean on the touched files.
- One commit on the dispatch branch, pushed. Report the SHA.

## What not to do

- Do not edit `scripts/lib/foundation/` (the lib-foundation subtree) or `bin/install-sudoers.sh`.
- Do not add a sudoers rule, call `sudo` directly, or use `sudo -v` outside `_run_command`.
- Do not change return codes, messages, or the no-terminal and fixture branches.
- Do not touch the install, revoke or uninstall steps after the ticket check.

Out of scope, a follow-up row for `docs/ideas.md`: lib-foundation's own `sudo -n true` probes
(`scripts/lib/foundation/scripts/lib/system.sh`, `_run_command_resolve_sudo`, the `require_sudo` path) are defeated by
the same rule. They answer "may run passwordless" rather than "is a ticket open"; whether any caller needs the latter
has to be audited upstream first.
