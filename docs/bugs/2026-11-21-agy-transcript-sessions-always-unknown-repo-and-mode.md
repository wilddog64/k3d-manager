# Bug: agy sessions from transcripts always report repo and mode "unknown"

**Status:** OPEN — filed 2026-11-21; dispatched to Flash on operator instruction
**Priority:** P3
**Classified:** pending (Argon, from this doc alone)
**Waiting on:** fix running — since 2026-11-21
**Introduced by:** `b44f5efd` (fix for `docs/bugs/2026-11-04-agy-activity-no-data-local-ledger-coverage.md`, landed in v1.43.14)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Prior art:** `docs/bugs/2026-11-04-agy-activity-no-data-local-ledger-coverage.md` (found by grep, not scored) — read, same
code, different defect: that fix chose `unknown` on purpose because "the transcript holds neither" (`:112`, `:122`); this
doc shows the data is in agy's conversation DB. `make find-similar-docs` not run to a result (vector store unreachable from
the M4: `context "k3d-k3d-cluster" does not exist`, 2026-11-21).
**Approval:** operator, 2026-11-21: "can you check that then write a plan or bug ... if it is a bug then dispatch to flash"
**Intent approved:** operator, 2026-11-21
Intents E1-E6 shown to the operator after dispatch; operator confirmed 2026-11-21: "intent approve".
**Branch:** `k3d-manager-v1.45.0`
**Severity:** low — two Agent Activity panels show a single "unknown" bar; totals are correct

## Symptom

Agent Activity, row "All agy activity (including outside the dispatcher)": "agy sessions by mode"
(`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml:1049`, query `sum by (mode)` at `:1063`) and "agy
untracked by repo" (`:1100`, `sum by (repo,mode)` at `:1114`) show one bar, `unknown`. Pushgateway on `m4-air`,
2026-11-21: `k3dm_agy_sessions{mode="unknown",repo="unknown",window="7d"} 121`, `window="30d"} 298`. The Codex row beside
it splits by repo and mode.

## Root cause

The transcript branch of `_agy_metrics` (`bin/k3dm-dispatch-metrics:2356`) hard-codes
`labels = f'window="{window}",mode="unknown",repo="unknown"'` (`:2427`) and `mode="unknown"` on
`k3dm_agy_active_seconds` and `k3dm_agy_tokens`, because the 2026-11-04 fix found no working directory or mode in
`transcript_full.jsonl`. That is true of the transcript, but agy records both elsewhere.

## Capture (proof of external behaviour)

Read-only, `m4-air`, 2026-11-21, agy 1.5.14. DBs were copied (`.db`, `-wal`, `-shm`) to a scratch dir and opened there; only
`trajectory_meta` and `trajectory_metadata_blob` were read, and only path-, repo- and branch-shaped strings were printed,
with the home dir masked.

- `~/.gemini/antigravity-cli/conversations/<id>.db` exists for every brain session sampled (40 of 40); `<id>` equals the
  brain directory name, which `_agy_metrics` already uses as `session_id` (`:2375`).
- Table `trajectory_metadata_blob(id text DEFAULT "main", data blob)`: one row. `data` is protobuf. Top-level field 1 is a
  repeated workspace message (60 DBs: 24 with one, 35 with two, 1 with three), first entry = primary workspace:
  - `1.1` string, folder URI, e.g. `file:///Users/<u>/src/gitrepo/personal/dirused`
  - `1.2` string, git root URI (absent outside a git repo)
  - `1.3` message: `1.3.1` string `owner/repo` (e.g. `wilddog64/dirused`), `1.3.2` string remote URL; empty when not a repo
  - `1.4` string, branch (e.g. `main`, `task/v1.45.0/<slug>`)
  Seen: dispatch worktrees under `~/.local/share/k3d-manager/worktrees/v1.45.0/<task>` with `1.3.1`
  `wilddog64/k3d-manager` or `wilddog64/dirused`; the main checkout; Claude scratchpad dirs with an empty `1.3`.
- Mode: `trajectory_meta(trajectory_type, source)` is `(4, 17)` for all 60 sampled, so it does not separate modes.
  `~/.gemini/antigravity-cli/history.jsonl` rows (keys `display`, `timestamp`, `workspace`, `conversationId`, `type`) are
  written by interactive sessions only: 4 of 490 brain sessions appear there, none of the sampled `--print` runs do.
- Live DBs fail to open with `?mode=ro` because of WAL (2026-11-20); a copy opens normally.

## Fix

In the transcript branch only (the ledger branch `_agy_ledger_metrics` and every series name stay as they are):

1. For each in-window session, look up `conversations/<session_id>.db` beside the brain dir (`brain_root.parent /
   "conversations"`). Copy the `.db` and any `-wal`/`-shm` into a `tempfile.TemporaryDirectory`, open the copy, run exactly
   `SELECT data FROM trajectory_metadata_blob` and nothing else, close, and let the temp dir go.
2. Walk the blob with a small stdlib protobuf reader (varint and length-delimited only). Take the first top-level field 1
   message; from it take `1.3.1`. `repo` = the part after the last `/`, kept only if it matches `[A-Za-z0-9._-]{1,64}`,
   else `other`. No first entry or empty `1.3` (not a repo) → `other`. DB missing, unreadable, or blob not parseable →
   `unknown` (the session still counts; nothing fails).
