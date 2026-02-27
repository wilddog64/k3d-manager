# SMB CSI — macOS Development Workaround Plan

**Date:** 2026-02-27
**Status:** Planned
**Related:** `docs/plans/jenkins-k8s-agents-and-smb-csi.md`

---

## Problem

SMB CSI driver (`csi-driver-smb`) cannot mount volumes on macOS-based k3d or OrbStack
clusters. The failure chain is:

1. SMB CSI node plugin (DaemonSet) runs inside a k3d node container
2. To mount an SMB share it needs `mount.cifs` (from `cifs-utils`) inside that container
3. Standard `rancher/k3s` node images do not include `cifs-utils`
4. Even if `cifs-utils` were installed, the `cifs` kernel module must be loaded — the
   Docker Desktop LinuxKit VM and OrbStack's lightweight Linux VM do not expose it

**Result:** PVC stays in `Pending` / `ContainerCreating`; mount call fails silently or
with `modprobe: FATAL: Module cifs not found`.

This is a **macOS-only** limitation. Linux hosts (bare metal, cloud VM, WSL2 with the
right kernel) work normally with SMB CSI.

---

## Options

### Option 1 — NFS CSI Swap (Recommended for local dev)

**Idea:** Replace SMB CSI with NFS CSI for local macOS development. NFS uses the `nfs`
kernel module which is available inside k3d node containers out of the box. An in-cluster
NFS server (e.g., `nfs-ganesha` or a simple `erichough/nfs-server` pod) acts as the
storage backend. From Jenkins agents the mount path and `ReadWriteMany` semantics are
identical — only the StorageClass and server protocol differ.

**Architecture (macOS):**

```
Jenkins Agent Pod
  └── PVC (StorageClass: nfs-local)
        └── NFS CSI node plugin (mounts via nfs kernel module — available in k3d)
              └── nfs-server pod (in-cluster, same cluster)
```

**Architecture (Linux / production):**

```
Jenkins Agent Pod
  └── PVC (StorageClass: smb)
        └── SMB CSI node plugin (mounts via cifs kernel module)
              └── Real SMB server / Azure Files / Samba
```

**Implementation steps:**

1. Deploy NFS server in-cluster:
   ```bash
   # scripts/plugins/nfs-server.sh  (new, macOS dev only)
   helm repo add nfs-ganesha-server https://kubernetes-sigs.github.io/nfs-ganesha-server-and-external-provisioner
   helm upgrade --install nfs-server nfs-ganesha-server/nfs-server-provisioner \
     --namespace nfs --create-namespace \
     --set persistence.enabled=true \
     --set persistence.size=20Gi
   ```

2. Deploy NFS CSI driver:
   ```bash
   helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
   helm upgrade --install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
     --namespace kube-system
   ```

3. Create a `StorageClass` named `smb` that actually uses `nfs.csi.k8s.io` — this way
   Jenkins manifests and PVCs need zero changes between macOS dev and Linux prod; only
   the underlying StorageClass definition differs:
   ```yaml
   # scripts/etc/smb-csi/storage-class-macos.yaml.tmpl
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: ${SMB_STORAGE_CLASS_NAME}   # same name as production ("smb")
   provisioner: nfs.csi.k8s.io
   parameters:
     server: nfs-server.nfs.svc.cluster.local
     share: /
   reclaimPolicy: Delete
   volumeBindingMode: Immediate
   ```

4. Gate the choice in `deploy_smb_csi`:
   ```bash
   if [[ "$(uname)" == "Darwin" ]]; then
       _info "[smb-csi] macOS detected — using NFS CSI swap (cifs unavailable)"
       _deploy_nfs_csi_swap
   else
       _deploy_smb_csi_native
   fi
   ```

**Pros:** Zero manifest changes for Jenkins agents; `ReadWriteMany` works; no custom
images needed.

