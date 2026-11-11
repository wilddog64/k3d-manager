# Bug: Dispatch table shows Gemini Flash and Claude Fable workers as `google/other`, and the Worker column is off-screen

**Status:** OPEN
**Priority:** P3
**Waiting on:** fix running — since 2026-11-10 (batched into Flash dispatch `2026-11-10-agent-cost-shows-unpriced-claude-model-as-zero`)
**Introduced by:** pre-existing: `MODEL_IDENTITY_ALLOWLIST` was not updated when Flash 3.8 dispatches began (first: `2026-11-02-hub-data-export-never-ran`)
**Should have been caught by:** review (the dispatch that first used `gemini-3.8-flash-medium` did not check the Worker column)
**Prior art:** exact-slug glob: none; `ls docs/bugs | grep allowlist`: two unrelated docs. `make find-similar-docs` not run (vector store context missing on the M4, 2026-11-10)
**Severity:** reporting only. The ledger records the exact model; the dashboard hides it. Workaround: read `<run>/model` or the ledger `start` event.
**Approval:** Claude, 2026-11-10 (operator asked: "for agent can we show what agy model for a particular spec")
**Dispatch go:** operator, 2026-11-10: "go as you recommeded for those two"
**Intent approved:** operator, 2026-11-10
**Intent approval words:** ("intent approved", E1-E3)
**Filed:** 2026-11-10
**Detected by:** Claude, answering the operator's question about the Agent Dispatch "Landed specs" table
**Branch:** `k3d-manager-v1.43.15`

## Evidence (Claude, M4, 2026-11-10)

- Ledger `start` event for `cost-attribution-coverage`: `"model": "gemini-3.8-flash-medium", "agent": "agy"`.
- `bin/k3dm-dispatch-metrics --dry-run` (nothing pushed), 30d window: for all four agy specs on the table
  (`cost-attribution-coverage`, `2026-11-07-claude-plan-quota-not-exported`, `2026-11-02-hub-data-export-never-ran`,
  `2026-11-07-bugs-dashboard-fix-running-not-checked-against-worker`):
  `k3dm_dispatch_model_identity{role="worker",vendor="google",model="other",display="google/other (selected)"}`.
- `bin/k3dm-dispatch-metrics:39-43` `MODEL_IDENTITY_ALLOWLIST` (a label-cardinality guard) lists Luna/Sol/Terra/Astra,
  Opus/Sonnet/Haiku and Argon, but no `gemini-3.8-flash-*` and no `claude-fable-5-1`; `:1676-1677` maps anything else
  to `other`.
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` "Landed specs" table: the Worker column
  (refId I, `indexByName` `worker: 11`) is placed after Runs and API eq, so on a laptop-width screen you can't see it
  without scrolling; Agent (`agent: 3`) shows only `agy`.

## Fix

1. Add `gemini-3.8-flash-low`, `gemini-3.8-flash-medium`, `gemini-3.8-flash-high` and `claude-fable-5-1` to
   `MODEL_IDENTITY_ALLOWLIST`. Check the exact Flash slugs against `bin/k3dm-codex-dispatch`'s accepted models
   and the ledger before adding them, not from this doc.
2. Agent Dispatch "Landed specs" table: move Worker right after Agent (and rename it "Worker model").

## Files

| File | Change |
|---|---|
| `bin/k3dm-dispatch-metrics` | allowlist entries |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` | Worker column order and name |
| `scripts/tests/` (dispatch-metrics and agent-dispatch dashboard suites) | E1, E2 |

## Contract readers

- `k3dm_dispatch_model_identity{model}`: writer `bin/k3dm-dispatch-metrics:1665-1690`; readers: the Agent Dispatch
  table (refIds I, J, P, Q) and any other panel the worker finds with `git grep model_identity` before changing
  anything (it lists them). New label values are additive: rows that read `other` today will read the model name.
- `MODEL_IDENTITY_ALLOWLIST`: read only inside `bin/k3dm-dispatch-metrics`.

## Acceptance

```yaml
must:
  - id: M1
    text: "A dispatch started with an agy Flash 3.8 model, or with claude-fable-5-1, exports that exact model in k3dm_dispatch_model_identity and its display."
  - id: M2
    text: "The Landed specs table shows the worker model next to the Agent column."
must_not:
  - id: N1
    text: "A model name not on the allowlist is never exported as a label value (still maps to other)."
  - id: N2
    text: "Existing allowlisted models (gpt-6-luna, gemini-4-argon-medium, claude-opus-5-5) export unchanged."
evidence:
  - {id: E1, proves: [M1, N1, N2], kind: offline, intent: "You will see a test with a scratch ledger holding a Flash 3.8 run, a Fable run, a Luna run and a made-up model: the first three export their own names, the made-up one exports other. Against today's code Flash and Fable export other."}
  - {id: E2, proves: [M2], kind: offline, intent: "You will see a dashboard test find the Worker model column placed right after Agent; it fails on today's dashboard."}
  - {id: E3, proves: [M1, M2], kind: live, intent: "After promote, Claude opens Agent Dispatch and sees cost-attribution-coverage with worker model google/gemini-3.8-flash-medium next to agy."}
interface:
  - "bin/k3dm-dispatch-metrics --dry-run (Prometheus text output)"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml (Landed specs table)"
```

## Worker definition of done

- Change only the files above. Show E1 red against today's code, then green. Paste command, rc and proving lines.
  Leave changes uncommitted; Claude reviews and lands. Batch with
  `docs/bugs/2026-11-10-agent-cost-shows-unpriced-claude-model-as-zero.md` (same `bin/k3dm-dispatch-metrics`; one open
  dispatch per file).
