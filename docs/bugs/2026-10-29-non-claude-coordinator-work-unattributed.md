# Bug: Sol and Terra coordinator work is unattributed because coordinator identity is opt-in

**Status:** OPEN
**Priority:** P2
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (Coordinator attribution telemetry is degraded (recording `unreported` by default), but a functional workaround exists by explicitly passing `--coordinator VENDOR/MODEL` and adding commit trailers manually); Claude proposed P2. Agreed.
**Triage:** carry → v1.44.0 (cost-dashboard batch) — grooming 2026-11-12, operator.
**Waiting on:** dispatch — since 2026-11-13 (queued: WIP 3 until Part B lands)
**Severity:** medium — dispatch, cost and quality metrics describe almost all recent work as coming from an unknown coordinator, so the Opus-vs-Sol/Terra comparison the operator needs cannot be made
**Release:** v1.44.0 (carried by grooming 2026-11-12)
**Branch:** `k3d-manager-v1.44.0`
**Filed:** 2026-10-29, operator: "we need to consider other models like OpenAI Sol6.1 and Terra 6.1 as primary coordinators as we are not capturing their work like yours"
**Approval:** operator, 2026-11-12 (grooming: carry → v1.44.0)
**Intent approved:** operator, 2026-11-13
**Intent approval words:** "apporve three intents and you can dispatch them" (vault-unseal, hermes-card amended E1, coordinator-unattributed)
**Component:** `bin/k3dm-codex-dispatch`, git commit attribution, `AGENTS.md`, Agent Dispatch dashboard
**Related:** [`2026-10-26-primary-coordinator-and-handoff-telemetry.md`](2026-10-26-primary-coordinator-and-handoff-telemetry.md) (fix `9424c32a`, works only when a coordinator is declared), [`v1.47.0-coordinator-rotation-trial.md`](../plans/v1.47.0-coordinator-rotation-trial.md), [`v1.47.0-dispatch-agent-five-hour-window-usage.md`](../plans/v1.47.0-dispatch-agent-five-hour-window-usage.md)

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
3. Add a coordinator-session rule to `AGENTS.md`, outside the `shared:` blocks (`bin/k3dm-check-agent-docs` must stay green). A session acting as primary coordinator exports `K3DM_COORDINATOR` (for example `openai/gpt-6.1-sol` or `openai/gpt-6.1-terra`). It also ends each commit with a `Coordinator: <vendor/model>` trailer. Claude keeps its existing `Co-Authored-By` trailer.
4. `bin/k3dm-dispatch-metrics:981-985`: the declared-coordinator filter accepts `source` `declared` or `env` (status stays `declared` for both), so env-declared runs are attributed.
5. Agent Dispatch dashboard: add a stat for the share of `start` events with an `unreported` coordinator over the selected range.
6. Update `docs/howto/codex-dispatch.md` with the env var, the precedence and the trailer.

Out of scope: inferring the coordinator from `agent`/`model` (the 10-26 spec forbids this), quota pools (v1.47.0), and rewriting history.

## Files

- `bin/k3dm-codex-dispatch`
- `bin/k3dm-dispatch-metrics`
- the Agent Dispatch dashboard JSON under `scripts/etc/grafana/dashboards/`
- `AGENTS.md`, `docs/howto/codex-dispatch.md`, `CHANGELOG.md`
- tests: `scripts/tests/bin/codex_dispatch_ledger.bats` (or a new `codex_dispatch_coordinator_env.bats`), `scripts/tests/bin/test_dispatch_metrics.py`

## Contract readers

New env var `K3DM_COORDINATOR` and a new value `env` for ledger `coordinator_identity.source` (grep 2026-11-13: no current reader of `K3DM_COORDINATOR`).

- `bin/k3dm-codex-dispatch:976,978` (start) and `:1360` (resume): writers of `coordinator_identity`. Change: read the env var when no flag, record `source: env`, `status: declared`.
- `bin/k3dm-dispatch-metrics:981-985`: reader; keeps only `source == "declared"`. Changes: accept `env` too, or env-declared runs stay unattributed (the bug this fixes).
- `scripts/tests/bin/test_dispatch_metrics.py:2303,2420`, `codex_dispatch_{start,cross_repo,ledger,agy}.bats`: readers in tests; unchanged; must stay green.
- `Makefile:506` (`COORDINATOR=` passes `--coordinator`): unchanged; the flag still wins.
- Writers of the env var: coordinator sessions per the new `AGENTS.md` rule. Claude sessions keep passing `COORDINATOR=` as today.

## Acceptance

```yaml
must:
  - id: M1
    text: start and resume with K3DM_COORDINATOR=openai/gpt-6.1-sol and no flag record coordinator_identity vendor openai, model gpt-6.1-sol, source env, status declared
  - id: M2
    text: an explicit --coordinator overrides K3DM_COORDINATOR (source declared)
  - id: M3
    text: with neither set, the run proceeds (rc as today), records source unreported, and stderr has one line naming both --coordinator and K3DM_COORDINATOR
  - id: M4
    text: AGENTS.md and docs/howto/codex-dispatch.md state the env var, the precedence and the Coordinator trailer; bin/k3dm-check-agent-docs passes
  - id: M5
    text: the dashboard shows the share of start events with an unreported coordinator over the selected range
  - id: M6
    text: an invalid K3DM_COORDINATOR (bad shape, over 64 chars per side, shell metacharacters) is rejected exactly as the same invalid --coordinator value is (same rc and message), and nothing is recorded from it
  - id: M7
    text: the coordinator is never inferred from agent or worker model (with neither set and --agent agy or MODEL=gpt-6-luna, source stays unreported)
must_not:
  - id: N1
    text: with a valid K3DM_COORDINATOR and no flag, a start or resume event records source unreported (red on pre-fix code, which ignores the env var)
  - id: N2
    text: k3dm-dispatch-metrics reports a task whose start event declared its coordinator via K3DM_COORDINATOR as unknown/unreported (red on pre-fix code)
evidence:
  - id: E1
    proves: [M1, M2, M3, M6, M7, N1]
    kind: offline
    intent: "You will see tests start and resume a dispatch with K3DM_COORDINATOR set to Sol and no flag, and the ledger names Sol as coordinator; the flag still wins; with nothing set it still runs and prints how to declare one; a malformed value is refused like a bad flag. Today the env var is ignored."
  - id: E2
    proves: [M5, N2]
    kind: offline
    intent: "You will see the dispatch metrics count an env-declared Sol run under Sol, not unknown, and the Agent Dispatch dashboard gain an 'unreported coordinator share' stat, checked against a fixture ledger."
  - id: E3
    proves: [M1, M4]
    kind: live
    intent: "You run one Sol-coordinated dispatch with K3DM_COORDINATOR set; Claude shows you its ledger start event naming Sol and a commit carrying the Coordinator trailer."
interface:
  - bin/k3dm-codex-dispatch start|resume [--coordinator VENDOR/MODEL]
  - env K3DM_COORDINATOR
  - ledger.jsonl start/resume events, field coordinator_identity
  - bin/k3dm-dispatch-metrics (Pushgateway text output from a fixture ledger)
```
