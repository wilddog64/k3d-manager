# Bug: Linux Homebrew installer download or run failure exits before cleanup and its report line

**Status:** OPEN
**Priority:** P3
**Classified:** P3 by gemini-4-argon-medium, 2026-11-12 (Error-path hygiene and cosmetic output issue: the script already exits with the expected non-zero status on installer failure, only skipping temp-file cleanup in `TMPDIR` and the formatted report message); Claude proposed P3. Agreed.
**Triage:** passed over, 1st — grooming 2026-11-12, operator.
**Waiting on:** operator decision — since 2026-11-12
**Introduced by:** `4bd764b9` (v1.43.15, `bin/k3dm-machine-setup:85,90`)
**Should have been caught by:** offline test (N6 tests checked that nothing ran, not the cleanup or the report line)
**Prior art:** `docs/bugs/2026-11-10-machine-setup-linux-exits-on-first-missing-formula.md` (same `_run_command` without `--soft` shape, lines 102-103, fixed in `d2cae3a6`) — read, same pattern at different lines; `make find-similar-docs` not run (vector store unreachable from the M4)
**Severity:** hygiene. N6 still holds (exits non-zero, runs nothing, prefix unchanged), but an empty `${TMPDIR:-/tmp}/homebrew-install.XXXXXX` is left behind and the operator sees a raw `ERROR: failed to execute curl ...` instead of `homebrew installer download failed`.
**Approval:** Claude, 2026-11-10 (found by the control-node independent verifier; dispatch needs the operator's intent approval)
**Intent approved:** operator, 2026-11-11
**Filed:** 2026-11-10
**Detected by:** independent verifier (Sonnet, Acceptance block only) for `docs/plans/v1.43.15-control-node-linux.md`, extra check `download-failure-leaves-no-tempfile`; reproduced by Claude on `17167381`
**Branch:** `k3d-manager-v1.43.15`
**Release:** v1.43.15 or the next patch

## Root cause

`bin/k3dm-machine-setup:85` runs `_run_command -- curl -fL ... -o "$installer"` inside an `if !`. `_run_command` without
`--soft` calls `_err` on a non-zero exit, which exits the script, so the `rm -f "$installer"` and `report homebrew
'installer download failed'` in the same branch never run. Line 90 (`_run_command -- env ... bash "$installer"`) has the
same shape for a failed installer run.

## Fix

Use `_run_command --soft` on lines 85 and 90 so the failure branch runs: the temp file is removed, the report line is
printed, and the function returns 1 as today.

## Files

| File | Change |
|---|---|
| `bin/k3dm-machine-setup` | lines 85 and 90 |
| `scripts/tests/bin/machine_setup.bats` | download-failure and installer-failure cases assert no temp file left and the report line |

## Contract readers

None: same exit codes; the report lines already exist in the script and are only reached now.

## Acceptance

```yaml
must:
  - id: M1
    text: "When the installer download fails, setup prints 'homebrew installer download failed', removes its temp file and exits non-zero."
  - id: M2
    text: "When the downloaded installer exits non-zero, setup prints 'homebrew installer failed', removes its temp file and exits non-zero."
must_not:
  - id: N1
    text: "A failed download or installer run never leaves a homebrew-install.* file in TMPDIR."
evidence:
  - {id: E1, proves: [M1, M2, N1], kind: offline, intent: "You will see machine_setup.bats fail the download (curl stub exits 22) and fail the installer, and assert the report line, an empty scratch TMPDIR, and a non-zero exit; it fails on today's script."}
interface:
  - "bin/k3dm-machine-setup --role control (Linux, uname stubbed)"
```
