# Phase 4 — SMB Storage & Backup

Finalize and validate SMB CSI configuration and backup procedures.

---

## 1️⃣ SMB CSI Configuration

Ensure `smb-jenkins` StorageClass is in place:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: smb-jenkins
provisioner: smb.csi.k8s.io
parameters:
  source: "//smb-server.example.com/jenkins-data"
  csi.storage.k8s.io/node-stage-secret-name: smb-creds
  csi.storage.k8s.io/node-stage-secret-namespace: jenkins
allowVolumeExpansion: true
reclaimPolicy: Retain
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=1000
  - gid=1000
```

** SMB Secret

```bash
kubectl -n jenkins create secret generic smb-creds \
  --from-literal username='svc_jenkins' \
  --from-literal password='REDACTED'


Note: we can handle this either via vault or azure key vault
