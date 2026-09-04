# Manifest-authoring verification: unrelated curated test failures

## What was tested

The manifest-authoring change was checked with YAML parsing, embedded exporter Python
compilation, `bash -n`, `shellcheck`, `_agent_audit`, the focused Hostinger provider suite,
and `./scripts/k3d-manager test all`. No live cluster or Vault command was run.

Focused provider suite:

```
1..54
ok 17 _hostinger_reapply_gitops_applicationsets reapplies data, services, platform, istio-ambient, and CVE reader appsets from the current branch
```

The complete curated suite reached these failures, verbatim:

```
not ok 356 configure_vault_argocd_repos --dry-run makes no kubectl calls
# (in test file scripts/tests/plugins/argocd_deploy_keys.bats, line 98)
#   `[ ! -s "$KUBECTL_LOG_PATH" ]' failed
not ok 358 configure_vault_argocd_repos --dry-run --seed-vault prints actions only
# (in test file scripts/tests/plugins/argocd_deploy_keys.bats, line 117)
#   `[ ! -s "$KUBECTL_LOG_PATH" ]' failed
not ok 601 slack relay cluster-status acks before webhook completes
# (in test file scripts/tests/plugins/slack_relay_ack.bats, line 18)
#   `[ "${status}" -eq 0 ]' failed
not ok 607 slack relay allowlist includes cluster-status and hostinger-status
# (in test file scripts/tests/plugins/slack_slash_commands.bats, line 94)
#   `[ "${status}" -eq 0 ]' failed
not ok 684 vcluster_create: uses foundation-managed CLI path
# (in test file scripts/tests/plugins/vcluster.bats, line 45)
#   `[ "$status" -eq 0 ]' failed
not ok 685 _vcluster_check_prerequisites: stores the contract path
# (in test file scripts/tests/plugins/vcluster.bats, line 56)
#   `[ "$_VCLUSTER_BIN" = "$managed_path" ]' failed
not ok 688 vcluster_create: honors VCLUSTER_VALUES_FILE override
# (in test file scripts/tests/plugins/vcluster.bats, line 79)
#   `[ "$status" -eq 0 ]' failed
```

## Root cause / recommended follow-up

No root cause was established during this manifest-only task. The failures are in unrelated
ArgoCD dry-run, Slack relay, and vcluster suites; the changed Hostinger provider contract
test passed. Investigate those suites separately before treating the full curated suite as
green.
