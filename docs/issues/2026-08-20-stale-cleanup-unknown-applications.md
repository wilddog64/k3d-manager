# Stale cleanup left generated ArgoCD Applications `Unknown`

## What was tested

Ran the focused cleanup and lifecycle suites before and after the fix:

```text
1..5
ok 1 cleanup-stale-clusters dry-run only reports expired k3s-aws registrations
ok 2 cleanup-stale-clusters confirm deletes managed apps and secret
ok 3 make help advertises guarded stale cleanup
ok 4 make down gates stale cleanup behind CLEANUP_STALE
ok 5 cleanup-stale-resources dispatches both paths for AWS
```

Ran the repository webhook suite as a separate baseline check:

```text
1..54
not ok 1 POST with wrong token returns 401
not ok 2 POST with no auth header returns 401
not ok 3 POST with correct token returns 202 and job_id
not ok 4 POST body over 4KB returns 413
not ok 5 GET /status with invalid job_id (not hex8) returns 400
not ok 6 GET /status with invalid job_id containing special chars returns 400
not ok 7 GET /status with valid hex8 job_id that does not exist returns 404
not ok 8 GET unknown path returns 404
not ok 9 POST with missing stage field returns 400
not ok 10 POST with invalid stage value returns 400
not ok 11 POST with JSON-injection attempt in chart_version queues job safely
not ok 12 POST /cluster with provider=gcp returns 202 and job_id
not ok 13 POST /cluster with unknown provider defaults to aws (202)
not ok 14 POST /cluster-status with correct token returns 202 and job_id
not ok 15 POST /cve-remediate requires auth, creates one job, and cooldown-skips repeat
ok 16 webhook hostinger status handler accepts provider dispatch
ok 17 Slack signature verification rejects malformed timestamps and bodies
not ok 18 Slack ignores signed unknown and user-less commands without creating anchors
not ok 19 Slack allowlisted reader can dispatch cluster-status
ok 20 Slack cluster parser accepts tokens in any order and dry-run isolates execution
ok 21 hostinger status keeps report header and final health sections when long
not ok 22 POST /cluster-status with wrong token returns 401
not ok 23 POST /cluster-status with reader role returns 202
not ok 24 POST /diagnostics with reader role returns 202
not ok 25 POST /diagnostics rejects non-approved namespaces
not ok 26 POST /diagnostics ArgoCD requests must target hub
not ok 27 POST /cluster-refresh with reader role returns 403
not ok 28 POST /cluster-refresh with operator role returns 202
not ok 29 POST /cluster up with operator role returns 403
ok 30 webhook remote operator access defines policy and audit log
ok 31 webhook diagnostics endpoint is reader-scoped and namespace-guarded
ok 32 webhook analysis defaults to agy CLI instead of gemini
ok 33 webhook cluster status classifies absent ACG sandboxes explicitly
ok 34 webhook ask subprocess captures transcripts in the k3d-manager run dir
ok 35 webhook ask subprocess ensures the run dir exists before capturing
not ok 36 POST /analyze with correct token returns 202 and job_id
not ok 37 POST /analyze with wrong token returns 401
not ok 38 POST /cluster with response_url stored in job dir
not ok 39 POST /cluster with wrong token returns 401
not ok 40 POST /cluster with action=up returns 202 and job_id
not ok 41 POST /cluster with action=down returns 202 and job_id
not ok 42 POST /cluster with invalid action returns 400
not ok 43 POST /cluster with missing action returns 400
ok 44 Level 1: POST queues job and GET /status returns job output # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 45 Level 1: GET /status output field is non-empty after job completes # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 46 Level 2: POST current chart version returns success without running make up # skip set K3DM_WEBHOOK_LEVEL2=1 to enable (requires cluster)
ok 47 Level 3: tunnel rejects wrong token with 401 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 48 Level 3: tunnel unknown path returns 404 (auth passes, routing fails) # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 49 Level 3: tunnel POST with real token queues job and returns 202 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 50 k3dm-ask-bash denies general-purpose interpreters
ok 51 k3dm-ask-bash denies output redirection
ok 52 k3dm-ask-bash denies nested shells and command maskers
ok 53 k3dm-ask-bash allows a plain kubectl read
ok 54 webhook role helpers preserve token admin and fail closed
```

## Root cause

`bin/cleanup-stale-clusters` filtered generated Applications on the
`k3d-manager/managed=true` label. The current ApplicationSet templates put that label on
ApplicationSets, not on most generated Applications, so the stale registration Secret could be
removed while its generated Applications remained and reported `Unknown`.

## Fix

For an already eligible expired and unreachable managed `k3s-aws` registration, cleanup now matches
Applications by cluster destination name, the registration's `k3d-manager/cluster` label, or the
registration Secret's API server destination. The registration provider, expiry, grace period, and
retain checks remain unchanged.

## Follow-up

The webhook failures above are unrelated to this change and indicate the local webhook test service
was unavailable or returned unexpected connection/status results. Re-run that suite with its
required test service before treating it as a code regression.
