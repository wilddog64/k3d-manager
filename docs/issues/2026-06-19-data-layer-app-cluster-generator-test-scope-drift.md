# Data-layer app-cluster generator test scope drift

## What was tested
- `bats scripts/tests/`
- `bats scripts/tests/plugins/argocd.bats scripts/tests/plugins/argocd_app_cluster_generator.bats`
- `shellcheck -S warning scripts/plugins/argocd.sh`
- `./scripts/k3d-manager _agent_audit`

## What happened
The first version of the static manifest guard used a broad grep for `name: ubuntu-k3s` across `scripts/etc/argocd/`.
That matched the `ubuntu-k3s` cluster references in `scripts/etc/argocd/projects/platform.yaml.tmpl`, which are
project-scoped cluster allowlists rather than a static Application destination.

Relevant output:
```text
1..18
ok 1 deploy_argocd --help shows usage
ok 2 deploy_argocd skips when CLUSTER_ROLE=app
ok 3 deploy_argocd_bootstrap --help shows usage
ok 4 deploy_argocd_bootstrap no-ops when skipping all resources
ok 5 _argocd_bootstrap_is_ready returns 0 when AppProject and ApplicationSets exist
ok 6 _argocd_bootstrap_is_ready returns 1 when an ApplicationSet is missing
ok 7 _argocd_ensure_logged_in uses plaintext non-interactive login
ok 8 _argocd_wait_for_local_port_forward returns 0 when healthz is reachable
ok 9 _argocd_wait_for_local_port_forward returns 1 when healthz never becomes reachable
ok 10 _argocd_write_port_forward_wrapper includes a self-healing loop
ok 11 _argocd_write_port_forward_wrapper falls back when the requested context is missing
ok 12 _argocd_write_browser_https_wrapper includes a canonical HTTPS listener
ok 13 _argocd_issue_browser_tls_material writes Vault-issued TLS files
ok 14 _argocd_deploy_appproject fails when template missing
ok 15 ARGOCD_NAMESPACE defaults to cicd
not ok 16 argocd app cluster generator: no static ubuntu-k3s destination remains
# (in test file scripts/tests/plugins/argocd_app_cluster_generator.bats, line 10)
#   `[ "$status" -eq 1 ]' failed
ok 17 argocd app cluster generator: services-git uses matrix clusters label selector
ok 18 argocd app cluster generator: data-git exists and targets shopping-cart-data
```

```text
scripts/etc/argocd/projects/platform.yaml.tmpl:17:      name: ubuntu-k3s
scripts/etc/argocd/projects/platform.yaml.tmpl:29:      name: ubuntu-k3s
scripts/etc/argocd/projects/platform.yaml.tmpl:31:      name: ubuntu-k3s
scripts/etc/argocd/projects/platform.yaml.tmpl:33:      name: ubuntu-k3s
scripts/etc/argocd/projects/platform.yaml.tmpl:35:      name: ubuntu-k3s
scripts/etc/argocd/projects/platform.yaml.tmpl:41:      name: ubuntu-k3s
scripts/etc/argocd/projects/platform.yaml.tmpl:43:      name: ubuntu-k3s
```

## Root cause
The repo still uses `ubuntu-k3s` in the ArgoCD Project cluster allowlist, so a blanket repo-wide grep was too broad
for this ApplicationSet cutover.

## Follow-up
Narrow the guard to `scripts/etc/argocd/applicationsets/`, which is the actual surface being switched from the
static `data-layer` app to the generated `data-git` ApplicationSet.