3. Apply the ledger branch's top-10 rule: repos outside the 10 most frequent in the 30 d set become `other`.
4. `mode` = `interactive` when `session_id` is a `conversationId` in `history.jsonl`, else `print` (the values the ledger
   branch uses, `:2327`). Read only the `conversationId` key of each row; a missing or unreadable file means `print`.
5. Emit `k3dm_agy_sessions` and `k3dm_agy_untracked_sessions` per `(mode, repo)`, and `k3dm_agy_active_seconds` and
   `k3dm_agy_tokens` per `mode`, with the same label names as today.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `docs/guides/grafana-dashboards/k3dm-agent-activity.md` (one sentence: where agy repo and mode come from)

## Contract readers

| Contract | Writer | Readers | Change |
|---|---|---|---|
| `k3dm_agy_sessions{window,mode,repo}`, `k3dm_agy_untracked_sessions{window,mode,repo}` | `bin/k3dm-dispatch-metrics:2336-2338` (ledger), `:2427-2429` (transcripts) | `grafana-dashboard-agent-activity.yaml:930`, `:976`, `:1063`, `:1114` | label values only: `print`/`interactive` and repo names instead of `unknown` |
| `k3dm_agy_active_seconds{window,mode}`, `k3dm_agy_tokens{window,mode,kind}` | `:2340`, `:2353`, `:2430-2432` | `:1022`, `:1170`; `docs/plans/lead-model-activity-dashboard.md` (planned) | mode value only |
| `~/.gemini/antigravity-cli/conversations/<id>.db` | agy | new reader: this fix (copies only); planned `docs/plans/agy-quota-dashboard.md` child A | new reader |
| `~/.gemini/antigravity-cli/history.jsonl` | agy | new reader: this fix (`conversationId` only) | new reader |

## Acceptance

```yaml
must:
  - M1: a brain session whose conversation DB's first workspace has 1.3.1 "owner/k3d-manager" is reported with repo="k3d-manager" in k3dm_agy_sessions and k3dm_agy_untracked_sessions
  - M2: a session whose first workspace has an empty 1.3 (not a git repo) is reported with repo="other"
  - M3: a session with no conversation DB, or a DB whose blob does not parse, is still counted, with repo="unknown"
  - M4: a session whose id is a conversationId in history.jsonl has mode="interactive"; one that is not, or with history.jsonl missing, has mode="print"
  - M5: only the first top-level field-1 entry decides the repo (a second entry naming another repo does not change it)
  - M6: session counts, untracked counts, active seconds and token sums per window equal today's totals for the same fixtures (only label values move)
  - M7: the ledger branch output is byte-identical for the existing ledger fixtures
must_not:
  - N1: open a live DB in ~/.gemini, or create, modify or delete any file under the agy home (hash every fixture file before and after)
  - N2: query any table other than trajectory_metadata_blob, or read the steps, gen_metadata or executor_metadata tables
  - N3: read the display key of history.jsonl, or the content, thinking or tool_calls keys of transcripts
  - N4: put an owner name, remote URL, path or branch into any metric label (repo is the bare name after the last "/")
  - N5: drop a session or fail the run because its DB is missing, locked or malformed
evidence:
  - E1: {proves: [M1, M2, M5, N4], offline: true, intent: "agy sessions are filed under the repo agy itself recorded (k3d-manager, dirused), scratch runs under other, and no GitHub owner, URL or folder path ever reaches a label"}
  - E2: {proves: [M3, N5], offline: true, intent: "a session with a missing or broken agy database still counts, as unknown, and the metrics run does not fail"}
  - E3: {proves: [M4, N3], offline: true, intent: "interactive agy sessions show as interactive and --print runs as print, without reading what you typed"}
  - E4: {proves: [M6, M7], offline: true, intent: "the totals on the panels do not change, only the split; the dispatcher-ledger path is untouched"}
  - E5: {proves: [N1, N2], offline: true, intent: "the reader works on a copy, touches only the workspace table, and leaves agy's files byte-identical"}
  - E6: {proves: [M1, M4], live: true, intent: "on the M4 after the next metrics push, 'agy sessions by mode' shows print (and interactive if any) and 'agy untracked by repo' shows k3d-manager, dirused and other instead of one unknown bar"}
interface:
  - bin/k3dm-dispatch-metrics (_agy_metrics transcript branch)
  - series k3dm_agy_sessions, k3dm_agy_untracked_sessions, k3dm_agy_active_seconds, k3dm_agy_tokens (label values)
```

**Fixtures.** Build the DBs in the test with `sqlite3` from the schema and field layout in the Capture section (no copy of
a real DB enters the repo); put a comment naming host `m4-air`, date 2026-11-21, agy 1.5.14. Each fixture first asserts it
sits under `tmp_path` (scratch HOME, `K3DM_AGY_BRAIN_DIR` pointed there). Pair the N1/N5 tests with a positive control (the
same fixture with a good DB reports the real repo). Every `must_not` must be red on `b44f5efd`'s behaviour or on a naive
reader (`SELECT *`, `?mode=ro` on the original path, label = full `owner/repo`).
