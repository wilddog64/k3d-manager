# Bug: make test fails when disposable ACG ubuntu-k3s context is unavailable

**Filed:** 2026-10-14
**Status:** CLOSED — DUPLICATE of `docs/bugs/2026-10-15-test-all-hub-data-prune-aging-fixtures.md` (fixed `24c5e960`). 2026-10-16 recheck: `make test` with the `ubuntu-k3s` context present and with an empty KUBECONFIG gave the same result, 1637 tests and the same 39 failing names. All 39 were `webhook.bats`/`webhook_hub_eso.bats` curl calls that could not reach the local test server inside the Codex sandbox, and those two files pass 74/74 outside it. The ACG context does not affect `make test`. Was: OPEN — investigation required; failing BATS case not yet identified
**Branch:** `k3d-manager-v1.43.2` (triage 2026-10-15, operator-approved placement)
**Priority:** P2 — offline regression environment coupling
**Reported:** 2026-10-14 by operator
**Release:** v1.43.2 (triage 2026-10-15, operator-approved placement)
**Component:** offline BATS tests, test environment contracts, optional ACG context
**Approval:** bug documentation only; no test or runtime behavior modified

## Operator report and evidence

Operator ran `make test` and received `make: *** [test] Error 1`. The visible tail includes tripwire's blocked host-tool call summary, including one `kubectl config get-contexts ubuntu-k3s`, read-only `aws cloudformation describe-stacks --region us-west-2 --stack-name k3d-manager-cluster ...`, GitHub auth and macOS Keychain reads. The operator states `ubuntu-k3s` refers to the ephemeral ACG sandbox and expects its absence/unreachability to yield a warning/skip rather than fail an offline suite.

**Do not overclaim root cause:** The screenshot shows the tripwire summary, not the BATS failing test name/assertion. The blocked `kubectl config get-contexts` is classified as a read by `scripts/tests/tripwire.sh`, so the blocked call alone may not explain exit 1. Get the full test transcript to identify the actual failure before changing code.

## Existing contracts

- `Makefile` `test` invokes `scripts/tests/tripwire.sh ./scripts/k3d-manager test all`.
- `scripts/tests/tripwire.sh` installs shims for `kubectl`, AWS, SSH, Vault, etc.; it blocks their real execution. Read-only probes are summarized; unsafe host modifications must fail. **Do not disable tripwire or change unsafe calls to warnings.**
- `ubuntu-k3s` is an optional ACG throwaway cluster, unlike required offline fixtures. Tests must not assume it is deployed, reachable or present in kubeconfig.

## Investigation and proposed resolution

1. Capture full `make test` output (including BATS test numbers and assertions) and determine which test returns nonzero, whether the cause is the missing `ubuntu-k3s` context, a blocked read returning 97, an AWS stack probe, another failing expectation, or a legitimate dangerous unmocked operation.
2. Trace affected test(s) to their fixture or setup logic. When a test validates behavior with ACG absent, provide a deterministic stubbed absent-context fixture and assert the correct warning/degraded result, instead of requiring live AWS/kubectl access.
3. If a test truly requires live ACG to assert its outcome, move/gate it as an explicit **opt-in integration test** (`make e2e-sandbox` or an appropriate live target), with a clear `SKIP: ACG not provisioned` report. The standard offline `make test` must not call or depend on live ACG.
4. Preserve failures from genuine offline regressions, unexpected probe errors unrelated to optional ACG, unsafe calls, and missing required fixture setup. Do not broadly translate all `kubectl` failures or test errors to success.
5. Verify any tripwire summary is clearly labeled as expected blocked diagnostic activity rather than implying that every listed read caused the test failure.

## Acceptance criteria

- [ ] Reproduce and name the failing test and exact failure mechanism using its full output; amend this bug with evidence.
- [ ] `make test` completes correctly on a Mac/CI runner with **no** `ubuntu-k3s` kubeconfig entry and no active ACG AWS stack, provided all offline assertions pass.
- [ ] Optional-context cases emit a clear warning/skip or are tested through deterministic mocks; their absence alone does not force failure.
- [ ] A real offline defect still fails `make test`; tripwire still blocks and fails unsafe/unmocked host-modifying commands.
- [ ] ACG live tests remain opt-in and fail accurately when specifically requested with a required unavailable sandbox, rather than silently passing.
- [ ] Regression coverage includes absent, stale/unreachable, and present simulated ACG contexts, without live AWS calls.
- [ ] No vacuous test passing or false-green dashboards; skipped live tests and unknown environments are recorded honestly.

No runtime or tests changed by this bug report.

## Cross-suite offline-contract audit — 2026-10-14 (source inspection only)

The operator requested a check of **other offline test suites**, not just `make test`. Current `Makefile` declarations show:

| Target | Coverage and safeguards | Finding |
|---|---|---|
| `make test` | `tripwire.sh ./scripts/k3d-manager test all` | Observed failure; failing BATS case unknown |
| `make test-bin` | `tripwire.sh bats scripts/tests/bin` | Offline host-tool guard present; same class of unexpected blocked-read/fixture assertions **possible**, not reproduced |
| `make test-python-unit` | Each non-`test_*.py` `scripts/tests/bin/*.py` run via `tripwire.sh python3` | Guard present for each script; same class possible, not reproduced |
| `make test-pytest` | `tripwire.sh pytest scripts/tests/hermes scripts/tests/bin/test_*.py` | Guard present; same class possible, not reproduced |
| `make test-python` | Depends on `test-python-unit` and `test-pytest` | Inherits both suites' behavior; no separate test logic |
| `make test-all` | Sequential `make test && make test-bin && make test-python` | Inherits failure of any child; short-circuits remaining children and publishes aggregate failure |
| `make test-alertmanager-behaviour` | Direct `python3 -m pytest` on two observability modules | **No tripwire wrapper** in this target. This is a verified difference in safety isolation; whether the specific tests access live host tools is unverified. Assess whether an explicit integration-test exception is warranted or wrap appropriately. |

