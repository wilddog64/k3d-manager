# Phase 1 — Job Import (No Credentials)

This phase establishes the new Jenkins controller on k3s,
configures SMB CSI storage, and validates job execution
using a small set of **no-credential** jobs.

---

## 1️⃣ Deploy Jenkins on k3s

Install via k3d-manager:

```bash
k3d-manager deploy_cluster automation
```
