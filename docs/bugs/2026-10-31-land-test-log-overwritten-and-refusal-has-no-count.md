# Bug: a retried land overwrites the failed test log, and a refused run shows no test count

**Status:** OPEN
**Priority:** P3
**Approval:** operator, 2026-10-31 ("go ahead to file two gaps as a separate small bug for v1.43.13")
**Filed:** 2026-10-31
**Detected by:** Claude, answering the operator's question whether a failed case among a land's 101
tests reaches the Agent Dispatch "Per run evidence" Log link
**Affected:** `bin/k3dm-codex-dispatch` (`land`); `bin/k3dm-dispatch-metrics` (`_evidence_details`);
`bin/k3dm-dispatch-logs`
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-31-ci-reds-reproducible-locally-no-fast-gate.md` (`land` will also run
the fast gate; its output goes into the same per-attempt log)

## Observed failure

`land` captures the whole `--test` output, so a failing test is recorded. Two gaps hide it afterwards:

1. **The failed log is overwritten.** `bin/k3dm-codex-dispatch:806` writes `"$run/land-test.log"` with
   `>` on every attempt. When a land is refused and a later land of the same slug passes, the refused
   run's row on the "Per run evidence" panel links to the same file, which now holds the passing output.
   The failing test's output is gone, from the Mac and from Loki (`bin/k3dm-dispatch-logs:162` ships
   the same fixed path).
2. **A refused run has no count.** `bin/k3dm-dispatch-metrics:584-597` counts TAP `ok`/`not ok` and the
   pytest summary only when the evidence is `land-test.log` (an accepted land). A refused land's Result
   cell shows the raw label `land_refused.tests`, so the operator cannot see how many tests failed, or
   which one, without opening the log.

## Root cause

The run directory holds one fixed-name log per slug, and the evidence model assumes one land attempt per
slug. The summary parser was written for accepted lands only.

## Fix

1. **`bin/k3dm-codex-dispatch land`:** write each attempt to `"$run/land-test.<N>.log"`, where `N` is
   1 + the number of existing `land-test.*.log` files in `$run`. Keep `"$run/land-test.log"` as a
   symlink to the newest attempt, so existing readers and the refusal message still work. Record the
   attempt's file name in the ledger event as `validation` on `land` (it already carries the path) and
   as a new `validation` field on `land_refused` with reason `tests`. The refusal message names the
   per-attempt file.
2. **`bin/k3dm-dispatch-metrics _evidence_details`:** resolve each run outcome's log from its ledger
   event's `validation` field; fall back to `land-test.log` only for events written before this fix.
   Compute the TAP and pytest summary for refused runs too, and for a refused run append the first
   failing test: the first `not ok` line's description, or the first pytest `FAILED` node id, cut to
   80 characters (e.g. `100/101 ok; first fail: ok 57 ...`). Apply the existing redaction before the
   label.
3. **`bin/k3dm-dispatch-logs`:** ship the file named by each event's `validation` field, falling back to
   `land-test.log` for old events. Never ship the same attempt twice.
4. Docs: update `docs/guides/grafana-dashboards/k3dm-agent-dispatch.md` with
   per-attempt logs and the refusal count. `CHANGELOG.md` entry.

## Files

- `bin/k3dm-codex-dispatch`
- `bin/k3dm-dispatch-metrics`
- `bin/k3dm-dispatch-logs`
- `scripts/tests/bin/codex_dispatch.bats`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/bin/test_dispatch_logs.py`
- `docs/guides/grafana-dashboards/k3dm-agent-dispatch.md`
- `CHANGELOG.md`

## What NOT to do

- Do not change the dashboard JSON or panel queries; the metric labels keep their names.
- Do not delete or rename existing `land-test.log` files in old run directories.
- Do not put unredacted log text in a metric label.

## Acceptance

```yaml
must:
  M1: a refused land followed by a passing land of the same slug leaves two log files, and the refused attempt's file still holds its failing output
  M2: each run outcome's evidence path points at its own attempt's file
  M3: a refused run's Result shows the TAP or pytest count and the first failing test
  M4: the log shipper sends each attempt's log once
must_not:
  N1: a passing land never overwrites a refused attempt's log
  N2: ledger events written before the fix still resolve to land-test.log and keep today's summary
  N3: the first-failing-test text never carries a value the existing redaction removes (home path, token-shaped string)
evidence:
  E1:
    proves: [M1, N1]
    kind: offline
    intent: >-
      You will see a land whose --test fails, then a land of the same slug that passes, leave
      land-test.1.log with the not ok line and land-test.2.log with the pass. It failed if the first file is
      gone or holds the passing output, or if the test passes against today's dispatch script.
    what: bats scripts/tests/bin/codex_dispatch.bats
  E2:
    proves: [M2, M3, N2, N3]
    kind: offline
    intent: >-
      You will see the metrics output give the refused run "100/101 ok; first fail: ..." with its own log
      path, the accepted run its own path, and an old-format ledger still read as before; a home path in the
      failing line is redacted. It failed if the refused run still shows land_refused.tests.
    what: pytest scripts/tests/bin/test_dispatch_metrics.py
  E3:
    proves: [M4]
    kind: offline
    intent: >-
      You will see the shipper, pointed at a stub Loki, send both attempts' logs once each across two runs.
      It failed if an attempt is missing or sent twice.
    what: pytest scripts/tests/bin/test_dispatch_logs.py
  E4:
    proves: [M1, M3]
    kind: live
    intent: >-
      You will see the first v1.43.13 land that is refused and then accepted show two rows on the Per run
      evidence panel, each opening its own log, the refused one with a count. It failed if both open the same log.
    what: Claude reads the Agent Dispatch dashboard on the M5 hub after such a land
interface:
  - bin/k3dm-codex-dispatch land --slug SLUG --test CMD
  - bin/k3dm-dispatch-metrics (Prometheus text output, evidence labels)
  - bin/k3dm-dispatch-logs (ships to Loki)
  - ledger events land and land_refused (field validation)
```

**Intent approved:** pending
