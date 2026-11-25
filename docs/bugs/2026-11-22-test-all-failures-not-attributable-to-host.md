# Bug: latest test-all failures cannot be traced to the Mac that ran them

**Status:** OPEN — captured 2026-11-22
**Priority:** P3
**Triage:** backlog — pull into a release that already touches `bin/k3dm-test-metrics` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Observability hygiene gap where `k3dm-test-metrics` lacks a `host` label, preventing the dashboard from identifying which Mac pushed a test failure.)
**Waiting on:** operator decision
**Prior art:** `docs/bugs/2026-10-07-test-metrics-stale-failure-series.md` (grep, not scored) — read, different root cause (stale series, not missing host); `make find-similar-docs` not run (vector store unreachable from the M4 on 2026-11-21).

## Symptom

The k3dm Tests dashboard (operator screenshot, 2026-11-22) shows Failed cases 3 and two `k3dm_test_failure` rows:

- bats 359 `_acg_resolve_provider falls back to k3s-hostinger when nothing is reachable and no file exists`
  (`scripts/tests/lib/provider_contract.bats:133`)
- bats 427 `E2: live and stalled listings are read-only and restricted to newest version`
  (`scripts/tests/bin/dispatch_stall_state.bats`)

## Findings (Claude, m4-air, 2026-11-22)

- Both cases pass in isolation, 3 of 3 runs each.
- The whole files pass: `provider_contract.bats` 62/62, `dispatch_stall_state.bats` 17/17, `provider_active_set.bats` 30/30.
- m4-air's `~/Library/Logs/k3dm-test-metrics.log` was last written 2026-10-30, so the run behind the dashboard was on m5-air or m2-air.
- `bin/k3dm-test-metrics:246` pushes to `job/k3dm-tests/instance/{target}-{origin}`: no host label, so every Mac
  overwrites the same series and the dashboard cannot say which Mac failed.
- The provider case stubs only `kubectl`; on a Mac where a provider is reachable by another path it may resolve
  differently. The E2 case depends on timing and on the dispatch state it lists. Both are candidate environment leaks.

## Proposed fix (for triage)

1. Add a `host` label (short hostname) to the k3dm-tests push group and to the failing-cases table.
2. Reproduce both cases with the whole files on the Mac that ran the failing run; if they fail there, find the leak.
