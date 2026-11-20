# Bug: `_wc_priv_open` reports a sudo ticket that does not exist on Macs with k3d-manager's sudoers

**Status:** OPEN — captured 2026-11-20 during the web-console part A live check (E11 prerequisite P3); fix spec below, revised after Fable review 2026-11-20
**Priority:** P2 (Claude-owned per the P2/P3 split; install fails partway on a Mac with k3d-manager's sudoers, workaround: `sudo -v` first)
**Introduced by:** 8faebd87 (web-console part A)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (both)
**Waiting on:** dispatch — since 2026-11-20
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

Revised 2026-11-20 after the Fable spec review (verdict NEEDS FIXES: 2 blockers, 5 should-fix; all were checked
against the code and adopted).

1. **`_wc_priv_open`** (`scripts/lib/web_console_common.sh:47`).
   - Keep its first branch (`:48-53`) unchanged: in fixture mode it appends `priv_open` to `calls.log`; with no
     terminal it prints the existing message and returns 10 without calling sudo.
   - Replace the two `/usr/bin/true` lines (`:54-58`) with exactly these two lines:

         _wc_priv /bin/sleep 0 2>/dev/null || return 10
         _wc_priv_ticket || {

     The `|| {` block keeps the existing message and `return 10`.
   - **Open call.** `/bin/sleep 0` is silent and not granted NOPASSWD by `bin/install-sudoers.sh`. It is already in
     the fixture tool list (`:38`). fd 0 and fd 1 are untouched, so `_run_command` runs interactive `sudo`, and the
     password prompt appears here.
2. **New helper `_wc_priv_ticket`** in `web_console_common.sh`, right after `_wc_priv_open`. It is the
   confirm call. Its body is one line, shaped so it passes the static test at `web_console_sshd.bats:913-917`,
   which requires `||`, `&&` or `; then` and a literal `2>/dev/null` on every `_wc_priv /` line:

       local out; out=$(_wc_priv /usr/bin/id -u </dev/null 2>/dev/null) && [[ "$out" = 0 ]] || return 10

   Both fds are off the terminal, so this runs as `sudo -n` and succeeds only with a real ticket. Output of exactly
   `0` proves the command ran as root. `--quiet` hides only messages, `--soft` returns the real rc, and sudo's own
   errors go to stderr, so nothing but the uid reaches `out`.
3. **`_wc_revoke`'s headless branch** (`bin/k3dm-web-console-sshd:375`) becomes
   `elif ! _wc_priv_ticket; then`. The message and return code 10 stay the same.
4. **Fixture shim** (`scripts/tests/bin/web_console_sshd.bats`).
   - Line 356 (`id`): with args `['-u']`, print `0`, or exit 1 when `get('ticket')=='closed'`. `-un` and the passwd
     form stay as they are.
   - Line 474: the `ticket=closed` knob currently fails only `true`. Move it so that it fails `id -u` as above, and
     drop the `true` case. The headless-revoke test at `:987-989` must stay green unchanged.
5. **Existing test `[M3] tty opens a ticket and confirms it works in a pipe`** (`:925`). It models
   `timestamp_timeout=0`: the open call succeeds and every `-n` call fails, which is a legitimate case. Keep the stub
   and the rc 10 and message assertions. Change only the two pinned strings at `:945-946`, to `/bin/sleep 0` and
   `-n /usr/bin/id -u`.

## Contract readers

`_wc_priv_open` is internal to web-console, and its return contract (0 / 10) does not change.

- **Writers:**
  - `scripts/lib/web_console_common.sh:54-58` (`_wc_priv_open`): the checks change.
  - New `_wc_priv_ticket` in the same file.
- **Readers:**
  - `bin/k3dm-web-console-sshd:374` (revoke, terminal branch), `:707` and `:722` (install and uninstall): unchanged,
    `|| return 10`.
  - `bin/k3dm-web-console-sshd:375` (revoke, headless branch): changes to `_wc_priv_ticket`.
  - `scripts/tests/bin/web_console_sshd.bats`:
    - `:117`, `:935` (child-script caller), `:1424`, `:1426`: unchanged paths.
    - `:925-947`: re-pinned (Fix item 5).
    - `:987-989`: depends on the `ticket=closed` knob (Fix item 4).
    - Shim `:356` and `:474`: change.
    - Static test `:908-918`: constrains the new lines (Fix item 2).
- **Not changed:** the `NOPASSWD: /usr/bin/true` rule (`bin/install-sudoers.sh:39`) stays. Headless k3d probes
  depend on it (`docs/bugs/2026-11-03-vault-ca-trust-target-and-headless-sudoers-probe.md`).

## Test design (required, from the review)

- **Stub form.** Both new tests use a `sudo()` shell function stub, as the existing test does at `:931`. A function
  wins over PATH because `_run_command` calls bare `sudo`. The stub never execs its arguments. It appends `$*` to
  a call log, then decides:
  - **NOPASSWD rule** (`/usr/bin/true`, with or without `-n`): exit 0. It never touches the ticket file. Real host:
    `sudo /usr/bin/true` opens no ticket.
  - **Any other `-n` call:** exit 1 with `sudo: a password is required` on stderr unless the ticket file exists. With
    the ticket file, `-n /usr/bin/id -u` prints `0` (or the value in `$WC_STUB_UID` when the test sets it) and exits
    0; any other `-n` call exits 0 silently.
  - **A non `-n` call for any other command:** "the password was typed". Create the ticket file and exit 0, unless
    `$WC_STUB_DENY` is set, in which case exit 1 (wrong password).
  - **Fixture assertions, first:** `type -t sudo` is `function`, and the ticket file is absent.
- **E1 harness.** A child script, as at `:926-940`: source `system.sh` and `web_console_common.sh`, define the stub,
  call `_wc_priv_open` and print its rc. Run it under `wc_pty_run`.
- **E2 harness.** Do not run `"$WC_BIN" revoke`: `_wc_main_env` resets PATH and runs `unset -f sudo`, and fixture
  mode replaces `_wc_priv` entirely.
  - Source the script with the suite's existing pattern, `source "$WC_BIN"; wc_library` (as at `:782`). `main` is
    guarded by `[[ "${BASH_SOURCE[0]}" = "$0" ]]`. Do not call `_wc_fixture_gate`, and do not set `K3DM_WC_ROOT`, so
    `_wc_priv` stays the real `_run_command` path.
  - Define the stub, and override `_wc_port_lookup`, `_wc_revoke_mark` and `_wc_stop` with sentinels that append
    their name to a log and return 0. Then run `_wc_revoke </dev/null`.
- **Tags.** Name new tests `[bug-2026-11-20] [E1] ...` and `[bug-2026-11-20] [E2] ...`, after the part A tag style.

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
    text: Every privileged call still goes through _wc_priv / _run_command; there is no direct sudo in web_console_common.sh or bin/k3dm-web-console-sshd; the commands the ticket check uses (/bin/sleep, /usr/bin/id) appear in no NOPASSWD line of bin/install-sudoers.sh.
  - id: M5
    text: Unchanged paths stay unchanged - no terminal and no fixture returns 10 with no sudo call; fixture mode appends priv_open to calls.log and passes; ticket=closed still makes fixture headless revoke exit 10.
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
    check: BATS child script under wc_pty_run with the Test design stub (modelled on the m4-air capture 2026-11-20, sudo 1.9.17p2 - sudo -n -l lists NOPASSWD /usr/bin/true; sudo /usr/bin/true and sudo -n /usr/bin/true exit 0 with no ticket and no prompt; sudo -n -v "a password is required"). Case A no ticket - rc 0, the ticket file exists afterwards (rc 0 implies ticket), and the call log has a non -n call for a non-NOPASSWD command before "-n /usr/bin/id -u". Case B (positive control) WC_STUB_DENY=1 - rc 10. Case C WC_STUB_UID=501 - rc 10 (uid must be exactly 0). Pre-fix red - with 8faebd87's _wc_priv_open (git show 8faebd87:scripts/lib/web_console_common.sh) case A returns 0 with no ticket file, so the test fails on behaviour, not on a call string.
  - id: E2
    proves: [M3, N2]
    kind: offline
    intent: A revoke run from a script with no open sudo session stops at once with a clear message, instead of starting and failing partway through.
    check: BATS per the E2 harness - no ticket file, _wc_revoke </dev/null exits 10 with the message and the sentinel log is empty; positive control - ticket file present, the check passes and the _wc_port_lookup sentinel is logged. Pre-fix red - on 8faebd87's revoke check the no-ticket case reaches the sentinels.
  - id: E3
    proves: [M4, M5]
    kind: offline
    intent: The fix changes only the ticket check; the rest of the web-console safety checks still pass.
    check: scripts/tests/bin/web_console_sshd.bats green in full, including the static test at :908-918 extended with an assertion that no NOPASSWD line of bin/install-sudoers.sh names /bin/sleep or /usr/bin/id, the no-terminal test at :117 extended to assert calls.log or the stub log is unchanged, the re-pinned [M3] test, and the ticket=closed revoke test at :987-989; shellcheck clean on the touched files.
  - id: E4
    proves: [M1, M2, N1]
    kind: live
    intent: On your M4, after sudo -k, make install-web-console-sshd with a throwaway CA asks for your password once at the start and finishes, with no "a password is required" errors.
    check: mandatory before LIVE-VERIFIED (it is the only proof that a ticket opened on the tty is usable by sudo -n with fds redirected). Operator on m4-air in tmux, Claude reading the pane - sudo -k, then the part A E11 install with a throwaway CA; one prompt at the start, install rc 0, make web-console-sshd-check rc 0; then the part A E11-E14 rerun and uninstall PURGE=1.
interface:
  - _wc_priv_open -> 0 | 10 (unchanged)
  - _wc_priv_ticket -> 0 | 10 (new, internal)
  - k3dm-web-console-sshd revoke headless -> exit 10 + "revoke needs an open sudo ticket or a terminal" (unchanged text)
```

## Files

- `scripts/lib/web_console_common.sh` — `_wc_priv_open` and the new `_wc_priv_ticket`.
- `bin/k3dm-web-console-sshd` — the headless check in `_wc_revoke` only.
- `scripts/tests/bin/web_console_sshd.bats` — shim lines 356 and 474, the re-pinned `[M3]` test, the extended static and no-terminal tests, and new E1/E2 tests.
- `CHANGELOG.md` — one line under `## [Unreleased]` → `### Fixed`.

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
