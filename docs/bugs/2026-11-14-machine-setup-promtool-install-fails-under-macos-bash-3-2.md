# Bug: machine-setup's promtool install fails under macOS /bin/bash 3.2 (`probe_args[@]: unbound variable`)

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-14
**Severity:** low. On a Mac where `env bash` resolves to Apple's `/bin/bash` 3.2 (a fresh Mac before Homebrew bash is first on `PATH`), the new `install_promtool` step in `bin/k3dm-machine-setup` reports `promtool missing (see installer output)` and sets `failed=1`. Setup still runs to the end. Workaround: rerun once Homebrew bash is on `PATH`.
**Filed:** 2026-11-14
**Detected by:** Fable review of the promtool Part B diff (finding M1), 2026-11-14
**Introduced by:** promtool Part B (uncommitted worktree diff, `docs/bugs/2026-11-09-promtool-tests-need-pinned-install-on-every-host.md`): its first `_run_command` call on the macOS path. The root cause, empty-array expansion in lib-foundation `_run_command`, is pre-existing.
**Should have been caught by:** review
**Prior art:** `docs/bugs/2026-11-05-install-sudoers-crashes-under-macos-bash-3-2.md` (exact symptom, found by grep; `find-similar-docs` unavailable, vector store down): read, same root cause. Fix A there only guarded `bin/install-sudoers.sh`; option B (make the lib 3.2-safe) was left out of scope.

## Evidence

Fable, m4-air, 2026-11-14, in a scratch copy of the Part B worktree:

    /bin/bash -c 'set -euo pipefail; source scripts/lib/system.sh; if _install_promtool; ...'
    scripts/lib/foundation/scripts/lib/system.sh: line 183: probe_args[@]: unbound variable

- The same command under `/opt/homebrew/bin/bash` returned 0 and printed `promtool, version 3.1.0`.
- `_run_command` expands `"${probe_args[@]}"` at `system.sh:181` and `:185` when no `--probe` is given (Claude confirmed the lines, 2026-11-14).
- Before Part B, the macOS path of `bin/k3dm-machine-setup` never called `_run_command`; every earlier call was in `linux_control`. So this is the first exposure.

## Options (operator picks)

- **A. Guard the script.** Add the `BASH_VERSINFO` check from `scripts/k3d-manager:16` to `bin/k3dm-machine-setup`. But machine-setup is the bootstrap that installs Homebrew, so a guard could block its first run.
- **B. Make `_run_command` 3.2-safe upstream.** Change `"${probe_args[@]}"` to `${probe_args[@]+"${probe_args[@]}"}` in lib-foundation, then subtree-pull. This is the option the 2026-11-05 doc deferred.
