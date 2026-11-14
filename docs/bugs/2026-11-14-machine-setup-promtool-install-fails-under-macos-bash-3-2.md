# Bug: machine-setup's promtool install fails under macOS /bin/bash 3.2 (`probe_args[@]: unbound variable`)

**Status:** LANDED (lib-foundation v0.5.6, subtree pull 79caba45)
**Priority:** P2
**Waiting on:** live check — since 2026-11-14 (promtool Part B re-land, then machine-setup on a bash 3.2 Mac)
**Severity:** medium; blocks the promtool Part B land. On a Mac where `env bash` resolves to Apple's `/bin/bash` 3.2 (a fresh Mac before Homebrew bash is first on `PATH`), the new `install_promtool` step in `bin/k3dm-machine-setup` reports `promtool missing (see installer output)` and sets `failed=1`. Setup still runs to the end. Workaround: rerun once Homebrew bash is on `PATH`.
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

## Update 2026-11-14: blocks the promtool Part B land

Claude, m4-air, 2026-11-14. The promtool land (`f5d1eb5a`, rebased onto `feb41165`) was refused: `machine_setup_acceptance.bats` "N4: report output has no username and no home path" failed. The leaking line is this crash, from a hub setup run with no flags:

    <land TMPDIR>/bats-run-*/test/1/tree/scripts/lib/foundation/scripts/lib/system.sh: line 183: probe_args[@]: unbound variable

- The suite's `ms` helper runs `/bin/bash "$TREE/bin/k3dm-machine-setup"` under `env -i`. So the repo's own acceptance harness expects machine-setup to work on Apple's bash 3.2, and Part B breaks that on every console and hub setup run.
- Under a normal TMPDIR the crash still happens, but its path has no `/Users/<user>`, so N4 passed in every earlier run. It showed up only because land sets `TMPDIR` under the operator's home.
- The same test passes on base `feb41165` under the same TMPDIR, so Part B introduced it.
- Option A (guard the script) cannot work: the harness runs bash 3.2 on purpose. That leaves option B (make `_run_command` 3.2-safe in lib-foundation, subtree-pull), which could go in the pending lib-foundation v0.5.6 with the ACG fix. Or Part B could avoid `_run_command` on the macOS path.

## Decision and fix 2026-11-14

- Operator, 2026-11-14: "let's fix _run_command in lib-foundation" (option B).
- lib-foundation `45d7dae` on `release/v0.5.6` (Claude): every `"${sudo_flags[@]}"` and the two unguarded `"${probe_args[@]}"` calls in `_run_command` become `${arr[@]+"${arr[@]}"}`. Three new `system.bats` tests run under `/bin/bash` 3.2.57 with `set -euo pipefail`: plain and `--quiet` `_run_command` without `--probe`, `_install_promtool` with the fixture, and the resolver's interactive-sudo branch on a TTY (BSD `script`). All three were red on `c7384ff` (`probe_args[@]` / `sudo_flags[@]: unbound variable`) and green on `45d7dae`. They skip on bash 4.4 or newer (CI's Linux runner), since newer bash no longer errors.
- `make bats` in lib-foundation: 232/232 (m4-air, 2026-11-14). shellcheck clean.
- Remaining: lib-foundation v0.5.6 release (with the ACG fix `c7384ff`), subtree pull into k3d-manager, then rerun the promtool land.

## Landed 2026-11-14

- lib-foundation PR #85 merged by the operator (`d18f4fe`), tagged and released as v0.5.6 (Claude).
- Subtree pulled into k3d-manager at `79caba45`. Under `/bin/bash` 3.2.57 with `set -euo pipefail`, `source scripts/lib/system.sh; _run_command --quiet -- true` now returns 0 (Claude, m4-air).
- Next: re-land promtool Part B, whose N4 acceptance test caught this crash.
