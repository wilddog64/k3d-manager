# Grafana Dashboards

This guide is the entry point for the Grafana dashboards shipped by this repository. The inventory below follows the 16 unique dashboard UIDs defined by the current labeled ConfigMaps and their deployment locations. Dashboard references document panels, metric producers, operational details, and known caveats.

## Dashboard inventory

| Dashboard | UID | Source file | Deployer | Cluster | Guide |
|---|---|---|---|---|---|
| ArgoCD Apps & Image Updater Hub | `argocd-image-updater-hub` | `platform-ops/grafana-dashboard-argocd.yaml` | `grafana-dashboards-hub` ApplicationSet; `make platform-ops` | hub | [Reference](grafana-dashboards/argocd-image-updater.md) |
| CVE Auto-Patch | `cve-autopatch` | `platform-ops/grafana-dashboard-cve-autopatch.yaml` | `grafana-dashboards-hub` ApplicationSet; `make platform-ops` | hub | [Reference](grafana-dashboards/cve-autopatch.md) |
| E2E Verification | `e2e-verification` | `platform-ops/grafana-dashboard-e2e.yaml` | `grafana-dashboards-hub` ApplicationSet; `make platform-ops` | hub | [Reference](grafana-dashboards/e2e-verification.md) |
| Hermes Status | `hermes-status` | `platform-ops/grafana-dashboard-hermes.yaml` | `grafana-dashboards-hub` ApplicationSet; `make platform-ops` | hub | [Reference](grafana-dashboards/hermes-status.md) |
| k3dm Host Disk | `k3dm-host-disk` | `platform-ops/grafana-dashboard-host-disk.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-host-disk.md) |
| k3dm Host Pod IP Pool | `k3dm-host-cni-ipam` | `platform-ops/grafana-dashboard-host-cni-ipam.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-host-cni-ipam.md) |
| k3dm PR Checks | `k3dm-pr-checks` | `platform-ops/grafana-dashboard-pr-checks.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-pr-checks.md) |
| k3dm Alertmanager Delivery | `k3dm-alertmanager-delivery` | `platform-ops/grafana-dashboard-alertmanager-delivery.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-alertmanager-delivery.md) |
| k3dm Agent Dispatch | `k3dm-agent-dispatch` | `platform-ops/grafana-dashboard-agent-dispatch.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-agent-dispatch.md) |
| k3dm Bug Tracking | `k3dm-bugs` | `platform-ops/grafana-dashboard-bugs.yaml` | `grafana-dashboards-hub` ApplicationSet; `make platform-ops` | hub | [Reference](grafana-dashboards/k3dm-bugs.md) |
| k3dm Deployment Metrics | `k3dm-deployments` | `etc/grafana/dashboards/k3dm-deployments-configmap.yaml` | `make observability-acg` | ACG | [Reference](grafana-dashboards/k3dm-deployments.md) |
| k3dm Tests | `k3dm-tests` | `etc/grafana/dashboards/k3dm-tests-configmap.yaml` | `grafana-dashboards-hub` and `grafana-dashboards-acg` ApplicationSets | hub + ACG | [Reference](grafana-dashboards/k3dm-tests.md) |
| Trivy Security | `trivy-security` | `etc/grafana/dashboards/trivy-security-configmap.yaml` | `make observability-acg` | ACG | [Reference](grafana-dashboards/trivy-security.md) |
| Checkout Load Test | `checkout-loadtest` | `etc/grafana/dashboards/checkout-loadtest-configmap.yaml` | `grafana-dashboards-acg` ApplicationSet | app clusters except hub | [Reference](grafana-dashboards/checkout-loadtest.md) |
| Grafana Health & Firing Alerts | `k3dm-grafana-health` | `platform-ops/grafana-dashboard-overview-readable.yaml`; `etc/grafana/dashboards/grafana-overview-readable-configmap.yaml` | hub and ACG dashboard ApplicationSets | hub + ACG | [Source definition](../../scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml) |
| k3dm VectorDB Health | `k3dm-vectordb` | `platform-ops/grafana-dashboard-vectordb.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-vectordb.md) |

