# Related k3s-aws provider contract suite failures

During offline verification of the k3s-aws SSH target fix, the related provider
contract suite reported two teardown/deregistration failures. The suite is
outside the changed implementation path; no provider code was changed to address
them.

Command: `bats scripts/tests/lib/k3s_aws_provider.bats`

Actual output:

```text
1..30
ok 1 _provider_k3s_aws_deploy_cluster --help prints k3s-aws usage
ok 2 _provider_k3s_aws_destroy_cluster --help prints k3s-aws usage
ok 3 _provider_k3s_aws_destroy_cluster without --confirm fails
ok 4 k3s-aws fallback watcher logs away from the terminal
ok 5 k3s-aws skips the fallback watcher when launchd is loaded
ok 6 k3s-aws preserves the already-running watcher branch
ok 7 N1: launchd retires a stale cluster-up watcher
ok 8 k3s-aws removes a dead launchd watcher PID
ok 9 k3s-aws does not kill an unrelated launchd PID
ok 10 cluster-up stops the shell watcher only after launchd succeeds
ok 11 _provider_k3s_aws_deploy_cluster runs acg_provision once
ok 12 k3s-aws marks a newly created stack with its name and region
ok 13 k3s-aws does not mark a healthy reused stack
ok 14 k3s-aws dry-run does not write stack ownership
ok 15 k3s-aws retries app provisioning over SSH after SSM bootstrap fails
ok 16 k3s-aws uses SSH when the laptop Vault reverse bridge is required
ok 17 k3s-aws overrides explicit SSM when the laptop Vault reverse bridge is required
ok 18 k3s-aws fails when SSM bootstrap and SSH retry both fail
ok 19 k3s-aws derives four agent hosts and five total nodes from ACG_AGENT_COUNT
ok 20 k3s-aws preserves two-agent default and three-node total
ok 21 k3s-aws rejects a malformed ACG_AGENT_COUNT before provisioning
not ok 22 _provider_k3s_aws_destroy_cluster --confirm runs acg_teardown
# (in test file scripts/tests/lib/k3s_aws_provider.bats, line 484)
#   `[ "$(printf "%s\n" "$output" | grep -n "\[stub\] deregister" | cut -d: -f1)" -lt \' failed
ok 23 _k3s_aws_deregister_cluster DRY_RUN describes the hub cleanup
ok 24 _k3s_aws_deregister_cluster deletes only ubuntu-k3s hub objects
not ok 25 _k3s_aws_deregister_cluster is idempotent when hub objects are absent
# (in test file scripts/tests/lib/k3s_aws_provider.bats, line 539)
#   `[ "$status" -eq 0 ]' failed
ok 26 k3s-aws keeps SSM when registration and tunnel succeed
ok 27 k3s-aws falls back to SSH when SSM registration fails
ok 28 k3s-aws fails when both SSM and SSH tunnels fail
ok 29 k3s-aws SSM registration timeout returns instead of exiting the shell
ok 30 k3s-aws falls back to SSH when the real SSM registration wait times out
```

Root cause is not established. Follow up by inspecting the two failing teardown
fixtures and their command output independently of the SSH target fix.
