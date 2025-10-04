# Cluster Provider Modules

The helper libraries in `scripts/lib/provider.sh` and `scripts/lib/cluster_provider.sh` let
`k3d-manager` call provider specific logic without hard-coding a single
implementation.  Providers appear as small bash modules stored in
`scripts/lib/providers/<name>.sh`.  Each module exposes a predictable set of
functions, and the framework selects the correct module based on a few
environment variables.

This document explains how provider selection works and how to author a custom
provider module.

## Selecting a provider

The dispatcher inspects the following variables (in order) when it needs to
know which provider to use:

1. `CLUSTER_PROVIDER` – first-class override for the current shell.
2. `K3D_MANAGER_CLUSTER_PROVIDER` – secondary override read by older helpers.
3. `DEFAULT_CLUSTER_PROVIDER` – optional default published in your shell rc.
4. Automatic detection – falls back to `k3d` on macOS or whichever binary is
   available (see `_cluster_provider_guess_default` in
   `scripts/lib/cluster_provider.sh`).

Once resolved, the provider name is cached in `CLUSTER_PROVIDER_ACTIVE` so
functions such as `_cluster_provider_is k3s` are fast.

## Loading provider modules

`scripts/lib/provider.sh` takes care of sourcing the provider module on first
use.  Modules live under `scripts/lib/providers/` and must follow the naming
convention:

```
scripts/lib/providers/<provider>.sh   # e.g. scripts/lib/providers/k3d.sh
```

When `_cluster_provider_call deploy_cluster` runs, the loader sources the module
(if it is not already cached) and then looks for a function named
`_provider_<provider>_deploy_cluster`.  If that function is missing, the helper
raises an error so failures surface quickly.

### Built-in actions

Core scripts call the following actions today.  A custom provider should
implement every action its workflow intends to use:

| Action             | Function signature                                      | Triggered from |
|--------------------|----------------------------------------------------------|----------------|
| `exec`             | `_provider_<name>_exec [flags] -- <args>`                | `_cluster_provider_call exec` (used by `_run_command` wrappers) |
| `cluster_exists`   | `_provider_<name>_cluster_exists <cluster>`             | `system.sh:_cluster_provider_exists` |
| `apply_cluster_config` | `_provider_<name>_apply_cluster_config <file>`     | `system.sh:_apply_cluster_config` |
| `list_clusters`    | `_provider_<name>_list_clusters`                         | `system.sh:_list_clusters` |
| `install`          | `_provider_<name>_install [args...]`                     | `core.sh:_install_provider` |
| `destroy_cluster`  | `_provider_<name>_destroy_cluster <cluster>`             | `core.sh:destroy_cluster` |
| `create_cluster`   | `_provider_<name>_create_cluster <cluster> [ports...]`   | `core.sh:create_cluster` |
| `deploy_cluster`   | `_provider_<name>_deploy_cluster [cluster]`              | `core.sh:deploy_cluster` |

It is fine for a provider to delegate work to helper functions in the same
module (see the bundled `k3d.sh`/`k3s.sh`).  If your workflow needs a new
provider action, add a function that calls `_cluster_provider_call <action>` and
implement the corresponding `_provider_<name>_<action>` in each module.

## Authoring a custom provider

1. Create the module file, for example `scripts/lib/providers/acme.sh`.
2. Implement the functions you need using the naming convention described
   above.  Existing modules are good templates—copy the signatures and adapt the
   internals.
3. Set `CLUSTER_PROVIDER=acme` (or export `DEFAULT_CLUSTER_PROVIDER=acme`) and
   run your workflow through `./scripts/k3d-manager`.
4. Add tests that source `scripts/lib/provider.sh` and call
   `_cluster_provider_call` if you want to validate the module in bats.

### Minimal skeleton

```bash
# scripts/lib/providers/acme.sh

_provider_acme_exec() {
  _run_command -- acmectl "$@"
}

_provider_acme_cluster_exists() {
  local cluster="$1"
  acmectl cluster exists "$cluster"
}

_provider_acme_create_cluster() {
  local cluster="$1"
  acmectl cluster create "$cluster"
}

_provider_acme_destroy_cluster() {
  local cluster="$1"
  acmectl cluster delete "$cluster"
}

# Implement other actions (list_clusters, deploy_cluster, etc.) as needed.
```

With the module in place you can point the tooling at the new provider:

```bash
CLUSTER_PROVIDER=acme ./scripts/k3d-manager deploy_cluster
```

If the helper cannot find the module or a required action, it prints an error
that names the missing function to help you finish the implementation.

## Using provider APIs from other code

Inside scripts/plugins/ or tests you can dispatch provider actions with
`_cluster_provider_call`:

```bash
_cluster_provider_call exec cluster list
if _cluster_provider_call cluster_exists mycluster; then
  echo "ready"
fi
```

This keeps plugins agnostic of the concrete backend while still giving them
access to provider-specific features.