Repository searches identify host-tool references inside offline test locations, including `scripts/tests/plugins/acg.bats` and `scripts/tests/bin/cluster_down.bats` for CloudFormation probes, and `scripts/tests/bin/makefile_keychain_read.bats` and `scripts/tests/hermes/test_pager.py` for Keychain probes. **These references are not proof of bugs**: they may be intentionally stubbed and properly asserted. Existing tripwire intercepts host access, while tests can still incorrectly depend on a successful real probe or fail on a blocked read (exit 97). Check fixture/mocking setup and output before changing assertions.

### Expanded investigation and regression matrix

1. Run each leaf target individually **without a provisioned ACG sandbox** and with controlled (simulated) missing, stale, and present `ubuntu-k3s` contexts: `test`, `test-bin`, `test-python-unit`, `test-pytest`. Capture named failing cases and tripwire reports separately. Do not trigger real AWS or destructive operations.
2. Prove all offline targets remain deterministic when AWS, kubeconfig, Keychain and GitHub authorization are absent; distinguish an intentionally mocked dependency from a genuine required fixture.
3. Verify `test-all` aggregates correct failure and does not silently suppress failures or report unexecuted suites as passing.
4. Audit `test-alertmanager-behaviour` separately for the missing tripwire safety wrapper; if live dependencies are required, classify and document it as an explicit opt-in integration gate rather than treating it as an offline suite.
5. Regression-test that **unmocked unsafe calls remain failures**. Only optional environment unavailability should become warning/skip when that is the documented contract.

**Audit result:** Common offline tripwire protection exists on the four main leaf suites. Other suite failures are **not confirmed** from source inspection alone; the uncovered `test-alertmanager-behaviour` target is a specific hardening candidate, not an established live-access incident. Keep this in the same bug pending test evidence rather than spawning speculative duplicates.

**Additional investigation requirement (operator, 2026-10-14):** Inventory **all other test-related Make targets**, not only `test`, `test-bin`, `test-python-unit`, `test-pytest`, and `test-all` (including dedicated targets such as `test-alertmanager-behaviour`). For each, determine whether it is intended to be offline or live/opt-in; check isolation, sandbox/cluster/Keychain/cloud dependencies, and missing-environment behavior. Document any separately confirmed defects or enhancements, without automatically adding special-purpose tests to `test-all` or weakening the tripwire.

## Codex verification task — 2026-10-16

**Approval:** explicit 2026-10-16 "go ahead and dispatch 1, 2, and 4 to codex" (operator)

The test-clock fix (`24c5e960`, `docs/bugs/2026-10-15-test-all-hub-data-prune-aging-fixtures.md`)
may have been this failure. This task checks that, with the `ubuntu-k3s` context both present and
absent. **It runs tests only; it fixes no test or runtime code.**

### Steps

1. `make test 2>&1 | tee "$RUN_LOG_PRESENT"` with your normal environment, where the real
   kubeconfig has an `ubuntu-k3s` context. Put both logs in a temp dir outside the repo.
   The suite takes about 15 minutes and goes quiet for long stretches. That is not a hang: run it
   in the background and watch the log's modification time, and never abandon it.
2. Make an absent-context kubeconfig: `tmp=$(mktemp -d)`; write `$tmp/config` containing only
   `apiVersion: v1`, `kind: Config`, `clusters: []`, `contexts: []`, `users: []`. Then run
   `KUBECONFIG="$tmp/config" make test 2>&1 | tee "$RUN_LOG_ABSENT"`.
3. For each run, report the final BATS summary line (`N tests, M failures`), the make exit code,
   and, for every `not ok` line, its number, name and the assertion output under it.
4. In `docs/bugs/2026-10-15-test-all-hub-data-prune-aging-fixtures.md`, change only its
   `**Status:**` line to:
   `**Status:** IMPLEMENTED — landed \`24c5e960\` (hub_data.bats freeze_clock + boundary test 5b; Claude verified 88/88 and mutations M1–M3 red). Was: OPEN — root cause confirmed 2026-10-15.`

## Files

| File | Change |
|---|---|
| `docs/bugs/2026-10-15-test-all-hub-data-prune-aging-fixtures.md` | step 4, Status line only |

No other file.

## What NOT to Do

- Do NOT edit any test, script or `Makefile`, even if a test fails: report the failure only.
- Do NOT bypass, disable or edit `scripts/tests/tripwire.sh`.
- Do NOT contact the hub, the sandbox, AWS or any cluster; do NOT run `kubectl` yourself.
- Do NOT modify the real `~/.kube/config`; the absent case uses `KUBECONFIG` only.
- Do NOT create a PR, commit, switch branches, or use `--no-verify`.
- Do NOT modify files outside the Files table, including this doc and `memory-bank/`.
