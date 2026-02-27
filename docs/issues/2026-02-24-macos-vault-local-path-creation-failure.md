# macOS Vault Local-Path Creation Failure

**Date:** 2026-02-24
**Status:** ✅ Fixed (2026-02-24)

## Description

When deploying Vault on macOS using k3d with the default `local-path` storage class, the `deploy_vault` command fails during the `_vault_ensure_data_path` step.

The script attempts to:
1. Resolve the host path of the PersistentVolume (PV) associated with the Vault PVC.
2. Ensure that this directory exists on the host by calling `mkdir -p`.

On macOS, the resolved path often points to a location like `/var/lib/rancher/k3s/storage/...`. This path exists **inside** the Docker/OrbStack virtual machine, but the script attempts to create it on the **macOS host file system**, where it lacks permissions (and where the path is not meaningful for the container).

### Error Output:
```
INFO: [vault] creating data directory: /var/lib/rancher/k3s/storage/pvc-5fe6f13b-0250-4d4c-afcc-7f06bd940841_vault_data-vault-0
mkdir: cannot create directory ‘/var/lib/rancher’: Permission denied
mkdir command failed (1): mkdir -p /var/lib/rancher/k3s/storage/pvc-5fe6f13b-0250-4d4c-afcc-7f06bd940841_vault_data-vault-0 
ERROR: failed to execute mkdir -p /var/lib/rancher/k3s/storage/pvc-5fe6f13b-0250-4d4c-afcc-7f06bd940841_vault_data-vault-0: 1
```

## Impact

Vault deployment fails on macOS when using the standard k3d/local-path provisioner because the script incorrectly assumes it needs to (and can) manage the underlying host directory for the PV.

## Root Cause

In `scripts/plugins/vault.sh`:
- `_vault_resolve_data_path` retrieves `.spec.local.path` from the PV.
- `_vault_ensure_data_path` then calls `mkdir -p "$host_path"` on the host.

On macOS, `local-path` provisioner manages directories inside the VM; the host-side script should not attempt to create them.

## Steps to Reproduce

1. Run on a macOS machine with OrbStack or Docker Desktop.
2. Run `./scripts/k3d-manager deploy_vault`.

## Fix

- `_vault_ensure_data_path` in `scripts/plugins/vault.sh` now returns early when
  `_is_mac` is true, so macOS hosts no longer attempt to create VM-only paths like
  `/var/lib/rancher/...`. Linux/WSL behavior is unchanged.

## Verification

- `PATH="/opt/homebrew/bin:$PATH" CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_vault ha`
  completes on m4 without the previous permission error.
- Vault bootstrap logs show the standard init/unseal detection and PKI setup with
  no warnings about host path creation.
