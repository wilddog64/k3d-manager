# Cloud-bridge Make job-status returns empty output, hiding test failure diagnostics

**Filed:** 2026-10-06
**Release / branch:** v1.41.0 / `k3d-manager-v1.41.0`
**Status:** OPEN
**Severity:** Medium — cloud agents see terminal failure but cannot diagnose it
**Component:** webhook job-status log selection / cloud-bridge response

## Reproduction and observed result

Operator requested `make-test-all` via cloud-bridge.
Request: `20261006T163821Z-make-test-all`; webhook job: `ccc20dc9`.
Initial response: HTTP 202, queued. Follow-up at 16:40:09Z: running, output empty.
The final response returned failure with output still empty:

```json
{"action": "job-status", "artifacts": ["artifacts/20261006T163821Z-make-test-all/summary.json"], "body": {"job_id": "ccc20dc9", "output": "", "status": "failed"}, "completed_at": "2026-10-06T16:47:53.547652Z", "http_status": 200, "id": "20261006T163821Z-make-test-all", "schema": 1, "status": "ok"}
```

The only published artifact was:

```json
{"finished_at": "2026-10-06T16:47:47.090084Z", "http_status": 200, "job_id": "ccc20dc9", "job_status": "failed", "request_id": "20261006T163821Z-make-test-all", "schema": 1, "target": "test-all"}
```

Sources:
- [Final response](https://github.com/wilddog64/k3d-manager/blob/cloud-requests/responses/20261006T163821Z-make-test-all.final.json)
- [Summary artifact](https://github.com/wilddog64/k3d-manager/blob/cloud-requests/artifacts/20261006T163821Z-make-test-all/summary.json)

The job finished at 09:47:47 America/Los_Angeles, about eight minutes after queue acceptance.
The transport succeeded; no failing assertion, exit code, or failure reason reached the cloud agent.
The full host-side log was not read, so the cause of the test-all failure remains UNKNOWN.

## Root cause of the missing output: file mismatch

Code inspection on v1.41.0:

- `scripts/lib/webhook/lifecycle.py::_run_make_target` writes process output to
  `JOB_DIR / job_id / "make.log"`. It reads that file for its notification tail, but does not
  write a corresponding `output` file.
- `bin/k3dm-webhook` job-status handler reads only `job_dir / "output"` and substitutes an
  empty string when that file is absent:

```python
output_file = job_dir / "output"
output = output_file.read_text()[-2000:] if output_file.exists() else ""
self._json(200, {"job_id": job_id, "status": status, "output": output})
```

This explains how a real Make log can coexist with an empty status response. The live host's
checked-out code and log content have not been independently inspected, so verify this path
against the actual job directory before declaring the runtime cause confirmed.

## Expected behavior / acceptance criteria

- [ ] Return a bounded log tail for Make jobs from `make.log`, while preserving `output`
  handling for other job types. Define deterministic precedence if both exist.
- [ ] Preserve webhook and bridge credential redaction before returning or committing any tail.
- [ ] Keep the existing output size bound and safe job-ID/path validation; no arbitrary file reads.
- [ ] Running and terminal Make jobs both return meaningful diagnostics when logs exist.
- [ ] A genuinely absent/empty log is distinguishable from a log-selection defect without
  inventing a test failure reason.
- [ ] Regression cases: make.log-only job, output-only job, both files, missing files,
  large log truncation, and redaction. Removing make.log handling must turn a test red.
- [ ] Operator reads ccc20dc9/make.log to identify the separate test failure; track that
  root cause separately if it is not already filed.
- [ ] Live cloud run proves a failed Make job exposes a useful redacted tail through job-status.

Do not publish full raw logs or broaden the bridge action allowlist as part of this fix.

## Related issue and dedup

[Cloud test-all does not publish Grafana metrics](2026-10-06-cloud-bridge-test-all-does-not-publish-grafana-metrics.md)
is a separate missing metrics path. Publishing Grafana metrics will not fix this status/log mismatch.
Exact-slug and local text searches found no duplicate report. Similarity retrieval was unavailable:

```text
find-similar-docs: retrieval unavailable — no embeddings credential. $K3DM_EMBEDDINGS_API_KEY is unset or empty; k3dm-embeddings-api-key: cannot run security (FileNotFoundError); gemini-cli-api-key: cannot run security (FileNotFoundError); hub Vault: cannot run kubectl: [Errno 2] No such file or directory: 'kubectl'
find-similar-docs: falling back to the exact-slug glob is still correct.
```

Documentation-only filing: no runtime implementation or new live test. This tracked report is
eligible for index-docs after the host pulls the branch; vector ingestion is not verified.

## Second live verification — passing Python unit job (2026-10-06)

Request `20261006T165715Z-make-test-python-unit`, job `5cc7f225`, queued at
16:57:28Z and completed successfully by the 16:58:14Z final response. Output is still empty:

```json
{"action":"job-status","artifacts":["artifacts/20261006T165715Z-make-test-python-unit/summary.json"],"body":{"job_id":"5cc7f225","output":"","status":"success"},"completed_at":"2026-10-06T16:58:14.040996Z","http_status":200,"id":"20261006T165715Z-make-test-python-unit","schema":1,"status":"ok"}
```

[Final response](https://github.com/wilddog64/k3d-manager/blob/cloud-requests/responses/20261006T165715Z-make-test-python-unit.final.json).
This reproduces missing logs on a passing job as well as the failed test-all job. Success status
alone does not verify test counts or assertions; the raw host log remains inaccessible through
this response. No runtime fix or additional suite rerun was attempted.
