# SMB CSI Driver Guide

This document explains how to enable and verify SMB-backed persistent storage in the single-node k3s environment, using the upstream `smb.csi.k8s.io` driver. The workflow keeps credentials out of the repository and supports multiple secret sources.

## Prerequisites

- A k3s cluster managed by `k3d-manager` (single-node for now).
- `cifs-utils` installed on the host node (handled automatically on Debian/Ubuntu and RHEL/Fedora; install manually if the helper warns).
- SMB credentials that can access the target share (domain optional).
- Network access from k3s to the SMB server (firewall and routing opened).

WSL2 notes:
- The WSL kernel already ships the `cifs` module; install `cifs-utils` via `sudo apt-get install cifs-utils`.
- Ensure the Windows host publishes the SMB share and accepts your credentials.

## Enabling SMB support

`deploy_cluster` now installs the SMB CSI driver by default (`--enable-cifs`). Provide credentials through environment variables before invoking the command:

```bash
export SMB_USERNAME='svcShareUser'
export SMB_PASSWORD='correct horse battery staple'
# optional: export SMB_DOMAIN='PACIFIC'

# Specify the SMB share (pick one form)
export SMB_SOURCE='//fileserver.example.com/projects'
# or
export SMB_SERVER='fileserver.example.com'
export SMB_SHARE='projects'
# optional: export SMB_SUBDIR='jenkins-artifacts'

./scripts/k3d-manager deploy_cluster --provider k3s
```

Key defaults:
- Secret name: `smb-credentials` in `kube-system`.
- StorageClass name: `smb-csi`.
- StorageClass reclaim policy: `Retain` (override via `SMB_STORAGE_RECLAIM_POLICY`).

Disable the driver with `--no-cifs` if you want to manage it manually.

## Credential sources

`k3d-manager` looks for `SMB_USERNAME`, `SMB_PASSWORD`, and optional `SMB_DOMAIN` in the environment. Populate them via:

- **smartcd**: export the values when entering a directory.
- **LastPass**: use `lpass show` in a wrapper script that exports the vars before running `deploy_cluster`.
- **Manual export**: type them in the shell (unset afterwards).
- **Future Vault integration**: once Vault contains the SMB secret, we will add a helper to read from `vault kv get` and feed `_ensure_smb_secret`.

If the environment variables are missing, the helper warns and skips secret creation—allowing manual `kubectl create secret` workflows.

## Smoke tests

Set `SMB_SMOKE_TEST=1` to run a smoke test after cluster bootstrap. The helper creates a temporary PVC and pod that writes a file into the mounted share and then deletes both resources.

```bash
export SMB_SMOKE_TEST=1
export SMB_SMOKE_NAMESPACE='default'        # optional
export SMB_SMOKE_STORAGE_REQUEST='1Gi'      # optional
./scripts/k3d-manager deploy_cluster --provider k3s
```

The smoke test skips gracefully when secrets or the StorageClass could not be created. If you expect the share to be unavailable (for example during initial wiring), set `SMB_SMOKE_EXPECT=failure` so the script reports a failure without halting the flow.

## Manual verification (WSL2 ↔ Windows host)

To validate cross-host connectivity:

1. Create or confirm the SMB share on the Windows host and verify credentials with `net use \\HOST\share /user:DOMAIN\user`.
2. From WSL2, install `cifs-utils` and test a direct mount:
   ```bash
   sudo apt-get install -y cifs-utils
   sudo mount -t cifs //HOST/share /mnt/test \
     -o username="$SMB_USERNAME",password="$SMB_PASSWORD",domain="$SMB_DOMAIN"
   ```
   Expect success when the share exists; repeat with a non-existent share to ensure failures surface clearly.
3. Run `deploy_cluster` with the environment variables set. Afterwards, check the controller pod:
   ```bash
   kubectl get sc smb-csi
   kubectl -n kube-system get secret smb-credentials
   kubectl -n default describe pvc smb-smoke        # when smoke test enabled
   ```

## Troubleshooting

- **Secret skipped**: confirm `SMB_USERNAME` and `SMB_PASSWORD` are exported and `base64` is available.
- **StorageClass skipped**: set `SMB_SOURCE` or the `SMB_SERVER/SMB_SHARE` pair.
- **Smoke test fails**: inspect the pod logs (`kubectl logs -n <ns> smb-smoke`) and verify network access to the Windows host. Use `SMB_SMOKE_EXPECT=failure` temporarily if the share is intentionally offline.
- **Share path wrong**: export `SMB_SUBDIR` to append a directory within the share without editing manifests.

## Cleanup

When done testing:

```bash
unset SMB_USERNAME SMB_PASSWORD SMB_DOMAIN SMB_SOURCE SMB_SMOKE_TEST SMB_SMOKE_EXPECT
kubectl -n kube-system delete secret smb-credentials
kubectl delete sc smb-csi
```
