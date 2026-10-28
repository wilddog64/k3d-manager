# Three open screenshot bugs — investigation and Luna work

Operator authorized investigation and task dispatch. Two initial bugs implemented by GPT-6-Luna, independently reviewed, committed/pushed; third incident investigation produced a separately reproducible bridge-auth gap scoped for Luna. No PRs, live mutations/restarts or external messages performed. Original incident cause remains unconfirmed.

## Count routing

Fix b6704d68e04da578bc060cda96e19fe0ae94e5f2. Initial denylist route still accepted release-plan/ticket/alert counts; review required a bounded omitted-noun word grammar. Exact target now bypasses retrieval/model, explicitbugs behavior unchanged, unrelated counts fall through. Relevant new tests were red on original matcher and overbroad first patch; final independent full output:

```text
........................................................................ [ 88%]
.........                                                                [100%]
81 passed in 4.21s
```

## Startup log link

Fix61e1d9944ed19048975dc470d28e57f866a85e1e plus fixture7451280f6b98adc23779ef61da583315abbe7974. Initial patch merely relabeled an unconditional Loki link; review rejected it. Final per-row loki_url exists only for supported landing-test evidence. Exit127 retains failed outcome/localcodex.log path and says local only(not shipped), with no Loki target. Shipper/transcripts/ledger unchanged. New target tests red on cosmetic patch, then green. Final independent pytest:

```text
........................................................................ [ 52%]
..................................................................       [100%]
138 passed in 13.27s
```

Full independent BATS:

```text
1..28
ok 1 agent dispatch dashboard: valid ConfigMap JSON and datasource
ok 2 agent dispatch dashboard: every queried metric is exported
ok 3 agent dispatch dashboard: Claude context and compaction row panels exist below existing rows
ok 4 agent dispatch dashboard: landing success aggregates both sides
ok 5 agent dispatch dashboard: panel rectangles do not overlap
ok 6 agent dispatch dashboard: Codex API cost shows priced total and excluded sessions
ok 7 agent dispatch dashboard: per-spec panels use readable units and grouped targets
ok 8 agent dispatch dashboard: final exit gap and operator coverage are exposed
ok 9 agent dispatch dashboard: window is a query over the exported scopes and defaults to 7d
ok 10 agent dispatch dashboard: rework rate stat reads the selected window
ok 11 agent dispatch dashboard: verified delivery stats use exported metrics without overlap
ok 12 agent dispatch dashboard: stat and bar gauge panels use explicit colours
ok 13 agent dashboards: panel ids exactly match the pre-split dashboard and assigned groups
ok 14 agent dashboards: panel targets, fieldConfig and options match the pre-split fixture
ok 15 agent dashboards: each dashboard has unique panel ids and no overlapping rectangles
ok 16 agent dashboards: all dashboards have the tag-based Agents link
ok 17 agent dashboards: Activity has three time windows and Dispatch and Cost keep the query variable
ok 18 agent activity: Claude row fills the width and bar gauge names read beside each bar
ok 19 agent dispatch: run outcomes read beside each bar, first-pass verification bars with fixed fonts sit beside per run evidence, and each slug links to its spec
ok 20 agent dispatch: failed startup evidence is local-only and the Loki link is scoped to shipped logs
ok 21 agent dispatch: per spec shows which agent landed each spec
ok 22 agent dispatch dashboard: Log opens the filtered run log dashboard
ok 23 agent cost: Claude tokens by kind splits the selected window by cache kind
ok 24 agent cost: daily Claude tokens and cost panels split by kind
ok 25 agent dashboards: labels and titles stay readable and release-only stats say why they are empty
ok 26 agent dispatch dashboard: Per spec exposes unknown worker and coordinator identities
ok 27 agent dispatch dashboard: Per spec shows handoff and measured cost fields within width budget
ok 28 agent dispatch dashboard: Per spec spans the full width and its columns fit without scrolling
```

Independent Ruff output for each task:

