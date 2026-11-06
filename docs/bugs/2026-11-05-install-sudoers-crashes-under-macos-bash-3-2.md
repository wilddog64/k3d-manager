# Bug: `make install-sudoers` crashes under macOS /bin/bash 3.2 (`probe_args[@]: unbound variable`)

**Status:** OPEN: dispatched to Luna (`gpt-6-luna`) 2026-11-05, fix A
**Priority:** P2
**Severity:** medium. On a Mac where `env bash` resolves to Apple's `/bin/bash` 3.2, `make install-sudoers` stops before installing anything. That blocks the sudoers P1 remediation on that host. Workaround: run with Homebrew bash first on `PATH`.
**Filed:** 2026-11-05
**Detected by:** operator, running `make install-sudoers` on the M2. It succeeded on the M4 and M5.
**Branch:** `k3d-manager-v1.43.14`
**Approval:** operator, 2026-11-05: "yes" to fix A (bash 4 guard in `bin/install-sudoers.sh`). Option B is out of scope.
**Related:** `docs/bugs/2026-11-05-sudoers-passwordless-rules-grant-root-escalation.md` (its live E4 needs this host); `docs/bugs/2026-10-10-dr-drill-set-u-wrappers.md`

## Evidence

Operator, M2, 2026-11-05, on branch `k3d-manager-v1.43.1`:

    bin/install-sudoers.sh
    /tmp/k3d-manager-sudoers.DsM3Nr: parsed OK
    .../scripts/lib/foundation/scripts/lib/system.sh: line 183: probe_args[@]: unbound variable
    make: *** [install-sudoers] Error 1

Reproduced by Claude on the M4, 2026-11-05, against `k3d-manager-v1.43.14` (`c97d2096`):

    /bin/bash -c 'set -euo pipefail; source scripts/lib/foundation/scripts/lib/system.sh; _run_command -- /usr/bin/true'
    scripts/lib/foundation/scripts/lib/system.sh: line 183: probe_args[@]: unbound variable

- `/bin/bash --version` is `3.2.57(1)-release`. On the M4 and M5, `command -v bash` is `/opt/homebrew/bin/bash` (5.3), so the bug does not appear there.
- Bash before 4.4 treats `"${arr[@]}"` on an empty array as unbound under `set -u`.
- `_run_command` expands `"${probe_args[@]}"` at `system.sh:181` and `:185` with no `--probe`. That is every `_run_command` call without a probe, including the two `--interactive-sudo` installs in `bin/install-sudoers.sh`.
- `scripts/k3d-manager:16` already refuses bash below 4. `bin/install-sudoers.sh` (`#!/usr/bin/env bash`) has no such guard.

Recurrence: the operator reran it on the M2 on `k3d-manager-v1.43.14` and got the same error at line 183. So the bug is not specific to the stale branch.

Root cause on the M2: the interactive shell did not have Homebrew on `PATH` until the operator ran `eval "$(brew shellenv)"`. After that, `make install-sudoers` succeeded (2026-11-05). So the M2's shell profile is missing `brew shellenv`, and a script without a bash-version guard fails silently into bash 3.2.

## Fix (proposal; the operator picks)

- **A. Fail fast (recommended, smallest).** `bin/install-sudoers.sh` checks `BASH_VERSINFO` the same way `scripts/k3d-manager:16` does. On bash below 4 it exits 2 with a message naming `brew install bash` and the `PATH` workaround, before writing the temp file.
- **B. Make the lib bash-3.2 safe.** In lib-foundation, change the empty-array expansions in `_run_command` to `${probe_args[@]+"${probe_args[@]}"}`, and do the same for any others a bash 3.2 run hits. Per the subtree rule, this is edited upstream first, then subtree-pulled. It is broader, because other bin scripts and the lib may hit more 3.2 gaps, and the repo's stated floor is bash 4.

## Files

- `bin/install-sudoers.sh`
- `scripts/tests/bin/install_sudoers.bats`
- `docs/bugs/2026-11-05-install-sudoers-crashes-under-macos-bash-3-2.md`

## Acceptance

```yaml
must:
  - id: M1
    text: "Under bash >= 4, `bin/install-sudoers.sh --dry-run` behaves exactly as before (exit 0, rules printed)."
  - id: M2
    text: "Under /bin/bash 3.2, `bin/install-sudoers.sh` (any mode) exits non-zero with a message naming the bash 4 requirement."
must_not:
  - id: N1
    text: "Under bash 3.2 the script never reaches `_run_command` and never prints `unbound variable`."
  - id: N2
    text: "Under bash 3.2 the script never creates the /tmp/k3d-manager-sudoers.* temp file."
evidence:
  - {id: E1, proves: [M2, N1, N2], kind: offline, text: "BATS runs the script via /bin/bash (skipped if /bin/bash is >= 4); N1 red on c97d2096. TMPDIR points at a scratch dir, and the test asserts it is not /tmp, then that no temp file was created."}
  - {id: E2, proves: [M1], kind: offline, text: "Existing install_sudoers.bats under Homebrew bash, unchanged and green (paired positive control)."}
  - {id: E3, proves: [M2], kind: live, text: "Operator: on the M2, plain `make install-sudoers` prints the bash 4 message; with Homebrew bash first on PATH it installs."}
interface:
  - "bin/install-sudoers.sh [--dry-run]"
```
