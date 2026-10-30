# Bug: Sol and Terra coordinator work is unattributed because coordinator identity is opt-in

**Status:** OPEN
**Priority:** P2
**Severity:** medium — dispatch, cost and quality metrics describe almost all recent work as coming from an unknown coordinator, so the Opus-vs-Sol/Terra comparison the operator needs cannot be made
**Release:** v1.43.10 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-29, operator: "we need to consider other models like OpenAI Sol6.1 and Terra 6.1 as primary coordinators as we are not capturing their work like yours"
**Approval:** pending
**Component:** `bin/k3dm-codex-dispatch`, git commit attribution, `AGENTS.md`, Agent Dispatch dashboard
**Related:** [`2026-10-26-primary-coordinator-and-handoff-telemetry.md`](2026-10-26-primary-coordinator-and-handoff-telemetry.md) (fix `9424c32a`, works only when a coordinator is declared), [`v1.44.1-coordinator-rotation-trial.md`](../plans/v1.44.1-coordinator-rotation-trial.md), [`v1.44.1-dispatch-agent-five-hour-window-usage.md`](../plans/v1.44.1-dispatch-agent-five-hour-window-usage.md)

## Evidence (2026-10-29, read-only)

- Dispatch ledger, `start` events since 2026-10-26: 32 in total. 31 carry `coordinator_identity` `{"vendor":"unknown","source":"unreported"}`. One carries `openai/unknown` (declared).
- `origin/k3d-manager-v1.43.9` commits from the afternoon of 2026-10-26 to now: 243 in total, none with a `Co-Authored-By` or coordinator trailer. 190 are `checkpoint:` commits made by Codex-run coordinator sessions. Claude-coordinated commits carry `Co-Authored-By: Claude …`, so only Claude's share of the work can be attributed.

## Root cause

The 10-26 fix added `--coordinator VENDOR/MODEL` to `start`/`resume`. Nothing supplies it:

1. The dispatcher has no fallback, so an undeclared run records `unreported`.
2. No instruction tells a Sol or Terra session to declare itself.
3. Commits have no coordinator trailer except Claude's own.

The telemetry contract is correct. Adoption is zero, so the metric is empty.

## Fix

1. `start`/`resume`: when `--coordinator` is absent, read `K3DM_COORDINATOR` (same `vendor/model` validation). Record `source: env`. An explicit flag still wins.
2. When neither is set, print a one-line stderr warning naming both. Do not refuse: a missing identity must not block work.
3. Add a coordinator-session rule to `AGENTS.md`. A session acting as primary coordinator exports `K3DM_COORDINATOR` (for example `openai/gpt-6.1-sol` or `openai/gpt-6.1-terra`). It also ends each commit with a `Coordinator: <vendor/model>` trailer. Claude keeps its existing `Co-Authored-By` trailer.
4. Agent Dispatch dashboard: add a stat for the share of `start` events with an `unreported` coordinator over the selected range.
5. Update `docs/howto/codex-dispatch.md` with the env var, the precedence and the trailer.

Out of scope: inferring the coordinator from `agent`/`model` (the 10-26 spec forbids this), quota pools (v1.44.1), and rewriting history.

## Acceptance

```yaml
must:
  - id: M1
    text: start and resume with K3DM_COORDINATOR=openai/gpt-6.1-sol and no flag record vendor openai, model gpt-6.1-sol, source env
  - id: M2
    text: an explicit --coordinator overrides K3DM_COORDINATOR
  - id: M3
    text: with neither set, the run proceeds, records source unreported, and stderr names both --coordinator and K3DM_COORDINATOR
  - id: M4
    text: AGENTS.md and docs/howto/codex-dispatch.md state the env var, the precedence and the Coordinator trailer
  - id: M5
    text: the dashboard shows the share of start events with an unreported coordinator
must_not:
  - id: N1
    text: an invalid K3DM_COORDINATOR (bad shape, over 64 chars per side, shell metacharacters) is recorded; it is rejected exactly as an invalid flag value is
  - id: N2
    text: a missing coordinator makes start or resume exit non-zero
  - id: N3
    text: the coordinator is inferred from agent or worker model
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    what: BATS against the dispatcher with an isolated worktree root and ledger; N1 and N3 shown red on pre-fix code where applicable
  - id: E2
    proves: [M5]
    kind: offline
    what: dashboard JSON lint plus a query-shape test over a fixture ledger
  - id: E3
    proves: [M1, M4]
    kind: live
    what: operator runs one Sol-coordinated dispatch with K3DM_COORDINATOR set; Claude confirms the ledger start event and a commit trailer
interface:
  - bin/k3dm-codex-dispatch start|resume [--coordinator VENDOR/MODEL]
  - env K3DM_COORDINATOR
  - ledger.jsonl start/resume events, field coordinator_identity
```
