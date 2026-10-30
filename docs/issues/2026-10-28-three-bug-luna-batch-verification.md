# Three selected screenshot bugs — Luna and independent verification

Operator selected webhook incident P2, PR duration history P3 and target-state
readability P3 on2026-10-28. Existing bug specs explicitly amended to bounded
current authorization; no new plan doc or UI panel. Native dispatcher launched
gpt-6-luna tasks target-state-readable-reason-luna,
pr-checks-history-semantics-luna and webhook-incident-evidence-review-luna.
Workers do not deploy/restart/access credentials or raw live logs, stage/commit,
push or modify memory. Coordinator independently reviews, stages/gates/commits,
lands/pushes; live acceptance remains operator-owned one step at a time.

## Target state readability — offline PASS

Commit2f551fc7090dea8416f7a008eb9881048a7d66ea. Source review of supported Grafana
11.4 BigValueLayout options.text.titleSize/valueSize and normal title wrapping:
https://github.com/grafana/grafana/blob/v11.4.0/packages/grafana-ui/src/components/BigValue/BigValueLayout.tsx
Independent YAML/JSON comparison: only panel31 options.text changed; exact
query, mappings, grid and all other panels unchanged. No runtime query changes
or extra panels. Full/narrow width legibility remains untested until operator UI.
Actual independent BATS:
```text
1..38
ok 1 bug dashboard is valid JSON with uid and Prometheus datasource
ok 2 release forecast panels align by version and map dates and states
ok 3 release cadence panel names the median tag gap and explains cadence
ok 4 target state names the blocked milestone and reason
ok 5 remaining releases table shows a not-before column
ok 6 bug dashboard has a release variable
ok 7 bug dashboard has a repo variable and scopes every bug selector
ok 8 bug dashboard has a verified filter
ok 9 bug dashboard defaults to Auto current release and keeps Manual selection
ok 10 Auto bug filtering follows the repo-scoped current-release metric
ok 11 release dropdown and table use version-order labels
ok 12 Auto and Manual modes filter every filed-in bug summary and the table
ok 13 release summary tiles follow mode while repository-wide tiles do not
ok 14 bug dashboard separates filed-in and fixed-in release views
ok 15 every bug metric queried by dashboard is emitted
ok 16 bug dashboard panels have non-overlapping positions inside 24 columns
ok 17 release forecast sits between the plan tiles and the Plans table, and lists only unshipped milestones for the selected release
ok 18 plan titles link to the plan doc with redundant Plan hidden, and bug tiles say bugs
ok 19 bug dashboard release plans row shows joined plan state without not-started inference
ok 20 bug dashboard Plans table orders plans numerically and shows dependencies
ok 21 bug dashboard bar charts blank the labels of empty segments
ok 22 bug dashboard pins one colour per priority and state, independent of data order
ok 23 bug dashboard stacked bars give counts in the tooltip, not on-bar labels
ok 24 open bugs table links each title to its doc on the scanned branch
ok 25 bug dashboard separates verified and live-verified summary and table
ok 26 Verified column reads verified, and only Live-verified reads live
ok 27 open bugs table sorts by sort_key before hiding it
ok 28 open bugs table sits in row 22 under the stats, with the time series moved below
ok 29 bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified (at), Live-verified (at)
ok 30 open bugs table shows age in days, not a duration that rolls up to weeks
ok 31 bugs table shows a dash, not a missing column, for an open bug's Fixed in and verification
ok 32 bugs table pairs each verification column with its timestamp
ok 33 Plans Dispatch links to the release in Agent dispatch
ok 34 priority tiles say they count open bugs
ok 35 bugs table columns fit a laptop-width panel without horizontal scrolling
ok 36 plans table columns fit a laptop-width panel without horizontal scrolling
ok 37 remaining releases table shows forecast dates only and fits a laptop-width panel
ok 38 Plans table separates verified and live-verified status indicators

```