```text
All checks passed!
```

Staged lint/audit were actually run, not inferred from worker unstaged gates. First startup audit correctly refused replaced assertion:

```text
WARN: Agent audit: assertions removed from Python test files (add '# agent-audit: allow assert-removed <reason>' on an added line in that file if intended):
WARN: scripts/tests/bin/test_dispatch_metrics.py:
-    assert 'evidence_summary="exit 7"' in line
```

Added local justified audit comment for replacement by stronger exit+local-only assertion; audit/checkpoint/hooks passed, no bypass. First landing then exposed a fixture assumption (normaltmp outsidehome vs dispatcher TMPDIR underhome), full actual failure:

```text
................................................F....................... [ 52%]
..................................................................       [100%]
=================================== FAILURES ===================================
_____ test_failed_startup_exit127_is_local_only_and_retains_codex_log_path _____

tmp_path = PosixPath('/Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/startup-log-link-local-only.run/state/tmp/pytest-of-cliang/pytest-0/test_failed_startup_exit127_is0')

    def test_failed_startup_exit127_is_local_only_and_retains_codex_log_path(tmp_path):
        now = int(time.time())
        output = dispatch_metrics.render([
            event(now - 20, "start", "startup", run=1),
            event(now - 10, "codex_exit", "startup", run=1, exit=127, tokens=10),
        ], 0, now, repo_root=tmp_path)
        line = next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{"))
        assert 'outcome="failed"' in line and 'evidence="codex_exit.exit"' in line
        assert 'evidence_summary="exit 127; local only (not shipped)"' in line
>       assert 'evidence_path="9.9.9/startup.run/codex.log"' in line
E       assert 'evidence_path="9.9.9/startup.run/codex.log"' in 'k3dm_dispatch_task_run_outcome{window="1d",version="9.9.9",slug="startup",run="1",repo="k3d-manager",outcome="failed"...only.run/state/tmp/pytest-of-cliang/pytest-0/test_failed_startup_exit127_is0/worktrees/9.9.9/startup.run/codex.log"} 1'

scripts/tests/bin/test_dispatch_metrics.py:579: AssertionError
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_failed_startup_exit127_is_local_only_and_retains_codex_log_path
1 failed, 137 passed in 9.07s
```

Coordinator isolated fake Path.home for that regression, retaining exact relative-path and no-absolute-path assertions. Focused rerun1 passed/137 deselected. Complete second landing passed138pytest/28BATS/Ruff/diff. Count landing passed81pytest/Ruff/diff. Worker Ruff was initially unavailable; coordinator supplied existing temporary Ruff path, both final checks clean. Python syntax/YAML+embeddedJSON validation passed. Curated full suite not rerun; prior unrelated failures remain in six-bug batch record, no whole-suite-green claim. No shell implementation changed; ShellCheck not applicable to these Python/YAML tasks.

## Webhook/cloud-bridge investigation

Current existing doctor --check output verbatim (read-only):

```json
{"classification": "local_http_healthy_external_delivery_unverified", "credential": {"lookup_exit": 0, "source": "keychain", "status": "available"}, "credential_action": null, "health": {"all_ok": true, "http_responsive": true, "status": "healthy_http"}, "health_timeout_seconds": 15, "launchd": {"last_exit_code": null, "pid": 4295, "port": 7443, "status": "loaded"}, "listener": {"listening": true, "status": "listening"}, "log": {"available": true, "error_categories": [], "freshness": "fresh", "modified_utc": "2026-10-28T01:59:14.316628+00:00"}, "mode": "check", "process": {"pids": [4295], "status": "available"}, "recovery_action": null, "recovery_recommended": false, "timestamp_utc": "2026-10-28T01:59:44.186435+00:00"}
```

Sanitized launchd bridge facts: lookup_exit0, state running, PID4315, no last-exit value. Process start output:

```text
 4295 Sun Oct 25 17:59:40 2026
 4315 Sun Oct 25 17:59:40 2026
```

