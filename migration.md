# Jenkins Upgrade & Migration (Legacy → k3s Jenkins 2.516.3)

This repository documents the plan for migrating from the legacy Jenkins controller
to the new **k3s-based Jenkins 2.516.3 LTS** deployment.

The migration is designed to minimize downtime and risk by following
a phased rollout approach — starting with jobs that **do not use credentials**,
then expanding once the platform and agents are verified stable.

---

## 🎯 Objectives

- Deploy modern Jenkins on k3s with full LTS support and SMB CSI persistence  
- Validate new platform with 1–2 Windows pilot agents (vSphere)  
- Import initial jobs that require no credentials  
- Gradually migrate credentials and dependent jobs  
- Maintain rollback capability to legacy Jenkins at every step  

---

## 📘 Phases

| Phase | Description |
|--------|--------------|
| [Phase 1: Job Import (No Credentials)](docs/phase1-no-credentials.md) | Deploy new Jenkins, configure SMB CSI, and test jobs that don’t use credentials |
| [Phase 2: Credentials Migration](docs/phase2-credentials.md) | Migrate or recreate credentials and import dependent jobs |
| [Phase 3: Agent & Job Expansion](docs/phase3-agents-expansion.md) | Add more Windows agents and scale job migration gradually |
| [Phase 4: SMB Storage & Backup](docs/phase4-storage-smb.md) | Finalize SMB CSI configuration, snapshot, and backup strategy |

---

## 🧩 Environment Summary

| Component | Description |
|------------|-------------|
| **Platform** | k3s on vSphere |
| **Jenkins Version** | 2.516.3 LTS |
| **Storage** | SMB CSI (backed by corporate SMB share) |
| **Ingress** | Istio Gateway — `https://jenkins.dev.local.me` |
| **Agents** | Windows VMs (WebSocket mode via WinSW) |

---

## 🔁 Rollback Policy

- The **legacy Jenkins** remains available in read-only mode until migration completes  
- Each phase is reversible — simply disable migrated jobs on the new controller  
- Always back up:
  - `credentials.xml`
  - `secrets/master.key`
  - `secrets/hudson.util.Secret`
  - SMB PVC snapshots or replicated data  

---

## 📞 Contacts

| Area | Contact |
|-------|----------|
| DevOps / Jenkins Platform | _Team / Owner_ |
| SMB Storage Administration | _Team / Owner_ |
| vSphere Infrastructure | _Team / Owner_ |
| Security / Credential Management | _Team / Owner_ |

---

> See the [docs/](docs/) folder for detailed steps per phase.
