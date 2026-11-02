# Dispatch review: pending verification

2026-11-01: reviewed the three v1.43.14 worker worktrees. No task was landed during this review.

## Results

- Role gate: `bats scripts/tests/bin/cluster_up.bats scripts/tests/bin/machine_setup.bats scripts/tests/bin/require_role.bats` completed with `1..157` and all 157 cases `ok`. `shellcheck -x -S warning bin/cluster-up bin/k3dm-machine-setup bin/k3dm-require-role` exited 0 without output.
- Resume reason: dispatcher suite completed with `1..94` and all 94 cases `ok`; `pytest -q scripts/tests/bin/test_dispatch_metrics.py` produced `169 passed in 5.83s`; dashboard suite completed `1..38` with all cases `ok`. Fixed `make codex-resume` and its how-to to supply the required reason; targeted wrapper test produced:

```text
1..1
ok 1 codex dispatch: make targets pass a declared coordinator
```

- Instruction refresh: `pytest -q scripts/tests/bin/test_check_agent_docs.py` produced:

```text
........                                                                 [100%]
8 passed in 0.20s
```

The worker reported broad gates did not finish green:

```text
$ make test-pytest
6 failed, 1753 passed, 4 skipped, 8 errors in 110.11s
[tripwire] FAIL: 4 blocked call(s) were not reads — stub them in the test.
make: *** [test-pytest] Error 1
```

Worker reported `make test` printed 1,979 cases with 37 failures and 21 skips, then was interrupted because a process held the wrapper open. Logs: `/private/tmp/k3dm-agent-refresh-bats.log` and `/private/tmp/k3dm-agent-refresh-pytest-final.log`. The worker attributed some failures to sandbox loopback and Docker restrictions; full independent triage remains. The worker could not determine which instruction file agy loads; `agy --help` did not resolve it.

## Follow-up

Review pre-fix negative controls, run staged `_agent_audit`, resolve broad-gate failures and agy loading, and review scope exceptions before landing. The role-gate spec calls for its ACG how-to and tests but dispatcher path matching flags them. The resume task needs its existing Makefile wrapper and how-to updated for the newly mandatory reason; those paths were not in its recorded file list. Operator live checks remain separate.

## Subsequent landing attempts

Role guard landed and pushed as `bd3002db`; 157 focused BATS cases and the dispatcher and pre-push fast gates passed. An initial fast gate failed on existing fixtures; the complete output and correction are in `docs/issues/2026-11-01-role-gate-verification-environment.md`. Its pre-fix and live verification remain pending.

Resume-reason task: focused BATS 94/94, pytest 169 passed, dashboard BATS 38/38. Its fast gate twice failed `hub_data.bats` and truncated the failing case. A parallel run captured the failure in case 12; an unrelated scratch tar reproduced it and isolating its TMPDIR made the case pass. The test-isolation commit `8614ebb4` and `docs/issues/2026-11-01-hub-data-shared-tmp-fast-gate.md` remain on the task branch. Landing was stopped pending explicit approval for those additional out-of-scope paths. No verification pass has been recorded. The first failed fast-gate output follows verbatim.

