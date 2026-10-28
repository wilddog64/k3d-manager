# Empty Log labels and blanket unknown attribution — findings and correction

Operator screenshots show eight earlier run attempts with outcomeunknown, Resultnone, emptyLog, plus missing coordinator/landing identities. No screenshots exported. Coordinator investigated, communicated intended existing-field corrections before editing, then implemented `0077b7b8f6cbc13b76a07c63bbd1b9286afa36f4`. No new table/panel, ledger/history/backfill, inferred model or measured cost.

## Actual published evidence

Read-only Pushgateway7d/v1.43.9 outcome counts:

```json
{"failed":2,"unknown":14,"accepted":19}
```

Selected actual run evidence shows earlier attempts alongside later accepted runs:

```text
app-cve-scan-fail-closed run1: unknown / none / empty evidence_path
app-cve-scan-fail-closed run2: accepted / land-test.log / 45/45 ok
independent-heartbeats-luna run1: unknown / none / empty evidence_path
independent-heartbeats-luna run2: accepted / land-test.log / 3/3 ok; 136 passed
plans-dispatch-status-reconcile-luna run1/run2: unknown / none / empty evidence_path
plans-dispatch-status-reconcile-luna run3: accepted / land-test.log / 38/38 ok; 111 passed
primary-coordinator-handoffs-luna run1: unknown / none / empty evidence_path
primary-coordinator-handoffs-luna run2: accepted / land-test.log / 124/124 ok; 136 passed
```

Renderer marks accepted only when landed validation passed and landed tree matches the attempt. Earlier exit0 attempts lacking that matching evidence fall to unknown/none. This does not mean the entire task failed or no logs exist. Field links were configured, but empty evidence_path rendered no visible clickable text: a real UI defect. No count or success inferred from screenshots alone.

Read-only direct Loki query for accepted app-cve-scan-fail-closed/run2 over7days, limit1, actual output (no raw log line exported):

```json
{
  "query_exit": 0,
  "status": "success",
  "selected_slug": "app-cve-scan-fail-closed",
  "selected_run": 2,
  "streams": 1,
  "returned_log_lines": 1,
  "limit": 1
}
```

Thus at least this accepted run has actual retained log data, independently of table link rendering. Not a claim every run has logs or that browser navigation succeeded.

Published identity counts:19worker identities openai/gpt-6-luna(reported), one historical worker_history openai/gpt-6.1-sol(reported).19each legacy/primary/acting/landing model identities displayedunknown;19landingactorname unknown. Source/selected ledger inspection confirms missing/unreported declarations in original tasks. Newer startup-log-noninteractive-cells records coordinatorvendoropenai/modelunknown and landingactorcodex/vendoropenai/modelunknown; they must not be guessed for old tasks. Published selection did not include that newer task at this check, so generation/refresh is a separate prerequisite. Renderer also collapsed explicitly knownvendor to unknown whenever modelunknown: reproduced real display bug. Exact current coordinator model is not supplied by this environment; no inference fromworker model.

## Communicated correction

Only blank/null Log labels map to Open run evidence; their existing link remains valid and targets the existing log/availability view. Nonempty file paths untouched. Existing attempt outcomeunknown displays unverified, Resultnone displays No landing-test evidence recorded. Raw metrics, classifications and history unchanged. Coordinator/primary/acting/landing(and unknown worker) displayunknown maps to not recorded; known identity text untouched. Corrected legacy Coordinator matcher to the actual existing renamed Coordinator(legacy) field. Partially recorded vendor retains vendor/model not recorded(status); unknownmodel remains unknown in its metric label. No cost/source/identity invented.