Read only fixed UTC log patterns, no raw messages/argv/env exported. Window2026-10-26T13:50:00Z–14:50:00Z (reported incident~07:20PDT). Webhook14structured INFO records13:51:37–14:45:50Z. Bridge60structured ERROR records13:50:26–14:49:52Z, all matched the fixed standard message:

```text
ssh: connect to host github.com port 22: Undefined error: 0
```

Other initially tested category patterns did not match; matching is restricted to fixed known patterns, no arbitrary exception content exported. Bridge540explicit ERROR records onOct26, latest explicit log22:17:21Z; missing advisory heartbeat marker is not current poll failure evidence (running process predates marker code).Webhook49820 and bridge2789 unstructured lines were NOT interpreted. Their absence of interpreted errors does not establish functional availability.

Existing remote cloud-requests tree read via GitHub API: not truncated,124request/154response blobs, latest prefixes20261027. Five latest retained response metadata include job-status HTTP200/completed2026-10-27T18:27:03.313612Z and18:26:00.604186Z, and other actionsHTTP202 completed18:26:36.560370Z,18:25:31.174182Z,18:21:59.280782Z. These are retained later successful bridge responses, not a new current functional probe; request payload/body/user metadata not exported. No request was created.

Controlled read-only Git branch lookups, same user/env except explicit SSH mode and no SSH_AUTH_SOCK; token/key material never printed:

```json
[
  {"mode":"no_agent","exit":128,"branch_head_present":false,"permission_denied_publickey":true,"ssh_connect_failure":false},
  {"mode":"keychain_no_agent","exit":0,"branch_head_present":true,"permission_denied_publickey":false,"ssh_connect_failure":false}
]
```

No-agent SSH command /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8. Successful mode adds -o UseKeychain=yes. Git ls-remote --heads origin refs/heads/cloud-requests is read-only; no Keychain mutation/credential export. The launchd-like auth gap reproduces; exact historical Undefined error:0 does NOT. Hermes already has fallback fix3aae7adc, bridge _git does not. Third bounded task in linked newP2; no speculative rewrite or claim original incident solved. Original incident stays OPEN.

## Pending live verification

No dashboard deployed, webhook/bridge restarted or Slack/cloud request sent by coordinator. Later operator checks remain one at a time after all offline review/landing: apply updated dashboard, verify unsupported/supported log rows; reload webhook for count route and ask exact wording; reload bridge then request one benign health result. Choose only one at each handoff, not a command bundle. Each current success has limits; retain historical incident/root-cause distinction.

## Third task completed offline — cloud-bridge Keychain Git fallback

Luna task cloud-bridge-keychain-git-auth landed implementation `f046763ff2a45e8fe56b938a8f828658d0b05ebe` on the release branch. _git copies the caller environment (or inherited env), adds the same established Hermes macOS default only if GIT_SSH_COMMAND is absent, and preserves explicit empty/custom overrides and other platforms. No credential/SSH/plist config or locking policy changed. The caller/env immutability checks and no-direct-SSH boundary were strengthened during review.

Initial new regression against original bridge actual output:

```text
FAILED scripts/tests/bin/test_cloud_bridge.py::test_git_uses_keychain_ssh_fallback_on_macos_without_override[None]
FAILED scripts/tests/bin/test_cloud_bridge.py::test_git_uses_keychain_ssh_fallback_on_macos_without_override[provided_env1]
2 failed, 99 deselected in 0.56s
```

Initial source change also hit the old blanket no-ssh-string guard (expected given the new allowed Git SSH env string):

```text
>       assert "ssh" not in source.lower()
E       assert 'ssh' not in '#!/usr/bin/...    main()\n'
```

Review rejected a weak replacement that only searched for a direct literal ssh argument. Final test removes only the exact approved env identifier/default string, then preserves the no-other-SSH assertion; explicit audit explanation records the legitimate replacement. No production SSH call was introduced outside Git transport.

