# Argo CD port-forward wrapper if-count audit mismatch

## What was tested

The Argo CD launchd wrapper helper in `scripts/plugins/argocd.sh` was refactored to render a template-backed watchdog script.

The shell function itself currently renders with a single `if` block when inspected directly:

```text
$ bash -lc 'export BATS_TEST_DIRNAME=/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/tests/plugins; source scripts/tests/test_helpers.bash; init_test_env; source scripts/plugins/argocd.sh; declare -f _argocd_write_port_forward_wrapper | grep -o "\<if\>" | wc -l'
1
```

But the agent audit still reports the helper as over budget:

```text
WARN: Agent audit: scripts/plugins/argocd.sh exceeds if-count threshold in: _argocd_write_port_forward_wrapper:11
```

## Root cause

The audit is over-counting the helper after the template-based refactor. The implementation is still a narrow wrapper renderer, but the audit tool is treating it as though it contains 11 `if` blocks.

## Recommended follow-up

- Keep the narrow allowlist entry for `scripts/plugins/argocd.sh:_argocd_write_port_forward_wrapper`.
- Revisit the audit counter separately if we want to remove the allowlist later.
- Keep the watchdog behavior in the external template file so the function stays compact.
