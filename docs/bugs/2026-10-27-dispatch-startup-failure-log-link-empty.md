# Bug: failed startup Log link opens an empty Loki view

**Status:** VERIFIED — single-table correction independently tested; two-dashboard deployment/UI verification pending
**Fix commit:** 0077b7b8f6cbc13b76a07c63bbd1b9286afa36f4
**Priority:** P3
**Filed:** 2026-10-27
**Branch:** `k3d-manager-v1.43.9`
**Related:** `docs/bugs/2026-10-25-dispatch-run-log-not-viewable-from-grafana.md`

Failed startup rows with codex_exit.exit evidence offer a Grafana Log link, but
the shipper deliberately ships only landing-test logs. The local codex.log
contains the startup error while the linked Loki view is empty. Historical
exit127 rows are valid; their later retry2 succeeded and landed.

[Verbatim evidence and source analysis](../issues/2026-10-27-dispatch-startup-exit127-empty-grafana-log.md).

A scoped fix should show unsupported evidence as local-only/unavailable with
a clear explanation, preserving the existing prohibition on shipping codex.log.
Do not rewrite failed historical attempts as successful or ship transcripts.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-run-log.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`

## Authorized bounded task

Operator asked to investigate the three open screenshot bugs and dispatch
accordingly. Implement this P3 in an isolated GPT-6-Luna worktree. Preserve
historical failure outcome/exit127 and local codex.log evidence path; label
unsupported startup evidence clearly local-only/not shipped. Offer usable
Loki links only for evidence supported by the existing landing-test shipper.
Do not ship/read worker transcripts, alter bin/k3dm-dispatch-logs, rewrite
ledger/history, claim recovery or add a new log-export pipeline. Preserve
supported land-test/land_refused logs and dashboard fields. Keep metric labels
bounded and safe; unknown/legacy/no-test evidence must be truthful.

Add meaningful offline metric/dashboard regressions for failed startup exit127
(no empty-view promise, local path retained), successful supported landing
log (working link retained), unknown/legacy evidence. Demonstrate new relevant
regression red on original behavior. Run focused test_dispatch_metrics pytest,
agent_dispatch_dashboard BATS, Python syntax/Ruff, YAML/embeddedJSON validation
and diff check. Existing unrelated legacy >8if functions must not be refactored
or allowlisted silently; report a conflict. New/refactored functions <=8ifs.

Read repository instructions/memory-bank first. Edit only Files; no spec or
memory edits, stage/commit/push/PR, cluster/provider/Keychain/network/live
checks, credentials, or service restart. Coordinator stages/reviews/gates/
lands/pushes and schedules operator dashboard live verification. No new plans.

## Independent implementation review

Luna implementation landed and pushed after review follow-up. [Full test output, corrected fixture/gate failures and live limits](../issues/2026-10-27-three-open-bugs-investigation-and-luna.md). Operator live check pending; no production deployment/restart by coordinator.

## Live verification failed — corrective task

Operator clicked a failed-startup Log cell after the new dashboard and metrics
were deployed. Grafana showed Page not found. Failed Log cells remain blue.
The prior missing loki_url metric label did not remove the field-level data
link; the organize transform also excludes that referenced field. The screenshot
does not expose the actual destination URL, so do not invent that URL. Deployed
Grafana is11.4.0. Official v11.4 DefaultCell uses field links to decide whether
to render a clickable cell, and fieldOverrides getLinksSupplier builds a link
model for every configured link; missing/null target is not a no-link contract.
Source reference and evidence are in the three-open-bugs issue.

Correct this same P3, preserving previous metrics/local path/history fixes.
Use a structural separation in Grafana11.4 rather than another null/interpolated
link trick. Small safe option: retain a per-run evidence table with all rows
and plain unlinked Log paths, plus a clearly labeled supported-landing-logs
view/table filtered to evidence=land-test.log|land_refused.tests with real
per-row links. Alternatively separate supported and unsupported tables with
clear titles. Unsupported evidence must NEVER enter a table with a configured
log action; supported logs must retain a usable filtered target. Preserve
visible run/outcome/result/token data, readable layout, no overlap, no unrelated
panels changed. Do not add UI plugins/custom frontend/downloads or upgradeGrafana.

Files remain the same four above. Prefer dashboard/test changes; do not change
metric schema without need or broaden log shipping. Add regression on actual
field-link config plus supported/unsupported query partition, including absent
and legacy evidence. Model transform field exclusion so links never refer to
removed fields. Show relevant regression red on current11.4-incompatible patch,
then full metrics pytest/dashboard BATS/Ruff/YAML+JSON/diff. Full UI behavior
remains operator verification, not proven by string/schema assertions alone.
Worker offline only/no credentials/Grafana/cluster/network/stage/commit/push/
memory/spec changes. Coordinator lands with --superseding startup-log-link-local-only,
records failed live check and corrected evidence, then requests one redeploy.

## Corrective implementation landed

Corrective Luna task startup-log-noninteractive-cells supersedes startup-log-link-local-only. Per run evidence now has plain Log paths with width/inspection retained and no Log data link. New Supported landing logs panel admits only exact supported evidence types and uses version/slug/run links whose fields survive organize. Unsupported/unknown/legacy evidence cannot appear in that linked view. No metric schema/shipper/history changes;29otherexistingpanels unchanged. Independent138pytest/28BATS/Ruff/PromQL/staged gates passed; actual operator clicks remain unverified. Full outputs and prior failed live check retained in three-open-bugs issue.

## User clarification: retain primary-table hyperlinks

Operator rejected removing successful-row hyperlinks from Per run evidence. Coordinator correction19a56939 restores linked shipped logs in original panel47/title/position; only unshipped rows move to Local-only run evidence(panel93). Exact complementary selectors cover unsupported/absent/legacy evidence without loss; both tokenqueries partitioned. Main merge/layout retained,29otherpanels unchanged. Offline138Python/28BATS/4PromQL/staged gates passed. No schema/shipper/history/identity changes. Actual UI check pending explicit ConfigMap apply; make platform-ops does not install this dashboard. Full output and corrected test failures in three-open-bugs issue.

## Current user-authorized correction: one evidence table

Operator explicitly requested remove the added table and fix Per run evidence
Log. This supersedes earlier two-table implementation proposals. Communicated
before edits: remove panel93, include all evidence kinds in existing panel47,
retain its Log hyperlinks. Every link opens existing k3dm-agent-run-log with
visible version/slug/run/Result values. Existing log panel heading includes
that Result via one hidden textbox variable, so local-only/unknown availability
is explicit without adding a panel/table. Existing shipped Loki query remains
unchanged. No new log shipping, raw transcript export, provider access or
automation expansion. Existing run-log ConfigMap/UID verified present read-only.
Run-log YAML added to Files for this communicated same-bug correction. Test
one table/all categories, retained-field URL and escaping, hidden result value
and existing heading/query, source compatibility, layout and no other panels.
Deploy only the two affected dashboard ConfigMaps after offline gates.

## Single-table implementation complete offline

Operator-requested removal implemented in0fc9d3ef: extra panel93 removed, existing Per run evidence again contains all run categories with Log hyperlinks. Link uses visible version/slug/run/Result, no hidden URL-field dependency. Existing Agent Run Log heading shows Result through a hidden textbox variable; local-only availability is explicit, shipped Loki query unchanged. No added table/panel/logshipping/transcript export. Independent138Python/28BATS/Ruff/2PromQL/staged gates passed;29otherdispatchpanels unchanged. Both existing dashboard ConfigMaps must be applied before UI checks. Full actual outputs in three-open-bugs issue.

## Empty path label follow-up

Operator screenshot showed earlier runs with outcomeunknown/evidencenone/pathblank. Configured link existed but empty displayed value made it invisible. Fix0077b7b8 maps only empty/null Log values to clickable Open run evidence; real paths unchanged. No newtable. Unverified/No landing-test evidence recorded distinguish earlier attempts without altering metric classifications. Accepted-run log existence independently confirmed viaLoki. [Findings/test output](../issues/2026-10-27-run-evidence-empty-link-and-attribution-findings.md). Publish metrics/applydashboard/UI verification still pending.

Operator screenshot/report “fixed now” confirms the single-table rendering with visible hyperlinks for accepted, unverified(empty-path) and failed startup rows, and correct status/Result labels. Destination navigation/test output still requires the next single click check. Recorded in the empty-link/attribution findings issue; no screenshot export.

Operator accepted-log check PASS: webhook-incident-doctor-luna/run3 opened correct Agent Run Log with5/5BATS and21Python output, correct Resultheading. Earlier unverifiedrun2 availability navigation also PASS. Final failed-startup local-only route check still pending before original P3liveclosure. Full textual evidence in empty-link/attribution findings issue; no image export.
