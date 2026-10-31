# k3dm Bug Tracking (`k3dm-bugs`) — hub

[← Grafana dashboards index](../grafana-dashboards.md)

Hermes publishes two Pushgateway groups on every poll through `bin/k3dm-vectordb-metrics`.
`k3dm-bug-docs` is the whole inventory: `k3dm_bug_docs{priority,state}` and its scan time.
`k3dm-bug-releases` is the same count per release, from `scripts/bug-tally.py` (the doc's
`**Branch:**` line, else the first tag that contains it). It covers the release branch Hermes
indexes and the five shipped releases before it, in `k3dm_bug_release_docs{release,order,priority,state}`.
Open for counts from filed until the bug is LIVE-VERIFIED, or a closed investigation has valid typed recovery proof.
`k3dm_bug_current_release_info{release}` names the current release. `k3dm_bug_later_release_open_docs`
counts open docs already scheduled for a later release, such as a patch release.

Bug counts have two release meanings. **Filed in** is the doc's `**Branch:**` line or the first tag
that contains its add commit. **Fixed in** is the first tag that contains the commit that changed
its status to fixed, or the current release branch when no tag does yet. A bug fixed, reopened and
fixed again counts once under its latest fix. A fixed bug with no detectable status change shows
`unknown` and is not counted under any release. So does a doc whose first Status line was added
already fixed to an existing doc, such as the 2026-10-09 status sweep: that commit records the
sweep, not the fix; release comes from tag ancestry, never dates. Tile 4
and panel 25 use fixed-in, while panels 7 and 8 and the `$release` row use filed-in. The table shows
both.

The top row shows the current release: bugs filed, open and fixed, open bugs scheduled later, and
untriaged docs. The middle row has two stacked bar charts across the six releases: by priority, and
open vs fixed. `unset` there means the doc predates priorities (2026-10-09). Each priority and state has a
fixed colour (P0 dark red, P1 red, P2 orange, P3 yellow, unset grey; closed green, open orange),
zero segments are dropped in the query, and counts are in the hover tooltip rather than on the bars,
where Grafana placed them on the wrong segment. The bottom row has the per-release summary strip,
scan age, a **Bugs** table, and open-by-priority over time (pinned to the last 3 days, the hub Prometheus retention). Each document is classified by status:

| Status | Doc `**Status:**` value begins with |
|---|---|
| `deferred` | `DEFERRED` |
| `fixed` | `IMPLEMENTED`, or a closed value such as `FIXED`, `VERIFIED`, or `CLOSED` |
| `unknown` | there is no status line |
| `open` | anything else |

The verification ladder is `OPEN → IMPLEMENTED → VERIFIED → LIVE-VERIFIED`. VERIFIED means
someone other than the implementer checked the fix offline: tests ran, the new tests were shown
red on the old code, and mutations were red. LIVE-VERIFIED means the fix was proven on the real
system (hub, cluster, Slack, or email). The ladder is cumulative, so LIVE-VERIFIED is also
VERIFIED.

Fixed documents also have a Verified and Live-verified label:

| Verified | When |
|---|---|
| `true` | fixed, release v1.43.2 or later, status begins `VERIFIED` or `LIVE-VERIFIED`, or a closed investigation has valid typed proof |
| `false` | fixed, release v1.43.2 or later, any other fixed status without valid typed investigation proof |
| `n/a` | fixed, release before v1.43.2 or unassigned |
| `-` | not fixed (table series only; shown as —) |

| Live-verified | When |
|---|---|
| `true` | fixed, release v1.43.2 or later, status begins `LIVE-VERIFIED`, or a closed investigation has valid typed proof |
| `false` | fixed, release v1.43.2 or later, status is not `LIVE-VERIFIED` and has no valid typed investigation proof |
| `n/a` | fixed, release before v1.43.2 or unassigned |
| `-` | not fixed (table series only; shown as —) |

The table shows `verified_at` and `live_verified_at` from `k3dm_bug_info` as **Verified at** and
**Live-verified at**, each next to its status column (`—` when not verified, `unknown` when no time
was found). A verified or
live-verified document gets `YYYY-MM-DD HH:MMZ` (UTC) or `YYYY-MM-DD`. The time comes from a date
written directly after the keyword (`VERIFIED — <ISO date or time>: <evidence>` /
`LIVE-VERIFIED — <ISO date or time>: <evidence>`); a date later in the Status text, such as a
planned drill or a `Was:` history note, is ignored. Without one, it is the UTC committer time of the
earliest commit that set that Status. A date-only Status date takes that commit's time when the
commit is from the same UTC day; otherwise it stays `YYYY-MM-DD` — usually because the only commit
that carries the Status is a release squash merge, whose time is the merge, not the verification.
Write the time in the Status (`VERIFIED — 2026-10-17T19:41Z: …`) to always get one. A verified doc
with neither is `true`; unverified values stay
`false`, `n/a` or `-`. These are text labels, so Grafana shows them in UTC, not the browser's zone.

