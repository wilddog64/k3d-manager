# Enhancement: capture Codex as primary coordinator and attribute coordinator handoffs

**Status:** OPEN — proposed P3 telemetry enhancement; not implemented or live-verified
**Priority:** P3
**Severity:** low — coordinator identity is incomplete or unknown in the Per spec table; worker and landing metrics remain intact
**Release:** v1.43.9 (bug/enhancement; does not count toward the five-plan cap)
**Branch:** `k3d-manager-v1.43.9`
**Filed:** 2026-10-26, operator: "this need change to capture if codex is a primary cooridnator"
**Approval:** operator requested the telemetry behavior; implementation requires normal dispatcher/review gates
**Component:** `bin/k3dm-codex-dispatch`, `bin/k3dm-codex-land-pending`, `bin/k3dm-dispatch-metrics`, Agent Dispatch Grafana dashboard
**Related:** `docs/plans/v1.43.7-dispatch-vendor-coordinator-model-telemetry.md`, `docs/howto/codex-dispatch.md`, `docs/architecture/codex-dispatch.md`

## Problem

The v1.43.9 Agent Dispatch **Per spec** table shows `Agent=codex` and a `Worker` model, but it does not clearly show whether Codex is the **primary coordinator** or merely the implementation worker. The latest `vectordb-retrieval-keyv...` task has about 55.9K worker tokens and $0 attributed Claude cost; neither fact proves who coordinated it.

Earlier v1.43.7 work introduced an optional `--coordinator VENDOR/MODEL` on `start` and `resume` and a coordinator identity metric. Current exporter selects the last declared coordinator from start/resume events (or unknown); landing events do not identify who performed landing. Thus the schema supports *declared coordinator model* but does not yet provide an auditable **primary versus acting coordinator versus landing actor**, or a meaningful handoff event for Claude quota exhaustion → Codex/Luna takeover.

Do not automatically infer that `Agent=codex` means Codex was coordinating. A task can be created and directed by Claude while Codex implements it, or Codex can independently plan, dispatch and integrate work.

## Requested behavior

1. Record vendor-neutral **primary coordinator** identity at the time task coordination is assigned. Support explicit `openai/gpt-6-luna` or other bounded vendor/model identities, with provenance `declared`, `runtime-reported`, or `unknown`. An explicit assertion is necessary; do not infer coordinator identity from the worker agent or subscription cost.
2. Record independent **acting coordinator** changes (including coordinator takeover) as append-only, timestamped task-correlated ledger events without overwriting original primary ownership. Capture a bounded `handoff_reason` enum such as `quota_exhausted`, `manual`, `unavailable`, `scheduled`, `other` and `unknown`; do not claim a provider limit unless observed or explicitly recorded.
3. Record the **landing actor** independently (`human`, `claude`, `codex`, `other_agent`, `unknown`, with model/vendor only when explicitly declared and supported), and distinguish an actor from the implementation worker. `codex-land-pending` should log a review-pending handoff and landing actor when supplied; an unannotated legacy land remains `unknown`.
4. Display **Primary coordinator**, **Acting coordinator**, **Landed by** and optionally **Handoff reason/count** alongside `Agent`, `Worker`, and existing cost/duration fields in Per spec. Use compact labels or detail/drilldown if the table becomes too wide. Current task `Coordinator` display must be clearly renamed or retained with accurate semantics.
5. Maintain backwards-compatible parsing for all historic `ledger.jsonl` records and cross-repo tasks. Old missing identity fields must display `unknown`, never be rewritten or filled from today's configured model or the worker identity.
6. Separate **primary coordination cost** from the currently approximate `Claude ≈` attribution. When Codex is coordinator, don't relabel worker token spend as coordinator cost. Show explicit absence of measured coordinator cost distinctly from a measured zero.
7. Capture `Claude → Codex` takeover without falsely implying Claude independently verified a landing. `LANDED — Claude review pending` remains review pending until a separate verifier event and required live evidence.
8. Limit metric cardinality: use bounded normalized vendor/model and reason labels, avoid task/user/session IDs in aggregate Prometheus series, and avoid secret prompts or raw transcripts in the ledger.

## Files

- `bin/k3dm-codex-dispatch`
- `bin/k3dm-codex-land-pending`
- `bin/k3dm-dispatch-metrics`
- `Makefile`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/codex_dispatch.bats` (confirm exact existing suite path)
- `docs/howto/codex-dispatch.md`
- `docs/architecture/codex-dispatch.md`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

Inspect suite paths and narrow the files to exactly necessary ones before implementation dispatch.

## Acceptance

```yaml
must:
  - id: M1
    text: A Codex-coordinated and Codex-implemented task records Codex as primary coordinator and worker as two independently sourced facts.
  - id: M2
    text: A Claude-primary task landed by Codex preserves original primary ownership and displays Codex as landing actor after an explicit handoff.
  - id: M3
    text: Handoffs are append-only, time-correlated, provenance-labeled and visible without overwriting a start/resume or verification event.
  - id: M4
    text: Existing task, landing, cost and model fields remain compatible and truthful for legacy and cross-repo records.
  - id: M5
    text: Per spec displays clear primary/acting/landing attribution with unknown rather than inferred identity.
  - id: M6
    text: Quota exhaustion may be a handoff reason only if explicitly evidenced; no automatic attribution from lack of Claude cost.
must_not:
  - id: N1
    text: Do not assume every Codex worker is its own primary coordinator.
  - id: N2
    text: Do not rewrite historical ledger entries or mark handoff landings independently verified.
  - id: N3
    text: Do not expose unbounded task identity, raw prompts, credentials or raw model responses in metric labels.
  - id: N4
    text: Do not change AI runtime routing, privileges or landing gates just for telemetry.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, M6, N1, N2]
    text: Ledger fixtures for Codex-primary, Claude-primary/Codex-takeover, Claude-primary/human-landing, unknown legacy actors, and resume after quota failure; require pre-fix red tests.
  - id: E2
    kind: offline
    proves: [M4, M5, N3, N4]
    text: Grafana and exporter tests assert one row per spec, correct model/actor fields, stable legacy metrics and bounded cardinality.
  - id: E3
    kind: live
    proves: [M1, M2, M5]
    text: Operator-authorized live dispatch and handoff exercise shows declared Codex-primary and Claude-primary takeover paths with no false completion/verification.
interface:
  - bin/k3dm-codex-dispatch: start/resume/handoff/land ledger events
  - bin/k3dm-dispatch-metrics: task-coordinator and handoff series
  - Grafana Agent Dispatch Per spec table and operator guide
```

## Definition of Done

- [ ] Align with v1.43.7 coordinator identity contract, and confirm existing dashboard field IDs.
- [ ] Tests red pre-fix, green post-fix; validate backward compatibility and cardinality.
- [ ] Preserve source/provenance/unknown without inferred coordinator or verifier.
- [ ] Document operator commands and one example of explicit primary Codex coordination.
- [ ] Capture E3 separately before marking live verified.
- [ ] Commit: `feat(dispatch): attribute primary coordinator handoffs and landing actors`

## What NOT to Do

- Do not change any live coordinator session or rescue an in-progress dispatch as part of filing.
- Do not infer that an LLM was primary simply from the worker model, `Claude ≈ $0`, or the last person who pushed.
- Do not create a PR or commit to `main`.
