# Webhook BATS verification required loopback access

**Date:** 2026-10-22
**Task:** `cluster-lifecycle-thread-recurrence-fix`
**Scope:** Verification environment only; no application code changes beyond the separately landed fix.

The first independent invocation of `bats scripts/tests/lib/webhook.bats` ran in the default sandbox, where the suite's local HTTP server was unreachable. Representative raw output:

```text
1..68
ok 1 the harness neutralizes the Pushgateway so tests cannot write live metrics
not ok 2 POST with wrong token returns 401
# (in test file scripts/tests/lib/webhook.bats, line 160)
#   `[ "$status" -eq 0 ]' failed
not ok 3 POST with no auth header returns 401
# (in test file scripts/tests/lib/webhook.bats, line 169)
#   `[ "$status" -eq 0 ]' failed
not ok 4 POST with correct token returns 202 and job_id
# (in test file scripts/tests/lib/webhook.bats, line 179)
#   `[ "$status" -eq 0 ]' failed
```

Reran the same suite with approved loopback access. The rerun completed all 68 cases successfully; six live/tunnel/cluster-dependent cases were expected skips. Representative raw output:

```text
1..68
ok 1 the harness neutralizes the Pushgateway so tests cannot write live metrics
ok 2 POST with wrong token returns 401
ok 3 POST with no auth header returns 401
ok 4 POST with correct token returns 202 and job_id
ok 5 POST body over 4KB returns 413
ok 6 GET /status with invalid job_id (not hex8) returns 400
ok 7 GET /status with invalid job_id containing special chars returns 400
ok 8 GET /status with valid hex8 job_id that does not exist returns 404
ok 9 GET unknown path returns 404
ok 10 POST with missing stage field returns 400
ok 11 POST with invalid stage value returns 400
ok 12 POST with JSON-injection attempt in chart_version queues job safely
ok 13 POST /cluster with provider=gcp returns 202 and job_id
ok 14 POST /cluster with unknown provider defaults to aws (202)
ok 15 POST /cluster-status with correct token returns 202 and job_id
ok 16 POST /cve-remediate requires auth, creates one job, and cooldown-skips repeat
ok 17 webhook hostinger status handler accepts provider dispatch
ok 18 Slack signature verification rejects malformed timestamps and bodies
ok 19 status smoke Keycloak admin login uses the operator keycloak-secrets account
ok 20 Slack ignores signed unknown and user-less commands without creating anchors
ok 21 Slack event larger than 4 KB is verified on the full body
ok 22 Slack event over the Slack cap returns 413
ok 23 Slack reports an authorization failure in the originating command thread
ok 24 Slack allowlisted reader can dispatch cluster-status
ok 25 Slack cluster parser accepts tokens in any order and dry-run isolates execution
ok 26 hostinger status keeps report header and final health sections when long
ok 27 POST /cluster-status with wrong token returns 401
ok 28 POST /cluster-status with reader role returns 202
ok 29 POST /diagnostics with reader role returns 202
ok 30 POST /diagnostics rejects non-approved namespaces
ok 31 POST /diagnostics ArgoCD requests must target hub
ok 32 POST /cluster-refresh with reader role returns 403
ok 33 POST /cluster-refresh with operator role returns 202
ok 34 POST /cluster up with operator role returns 403
ok 35 webhook remote operator access defines policy and audit log
ok 36 webhook diagnostics endpoint is reader-scoped and namespace-guarded
ok 37 webhook analysis uses ordered candidates and a safe sentinel
ok 38 webhook cluster status classifies absent ACG sandboxes explicitly
ok 39 webhook ask subprocess captures transcripts in the k3d-manager run dir
ok 40 webhook ask subprocess ensures the run dir exists before capturing
ok 41 POST /analyze with correct token returns 202 and job_id
ok 42 POST /analyze with wrong token returns 401
ok 43 POST /cluster with response_url stored in job dir
ok 44 POST /cluster with wrong token returns 401
ok 45 POST /cluster with action=up returns 202 and job_id
ok 46 POST /cluster with action=down returns 202 and job_id
ok 47 POST /cluster with invalid action returns 400
ok 48 POST /cluster with missing action returns 400
ok 49 Level 1: POST queues job and GET /status returns job output # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 50 Level 1: GET /status output field is non-empty after job completes # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 51 Level 2: POST current chart version returns success without running make up # skip set K3DM_WEBHOOK_LEVEL2=1 (requires cluster)
ok 52 Level 3: tunnel rejects wrong token with 401 # skip set K3DM_WEBHOOK_LEVEL3=1 (requires tunnel)
ok 53 Level 3: tunnel unknown path returns 404 (auth passes, routing fails) # skip set K3DM_WEBHOOK_LEVEL3=1 (requires tunnel)
ok 54 Level 3: tunnel POST with real token queues job and returns 202 # skip set K3DM_WEBHOOK_LEVEL3=1 (requires tunnel)
ok 55 k3dm-ask-bash denies general-purpose interpreters
ok 56 k3dm-ask-bash denies output redirection
ok 57 k3dm-ask-bash denies nested shells and command maskers
ok 58 k3dm-ask-bash allows a plain kubectl read
ok 59 k3dm-ask-bash denies outbound network clients
ok 60 k3dm-ask-bash denies git network subcommands
ok 61 k3dm-ask-bash allows local read-only git inspection
ok 62 k3dm-ask-bash denies credential-dir reads
ok 63 k3dm-ask-bash denies editors and find -exec
ok 64 k3dm-ask-bash denies awk system
ok 65 k3dm-ask-bash denies make in read-only mode
ok 66 webhook role helpers preserve token admin and fail closed
ok 67 webhook fix mode requires operator+ role, not question phrasing
ok 68 webhook _slack_post only targets https Slack hosts
```

This was an environment restriction, not a product-test failure. No live Slack, AWS, Kubernetes, or lifecycle checks were performed.