First independent105pytest passed; after review corrections final independent command python3 -m pytest -p no:cacheprovider scripts/tests/bin/test_cloud_bridge.py scripts/tests/bin/test_restart_cloud_bridge.py -q output:

```text
........................................................................ [ 67%]
...................................                                      [100%]
107 passed in 3.48s
```

Ruff:

```text
All checks passed!
```

Actual staged lint/audit output exit0:

```text
running under bash version 5.3.20(1)-release
running under bash version 5.3.20(1)-release
```

Python syntax/diffcheck clean; checkpoint hook doc links1fileOK. Dispatcher repeated107pytest/Ruff/diff and returned:

```text
scope: in-scope
tests: passed
landed: cloud-bridge-keychain-git-auth
push: git -C /Users/cliang/src/gitrepo/personal/k3d-manager push origin k3d-manager-v1.43.9
```

Across the three tasks independent focused totals326Python tests and28BATS pass; complete outputs are above, with failures/skips explicitly recorded. No full curated rerun or claim its pre-existing failures resolved. All implementations committed to release, no PR created. No live service restart/Keychain change/deployment or remote request by coordinator. Historical offsite incident stays OPEN; bridge-auth follow-up VERIFIED offline only.

First next operator live step: make platform-ops to apply updated Agent Dispatch dashboard, inspect deployment output, then view startup/supported log rows. Subsequent webhook/bridge reload is for installing the newly reviewed code, not inference that currently healthy webhook needs outage recovery. Keep remaining query/bridge checks separate and one at a time.

## Operator platform-ops deployment — dashboard applied, metrics refresh pending

Operator terminal tail verbatim:

```text
INFO: [argocd] Syncing k3dm-webhook-token Secret into namespace cicd from Keychain...
secret/k3dm-webhook-token unchanged
INFO: [argocd] Syncing platform-ops-app-rebuild Secret (gh-token) into namespace platform-ops from Keychain...
secret/platform-ops-app-rebuild unchanged
INFO: [argocd] Syncing platform-ops-git-writer Secret (git-token) into namespace platform-ops from Keychain...
secret/platform-ops-git-writer unchanged
INFO: [argocd] ArgoCD monthly credential rotator applied
Success! Uploaded policy: argocd-rotationSuccess! Data written to: auth/kubernetes/role/argocd-rotationINFO: [argocd] platform-ops deployed — CVE scan: 1st+15th, expiry check: every 30m
INFO: [argocd] Secrets still to create manually (no durable local source):
INFO: [argocd]   kubectl create secret generic oci-kubeconfig --from-file=config=<path> -n platform-ops
INFO: [argocd]   kubectl patch secret platform-ops-notifications -n platform-ops --type=merge \
INFO: [argocd]     -p '{"data":{"slack-incoming-webhook-url":"<base64-url>"}}'
```

Independent read-only monitoring ConfigMap JSON comparison result:

```json
{
  "dashboard_json_matches": true,
  "deployed_dashboard_sha256": "cf105d791db5954f33bfc06560fb8ee84e2c8cdbd3edecc3ae5aab3521d83b94",
  "panel_title": "Per run evidence",
  "query_retains_loki_url": true,
  "log_links": [
    {
      "title": "Open shipped landing-test log",
      "url": "${__data.fields.loki_url}"
    }
  ]
}
```

Selected published7d row fields from read-only localhost19094/metrics (only these labels exported for review):

```json
{
  "selected_published_rows": [
    {"version":"v1.43.9","slug":"vectordb-retrieval-key-cache-retry","run":"1","outcome":"failed","evidence":"codex_exit.exit","evidence_summary":"exit 127","loki_url":null},
    {"version":"v1.43.9","slug":"vectordb-retrieval-key-cache","run":"1","outcome":"failed","evidence":"codex_exit.exit","evidence_summary":"exit 127","loki_url":null},
    {"version":"v1.43.9","slug":"startup-log-link-local-only","run":"1","outcome":"unknown","evidence":"none","evidence_summary":"none","loki_url":null}
  ]
}
```

