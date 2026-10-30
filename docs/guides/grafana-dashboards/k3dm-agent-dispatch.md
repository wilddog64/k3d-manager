# k3dm Agent Dispatch (`k3dm-agent-dispatch`) — hub

[← Grafana dashboards index](../grafana-dashboards.md)

The dispatch dashboard reads the shared Codex ledger export; the **Window** control (top left,
default `7d`) selects 1d, 7d, 30d, or a release (v1.43.0 onward). The Grafana time picker does not change these panels. It shows
accepted specs, integration-test landing success, verifier lines changed, wait minutes, Codex
tokens per accepted spec, running and awaiting-land tasks, outcome counts, and export age. Wait
minutes are wall-clock waiting time rather than active human minutes; token cost is Codex tokens
only, excludes Claude verification, and is not converted to dollars because token pricing is not
stable. Scope and rebase refusals are excluded from the integration success ratio. The dashboard
also shows mean minutes to land (from the first Codex start through land, including verification)
and mean Codex minutes (Codex runtime summed across runs) for landed specs. The **Per spec** table
lists Codex tokens, Codex time, time to land, and Codex runs for the newest 50 landed specs in the
selected window. Tokens are the session total from the spec's last run; only dispatcher-launched
specs appear, because a bare `codex exec` writes no ledger event.

**Rework rate** is the share of landed specs in the window that needed a second pass, for any of
three causes: Codex ran more than once, the integration gate refused the land for failing tests,
or Claude changed lines between Codex's finished tree and what landed. Rebase and scope refusals
are not rework: a rebase refusal means `main` moved, and a scope refusal is the dispatcher's own
guard. `k3dm_dispatch_rework_landed{cause=...}` gives the count per cause (`rerun`, `tests`,
`claude_edit`, `any`); a spec can count under several. The independent verifier's verdict is not
recorded in the ledger, so a correction it asks for shows up only through the re-run or Claude edit
that follows.

The **Claude** row, second from the top, prices this repo's Claude Code transcripts at Anthropic's
API list rates (`scripts/etc/agent/codex-model-prices.json`). This is what the usage would cost on
the API, not the subscription bill. A time window counts every message in it; a release counts only
messages between each spec's first dispatch and its land, split across specs that overlap, so
spec writing and live checks between dispatches are left out.
These figures do **not** measure what Claude spent on each Codex dispatch. Attribution is by time
overlap: whatever Claude did while a spec was open (spec writing, design, discussion, other work) is
charged to that spec. **Claude per landed spec** and **Claude tokens per landed spec** show only for a
release; a time window shows no data, since its total is all Claude work, not only dispatch work. **Claude data since** is the oldest
transcript still on disk. **Claude tokens per day** covers the last 30 days and ignores the Spec
window.

## Release span, tokens and run logs

The **Agent Dispatch** dashboard covers dispatch throughput, active runs, per-spec delivery and verification, plus run outcomes. Its **Window** selector includes time windows and ledger releases from v1.43.0 onward. Use the **Agents** link to move between the three agent dashboards while keeping the selected time range and window.

In a release window, **Release span** measures calendar time from the release's first dispatch to its PR merge, or to its latest land while the release is unmerged; its `end` label is `merge` or `last_land` accordingly. **Active time** unions each landed spec's first-start-to-last-land interval, so overlapping work counts once. Both panels show no data for time windows, and **Time to land** is the mean per spec.

Agent-neutral task token totals include Codex's cumulative `codex_exit.tokens` and the sum of agy's per-run `agent_exit.usage.total_tokens`; agent runtime and run counts include exits from both agents.

The **Per run evidence** table's **Log** cell opens **k3dm Agent Run Log** for that version, slug and run; keep `make install-hub-loki-port-forward` installed once to connect Grafana log shipping to the hub's Loki. Only `land-test.log` is shipped, after redaction, with at most its last 4,998 lines (under Loki's 5,000-line query limit). Each push starts with a `[shipped <time> sha256:<prefix>]` line, so a log re-shipped after a re-land shows as a second block. The run directory keeps one `land-test.log` per slug, so only the slug's latest run is shipped; an earlier run's Log link shows whatever was shipped while it was the latest, or nothing. `codex.log` and every other run file stay on the Mac. The local path remains inspectable and copyable.

The Agent Dispatch **Per spec** table includes a **Repo** column. Per-task metrics carry the origin repository name as a `repo` label; legacy or invalid labels are exported as `k3d-manager`. Aggregate series do not include this label.
