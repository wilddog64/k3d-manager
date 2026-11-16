# Bug: `make fast-gate BASE=<sha>` fails `agent_dispatch_dashboard.bats` because the suite reads `BASE` from the environment

**Status:** LANDED — test-hygiene batch `0b8d2b80` on k3d-manager-v1.44.0, 2026-11-12 (Codex Luna; Flash 3.8 diff review; Claude verified offline)
**Priority:** P3
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (make fast-gate BASE=<sha>` fails due to `BASE` leaking into `agent_dispatch_dashboard.bats`, but calling `scripts/ci/fast_gate.sh <sha>` directly with a positional argument works around it); Claude proposed P3. Higher stands until the operator decides.
**Triage:** carry → v1.44.0 (test-hygiene batch) — grooming 2026-11-12, operator. Priority: operator kept Claude's P3 over Argon's P2.
**Waiting on:** live check — since 2026-11-12 (operator `make test` on the M4 / fresh clone)
**Severity:** low — a false red from the documented `make fast-gate BASE=...` form; the pre-push hook and `land` pass the base positionally and are unaffected; workaround `scripts/ci/fast_gate.sh <sha>`
**Approval:** operator, 2026-11-01 ("let's get the reminding items complete so we can create-pr"; found while running E4 of the fast-gate bug)
**Filed:** 2026-11-01
**Detected by:** Claude, live E4 of `docs/bugs/2026-10-31-ci-reds-reproducible-locally-no-fast-gate.md` on the M4
**Affected:** `Makefile` (`fast-gate` target), `scripts/ci/fast_gate.sh`, `scripts/tests/plugins/agent_dispatch_dashboard.bats` (line 3)
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-31-ci-reds-reproducible-locally-no-fast-gate.md` (the gate this breaks)

## Observed failure

On the M4, 2026-11-01, `make fast-gate BASE=bd68d6ff53cfbec771f3c6b8c253edf44a2ae4db` printed
`FAIL scripts/tests/plugins/agent_dispatch_dashboard.bats 2s` with every test `not ok` (1..35), and exited 2. The same
suite passes 35/35 run directly. `scripts/ci/fast_gate.sh bd68d6ff…` (positional, no `BASE` in the environment) passes
it. `BASE=bd68d6ff bats -f 'valid ConfigMap' scripts/tests/plugins/agent_dispatch_dashboard.bats` reproduces the red.

## Root cause

GNU make exports variables given on its command line to every recipe's environment. The suite starts with
`BASE="${BASE:-${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops}"`, so under `make fast-gate BASE=<sha>` it reads
the dashboards from a directory named after the SHA, which does not exist, and every test fails.

## Fix

1. `scripts/tests/plugins/agent_dispatch_dashboard.bats`: rename the suite's override to a name no caller uses for
   something else (`AGENT_DASHBOARD_DIR`, default unchanged), and replace every `$BASE` in the file.
2. `scripts/ci/fast_gate.sh`: run each check with `BASE` removed from its environment (`env -u BASE`), so a caller's
   make variable never reaches a suite.

## Files

- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `scripts/ci/fast_gate.sh`
- `scripts/tests/lib/fast_gate.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not change the `make fast-gate BASE=` interface or the positional argument of `fast_gate.sh`.
- Do not change any dashboard assertion in `agent_dispatch_dashboard.bats`; only the variable name.
- Tests use a scratch repo or fixture suite, never run the real full gate inside a test.

## Acceptance

```yaml
must:
  M1: agent_dispatch_dashboard.bats passes with BASE=<any sha> set in its environment
  M2: AGENT_DASHBOARD_DIR=<dir> points the suite at another dashboard directory (paired positive control: a directory missing the dashboards makes it fail)
  M3: a check run by fast_gate.sh does not see a BASE variable from the caller's environment
must_not:
  N1: make fast-gate BASE=<sha> never reports agent_dispatch_dashboard.bats FAIL when the suite passes run directly
  N2: fast_gate.sh's base selection (positional arg, then default) does not change
evidence:
  E1:
    proves: [M1, M2, M3, N2]
    kind: offline
    intent: >-
      You will see BATS run the dashboard suite with BASE=deadbeef exported and pass (red on the pre-fix suite), with
      AGENT_DASHBOARD_DIR at an empty dir and fail, and a fast_gate.bats case whose fixture check prints its env show
      no BASE while the positional base is still honoured.
    what: bats scripts/tests/plugins/agent_dispatch_dashboard.bats scripts/tests/lib/fast_gate.bats
  E2:
    proves: [N1]
    kind: live
    intent: You will see make fast-gate BASE=<v1.43.12 merge base> on the M4 report PASS for agent_dispatch_dashboard.bats.
    what: Claude on the M4
interface:
  - make fast-gate BASE=<sha>
  - scripts/ci/fast_gate.sh [BASE]
  - bats scripts/tests/plugins/agent_dispatch_dashboard.bats
  - env BASE, AGENT_DASHBOARD_DIR
```
