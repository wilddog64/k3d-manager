# Bug: `_run_command` sudo runs the first matching name in the user's PATH, so NOPASSWD rules for `/usr/bin/*` never match

**Status:** FIXED
**Filed:** 2026-10-05
**Branch:** `fix/sudo-system-path-resolution`
**Severity:** Medium. Automated runs stop at a `Password:` prompt, and root runs a binary from a
user-writable directory.
**Files:** `scripts/lib/system.sh`, `scripts/tests/lib/system.bats`, `docs/api/functions.md`,
`CHANGE.md`

## Symptom

In k3d-manager, `make up` (Step 10g) and `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger` print
`Password:` mid-run. The sudoers drop-in `/etc/sudoers.d/k3d-manager` is installed and contains:

```
%admin ALL=(root) NOPASSWD: /usr/bin/install -m 644 * /Library/LaunchDaemons/com.k3d-manager.*.plist
```

The caller is `_run_command --interactive-sudo --quiet --soft -- install -m 644 <src> <dest>`.

## Root cause

`_run_command_resolve_sudo` builds runners such as `(sudo "${sudo_flags[@]}" "$prog")` with the bare
name the caller passed. sudo resolves a bare name through the caller's PATH. The operator's PATH puts
GNU coreutils first. The operator ran
`sudo -k; sudo -n -l install -m 644 /tmp/x /Library/LaunchDaemons/com.k3d-manager.x.plist`:

```
/opt/homebrew/opt/coreutils/libexec/gnubin/install -m 644 /tmp/x /Library/LaunchDaemons/com.k3d-manager.x.plist
rc=0
```

The NOPASSWD rule names `/usr/bin/install`, so it never matches. Only the general admin rule
matches, and that rule requires a password. (`sudo -l` returns 0 for any matching rule, including
ones that need a password.)

This is also a privilege hazard. Root executes a binary from a Homebrew directory the user can write
to.

The no-TTY guard (`interactive_sudo == 1` with no TTY adds `-n`) is already present in this copy and
is not part of the defect. A regression test for it is added below because no test covers it today.

## Fix spec

### File 1 — `scripts/lib/system.sh` (`_run_command_resolve_sudo`)

Replace:

```bash
  local -a sudo_flags=()
  if (( interactive_sudo == 0 )); then
    sudo_flags=(-n)
  elif (( interactive_sudo == 1 )) && [[ ! -t 0 || ! -t 1 ]]; then
    sudo_flags=(-n)
  fi
```

with:

```bash
  local -a sudo_flags=()
  if (( interactive_sudo == 0 )); then
    sudo_flags=(-n)
  elif (( interactive_sudo == 1 )) && [[ ! -t 0 || ! -t 1 ]]; then
    sudo_flags=(-n)
  fi

  local sudo_prog="$prog"
  if [[ "$prog" != */* ]]; then
    local _sys_dir
    for _sys_dir in /usr/bin /bin /usr/sbin /sbin; do
      if [[ -x "${_sys_dir}/${prog}" ]]; then
        sudo_prog="${_sys_dir}/${prog}"
        break
      fi
    done
  fi
```

Then, in the rest of the same function, change `"$prog"` to `"$sudo_prog"` **only where it follows
`sudo`**. There are exactly 9 such occurrences:

- `_RCRS_RUNNER=(sudo "${sudo_flags[@]}" "$prog")` — 4 occurrences
- `_RCRS_RUNNER=(sudo -n "$prog")` — 3 occurrences
- `elif (( interactive_sudo )) && sudo "${sudo_flags[@]}" "$prog" "${probe_args[@]}" >/dev/null 2>&1; then`
- `elif sudo -n "$prog" "${probe_args[@]}" >/dev/null 2>&1; then`

Leave the non-sudo uses unchanged: `_RCRS_RUNNER=("$prog")` and
`if "$prog" "${probe_args[@]}" >/dev/null 2>&1; then`.

After the edit, inside `_run_command_resolve_sudo`:
- no line contains both `sudo` and `"$prog"` (the two plain lines above contain `"$prog"` only)
- `"$sudo_prog"` appears exactly 9 times

Update the function's header comment: add one line saying a bare program name is run from
`/usr/bin`, `/bin`, `/usr/sbin` or `/sbin` when it exists there, so sudoers rules that name those
paths match.

No other function changes.

### File 2 — `scripts/tests/lib/system.bats`