Staged lint/audit and checkpoint output:
```text
running under bash version 5.3.20(1)-release
running under bash version 5.3.20(1)-release
check-doc-links: 1 file(s) OK
[task/v1.43.9/target-state-readable-reason-luna 2f551fc7] checkpoint: before fix: make Target state blocker text readable
scope: in-scope
tests: passed
landed: target-state-readable-reason-luna
```
ShellCheck N/A: no shell implementation changed. Existing dashboard BATS were
extended, test count38 preserved. Config contract red on old sizing per worker
output; independently reviewed missing text options in base. No visual pass claim.

## Webhook incident evidence review — offline PASS, incident OPEN

Review landed223bb879. Current code matches review: default7443, health budget15s,
read-only doctor and operator-controlled recovery; bridge honors override envs.
No new code bug proven. Earlier local/Slack evidence does not prove historical
cause or current bridge delivery. Coordinator corrected obsolete port9000 snippet
in original bug to7443; loaded override still authoritative. No live test/restart.
Independent actual focused outputs:
```text
============================= test session starts ==============================
platform darwin -- Python 3.15.1, pytest-9.1.1, pluggy-1.7.0
rootdir: /Users/cliang/src/gitrepo/personal/k3d-manager
collected 142 items

scripts/tests/bin/test_webhook_doctor.py ............................... [ 21%]
....                                                                     [ 24%]
scripts/tests/bin/test_cloud_bridge.py ................................. [ 47%]
......................................................................   [ 97%]
scripts/tests/bin/test_restart_cloud_bridge.py ....                      [100%]

============================= 142 passed in 3.87s ==============================
1..5
ok 1 restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook
ok 2 restart-webhook continues to bootstrap when bootout reports the job is not loaded
ok 3 restart-webhook still restarts the cloud bridge
ok 4 restart-webhook retries bootstrap twice then reports success
ok 5 restart-webhook fails after five bootstrap attempts and skips cloud bridge

```
Dispatcher reran142Python+5BATS after private task rebase onto current release;
all passed. Worktree staged audit/lint/hooks pass. No shell implementation
changed. Worker full evidence and checklist:
[offline incident review](2026-10-28-webhook-incident-luna-review.md).

## Findings during dispatch/review

Sandbox status initially reported `terminated unexpectedly` for all three tasks,
but codex logs were active and permitted process/status checks reported `running`.
This was restricted process visibility, not worker startup failure. No worker
restart or duplicate task launched. Later actual status confirmed successful exits.
PR first submission contained toy constant/list assertions disconnected from
producer/query execution. Coordinator requested Luna rework2 for meaningful real
collector and PromQL fixtures, retaining actual old-presentation regression.
First PR worker test had wording assertion failure, corrected before green;
record final exact outputs on acceptance. No live check counted from these tests.

## PR Checks follow-up — offline PASS

Commit2b21e8af (rebased private task ca4bf186 onto current release at landing).
Independent YAML/JSON structural comparison:8originalpanels; queries/options/
transforms/mappings/layout unchanged, only panel8title and5/6/7/8descriptions
changed. Collector untouched; real newtests exercise collect/render/render_failure.
Actual final independent outputs:
```text
============================= test session starts ==============================
platform darwin -- Python 3.15.1, pytest-9.1.1, pluggy-1.7.0
rootdir: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/pr-checks-history-semantics-luna
collected 4 items

scripts/tests/hermes/test_pr_checks.py ....                              [100%]

============================== 4 passed in 0.09s ===============================
1..6
ok 1 PR checks dashboard YAML and embedded JSON are valid
ok 2 PR checks dashboard has filtered panels and repo variable
ok 3 PR checks tables say No open PRs instead of No data when nothing is open
ok 4 PR checks tables join populated rows without duplicate label fields
ok 5 PR check duration legend uses a readable side layout without changing its query
ok 6 PR checks distinguish current rows, retained history, empty ranges, and failed or stale reads
All checks passed!
```
Ruff used installed /private/tmp/k3dm-review-tools/bin/ruff. BATS ran with
promtool3.2.1 onPATH (zero skips); stale-marker/current/range/All/repo/no-history/
failed/stale-age fixtures evaluate actual dashboard expressions, not toyconstants.
Independent old-dashboard red (fix restored in finally block):
```text
1..2
not ok 1 PR check duration legend uses a readable side layout without changing its query
# (in test file scripts/tests/plugins/grafana_dashboard_pr_checks.bats, line 129)
#   `[ "${status}" -eq 0 ]' failed
not ok 2 PR checks distinguish current rows, retained history, empty ranges, and failed or stale reads
# (in test file scripts/tests/plugins/grafana_dashboard_pr_checks.bats, line 148)
#   `echo "$output"; [ "${status}" -eq 0 ]' failed
# Traceback (most recent call last):
#   File "<stdin>", line 7, in <module>
# AssertionError

