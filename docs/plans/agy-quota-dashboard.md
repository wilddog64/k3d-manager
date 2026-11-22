# agy token and quota row on Agent Cost, like Fable's

**Status:** DRAFT — written 2026-11-21 for grooming 2026-11-22; proposed as its own backlog plan, pulled out of `docs/plans/argon-bug-classifier.md` (which keeps the classifier and reuses this reader)
**Approval:** operator, 2026-11-21 ("can those info help you to build the agy token 5-hour/weekly quota like Fable"; "yes, please" to writing this plan)
**Intent approved:** pending
**Filed:** 2026-11-21
**Branch:** next open minor after grooming (not v1.45.0: it is at its plan cap)
**Source:** `docs/ideas.md:58` (2026-11-12, Argon token chart like Fable's), `docs/plans/argon-bug-classifier.md` `## Quota calibration evidence` (point 1, 2026-11-21)
**Split:** parent (this file: the metric contract) + child A (Luna, reader and metrics) + child B (Flash, dashboard and docs). No file is shared between A and B, so they can run in parallel (one dispatch per file). Operator, 2026-11-21: "split it into smaller pieces across flash and Luna".

## Problem

The Agent Cost dashboard shows Fable and Codex tokens per day and their 5-hour and weekly limits
(`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml:1528` "Fable tokens per day", `:1573` "Fable weekly
limit", `:1828`/`:1913` Codex weekly/5h). agy models (Gemini 3.8 Flash, Gemini 4 Argon, Hydrogen, and agy's Claude/GPT-OSS
pool) have none of this. Ad-hoc agy runs (Flash audits, Argon classifications) are not counted anywhere; dispatched agy runs are
priced per task only (`_agy_cost`, `bin/k3dm-dispatch-metrics:778`).

agy has no quota command and stores no limits. What is local, proven 2026-11-21 on the M4:
- every agy call writes a `gen_metadata` protobuf row to `~/.gemini/antigravity-cli/conversations/<id>.db` with model display
  name (field 1.21), input tokens (1.4.2, equals agy JSON `input_tokens`) and output tokens (1.4.3). Rows carry no timestamp.
- quota windows start at the first call: the window starts derived from the operator's panel screenshot (04:18 weekly, 14:11
  5-hour) equal the creation times of the two conversation DBs of that day, to the minute.
- the agy panel groups quota into pools: Gemini (Neon, Hydrogen, Orchestrator, 3.8 Flash; 5 h + weekly), Claude and GPT
  (Opus 5.5, Sonnet 5.5, GPT-OSS 120B; 5 h + weekly), Gemini 4 Argon (separate, weekly only on Pro).

## Goal

A "Gemini (agy)" row on Agent Cost, next to the Fable row: tokens per day by model (exact), and per pool a "% used (est.)"
gauge plus a "resets at" gauge (exact). Percentages are estimates from operator calibration points and are labelled so.

## Metric contract (parent; both children code to this, neither changes it)

Pushed by child A to the existing Pushgateway (`K3DM_DISPATCH_PUSHGATEWAY_URL`, default `http://localhost:19094`) as group
`k3dm-agy-usage`, instance = short hostname:

| Series | Labels | Meaning |
|---|---|---|
| `k3dm_agy_daily_tokens` | `date` (YYYY-MM-DD, local), `model` (display name lowercased, spaces to `-`), `kind` (`input`/`output`) | exact tokens per local day, last 14 days |
| `k3dm_agy_quota_window_tokens` | `pool` (`gemini`/`claude_gpt`/`argon`), `limit` (`five_hour`/`weekly`) | input + output tokens in the current window; 0 when no window is open |
| `k3dm_agy_quota_resets_at_seconds` | `pool`, `limit` | window start + 5 h or + 7 d; series absent when no window is open |
| `k3dm_agy_quota_budget_tokens` | `pool`, `limit` | estimated limit from the calibration file; absent when the pool has no calibration |
| `k3dm_agy_quota_used_ratio` | `pool`, `limit`, `basis="estimated"` | window tokens / budget; absent (never 0, never 1) when no budget |
| `k3dm_agy_quota_calibrated_at_seconds` | `pool`, `limit` | time of the newest calibration point used |
| `k3dm_agy_quota_sample_timestamp_seconds` | — | when this sample was taken |

Pool of a row: model name contains `Argon` → `argon`; `Claude` or `GPT` → `claude_gpt`; any other `Gemini` → `gemini`;
anything else → not counted in a pool (still in daily tokens). Argon has no `five_hour` series.

**Calibration file** (new, `scripts/etc/agent/agy-quota-calibration.json`, written by hand from operator screenshots): a list of
points `{at, pool, limit, remaining_percent, window_tokens}`; budget = mean of `window_tokens / (1 - remaining/100)` over points
with used ≥ 1% (smaller readings are rounding noise). Seeded with point 1 (2026-11-21 16:28 PST): gemini five_hour 97.69% /
299,728; gemini weekly 96.40% / 1,173,149.