```text
PASS scripts/tests/bin/codex_dispatch.bats 206s
PASS scripts/tests/bin/test_dispatch_metrics.py 6s
SKIP scripts/tests/bin/test_dispatch_metrics.py promtool tests (promtool not installed): scripts/tests/bin/test_dispatch_metrics.py::test_by_model_promql_returns_one_series_per_model
PASS scripts/tests/lib/bats_negation_lint.bats 1s
PASS scripts/tests/lib/ci_workflow_no_stage2.bats 1s
PASS scripts/tests/lib/grep_q_pipe_guard.bats 0s
PASS scripts/tests/bin/agy_wrapper.bats 1s
PASS scripts/tests/bin/cloudflared_secret_argv.bats 1s
PASS scripts/tests/bin/cluster_down.bats 9s
PASS scripts/tests/bin/cluster_status_summary.bats 2s
PASS scripts/tests/bin/hub_new.bats 26s
PASS scripts/tests/bin/hub_restore.bats 5s
PASS scripts/tests/bin/hub_up.bats 1s
PASS scripts/tests/bin/k3dm_worker_setup.bats 1s
PASS scripts/tests/bin/launchd_plist_path.bats 0s
PASS scripts/tests/bin/machine_setup.bats 122s
PASS scripts/tests/bin/machine_setup_acceptance.bats 116s
PASS scripts/tests/bin/makefile_acg_watch.bats 1s
PASS scripts/tests/bin/makefile_appsets.bats 1s
PASS scripts/tests/bin/makefile_argocd_hermes_token.bats 0s
PASS scripts/tests/bin/makefile_default_url.bats 0s
PASS scripts/tests/bin/makefile_e2e_recorded.bats 1s
PASS scripts/tests/bin/makefile_gh_secret.bats 0s
PASS scripts/tests/bin/makefile_hermes_approvals.bats 1s
PASS scripts/tests/bin/makefile_hub_port_forward.bats 1s
PASS scripts/tests/bin/makefile_keychain_read.bats 0s
PASS scripts/tests/bin/makefile_platform_ops.bats 0s
PASS scripts/tests/bin/makefile_show_service_passwords.bats 1s
PASS scripts/tests/bin/makefile_signing_restore.bats 1s
PASS scripts/tests/bin/makefile_webhook_slack.bats 1s
PASS scripts/tests/bin/require_role.bats 5s
PASS scripts/tests/bin/restart_webhook.bats 0s
SKIP scripts/tests/bin/test_dashboard_queries.py 1s (no tests remain)
SKIP scripts/tests/bin/test_dashboard_queries.py promtool tests (promtool not installed): scripts/tests/bin/test_dashboard_queries.py::test_every_bug_dashboard_target_matches_producer_series
PASS scripts/tests/bin/test_dispatch_logs.py 12s
PASS scripts/tests/bin/test_find_similar_docs_make_target.py 1s
PASS scripts/tests/bin/test_restart_cloud_bridge.py 0s
PASS scripts/tests/bin/test_smoke_logins.py 21s
PASS scripts/tests/bin/test_test_tripwire.py 1s
PASS scripts/tests/bin/test_vectordb_bug_metrics.py 4s
PASS scripts/tests/lib/ensure_kubeconform.bats 1s
PASS scripts/tests/lib/observability.bats 4s
PASS scripts/tests/plugins/agent_dispatch_dashboard.bats 1s
PASS scripts/tests/plugins/e2e_remote.bats 7s
PASS scripts/tests/plugins/e2e_sandbox_preflight.bats 3s
FAIL scripts/tests/plugins/hub_data.bats 40s
ok 97 recover B4-R2: restore uses the recorded export and never clones
ok 98 recover B4-R3: verification passes context to kubectl
ok 99 recover B4-R3: a failed LDAP admin bind fails LDAP verification
ok 100 recover B4-R4: resume failure is logged and report records false
ok 101 recover B4-14: without a TTY approval is refused before the prompt
ok 102 recover B4-16: age identity is not sent in command argv
ok 103 recover B4-17a: ArgoCD read-back stops before destructive work
ok 104 recover B4-19: V8 records SecretSyncedError as false
ok 105 recover B4-21: drill unseal uses the moved hub function
ok 106 dr credential shim: stdin is recorded and forwarded byte-for-byte without -w value
ok 107 dr credential shim: argv -w is skipped and never written under the run directory
ok 108 dr credential shim: enforce exits 44 and does not reach real security
ok 109 dr credential scope: a drill may not touch the unseal-key cache or another context's root token
ok 110 dr credential scope: a hub restore may cache unseal keys; a drill rehearsal may not; root token only for the target context
ok 111 dr credential guard: hub_data_recover records in its own process, also on RESUME, and scopes by target
ok 112 dr restore: an out-of-cluster docker target is refused before exec
ok 113 recover F1: the preflight summary is on stderr so it shows before the approval; stdout is only RUN_ID
ok 114 recover F2: a resumed run pauses ArgoCD again and keeps the value recorded before the first pause
ok 115 recover F3: step 2 prompts on every run and hub mode never reads the age identity from the Keychain
ok 116 scheduled export: SSH guard runs first and a failed guard prevents export
PASS scripts/tests/plugins/hub_recovery.bats 15s
PASS doc-links (2 files) 0s
SLOWEST scripts/tests/bin/codex_dispatch.bats 206s
TOTAL 206s

```
