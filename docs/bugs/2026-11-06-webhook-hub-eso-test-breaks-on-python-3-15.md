# Bug: webhook_hub_eso.bats fails on Python 3.15, so no Python on the M4 passes the land gate

**Status:** FIXED `2ee593e3`, independent verify PASS 2026-11-06 under Python 3.15.2 and 3.13.6; offline only, no live evidence required. The full land gate under Homebrew Python is confirmed at the next land
**Priority:** P3
**Severity:** low. Test-only; the webhook itself is not affected.
**Approval:** not required: non-critical, Claude files and dispatches. Operator told 2026-11-06.
**Filed:** 2026-11-06
**Detected by:** Claude, landing `9691bbaa` on the M4
**Branch:** `k3d-manager-v1.43.14`

## Problem

Test 6 of `scripts/tests/lib/webhook_hub_eso.bats` loads the webhook with `SourceFileLoader(...).load_module()`. Under Python 3.15.2 (`/opt/homebrew/bin/python3`, M4, 2026-11-06) that raises:

    AttributeError: 'SourceFileLoader' object has no attribute 'load_module'. Did you mean '.exec_module' instead of '.load_module'?

The M4 has two Pythons, and neither passes every suite the land fast gate selects for a webhook change:

- Homebrew 3.15.2 fails this test.
- The direnv 3.13.6 has no `yaml`, so `ci_workflow_no_stage2.bats` and tests 4 and 5 of `hub_pushgateway.bats` fail with `ModuleNotFoundError: No module named 'yaml'`.

Landing `9691bbaa` took a scratch Python 3.13 venv with PyYAML. This is also the failure Luna's full-suite runs reported.

## Fix

Load the webhook in this test with `importlib.util.spec_from_loader` and `exec_module`. This is the only `load_module()` call under `scripts/` and `bin/`. With it fixed, Homebrew Python passes the gate on the M4.

## Files

- `scripts/tests/lib/webhook_hub_eso.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "scripts/tests/lib/webhook_hub_eso.bats passes under Python 3.15."
  - id: M2
    text: "It still passes under Python 3.13."
must_not:
  - id: N1
    text: "The test still fails when the smoke test stops using the helper (paired with M1): the assertions must not be weakened."
evidence:
  - {id: E1, proves: [M1, M2, N1], kind: offline, text: "bats run under both Pythons; M1 red on the pre-fix commit under 3.15; N1 red by a mutant of _smoke_test_services."}
interface:
  - "scripts/tests/lib/webhook_hub_eso.bats"
  - "bin/k3dm-webhook _smoke_test_services"
```
