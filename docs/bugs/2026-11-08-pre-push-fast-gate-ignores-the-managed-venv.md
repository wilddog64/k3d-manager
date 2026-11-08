# Bug: the pre-push fast gate runs tests with whatever python3 is first on PATH, not the managed venv

**Status:** LANDED — `99d6796b` on `k3d-manager-v1.43.15` (2026-11-08); Claude review; `fast_gate.bats` + `ci_workflow_no_stage2.bats` green at land; M4 managed venv given PyYAML 6.0.3 by the operator first (else the fix would have broken M4 pushes)
**Priority:** P2
**Waiting on:** live check — since 2026-11-08 (Flash verifier; then M5 `make machine-setup` and a push without K3DM_SKIP_FAST_GATE, E2)
**Introduced by:** unknown (the fast gate always used bare `python3`; `ci_workflow_no_stage2.bats` added `import yaml` in `bd68d6ff`, v1.43.12)
**Should have been caught by:** deploy step
**Severity:** medium — any push from M5 fails the gate (`ModuleNotFoundError: No module named 'yaml'`), and from M4 unless PATH is changed by hand. Workaround: `K3DM_SKIP_FAST_GATE=1`, or `PATH=/opt/homebrew/bin:$PATH` on M4 only.
**Approval:** operator, 2026-11-08 ("go ahead to file those and dispatch to Luna/Flash 3.8 base on our rules")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** operator, M5 `make hub-promote` (bootstrap): `FAIL scripts/tests/lib/ci_workflow_no_stage2.bats`
**Affected:** `scripts/ci/fast_gate.sh`
**Branch:** `k3d-manager-v1.43.15`
**Related:** `docs/bugs/2026-11-06-machine-setup-leaves-nightly-suite-without-pyyaml.md` (VERIFIED, `785f25a4`: machine-setup installs PyYAML into the managed venv and the nightly plist puts that venv first on PATH; the fast gate was not covered)

## Symptom

On M5 during the 2026-11-08 bootstrap, `git push` from `make hub-promote` ran the pre-push fast gate, which failed:
`FAIL scripts/tests/lib/ci_workflow_no_stage2.bats`, `ModuleNotFoundError: No module named 'yaml'`.
`/opt/homebrew/bin/python3 -c 'import yaml'` also fails on M5. On M4 the push passes only with
`PATH=/opt/homebrew/bin:$PATH`.

## Root cause

Two gaps:
1. `scripts/ci/fast_gate.sh` runs suites with the caller's PATH. Tests such as `ci_workflow_no_stage2.bats` call bare
   `python3`, so the result depends on the shell (direnv venv, Homebrew, pyenv). The managed venv that `machine-setup`
   prepares (`${XDG_DATA_HOME:-$HOME/.local/share}/k3d-manager/venv`) is used by the nightly agent but not here.
2. The managed venv itself lacks PyYAML on M4 (checked 2026-11-08: `~/.local/share/k3d-manager/venv/bin/python3 -c
   'import yaml'` → ModuleNotFoundError), so `machine-setup` has not been rerun since `785f25a4`. This part is an
   operator step, not code.

## Fix

- `scripts/ci/fast_gate.sh`: when `${XDG_DATA_HOME:-$HOME/.local/share}/k3d-manager/venv/bin/python3` exists and is
  executable, put that `bin` directory first on PATH for the suites it runs. When it does not exist, PATH is
  unchanged.
- Operator, once landed: `make machine-setup` on M4 and on M5 (installs PyYAML into the managed venv).

## Files

- `scripts/ci/fast_gate.sh`
- `scripts/tests/lib/fast_gate.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "when the managed venv exists under XDG_DATA_HOME, a suite run by the fast gate finds that venv's python3 first on PATH"
  - id: M2
    text: "a suite needing a module present only in the managed venv passes under the fast gate, even when the first python3 on the caller's PATH lacks it"
must_not:
  - id: N1
    text: "when no managed venv exists, the fast gate changes PATH (paired control for M1: with the venv present, PATH does change)"
  - id: N2
    text: "the fast gate creates, installs into, or modifies the managed venv"
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: "tests run the fast gate with a scratch XDG_DATA_HOME holding a fake venv, and check which python3 a test suite sees, with and without that venv"
  - id: E2
    proves: [M2]
    kind: live
    intent: "after make machine-setup on M5, the operator pushes from M5 without K3DM_SKIP_FAST_GATE and the gate passes"
interface:
  - "scripts/ci/fast_gate.sh (run by .githooks/pre-push), with XDG_DATA_HOME and HOME pointed at scratch directories"
```

## Notes

- Fixtures assert first that `XDG_DATA_HOME` and `HOME` point at scratch directories, never the real
  `~/.local/share/k3d-manager` (CLAUDE.md test controls).
