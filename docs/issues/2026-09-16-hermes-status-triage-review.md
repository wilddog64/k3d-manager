# Hermes scheduled status: interrupted implementation review and corrections

Date: 2026-09-16. Branch: `k3d-manager-v1.34.0`. Machine: `m4-air.local`.
Scope: finish the existing status-triage implementation and fix the issues found in
the user's requested review. Code validation passes; live acceptance remains pending.
No PR created (repository policy assigns PR creation to Claude).

Implementation landed as `e3e37f9671b9de4a14a87176e494de3a578642fa` on origin.

## Findings and fixes

1. **Unknown status generated a duplicate SMS page.** The new record passed straight
   into `pager.health_events`, whose generic unknown-sensor streak pages after six
   samples. The poll now excludes `status_checks` from that pager input. The existing
   webhook detector still receives its normal records. A seven-sample poll regression
   verifies no page, filing, or false recovery of an existing status group.
2. **Raw status messages leaked through JSON output.** Redacting triage groups was too
   late: the poll and forced status command print the sensor record itself. Sanitize
   strings recursively at the status JSON boundary, including nested metadata and
   keys, before building any record. Triage targets are redacted too. Tests use
   synthetic sentinels only; no live credential was read or disclosed.
3. **Status bug docs invented an E2E execution.** Shared filing used a template that
   hardcodes M2/vcluster and failed tests. Add an explicit `source: status` template,
   recurrence wording, and commit label while retaining E2E behavior and shared
   worktree/push logic. Status reports contain the sample timestamp, check ids, and
   counts. A temporary local Git remote test verifies the written report.
4. **Reminders reset at UTC midnight.** Use the host's local date. The regression
   crosses local midnight while UTC is already on the following date and asserts
   only one ongoing reminder and no duplicate bug filing.
5. **The ShellCheck gate targeted Python.** Replace it in the existing plan with
   Python compilation. No shell files were changed, so shell lint is not applicable.
6. **The documented activation prerequisite was not enforced.** The unfinished code
   enabled the schedule by default even though the Prometheus authenticated-probe
   dependency remains unverified. Default off; explicitly set
   `K3DM_HERMES_STATUS_ENABLED=1` after verification. Forced `status` remains available.

The existing plan's file table includes the shared bug renderer and its regression
test. No repair was added and no new auto-execution path was introduced.

## Original review evidence (verbatim)

```text
pytest scripts/tests/hermes/ -q
101 passed in 2.24s

Unknown sensor after six scheduled samples: ['Hermes: status_checks check unknown 30+ min: cluster status source unavailable']
Raw sensor output retains synthetic secret: True

In bin/k3dm-hermes line 1:
#!/usr/bin/env python3
^-- SC1071 (error): ShellCheck only supports sh/bash/dash/ksh/'busybox sh' scripts. Sorry!

For more information:
  https://www.shellcheck.net/wiki/SC1071 -- ShellCheck only supports sh/bash/...
```

## Validation after corrections

```text
$ python3 -m py_compile bin/k3dm-hermes scripts/lib/hermes/sensors.py scripts/lib/hermes/status_triage.py scripts/lib/hermes/e2e_bugs.py
```

No output; exit 0.

```text
$ pytest scripts/tests/hermes/ -q
........................................................................ [ 67%]
..................................                                       [100%]
106 passed in 2.90s

$ bats scripts/tests/bin/cluster_status_summary.bats
1..8
ok 1 summary reports failed services before healthy checks
ok 2 focused service mode excludes unrelated services
ok 3 json mode contains structured statuses and no ANSI
ok 4 unknown service returns usage error
ok 5 json mode follows the active provider when no provider is explicit
ok 6 hostinger edge-down 530s suggest refresh-edge
ok 7 single hostinger 530 does not suggest refresh-edge
ok 8 non-hostinger provider does not suggest refresh-edge for multiple 530s
```

`git diff --check`: no output, exit 0.

## Full-suite limitation and follow-up

Attempted the required `./scripts/k3d-manager test all`. It stalled at the third,
unrelated deployment test, not in Hermes. Complete emitted test output before stopping:

```text
running under bash version 5.3.20(1)-release
1..919
ok 1 deploy_app_cluster --help passes through the guard
ok 2 deploy_app_cluster without --confirm is blocked by the guard safety gate
not ok 3 deploy_app_cluster --confirm reaches the confirmed path (Finding 2b)
# (in test file scripts/tests/core/deploy_app_cluster_confirm.bats, line 34)
#   `@test "deploy_app_cluster --confirm reaches the confirmed path (Finding 2b)" {' failed
# bats warning: Executed 3 instead of expected 919 tests
```

The active test was `deploy_app_cluster --confirm reaches the confirmed path (Finding 2b)`
in `scripts/tests/core/deploy_app_cluster_confirm.bats`. Process inspection:

```text
  PID  PPID ELAPSED ARGS
99498 99459   01:44 kubectl get nodes --no-headers
```

Stopped the identified test process tree with TERM (exit 143); test 3's failure above
was emitted on termination. The fixture stubs `k3sup` but
allows a real `kubectl` invocation despite `KUBECONFIG=/dev/null`. Why the dispatcher
reaches this cluster check before rejecting the nonexistent SSH key needs a separate
investigation. Do not claim the 919-test suite passed; make this fixture hermetic and
rerun it in a separate task. No deployment code was changed here.

Live checks were deliberately not run: the plan specifies stub-only implementation
validation and separately blocks live activation on the Prometheus probe-authentication
fix. Verify that dependency, then test a healthy forced status sample and one enabled
scheduled cycle before treating this monitor as live-accepted.

## Repository gates

Staged-change gates (verbatim):

```text
_agent_audit exit=0
_agent_lint exit=0 (AI gate disabled by default)
```

The AI lint gate is disabled in the existing configuration; this is not an AI review.
No `.sh` files were touched, so the audit's shell if-count scan has no new shell
functions to inspect; the threshold remains 8.

The original plan requested rebasing a shared branch, contrary to repository rule 8;
the plan now requires fetching and merging if needed. Fetch showed HEAD and origin
aligned before committing.

`_agent_checkpoint` stages everything with `git add -A` and creates a commit. That
conflicts with this plan's explicit prohibition on `git add -A` in the inherited dirty
worktree. Use explicit path staging and normal hooked commits; run the checkpoint
helper once the worktree is clean, when it safely skips. No hook is bypassed.

Post-commit checkpoint and first push attempt (verbatim):

```text
INFO: Working tree clean; checkpoint skipped
ssh: Could not resolve hostname github.com: -65563
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
```

The sandbox restricted network access. Retried with the required escalation; push succeeded:

```text
To github.com:wilddog64/k3d-manager.git
   dadacf31..e3e37f96  k3d-manager-v1.34.0 -> k3d-manager-v1.34.0
```