The table also shows `fix_sha` and `verified_sha` as **Fix commit** and **Verified commit**. They
contain the first eight characters of the commit that marked the doc fixed (the commit used for
**Fixed in**) and the earliest commit that marked it `VERIFIED` or `LIVE-VERIFIED`, respectively;
otherwise they are `-` and render as `—`.

An investigation can verify recovery without identifying a causal code fix. Such a bug doc uses
`**Verification type:** investigation` and a typed line, for example:
`**Live investigation evidence:** 2026-10-28 · source operator · reference docs/issues/recovery-check.md · env m4-webhook · scenario health-check · proves m1,m3`.
The parser checks the metadata shape and calendar date; it does not fetch the reference or claim
that the cited evidence is true. The operator remains responsible for reviewing that evidence.
When this proof is attached to a closed bug, the row reports Verified and Live-verified with
`live_evidence="ok"`; `verified_sha` identifies the commit recording the proof, while `fix_sha`
stays `-` because an operational recovery record is not a causal code fix. Both date labels use
the typed proof date; the recording SHA is found in the history of the scanned Git ref, even
when a later working tree contains different evidence. Legacy and unassigned releases retain
their established `n/a` labels. Open investigations
remain open and unverified. Do not add a Fix commit to an investigation-only proof; ordinary code
fix evidence continues to require its Fix commit and ancestry check. Any explicit Fix commit
header conflicts with investigation-only proof, including an empty or malformed value. Typed
investigations with missing or invalid proof stay unverified even when their Status says
LIVE-VERIFIED. Their inferred status-change commit is never displayed as a causal fix; a genuine
explicit code-fix SHA remains visible, and ordinary live code-fix evidence retains its ancestry
validation.

It also shows **Live evidence**, which checks the proof commit recorded in the bug doc against the
fix commit:

| Live evidence | Meaning |
|---|---|
| `ok` | `✓ current`: at least one evidence commit contains the fix |
| `stale` | `stale proof`: git confirms no evidence commit contains the fix |
| `missing` | no well-formed evidence line is recorded |
| `unchecked` | evidence exists, but the fix commit is unknown, or git cannot resolve the fix or evidence commit (for example a squash-merged release branch that was deleted without an archive tag) |
| `n/a` | LIVE-VERIFIED release predates v1.43.4 |
| `-` | not fixed or not LIVE-VERIFIED |

Each live proof uses one line in this form (multiple lines are allowed):
`**Live evidence:** YYYY-MM-DD · run <id> · env <value> · scenario <value> · commit <sha> · proves <ids>`.
The separators may also be written as ` | `. `proves` contains comma-separated Acceptance IDs such
as `E1,E3`, or `fix` for a doc with no Acceptance block. `commit` is the k3d-manager commit checked
out when the proof ran (an e2e run records it in `~/.k3dm/e2e/<run>.json`); `run` is the e2e run ID,
or a short name or log path for a proof that is not an e2e run. The check compares against the commit that first closed the doc's Status. When the doc was closed
after the proof ran (for example straight to LIVE-VERIFIED), add `**Fix commit:** <sha>` naming the
code fix; it overrides that proxy for this check only. Open for keeps counting from Filed
for `missing` and `stale`; `ok`, `unchecked`, and historic `n/a` rows keep the live-verified value
of `-2`. The pre-commit hook rejects a commit that makes a bug doc LIVE-VERIFIED without a
well-formed line and now requires a **Fix commit:** header for a new LIVE-VERIFIED doc, checking
that an evidence commit contains it (`make check-bug-evidence` sweeps every doc).

`k3dm_bug_info` also gives a bug that is not fixed `fixed_in="-"`. The placeholder keeps the three
columns in the table when the selected release has no fixed bug: Grafana drops a column that no row
has. The `k3dm_bug_status_docs` aggregate still carries none of these labels for an unfixed bug.

The summary strip follows the Release dropdown and shows open P0–P3 (titled P0 to P3), Fixed, Verified,
Live-verified, Deferred, and scan age. The table reads `k3dm_bug_info`, includes Release, Bug,
Priority, Filed, Open for, Status, Fixed in, Verified, Live-verified, and Live evidence, and clicking a title opens that
document on the scanned branch. The dashboard opens on **Show all**; **Hide live-verified** is the
other option. It keeps open, unknown, deferred, and not-yet-live-verified rows visible while hiding
live-verified and historic `n/a` fixes. To mark a fix live-proven, change its Status to
`LIVE-VERIFIED — <evidence>`.

