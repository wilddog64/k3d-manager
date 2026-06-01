# OCI Object Storage Backup/Restore Validation Note

## What was attempted

- Implemented `scripts/lib/providers/k3s-oci-storage.sh`
- Wired `scripts/lib/providers/k3s-oci.sh` to source the storage helper and auto-backup after deploy
- Added `backup` and `restore` targets to `Makefile`
- Added the `oci_backup` / `oci_restore` dispatch hook in `scripts/k3d-manager`
- Ran `shellcheck` on the touched shell files
- Ran `bash -n` on the touched shell files
- Ran `./scripts/k3d-manager oci_backup --help`
- Ran `./scripts/k3d-manager oci_restore --help`

## Actual output

```text
shellcheck scripts/lib/providers/k3s-oci-storage.sh scripts/lib/providers/k3s-oci.sh scripts/k3d-manager
<no output>
```

```text
bash -n scripts/lib/providers/k3s-oci-storage.sh && bash -n scripts/lib/providers/k3s-oci.sh && bash -n scripts/k3d-manager
<no output>
```

```text
./scripts/k3d-manager oci_backup --help
running under bash version 5.3.9(1)-release
Usage: CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager oci_backup
       make backup CLUSTER_PROVIDER=k3s-oci

Backs up the OCI k3s etcd snapshot and kubeconfig to OCI object storage.
```

```text
./scripts/k3d-manager oci_restore --help
running under bash version 5.3.9(1)-release
Usage: CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager oci_restore [--snapshot <name>]
       make restore CLUSTER_PROVIDER=k3s-oci

Restores the OCI k3s etcd snapshot and kubeconfig from OCI object storage.
```

## Root cause

The live `oci_backup` / `oci_restore` flows were not run in this workspace because they require a configured OCI account, live OCI object storage access, and a reachable OCI k3s cluster.

## Recommended follow-up

Run `make backup CLUSTER_PROVIDER=k3s-oci` and `make restore CLUSTER_PROVIDER=k3s-oci` against a live OCI cluster once OCI credentials and network access are available.
