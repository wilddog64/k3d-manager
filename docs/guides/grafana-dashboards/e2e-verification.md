# E2E Verification (`e2e-verification`)

[← Grafana dashboards index](../grafana-dashboards.md)

Templated on `$service` / `$tier` / `$runner`. Everything is exporter-fed from
`k3dm.k3d.io/e2e-result=true` ConfigMaps.

| Panel | Query |
|---|---|
| Status by runner/service/tier/project | `e2e_last_run_pass{...}` |
| Last success age | `time() - e2e_last_success_timestamp_seconds{...}` |
| Failing runs in window | `count(e2e_run_info{passed="false",...})` |
| Duration trend | `e2e_last_run_duration_seconds{...}` |
| Recent runs | `topk(100, e2e_run_info{...,failure_ratio=~".*%.*"})`; newest first. **Run date** is when the run happened (UTC). **Status now** is `passed`, `still failing`, or `fixed: passed <date>` when a later run of the same tier/service/suite/runner passed, so an old failure is not mistaken for a current one |
| Failure groups / details | `topk(200, e2e_failure_group_info{...})`, `topk(100, e2e_failure_info{...})` |
| Failure trend / causes by service | `sum by (exported_service[, kind]) (e2e_failure_group_info{...})` |
| Top failing specs | `topk(10, sum by (exported_service,file) (e2e_failure_info{...}))` |

Traps:

- **Remote runs can finish, fail informatively, and still publish nothing.**
  `E2E_M2_PUBLISH_BACK_HOST` lives only in the repo `.envrc`, which **launchd never loads** —
  so Slack-triggered (`/k3dm e2e-remote`) and Hermes-triggered runs pass no publish-back
  host and the runner retains the result as `*.publication_pending.json`. The hub then has
  **zero** `k3dm.k3d.io/e2e-result` ConfigMaps and the dashboard is empty even though the
  run produced 45 real failures. OPEN:
  `docs/bugs/2026-09-15-e2e-remote-results-never-reach-grafana.md`.
- **Aggregate-only events make the *detail* panels empty while the summary panels work.**
  Older result ConfigMaps carried only `failed=/total=`; with no per-failure payload the
  exporter falls back to ConfigMap metadata and emits no `e2e_failure_group_info`
  (`docs/issues/2026-09-16-live-e2e-failure-groups-empty.md`).
- A run that fails before any test runs counts as one failure group, `aborted at <phase>`;
  Top failing specs stays empty because no spec ran.
- A table rendering raw label soup instead of columns is a transform problem, not a query
  problem — `docs/issues/2026-08-25-e2e-grafana-table-raw-labels.md`.
