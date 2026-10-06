# Bug: `make up` and `refresh-edge` prompt for a sudo password although NOPASSWD rules cover every call

**Status:** FIXED — spec rewritten 2026-10-05 after lib-foundation PR #63 (`8b97c0b`) was
subtree-pulled (`c848d37c`).
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Medium. An automated run stops at a `Password:` prompt. Unattended (watcher, headless)
runs cannot answer it.
**Files:** `scripts/lib/system.sh`, `scripts/tests/lib/system_shim.bats` (new),
`scripts/tests/lib/run_command.bats`, `scripts/tests/lib/system.bats`,
`scripts/tests/lib/ensure_copilot_cli.bats`, `CLAUDE.md`, `docs/guides/plugin-development.md`,
`CHANGELOG.md`

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

1. **sudo ran whatever `install` came first in the user's PATH.** GNU coreutils
   (`/opt/homebrew/opt/coreutils/libexec/gnubin`) shadows `/usr/bin/install`, so the
   `/usr/bin/install` NOPASSWD rule never matched. **Fixed upstream** in lib-foundation
   (`docs/bugs/2026-10-05-sudo-resolves-bare-name-through-user-path.md`, PR #63) and now in
   `scripts/lib/foundation/scripts/lib/system.sh`.
2. **`bin/*` never load that fix.** 23 `bin/` scripts, `Makefile:1148` and 25 BATS files
   `source scripts/lib/system.sh` — a 1847-line local copy that predates both the PATH fix and the
   no-TTY guard (`interactive_sudo == 1` with no TTY adds `-n`). The dispatcher
   (`scripts/k3d-manager:70-74`) loads the foundation copy instead. So `make up` (via
   `bin/cluster-up:30`) runs the stale resolver, and redirected `--interactive-sudo` calls run a
   bare `sudo install`, which prompts on `/dev/tty`.

### What the local copy holds (measured 2026-10-05 against foundation `8b97c0b`)

- 91 functions; 88 also exist in the foundation copy. Only 3 bodies differ:
  `_run_command_resolve_sudo` (the defect), `_copilot_auth_check` and `_copilot_review`.
  No `bin/*` script reaches the two Copilot helpers, and `scripts/plugins/copilot.sh` enforces
  `K3DM_ENABLE_AI` itself. The dispatcher already runs the foundation versions of all three.
- 3 functions exist only locally: `_kubeconform_sha256`, `_install_kubeconform_from_release`,
  `_ensure_kubeconform`, plus `KUBECONFORM_VERSION="0.7.0"` (lines 1635–1738). `Makefile:1148` and
  `scripts/tests/lib/ensure_kubeconform.bats` use them.
- Top-level code is identical in both copies except that each defaults `SCRIPT_DIR` relative to its
  own path. Pointing `bin/*` straight at the foundation file would set `SCRIPT_DIR` to
  `scripts/lib/foundation/scripts` and break `${SCRIPT_DIR}/plugins`, `/etc` lookups.

## Fix — make `scripts/lib/system.sh` a shim over the foundation copy

One file change fixes all 23 `bin/` callers, the Makefile and the tests, with no edits to `bin/`.
A prototype was run on a scratch worktree: the 25 affected BATS files go 305/305 green with the
test updates below, shellcheck is clean, and both mutations below turn the new tests red.

### File 1 — `scripts/lib/system.sh`

Replace lines 1–1634 (everything above `KUBECONFORM_VERSION="0.7.0"`) with exactly:

```bash
# shellcheck shell=bash
# k3d-manager's system library is the lib-foundation subtree copy. This file loads it so that
# bin/* scripts, the Makefile and tests that source scripts/lib/system.sh get the same
# _run_command as the dispatcher. Only k3d-manager-specific helpers are defined here; change
# shared helpers upstream in lib-foundation.
_k3dm_system_lib_dir="${BASH_SOURCE[0]%/*}"
if [[ "$_k3dm_system_lib_dir" == "${BASH_SOURCE[0]}" ]]; then
    _k3dm_system_lib_dir="."
fi
_k3dm_system_lib_dir="$(cd -P "$_k3dm_system_lib_dir" >/dev/null 2>&1 && pwd)"

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="${_k3dm_system_lib_dir%/*}"
fi

# shellcheck source=scripts/lib/foundation/scripts/lib/system.sh
source "${_k3dm_system_lib_dir}/foundation/scripts/lib/system.sh"
unset _k3dm_system_lib_dir

```

Keep lines 1635–1738 (`KUBECONFORM_VERSION="0.7.0"` through the closing `}` of
`_ensure_kubeconform`) byte-for-byte. Delete lines 1739–1847 (two blank lines, then `_ensure_cargo` to end of file; every
function there is defined in the foundation copy).

Why each line is the way it is:
- `${BASH_SOURCE[0]%/*}` and `cd -P`/`pwd` are builtins. `shopping_cart.bats` sources this file
  with `PATH=/dev/null`; a `$(dirname …)` here made two of its tests fail in the prototype.
- `SCRIPT_DIR` is set before the foundation file is sourced, so its own default is skipped and
  `${SCRIPT_DIR}/lib/agent_rigor.sh` still resolves to k3d-manager's copy, as today.
- No fallback to a local copy if the foundation file is missing. Falling back is what let this
  copy go stale.

### File 2 — `scripts/tests/lib/system_shim.bats` (new)

```bash
#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  REPO_ROOT="$(cd -P "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  LOCAL_LIB="${REPO_ROOT}/scripts/lib/system.sh"
  FOUNDATION_LIB="${REPO_ROOT}/scripts/lib/foundation/scripts/lib/system.sh"
}

@test "system.sh shim: _run_command_resolve_sudo is the lib-foundation definition" {
  run bash -c 'source "$1" >/dev/null 2>&1; declare -f _run_command_resolve_sudo' _ "$LOCAL_LIB"
  [ "$status" -eq 0 ]
  local_def="$output"
  run bash -c 'source "$1" >/dev/null 2>&1; declare -f _run_command_resolve_sudo' _ "$FOUNDATION_LIB"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$local_def" = "$output" ]
}

@test "system.sh shim: no-TTY interactive sudo resolves to sudo -n and the system binary" {
  run bash -c 'source "$1" >/dev/null 2>&1; _run_command_resolve_sudo install 1 0 1 </dev/null; printf "%s|" "${_RCRS_RUNNER[@]}"' _ "$LOCAL_LIB"
  [ "$status" -eq 0 ]
  [ "$output" = "sudo|-n|/usr/bin/install|" ]
}

@test "system.sh shim: defines only the k3d-manager kubeconform helpers itself" {
  run bash -c 'grep -oE "^(function[[:space:]]+)?_?[A-Za-z0-9_]+[[:space:]]*\(\)" "$1" | sed -E "s/^function[[:space:]]+//; s/[[:space:]]*\(\)//" | sort | tr "\n" " "' _ "$LOCAL_LIB"
  [ "$status" -eq 0 ]
  [ "$output" = "_ensure_kubeconform _install_kubeconform_from_release _kubeconform_sha256 " ]
}

@test "system.sh shim: SCRIPT_DIR defaults to the k3d-manager scripts dir" {
  run bash -c 'unset SCRIPT_DIR; source "$1" >/dev/null 2>&1; printf "%s" "$SCRIPT_DIR"' _ "$LOCAL_LIB"
  [ "$status" -eq 0 ]
  [ "$output" = "${REPO_ROOT}/scripts" ]
}

@test "system.sh shim: loads with no external commands on PATH" {
  run bash -c 'PATH=/dev/null; source "$1" >/dev/null 2>&1; declare -F _run_command >/dev/null && declare -F _ensure_kubeconform >/dev/null && [ "$KUBECONFORM_VERSION" = "0.7.0" ]' _ "$LOCAL_LIB"
  [ "$status" -eq 0 ]
}
```

### File 3 — `scripts/tests/lib/run_command.bats`

These tests asserted the stale behavior (bare program name; no `-n` without a TTY). BATS has no
TTY, so under the fixed resolver they get `-n` and an absolute path. The `-n` stub returning 1 made
the interactive tests fail outright.

- In `--prefer-sudo uses sudo when available`, replace
  `  [ "${log[1]}" = "sudo -n echo hi" ]` with
  `  [[ "${log[1]}" == "sudo -n /"*"/echo hi" ]]`.
  (`echo` is `/bin/echo` on macOS and `/usr/bin/echo` on Linux; do not pin the directory.)
- Replace the test `--interactive-sudo runs without -n flag` with:

```bash
@test "--interactive-sudo without a TTY passes -n and the system binary" {
  sudo() {
    echo "sudo $*" >> "$RUN_LOG"
    [[ "$1" == "-n" ]] && shift
    "$@"
  }
  export -f sudo
  run _run_command --interactive-sudo -- echo hi </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" = "hi" ]]
  read_lines "$RUN_LOG" log
  [[ "${log[0]}" == "sudo -n /"*"/echo hi" ]]
}
```

- Replace the test `--require-sudo --interactive-sudo runs without -n flag` with the same body,
  titled `--require-sudo --interactive-sudo without a TTY passes -n and the system binary`, running
  `run _run_command --require-sudo --interactive-sudo -- echo hi </dev/null`.

Leave every other test in the file unchanged.

### File 4 — `scripts/tests/lib/system.bats`

In `_run_command: --interactive-sudo flag is accepted without error`, replace
`  function sudo() { "$@"; }` with
`  function sudo() { [[ "$1" == "-n" ]] && shift; "$@"; }`.

### File 5 — `scripts/tests/lib/ensure_copilot_cli.bats`

`fails when authentication is invalid and AI gated` tested the local `_copilot_auth_check`
(`copilot auth status`, `K3DM_ENABLE_AI` message). The dispatcher already runs the foundation
version, which checks the token env vars, then `~/.config/github-copilot/apps.json`, then
`gh auth status`. Replace the whole test with:

```bash
@test "fails when copilot is not authenticated" {
  export_stubs

  unset COPILOT_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  _command_exist() {
    [[ "$1" == copilot ]]
  }
  _run_command() {
    local payload="$*"
    if [[ "$payload" == *"gh auth status"* ]]; then
      return 1
    fi
    printf '%s\n' "$payload" >> "$RUN_LOG"
    return 0
  }
  export -f _command_exist _run_command

  run _ensure_copilot_cli
  [ "$status" -ne 0 ]
  [[ "$output" == *"Copilot CLI is not authenticated"* ]]
}
```

### File 6 — `CLAUDE.md` and `docs/guides/plugin-development.md`

Both say to register sensitive flags in `_args_have_sensitive_flag` in `scripts/lib/system.sh`.
That function now lives only in lib-foundation.
- `CLAUDE.md:133`: replace the line with
  `- New sensitive CLI flags must be registered in `_args_have_sensitive_flag` in lib-foundation's `scripts/lib/system.sh` (change it upstream, then subtree-pull; `scripts/lib/system.sh` here only loads it).`
- `docs/guides/plugin-development.md:70`: replace the line with
  `- Sensitive CLI flags: register in `_args_have_sensitive_flag` in lib-foundation's `scripts/lib/system.sh` (upstream, then subtree-pull; the local `scripts/lib/system.sh` only loads it)`

### File 7 — `CHANGELOG.md`

Under `## [Unreleased]` → the first `### Fixed`, add a prose entry: `bin/*` scripts, the Makefile
and the tests sourced `scripts/lib/system.sh`, a stale local copy of lib-foundation's system
library, while the dispatcher loaded the subtree copy. The stale `_run_command` lacked the no-TTY
`-n` guard and lib-foundation's system-path fix, so `make up` Step 10g and `refresh-edge` ran
GNU coreutils `install` under sudo and stopped at a `Password:` prompt. `scripts/lib/system.sh` is
now a shim that loads the subtree copy and defines only the kubeconform helpers. Reference this
spec.

Flip this file's **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: add `system_shim.bats` first and run it against the `HEAD` `system.sh`; tests
      1–3 are RED, 4–5 pass. Paste the output.
- [ ] Mutation 1: in the shim, prefix the foundation `source` line with `: `; tests 1, 2 and 5 go
      red.
- [ ] Mutation 2: replace `"${BASH_SOURCE[0]%/*}"` with `"$(dirname "${BASH_SOURCE[0]}")"`; test 5
      goes red.
- [ ] Restore after each mutation from a `$TMPDIR` snapshot and prove it with `cmp`.
- [ ] `bats` over every `scripts/tests/**/*.bats` file that sources `lib/system.sh`, plus
      `system_shim.bats`: all pass; paste the counts.
- [ ] `make test` green (allow ~15 minutes; run it backgrounded and read the log, do not abandon it).
- [ ] `shellcheck -x scripts/lib/system.sh scripts/tests/lib/system_shim.bats` clean.
- [ ] `grep -c '^function ' scripts/lib/system.sh` = 3.
- [ ] Changes left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT run `make up`, any `bin/` script, real `sudo`, `launchctl`, `install` into `/Library`,
  `ifconfig`, or anything live.
- Do NOT edit `scripts/lib/foundation/`, `scripts/k3d-manager`, `scripts/lib/system_overrides.sh`,
  `Makefile`, any `bin/` script, `/etc/sudoers.d` or `bin/install-sudoers.sh`.
- Do NOT add a fallback that defines functions locally when the foundation file is missing.
- Do NOT touch files outside those listed. Do NOT touch other unstaged changes. No commit, push,
  PR or `--no-verify`. Do NOT switch branches or touch `main`.

## Follow-ups (not in this spec)

- lib-foundation: the `sudo -n true` probe in the `--prefer-sudo` / `--require-sudo` paths never
  passes with command-scoped NOPASSWD rules.
- `bin/hub-up`, `bin/hub-restore`, `bin/k3dm-hermes-setup` and the dispatcher keep their
  "prefer foundation, else local" blocks; with the shim both branches load the same code. Simplify
  later.
- Upstream the kubeconform helpers to lib-foundation so the shim defines nothing.
