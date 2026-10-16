# Bug: test-all fails on aging hub-data prune fixtures and omits actual BATS diagnostics

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2` (triage 2026-10-15, operator-approved placement)
**Status:** IMPLEMENTED — landed `24c5e960` (hub_data.bats freeze_clock + boundary test 5b; Claude verified 88/88 and mutations M1–M3 red). Was: OPEN — root cause confirmed 2026-10-15.
**Approval:** explicit 2026-10-15 "let's do what you suggest, and you can dispatch to codex" (operator, to fixing this first in v1.43.2)
**Priority:** P2 — blocks the canonical `test-all` release gate despite other tests passing; workaround is targeted investigation and rerun, not suppressing this test
**Severity:** medium
**Origin:** operator, 2026-10-15; `k3dm-test-all-1792063475.log` and Grafana “Failures in selected time range” screenshot

## Symptom and evidence

`./scripts/k3d-manager test all` ran 1,585 BATS cases and exited 1 with exactly one failed case:

```text
not ok 1006 5 prune keeps recent exports and the last passing export
# (in test file scripts/tests/plugins/hub_data.bats, line 443)
# `source_plugin; export DR_TEST_RESULT_EXPORT=20261002T120000Z; run hub_data_prune; [ "$status" -eq 0 ]; ...` failed
make[2]: *** [test] Error 1
```

The test fixture creates snapshot directories `20261009T120000Z`, `20261007T120000Z`, `20261004T120000Z`, `20261002T120000Z`, and `20260928T120000Z`; marks October 2 as the last drill-passing export; and expects:

| Export | Expected |
|---|---|
| 20261009T120000Z | keep (recent / newest) |
| 20261007T120000Z | keep (recent) |
| 20261004T120000Z | prune |
| 20261002T120000Z | keep (last drill-proven) |
| 20260928T120000Z | prune |

The observed BATS output only prints the entire chained assertion; it **does not identify which predicate failed**, nor does it include the actual `hub_data_prune` exit status or output. Adjacent tests for keeping the newest old export, refusing an unreadable results ref, force-pushing snapshots only, manifest validation, and dry-run behavior passed. The 428 blocked tripwire host-tool calls are expected isolation diagnostics, not separate test failures.

## Root-cause hypothesis (confirmed 2026-10-15 — see Diagnosis)

In `scripts/plugins/hub_data.sh`, `hub_data_prune` calculates `now="$(date -u +%s)"` and `cutoff=$((now - K3DM_HUB_DATA_RETAIN_DAYS * 86400))`; a snapshot is kept only if newer than cutoff, newest, or the last passing export. The test uses **fixed October 2026 timestamps** while the runtime clock advances. On October 15, an October 7 fixture may have aged out of the configured retention window; that would make an expected `keep:` turn into `prune:`. Reproduce and inspect actual output before declaring this the cause.

A separate possibility is a return-code failure, snapshot verification failure, or changed retention behavior. Do not assume a production backup was pruned incorrectly based only on this failed unit test.

## Grafana evidence and diagnostics gap

The existing test observability pipeline successfully ingested and displayed:

- **Target / origin:** `test-all-local`
- **Target:** `test-all`
- **Test suite:** `bats`
- **Case:** `1006`
- **Test name:** `5 prune keeps recent exports and the last passing export`
- **Failure reason:** assertion source starting with `source_plugin; export DR_TEST_RESULT_EXPORT=20261002T120000Z; run hub_data_prune; ...`

This confirms attribution and failure ingestion work. However, “Failure reason” is effectively the test's shell source, not observed versus expected output. Investigate whether the test runner can collect **bounded, redacted** actual exit code, stdout/stderr and the specific failed predicate in the per-test failure artifact; surface useful context in the Grafana table or through a linked detail artifact without creating high-cardinality metrics or leaking secrets. Keep this as a **secondary diagnostic scope**; do not make the core prune-fixture fix dependent on a dashboard redesign.

## Investigation and proposed fix

1. Reproduce just the failing BATS test using the current release branch and capture its actual `status` and `output`, including each `keep:` and `prune:` line.
2. Confirm `K3DM_HUB_DATA_RETAIN_DAYS` defaults/overrides and identify precisely which assertion fails.
3. If aging fixtures are the cause, use a controlled/injected clock or compute fixture timestamps relative to a frozen reference date. Ensure the behavior is reproducible regardless of calendar date, timezone, and run time. Prefer controlling `now` in tests over changing production retention policy.
4. Preserve the safety invariants: newest export and last **verified drill-passing** export must never be pruned solely due to age; unverified or malformed retained exports fail closed; no unwanted branch push on error.
5. Split the one-line chained assertion or provide explicit expected/actual diagnostic output so subsequent failures identify the actual mismatch.
6. Validate Grafana per-case failure extraction and determine whether actual/expected details can be captured safely within the existing artifact and exporter contracts.
7. Run targeted `scripts/tests/plugins/hub_data.bats`, related mutation/negative cases, then full `make test` or `./scripts/k3d-manager test all` under tripwire.

## Acceptance criteria

- Test #1006 is repeatable on arbitrary dates; explicitly simulate clock movement across retention boundaries.
- Exact keep/prune expectations match documented five-day (or configured) policy, including protection for newest and last drill-proven snapshots.
- No production data export, pruning, retention, or deletion changes are performed to satisfy a brittle test.
- Failure reports expose an actionable predicate and expected-versus-actual data (redacted, bounded), with at least a demonstrated per-test diagnostic path; do not distort Prometheus cardinality.
- Hub-data test suite and full `test-all` pass, with no weakened or skipped safety assertions.

## Relevant files

- `scripts/tests/plugins/hub_data.bats` — case #1006 fixture and assertions
- `scripts/plugins/hub_data.sh` — `hub_data_prune` cutoff and protection logic
- Test-all BATS result collector / failure artifact exporter / Grafana K3DM Tests dashboard — diagnostic-depth investigation (identify exact paths before changing)

## Evidence location

Operator upload: `k3dm-test-all-1792063475.log`, run artifact `scratch/test-logs/all/20261015-042435.log`; Grafana “Failures in selected time range” screenshot 2026-10-15. No real backup export/prune was executed as part of this bug filing.

## Diagnosis — 2026-10-15

Claude ran a temporary copy of the test (outside the repo) that printed `status` and `output`:

```text
STATUS=0
keep: 20261002T120000Z
keep: 20261009T120000Z
prune: 20260928T120000Z
prune: 20261004T120000Z
prune: 20261007T120000Z
```

Exit 0; four of five decisions match. Only `20261007T120000Z` flipped from `keep` to `prune`. With
`K3DM_HUB_DATA_RETAIN_DAYS=5` its 5-day window closed at 2026-10-12T12:00Z, and the test has failed on
every run since. `hub_data_prune` is correct; the test reads the real clock. No production change.

**Scope split.** The Grafana failure-detail work (actual vs expected in the K3DM Tests dashboard) is
**not** in this fix. It is unscheduled until someone wants it; this fix only makes the failure
message itself say what differed, by printing `status` and `output` before the assertions (BATS shows
a failed test's stdout).

## Fix

Test-only. `scripts/plugins/hub_data.sh` is not edited.

### 1. Add a clock helper — `scripts/tests/plugins/hub_data.bats`

Directly after the closing `}` of `make_prune_fixture()`, add:

```bash