The dashboard opens on the release branch's own version, which is the saved Release value. When a
new release branch is cut, bump that value; the BATS test fails until it matches. lib-foundation has
no release branch value and falls back to All. Rows sort by release, then priority (P0 first and
unset last), then status.

The exporter publishes the table and status aggregate in the separate `k3dm-bug-open` Pushgateway
group with `PUT`, so a changed or empty list is removed rather than lingering in Pushgateway.
The Release dropdown filters the table and the Open P0–P3 stats by the release the bug was filed in:
the doc's `**Branch:** k3d-manager-vX.Y.Z` line, otherwise the first tag containing the commit that
added the file, otherwise the current release branch. Bugs without a valid release use the `unassigned`
bucket. The table and dropdown list releases newest first, by version. The dropdown does not filter
Open, any release or the history.
On `main`, which is
not a release branch, the current-release row is empty and the charts show the last five shipped
releases. A tally failure skips only the release group, so the inventory keeps updating.

The Repo selector chooses among the nine PR Checks repos listed above. lib-foundation is read from
its clone at `origin/main`, configured by `K3DM_LIB_FOUNDATION_DIR` (default
`~/src/gitrepo/personal/lib-foundation`), and its release labels are its own tags such as
`v0.5.3`. The "Fixed this release" and "Open in later releases" tiles remain k3d-manager-only
because lib-foundation has no release branch.

## Filters, release mode and the Bugs table

In the k3dm Bug Tracking dashboard, use the funnel icon in the **Bug** column header to filter rows by title. If the table is empty with no column filter selected, there are no `k3dm_bug_info` series for the current repository, release, and verification selections; check telemetry ingestion before concluding that a bug is missing.

Bug Tracking defaults to **Auto (current)**: the **Release** row (Release, Bugs filed, Bugs open and Bugs fixed) and Bugs table follow `k3dm_bug_current_release_info` for the selected repository. Choose **Manual** to use **Manual releases (ignored in Auto)**, which retains historical multi-select and **All**; the Release tile shows the picked releases as that box names them, or All. **Open, scheduled later** and **Open, untriaged** are repository-wide counts in both modes. “Filed in” follows the shared attribution rule: the bug doc's **Branch:** line, otherwise the first tag containing the commit that added it, otherwise the current release branch. If the selected repository has no current-release metric, use Manual; Auto has no release to match. In Manual, panels filter with `release=~"$release"`; the `release_order` label only sorts release choices and tables (it holds an ordering prefix and the release value), so never filter on it.

In the Bugs table, **Fix commit** comes from the bug doc's **Fix commit:** header when present, otherwise from the commit that marked the bug fixed. **Fixed in** continues to show the release where its status changed.

## Release plans

The **Release plans** row inventories every top-level `docs/plans/v<X.Y.Z>-<slug>.md` file for k3d-manager. Hermes reads each plan's H1, `**Status:**`, `**Approval:**`, `**Dispatch:**`, `**Release:**`, `**Depends on:**`, `**Wave:**`, and `**Component:**` lines; the filename determines its release. Each plan name in the **Plans** table links to that file on the branch Hermes scanned (a plan for a later release still lives on the current release branch). Execution and verification are independent labels derived from the leading Status words:

The **Order** column comes from the plan number on each document's `**Release:**` line. **Depends on** lists the referenced plans and links to the first dependency's spec on the scanned branch. A plan whose dependency has not been implemented is not ready to dispatch. **Wave** is calculated from same-release dependencies: independent plans start at 1, and each dependent plan follows the highest dependency wave. A cycle displays `cycle`. A declared `**Wave:** <n> — <reason>` can postpone a plan; it cannot make it earlier. **Wave note** shows the sanitized reason (up to 80 characters), or reports when the declared number is earlier than required.

**Overlaps** flags same-release plans that share a path listed on their `**Component:**` lines and have no direct or transitive dependency. Directory paths ending in `/` cover paths below them. To clear an overlap, add the real prerequisite to `**Depends on:**`; if the shared work is intentionally independent, record the accepted overlap in the plan body. The table continues to flag accepted overlaps by design. Keep `**Component:**` complete: detection reads only that header, not paths mentioned elsewhere in the document. The Undeclared plan overlaps stat counts conflicting pairs for the selected releases.