The dashboard is current but these metric rows have not acquired the new local-only summary or final task state. Deployment does not itself run the host-side metric publisher. Local scheduler metadata:

```json
{
  "metrics.lock": {"exists":true,"modified_epoch":1793153705.5586774,"pid_available":false},
  "metrics.pending": {"exists":true,"modified_epoch":1793153798.176973},
  "metrics.log": {"exists":true,"modified_epoch":1793017297.0247214}
}
```

The scheduler uses a directory lock and pending marker (no pid file is part of that contract); absent pid metadata is not proof of a dead process. No lock was deleted or process killed. Background publisher completion/cause of lag not established. Avoid treating missing Loki target on this old export as sufficient live proof of new behavior. Next single operator command make dispatch-metrics invokes existing publisher and ships supported landing-test logs; inspect its output, then selected published metrics, before dashboard UI check. No coordinator metric PUT, log shipping, synthetic ledger edit or production restart performed. Generic manual-secret reminder is not proof those Secrets are absent; none were read/decoded in this check. Canonical bug stays VERIFIED offline pending UI/live evidence.

## Silent operator metrics refresh — publication verified

Operator reports make dispatch-metrics returned no output. Existing Make recipe is quiet and publisher prints only failures; silence alone was not treated as success. Independent read-only localhost19094/metrics verification returned these selected7d rows (same5-slug selection as prior check):

```json
{
  "selected_published_rows": [
    {
      "version": "v1.43.9",
      "slug": "vectordb-retrieval-key-cache-retry",
      "run": "1",
      "outcome": "failed",
      "evidence": "codex_exit.exit",
      "evidence_summary": "exit 127; local only (not shipped)",
      "loki_url": null
    },
    {
      "version": "v1.43.9",
      "slug": "vectordb-retrieval-key-cache",
      "run": "1",
      "outcome": "failed",
      "evidence": "codex_exit.exit",
      "evidence_summary": "exit 127; local only (not shipped)",
      "loki_url": null
    },
    {
      "version": "v1.43.9",
      "slug": "ask-docs-priority-count-intent",
      "run": "1",
      "outcome": "unknown",
      "evidence": "none",
      "evidence_summary": "none",
      "loki_url": null
    },
    {
      "version": "v1.43.9",
      "slug": "cloud-bridge-keychain-git-auth",
      "run": "1",
      "outcome": "unknown",
      "evidence": "none",
      "evidence_summary": "none",
      "loki_url": null
    },
    {
      "version": "v1.43.9",
      "slug": "startup-log-link-local-only",
      "run": "1",
      "outcome": "unknown",
      "evidence": "none",
      "evidence_summary": "none",
      "loki_url": null
    },
    {
      "version": "v1.43.9",
      "slug": "ask-docs-priority-count-intent",
      "run": "2",
      "outcome": "accepted",
      "evidence": "land-test.log",
      "evidence_summary": "81 passed",
      "loki_url": "/d/k3dm-agent-run-log?var-version=v1.43.9&var-slug=ask-docs-priority-count-intent&var-run=2&from=now-30d&to=now"
    },
    {
      "version": "v1.43.9",
      "slug": "cloud-bridge-keychain-git-auth",
      "run": "2",
      "outcome": "accepted",
      "evidence": "land-test.log",
      "evidence_summary": "107 passed",
      "loki_url": "/d/k3dm-agent-run-log?var-version=v1.43.9&var-slug=cloud-bridge-keychain-git-auth&var-run=2&from=now-30d&to=now"
    },
    {
      "version": "v1.43.9",
      "slug": "startup-log-link-local-only",
      "run": "2",
      "outcome": "accepted",
      "evidence": "land-test.log",
      "evidence_summary": "28/28 ok; 138 passed",
      "loki_url": "/d/k3dm-agent-run-log?var-version=v1.43.9&var-slug=startup-log-link-local-only&var-run=2&from=now-30d&to=now"
    }
  ]
}
```

