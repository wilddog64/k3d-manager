# Bug: `make up` and `refresh-edge` prompt for a sudo password although NOPASSWD rules cover every call

**Status:** OPEN — RETARGETED 2026-10-05. Do not implement the File 1 fix below in the local
`scripts/lib/system.sh`. Defect 1 (PATH resolution) is fixed upstream: lib-foundation
`docs/bugs/2026-10-05-sudo-resolves-bare-name-through-user-path.md` (branch
`fix/sudo-system-path-resolution`). After that merges and is subtree-pulled, this doc is rewritten
to fix defect 2 by making `bin/*` load the foundation resolver instead of the stale local copy.
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Medium. An automated run stops at a `Password:` prompt. Unattended (watcher, headless)
runs cannot answer it.
**Files:** `scripts/lib/system.sh`, `scripts/tests/lib/system.bats`, `CHANGELOG.md`

## Symptom

From the operator's `make up` pane on 2026-10-05:

```
INFO: [acg-up] Step 10g/14 — Installing frontend HTTP listener (...)
Password:
Boot-out failed: 5: Input/output error
WARN: [acg-up] existing frontend browser HTTP listener was not loaded; continuing
```

And from `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger`:

```
INFO: [k3s-hostinger] launchd com.k3d-manager.keycloak-browser-http: restarted
Password:
INFO: [k3s-hostinger] launchd com.k3d-manager.frontend-browser-http: restarted
```

`/etc/sudoers.d/k3d-manager` (from `make sudoers`) is installed and contains
`%admin ALL=(root) NOPASSWD: /usr/bin/install -m 644 * /Library/LaunchDaemons/com.k3d-manager.*.plist`.

## Root cause — two defects that combine

### 1. sudo runs whatever `install` comes first in the user's PATH

The callers pass a bare name (`_run_command --interactive-sudo ... -- install -m 644 ...`). sudo
resolves a bare name through the caller's PATH. The operator's PATH puts GNU coreutils first. The
operator ran `sudo -k; sudo -n -l install -m 644 /tmp/x /Library/LaunchDaemons/com.k3d-manager.x.plist`:

```
/opt/homebrew/opt/coreutils/libexec/gnubin/install -m 644 /tmp/x /Library/LaunchDaemons/com.k3d-manager.x.plist
rc=0
```

The NOPASSWD rule names `/usr/bin/install`, so it never matches. Only the general admin rule
matches, and that rule requires a password. (`sudo -l` reports rc=0 for any matching rule, including
ones that need a password.)

This is also a privilege hazard. Root executes a binary from a Homebrew directory the user can write
to.

### 2. `bin/*` load a stale `scripts/lib/system.sh` without the no-TTY guard

`bin/cluster-up:30` and 25 other `bin/` scripts `source "${REPO_ROOT}/scripts/lib/system.sh"`. The
dispatcher loads `scripts/lib/foundation/scripts/lib/system.sh` instead. The two copies have drifted.
The foundation copy has this guard in `_run_command_resolve_sudo` and the local copy does not:

```bash
  elif (( interactive_sudo == 1 )) && [[ ! -t 0 || ! -t 1 ]]; then
    sudo_flags=(-n)
```

Without it, `--interactive-sudo` calls whose output is redirected to a log still run plain `sudo`.
sudo writes its prompt straight to `/dev/tty`, so the redirect does not hide it. Step 10g's
frontend `launchctl bootout` / `install` / `bootstrap` calls are redirected this way. Together with
defect 1 they produced the Step 10g prompt.

Verified as not the cause: `sudo -k; sudo /sbin/ifconfig lo0 alias 127.0.0.3` returns rc=0 with no
prompt, so the ifconfig rule matches.

## Fix spec

### File 1 — `scripts/lib/system.sh` (`_run_command_resolve_sudo`)

Replace:

