# Bug: Codex dispatch has no throughput, landing, intervention or cost metrics

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** OPEN — dispatched 2026-10-09 (land-test dependency landed `c0871808`)
**Priority:** P3 — no outage; without it, parallel dispatch cannot be judged by numbers
**Severity:** low
**Origin:** operator, 2026-10-09: track fleet throughput (accepted specs/day), landing success
(% passing integration), human intervention (minutes/task) and agent efficiency (cost/accepted spec).

## Symptom

`bin/k3dm-codex-dispatch` has run six tasks on 2026-10-09. The only record is the run folders. There
is no way to answer:
- how many specs landed per day;
- how many landings passed integration tests;
- how much Claude changed after Codex finished;
- what each landed spec cost.

The data exists but is never kept:
- each `codex.log` ends with `tokens used` followed by a number (57,631 to 148,680 so far);
- `land` knows when it succeeds and why it refuses.

## Definitions

| Panel | Measure | Source |
|---|---|---|
| Fleet throughput | landed tasks per day | `land` events |
| Landing success | landed ÷ (landed + refused at the test step) | `land` and `land_refused` events with `reason="tests"` |
| Human intervention | (a) lines Claude changed between Codex's finished tree and what landed; (b) wall-clock minutes from Codex exit to land | the `codex_exit` tree and the `land` event |
| Agent efficiency | Codex tokens per landed task | the `tokens used` line in `codex.log` |

**Limits.** Show these as panel descriptions:
- (b) is **waiting time**, not active minutes.
- Cost is **Codex tokens only**. Claude's verification tokens are not recorded per task.
- Tokens are not converted to dollars, because the price per token is not stable.

## Fix

### 1. Ledger in `bin/k3dm-codex-dispatch`

- **Location.** Append one JSON line per event to `$_dispatch_worktree_root/ledger.jsonl`. It is
  shared by all versions.
- **How to write.** Write with `printf '%s\n' "$json" >>`, building the JSON with `jq -nc` so slugs
  are quoted correctly.
- **Never fatal.** A failed ledger write prints one warning and never fails the command.
- **Fields.** Every event carries `ts` (UTC epoch seconds), `event`, `version` and `slug`.

| Event | When | Extra fields |
|---|---|---|
| `start` | after the worktree is created | `network` (bool) |
| `codex_exit` | in the background subshell, after Codex exits, before writing `<run>/exit` | `exit` (int), `tokens` (int or null), `tree` (see below) |
| `land` | after `merge --ff-only` succeeds | `verifier_lines` (int), `wait_seconds` (int or null) |
| `land_refused` | when `land` refuses for scope, rebase or tests | `reason`: `scope`, `rebase` or `tests` |
| `abandon` | after `abandon --yes` | — |
| `resume` | after `resume` launches | `n` (int, the resume number) |

- `tokens` comes from the line after `^tokens used$` in `codex.log`, with commas removed. It is
  `null` when absent.
- `tree`:
  - in the subshell after Codex exits, run `git -C "$worktree" add -A`, then
    `tree=$(git -C "$worktree" write-tree)`, then `git -C "$worktree" reset -q`;
  - also write the tree id to `<run>/codex-tree`;
  - this snapshots Codex's result, untracked files included, without committing.
- `verifier_lines` is computed in `land` **before** the rebase. It is the sum of added plus deleted
  lines from `git -C "$task" diff --numstat "$(<"$run/codex-tree")" HEAD`, binary files counting as 0.
  It is 0 when `codex-tree` is missing.
- `wait_seconds` is the `land` ts minus the run's `codex_exit` ts. It is `null` if there is no
  `codex_exit`.
- **Resume** (added after `resume` landed in `c0871808`). The `resume` background subshell writes a
  `codex_exit` event exactly like `start`'s: tokens from `<run>/codex-<n>.log`, and a fresh `tree`
  that overwrites `<run>/codex-tree`. Codex reports `tokens used` as the **session total**, so a
  resumed log already includes the first run (observed: 148,680 after the first run, 246,887 after
  one resume). The exporter therefore uses each task's **latest** `codex_exit` for `tokens`, and
  `wait_seconds` / `verifier_lines` are measured from that latest exit too. Never sum `codex_exit`
  tokens across one slug.

### 2. `bin/k3dm-dispatch-metrics` (new, Python)

- **Inputs.**
  - Reads the ledger; the path comes from `K3DM_WORKTREE_ROOT`, as in the dispatcher.
  - It skips malformed lines and counts them in `k3dm_dispatch_ledger_bad_lines`.
  - It computes gauges for `window` in `1d`, `7d` and `30d`, relative to now. The windows are
    computed here because hub Prometheus keeps only 3 days.
- **Gauges** (`window` label only, apart from `result`):
  - `k3dm_dispatch_landed{window}`
  - `k3dm_dispatch_land_attempts{window,result="landed|tests|scope|rebase"}`
  - `k3dm_dispatch_codex_tokens_per_landed{window}` (mean over landed tasks with a token count; 0
    when there are none)
  - `k3dm_dispatch_verifier_lines_per_landed{window}` (mean)
  - `k3dm_dispatch_wait_minutes_per_landed{window}` (mean of `wait_seconds / 60`, non-null only)
  - `k3dm_dispatch_running`: started tasks with no `codex_exit`, `land` or `abandon`.
  - `k3dm_dispatch_awaiting_land`: tasks with a `codex_exit` and no `land` or `abandon`.
  - `k3dm_dispatch_ledger_timestamp_seconds`: when this export ran.
- **Push.**
  - PUT the text to `{URL}/metrics/job/k3dm-dispatch`, replacing the group.
  - `URL` is `K3DM_DISPATCH_PUSHGATEWAY_URL`, defaulting to `http://localhost:19094`, the hub
    Pushgateway (the same default as `bin/k3dm-vectordb-metrics`).
  - `--dry-run` prints the text and does not push.
  - A failed push exits 1 with one line. It never retries forever.