The two historical exit127 failures now carry the new local-only summary with no Loki target. Supported acceptedrun2 rows carry the precise per-row Loki target and real test summaries. Earlier run1 unknown rows remain historical attempts; no ledger rewritten. Current publication prerequisite passed. Still pending: actual Grafana rendering/click behavior. Next single operator check refresh Agent Dispatch/Per run evidence and show the two historical failed startup rows. No coordinator metric write, service restart, UI action or log export. Evidence-only update; prior326Python/28BATS and staged gate results remain, no code/test rerun.

## Operator screenshot: local-only Result renders; click behavior pending

[Supplied Per run evidence screenshot](../assets/2026-10-27-startup-log-local-only-render.png) shows both vectordb-retrieval-key-cache and -retry rows failed, run1, Result beginning exit127;localonly(not…); accepted retry2 remains accepted. Thus refreshed row status/Result visible. Local log paths still render blue in both failed rows, like the supported rows. The cropped image does not show a link destination or a click result; cannot infer the unwanted Loki action is absent from color or missing metric target alone.

Next single operator UI check: click Log on failed vectordb-retrieval-key-cache and report actual action/destination. Do not mark the P3 LIVE-VERIFIED until unsupported row no longer opens empty Loki and a supported landing-log action is also confirmed. No coordinator click, new metric write, restart or ledger change. Offline138Python/28BATS remains valid; this is a limited rendering observation, not complete UI verification. If missing-field interpolation still provides an action, reopen implementation with actual click evidence rather than claiming the current patch complete.

## Live click failed; P3 reopened and correction scoped

Operator screenshot /tmp/codex-clipboard-ljiUHu.png shows Grafana Page not found after clicking the failed-startup Log action. Exact destination absent from image. Do not archive that full-browser screenshot (unrelated credential-page browser tab titles are visible); observation recorded without extra personal tab artifact. Prior cropped table screenshot already archived shows failed Log cells remain blue. Actual live assertion unsupported row has no action FAILED. P3 reopened; previous null-target metric/frontend assumption was insufficient.

