# Automate Argon bug classification, with a quota guard

**Status:** DRAFT — written 2026-11-15; ordered backlog position 2 at grooming 2026-11-15 (operator: "Accept"), merged with the 2026-11-12 Argon/Flash token chart idea (build the agy usage reader once); waits on intent approval, the open questions, and a capture-built fixture
**Approval:** operator, 2026-11-15 (prompt-debt T4: "automate Argon review ... pay attention to his 5-hour/weekly quota"; Fable stays manual)
**Intent approved:** pending
**Filed:** 2026-11-15
**Branch:** `k3d-manager-v1.45.0` (not yet cut; see Open questions for the branch the job commits to)
**Source:** `docs/ideas.md` rows 2026-11-15 (`:78`, this idea) and 2026-11-12 (`:58`, Argon token chart; folded in below)
**Related:** `docs/process/rules.md:67` (second-agent classification rule), `docs/reviews/reviewer-trial-fable-vs-argon.md`

## Problem

Capture-first triage (`docs/process/rules.md:67`) says Gemini 4.0 Argon (`gemini-4-argon-medium`) reads only the bug
doc and gives a Priority, recorded as `**Classified:** <P> by <agent>, YYYY-MM-DD`. It is manual. Only 43 of 80 (2026-11-11…15, counted 2026-11-15)
recent bugs got one (operator count, 2026-11-15), and some docs sit at `**Classified:** pending (Argon, from this doc
alone)` (`docs/bugs/2026-11-13-agent-cost-turns-panel-mostly-blank-under-30-day-range.md:5`). A real result looks like
`docs/bugs/2026-11-13-dev-hub-sync-without-vcluster-gives-raw-kubeconfig-error.md:5` (`P3 by gemini-4-argon-medium,
2026-11-14 (<one-line reason>)`); when Claude's proposal is lower, the line appends `; Claude proposed P3. Higher
stands until the operator decides.` (`docs/bugs/2026-11-10-hub-promote-status-ahead-counts-local-release-branch.md:5`).

A pre-commit hook is wrong: runs take 1-20 minutes and can fail on quota. Hermes is wrong: it cycles every 300 s on
the M5 and must not wait on model calls. Argon has Google 5-hour and weekly limits, agy has no quota command, and
operator-run reviews (spec and diff review, `docs/process/rules.md:126-130`) must never be starved by the batch.

## Goal

A separate launchd LaunchAgent on the M4 (worker role) finds bug docs without a `**Classified:**` line, classifies
at most N per run read-only with Argon, writes the line, and commits it. A quota guard built from our own recorded
Argon tokens keeps the job inside budgets and backs off on a quota error. Three panels on the existing Agent Activity
dashboard show backlog, tokens against budget, and skipped runs. Fable is never automated.

## Design

**Command.** New `bin/k3dm-bug-classify` (Python, `set -euo pipefail`-equivalent exit discipline), run by a new
LaunchAgent `com.k3d-manager.bug-classify` copied from the `test-metrics` pattern: template
`scripts/etc/launchd/com.k3d-manager.test-metrics.plist.tmpl` (ProgramArguments, `{{K3DM_REPO_ROOT}}`, `{{HOME}}`,
PATH) with `StartInterval` instead of `StartCalendarInterval`, installed by a new `install-bug-classify` Make target
modelled on `Makefile:106-117` (sed the template, `K3DM_AGENT_LOAD != 0` gate, `launchctl bootout`/`bootstrap`) and
`uninstall-bug-classify` modelled on `Makefile:84-87`. The worker role manifest `scripts/etc/machine/agents.worker.list`
(`:2-4`, one action per line, run by `run_agents`, `bin/k3dm-machine-setup:714-720`) gets `install-bug-classify`.

**Selection.** Scan `docs/bugs/*.md` in the working checkout; a doc is a candidate when it has no line starting
`**Classified:** ` or its line starts `**Classified:** pending`. A doc whose Classified line holds a priority is never
touched (not even to refine it). Oldest first, at most `K3DM_CLASSIFY_MAX_PER_RUN` per run.

**Classify.** `agy -p "<prompt>" --model gemini-4-argon-medium --print-timeout 1200s`, no
`--dangerously-skip-permissions` (read-only). The prompt gives only the doc path and the Priority definitions from
`CLAUDE.md` (P0-P3) and asks for one line: `<P> by gemini-4-argon-medium, <today> (<reason, one sentence>)`. It does
not include Claude's Priority reasoning; the job appends `; Claude proposed <P>. Higher stands until the operator
decides.` itself when the doc's `**Priority:**` is lower. The job validates the reply against a strict regex and
discards anything else (the doc stays a candidate and counts as a failed attempt).

**Quota guard** (before every doc, not only at run start). agy has no quota command and Google's limits are not
stored locally, so the guard measures our own use: open each `~/.gemini/antigravity-cli/conversations/*.db`
read-only (`file:<path>?mode=ro` URI) and read `gen_metadata` (one protobuf blob per model call). Inferred field map
(proven 2026-11-12 on the M4, `docs/ideas.md:58`; corrected 2026-11-21, see `## Quota calibration evidence`): `1.21`
model display name (`Gemini 4 Argon (Medium)`), `1.4.2` input, `1.4.3` output. The reader itself now comes from
`docs/plans/agy-quota-dashboard.md` child A; this job imports it. Sum output tokens of Argon rows over the last 5 h and 7 d. The job never
selects, reads or prints the `steps` table's blobs (they hold prompt text). Rules:
1. Skip the run (exit 0, `skipped_reason=budget`) when 5 h or 7 d output tokens plus the per-doc estimate would pass
   `K3DM_CLASSIFY_BUDGET_5H` or `K3DM_CLASSIFY_BUDGET_7D`. The budgets already hold back the operator headroom: they
   are a share of the true limit, set by the operator (defaults: Open questions).
2. A quota error from agy (non-zero exit with a quota or rate-limit message, matched on exit code and a fixed phrase
   list from the real capture) stops the run, writes `~/.local/state/k3d-manager/bug-classify.backoff` with an expiry
   (`K3DM_CLASSIFY_BACKOFF_SECONDS`), and later runs skip until it expires (`skipped_reason=quota_error`).
3. A DB that cannot be read, or whose model-name field matches no Argon row ever, fails closed: skip the run
   (`skipped_reason=guard_unreadable`). Never classify without a reading.

**Write and commit.** For each accepted line the job inserts `**Classified:** <line>` directly under the doc's
Status/Priority header lines (replacing a `pending` line in place), then commits the touched docs in one commit with
the fixed message `docs(bugs): Argon classification of <n> bug doc(s) [automated]` plus the attribution lines the
repo uses. The job runs `git commit` as a separate step after all agy calls finish; it never runs inside, or waits
on, a model call, and it never runs under a git hook. It does not push (Open question: branch, PR instead).

**Metrics** (Pushgateway, same path as the other agent and bug series). `bin/k3dm-dispatch-metrics` writes agent
series (`k3dm_agy_tokens`, `bin/k3dm-dispatch-metrics:2341`) and pushes to `K3DM_DISPATCH_PUSHGATEWAY_URL`
(`:2974`, default `http://localhost:19094`); bug-doc series are pushed by `_push_bug_group`
(`bin/k3dm-vectordb-metrics:1129-1140`, `publish_bug_metrics :1031`). The new job pushes its own group
`k3dm-bug-classify` the same way (health check on `/-/healthy`, then POST) after each run, including skipped runs:
- `k3dm_bug_classify_backlog{repo}`: docs without a real Classified line.
- `k3dm_bug_classify_argon_output_tokens{window="5h|7d"}` and `k3dm_bug_classify_budget_tokens{window}`.
- `k3dm_bug_classify_runs_total{result="classified|skipped_budget|skipped_quota_error|skipped_guard_unreadable|failed"}`
  (gauge of the last 24 h count, since a pushed counter would reset with the group).
- `k3dm_bug_classify_last_run_timestamp_seconds`.

This also folds in the 2026-11-12 idea row: its "Argon tokens per day by model" series is the same DB read, so the
job's token reader is written as a reusable function (`argon_tokens(window)`) that the Agent Cost chart can call
later; the daily-bars chart itself stays on that row (Open question 5).

**Dashboard.** No new dashboard. Add to `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`,
under the row "All agy activity (including outside the dispatcher)" (`:1206`, near the "agy sessions" stat `:1223`):
(1) stat "Bug classification backlog"; (2) timeseries "Our Argon output tokens (5 h / 7 d) vs budget" with the budget
as a threshold line; (3) stat "Classifier runs skipped (24 h)" by reason. Use the same `$window`-independent query
style as the neighbours (the existing panels key on `window="$window"`; the new ones must not, because 5 h and 7 d are
fixed windows).

## Files

- `bin/k3dm-bug-classify`
- `scripts/etc/launchd/com.k3d-manager.bug-classify.plist.tmpl`
- `Makefile`
- `scripts/etc/machine/agents.worker.list`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
- `scripts/tests/bin/test_bug_classify.py`
- `scripts/tests/fixtures/bug-classify/` (stub agy, Argon DB fixture, bug-doc fixtures)
- `docs/howto/` one short section: install, budgets, reading the panels

## Contract readers

New contracts: the `**Classified:**` line (writer is now also the job), the `k3dm-bug-classify` series, the backoff
file, the env vars `K3DM_CLASSIFY_*`, the LaunchAgent label.

| Contract | Reader / writer | Change |
|---|---|---|
| `**Classified:** <P> by <agent>, <date> (...)` line in `docs/bugs/*.md` | writer: manual by Claude and Argon today (`docs/process/rules.md:67`); new writer `bin/k3dm-bug-classify` | job writes only when absent or `pending` |
| same line | readers: none in code — `grep -rn "Classified" bin scripts .githooks` (Claude, 2026-11-15) returns nothing; `scripts/check-bug-status.py` does not read it. Readers are humans and grooming only | new writer: `bin/k3dm-bug-classify` |
| `~/.gemini/antigravity-cli/conversations/*.db` `gen_metadata` | reader: new job only; existing agy readers use `~/.gemini/antigravity-cli/brain` (`bin/k3dm-dispatch-metrics:2346`), not these DBs; writer is agy itself | read-only, `mode=ro` |
| Pushgateway group `k3dm-bug-classify` | writer: new job; readers: three new panels in `grafana-dashboard-agent-activity.yaml` | new |
| `k3dm_bug_docs*` (`bin/k3dm-vectordb-metrics:181`) | writer `publish_bug_metrics`; readers `grafana-dashboard-bugs.yaml:348,1042,1607` | unchanged, not reused for the backlog (see Open question 4) |
| launchd label `com.k3d-manager.bug-classify` | writer: `Makefile` install target; reader: `agents.worker.list` via `run_agents` (`bin/k3dm-machine-setup:714-720`) | new |
| worker manifest `agents.worker.list` | reader `bin/k3dm-machine-setup:68,720`; `scripts/etc/machine/not-installed.list` (check for a listing rule) | one added line |

## Acceptance

```yaml
must:
  - M1: given 3 unclassified docs, 1 doc with "Classified: pending", and 1 doc with "Classified: P2 by ...", a run with MAX_PER_RUN=2 and budgets not exceeded calls agy twice, writes a valid Classified line into the two oldest candidates, and leaves the other candidates and the already-classified doc byte-identical
  - M2: agy is invoked with --model gemini-4-argon-medium, --print-timeout 1200s, and without --dangerously-skip-permissions
  - M3: when output tokens of Argon rows in the last 5 h (or 7 d) plus the estimate exceed the budget, the run calls agy zero times, edits nothing, commits nothing, and publishes runs_total{result="skipped_budget"}
  - M4: a quota error from agy stops the run after that doc, leaves that doc unchanged, writes the backoff file, and the next run inside the backoff window calls agy zero times
  - M5: the guard counts only rows whose model name is Argon (Medium) and only rows inside the window; Flash rows and rows older than the window are not counted
  - M6: one commit per run holds all edited docs with the fixed message; an unparseable agy reply leaves the doc a candidate
  - M7: the pushed series include backlog, tokens 5h and 7d, budgets, and runs_total by result, also on a skipped run
  - M8: the three dashboard panels exist in grafana-dashboard-agent-activity.yaml and their queries name the new series
must_not:
  - N1: classify any doc while 5 h or 7 d Argon tokens plus estimate exceed the budget (red on a naive loop that only checks budget once at start, or not at all)
  - N2: select, read, or print the steps table, any blob outside gen_metadata, or prompt text (red on a SELECT * or a dump of the DB)
  - N3: open a conversation DB writable, or create or modify any file under ~/.gemini
  - N4: edit a doc that already carries a Classified line with a priority, or rewrite any other line of a doc
  - N5: run git commit inside a model call, under a git hook, or before every agy call of the run has returned; or push
  - N6: invoke any Fable or Claude model, or pass --dangerously-skip-permissions
  - N7: classify when the guard cannot read the DB (missing, locked, unknown schema) or finds no Argon row at all
  - N8: run inside Hermes or add a call to the Hermes cycle (bin/k3dm-hermes, scripts/lib/hermes/)
  - N9: put a Vault token, API key, or any secret into agy arguments, the log, or the commit message
evidence:
  - E1: {proves: [M1, N4, M6], offline: true, intent: "with a stub agy and a scratch copy of the bug docs, only the unclassified docs change, only up to the per-run limit, and finished docs are never touched"}
  - E2: {proves: [M2, N6], offline: true, intent: "the stub agy records its arguments, so you can see Argon is called read-only and no Fable or Claude model is ever run"}
  - E3: {proves: [M3, N1, M5], offline: true, intent: "with a fixture DB just under and just over each budget, the job classifies in the first case and does nothing in the second; the positive control (just under) proves the guard is not simply blocking everything"}
  - E4: {proves: [M4], offline: true, intent: "a quota error from agy makes the job stop and stay quiet until the backoff passes, instead of hammering Google's limit"}
  - E5: {proves: [N2, N3], offline: true, intent: "the job reads only the token counts from the Argon DBs, never your prompts, and leaves the DB files untouched (hash before and after)"}
  - E6: {proves: [N5, M6], offline: true, intent: "the commit happens once, after all model calls are done, never inside a git hook, and nothing is pushed"}
  - E7: {proves: [N7], offline: true, intent: "if the token DB is missing or unreadable, the job refuses to spend any Argon quota"}
  - E8: {proves: [M7, M8], offline: true, intent: "the backlog, token and skipped-run panels exist and read series the job really pushes"}
  - E9: {proves: [M1, M3, N8], live: true, intent: "on the M4, after install, one real run classifies one real unclassified bug, the panels show the backlog drop and tokens against budget, and Hermes on the M5 is untouched"}
interface:
  - bin/k3dm-bug-classify (run by launchd on the worker role)
  - make install-bug-classify, make uninstall-bug-classify
  - scripts/etc/machine/agents.worker.list
  - env: K3DM_CLASSIFY_BUDGET_5H, K3DM_CLASSIFY_BUDGET_7D, K3DM_CLASSIFY_MAX_PER_RUN, K3DM_CLASSIFY_BACKOFF_SECONDS
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml
```

**Fixture precondition (TODO before dispatch).** The Argon DB fixture and the stub agy quota-error output must come
from a real read-only capture on the M4 (host, date, agy version in a comment), per the Test controls rule. Needed:
a small `gen_metadata` sample with Argon and non-Argon rows (field map confirmed, not just inferred), and the real
agy stderr and exit code for a quota error (not yet seen; if it cannot be captured, M4 stays unproven and the phrase
list is a guess to flag). Fixtures assert their target first (scratch HOME, stub agy on PATH, temp repo).

## Quota calibration evidence

**Point 1 — 2026-11-21 16:28 PST, M4** (operator screenshot of agy `Models & Quota`; tokens decoded read-only from copies of
`~/.gemini/antigravity-cli/conversations/*.db`, `gen_metadata`).

| Pool (agy panel) | Window | Remaining | Refreshes in | Window start (derived) | Our use in window |
|---|---|---|---|---|---|
| Gemini (Neon, Hydrogen, Orchestrator, 3.8 Flash) | 5 h | 97.69% | 2h 43m | 14:11 | 1 conversation (Flash audit, 19 calls): input 187,402, output 112,326 (97,127 thinking), cache read 1,751,464 |
| Gemini | weekly | 96.40% | 155h 50m | 04:18 (11-21) | 2 conversations, 236 Flash calls: input 918,723, output 254,426 |
| Claude and GPT (Opus 5.5, Sonnet 5.5, GPT-OSS 120B) | 5 h / weekly | 100% / 100% | — | — | none |
| Gemini 4 Argon (separate on Pro) | weekly only | 100% | — | — | none in window |

Findings:
- Windows start at the first call, not on a clock: the derived starts match the creation times of the two conversation DBs
  exactly (04:18 and 14:11). A window with no use shows "Quota available" and no refresh time.
- Estimated Gemini budgets from this one point (input + output, cache reads excluded): 5 h ≈ 299,728 / 2.31% ≈ 13.0M;
  weekly ≈ 1,173,149 / 3.60% ≈ 32.6M. Treat as ±30% until more points: whether cache reads or thinking tokens are weighted
  differently is unknown, and the panel rounds to 0.01%.
- Argon has its own weekly bucket with no 5 h limit shown; the quota guard for Argon classification needs a weekly budget only.
- Field map correction: `gen_metadata` 1.4.2 is input tokens (it equals agy JSON `input_tokens`), not cached input.
- Next points: record the panel again after a heavier Flash day and after an Argon batch, with the time, so the estimate can
  be checked against a second and third point.

## Open questions

1. **Budgets and N defaults.** Argon output tokens of ours are about 485K since 2026-11-05 (`docs/ideas.md:58`), but
   the true Google limit is unknown. Operator to set `K3DM_CLASSIFY_BUDGET_5H` and `_7D` (suggest starting low, e.g.
   a small share, and raising from the panel), `K3DM_CLASSIFY_MAX_PER_RUN` (suggest 3), and the per-doc estimate
   (data: 869,027 tokens for 76 classifications = about 11.4K each, `docs/ideas.md:58`; whether that figure is
   input plus output or output only is not stated, confirm).
2. **Schedule interval.** `StartInterval` seconds (suggest 3600). Run at load? (suggest no, as `test-metrics` does).
3. **Commit versus PR.** Where does the job commit: the current release branch checkout on the M4 (push left to the
   operator, risk of a dirty or wrong branch), a dedicated `bot/bug-classify` branch with a PR, or no commit at all
   (write the line and let Claude include it in the next commit)? Also whether it must skip when the checkout is
   dirty or not on the release branch (suggest: skip and report `skipped_dirty_checkout`).
4. **Where the backlog metric is computed.** In this M4 job (simple, but counts the M4 checkout, which can lag
   `origin`), or in the hub repo-sync / `publish_bug_metrics` path so it counts the hub's `deploy/hub` view with the
   other `k3dm_bug_docs*` series (`bin/k3dm-vectordb-metrics:181`). Suggest M4 job first.
5. **2026-11-12 Argon token chart.** Fold only the reader function (this plan) and leave the daily-bars-by-model chart
   on Agent Cost to its own idea row, or include the chart here (would make 2 panels more and touch
   `grafana-dashboard-agent-cost.yaml`)?
6. **Output-token field choice.** Limits may count input plus thinking tokens; the guard sums output (1.4.3) as
   instructed. Confirm that is the right proxy once the capture shows the fields.
