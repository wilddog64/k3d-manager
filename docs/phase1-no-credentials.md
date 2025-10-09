# Phase 1 — Job Import (No Credentials)

This phase establishes the new Jenkins controller on k3s,
configures SMB CSI storage, and validates job execution
using a small set of **no-credential** jobs.

---

## 1️⃣ Deploy Jenkins on k3s

Install via Helm:
```bash
helm upgrade --install jenkins jenkins/jenkins \
  -n jenkins \
  --create-namespace \
  --set controller.tag=2.516.3-lts-jdk17 \
  --set controller.serviceType=ClusterIP \
  --set controller.ingress.enabled=true \
  --set controller.ingress.hostName=jenkins.dev.local.me \
  --set controller.persistence.storageClass=smb-jenkins \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=4Gi \
  --set controller.resources.limits.cpu=4 \
  --set controller.resources.limits.memory=16Gi