```bash
  local -a sudo_flags=()
  if (( interactive_sudo == 0 )); then
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
- `grep -c 'sudo[^|]*"\$prog"'` over the function body = 0
- `grep -c '"\$sudo_prog"'` = 9

No other function changes. Do NOT edit `scripts/lib/foundation/` — that is a subtree. The upstream
change is a separate lib-foundation spec.

### File 2 — `scripts/tests/lib/system.bats`

Add four tests. Call the resolver directly (not via `run`), so `_RCRS_RUNNER` survives, and redirect
stdin from `/dev/null` so there is no TTY.

1. **"_run_command_resolve_sudo: sudo runner uses the system binary, not a PATH shadow"**
   - Create `${BATS_TEST_TMPDIR}/shadow/install` (an executable `#!/bin/sh` stub), and prepend that
     dir to `PATH`.
   - `_run_command_resolve_sudo install 1 0 1 </dev/null`
   - Assert `${_RCRS_RUNNER[0]}` = `sudo`, `${_RCRS_RUNNER[1]}` = `-n`,
     `${_RCRS_RUNNER[2]}` = `/usr/bin/install`, and the array length is 3.
2. **"_run_command_resolve_sudo: interactive sudo without a TTY adds -n"**
   - `_run_command_resolve_sudo echo 1 0 1 </dev/null`
   - Assert `${_RCRS_RUNNER[0]}` = `sudo` and `${_RCRS_RUNNER[1]}` = `-n`.
3. **"_run_command_resolve_sudo: plain runner keeps the bare name"**
   - `_run_command_resolve_sudo install 0 0 0`
   - Assert the array is exactly (`install`).
4. **"_run_command_resolve_sudo: absolute program path is left unchanged"**
   - `_run_command_resolve_sudo /opt/custom/tool 1 0 1 </dev/null`
   - Assert the last element is `/opt/custom/tool`.

`unset _RCRS_RUNNER` (and restore `PATH`) at the end of each test.

### File 3 — `CHANGELOG.md`

Under `## [Unreleased]` → `### Fixed`, add a prose entry covering both defects:

- `bin/*` scripts load `scripts/lib/system.sh`, which lacked the no-TTY guard, so redirected
  `--interactive-sudo` calls ran plain `sudo` and could prompt on the terminal mid-run.
- sudo resolved bare names through the user's PATH, so GNU coreutils `install` ran as root and the
  `/usr/bin/install` NOPASSWD rule never matched.
- The resolver now adds `-n` when there is no TTY and runs sudo commands from `/usr/bin`, `/bin`,
  `/usr/sbin` or `/sbin` when a bare name is found there.

Flip this file's **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: tests 1 and 2 are RED against the `HEAD` copy of `scripts/lib/system.sh`; paste
      the output. (Tests 3 and 4 may pass pre-fix; say so.)
- [ ] Mutation A: delete the two `elif ... ! -t 0 || ! -t 1` lines; test 2 goes red.
- [ ] Mutation B: delete the `for _sys_dir` loop; test 1 goes red.
- [ ] Restore after each mutation from a `$TMPDIR` snapshot and prove the restore with `cmp`.
- [ ] `bats scripts/tests/lib/system.bats scripts/tests/lib/run_command.bats` green; paste the counts.
- [ ] `shellcheck scripts/lib/system.sh` shows no new findings vs `HEAD`.
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT run `make up`, any `bin/` script, real `sudo`, `launchctl`, `install` into `/Library`,
  `ifconfig`, or anything live.
- Do NOT edit `scripts/lib/foundation/`, `/etc/sudoers.d`, `bin/install-sudoers.sh`, or any caller.
- Do NOT merge or reconcile the two `system.sh` copies; that is a separate follow-up.
- Do NOT touch files outside those listed. Do NOT touch other unstaged changes. No commit, push,
  PR or `--no-verify`.

## Follow-ups (not in this spec)

- lib-foundation: port the system-path resolution upstream (the no-TTY guard is already there).
- `scripts/lib/system.sh` and the foundation copy have drifted both ways (113 / 359 lines). Make
  `bin/*` load one copy.
- lib-foundation: the `sudo -n true` probe in the `--prefer-sudo` path never passes with
  command-scoped NOPASSWD rules.
