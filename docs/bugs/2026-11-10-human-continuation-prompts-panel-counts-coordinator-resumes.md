# Bug: "Human continuation prompts" counts Claude's resumes of dispatched agents, not human turns

**Status:** OPEN — reopened on recurrence 2026-11-23 (operator); was: CLOSED at grooming 2026-11-22 ("reopen on recurrence")
**Priority:** P3
**Classified:** P3 by gemini-4-argon-medium, 2026-11-12 (Cosmetic wording fix renaming a dashboard panel title, description, and related documentation without changing underlying queries or behavior); Claude proposed P3. Agreed.
**Triage:** patch → v1.45.1 (operator, 2026-11-23: "yes, go ahead to file a P3 spec"); was: close — grooming 2026-11-22, operator; before that: passed over, 1st (out of v1.44.0 at the 10-P3 cap) — grooming 2026-11-12, operator.
**Introduced by:** pre-existing (the panel title and description since the reason bars; see CHANGELOG "Agent Dispatch Human continuation prompts")
**Should have been caught by:** review
**Prior art:** `make find-similar-docs` unavailable (vector store unreachable from the M4: `context "k3d-k3d-cluster" does not exist`, 2026-11-10); exact-slug glob: none; `docs/plans/human-operator-turns.md` covers the same panel (read: this doc takes only its rename step; the plan keeps the real turn counting)
**Severity:** cosmetic, misleading. The operator read the bars (correction, clarification, continue) as their own effort; they are Claude's coordinator → sub-agent resume prompts recorded in the ledger.
**Approval:** operator, 2026-11-10: "also can you schedule the label fix?"
**Intent approved:** operator, 2026-11-23
**Intent approval words:** "yes, go ahead to file a P3 spec" (2026-11-23); first approved 2026-11-10 ("go with your suggestion")
**Waiting on:** fix running — since 2026-11-23
**Dispatch:** codex gpt-6-luna, started 2026-11-23 (task/v1.45.1/2026-11-10-human-continuation-prompts-panel-counts-coordinator-resumes)
**Filed:** 2026-11-10
**Detected by:** operator, 2026-11-07 (v1.43.14 retro); re-raised 2026-11-10
**Branch:** `k3d-manager-v1.45.1`
**Release:** P3 batch

## Recurrence — 2026-11-23

Operator, from a dashboard screenshot: "should we change the title Human continuation prompts? I remembered you said
this is primary you interact with other agents". Ledger check the same day: 215 `intervention` events (correction
162, clarification 27, continue_prompt 24, other 2), every one written by `resume --reason` (`bin/k3dm-codex-dispatch:1780`),
which Claude runs as coordinator. Line numbers below refreshed 2026-11-23 by grep.

## Symptom

Agent Dispatch, panel id 85 `"title": "Human continuation prompts"`
(`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml:1167`); its description says "Explicitly
recorded operator events by reason". The ledger `intervention` events behind it are written by
`bin/k3dm-codex-dispatch resume`, which Claude runs.

## Fix

1. Panel 85 title becomes `Coordinator → agent prompts`; description: "Resume prompts the coordinator (Claude) sent to
   dispatched agents, by recorded reason. Not operator turns: those are counted by the v1.45.0 human-operator-turns
   plan. The tracked tasks bar is the coverage denominator." Query, layout and id unchanged.
2. The guide and the how-to say the same.
3. `docs/plans/human-operator-turns.md` drops its rename step and refers here.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` | panel 85 title and description |
| `scripts/tests/plugins/agent_dispatch_dashboard.bats` | lines 277 and 1130 look the panel up by the new title; a test that the old title is gone |
| `docs/guides/grafana-dashboards/k3dm-agent-cost.md` | line 69 wording |
| `docs/howto/codex-dispatch.md` | line 168 wording |

## Contract readers

| Reader | Changes? |
|---|---|
| `scripts/tests/plugins/agent_dispatch_dashboard.bats:277,1130` (panel lookup by title) | Yes |
| `docs/guides/grafana-dashboards/k3dm-agent-cost.md:69`, `docs/howto/codex-dispatch.md:168` | Yes |
| `CHANGELOG.md:338`, `docs/retro/2026-11-07-v1.43.14-retrospective.md:24` | No: history |
| `docs/plans/human-operator-turns.md` | Yes: rename step removed (Claude, at filing) |

Writers: `bin/k3dm-codex-dispatch resume` writes the `intervention` events; unchanged. Found by
`git grep -n "Human continuation prompts"`, 2026-11-10; re-run 2026-11-23. The metric name `k3dm_dispatch_human_continuation_prompts` (`bin/k3dm-dispatch-metrics:1841`, `scripts/tests/bin/test_dispatch_metrics.py:502,508`) is unchanged: renaming it would split the series.

## Acceptance

```yaml
must:
  - id: M1
    text: "Agent Dispatch panel 85 is titled 'Coordinator → agent prompts' and its description says the prompts come from the coordinator, not the operator."
  - id: M2
    text: "Panel 85 keeps its id, query and gridPos."
must_not:
  - id: N1
    text: "No dashboard panel is titled 'Human continuation prompts'."
evidence:
  - {id: E1, proves: [M1, M2, N1], kind: offline, intent: "You will see agent_dispatch_dashboard.bats find panel 85 by its new title with the same expr and gridPos, and a test that fails if any panel is titled 'Human continuation prompts'; that test fails on today's dashboard."}
  - {id: E2, proves: [M1], kind: live, intent: "After the fix lands and is promoted, you open Agent Dispatch and see 'Coordinator → agent prompts' where 'Human continuation prompts' was, with the same bars."}
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml (dashboard JSON under data)"
```

## Worker definition of done

- Run `bats scripts/tests/plugins/agent_dispatch_dashboard.bats` and `make validate-manifests`; paste command, rc and
  proving lines, and the N1 test red on today's dashboard. Leave changes uncommitted; Claude reviews and lands. No
  kubectl, nothing against the hub.
