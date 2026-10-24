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
