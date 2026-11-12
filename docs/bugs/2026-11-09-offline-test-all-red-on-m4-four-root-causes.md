# Bug: offline test-all is red on the M4 from four separate root causes

**Status:** OPEN — parent filed 2026-11-09; child specs C1–C4 written and intents approved; children dispatch on `k3d-manager-v1.43.16`
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-12 (capture-first triage; nothing dispatched)
**Introduced by:** unknown (four root causes, each with its own origin; see the table)
**Should have been caught by:** unknown
**Prior art:** `docs/bugs/2026-10-28-offline-test-all-grep-guard-and-e2e-dispatch-regressions.md` (found by grep, not
scored) — read, different root cause: four BATS cases fixed in v1.43.9, none of them in this set.
`make find-similar-docs` not run to a result (vector store unreachable from the M4: `context "k3d-k3d-cluster" does
not exist`, 2026-11-09).
**Severity:** medium — the offline gate has been red for about 1.7 weeks (Grafana Offline Tests showed 28 failing),
so a new regression would not stand out. One root cause (C3) is also a safety issue: a test reaches the operator's real
launch agent and only the tripwire stops it.
**Approval:** operator, 2026-11-09 ("go head to file v1.43.16 test-failure parent bug"); the operator decided on
2026-11-09 to fix it in bug-only v1.43.16 as one P2 parent with child fixes per root cause (decomposition trial)
**Intent approved:** operator, 2026-11-09
**Filed:** 2026-11-09
**Detected by:** Claude, 2026-11-09, serial `make test-all` baseline and a per-file parallel run on the M4
**Release:** v1.43.16 (bug-only; does not use a plan slot)
**Branch:** filed on `k3d-manager-v1.43.15`; fixes go on `k3d-manager-v1.43.16`

## Symptom

On the M4, in the operator's normal shell (direnv active under `~/src/gitrepo/personal`), at `2c42361d`:

| Target | rc | Seconds | Failing cases |
|---|---|---|---|
| `make test` | 2 | 322 | 27 |
| `make test-bin` | 2 | 704 | 5 |
| `make test-python` | 2 | 341 | 4 |

A per-file run of all 330 test files with `xargs -P` at `b9c16615` (P = 1, 4, 6, 10, and P = 4 slowest-first at
`fadbb82a`) failed the same files every time. One of the 36 cases (`machine_setup_acceptance.bats` "M5: README and
Makefile link the howto") has since been fixed by `ed6b953b` and passes at `4740bbf5`. That leaves 35 cases from four
root causes.

## Root causes and children

| Child | Cases | Files | Root cause | Evidence |
|---|---|---|---|---|
| C1 | 27 | `lib/ci_workflow_no_stage2.bats`, `plugins/argocd_app_cluster_generator.bats`, `plugins/dr_alert_rules.bats`, `plugins/e2e_observability.bats`, `plugins/hub_pushgateway.bats`, `plugins/vectordb_rules.bats` | The tests run bare `python3 -` and need PyYAML. In the operator's shell, the first `python3` is the direnv layout (`~/.cache/direnv/layouts/…/python-3.13`), which has no PyYAML: `ModuleNotFoundError: No module named 'yaml'`. CI's python has it. | Rerun 2026-11-09 with `/opt/homebrew/bin` first on `PATH`: all six files pass. 23 bats files under `lib/` and `plugins/` call `python3 -`. |
| C2 | 4 | `bin/test_dashboard_queries.py`, `bin/test_dispatch_metrics.py`, `bin/test_orbstack_metrics.py` (2) | No local `promtool`, so the tests fall back to `docker run --entrypoint=promtool prom/prometheus:v3.1.0`, which the tripwire blocks: `assert 97 == 0`. CI has promtool. | Logs show the docker argv under `/tmp/k3dm-tripwire.*/bin/docker`. |
| C3 | 3 | `bin/cluster_status_app_cluster_registration.bats` | `bin/cluster-status:431` calls `_observability_restore_alertmanager_access_layer`. The test stubs `kubectl`, `aws` and `curl` but not `launchctl`, and does not isolate `HOME`, so the call aims at the real agent: 30× `launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.k3d-manager.alertmanager-port-forward.plist` and 3× `bootout`. The tripwire blocks all 33 and fails the file. **Without the tripwire, the test would act on the operator's live launch agent.** | Tripwire report in the P=1 log, 2026-11-09. |
| C4 | 1 | `bin/machine_secrets.bats` #24 "real throwaway keychain round trip is macOS only" | The test asserts `command -v security` is `/usr/bin/security` and creates a throwaway keychain. Under `make test-bin` the tripwire shims `security`, so the test can never pass there. | `security create-keychain -p fixture-pass …/stream-source.keychain-db` blocked. |

The order is by risk, not size: C3 first (real-host reach), then C1 (largest count), C4, C2.

## Not in scope: harness artifacts seen only in the parallel run

- `bin/ask_bash_scope.bats` failed only because the scratch checkout was under `/tmp`, which `/ask` allows by design.
  It passes under `make` in the real checkout. Its fixture builds the "outside" path inside the repo and never checks
  that the path is out of scope. That is a P3 (fixture self-check), filed separately, not a child here.
- `bin/test_webhook_log.py` fails when run as a single file (`No module named 'webhook'`) but passes under
  `make test-python`, which runs it together with `scripts/tests/hermes`.
- `bin/test_webhook_analyze_routing.py` failed once in five runs (P = 6): the 413 test got `ConnectionResetError`
  while the client was still sending. A load race; P3 candidate.
- `bin/codex_dispatch.bats` takes 292–346 s, a quarter of the serial run and the floor for any parallel run. Splitting
  it is a P3 candidate for the same batch.

## Plan (decomposition trial)

1. Claude writes one child spec per root cause (C1–C4) with its own Acceptance block, for intent approval.
2. Children touch disjoint files and can be dispatched in parallel within the WIP limit of 3.
3. After all four land, Claude runs the integration check below. The parent closes only on that result.

Rework is tracked against the trial baseline of 0.66.

## Acceptance

```yaml
must:
  - id: M1
    text: make test, make test-bin and make test-python each exit 0 on the M4, run from the operator's normal shell
      (direnv active), with zero failing cases.
  - id: M2
    text: no case in the suite reaches launchctl, security or docker on the real host; the tripwire reports zero
      blocked non-read calls.
must_not:
  - id: N1
    text: no failing case is made green by deleting it, skipping it, or weakening its assertion; the total case count
      per target is at least the 2c42361d baseline, less any case a child spec explicitly retires.
  - id: N2
    text: no package is installed into the direnv or system python to make C1 pass; the fix is in how tests pick their
      interpreter or report a missing module.
evidence:
  - id: E1
    proves: M1, M2
    kind: offline
    intent: After all four fixes, the full offline test run on the M4 is green from your normal shell, with no test
      touching launch agents, the keychain or docker.
  - id: E2
    proves: M1
    kind: live
    intent: The Grafana Offline Tests dashboard shows zero failing after your next published test-all run.
  - id: E3
    proves: N1
    kind: offline
    intent: The number of test cases per target did not drop, so nothing went green by being removed.
interface:
  - make test
  - make test-bin
  - make test-python
  - scripts/tests/tripwire.sh
```