**Cons:** Not testing actual SMB code paths on macOS — production regression possible.
Mitigate by running SMB CSI tests on Linux CI (k3s provider) before merge.

---

### Option 2 — Custom k3d Node Image with `cifs-utils`

**Idea:** Build a custom k3d node image based on `rancher/k3s` with `cifs-utils`
pre-installed. The `cifs` kernel module still needs to be available from the host kernel,
but OrbStack's Linux VM may expose it; Docker Desktop's LinuxKit likely does not.

**Dockerfile:**
```dockerfile
# images/k3d-node-cifs/Dockerfile
ARG K3S_VERSION=v1.31.0-k3s1
FROM rancher/k3s:${K3S_VERSION}
RUN apk add --no-cache cifs-utils
```

**Build and use:**
```bash
docker build -t k3d-node-cifs:local ./images/k3d-node-cifs/
k3d cluster create dev --image k3d-node-cifs:local
```

**Pros:** Tests real SMB CSI code paths if the kernel module is available.

**Cons:** Must maintain a custom image; module availability on OrbStack is unconfirmed;
Docker Desktop LinuxKit almost certainly will not work regardless.

**Verdict:** Worth trying on OrbStack; skip for Docker Desktop. If OrbStack works, add
to CI as an optional test. If it doesn't, fall back to Option 1.

---

### Option 3 — Linux-only Validation (Minimal Change)

**Idea:** Do nothing special for macOS. SMB CSI is simply not tested locally on macOS.
All SMB CSI validation runs on Linux via the k3s provider (bare metal or GitHub Actions
Linux runner). macOS developers skip `deploy_smb_csi` entirely.

**Gate:**
```bash
if [[ "$(uname)" == "Darwin" ]]; then
    _warn "[smb-csi] SMB CSI not supported on macOS — skipping. Use Linux/k3s to validate."
    return 0
fi
```

**Pros:** Zero extra work. No custom images, no NFS shim.

**Cons:** Developers on macOS get no local SMB storage testing at all.

**Verdict:** Acceptable as a starting point. Upgrade to Option 1 when shared workspace
validation is needed locally.

---

## Recommendation

| Scenario | Option |
|---|---|
| Local macOS dev — need shared workspace validation | Option 1 (NFS CSI swap) |
| OrbStack user — want real SMB code path | Option 2 (custom image, experimental) |
| No local SMB needed, CI is enough | Option 3 (skip on macOS) |
| Production / Linux CI validation | Native SMB CSI — no workaround needed |

**Suggested implementation order:**
1. Start with Option 3 (skip guard) — unblocks Jenkins agent work immediately
2. Add Option 1 (NFS CSI swap) when a developer needs local `ReadWriteMany` storage
3. Attempt Option 2 on OrbStack opportunistically; document result

---

## In-cluster Samba Server (SMB server for either option)

Regardless of which CSI approach is used, when a real SMB endpoint is needed for
integration testing (e.g., Option 2 on OrbStack), deploy Samba in-cluster:

```bash
helm repo add groundhog2k https://groundhog2k.github.io/helm-charts/
helm upgrade --install samba groundhog2k/samba \
  --namespace samba --create-namespace \
  --set env.SAMBA_WORKGROUP=WORKGROUP \
  --set env.SAMBA_SHARE=jenkins \
  --set env.SAMBA_USER=jenkins \
  --set env.SAMBA_PASS=jenkins
```

StorageClass would then point to `//samba.samba.svc.cluster.local/jenkins`.

---

## Files to Create/Modify

```
docs/plans/smb-csi-macos-workaround.md          # this file
scripts/plugins/smb-csi.sh                       # add macOS gate (Option 3 first)
scripts/plugins/nfs-server.sh                    # new, macOS NFS swap (Option 1)
scripts/etc/smb-csi/storage-class-macos.yaml.tmpl # NFS-backed StorageClass (Option 1)
images/k3d-node-cifs/Dockerfile                  # custom node image (Option 2, optional)
```