freeze_clock() {
  export DR_TEST_NOW="$1"
  date() { if [[ "$*" == '-u +%s' ]]; then printf '%s\n' "$DR_TEST_NOW"; else command date "$@"; fi; }
}
```

It replaces only the exact call `date -u +%s` that `hub_data_prune` uses for `now`. Every other
`date` call (including `_hub_data_export_timestamp_epoch`, which parses the stamps) still runs the
real `date`.

### 2. Replace test 5

Old:

```bash
@test "5 prune keeps recent exports and the last passing export" {
  make_prune_fixture 20261009T120000Z 20261007T120000Z 20261004T120000Z 20261002T120000Z 20260928T120000Z
  source_plugin; export DR_TEST_RESULT_EXPORT=20261002T120000Z; run hub_data_prune; [ "$status" -eq 0 ]; [[ "$output" == *'keep: 20261009T120000Z'* ]]; [[ "$output" == *'keep: 20261007T120000Z'* ]]; [[ "$output" == *'keep: 20261002T120000Z'* ]]; [[ "$output" == *'prune: 20261004T120000Z'* ]]; [[ "$output" == *'prune: 20260928T120000Z'* ]]
}
```

New (`1791590400` = 2026-10-10T00:00:00Z):

```bash
@test "5 prune keeps recent exports and the last passing export" {
  make_prune_fixture 20261009T120000Z 20261007T120000Z 20261004T120000Z 20261002T120000Z 20260928T120000Z
  source_plugin; freeze_clock 1791590400; export DR_TEST_RESULT_EXPORT=20261002T120000Z
  run hub_data_prune
  printf 'status=%s\n%s\n' "$status" "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *'keep: 20261009T120000Z'* ]]
  [[ "$output" == *'keep: 20261007T120000Z'* ]]
  [[ "$output" == *'keep: 20261002T120000Z'* ]]
  [[ "$output" == *'prune: 20261004T120000Z'* ]]
  [[ "$output" == *'prune: 20260928T120000Z'* ]]
}