**Call times without timestamps.** Child A keeps a state file (`~/.local/state/k3d-manager/agy-usage/rows.json`: per DB, rows
seen and the time first seen). Rows new since the last sample get that sample's time (resolution = sample interval). On the very
first run, all existing rows of a DB take its modification time. A resumed conversation (dispatch `resume` reuses a DB) therefore
gets its new rows at the right time, not the DB's creation time. A window opens at the first row after the previous window
closed.

## Child A — reader and metrics (Luna, `gpt-6-luna`)

Files: `bin/k3dm-agy-usage-metrics` (new, Python, stdlib only), `scripts/etc/agent/agy-quota-calibration.json` (new),
`scripts/tests/bin/test_agy_usage_metrics.py` (new), `scripts/tests/fixtures/agy-usage/` (new; DB fixture built from a real
read-only capture, host/date/agy version in a comment), and one call line at the end of the scheduled metrics run in
`bin/k3dm-dispatch-metrics` (exact place named in the spec after `schedule-metrics` is traced; Open question 1).

DB access: copy `*.db`, `*.db-wal`, `*.db-shm` to a private temp dir, open the copy read-only, delete it after (live DBs fail
under `mode=ro` because of WAL, 2026-11-20). Select only `gen_metadata.idx` and `gen_metadata.data`. Pure-Python varint walker
(protoc is not installed). Never print or store anything from `data` except fields 1.21, 1.4.2, 1.4.3.

## Child B — dashboard and docs (Flash, `gemini-3.8-flash-medium`)

Files: `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml` (new row "Gemini (agy)" after the Fable row:
"Gemini tokens per day" stacked bars by model; per pool "Gemini 5h limit (est.)", "Gemini weekly limit (est.)", "Claude/GPT in
agy 5h (est.)", "… weekly (est.)", "Argon weekly limit (est.)"; each gauge paired with "resets at" like `:1573-1600`; a stat
"agy quota reading age" like Codex `:2049`), `scripts/tests/bin/agy_quota_dashboard.bats` (new),
`docs/howto/agent-cost-dashboard.md` or the existing Agent Cost how-to (one section: what is exact, what is estimated, how to add
a calibration point). Panel descriptions say "estimate from N calibration points, newest <date>; the agy panel is the truth".

## Revision 2026-11-21 (evening): better source, and Agent Activity scope

**Source.** The brain transcripts (`~/.gemini/antigravity-cli/brain/<conversation>/.system_generated/logs/transcript_full.jsonl`,
already read by `_agy_metrics`, `bin/k3dm-dispatch-metrics:2356`) carry per step `created_at`, `model` and
`input_tokens`/`cache_read_tokens`/`output_tokens` (key census on the M4, 2026-11-21: 490 transcripts; models
`gemini-3.8-flash-medium`, `gemini-4-argon-medium`). Per-step timestamps remove the state-file timing above, so child A reads
the transcripts first and uses the conversation DBs only to fill in a missing model name. Caveat: 1,248 of 1,932 token rows in
a sample of 80 transcripts have `model`; the rest take the session's last named model, else `unknown`. Keys `content`,
`thinking`, `tool_calls` hold prompt and reply text and are never read (same rule as N1).

**Agent Activity.** The row "All agy activity (including outside the dispatcher)" already exists
(`grafana-dashboard-agent-activity.yaml:899-1220`: sessions, untracked, active hours, by mode, untracked by repo, tokens) and
gets data (pushed 2026-11-21: 121 sessions/7 d, 18.7M input, 3.1M output, 476M cache read). But the transcript branch labels
every session `mode="unknown",repo="unknown"` (`:2427`), so the by-mode and by-repo bars show one bar. Child A also fills:
- `mode`: `interactive` when the conversation id is in `~/.gemini/antigravity-cli/history.jsonl` (keys `workspace`,
  `conversationId`, `timestamp`, `type` only; `display` holds the typed prompt and is never read), else `exec`.
- `repo`: dispatched sessions from the ledger (session = conversation id, already matched for `untracked`); interactive from
  history `workspace`; untracked exec sessions `unknown` (history covers only 4 of 490 conversations, all interactive). Open
  question 5: whether `trajectory_metadata_blob` in the conversation DB holds the workspace (schema seen, contents not read).
- new `k3dm_agy_tokens_by_repo{window,repo,kind}` and `k3dm_agy_tokens_by_model{window,model,kind}`; child B adds
  "agy tokens by repo" and "agy tokens by model" bar gauges beside the existing "agy tokens" stat, like Codex "Tokens by repo"
  (`:555`). The existing series keep their names and labels (readers `:916-1220`).

## Contract readers