Native Grafana11.4 value mapping support reviewed at [valueMappings](https://github.com/grafana/grafana/blob/v11.4.0/packages/grafana-data/src/utils/valueMappings.ts): empty-string value and null special mappings are supported. This fixes the visible label, without adding a table or plugin. Same30panels retained. Existing log query/UID unchanged.

## Red and green tests

New partial-identity regression before implementation:

```text
F                                                                        [100%]
=================================== FAILURES ===================================
_____ test_partial_identity_keeps_recorded_vendor_without_inventing_model ______

    def test_partial_identity_keeps_recorded_vendor_without_inventing_model():
        output = dispatch_metrics.render([
            event(1, "start", "partial-identity", agent="codex",
                  coordinator_identity={"vendor": "openai", "model": "unknown",
                                        "source": "declared", "status": "declared"}),
            event(2, "codex_exit", "partial-identity", exit=0, tokens=10),
            event(3, "land", "partial-identity"),
        ], 0, 100)
        lines = _identity_lines(output, "coordinator")
        assert len(lines) == 1
        assert 'vendor="openai"' in lines[0] and 'model="unknown"' in lines[0]
>       assert 'display="openai/model not recorded (declared)"' in lines[0]
E       assert 'display="openai/model not recorded (declared)"' in 'k3dm_dispatch_model_identity{window="1d",version="9.9.9",slug="partial-identity",agent="codex",repo="k3d-manager",role="coordinator",vendor="openai",model="unknown",source="declared",status="declared",display="unknown"} 1'

scripts/tests/bin/test_dispatch_metrics.py:2176: AssertionError
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_partial_identity_keeps_recorded_vendor_without_inventing_model
1 failed, 138 deselected in 0.58s
```

New empty-link/unrecorded attribution regressions before implementation:

```text
1..2
not ok 1 agent dispatch: blank evidence paths remain visible clickable links and gaps are explicit
# (in test file scripts/tests/plugins/agent_dispatch_dashboard.bats, line 648)
#   `[ "$status" -eq 0 ]' failed
# Last output:
# Traceback (most recent call last):
#   File "<stdin>", line 5, in <module>
# KeyError: 'mappings'
not ok 2 agent dispatch: unrecorded attribution is labeled without overwriting known identities
# (in test file scripts/tests/plugins/agent_dispatch_dashboard.bats, line 664)
#   `[ "$status" -eq 0 ]' failed
# Last output:
# Traceback (most recent call last):
#   File "<stdin>", line 6, in <module>
# KeyError: 'mappings'
```

Final Python output:

```text
........................................................................ [ 51%]
...................................................................      [100%]
139 passed in 16.21s
```

Full final BATS output:

```text
1..30
ok 1 agent dispatch dashboard: valid ConfigMap JSON and datasource
ok 2 agent dispatch dashboard: every queried metric is exported
ok 3 agent dispatch dashboard: Claude context and compaction row panels exist below existing rows
ok 4 agent dispatch dashboard: landing success aggregates both sides
ok 5 agent dispatch dashboard: panel rectangles do not overlap
ok 6 agent dispatch dashboard: Codex API cost shows priced total and excluded sessions
ok 7 agent dispatch dashboard: per-spec panels use readable units and grouped targets
ok 8 agent dispatch dashboard: final exit gap and operator coverage are exposed
ok 9 agent dispatch dashboard: window is a query over the exported scopes and defaults to 7d
ok 10 agent dispatch dashboard: rework rate stat reads the selected window
ok 11 agent dispatch dashboard: verified delivery stats use exported metrics without overlap
ok 12 agent dispatch dashboard: stat and bar gauge panels use explicit colours
ok 13 agent dashboards: panel ids exactly match the pre-split dashboard and assigned groups
ok 14 agent dashboards: panel targets, fieldConfig and options match the pre-split fixture
ok 15 agent dashboards: each dashboard has unique panel ids and no overlapping rectangles
ok 16 agent dashboards: all dashboards have the tag-based Agents link
ok 17 agent dashboards: Activity has three time windows and Dispatch and Cost keep the query variable
ok 18 agent activity: Claude row fills the width and bar gauge names read beside each bar
ok 19 agent dispatch: run outcomes read beside each bar, first-pass verification bars with fixed fonts sit beside per run evidence, and each slug links to its spec
ok 20 agent dispatch: failed startup evidence is local-only and the Loki link is scoped to shipped logs
ok 21 agent dispatch: per spec shows which agent landed each spec
ok 22 agent dispatch dashboard: Log opens the filtered run log dashboard
ok 23 agent cost: Claude tokens by kind splits the selected window by cache kind
ok 24 agent cost: daily Claude tokens and cost panels split by kind
ok 25 agent dashboards: labels and titles stay readable and release-only stats say why they are empty
ok 26 agent dispatch dashboard: Per spec exposes unknown worker and coordinator identities
ok 27 agent dispatch dashboard: Per spec shows handoff and measured cost fields within width budget
ok 28 agent dispatch dashboard: Per spec spans the full width and its columns fit without scrolling
ok 29 agent dispatch: blank evidence paths remain visible clickable links and gaps are explicit
ok 30 agent dispatch: unrecorded attribution is labeled without overwriting known identities
```

Ruff:

```text
All checks passed!
```

Diffcheck, actual staged lint/audit/checkpoint hooks passed. No shell implementation changed; ShellCheck not applicable. Previous unrelated curated failures not rerun or claimed resolved. No production metric PUT, ConfigMap apply, service restart, browser click, raw transcript export or screenshot archival by coordinator. Pending: operator make dispatch-metrics to publish latest renderer/ledger facts, then apply only Agent Dispatch ConfigMap and fully reload existing dashboard. Verify visible Open run evidence on previously blank row; supported log output check remains separate. No new layout change.

## Operator rendering check passed

Operator supplied updated Per run evidence screenshot and explicitly reported “fixed now”. Visible rows confirm accepted webhook-incident-doctor-luna/run3 retains its log-path hyperlink and5/5ok;21passed summary. Earlier doctorrun1/run2 display unverified, No landing-test evidence… and clickable Open run evidence labels. Historical key-cache/-retry exit127 rows retain failed state/local-only result and log hyperlinks. Single original table visible; no duplicate table introduced. No image copied/exported, consistent with prior artifact rejection.

This establishes successful table rendering of0077b7b8. The screenshot does not show a destination page or log contents. Next single operator check: click the accepted webhook-incident-doctor-luna/run3 Log and confirm existing Agent Run Log page displays test output. Local-only availability-heading navigation can follow separately. Previously direct Loki read independently established retained output for accepted app-cve-scan-fail-closed/run2, not this browser click. No new code/runtime mutation/tests; prior139Python/30BATS gates retained. Historical missing attribution remains not recorded; no guessed backfill.
