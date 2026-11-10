# Bug: "Human continuation prompts" counts Claude's resumes of dispatched agents, not human turns

**Status:** OPEN
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-10
**Introduced by:** pre-existing (the panel title and description since the reason bars; see CHANGELOG "Agent Dispatch Human continuation prompts")
**Should have been caught by:** review
**Prior art:** `make find-similar-docs` unavailable (vector store unreachable from the M4: `context "k3d-k3d-cluster" does not exist`, 2026-11-10); exact-slug glob: none; `docs/plans/v1.45.0-human-operator-turns.md` covers the same panel (read: this doc takes only its rename step; the plan keeps the real turn counting)
**Severity:** cosmetic, misleading. The operator read the bars (correction, clarification, continue) as their own effort; they are Claude's coordinator → sub-agent resume prompts recorded in the ledger.
**Approval:** operator, 2026-11-10: "also can you schedule the label fix?"
**Intent approved:** operator, 2026-11-10
**Intent approval words:** "go with your suggestion"
**Dispatch:** operator go 2026-11-10 ("go with your suggestion"), `--agent agy --model gemini-3.8-flash-medium`, slug `human-continuation-prompts-rename`; queued behind control-node-linux (WIP limit 3)
**Filed:** 2026-11-10
**Detected by:** operator, 2026-11-07 (v1.43.14 retro); re-raised 2026-11-10
**Branch:** `k3d-manager-v1.43.15`
**Release:** P3 batch

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
3. `docs/plans/v1.45.0-human-operator-turns.md` drops its rename step and refers here.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` | panel 85 title and description |
| `scripts/tests/plugins/agent_dispatch_dashboard.bats` | lines 187 and 1036 look the panel up by the new title; a test that the old title is gone |
| `docs/guides/grafana-dashboards/k3dm-agent-cost.md` | line 69 wording |
| `docs/howto/codex-dispatch.md` | line 162 wording |

## Contract readers

| Reader | Changes? |
|---|---|
| `scripts/tests/plugins/agent_dispatch_dashboard.bats:187,1036` (panel lookup by title) | Yes |
| `docs/guides/grafana-dashboards/k3dm-agent-cost.md:69`, `docs/howto/codex-dispatch.md:162` | Yes |
| `CHANGELOG.md:338`, `docs/retro/2026-11-07-v1.43.14-retrospective.md:24` | No: history |
| `docs/plans/v1.45.0-human-operator-turns.md` | Yes: rename step removed (Claude, at filing) |

Writers: `bin/k3dm-codex-dispatch resume` writes the `intervention` events; unchanged. Found by
`git grep -n "Human continuation prompts"`, 2026-11-10.

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
