# Cloud-bridge test-all runs do not publish results to the Grafana test dashboard

**Filed:** 2026-10-06
**Release / branch:** v1.41.0 / `k3d-manager-v1.41.0`
**Status:** OPEN
**Severity:** Medium — remote test execution is visible through job-status but leaves dashboard results stale
**Component:** cloud-bridge / webhook Make jobs / offline test metrics

## Observed execution

The operator requested a real `make-test-all` run through cloud-bridge.
Request ID: `20261006T163821Z-make-test-all`.
Job ID: `ccc20dc9`.

[Initial response](https://github.com/wilddog64/k3d-manager/blob/cloud-requests/responses/20261006T163821Z-make-test-all.json):

```json
{"action": "make-test-all", "body": {"job_id": "ccc20dc9", "status": "queued"}, "completed_at": "2026-10-06T16:39:29.830712Z", "http_status": 202, "id": "20261006T163821Z-make-test-all", "schema": 1, "status": "ok"}
```

[Follow-up response](https://github.com/wilddog64/k3d-manager/blob/cloud-requests/responses/20261006T163950Z-job-status.json):

```json
{"action": "job-status", "body": {"job_id": "ccc20dc9", "output": "", "status": "running"}, "completed_at": "2026-10-06T16:40:09.346868Z", "http_status": 200, "id": "20261006T163950Z-job-status", "schema": 1, "status": "ok"}
```

This proves request delivery, acceptance, and a running webhook job. The terminal test result
was not available when filing, and the live dashboard/Pushgateway was not inspected.

## Code evidence and root cause

- `scripts/lib/webhook/cloud_actions.py` maps `make-test-all` to the fixed Make target `test-all`.
- `scripts/lib/webhook/make_targets.py` permits `test-all` at reader tier with a 1800s timeout.
- `Makefile` defines `test-all: test test-bin test-python`; it runs suites without publishing metrics.
- Only `make test-metrics` captures the full test-all log and wall-clock duration and calls
  `bin/k3dm-test-metrics` to publish test metrics to Pushgateway.
- `scripts/lib/webhook/lifecycle.py::_run_make_target` captures `make.log`, writes job status,
  and reports progress/result, but does not invoke the test metrics exporter.
- `test-metrics` is absent from the bridge action allowlist.
- The `k3dm Tests` dashboard (`k3dm-tests`) reads `k3dm_test_*` series, not bridge job-status.

Thus a cloud test-all run does not update dashboard freshness, total/failed cases, or duration
through this execution path. The dashboard may continue displaying an older scheduled or manual
`test-metrics` run. This is a missing publication path, distinct from a failed metrics push.

Related prior art: [nightly metrics push failure](2026-10-05-nightly-test-metrics-push-failure-is-silent.md).
That fixed staleness detection after a push fails; this job never attempts a test metrics push.

## Expected behavior / proposed follow-up

Make cloud-triggered full-suite runs observable in the existing test dashboard after completion.
Prefer publishing from the already captured test-all log, once, without rerunning the suites.
Keep the original test exit status and timeout outcome authoritative; do not replace the job with
`make test-metrics` unchanged, because that recipe ends with `exit 0`.

Acceptance criteria:

- [ ] A completed cloud `make-test-all` publishes case totals, failed cases, run duration,
  and a fresh timestamp using the existing metrics contract.
- [ ] Passing, failing, and timed-out test jobs retain their correct webhook terminal status.
- [ ] Metrics publication failure is reported separately and does not rewrite the test result.
- [ ] Tests remain behind the offline tripwire; publication occurs outside suite isolation.
- [ ] No arbitrary Make targets or broader cluster/operator capabilities become reachable.
- [ ] No duplicate suite execution, secret-bearing logs, or unbounded job-ID metric labels.
- [ ] Regression checks prove the exporter runs once for the intended target, receives the
  original result/duration, and is not called for unrelated Make jobs; mutations turn tests red.
- [ ] Operator verifies updated `k3dm-tests` freshness/counts/duration after a real cloud run.

Scope of this filing: documentation only. No runtime fix or dashboard rollout is included.

## Dedup and indexing

Exact-slug and local text searches found no existing report for this missing publication path.
The related nightly push-failure doc was read and is a different cause.
Similarity retrieval was attempted but unavailable:

```text
find-similar-docs: retrieval unavailable — no embeddings credential. $K3DM_EMBEDDINGS_API_KEY is unset or empty; k3dm-embeddings-api-key: cannot run security (FileNotFoundError); gemini-cli-api-key: cannot run security (FileNotFoundError); hub Vault: cannot run kubectl: [Errno 2] No such file or directory: 'kubectl'
find-similar-docs: falling back to the exact-slug glob is still correct.
```

This tracked docs/bugs report is in the index-docs corpus. The host must pull this commit before
its next indexing run can ingest it. Live vector ingestion was not attempted.
