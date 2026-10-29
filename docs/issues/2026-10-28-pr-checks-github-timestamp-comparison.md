# PR Checks operator screenshot and GitHub comparison — 2026-10-28

Operator screenshot is Repo=All, Last24hours (not payment-only/7days). Current Open PRs5, Failing0, Running0, Last scrape7.25mins, GitHub readok. Current table shows product-catalog62, basket56, order103/104/105. Updated Historical sampled check durations (may include closed PRs) title visible; chart includes payment93/94 absent from current table. This passes updated presentation/All view only. No screenshot export.

Read-only gh api metadata:
```json
{"closed_at":"2026-10-27T14:29:20Z","head_sha":"6267118f6c62cd6ec043a7a1278492270f5b5035","merged":true,"number":93,"state":"closed"}
{"closed_at":"2026-10-27T14:38:33Z","head_sha":"a94a76c33ade11b0f88506b2c7267ec1b79a160b","merged":true,"number":94,"state":"closed"}
```

Actual read-only gh api check-runs outputs:


PR93:
```json
{"checks":[{"completed_at":"2026-10-27T14:24:26Z","conclusion":"skipped","name":"Build, Scan \u0026 Push","started_at":"2026-10-27T14:24:26Z","status":"completed"},{"completed_at":"2026-10-27T14:25:59Z","conclusion":"success","name":"Integration Tests","started_at":"2026-10-27T14:24:28Z","status":"completed"},{"completed_at":"2026-10-27T14:24:47Z","conclusion":"success","name":"Security Scan","started_at":"2026-10-27T14:24:29Z","status":"completed"},{"completed_at":"2026-10-27T14:29:04Z","conclusion":"success","name":"Image Build Check","started_at":"2026-10-27T14:24:28Z","status":"completed"},{"completed_at":"2026-10-27T14:24:25Z","conclusion":"success","name":"Build and Test","started_at":"2026-10-27T14:22:53Z","status":"completed"},{"completed_at":"2026-10-27T14:22:45Z","conclusion":"success","name":"GitGuardian Security Checks","started_at":"2026-10-27T14:22:31Z","status":"completed"},{"completed_at":"2026-10-27T14:22:34Z","conclusion":"success","name":"automerge","started_at":"2026-10-27T14:22:30Z","status":"completed"},{"completed_at":"2026-10-27T14:22:51Z","conclusion":"success","name":"Checkstyle \u0026 SpotBugs","started_at":"2026-10-27T14:22:30Z","status":"completed"},{"completed_at":"2026-10-27T14:24:21Z","conclusion":"success","name":"Validate PR","started_at":"2026-10-27T14:22:29Z","status":"completed"},{"completed_at":"2026-10-27T14:22:59Z","conclusion":"success","name":"Code Quality","started_at":"2026-10-27T14:22:29Z","status":"completed"},{"completed_at":"2026-10-27T14:22:34Z","conclusion":"success","name":"API Compatibility","started_at":"2026-10-27T14:22:29Z","status":"completed"}]}
```


PR94:
```json
{"checks":[{"completed_at":"2026-10-27T14:33:28Z","conclusion":"skipped","name":"Build, Scan \u0026 Push","started_at":"2026-10-27T14:33:29Z","status":"completed"},{"completed_at":"2026-10-27T14:37:35Z","conclusion":"success","name":"Image Build Check","started_at":"2026-10-27T14:33:30Z","status":"completed"},{"completed_at":"2026-10-27T14:35:14Z","conclusion":"success","name":"Integration Tests","started_at":"2026-10-27T14:33:30Z","status":"completed"},{"completed_at":"2026-10-27T14:33:57Z","conclusion":"success","name":"Security Scan","started_at":"2026-10-27T14:33:31Z","status":"completed"},{"completed_at":"2026-10-27T14:33:28Z","conclusion":"success","name":"Build and Test","started_at":"2026-10-27T14:31:51Z","status":"completed"},{"completed_at":"2026-10-27T14:31:48Z","conclusion":"success","name":"Checkstyle \u0026 SpotBugs","started_at":"2026-10-27T14:31:25Z","status":"completed"},{"completed_at":"2026-10-27T14:31:28Z","conclusion":"success","name":"automerge","started_at":"2026-10-27T14:31:24Z","status":"completed"},{"completed_at":"2026-10-27T14:31:44Z","conclusion":"success","name":"Code Quality","started_at":"2026-10-27T14:31:24Z","status":"completed"},{"completed_at":"2026-10-27T14:33:13Z","conclusion":"success","name":"Validate PR","started_at":"2026-10-27T14:31:25Z","status":"completed"},{"completed_at":"2026-10-27T14:31:31Z","conclusion":"success","name":"API Compatibility","started_at":"2026-10-27T14:31:25Z","status":"completed"},{"completed_at":"2026-10-27T14:31:23Z","conclusion":"success","name":"GitGuardian Security Checks","started_at":"2026-10-27T14:31:21Z","status":"completed"}]}
```


GitHub sources: https://github.com/wilddog64/shopping-cart-payment/pull/93 and https://github.com/wilddog64/shopping-cart-payment/pull/94. Check runs queried on their head SHAs. #93 Build and Test ran14:22:53–14:24:25UTC (92s); #94 ran14:31:51–14:33:28UTC (97s). Completed timestamps are actual GitHub execution metadata; chart x-axis remains repeated scrape time, not new runs. Closed/merged metadata supports those series being retained history. Exact plotted-value tooltip comparison, payment-only view and no-history repo still pending; do not mark LIVE-VERIFIED from All screenshot alone.


Unexpected source metadata: PR94 skipped Build, Scan & Push completed14:33:28Z, started14:33:29Z (negative1s interval). Not used for completed-success duration comparison. Outside current presentation-only scope; report for future collector normalization investigation, no code fix or query change made. No CI rerun, credentials, live mutation, screenshot export or implementation test rerun. Canonical PR bug stays VERIFIED.


## Operator repo filters and tooltip — 2026-10-29

The operator supplied [k3d-manager, last 24 hours](../assets/2026-10-29-pr-checks-no-history.png): zero open PRs, no historical chart data, GitHub read ok. They also supplied [payment, last 7 days](../assets/2026-10-29-pr-checks-payment-history.png): zero open PRs, retained PR #93/#94 historical series, GitHub read ok. The [isolated PR #93 Build and Test tooltip](../assets/2026-10-29-pr-checks-payment-tooltip.png) shows **1.53 mins**. GitHub's recorded 14:22:53–14:24:25 UTC interval is 92 seconds = 1.5333 minutes, matching after display rounding. Tooltip x-axis is a sample time; it is not asserted to be the GitHub completion time. Prior All view is recorded above.

Read-only deployment check:

```text
$ kubectl --context k3d-k3d-cluster -n cicd get application hub-grafana-dashboards -o jsonpath='{.status.sync.status}{" revisions="}{.status.sync.revisions}{" health="}{.status.health.status}{"\n"}'
Synced revisions=["858d6612979a2c0bfa473f610e7b6f383d72b84f","858d6612979a2c0bfa473f610e7b6f383d72b84f"] health=Healthy
$ git merge-base --is-ancestor 2b21e8af 858d6612 && printf 'revision contains fix\n'
revision contains fix
```

An initial lookup used the wrong namespace and returned `Error from server (NotFound): namespaces "argocd" not found`; listing applications identified `cicd`. A sandboxed retry also returned `Unable to connect to the server: dial tcp 127.0.0.1:55730: connect: operation not permitted`; the approved read-only retry produced the result above. The screenshots do not test a currently failed GitHub read; that case was covered offline. No dashboard, service, CI or metrics mutation was performed.