- **Labels.** Slugs, spec paths and versions never become labels; only `window` and `result` do.
- **Schedule.** The dispatcher runs `bin/k3dm-dispatch-metrics` in the background, never blocking,
  after every `codex_exit`, `land`, `land_refused` and `abandon`. Its output goes to
  `<root>/metrics.log`.

### 3. Dashboard: `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (new)

- **Shape.**
  - The same ConfigMap shape and labels as `grafana-dashboard-alertmanager-delivery.yaml`.
  - `uid` is `k3dm-agent-dispatch`, the title `k3dm Agent Dispatch`, with tags.
  - Datasource `{"type": "prometheus", "uid": "prometheus"}`.
  - A `window` custom variable (`1d`, `7d`, `30d`; default `7d`).
  - The `grafana-dashboards-hub` ApplicationSet already includes `grafana-dashboard-*.yaml`.
- **Stats (top row):**
  - Accepted specs: `k3dm_dispatch_landed{window="$window"}`.
  - Landing success:
    `k3dm_dispatch_land_attempts{window="$window",result="landed"} / sum(k3dm_dispatch_land_attempts{window="$window",result=~"landed|tests"})`.
    Unit `percentunit`; red below 0.8. The description says refusals for scope or rebase are not
    counted, because they are not integration results.
  - Claude lines changed per task: `k3dm_dispatch_verifier_lines_per_landed{window="$window"}`.
  - Wait minutes per task: `k3dm_dispatch_wait_minutes_per_landed{window="$window"}`.
  - Codex tokens per accepted spec: `k3dm_dispatch_codex_tokens_per_landed{window="$window"}`.
- **Second row:**
  - Running / awaiting land stats.
  - Land outcomes, a bar gauge of `k3dm_dispatch_land_attempts{window="$window"}` by `result`.
  - Export age: `time() - k3dm_dispatch_ledger_timestamp_seconds`, yellow above 1 day.
- Every panel description states its limit from the Definitions table.

### 4. Make and docs

- `Makefile`: `dispatch-metrics` (`bin/k3dm-dispatch-metrics`), with `DRY_RUN=1` passing
  `--dry-run`. Add it to `.PHONY`.
- `docs/howto/codex-dispatch.md`: a Metrics section covering the ledger, the four measures and their
  limits, and `make dispatch-metrics`.
- `docs/guides/grafana-dashboards.md`: add a row for the new dashboard and a section for it.
- `docs/howto/makefile.md`: a `dispatch-metrics` row.

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | item 1 |
| `bin/k3dm-dispatch-metrics` | new, item 2 |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` | new, item 3 |
| `Makefile` | `dispatch-metrics` |
| `scripts/tests/bin/codex_dispatch.bats` | ledger tests |
| `scripts/tests/bin/test_dispatch_metrics.py` | new |
| `scripts/tests/plugins/agent_dispatch_dashboard.bats` | new |
| `docs/howto/codex-dispatch.md` | Metrics section |
| `docs/guides/grafana-dashboards.md` | dashboard row + section |
| `docs/howto/makefile.md` | row |

## Tests

**`scripts/tests/bin/codex_dispatch.bats`**. The stub Codex prints `tokens used` then `12,345` at
the end of its log.
1. `start`, then exit: the ledger has `start` and `codex_exit` events with `tokens` 12345 and a
   40-character `tree`; `<run>/codex-tree` exists. The worktree index is clean afterwards, with
   nothing staged.
2. Codex's change plus one extra committed line in the worktree, then `land`: the `land` event's
   `verifier_lines` is 1 and `wait_seconds` is at least 0.
3. An out-of-scope `land`: a `land_refused` event with `reason` `scope`.
4. A ledger directory that is not writable: `start` still succeeds and prints a warning.
5. A slug containing a double quote is not possible (slugs are validated). Assert that every
   ledger line parses with `jq -e .`.
6. After a `resume` (stub prints `tokens used` then `20,000` in `codex-2.log`), the ledger has a
   `resume` event with `n` 2 and a second `codex_exit` with `tokens` 20000, and `<run>/codex-tree` is
   the new tree.

**`scripts/tests/bin/test_dispatch_metrics.py`**, with a hand-written ledger and a fixed `now`:
- exact gauge values for each window: landed counts, landing success inputs, means, `running` and
  `awaiting_land`;
- events older than 30 days are excluded from every window;
- a slug with two `codex_exit` events (12345, then 20000) counts 20000 tokens, not 32345;
- malformed lines are counted, not fatal;
- `--dry-run` never opens a connection (stub the opener and assert it is not called);
- the rendered text contains no slug.

**`scripts/tests/plugins/agent_dispatch_dashboard.bats`**:
- the JSON is valid;
- the uid and datasource are as specified;
- every `k3dm_dispatch_*` metric the dashboard queries is one the exporter emits (grep both files);
- no panels overlap.

Mutation checks. Paste the red output for each:
- Drop the `reset -q` after `write-tree`. Test 1 must fail (index not clean).
- Compute `verifier_lines` after the rebase instead of before. Test 2 must fail when the release
  branch moved. Add a release commit in that test.
- Remove the 30-day cutoff. The old-event pytest must fail.

## Rules

- `shellcheck bin/k3dm-codex-dispatch`: zero warnings.
- `bats scripts/tests/bin/codex_dispatch.bats scripts/tests/plugins/agent_dispatch_dashboard.bats`:
  all green.
- Bare `pytest scripts/tests/bin/test_dispatch_metrics.py`: green.
- Do not push to a real Pushgateway in tests.
- Do not commit. `.git` is read-only in the sandbox.
