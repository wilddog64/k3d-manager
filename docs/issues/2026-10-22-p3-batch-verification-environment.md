# P3 batch verification: sandbox denials and gated skips

**Date:** 2026-10-22
**Branch:** `k3d-manager-v1.43.5`
**Tasks:** cluster-down Slack summary, E2E failure-table correlation, firing-alert timing, PR-check duration, read-only vulnerability-report command

## What was tested

Focused unit, pytest, and BATS suites were run independently in the five dispatcher worktrees and rerun by the dispatcher after rebase. All required suites passed after granting the isolated worktrees the normal test write/listener permissions. `_agent_lint`, `_agent_audit`, applicable ShellCheck, Make dry-run, and `git diff --check` passed.

## Initial sandbox-denied attempts (verbatim excerpts)

The cloud-bridge test initially could not create its temporary Git index inside the isolated task worktree:

```text
E               PermissionError: [Errno 1] Operation not permitted: '/Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/vuln-scan-report-command-name/cloud-index.n8a9iknt'
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_cloud_bridge.py::test_request_helper_fetches_an_unfetched_remote_tip_before_committing
1 failed, 83 passed, 2 warnings in 2.05s
```

The webhook BATS suite's first sandboxed attempt failed its local HTTP request setup; representative exact output:

```text
not ok 2 POST with wrong token returns 401
# (in test file scripts/tests/lib/webhook.bats, line 160)
#   `[ "$status" -eq 0 ]' failed
not ok 3 POST with no auth header returns 401
# (in test file scripts/tests/lib/webhook.bats, line 169)
#   `[ "$status" -eq 0 ]' failed
```

## Approved reruns and remaining skips (verbatim)

The approved temporary-file rerun passed:

```text
84 passed in 1.76s
```

The cluster webhook suite then passed 68 cases; its six live/cluster/tunnel checks remained environment-gated. The E2E dashboard suite passed 26 cases, with these Prometheus-rule checks skipped because `promtool` is absent:

```text
ok 21 e2e staleness is fresh if any runner passed recently # skip promtool not installed
ok 22 E2EResultsMissing fires only when the hub has no e2e results # skip promtool not installed
```

## Assessment and follow-up

The denied writes/listeners were sandbox limitations, not test failures in the changes; the permission-enabled reruns passed. No production service, AWS resource, Slack command, or vulnerability scan was exercised. Install `promtool` to execute the two skipped Prometheus rule validations. Live checks for each bug remain operator-owned and are not inferred from these offline tests.
