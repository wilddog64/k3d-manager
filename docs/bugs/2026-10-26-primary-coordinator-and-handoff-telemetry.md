# Enhancement: capture Codex as primary coordinator and attribute coordinator handoffs

**Status:** OPEN — proposed P3 telemetry enhancement; not implemented or live-verified
**Priority:** P3
**Severity:** low — coordinator identity is incomplete or unknown in the Per spec table; worker and landing metrics remain intact
**Release:** v1.43.9 (bug/enhancement; does not count toward the five-plan cap)
**Branch:** `k3d-manager-v1.43.9`
**Filed:** 2026-10-26, operator: "this need change to capture if codex is a primary cooridnator"
**Approval:** explicit operator selection in the 2026-10-27 Luna batch, with normal independent review and sequential operator live checks
**Dispatch:** go — model `gpt-6-luna`; task `primary-coordinator-handoffs-luna`
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
- `scripts/tests/bin/codex_dispatch.bats`
- `scripts/tests/bin/codex_land_pending.bats`
- `docs/howto/codex-dispatch.md`
- `docs/architecture/codex-dispatch.md`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

The existing suites are under scripts/tests/bin, confirmed before dispatch.
Use only the paths above; leave untouched files unchanged.

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

## Bounded CLI and compatibility contract

- Add explicit primary assignment at start (for example --primary-coordinator
  VENDOR/MODEL). Keep current --coordinator behavior/legacy fields compatible.
  Primary omission is unknown; never fill it from worker model, default config,
  cost, verifier, or a later resume. Preserve the original primary on handoff.
- Add handoff CLI accepting explicit acting identity/reason and append-only
  task events. Explicit quota_exhausted is a declaration, not runtime detection.
  Report declared/runtime-reported/unknown provenance truthfully.
- Land and codex-land-pending accept explicit landing actor metadata, passing it
  through without changing rebase/test/lock/scope/commit policies. Legacy/unmarked
  land is unknown. Preserve the independent verifier and review-pending states.
- Metrics/display add primary, acting, landed-by and bounded handoff details;
  keep existing worker/agent/coordinator and costs compatible. Coordinator cost
  remains not measured when no distinct measured source exists, not zero and
  never worker spend. Avoid changing actual execution routing, including the
  separately observed resume-model issue, as part of this telemetry patch.
- Test strict identifiers, invalid enums, non-leaking labels, legacy/cross-repo
  records, first-primary preservation, repeated handoffs, explicit land actor
  passthrough, no false verifier and unknown-versus-zero costs.
- Existing long shell functions must not grow new unbounded conditional logic;
  extract new bounded helpers. Do not raise audit thresholds or bypass hooks.


## Dispatch rules — operator batch 2026-10-27

The operator explicitly selected this existing bug for implementation by
GPT-6-Luna, independent offline review, and operator live verification one fix
at a time. This is implementation authorization; no worker may deploy, restart
services, contact live clusters/registries/providers, create accounts, rotate
credentials, or run live tests. Work only in the isolated task worktree and the
Files allowlist. Do not edit this spec, memory-bank, or source plan statuses.
Do not stage, commit, push, or create PRs. Preserve DO NOT REMOVE comments.
Add meaningful regressions and show them red on the original behavior before
reporting green. Run focused tests, syntax/lint, and git diff --check; report
actual outputs and any unmet acceptance honestly. Use <=8 if blocks in new or
refactored functions. Report legacy budget conflicts instead of raising limits.
The coordinator will run audit/lint on staged changes before committing.

Focused gates: codex_dispatch and codex_land_pending BATS, dispatch metrics
pytest, existing agent_dispatch_dashboard BATS and Python/Ruff/ShellCheck for
touched code. Use isolated fixture ledgers only; never handoff/land/resume a
real running task or inject synthetic identities into the production ledger.
The operator's real E3 exercise is later and separate.