| Contract | Writer | Readers | Change |
|---|---|---|---|
| Pushgateway group `k3dm-agy-usage`, series above | child A | child B panels only | new |
| `scripts/etc/agent/agy-quota-calibration.json` | operator/Claude by hand | child A | new |
| `~/.gemini/antigravity-cli/conversations/*.db` | agy | child A (copies only); `docs/plans/argon-bug-classifier.md` guard (planned) will import child A's reader | new reader |
| `bin/k3dm-dispatch-metrics` scheduled run | existing | child A adds one call | one line |
| `k3dm_agy_tokens` (`bin/k3dm-dispatch-metrics:2353`, brain-dir sessions) | existing | Agent Activity panels | unchanged, not reused |
| `scripts/etc/agent/codex-model-prices.json` Gemini rates | existing | `_agy_cost` | unchanged (pricing is not part of this plan) |

## Acceptance

```yaml
must:
  - M1: from a fixture DB with Flash, Argon and Claude rows, daily tokens per model and kind equal the fixture sums
  - M2: pool window tokens count only that pool's rows inside the open window; Argon rows never count in gemini
  - M3: a window opens at the first row after the previous one closed; resets_at = start + 18000 s (five_hour) or + 604800 s (weekly)
  - M4: rows added to an existing DB after a sample are timed at the next sample, not at the DB's creation or first-sample time
  - M5: used_ratio = window tokens / budget, labelled basis="estimated"; budget is computed from the calibration file per the rule above
  - M6: with point 1 seeded and the point-1 fixture, gemini five_hour used_ratio is 0.0231 ±0.0005 and weekly 0.0360 ±0.0005
  - M7: dashboard row exists after the Fable row; every gauge title ends "(est.)", every query names a k3dm_agy_quota_* or k3dm_agy_daily_tokens series
must_not:
  - N1: read, print or store the steps table, any column but gen_metadata.idx/data, or any protobuf field but 1.21/1.4.2/1.4.3
  - N2: open a live DB, or create, modify or delete anything under ~/.gemini
  - N3: publish used_ratio or budget for a pool/limit with no calibration point (no fake 0% or 100%)
  - N4: publish a five_hour series for argon
  - N5: put the operator's account e-mail or any credential into a metric, label, log or fixture
evidence:
  - E1: {proves: [M1, M2, N4], offline: true, intent: "tokens from a sample agy database land on the right model and pool, Argon stays in its own bucket, and Argon has no 5-hour gauge"}
  - E2: {proves: [M3, M4], offline: true, intent: "the reset time matches how agy starts windows (at the first call), including when an old conversation is resumed later"}
  - E3: {proves: [M5, M6, N3], offline: true, intent: "today's screenshot reproduces as 2.31% and 3.60%, and a pool you never calibrated shows no gauge instead of a made-up number"}
  - E4: {proves: [N1, N2, N5], offline: true, intent: "the reader never sees your prompts, never touches agy's own files (hashes before and after), and never writes your account name anywhere"}
  - E5: {proves: [M7], offline: true, intent: "the new row is on Agent Cost beside Fable's, says (est.) on every gauge, and reads only series the reader publishes"}
  - E6: {proves: [M3, M6], live: true, intent: "on the M4, after one Flash run, the dashboard's Gemini 5h reset time matches the agy panel's 'Refreshes in' within the sample interval, and the % is within 30% of the panel"}
interface:
  - bin/k3dm-agy-usage-metrics
  - scripts/etc/agent/agy-quota-calibration.json
  - Pushgateway group k3dm-agy-usage
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml (row "Gemini (agy)")
```

**Fixture precondition (before dispatch).** Child A's DB fixture comes from a real read-only capture on the M4: a few
`gen_metadata` rows with Flash and (once one exists) Argon and Claude rows, prompt-bearing tables dropped from the copy before it
enters the repo. Child B tests against child A's published series names only (this contract), not against child A's code, so B
does not wait for A.

## Open questions

1. Where child A runs: one line at the end of the scheduled `bin/k3dm-dispatch-metrics` run (recommended: no new LaunchAgent,
   Makefile untouched) vs. its own LaunchAgent.
2. Machines: the quota is account-wide but the DBs are per machine. Does agy run anywhere but the M4 (M2, m4/m5-air, hub)? If
   yes, each machine pushes its own instance and the panels `sum by (pool, limit)`, and the window start is the earliest across
   instances; if no, the panels say "M4 only (lower bound)".
3. Calibration cadence: one operator screenshot per week (after a heavy day, and one after an Argon batch) until three points
   agree within 10%, then monthly.
4. Whether cache reads count against the limit: point 1 cannot tell (cache reads 1.75M in the 5 h window). A second point with
   a different cache share will.
5. Repo for untracked exec runs (ad-hoc Flash audits): probe `trajectory_metadata_blob` for a workspace path (path-shaped
   strings only, from a copy), or accept `unknown`.