Add four tests after the existing `_run_command_resolve_sudo: probe succeeds as user → plain runner`
test. Call the resolver directly (not via `run`), so `_RCRS_RUNNER` survives, and redirect stdin from
`/dev/null` so there is no TTY. None of these argument combinations invokes `sudo`, so no stub is
needed; do not run real sudo.

1. **`_run_command_resolve_sudo: sudo runner uses the system binary, not a PATH shadow`**
   - Create `${BATS_TEST_TMPDIR}/shadow/install` (executable, `#!/bin/sh` + `exit 0`), save `PATH`,
     and prepend that dir to `PATH`.
   - `_run_command_resolve_sudo install 1 0 1 </dev/null`
   - Assert `${_RCRS_RUNNER[0]}` = `sudo`, `${_RCRS_RUNNER[1]}` = `-n`,
     `${_RCRS_RUNNER[2]}` = `/usr/bin/install`, and `${#_RCRS_RUNNER[@]}` -eq 3.
2. **`_run_command_resolve_sudo: interactive sudo without a TTY adds -n`**
   - `_run_command_resolve_sudo echo 1 0 1 </dev/null`
   - Assert `${_RCRS_RUNNER[0]}` = `sudo` and `${_RCRS_RUNNER[1]}` = `-n`.
3. **`_run_command_resolve_sudo: plain runner keeps the bare name`**
   - `_run_command_resolve_sudo install 0 0 0`
   - Assert `${_RCRS_RUNNER[0]}` = `install` and `${#_RCRS_RUNNER[@]}` -eq 1.
4. **`_run_command_resolve_sudo: absolute program path is left unchanged`**
   - `_run_command_resolve_sudo /opt/custom/tool 1 0 1 </dev/null`
   - Assert `${_RCRS_RUNNER[${#_RCRS_RUNNER[@]}-1]}` = `/opt/custom/tool` (not `[-1]`; bash 3.2).

Restore `PATH` and `unset _RCRS_RUNNER` at the end of each test.

### File 3 — `docs/api/functions.md`

Extend the `_run_command_resolve_sudo` row (line 18) with: "A bare program name is run under sudo
from `/usr/bin`, `/bin`, `/usr/sbin` or `/sbin` when it exists there, so a PATH entry such as GNU
coreutils cannot shadow the binary a sudoers rule names."

### File 4 — `CHANGE.md`

Under `## [Unreleased]` → `### Fixed`, add a prose entry: `_run_command` passed bare program names
to sudo, which resolved them through the caller's PATH. With GNU coreutils first in PATH, `install`
ran as root from a user-writable Homebrew directory and the `/usr/bin/install` NOPASSWD rule never
matched, so automated runs stopped at a password prompt. The resolver now runs a bare name from
`/usr/bin`, `/bin`, `/usr/sbin` or `/sbin` when it exists there. Reference this spec.

Flip this file's **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: test 1 is RED against the `HEAD` copy of `scripts/lib/system.sh`; paste the
      output. Tests 2–4 pass pre-fix (the TTY guard already exists); say so.
- [ ] Mutation A: delete the `elif (( interactive_sudo == 1 )) && [[ ! -t 0 || ! -t 1 ]]` branch
      (both lines); test 2 goes red.
- [ ] Mutation B: delete the `for _sys_dir` loop; test 1 goes red.
- [ ] Restore after each mutation from a `$TMPDIR` snapshot and prove the restore with `cmp`.
- [ ] `make bats` green; paste the pass/fail counts.
- [ ] `shellcheck scripts/lib/system.sh` shows no new findings vs `HEAD`.
- [ ] Changes left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT run real `sudo`, `install` into `/Library`, `launchctl`, `ifconfig`, or anything live.
- Do NOT change the `sudo -n true` probes in the `require_sudo` / `prefer_sudo` paths (follow-up).
- Do NOT edit any file outside the four listed. Do NOT touch other unstaged changes.
- No commit, push, PR, merge, or `--no-verify`. Do NOT switch branches or touch `main`.

## Follow-ups (not in this spec)

- The `sudo -n true` probe in the `--prefer-sudo` / `--require-sudo` paths fails under command-scoped
  NOPASSWD rules, so those paths fall back to running as the user.
- k3d-manager: `bin/*` source a stale local `scripts/lib/system.sh` instead of this copy; after the
  subtree pull, make them load the foundation resolver
  (k3d-manager `docs/bugs/2026-10-05-sudo-prompt-stale-system-sh-gnubin-install.md`).
