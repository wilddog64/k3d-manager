# k3dm Agent Cost (`k3dm-agent-cost`) — hub

[← Grafana dashboards index](../grafana-dashboards.md)

The **Agent Cost** dashboard contains the per-spec cost table, Codex API-equivalent costs, subscription costs, model breakdown, projected monthly cost, and Claude usage totals. Its **Window** selector matches Agent Dispatch, including release scope.

Agent Dispatch ledger events keep `worker_identity`, the legacy `coordinator_identity`, and
`primary_coordinator_identity` separate. Primary coordinator is assigned with
`PRIMARY_COORDINATOR=<vendor>/<model>` at dispatch; its first assignment is retained across
resumes. Handoffs append `acting_coordinator_identity` with bounded reason and provenance. The
Per spec table shows Primary coordinator, Acting coordinator, and Landed by; missing historical
facts display `unknown`. The existing Coordinator (legacy) column retains the prior
`COORDINATOR=<vendor>/<model>` semantics. The Claude edit measure describes intervention, not
coordinator identity. Vendor labels use a finite normalized set, and model labels use a finite
allowlist; valid but unlisted model names are exported as `other` while their bounded ledger
identity remains intact. Invalid values render as `unknown`.

`LANDING_ACTOR=human|claude|codex|other_agent|unknown` optionally identifies the landing actor;
`LANDING_MODEL=<vendor>/<model>` records model details only when explicitly declared. The
codex-land-pending wrapper records `review_pending` and does not create verification. No distinct
primary coordination cost source is measured currently, so Per spec leaves Primary cost blank; an
explicitly measured zero appears as `0`. Worker tokens and API cost are never reassigned as
coordinator cost. Aggregate handoff counts use only the
bounded reason label and contain no task identifiers.

Claude usage in **Cost (API-equivalent)** comes from Claude Code assistant transcript records under `~/.claude/projects`, including subagent transcripts. The exporter stores only message IDs, model, timestamp, speed and usage numbers in `~/.local/share/k3d-manager/claude-usage/rollup.json`, reading appended bytes incrementally so coverage survives transcript deletion. Transcripts older than Claude Code's retention period are gone unless the exporter saw them first. Time-window Claude totals count each retained message exactly once; the **Claude ≈** Per spec column attributes usage between each task's dispatch and land, splitting messages evenly across overlapping tasks. It is approximate because it misses spec writing and post-land verification and can include unrelated work during the task interval. Claude API-equivalent rates remain unpriced until confirmed.

## Agent dispatch cost details

Agent Dispatch measures two kinds of size separately. **Spec files** and **Acceptance items** are
captured at dispatch from the spec's `## Files` and `## Acceptance` sections. **Files changed**,
**Lines changed** and **Test lines** are captured at land from the rebased task diff; added and
deleted lines are both counted. Tests are under `scripts/tests/` or named `test_*.py` / `*.bats`;
documentation is under `docs/` or `memory-bank/`, plus Markdown files; other files are code. Binary
files count as changed files and add no lines. Release totals and the median include all measured
landed tasks, even when the table shows only its newest 50 rows. Missing measurements remain blank.
Specs landed before this shipped are not backfilled.

The Agent dispatch **Per spec** table links each Spec name to its plan or bug document on the
task's release branch; the link opens in a new tab. **Agent** names who landed the spec
(`codex` or `agy`); the Codex columns stay empty for an agy row. Its totals row sums Codex tokens, Codex time, Codex runs and
API equiv. over the rows shown, so picking a release in the Window menu gives that release's
totals. **Dispatch-to-land elapsed (wall clock)** (column **Dispatch → land**) is `earliest(start.ts) → land.ts`, including retries,
idle time and overnight waits; it is not worker runtime or active review. **Final worker exit → land** (column **Exit → land**)
is the wall-clock gap from the final qualifying Codex exit to land, and missing exits remain N/A.
Both values are means rather than footer sums because parallel dispatches overlap. The former
includes the full dispatch-to-land interval; the latter is not proof of human waiting. Live
verification happens after land. **Human continuation prompts** counts explicit operator records
by reason and displays the tracked-task coverage denominator; older history is unknown and is not
backfilled. Codex tokens uses the cumulative session total from the last
exit after a resume; summing those exits would double count. API equiv. counts each session's
recorded cumulative usage once.

