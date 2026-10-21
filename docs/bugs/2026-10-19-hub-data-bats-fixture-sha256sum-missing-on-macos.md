# Bug: hub-data Bats recovery fixtures fail on macOS because sha256sum is unavailable

**Filed:** 2026-10-19 (operator-provided live `make test` output; ChatGPT investigation)
**Branch:** `k3d-manager-v1.43.5`
**Status:** OPEN — reproduced in a live macOS test run; fix and post-fix verification pending
**Approval:** operator requested review and dispatch on 2026-10-21; scope is test-fixture portability only
**Priority:** P2 — recovery-preflight safety assertions are never reached, and offline `make test` fails on the primary macOS runner
**Severity:** Medium — test coverage and CI/observability reliability are impaired; no evidence here that production hub recovery itself is broken
**Component:** `scripts/tests/plugins/hub_data.bats`, `make test` / `test-all` Bats dispatcher
**Origin:** 2026-10-19 ~07:38 PDT operator-shared live Bats failure excerpt; cloud-bridge `make-test` request `20261019T143301Z-make-test`, webhook job `7e59e3ff`
**Related:** `memory-bank/progress.md` (2026-10-11 round-1 review already noted `sha256sum` is absent on stock macOS); `docs/plans/v1.43.1-hub-data-recover.md`

## Symptom

On macOS, several `recover preflight` tests fail in fixture setup before their recovery logic or assertions run. The operator-supplied output includes:

```text
# (from function `make_fixture' in file scripts/tests/plugins/hub_data.bats, line 125,
#  in test file scripts/tests/plugins/hub_data.bats, line 898)
#   `make_fixture; source_plugin' failed with status 127
# scripts/tests/plugins/hub_data.bats: line 126: sha256sum: command not found
not ok 1162 recover preflight: absent hub skips validation and still asks approval
...
not ok 1168 recover preflight: a failed k3d listing refuses instead of treating the hub as absent
# (from function `make_fixture' in file scripts/tests/plugins/hub_data.bats, line 125,
#  in test file scripts/tests/plugins/hub_data.bats, line 967)
#   `make_fixture; source_plugin' failed with status 127
# scripts/tests/plugins/hub_data.bats: line 126: sha256sum: command not found
```

The adjacent preflight test before #1162 also reports this fixture error. Case numbers are suite-order-dependent; use test names and the fixture line rather than relying on numeric identifiers.

## Root cause

`make_fixture()` generates a checksum manifest using an unconditional GNU command:

```bash
(cd "$root" && sha256sum *.age pv-pvc.yaml inventory.json > SHA256SUMS)
```

Stock macOS provides `shasum -a 256`, not `sha256sum`. Bash exits 127 before `source_plugin` and the test assertion execute. This is a test-fixture portability defect, distinct from a confirmed bug in the actual disaster-recovery workflow.

This issue was already noticed during the 2026-10-11 hub-recovery review, but is still present in the tested source.

## Expected behavior

The fixture emits a GNU-compatible `SHA256SUMS` manifest across macOS and Linux, and every recovery-preflight test exercises its real guard/approval path. A missing checksum utility must fail loudly rather than create a misleading green test or an empty manifest.

## Proposed fix

1. In `scripts/tests/plugins/hub_data.bats`, use a portable SHA-256 manifest writer: prefer `sha256sum` when available, else `shasum -a 256`; fail explicitly when neither is available. Keep the current filename list and standard two-space checksum format.
2. Check other `.bats` fixtures in `scripts/tests/` for the same nonportable assumption, but keep unrelated production checksum behavior outside this fix unless proven affected.
3. Do not skip/relax the recovery safety tests, install GNU coreutils as an undocumented prerequisite, or modify production recovery logic merely to satisfy the fixture.
4. Verify the generated manifest has correct checksums for all fixture files (including `*.age`, `pv-pvc.yaml`, `inventory.json`) and works with the verification path used by `hub_data.sh`.

## Acceptance

```yaml
must:
  - id: M1
    text: hub_data.bats fixtures generate a valid SHA256SUMS manifest on stock macOS using available tools; no sha256sum command-not-found (exit 127).
  - id: M2
    text: The same fixture and checksum verification run on Linux where sha256sum is available.
  - id: M3
    text: Recovery-preflight tests including absent-hub approval and failed-k3d-list refusal reach and assert the intended behavioral gates.
  - id: M4
    text: A missing checksum implementation causes an explicit failure, not a skipped test, success status, or silently incomplete manifest.
must_not:
  - id: N1
    text: Do not change production hub recovery logic, bypass checksum validation, or weaken preflight safety guards.
  - id: N2
    text: Do not require GNU coreutils installation on macOS or mask a fixture failure as an expected skip.
evidence:
  - id: E1
    proves: [M1, M3, M4, N1, N2]
    kind: offline
    text: Run bats scripts/tests/plugins/hub_data.bats on macOS; capture named recovery-preflight cases, exit code, and summary. Demonstrate the no-checksum-tool branch fails clearly.
  - id: E2
    proves: [M2, M4]
    kind: offline
    text: Exercise the checksum helper with sha256sum available in Linux and verify manifest contents using standard checksum validation.
  - id: E3
    proves: [M1, M3]
    kind: live
    text: Re-run the Mac-hosted make test or scheduled test-all, confirm these formerly fixture-blocked tests pass, and record the resulting run in K3DM Tests; investigate any unrelated remaining failures independently.
interface:
  - scripts/tests/plugins/hub_data.bats (make_fixture, SHA256SUMS generation)
```

## Verification status

OPEN. The 2026-10-19 cloud-bridge job `7e59e3ff` was still running at the last checked status (07:37:18 PDT). Reproduced in Slack job `be53f685` on 2026-10-20 and again in `c30366d6`: hub-data fixture setup failed at `scripts/tests/plugins/hub_data.bats:126` with `sha256sum: command not found` (exit 127). In `c30366d6`, named affected tests included hub-data restore/export/prune and recovery-preflight assertions, all blocked in fixture setup before their intended assertions. The full `make test-all` reported 1,747 cases / 56 failures / exit 2. This remains a test-fixture portability defect; no fix was attempted. The 56 failures span separate test areas and are not all attributed to this issue; 55 non-`sha256sum` failures remain untriaged in `docs/issues/2026-10-20-slack-make-job-id-live-verification-still-omits-ids.md`. Verbatim latest evidence:

```text
not ok 1171 recover preflight: a failed k3d listing refuses instead of treating the hub as absent
# (from function `make_fixture' in file scripts/tests/plugins/hub_data.bats, line 125,
#  in test file scripts/tests/plugins/hub_data.bats, line 967)
#   `make_fixture; source_plugin' failed with status 127
# /Users/cliang/src/gitrepo/personal/k3d-manager/scripts/tests/plugins/hub_data.bats: line 126: sha256sum: command not found
[k3dm-test-metrics] 1747 cases, 56 failed
make: *** [test-all] Error 2
```

The complete local run transcript is `scratch/test-logs/all/20261020-171339.log`. Update Status, verification timestamp, and live-evidence metadata only after a real fix and matching verification.
## Files

- `scripts/tests/plugins/hub_data.bats`
