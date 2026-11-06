# Bug: machine-setup leaves the nightly test agent without PyYAML

**Status:** OPEN — dispatched to Luna 2026-11-06
**Priority:** P2
**Severity:** medium. The nightly offline suite on the M5 has been red since the cutover, so `OfflineSuiteFailing`, `OfflineSuiteRunIncomplete` and `OfflineSuiteStale` fire on real and environmental failures alike. The suite cannot warn about a real regression.
**Approval:** operator, 2026-11-06: "go ahead for those two".
**Filed:** 2026-11-06
**Detected by:** Claude, read-only M5 check of `docs/bugs/2026-11-02-hostinger-offline-suite-alerts.md`
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-02-hostinger-offline-suite-alerts.md`, `docs/bugs/2026-11-06-webhook-hub-eso-test-breaks-on-python-3-15.md`, `docs/bugs/2026-10-28-offline-test-all-grep-guard-and-e2e-dispatch-regressions.md`

## Problem

Read-only capture from `m5-air`, 2026-11-06 about 17:40Z:

- `com.k3d-manager.test-metrics` runs `make test-all` at 04:30 local with `/Users/cliang/.pyenv/shims:/opt/homebrew/bin:...` as PATH. `python3` resolves to `/opt/homebrew/bin/python3`, 3.15.2, with no PyYAML.
- `~/Library/Logs/k3dm-test-metrics.log` holds 125 `ModuleNotFoundError: No module named 'yaml'` lines.
- The last run reports 29 failed of 1995, `k3dm_test_run_complete 0`, exit code 2. The last passing run is 2026-10-28 22:42Z.

The M4 passes only because its PyYAML was installed by hand into `~/Library/Python/3.15/lib/python/site-packages`. Nothing in `bin/k3dm-machine-setup` provides it: `ensure_python_tools` (`bin/k3dm-machine-setup:187`) installs only `pytest` and `ruff` into `~/.local/share/k3d-manager/venv`, returns early when those are found, and the agent's PATH does not include that venv.

Not every one of the 29 is proven to be this cause. Case 500 is fixed by `2ee593e3`, but the M5 checkout was 30 commits behind. Cases 64 and 332 are not classified. Whatever still fails after this fix gets its own bug.

## Fix

1. `ensure_python_tools` also requires `import yaml` in the venv and installs `PyYAML==6.0.3` there. The early returns must not skip this when `ruff` and `pytest` are already present. In check mode, a venv without PyYAML is reported as missing and nothing is installed.
2. `scripts/etc/launchd/com.k3d-manager.test-metrics.plist.tmpl` puts `{{HOME}}/.local/share/k3d-manager/venv/bin` first on PATH.

## Files

- `bin/k3dm-machine-setup`
- `scripts/etc/launchd/com.k3d-manager.test-metrics.plist.tmpl`
- `scripts/tests/bin/machine_setup.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "In setup mode, with ruff and pytest already available and a venv that cannot import yaml, machine-setup installs PyYAML pinned to 6.0.3 into that venv and reports success."
  - id: M2
    text: "In check mode, a venv that cannot import yaml is reported as a python-tools failure."
  - id: M3
    text: "The rendered test-metrics plist has the k3d-manager venv bin directory as the first PATH entry."
must_not:
  - id: N1
    text: "Check mode installs nothing and does not create or change the venv (paired positive control: M1 shows setup mode does install)."
  - id: N2
    text: "A venv that already imports yaml, ruff and pytest triggers no install."
evidence:
  - {id: E1, proves: [M1, M2, M3, N1, N2], kind: offline, text: "Black-box tests running bin/k3dm-machine-setup with a scratch HOME and XDG_DATA_HOME and a stub python/pip recording its calls, each asserting first that it is pointed at the scratch paths. M1, M2 and M3 red on the pre-fix commit; N1 and N2 red by a mutant."}
  - {id: E2, proves: [M1, M3], kind: live, text: "After the operator updates the M5 checkout and runs make machine-setup ROLE=hub and make install-test-metrics, the next 04:30 run has no 'No module named' line in its log. Remaining failures are listed and filed."}
interface:
  - "bin/k3dm-machine-setup, mode check and mode setup, ensure_python_tools"
  - "make install-test-metrics with K3DM_AGENT_LOAD=0"
```
