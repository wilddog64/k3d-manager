# Bug: CI lint red on the release branch: repo-sync LaunchAgent has no hub classification, and the hub-sync test breaks under a parent make

**Status:** VERIFIED 2026-11-11 — CI run 42952933807 on 446d2c49: lint success, alertmanager-behaviour success (E2). Was: LANDED 2026-11-11 367d6caa — Claude (operator: "go ahead"): repo-sync classified in hub-local.list; hub-sync test passes --no-print-directory. Offline: Linux MAKELEVEL=1 21/21, macOS 209/209, rc 0
**Priority:** P2 — CI lint is red on `k3d-manager-v1.43.15`, which blocks the release PR gate; the product is unaffected (test registry and test harness only); no workaround short of the fix
**Introduced by:** `f310b4d4` (v1.43.15, checkout auto-sync): added `com.k3d-manager.repo-sync.plist.tmpl` and the hub-sync test
**Should have been caught by:** offline test — both suites were run only on macOS with bats invoked directly; CI runs them under `make test-bin` on GNU make 4
**Severity:** low — no runtime behaviour changes; the release cannot pass its CI gate until fixed
**Approval:** operator 2026-11-11: "ci failed" (report of run 42947911553)
**Intent approved:** operator 2026-11-11: "go ahead"
**Prior art:** `docs/bugs/2026-11-10-repo-sync-reports-zero-behind-for-diverged-checkout.md` — read, different root cause; `docs/bugs/2026-11-09-offline-test-all-red-on-m4-four-root-causes.md` — read, does not name these tests (`make find-similar-docs` not run)
**Filed:** 2026-11-11
**Detected by:** operator (GitHub CI email); diagnosed by Claude
**Affected:** `scripts/etc/machine/hub-local.list`, `scripts/tests/bin/repo_sync.bats`
**Branch:** `k3d-manager-v1.43.15`
**Release:** v1.43.15
**Assigned:** Claude

## Observed

CI run 42947911553 (`b5c6c621`) and 42939374114 (`7673807a`), job lint, both red. No CI run between `f310b4d4` and `b5c6c621` completed green:

    not ok … M4: every launchd template label has exactly one hub classification
    # repo-sync has 0 classifications
    not ok 1018 hub-sync prints the remote line and warns but succeeds on ssh failure
    # (in test file scripts/tests/bin/repo_sync.bats, line 386)

## Root cause

1. **Unclassified label.** `agent_classification.bats` requires every `scripts/etc/launchd/*.plist.tmpl` label to appear in exactly one of `hub-local.list`, `hub-singletons.list` or `not-installed.list`. `f310b4d4` added `repo-sync` to `agents.{hub,worker,console}.list` (machine setup installs it on every machine) and gave it no class.
2. **Sub-make banner.** CI runs bats from `make test-bin`, so `MAKELEVEL` is set when the test runs `"$REAL_MAKE" -f Makefile hub-sync`. GNU make 4 then prints `make[1]: Entering directory '…'` before the output and `Leaving directory` after, so the "starts with `hub `" match and the one-line count fail. macOS make 3.81, and bats run directly, print no banner. Reproduced in `ubuntu:24.04` (GNU make 4) with `MAKELEVEL=1`; captured output, 2026-11-11:

        make[1]: Entering directory '/w'
        hub f18cc7aeca6e: main at c911aa3 (updated); deploy pending: platform-ops; deploy/hub c911aa3; promote backlog: 0
        make[1]: Leaving directory '/w'

## Fix

1. `scripts/etc/machine/hub-local.list`: add `repo-sync|install-repo-sync|Checkout fast-forward; every machine runs its own`. It is per-machine and installed by machine setup, as `vault-port-forward` is; it is not a cutover singleton (`hub-singletons.list` is read by `bin/hub-new` and `bin/hub-cutover`, which would install it at cutover) and not `not-installed` (machine setup does install it).
2. `scripts/tests/bin/repo_sync.bats`: both `hub-sync` invocations pass `--no-print-directory` (supported by make 3.81 and 4.x).

## Contract readers

- `hub-local.list`: readers are tests only (`git grep` outside docs: no production reader). `agent_classification.bats` changes (now passes). No writer.
- `hub-singletons.list` (`bin/hub-new:23`, `bin/hub-cutover:6`) and `not-installed.list` (machine-setup tests): unchanged.
- `make hub-sync` (`Makefile:55-59`): unchanged; only the test's invocation of it changes.

## Acceptance

```yaml
must:
  - id: M1
    text: "agent_classification.bats passes with repo-sync classified exactly once"
  - id: M2
    text: "repo_sync.bats hub-sync test passes when run with MAKELEVEL=1 under GNU make 4, and when run directly under macOS make 3.81"
must_not:
  - id: N1
    text: "repo-sync appears in hub-singletons.list (it would be installed at cutover)"
  - id: N2
    text: "the hub-sync test passes on pre-fix code under GNU make 4 with MAKELEVEL=1 (shown red 2026-11-11 in ubuntu:24.04)"
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: "the two failing CI tests pass on a Linux box set up like CI and on the Mac, and repo-sync is filed as a per-machine agent, not one the hub moves at cutover"
  - id: E2
    proves: [M1, M2]
    kind: live
    intent: "the next CI run on the release branch shows the lint job green"
interface:
  - "bats scripts/tests/bin/agent_classification.bats scripts/tests/bin/repo_sync.bats, in ubuntu:24.04 with MAKELEVEL=1 and on macOS"
```

## Evidence so far (2026-11-11, Claude)

- Pre-fix: classification red on macOS; hub-sync red in `ubuntu:24.04` with `MAKELEVEL=1` (output above), green on macOS.
- Post-fix: `ubuntu:24.04`, `MAKELEVEL=1 bats repo_sync.bats agent_classification.bats`: 21/21, rc 0. macOS, `tripwire.sh bats` repo_sync + agent_classification + machine_setup + machine_setup_acceptance + hub_new: 209/209, rc 0.