Read-only deployed Grafana image: docker.io/grafana/grafana:11.4.0. Primary source review: [DefaultCell v11.4](https://github.com/grafana/grafana/blob/v11.4.0/packages/grafana-ui/src/components/Table/DefaultCell.tsx) computes hasLinks from configured getCellLinks; [getLinksSupplier v11.4](https://github.com/grafana/grafana/blob/v11.4.0/packages/grafana-data/src/field/fieldOverrides.ts) creates models from configured links without requiring a nonempty interpolated per-row URL. Current table keeps links configured on every Log cell, while loki_url is removed by organize. Structural no-link/support separation scoped; no dependency upgrade or new transcript export. Browser destination specifics not inferred; supported-link behavior still needs live check.

Other screenshot questions: coordinator/primary/acting/landing unknown values come from absent/unreported ledger declarations, not task failure. Selected recent start events have worker modelgpt-6-luna and coordinator_identity vendor/modelunknown sourceunreported. Land events omit actor or explicitly actorunknown because coordinator omitted optional flags. No old history rewritten/guessed. Correction task will declare known coordinator vendoropenai/modelunknown and landing actorcodex; exact coordinator model is not established here.

Historical key-cache and-retry each have startagentcodex/modelnull then codex_exit127, no codex_usage. Recorded local startup errors were missingcodex then missingnode, before worker session; missing usage yields blank token field, not fabricated zero. Retry2successful usage stays independent. No worker costs inferred from failure status.

## Corrective no-action dashboard task — independent review and landing

GPT-6-Luna corrective task startup-log-noninteractive-cells supersedes prior startup-log-link-local-only. Commit `0d1807715691c0b21c344de7d0af724ff05c5e20`. The prior operator live click FAILED with Page not found; do not overwrite that evidence or call the previous patch live verified.

Per run evidence preserves all rows and plain Log path width/inspection; its defaults/Log override have no data links. Supported landing logs(newpanel93) admits only anchored exact land-test.log/land_refused.tests evidence. Supported links use fixed /d/k3dm-agent-run-log with visible version/slug/run placeholders, not a hidden/removed loki_url. Token query is filtered to supported evidence too. The unused URL label was removed from the plain table query; no metric schema or shipper/history changed.29otherexistingpanels unchanged, grid has no overlap. No plugins/custom frontend/Grafanaupgrade.

Worker initial corrective attempt reserialized unrelated JSON and still referenced a hidden URL field; coordinator rejected that and required a surgical diff and retained-field URL. Relevant mutation-red check output:

```text
not ok 1 agent dispatch dashboard: Log opens the filtered run log dashboard
```

It failed when previous loki_url interpolation was put back, then passed after the fixed retained-field link. Unsupported-field configuration regression also failed on prior configured-link table. Worker initially lacked Ruff executable; final existing temporary Ruff path used successfully. Final independent full Python output:

```text
........................................................................ [ 52%]
..................................................................       [100%]
138 passed in 16.12s
```

Final independent BATS output:

```text
1..28
ok 1 agent dispatch dashboard: valid ConfigMap JSON and datasource
ok 2 agent dispatch dashboard: every queried metric is exported
ok 3 agent dispatch dashboard: Claude context and compaction row panels exist below existing rows
ok 4 agent dispatch dashboard: landing success aggregates both sides
ok 5 agent dispatch dashboard: panel rectangles do not overlap
ok 6 agent dispatch dashboard: Codex API cost shows priced total and excluded sessions
ok 7 agent dispatch dashboard: per-spec panels use readable units and grouped targets
ok 8 agent dispatch dashboard: final exit gap and operator coverage are exposed
ok 9 agent dispatch dashboard: window is a query over the exported scopes and defaults to 7d
ok 10 agent dispatch dashboard: rework rate stat reads the selected window
ok 11 agent dispatch dashboard: verified delivery stats use exported metrics without overlap
ok 12 agent dispatch dashboard: stat and bar gauge panels use explicit colours
ok 13 agent dashboards: panel ids exactly match the pre-split dashboard and assigned groups
ok 14 agent dashboards: panel targets, fieldConfig and options match the pre-split fixture
ok 15 agent dashboards: each dashboard has unique panel ids and no overlapping rectangles
ok 16 agent dashboards: all dashboards have the tag-based Agents link
ok 17 agent dashboards: Activity has three time windows and Dispatch and Cost keep the query variable
ok 18 agent activity: Claude row fills the width and bar gauge names read beside each bar
ok 19 agent dispatch: run outcomes read beside each bar, first-pass verification bars with fixed fonts sit beside per run evidence, and each slug links to its spec
ok 20 agent dispatch: failed startup evidence is local-only and the Loki link is scoped to shipped logs
ok 21 agent dispatch: per spec shows which agent landed each spec
ok 22 agent dispatch dashboard: Log opens the filtered run log dashboard
ok 23 agent cost: Claude tokens by kind splits the selected window by cache kind
ok 24 agent cost: daily Claude tokens and cost panels split by kind
ok 25 agent dashboards: labels and titles stay readable and release-only stats say why they are empty
ok 26 agent dispatch dashboard: Per spec exposes unknown worker and coordinator identities
ok 27 agent dispatch dashboard: Per spec shows handoff and measured cost fields within width budget
ok 28 agent dispatch dashboard: Per spec spans the full width and its columns fit without scrolling
```

Additional independent validation output:

```text
All checks passed!
unchanged existing panels: 29
plain Log field: no configured data links
Python/YAML/embedded JSON syntax: valid
Checking /private/tmp/k3dm-noninteractive-query-rules.yaml
  SUCCESS: 2 rules found
```

Actual staged lint/audit passed; expected-query-count assertion changed78to80 for the2newqueries, with an explicit legitimate replacement marker. Audit/checkpoint hooks passed, no bypass. No shell changes, ShellCheck not applicable. Required post-rebase landing repeated138Python/28BATS/Ruff/diff and returned:

```text
scope: in-scope
tests: passed
landed: startup-log-noninteractive-cells
push: git -C /Users/cliang/src/gitrepo/personal/k3d-manager push origin k3d-manager-v1.43.9
```

A branch-SHA lookup after landing returned unknown revision because dispatcher had already removed its task branch; SHA above comes from landed release HEAD. No history rewrite. No production deployment/metric push/GUI click/restart by coordinator. First operator step make platform-ops to deploy dashboard; then recheck unsupported plain paths and separately a supported landing-log link. UI verification remains pending even though source-contract/query/fixture gates pass.

Metadata clarification from actual ledger: previous recent tasks omitted optional coordinator/primary/landing declarations (sourceunreported or actorunknown); known workerLuna is independent. Blank token cells for historical exit127 match no codex_usage events after startup failures (missingcodex/node), not fabricated zero. Successfulretry2 is separate usage. No old metadata/costs backfilled. Corrective task declares coordinator and primary vendoropenai/modelunknown; landing actorcodex/vendoropenai/modelunknown. Acting coordinator remains unrecorded absent a handoff, and exact model/costs stay unknown. These metadata limits are independent of task success.

## Correction: platform-ops does not install Agent Dispatch dashboard

Operator followed coordinator's suggested make platform-ops and supplied this tail:

```text
secret/platform-ops-app-rebuild unchanged
INFO: [argocd] Syncing platform-ops-git-writer Secret (git-token) into namespace platform-ops from Keychain...
secret/platform-ops-git-writer unchanged
INFO: [argocd] ArgoCD monthly credential rotator applied
Success! Uploaded policy: argocd-rotationSuccess! Data written to: auth/kubernetes/role/argocd-rotationINFO: [argocd] platform-ops deployed — CVE scan: 1st+15th, expiry check: every 30m
INFO: [argocd] Secrets still to create manually (no durable local source):
INFO: [argocd]   kubectl create secret generic oci-kubeconfig --from-file=config=<path> -n platform-ops
INFO: [argocd]   kubectl patch secret platform-ops-notifications -n platform-ops --type=merge \
INFO: [argocd]     -p '{"data":{"slack-incoming-webhook-url":"<base64-url>"}}'
```

Read-only verification unexpectedly found no panel93. First probe assumed it existed and failed:

```text
Traceback (most recent call last):
  File "<stdin>", line 7, in <module>
StopIteration
```

Follow-up safely queried existing content:

```json
{
  "panel93_present": false,
  "panel_count": 30,
  "plain_table_title": "Per run evidence",
  "plain_log_actions": [
    {
      "title": "Open shipped landing-test log",
      "url": "${__data.fields.loki_url}"
    }
  ]
}
```

Source deploy_argocd_platform_ops in scripts/plugins/argocd.sh applies dashboards argocd, cve-autopatch, e2e, alertmanager-delivery, vectordb only; it does not apply grafana-dashboard-agent-dispatch.yaml. Coordinator's prior deployment guidance was wrong for this dashboard. Prior matching ConfigMap did not prove that target installs it. This is an instruction/prerequisite failure, not new evidence that the corrective dashboard code failed live. Do not ask the operator to repeat platform-ops or mutate secrets to fix this.

This section supersedes earlier make platform-ops instructions for Agent Dispatch. Correct next single operator command from repo root:

```bash
kubectl --context k3d-k3d-cluster -n monitoring apply -f scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml
```

Applies only the reviewed dashboard ConfigMap. Inspect result, then independently compare deployed JSON before UI check. No coordinator apply/Secret read or mutation/restart performed. No code change or test rerun; prior offline138Python/28BATS/Ruff/PromQL remains. No deployment automation expansion silently added; canonical bug stays pending actual corrected-dashboard deployment/UI verification.