@test "5b prune retention boundary follows the clock, not the calendar" {
  make_prune_fixture 20261009T120000Z 20261007T120000Z
  source_plugin; freeze_clock 1791806400
  run hub_data_prune
  printf 'status=%s\n%s\n' "$status" "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *'keep: 20261007T120000Z'* ]]
  freeze_clock 1791806401
  run hub_data_prune
  printf 'status=%s\n%s\n' "$status" "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *'prune: 20261007T120000Z'* ]]
}
```

`1791806400` = 2026-10-12T12:00:00Z, exactly 5 days after `20261007T120000Z`: the export is on the
boundary and kept (`age >= cutoff`). One second later it is pruned. `20261009T120000Z` is the newest
and the default passing export, so it is kept in both runs.

Tests 6, 8 and 9 use `K3DM_HUB_DATA_RETAIN_DAYS=1` with October 2 and 4 fixtures; they only age further
into "old" and are left unchanged.

## Files

- `scripts/tests/plugins/hub_data.bats`

## Rules

Run from the repo root and paste the output:

1. `bats scripts/tests/plugins/hub_data.bats` — all pass, including 5 and 5b.
2. Mutations. Before each, `cp` the file to a snapshot under `$TMPDIR`; after each, restore with `cp`
   and confirm `cmp` is silent. Each must turn the named test red:
   - M1: delete `freeze_clock 1791590400; ` from test 5 → test 5 red (today is after 2026-10-12).
   - M2: in `scripts/plugins/hub_data.sh`, change `(( age >= cutoff ))` to `(( age > cutoff ))` →
     test 5b red.
   - M3: in `scripts/plugins/hub_data.sh`, delete ` || [[ "$stamp" == "$passing" ]]` → test 5 red.
3. After restoring, `git diff --stat` shows only `scripts/tests/plugins/hub_data.bats`.

Do not run `make test`; Claude runs it at land.

## Definition of Done

- [ ] Fix 1 and 2 applied exactly as written.
- [ ] Rule 1 green; M1–M3 each red, then restored (`cmp` silent).
- [ ] Only `scripts/tests/plugins/hub_data.bats` changed.
- [ ] Commit message (Claude commits at land): `test(hub-data): freeze the clock in the prune retention tests`
- [ ] Final message lists every changed file.

## What NOT to Do

- Do NOT edit `scripts/plugins/hub_data.sh` or change retention, prune or export behavior. The
  mutations in Rule 2 are temporary and must be restored.
- Do NOT skip, delete or weaken an assertion in test 5.
- Do NOT run `hub_data_prune`, `hub_data_export` or any hub-data target against a real repo or cluster.
- Do NOT run `make test`, `make test-all` or any live target.
- Do NOT touch the Grafana dashboard or test exporters — split out above.
- Do NOT run `git add`, `git commit` or `git push`; do NOT touch `memory-bank/`.
- Do NOT modify files outside the Files list.