**Delivered** means the latest independent verification recorded `pass`. If the spec's Acceptance
requires live evidence, its document must also have `**Status:** LIVE-VERIFIED` and a well-formed
`**Live evidence:**` line. The **Codex tokens per verified spec** stat averages implementation
Codex tokens plus any `verify --tokens` value when the verifier was a Codex task. It excludes
Claude's own verification tokens, and averages over Codex-run specs only: a spec implemented by agy
counts as delivered but is left out of this mean, since it has no Codex tokens. **Awaiting verification** counts landed specs whose document is
available but whose verification pass or required live evidence is missing. **Verification
unknown** counts landed specs whose `spec` path is absent from the start event or whose document
cannot be read. A failed independent review contributes to rework cause `review` and to `any`.

Run outcomes require independently referenced evidence. `accepted` means controlled validation
accepted that run's output; `rework` means objective refusal or failed verification led to another
attempt; `failed` requires an evidenced failure or abandonment without an accepted artifact;
`progress` requires reviewer-approved useful evidence; otherwise the outcome is `unknown`. Progress
and unknown token totals are not treated as waste. Bug-level token cost is N/A without an explicit
task-to-bug link and an independently verified live closure.

**Per run evidence** lists one row per attempt: version, slug, run, outcome, **Result**, **Log** and the
run's Codex tokens. Result summarizes TAP and pytest output from the land test log, or shows the
exit code for a Codex process failure; unavailable test output is `unknown`. To open a run log,
click its **Log** cell, copy the full path shown in the inspector, then run `less <path>` in a
terminal on the operator's Mac. Each slug links to its spec on GitHub, at the release branch named by the
row's version: `docs/bugs/<slug>.md` for a dated bug slug, `docs/plans/<version>-<slug>.md`
otherwise. The raw sample value of the outcome series (always 1) is hidden. The **Run outcomes**
bars are horizontal, so each outcome name reads in full left of its bar. **First-pass live
verification** sits left of the table, the way Last update sits beside Per spec: horizontal pass
and fail bars with fixed-size names.

The **Cost (API-equivalent)** row estimates what recorded Codex session tokens would cost at the
configured API rates. It is an estimate, not a bill: Codex runs on the $20/month ChatGPT plan.
Rates live in `scripts/etc/agent/codex-model-prices.json`; update a model's input, cached-input and
output rates there when pricing changes. Models without an explicit entry remain unpriced.

- **API equiv.** in Per spec is the sum for that landed task's priced Codex sessions. An empty cell
  means at least one session is unpriced or no session usage was recorded.
- **Codex at API prices** totals all priced usage in scope, including refused and abandoned attempts.
- **Per landed spec** divides that same total by landed tasks. Landed means the tests and scope gate
  passed; it does not mean live-verified.
- **Cached input** shows cached input tokens as a share of input tokens.
- **Subscriptions / month** shows the fixed ChatGPT, Claude, Gemini, GitHub and Hostinger plan costs
  (Hostinger is $250 per two years, so $10.42 a month); only the ChatGPT plan pays for Codex.
- **Ledger coverage** compares Codex sessions started in the selected time window with sessions
  present in the dispatch ledger. It has no release-scope value; “outside the ledger” estimates the
  cost of sessions missing from that ledger.
- **By model** splits priced usage by model. Time windows count a session by when it started;
  **Projected / month** divides the 7d cost by the days actually observed, then scales to 30 days.
- **Claude per landed spec** and **Claude tokens per landed spec** have values only when Window is a
  release; at `1d`/`7d`/`30d` they show No data by design, because a time window's Claude total
  includes work that is not dispatch work.
- **Claude tokens by kind** splits every Claude token in the selected window or release into
  `cache_read`, `cache_write`, `input` and `output`. Cache reads are usually most of the volume but
  are billed at a small fraction of the input rate, so token volume is not proportional to cost.
- **Claude tokens per day by kind** stacks the last 30 local dates by `cache_read`, `cache_write`,
  `input` and `output`; cache reads are billed at a fraction of the input rate.
- **Claude cost by kind** splits Claude API-equivalent cost in the selected window or release into
  `cache_read`, `cache_write`, `input` and `output`, using the price for each cache write duration.

`bin/k3dm-codex-dispatch usage-backfill` records usage for existing dispatch logs when their Codex
session files are available. It is safe to rerun; it skips already-recorded `(release, spec, session)`
tuples and reports missing session files.
