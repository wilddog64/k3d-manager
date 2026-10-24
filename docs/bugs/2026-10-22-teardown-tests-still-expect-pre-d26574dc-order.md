# Bug: six teardown tests still expect the pre-`d26574dc` hub-deregister order

**Filed:** 2026-10-22 (Claude, from a full BATS run on `k3d-manager-v1.43.5`)
**Status:** VERIFIED 2026-10-24 (offline-only change; E1 is the whole proof) — FIXED `99048395` — 77/77 bats green (11 acceptance, 32 k3s-aws, 34 cluster-down); offline-only change
**Priority:** P3 — test-only; the suite is red on the release branch, the code is correct
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "yes, go for that proposal" (file for Luna)
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/tests/bin/cluster_down_acceptance.bats`; `scripts/tests/lib/k3s_aws_provider.bats`
**Related:** `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md` (fix `d26574dc`, LIVE-VERIFIED)

## Symptom

`bats` on `k3d-manager-v1.43.5` fails six tests, all from v1.43.4 or earlier:

- `cluster_down_acceptance.bats`: the three `M2/N1/N2: acg_teardown rc2/rc3 ... cleanup still ran`
  tests and `M3/N2: invalid credentials: acg_teardown not called ...`. All fail in
  `assert_cleanup_ran`, which requires `delete secret cluster-ubuntu-k3s` in the kubectl log.
- `k3s_aws_provider.bats`: `_provider_k3s_aws_destroy_cluster --confirm runs acg_teardown`
  asserts `[stub] deregister` prints **before** `[stub] acg_teardown`.
- `k3s_aws_provider.bats`: `_k3s_aws_deregister_cluster is idempotent when hub objects are absent`
  stubs `kubectl() { return 1; }` and expects exit 0.

## Root cause

`d26574dc` changed the contract on purpose (operator-approved, live-verified 2026-10-21):

1. AWS teardown runs **first**; hub deregistration runs only after it is confirmed.
2. When AWS teardown fails or cannot be verified (rc2/rc3, invalid credentials), the hub
   registration and `ApplicationSet/observability-acg` are **preserved**, with the warning
   `Preserving hub registration and observability-acg because AWS teardown was not confirmed.`
   Local cleanup (e.g. the vault port-forward pid) still runs.
3. `_k3s_aws_deregister_cluster` also deletes `applicationset observability-acg --ignore-not-found`
   and returns 1 if that command fails.

`d26574dc` updated `scripts/tests/bin/cluster_down.bats` but not these two files.

## Fix

Rewrite the six tests to the current contract. No production code changes.

- **F1.** `cluster_down_acceptance.bats`: keep the name `assert_cleanup_ran` but make it check local cleanup only
  (`vault-pf.pid` gone), and add `assert_hub_cleanup_ran` for hub cleanup. In the four failure-path tests assert local cleanup ran,
  `delete secret cluster-ubuntu-k3s` is **absent** from the kubectl log, and the output contains
  `Preserving hub registration`. Keep every other assertion (UNVERIFIED summary,
  `assert_no_bare_verified`, no `delete-stack` where present today). Add hub-cleanup-present
  assertions to the rc0 M1 test. Exit codes: rc2/rc3 exit 1, and so does invalid credentials —
  `d26574dc` sets `_cloud_teardown_failed=1` there, so the M3/N2 test title and assertion change from
  exit 0 to exit 1 (correction added 2026-10-23 at review).
- **F2.** `k3s_aws_provider.bats` destroy test: assert `[stub] acg_teardown` prints **before**
  `[stub] deregister`. Add a test: when the `acg_teardown` stub returns 1,
  `_provider_k3s_aws_destroy_cluster --confirm` returns non-zero and `[stub] deregister` is absent.
- **F3.** `k3s_aws_provider.bats` idempotent test: model "objects absent" the way real kubectl
  behaves — the stub returns 0 for `delete ... --ignore-not-found` and empty output for `get`,
  and the test asserts exit 0 and that `delete applicationset observability-acg --ignore-not-found`
  was called. Add a separate test: a kubectl that fails every call makes the function return
  non-zero (hub unreachable is an error, not "absent").
- **F4.** `CHANGELOG.md` entry.

## Files

- `scripts/tests/bin/cluster_down_acceptance.bats`
- `scripts/tests/lib/k3s_aws_provider.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: All tests in cluster_down_acceptance.bats and k3s_aws_provider.bats pass on k3d-manager-v1.43.5.
  - id: M2
    text: On a failed or unverified AWS teardown, cluster-down still performs local cleanup and prints the preserving-hub-registration warning.
  - id: M3
    text: Provider destroy runs acg_teardown before _k3s_aws_deregister_cluster, and skips deregister when teardown fails.
  - id: M4
    text: _k3s_aws_deregister_cluster exits 0 when the hub objects are already absent and calls delete applicationset observability-acg --ignore-not-found.
must_not:
  - id: N1
    text: On a failed or unverified AWS teardown, cluster-down must not delete secret cluster-ubuntu-k3s (red if bin/cluster-down is reverted to the pre-d26574dc order).
  - id: N2
    text: Provider destroy must not call deregister when acg_teardown fails (red against the pre-d26574dc k3s-aws.sh).
  - id: N3
    text: _k3s_aws_deregister_cluster must not report success when every hub kubectl call fails.
  - id: N4
    text: No file under bin/ or scripts/lib/ or scripts/plugins/ changes.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    text: bats on both files green; N1 and N2 red with bin/cluster-down and scripts/lib/providers/k3s-aws.sh checked out at d26574dc^ (on a temp copy, never the live tree).
interface:
  - bin/cluster-down --confirm
  - _provider_k3s_aws_destroy_cluster --confirm (scripts/lib/providers/k3s-aws.sh)
  - _k3s_aws_deregister_cluster (scripts/lib/providers/k3s-aws.sh)
```

## Definition of Done

- [ ] F1–F4 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 and N2 shown red against the pre-`d26574dc` code.
- [ ] `bats scripts/tests/bin/cluster_down_acceptance.bats scripts/tests/lib/k3s_aws_provider.bats scripts/tests/bin/cluster_down.bats` green.
- [ ] Commit: `test(teardown): align cluster-down and k3s-aws tests with confirmed-teardown-first order`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT change `bin/cluster-down`, `scripts/lib/providers/k3s-aws.sh` or any production code to make a test pass.
- Do NOT delete a test; rewrite it to the current contract.
- Do NOT remove any line beginning with `assert_` from a BATS file: `_agent_audit` blocks it and has no BATS escape (the `allow assert-removed` marker covers Python only). Keep helper names and call lines; change helper bodies and add new assertions beside them. (Corrected 2026-10-23 at review.)