```
Initial real-query fixture failure (test expectation, no production-query defect):
```text
1..6
ok 1 PR checks dashboard YAML and embedded JSON are valid
ok 2 PR checks dashboard has filtered panels and repo variable
ok 3 PR checks tables say No open PRs instead of No data when nothing is open
ok 4 PR checks tables join populated rows without duplicate label fields
ok 5 PR check duration legend uses a readable side layout without changing its query
not ok 6 PR checks distinguish current rows, retained history, empty ranges, and failed or stale reads
# (in test file scripts/tests/plugins/grafana_dashboard_pr_checks.bats, line 245)
#   `echo "$output"; [ "${status}" -eq 0 ]' failed
#
#
#   FAILED:
#     expr: "max by (__join) (label_join(k3dm_pr_check_duration_seconds{repo=~\"wilddog64/lib-foundation\"},\"__join\",\":\",\"repo\",\"pr\",\"check\"))", time: 5m,
#         exp: {__join="wilddog64/lib-foundation:66:lint", check="lint", pr="66", repo="wilddog64/lib-foundation"} 4.5E+01
#         got: {__join="wilddog64/lib-foundation:66:lint"} 4.5E+01

```
max by(__join) drops other labels, so corrected fixture to actual expected
__join-only shape. Worker first Ruff command was unavailable on defaultPATH;
installed Ruff was then used successfully, no dependency installed. All final
staged lint/audit/checkpoint hooks passed, landing reran4pytest+6BATS+Ruff green.
ShellCheck N/A: no shell implementation changed. No full curated-suite rerun;
previously recorded unrelated failures remain, no claim of repo-wide green.

## Completion boundary and next live step

Target-state fix2f551fc7 and PR-history fix2b21e8af are VERIFIED offline and landed.
Incident review223bb879 is complete; original P2 incident stays OPEN because
historical cause/current bridge live evidence is not established. Never claim
allthreebugsclosed from worker exits. No coordinator deploy, service restart,
Keychain access/rotation, cloud/Slack request or screenshot export performed.
Operator live work begins with make webhook-doctor; inspect its redacted JSON
before any recovery or cloud action. Subsequent dashboard live checks require
fresh ArgoCD revision/ConfigMap and operator normal/narrow screenshots and PR
GitHub timestamp cross-checks, one step at a time. No extra panels introduced.

## Operator live step1 — local doctor PASS

Actual operator output after make webhook-doctor:
```json
{"classification": "local_http_healthy_external_delivery_unverified", "credential": {"lookup_exit": 0, "source": "keychain", "status": "available"}, "credential_action": null, "health": {"all_ok": true, "http_responsive": true, "status": "healthy_http"}, "health_timeout_seconds": 15, "launchd": {"last_exit_code": null, "pid": 4295, "port": 7443, "status": "loaded"}, "listener": {"listening": true, "status": "listening"}, "log": {"available": true, "error_categories": [], "freshness": "fresh", "modified_utc": "2026-10-28T11:44:15.998184+00:00"}, "mode": "check", "process": {"pids": [4295], "status": "available"}, "recovery_action": null, "recovery_recommended": false, "timestamp_utc": "2026-10-28T11:44:33.867109+00:00"}
```
Authenticated local HTTP and downstream all_ok pass at11:44:33Z, loaded PID4295,
port7443 listening, reader credential available, log fresh/no errors, recovery
not recommended. No webhook restart warranted. External cloud-bridge delivery
is explicitly unverified. Historical cause remains unknown; original P2 OPEN.
No new test failure or code change; docs-only verification, no rerun needed.
Next operator step is the previously pending one-time bridge reload to activate
reviewed SSH-auth implementation f046763f, not webhook recovery. Use
make restart-cloud-bridge, inspect result before a separate benign health request.
No coordinator service mutation, credential access or external request performed.

## Operator bridge reload — process PASS, delivery pending

Operator reports make restart-cloud-bridge returned no output. Makefile target
suppresses command echo and directly calls launchctl kickstart -k; success is
normally silent, while a missing installation emits an explicit skip warning.
Read-only filtered launchd/process result (raw environment not emitted):
```json
{"launchctl_exit": 0, "state": "running", "pid": "65583", "runs": "89", "process": "65583 00:31 /opt/homebrew/Cellar/python@3.15/3.15.1/Frameworks/Python.framework/Versions/3.15/Resources/Python.app/Contents/MacOS/Python"}
```
Running process age31s is consistent with the operator reload. Operator did
not supply an exit code, so do not invent one. This confirms current process,
not end-to-end delivery or historical cause. Next single operator request:
bin/k3dm-cloud-request --wait health. Inspect completed response, not queued.
No coordinator restart/cloud request, credentials or raw logs accessed. Docs-only;
no test rerun or new failure. Original incident remains OPEN pending evidence.

## Operator bridge health request — end-to-end PASS

Full actual operator output:
```text
20261028T114826Z-health
{"action": "health", "body": {"all_ok": true, "services": [{"detail": "HTTP 200", "name": "ArgoCD", "ok": true}, {"detail": "HTTP 200", "name": "Frontend", "ok": true}, {"detail": "HTTP 200", "name": "Keycloak", "ok": true}, {"detail": "HTTP 401 (auth enforced)", "name": "Prometheus", "ok": true}, {"detail": "HTTP 200", "name": "Grafana", "ok": true}, {"detail": "HTTP 200", "name": "Pushgateway", "ok": true}, {"detail": "20/20 have image_url", "name": "Product images", "ok": true}, {"detail": "Ready=True", "name": "ESO ClusterSecretStore", "ok": true}, {"detail": "20/20 synced", "name": "ESO ExternalSecrets", "ok": true}, {"detail": "Ready=True", "name": "Hub ESO ClusterSecretStore", "ok": true}, {"detail": "9/9 synced", "name": "Hub ESO ExternalSecrets", "ok": true}, {"detail": "4/4 ready", "name": "Data layer", "ok": true}, {"detail": "admin via identity/keycloak-secrets Secret: HTTP 200", "name": "Keycloak admin login", "ok": true}, {"detail": "admin via Vault keycloak/users: code received; developer via Vault keycloak/users: code received; operator via Vault keycloak/users: code received", "name": "Frontend SSO login", "ok": true}, {"detail": "admin via Vault argocd/admin: HTTP 200", "name": "ArgoCD login", "ok": true}, {"detail": "admin via Vault keycloak/users/admin: code received", "name": "ArgoCD SSO login", "ok": true}, {"detail": "admin via Vault k3d-manager/prometheus-basic-auth: HTTP 200", "name": "Prometheus login", "ok": true}, {"detail": "admin via ~/.local/share/k3d-manager/alertmanager-basic-auth.env: HTTP 200", "name": "Alertmanager login", "ok": true}, {"detail": "admin via Vault observability/grafana: HTTP 200", "name": "Grafana login", "ok": true}, {"detail": "k3dm-smoke-user via identity/k3dm-smoke-user Secret: HTTP 200", "name": "Keycloak smoke token (k3dm-smoke-user)", "ok": true}, {"detail": "k3dm-smoke-user via identity/k3dm-smoke-user Secret: HTTP 200 on /api/cart", "name": "Frontend API (smoke token)", "ok": true}]}, "completed_at": "2026-10-28T11:49:51.677857Z", "http_status": 200, "id": "20261028T114826Z-health", "schema": 1, "status": "ok"}
```
Completed response HTTP200/statusok/all_oktrue proves current request/reply path
through cloud-bridge and webhook after operator bridge reload. All21servicechecks
ok; Prometheus unauthenticated401 is explicitly expected auth enforcement.
Together with local doctor11:44:33Z, current local and external functionality
are verified. Bridge auth follow-up f046763f meets documented reload/benignhealth
acceptance; it does not reproduce no-agent failure or establish October26cause.
Original incident remains OPEN for historical cause uncertainty; current external
delivery is no longer missing evidence. No webhook restart needed/performed.

Read-only next-check preparation confirms deployed Target state fix:
```json
{
  "target_state_text": {
    "titleSize": 16,
    "valueSize": 40
  },
  "source_query_preserved": true,
  "revision": [
    "2cbc24d0d51872aa03bd9cd7b087b124de563279",
    "2cbc24d0d51872aa03bd9cd7b087b124de563279"
  ],
  "sync": "Synced"
}
```
Owner Synced, title16/value40 and original query loaded. Concurrent remote
2cbc24d0 added unrelated v2.0.0 plan only; clean local release fast-forwarded
before this documentation record, preserving it without edits. Next single
operator check: fully reload Bug Tracking and inspect Target state at normal
zoom; full/narrow wrapping checks remain pending, no visual pass assumed.
Docs-only, no implementation test rerun or live coordinator mutation/request.

## Operator Target state normal-width screenshot — PASS

Supplied screenshot after reload shows Target state reason in three readable
wrapped lines: `blocked at v1.49.0:`, `TwinkleAI app M1 near`, `done (app repo)`.
Full reason visible with prominent orange `blocked` below, no overlap/clipping.
Remaining row tiles show18releases/median0.510/no-date forecast labels.
Visual sizing/wrapping at supplied normal width PASS. Narrow window still
pending; do not claim responsive acceptance yet or mark LIVE-VERIFIED.
Next single operator action: narrow browser window at unchanged zoom and
show Target state. No raw image copied/exported, no terminal output for UI
check, no code/live mutation or test rerun (documentation-only record).

## Target state requested narrow-view check — PASS

Operator replied to narrower-window check with cropped Target state panel:
full reason wraps across3lines, orange blocked remains clear below, no clipping
or overlap. Viewport dimensions were not provided/measured; this verifies only
the supplied operator view. Combined with prior normal-width view, E2 accepted;
canonical P3 now LIVE-VERIFIED, fix2f551fc7. No image export or terminal output.

Next-check read-only deployed PR Checks ConfigMap inspection:
```json
{"title": "Historical sampled check durations (may include closed PRs)", "query": "k3dm_pr_check_duration_seconds{repo=~\"$repo\"}"}
```
Correct PR-history fix deployed. Next operator single UI check: reload PR Checks,
select shopping-cart-payment and Last7days, inspect current counts/readhealth and
historical sampled durations together. Later GitHub timestamp cross-check and
no-history repo remain pending. Docs-only record; no test rerun/live mutation.

## PR Checks operator All/24h screenshot — partial live PASS

Actual screenshot RepoAll/Last24hours, not requestedpayment/7days. Updatedtitle
and currentPR5/failing0/running0/readok/lastscrape7.25min visible. Retainedpayment
93/94lines coexistwithcatalog62/basket56/order103/104/105currentrows. Read-only
GitHub metadata confirms paymentPRsmergedOct27, actual Build and Test92s/97s.
[Full API outputs/comparison and source anomaly](2026-10-28-pr-checks-github-timestamp-comparison.md).
Nextsingleoperator selectonlyshopping-cart-payment, keepLast24hours, sendcurrent
counts/tables+history/readhealth. Exacttooltip comparison/no-historyrepo later.
CanonicalbugremainsVERIFIED. No screenshotexport/runtimewrites/testsrerun.
