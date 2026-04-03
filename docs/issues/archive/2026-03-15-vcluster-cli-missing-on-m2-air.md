# Issue: vCluster CLI missing on M2 Air infra cluster

**Date:** 2026-03-15
**Component:** `scripts/plugins/vcluster.sh`

## Description

During the Gemini smoke test of the `vcluster` plugin on the M2 Air infra cluster (`k3d-k3d-cluster`), the `vcluster_create` command failed. The `vcluster` CLI binary was expected to be installed on the host but was not found in any common binary directories (`/usr/local/bin`, `/opt/homebrew/bin`, etc.).

## Evidence

Running the following commands on `m2-air.local`:

```bash
which vcluster
ls /opt/homebrew/bin/vcluster
```

Result:
```
vcluster not found
ls: /opt/homebrew/bin/vcluster: No such file or directory
```

Attempting to run `vcluster_create smoke-test`:
```
ERROR: vcluster CLI is not installed; see https://github.com/loft-sh/vcluster
```

## Impact

The `vcluster` plugin functions (`vcluster_create`, `vcluster_list`, `vcluster_destroy`, `vcluster_use`) all depend on the `vcluster` CLI binary being available in the system PATH. Without this binary, the plugin is unusable on the M2 Air.

## Recommendation

Install the `vcluster` CLI on `m2-air.local` via Homebrew or direct binary download. Alternatively, consider adding a `deploy_vcluster_cli` or similar helper function to `k3d-manager` to automate the installation of required binaries, similar to how `istioctl` or `helm` might be handled.
