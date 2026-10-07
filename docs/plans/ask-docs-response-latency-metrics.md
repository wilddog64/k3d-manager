# Enhancement — ask-docs response-latency observability

**Status:** PROPOSED — release placement TBD; candidate for v1.43.0
**Requested scope:** Track document retrieval, model execution, and end-to-end ask-docs timing
in Grafana without exposing question text or creating unbounded metric cardinality.

> The request mentioned v1.34.0. This repository is currently delivering v1.42.0 and planning
> v1.43.0, so this spec deliberately does not claim a v1.34.0 slot. The release owner should
> assign it after checking that milestone's capacity.

## Problem

The webhook access log records request duration in milliseconds, and ask-docs model metadata
records candidate elapsed time, but neither is currently published as a Grafana metric. The
retrieval phase is not timed separately. Operators therefore cannot see whether slow answers
come from document search, model execution, Slack delivery, or queueing, nor can they compare
latency trends across successful and failed requests.

## Goals

- Show ask-docs end-to-end response latency in Grafana.
- Separate queue/wait, retrieval, model, rendering, and total durations where the lifecycle
  makes those boundaries available.
- Support p50, p95, and p99 trend panels plus request counts and failure rates.
- Keep metric labels bounded and free of question text, document paths, job IDs, credentials,
  Slack IDs, and user identifiers.
- Preserve exact per-job investigation through structured job metadata/logs rather than using
  Prometheus as an event database.
- Keep metric publication non-fatal: an unavailable Pushgateway or metrics endpoint must not
  change the ask-docs result.

## Non-goals

- Storing prompts, retrieved excerpts, model responses, or credentials in Prometheus labels.
- Adding a new AI provider or changing retrieval/model selection behavior.
- Making Grafana the source of truth for an individual response.
- Introducing a high-cardinality `job_id` label for every ask-docs request.
- Replacing the existing bounded/redacted job output and failure metadata.

## Proposed telemetry contract

Use a bounded action label and terminal status:

```text
k3dm_webhook_request_duration_seconds{route="ask-docs",status="success"}
k3dm_ask_docs_phase_duration_seconds{phase="retrieval",status="success"}
k3dm_ask_docs_phase_duration_seconds{phase="model",status="failed"}
k3dm_ask_docs_requests_total{status="failed",failure_class="summary_model_unavailable"}
```

The exact metric type and transport must follow the repository's deployed observability path:

- Prefer a Prometheus-scraped webhook histogram/counter when the webhook can expose a stable
  metrics endpoint.
- If the host Pushgateway remains the supported path, publish bounded aggregate gauges/counters
  using the existing provider-aware Pushgateway plumbing and document that Pushgateway retains
  the latest aggregate value rather than a full event history.
- Do not put `job_id`, request ID, question, path, actor, candidate model name, or exception
  text in metric labels. Candidate names may be reduced to a fixed allowlist (`agy`, `gemini`)
  if the operator explicitly needs provider comparison.

Recommended bounded labels:

| Label | Allowed values |
| --- | --- |
| `route` | `ask-docs` |
| `phase` | `queue`, `retrieval`, `model`, `delivery`, `total` |
| `status` | `success`, `failed`, `sources_only` |
| `failure_class` | finite categories already used by ask-docs, or `none` |

## Timing boundaries

Record monotonic timestamps in the worker:

1. `queue`: request accepted until the ask-docs worker starts.
2. `retrieval`: start/end around the allowed-document search and source preparation.
3. `model`: start/end around the summarization attempt, including fallback candidates.
4. `delivery`: start/end for response rendering and Slack/response-url publication.
5. `total`: worker start until terminal status and best-effort metric publication.

The existing `--sources` mode should publish `status="sources_only"` and omit the model phase
or record it as zero only if the metric contract explicitly defines zero as “not attempted.”
Prefer omission or a separate mode label so zero is not confused with an instantaneous model.

## Grafana panels

Add a small ask-docs section to the existing webhook/operations dashboard, or create a focused
panel group if no suitable dashboard exists:

- Total response latency: p50 / p95 / p99.
- Retrieval versus model latency by phase.
- Requests per minute by terminal status.
- Failure rate by finite failure class.
- Sources-only share versus summarized-answer share.
- A panel description linking exact-job investigation to webhook job metadata/logs.

Use recording rules or `histogram_quantile` as appropriate to the selected metric transport.
Do not show a misleading per-job time series from a Pushgateway last-value gauge.

## Exact per-request investigation

Metrics provide aggregates. For an individual request, retain bounded metadata in the existing
job directory:

```json
{
  "route": "ask-docs",
  "status": "success",
  "started_at": "...",
  "finished_at": "...",
  "duration_ms": 9279,
  "phases_ms": {"retrieval": 3120, "model": 6011, "delivery": 148},
  "failure_class": null
}
```

This file must be scrubbed, size-bounded, safe under the existing job-ID path checks, and
available through the existing job-status/artifact path. Timestamps and durations are safe;
questions, excerpts, and raw CLI output are not to be added.

## Verification

- Unit tests assert every phase timer closes on success, model failure, timeout, and
  sources-only execution.
- Tests assert metric publication failure cannot change the ask-docs terminal result.
- Tests reject unbounded or forbidden labels, including job ID, prompt text, source path, and
  actor identity.
- Controlled fixtures produce non-zero retrieval/model/total durations.
- Grafana JSON validation and dashboard panel tests pass.
- A live slow retrieval and a live model fallback show distinct phase timings.
- A live job ID can be correlated to metadata without requiring a Prometheus label lookup.

## Release decision

This is an observability enhancement, not a correctness bug. Assign it to v1.43.0 only if the
release has room after the structured E2E evidence work; otherwise carry the same spec forward
unchanged. Do not backport it to v1.34.0 without confirming that milestone is still active and
that its dashboard/metric transport matches the current webhook architecture.