Public endpoint probes (`probe_*`) are Prometheus blackbox-exporter metrics and `Probe` resources, not Grafana dashboards. See [probe triage](grafana-dashboards/shared-operations.md#triage-no-data-by-cause).

## Choosing a Grafana instance

The repository ships separate hub and ACG Grafana instances, with dashboards placed according to their data. The public `grafana.3ai-talk.org` route should reach hub Grafana. Confirm the instance before debugging a missing dashboard or empty panel; the [health dashboard](grafana-dashboards/shared-operations.md#which-grafana-am-i-looking-at) explains the stock Grafana Overview distinction.

All dashboard ConfigMaps use the `grafana_dashboard: "1"` label in the `monitoring` namespace for sidecar discovery. A missing dashboard points first to deployment, namespace, or label; a loaded dashboard with empty panels points first to its producer.

In the k3dm Bug Tracking dashboard, use the funnel icon in the **Bug** column header to filter rows by title. If the table is empty with no column filter selected, there are no `k3dm_bug_info` series for the current repository, release, and verification selections; check telemetry ingestion before concluding that a bug is missing.

Bug Tracking panels filter on `release=~"$release"`. The `release_order` label is used only to sort the release dropdown and release table; it contains both an ordering prefix and the release value. New dashboard panel specs must preserve this filter convention.

### Release plans

The **Release plans** row inventories every top-level `docs/plans/v<X.Y.Z>-<slug>.md` file for k3d-manager. Hermes reads each plan's H1, `**Status:**`, `**Approval:**`, `**Release:**`, and `**Depends on:**` lines; the filename determines its release. Each plan name in the **Plans** table links to that file on the branch Hermes scanned (a plan for a later release still lives on the current release branch). Execution and verification are independent labels derived from the leading Status words:

The **Order** column comes from the plan number on each document's `**Release:**` line, and **Depends on** lists the plan paths from its `**Depends on:**` line. A plan whose dependency has not been implemented is not ready to dispatch.

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

Approval is `explicit` unless the line is absent (`none`) or begins with `pending`; plans before v1.43.2 use `n/a`. Dispatch is joined by the plan filename stem from the Codex dispatch ledger. Only a start event that records a `docs/plans/` spec can appear; `landed` describes integration and does not change verification. Missing dispatch telemetry displays **no record**. The dashboard deliberately does not infer **not started** from missing information or **done** from implementation. As the operator requirements say: “Include every planned specification”; “Keep execution state separate from verification state”; “Don't infer completion from missing information.” Each **Dispatch** cell links to that release in Agent dispatch, and the Agent dispatch dashboard has a top-level **Bug Tracking** link back. The Agent dispatch **Window** selector lists the time windows and ledger releases from v1.43.0 onward; v1.43.0 is the coverage floor because earlier releases predate the ledger. Its **Release** cells link back to Bug Tracking. A release before v1.43.0 has no dispatch scope, so its row link opens an empty dispatch view.

## Agent dispatch costs

The Agent dispatch **Per spec** table links each Spec name to its plan or bug document on the
task's release branch; the link opens in a new tab. Its totals row sums Codex tokens, Codex time, Codex runs and
API equiv. over the rows shown, so picking a release in the Window menu gives that release's
totals. Time to land is not summed: parallel dispatches overlap, so the useful number is the mean,
which the **Time to land** stat shows. Codex tokens uses the cumulative session total from the last
exit after a resume; summing those exits would double count. API equiv. counts each session's
recorded cumulative usage once.

**Delivered** means the latest independent verification recorded `pass`. If the spec's Acceptance
requires live evidence, its document must also have `**Status:** LIVE-VERIFIED` and a well-formed
`**Live evidence:**` line. The **Codex tokens per verified spec** stat averages implementation
Codex tokens plus any `verify --tokens` value when the verifier was a Codex task. It excludes
Claude's own verification tokens. **Awaiting verification** counts landed specs whose document is
available but whose verification pass or required live evidence is missing. **Verification
unknown** counts landed specs whose `spec` path is absent from the start event or whose document
cannot be read. A failed independent review contributes to rework cause `review` and to `any`.

Run outcomes require independently referenced evidence. `accepted` means controlled validation
accepted that run's output; `rework` means objective refusal or failed verification led to another
attempt; `failed` requires an evidenced failure or abandonment without an accepted artifact;
`progress` requires reviewer-approved useful evidence; otherwise the outcome is `unknown`. Progress
and unknown token totals are not treated as waste. Bug-level token cost is N/A without an explicit
task-to-bug link and an independently verified live closure.

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

`bin/k3dm-codex-dispatch usage-backfill` records usage for existing dispatch logs when their Codex
session files are available. It is safe to rerun; it skips already-recorded `(release, spec, session)`
tuples and reports missing session files.

The **Claude context and compaction** row (time windows `1d`, `7d`, `30d` only) measures what context compaction costs Claude per verified spec. **Claude cost per verified spec** divides the time window's Claude cost at API list prices (not subscription usage) by `k3dm_claude_verified_specs`, where a "verified spec" is a `docs/bugs` or `docs/plans` document whose `**Status:**` line moved to a closed state in a commit within the window (shows "No data" when the count is 0). **Compactions per verified spec** divides total `compact_boundary` events in the window by verified specs, **Compactions by trigger** splits those compactions by `auto` or `manual` trigger, and **Re-read share after compaction** shows the fraction of `Read` tool calls in the window that re-read a file already read before the latest compaction boundary in the same session. **Context incidents** splits `resumption-failure` and `missing-context-correction` counts by kind, and **Auto-compact threshold** shows the latest non-future `auto_compact_tokens` setting; the incident panels are only as complete as the hand tally in [context-window-experiment.md](../metrics/context-window-experiment.md).

## CVE Auto-Patch triage

### Release forecast

The **Release forecast** row reads the ordered inventory in `docs/release-milestones.json`, maintained alongside the roadmap. The summary tiles always describe the whole path to the target; the **Remaining releases** table follows the **Release** selector at the top, so pick **All** to see every remaining release. Update the JSON in the same commit as any roadmap split. The scanner derives cadence from the last 12 date-ordered gaps between annotated k3d-manager release tags and uses nearest-rank 25th, 50th, and 75th percentiles to make earliest, expected, and latest estimates for each remaining milestone. A milestone blocked by outside work and every later milestone have no dates because the release chain cannot safely proceed past the blocker until it is marked done.

| Symptom | Meaning | Check |
|---|---|---|
| **Our images with no Trivy report** has a row | The critical-CVE table cannot vouch for that running image because no VulnerabilityReport exists | Check the app-cluster Trivy Operator scan jobs and report in the listed namespace; findings panels cannot show an unscanned image |

## Shared operations

- [Producer chain and provenance](grafana-dashboards/shared-operations.md#the-producer-chain)
- [No data triage](grafana-dashboards/shared-operations.md#triage-no-data-by-cause)
- [Adding or changing a dashboard](grafana-dashboards/shared-operations.md#adding-or-changing-a-dashboard)
- [Where to look next](grafana-dashboards/shared-operations.md#where-to-look-next)

Claude usage in **Cost (API-equivalent)** comes from Claude Code assistant transcript records under `~/.claude/projects`, including subagent transcripts. The exporter stores only message IDs, model, timestamp, speed and usage numbers in `~/.local/share/k3d-manager/claude-usage/rollup.json`, reading appended bytes incrementally so coverage survives transcript deletion. Transcripts older than Claude Code's retention period are gone unless the exporter saw them first. Time-window Claude totals count each retained message exactly once; the **Claude ≈** Per spec column attributes usage between each task's dispatch and land, splitting messages evenly across overlapping tasks. It is approximate because it misses spec writing and post-land verification and can include unrelated work during the task interval. Claude API-equivalent rates remain unpriced until confirmed.
