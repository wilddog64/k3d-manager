# Role gate verification environment

The initial focused BATS run encountered a sandbox loopback restriction:

```text
not ok 72 acg-up Vault port cleanup kills the listener but not a connected client such as an ssh -R tunnel
# (from function `_start_vault_port_fixture' in file scripts/tests/bin/cluster_up.bats, line 1108,
#  in test file scripts/tests/bin/cluster_up.bats, line 1123)
#   `_start_vault_port_fixture' failed
# Traceback (most recent call last):
#   File "<string>", line 2, in <module>
#     s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",0)); s.listen(4)
#                                                                               ~~~~~~^^^^^^^^^^^^^^^^^
# PermissionError: [Errno 1] Operation not permitted
# cat: /tmp/bats-run-RQTg81/test/72/port: No such file or directory
```

The test needs loopback socket access. Rerun the focused suites with that access. Live E2 and E3 require the operator's M4 and M5 respectively and were not attempted.

The initial ShellCheck command also reported an existing warning, subsequently corrected:

```text
In bin/k3dm-machine-setup line 65:
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
                      ^----^ SC2088 (warning): Tilde does not expand in quotes. Use $HOME.
```

The rerun with loopback access passed all 157 cases; the complete TAP output is at `/private/tmp/k3dm-role-gates-final` for this session.

## Landing fast gate, first attempt

```text
fast-gate: 9 more tests name touched files — run make test
PASS scripts/tests/bin/cluster_up.bats 4s
PASS scripts/tests/bin/machine_setup.bats 117s
PASS scripts/tests/bin/require_role.bats 5s
PASS scripts/tests/lib/bats_negation_lint.bats 1s
PASS scripts/tests/lib/ci_workflow_no_stage2.bats 0s
PASS scripts/tests/lib/grep_q_pipe_guard.bats 0s
PASS scripts/tests/bin/agy_wrapper.bats 1s
PASS scripts/tests/bin/cloudflared_secret_argv.bats 1s
PASS scripts/tests/bin/cluster_down.bats 8s
PASS scripts/tests/bin/cluster_status_summary.bats 2s
PASS scripts/tests/bin/hub_new.bats 27s
PASS scripts/tests/bin/hub_restore.bats 5s
FAIL scripts/tests/bin/hub_up.bats 2s
1..12
ok 1 hub-up harness proves all cluster tools resolve to stubs
ok 2 hub-up creates a missing hub and deploys bootstrap components in order
ok 3 hub-up skips creation for an existing hub and never changes context
ok 4 hub-up stops when Vault deployment fails
ok 5 hub-up refuses deployment when the current context is not the hub
not ok 6 Makefile routes k3d and preserves k3s-aws routing
# (in test file scripts/tests/bin/hub_up.bats, line 117)
#   `[[ "$output" == *"k3d) bin/hub-up"* ]]' failed
ok 7 hub-up target is phony, documented, and forwards to k3d up
ok 8 hub-up: DR drill mode stops before ArgoCD
ok 9 hub-up: DR namespaces exist before egress policy and workloads
ok 10 hub-up: DR mode lets drill pods reach only the drill API server
ok 11 hub-up: DR mode stops when the API server endpoint is unreadable
ok 12 DR egress policy allows only DNS and the two drill namespaces
PASS scripts/tests/bin/k3dm_worker_setup.bats 1s
PASS scripts/tests/bin/launchd_plist_path.bats 0s
PASS scripts/tests/bin/machine_secrets.bats 25s
PASS scripts/tests/bin/machine_setup_acceptance.bats 111s
PASS scripts/tests/bin/makefile_acg_watch.bats 0s
FAIL scripts/tests/bin/makefile_appsets.bats 1s
1..4
not ok 1 appsets-reapply validates and passes the release branch
# (in test file scripts/tests/bin/makefile_appsets.bats, line 28)
#   `[ "${status}" -eq 0 ]' failed
not ok 2 appsets-reapply refuses non-release branches
# (in test file scripts/tests/bin/makefile_appsets.bats, line 37)
#   `[[ "${output}" == *"not a release branch"* ]]' failed
ok 3 appsets-check passes the branch and infra context
ok 4 appsets targets are phony and listed in help
PASS scripts/tests/bin/makefile_argocd_hermes_token.bats 0s
PASS scripts/tests/bin/makefile_default_url.bats 1s
PASS scripts/tests/bin/makefile_e2e_recorded.bats 0s
PASS scripts/tests/bin/makefile_gh_secret.bats 1s
PASS scripts/tests/bin/makefile_hermes_approvals.bats 0s
PASS scripts/tests/bin/makefile_hub_port_forward.bats 1s
PASS scripts/tests/bin/makefile_keychain_read.bats 0s
PASS scripts/tests/bin/makefile_platform_ops.bats 0s
PASS scripts/tests/bin/makefile_show_service_passwords.bats 2s
PASS scripts/tests/bin/makefile_signing_restore.bats 0s
FAIL scripts/tests/bin/makefile_webhook_slack.bats 1s
1..12
ok 1 update-webhook-slack reads the bot token from Keychain
ok 2 update-webhook-slack no longer passes the token to PlistBuddy argv
ok 3 update-webhook-slack hands the token to python via env
ok 4 update-webhook-slack recipe commands are all @-silenced
ok 5 update-webhook-slack backs up the plist before writing
ok 6 make -n update-webhook-slack does not expand an exported token
not ok 7 update-webhook-slack writes exported status channel and preserves it when unset
# (in test file scripts/tests/bin/makefile_webhook_slack.bats, line 61)
#   `[ "${status}" -eq 0 ]' failed
not ok 8 update-webhook-slack does not add absent status channel when unset
# (in test file scripts/tests/bin/makefile_webhook_slack.bats, line 74)
#   `[ "${status}" -eq 0 ]' failed
ok 9 update-webhook-slack-secret no longer passes the secret to PlistBuddy argv
ok 10 update-webhook-slack-secret recipe commands are all @-silenced
ok 11 update-webhook-slack-secret fails closed when the Keychain item is missing
not ok 12 update-webhook-slack-secret writes the secret via env without printing it
# (in test file scripts/tests/bin/makefile_webhook_slack.bats, line 126)
#   `[ "${status}" -eq 0 ]' failed
PASS scripts/tests/bin/prometheus_port_split.bats 0s
FAIL scripts/tests/bin/restart_webhook.bats 0s
not ok 1 restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook
# (in test file scripts/tests/bin/restart_webhook.bats, line 44)
#   `[ "${status}" -eq 0 ]' failed
not ok 2 restart-webhook continues to bootstrap when bootout reports the job is not loaded
# (in test file scripts/tests/bin/restart_webhook.bats, line 57)
#   `[ "${status}" -eq 0 ]' failed
not ok 3 restart-webhook still restarts the cloud bridge
# (in test file scripts/tests/bin/restart_webhook.bats, line 65)
#   `[ "${status}" -eq 0 ]' failed
not ok 4 restart-webhook retries bootstrap twice then reports success
# (in test file scripts/tests/bin/restart_webhook.bats, line 73)
#   `[ "${status}" -eq 0 ]' failed
not ok 5 restart-webhook preserves bootstrap errors without suggesting root for a user agent
# (in test file scripts/tests/bin/restart_webhook.bats, line 82)
#   `[ "${status}" -eq 0 ]' failed
not ok 6 restart-webhook fails after five bootstrap attempts and skips cloud bridge
# (in test file scripts/tests/bin/restart_webhook.bats, line 94)
#   `[ "$(grep -c '^bootstrap ' "${STUB_CALLS}")" -eq 5 ]' failed with status 2
# grep: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.14/2026-11-01-acg-up-on-dev-node-restarts-retired-local-hub.run/state/tmp/bats-run-fit7oR/test/6/launchctl.calls: No such file or directory
# /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.14/2026-11-01-acg-up-on-dev-node-restarts-retired-local-hub/scripts/tests/bin/restart_webhook.bats: line 94: [: : integer expected
PASS scripts/tests/bin/sandbox_launchd_scope.bats 1s
PASS scripts/tests/bin/sandbox_prometheus_port_forward.bats 1s
PASS scripts/tests/bin/test_ask_docs.py 1s
PASS scripts/tests/bin/test_cloud_bridge.py 3s
PASS scripts/tests/bin/test_find_similar_docs_make_target.py 0s
PASS scripts/tests/bin/test_restart_cloud_bridge.py 1s
PASS scripts/tests/bin/test_smoke_logins.py 20s
PASS scripts/tests/bin/test_test_tripwire.py 2s
PASS scripts/tests/bin/test_webhook_thread_dispatch.py 1s
PASS scripts/tests/bin/test_webhook_untrusted_input.py 0s
PASS scripts/tests/lib/ensure_kubeconform.bats 1s
PASS scripts/tests/lib/hostinger_pushgateway_port_forward.bats 0s
PASS scripts/tests/lib/k3s_aws_provider.bats 6s
PASS scripts/tests/lib/observability.bats 3s
PASS doc-links (4 files) 0s
SLOWEST scripts/tests/bin/machine_setup.bats 117s
TOTAL 125s

```

The new guard required scratch hub-role fixtures in the existing Makefile suites. Those fixtures were updated and their 34 cases passed. Rerun the landing gate.
