# Jenkins crumbIssuer XML XPath blocked after 2.541.2

**Date:** 2026-02-27
**Status:** FIXED

## Summary

After upgrading Jenkins to 2.541.2, the `crumbIssuer` endpoint rejects primitive XPath queries unless the requester implements `jenkins.security.SecureRequester`. Our automation (`bin/create-k8s-agent-test-jobs.sh`, `bin/run-k8s-agent-tests.sh`) still used the old pattern:

```
curl -s -u jenkins-admin:*** \
  "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,":",//crumb)"
```

The new controller responds with HTTP 403 and the message
`primitive XPath result sets forbidden; implement jenkins.security.SecureRequester`,
so the scripts never obtained a crumb. Job creation/triggering silently failed when running
`deploy_jenkins` validation.

## Impact

- `bin/create-k8s-agent-test-jobs.sh` could not seed the linux/kaniko jobs anymore.
- `bin/run-k8s-agent-tests.sh` bailed out before triggering builds, blocking the agent verification checklist.
- Users attempting to run the documented `curl` manually see the same 403.

## Fix

- Switch both scripts (and their derivatives) to call `/crumbIssuer/api/json` and parse the
  crumb via `python3`.
- Store the session cookie from the crumb request (`-c $COOKIE_JAR`) and reuse it on subsequent
  POSTs (`-b $COOKIE_JAR`). Jenkins ties a crumb to the HTTP session, so we must send both.
- Added defensive parsing to keep the scripts functional even if the crumb endpoint is unavailable
  (they now print a warning and exit instead of continuing blindly).

## Evidence

```
$ PATH="/opt/homebrew/bin:$PATH" JENKINS_URL="http://127.0.0.1:8083" ./bin/run-k8s-agent-tests.sh
=== Triggering Jenkins K8s Agent Tests ===

Getting Jenkins crumb...
Got crumb: Jenkins-Crumb

Triggering job: 01-linux-agent-test
  ✓ Job '01-linux-agent-test' triggered successfully

Triggering job: 02-kaniko-agent-test
  ✓ Job '02-kaniko-agent-test' triggered successfully
```

Jobs now spin up pods and finish cleanly (see linux/kaniko console excerpts in memory-bank update).

## Follow-up

Audit any other helper scripts that shell out to `crumbIssuer/api/xml?...xpath` and move them to JSON.
Currently tracked call sites: `bin/smoke-test-jenkins.sh` (best-effort, still works, but should be updated
for consistency).