**Spec approval** reports `approved`, `pending`, `none`, or `n/a` from the plan `**Approval:**` header. **Dispatch approval** reports the plan `**Dispatch:**` header (`go`, `needed`, `not required`, or `unknown`); the table displays `unknown` as `not recorded`. It is independent of spec approval, and neither approval prose nor ledger events fill in a missing header. **Dispatch task** comes from the dispatch ledger and shows lifecycle (`landed`, `awaiting land`, `refused`, `Codex failed`, `running`, or `no record`). `awaiting land` means the worker exited successfully and the task still awaits integration; it does not mean landed or verified. **Execution**, **Verified**, and **Live verified** come from the plan `**Status:**` header, never from the land event. The verification columns are status indicators only; they do not identify a verifier, timestamp, commit, or evidence record. **Verified** is marked for `verified` and `live_verified`; **Live verified** is marked only for `live_verified`; other states show `-`. The raw source verification label remains unchanged in query metadata. **Status lags dispatch** counts ledger-landed tasks whose document still says proposed, ready, or in progress. In the v1.43.9 screenshot, all five ledger tasks were landed while four plan Status headers remained PROPOSED/READY. After reviewing the landed change and its evidence, reconcile the plan document itself; the dashboard preserves its current Status and verification until then. For a landed task with stale Status, **Blocked by** displays `landed; documentation stale`; tasks that have not landed retain their branch, dependency, approval, and wave blockers.

When filing a plan, keep `**Component:**` complete with every touched file or directory in backticks. The overlap scanner intentionally uses this line alone.

| Status starts with | Execution | Verification |
|---|---|---|
| LIVE-VERIFIED | implemented | live_verified |
| VERIFIED | implemented | verified |
| IMPLEMENTED, DONE, LANDED, MERGED, SHIPPED | implemented | unknown |
| IN PROGRESS, IN-PROGRESS, DISPATCHED, PENDING CODEX | in_progress | n/a |
| READY, APPROVED | ready | n/a |
| PROPOSED, SPEC, DRAFT, PLAN, PLANNED, SCOPED, QUEUED | proposed | n/a |
| DEFERRED, MOVED, SPLIT | deferred | n/a |
| SUPERSEDED, CANCELLED, CANCELED, DROPPED, WITHDRAWN | cancelled | n/a |
| anything else or no Status | unknown | unknown |

Approval is `explicit` unless the line is absent (`none`) or begins with `pending`; plans before v1.43.2 use `n/a`. Dispatch is joined by the plan filename stem from the Codex dispatch ledger. Its state comes from the task's dispatch events only (start, resume, worker exit, land, land refused, abandon); bookkeeping recorded afterwards, such as interventions, usage or verification, does not change it. Only a start event that records a `docs/plans/` spec can appear; `landed` describes integration and does not change verification. Missing dispatch telemetry displays **no record**. The dashboard deliberately does not infer **not started** from missing information or **done** from implementation. As the operator requirements say: “Include every planned specification”; “Keep execution state separate from verification state”; “Don't infer completion from missing information.” Each **Dispatch** cell links to that release in Agent dispatch, and the Agent dispatch dashboard has a top-level **Bug Tracking** link back. The Agent dispatch **Window** selector lists the time windows and ledger releases from v1.43.0 onward; v1.43.0 is the coverage floor because earlier releases predate the ledger. Its **Release** cells link back to Bug Tracking. A release before v1.43.0 has no dispatch scope, so its row link opens an empty dispatch view.

## Release forecast

The **Release forecast** row reads the ordered inventory in `docs/release-milestones.json`, maintained alongside the roadmap. The summary tiles always describe the whole path to the target; the **Remaining releases** table follows **Release mode**: in Auto it shows the current release; switch to Manual and pick **All** in **Manual releases** to see every remaining release. Update the JSON in the same commit as any roadmap split. The scanner derives cadence from the last 12 date-ordered gaps between annotated k3d-manager release tags and uses nearest-rank 25th, 50th, and 75th percentiles to make earliest, expected, and latest estimates for each remaining milestone. **Median gap (days)** is the median gap between release tags: a cadence measure, not the effort a release takes. A milestone blocked by outside work and every later milestone have no dates; **Target state** names the blocking milestone and its `blocked_by` reason. The panel keeps the state prominent and renders the supporting reason as a 16 px wrapping title. Set optional `not_before: YYYY-MM-DD` when a plan's live evidence must wait for a scheduled window; forecasts for that milestone and later releases will not be earlier than midnight Pacific time on that date (`K3DM_FORECAST_TZ` overrides the zone), so the dashboard never shows the day before. Shipped milestones ignore the floor.
