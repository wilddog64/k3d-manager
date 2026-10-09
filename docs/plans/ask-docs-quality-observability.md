# Enhancement — Ask-docs answer quality and usefulness dashboard

**Status:** PROPOSED — release placement TBD; candidate for v1.43.0
**Relationship:** Companion to [Ask-docs response time and troubleshooting dashboard](ask-docs-response-latency-metrics.md)

## Problem

Latency shows how quickly ask-docs responds, but not whether the response was useful. A fast
answer with weak sources, no citations, or a model fallback is not a quality success. Quality
must be measured without storing raw questions, prompts, document excerpts, or user identities
in Prometheus labels or dashboard data.

## Goals

- Measure source usefulness, answer completion, citation coverage, and failure outcomes.
- Add optional operator/user feedback without making feedback required to use ask-docs.
- Identify questions that need follow-up or produce no grounded answer.
- Provide human-readable Grafana panels and an exact-job investigation path.
- Keep all metrics privacy-safe, bounded, and non-blocking to the ask-docs response.

## Non-goals

- Automatically judging a user's question as good or bad based on wording.
- Storing raw question text, prompts, model output, excerpts, Slack IDs, or user IDs in metrics.
- Automatically changing retrieval thresholds or model routing from a quality score.
- Treating retrieval similarity alone as proof that an answer is correct.

## Quality signals

Publish counters/histograms with only bounded labels such as `mode`, `outcome`, and a finite
`quality_reason`. Never use question text, document paths, job IDs, or identities as labels.

| Human-readable signal | Meaning | Example bounded value |
| --- | --- | --- |
| **Answers with useful sources** | Retrieved sources met the configured relevance floor and were linkable | `sources_useful` |
| **Answers without enough evidence** | Retrieval returned no usable sources or the answer could not be grounded | `insufficient_evidence` |
| **Answers with citations** | A summarized response retained the expected source links | `cited` |
| **Source-list requests** | User intentionally requested `--sources` and no model summary was attempted | `sources_only` |
| **Successful summaries** | Model returned a non-empty answer with preserved sources | `summary_success` |
| **Summary fallbacks** | The primary model failed but a configured fallback answered | `fallback_success` |
| **Failed summaries** | All enabled model candidates failed, timed out, or returned no output | `summary_failed` |
| **Questions needing follow-up** | A bounded follow-up signal indicates the answer was incomplete or unclear | `follow_up` |
| **Helpful feedback** | Explicit positive operator/user feedback | `helpful` |
| **Unhelpful feedback** | Explicit negative operator/user feedback | `unhelpful` |

Similarity score, source count, citation count, and answer length may be recorded as bounded
numeric fields in job metadata. They must not become unbounded labels.

## Groundedness evaluation

Add an offline evaluation job over fixed, versioned question fixtures. Each fixture contains a
question, expected source paths or source themes, and a rubric. The evaluator reports retrieval
recall at configured top-k, citation coverage, answer groundedness against supplied excerpts,
no-answer honesty when evidence is insufficient, and regression count by corpus revision.

The evaluator must not send production questions or credentials to an external model. If a model
judge is used for fixture evaluation, prompts and outputs stay in disposable test artifacts and
are redacted before publication.

## Feedback and follow-up

Feedback should be explicit and low-friction, for example Slack actions or a `/ask-docs
feedback helpful|unhelpful` command associated with an existing job. Store only the job-safe
outcome and bounded timestamp metadata. Do not record actor identity in Prometheus labels.

Follow-up is a diagnostic signal, not proof of failure. Count it only when the user explicitly
requests clarification, asks for missing evidence, or uses the feedback action—not merely when a
second unrelated question arrives.

## Human-readable Grafana layout

Use a focused dashboard section with these panel titles:

- **Answers with useful sources** — percentage and count of responses with usable citations.
- **Answers needing more evidence** — insufficient-evidence and no-answer rate.
- **Summary outcomes** — successful summary, fallback success, sources-only, and failed summary.
- **Citation coverage** — responses that include source links.
- **User-rated helpfulness** — helpful versus unhelpful feedback, with sample count.
- **Questions needing follow-up** — explicit follow-up signals over time.
- **Offline groundedness score** — fixture evaluation trend by corpus revision.

For an exact-job table, use these visible columns:

| Column title | Meaning |
| --- | --- |
| **Completed** | When the answer finished |
| **Job ID** | Linkable job record for investigation, not a metric label |
| **Answer outcome** | Summary succeeded, fallback succeeded, source list only, or failed |
| **Source quality** | Useful sources, insufficient evidence, or not evaluated |
| **Citations** | Present, absent, or not applicable |
| **Feedback** | Helpful, unhelpful, pending, or not collected |
| **Follow-up needed** | Explicit follow-up signal, or `No` |
| **Failure reason** | Human-readable finite category, or `—` |

Avoid exposing implementation names such as `failure_class`, `top_k`, or `groundedness_score`
as unexplained visible headers; place their definitions in panel descriptions.

## Data contract and privacy

Extend existing bounded job metadata with quality fields:

```json
{
  "answer_outcome": "summary_success",
  "source_quality": "sources_useful",
  "source_count": 5,
  "citation_count": 5,
  "feedback": "pending",
  "follow_up_needed": false,
  "failure_reason": null
}
```

All fields are optional and must degrade safely when older jobs lack them. Scrub credentials,
IPs, phone numbers, and unsafe text before writing metadata. Enforce existing job-path and size
limits. Metrics publication or feedback storage must never change the answer's terminal status.

## Verification

- Fixtures cover relevant sources, insufficient evidence, sources-only, primary success,
  fallback success, all-model failure, explicit helpful/unhelpful feedback, and follow-up.
- Tests reject raw question text, prompts, source paths, job IDs, and identities in metric labels.
- Tests prove metric or feedback publication failures do not fail ask-docs.
- Offline groundedness results are reproducible against a pinned fixture/corpus revision.
- Dashboard JSON uses the human-readable titles and table columns above.
- Live verification confirms the panels populate without exposing sensitive content.

## Release decision

This is an observability and evaluation enhancement, not a correctness fix. Assign it to
v1.43.0 only after the latency and E2E evidence work are capacity-checked; otherwise carry the
spec forward unchanged.
