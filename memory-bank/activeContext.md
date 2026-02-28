# Active Context – k3d-manager

## Current Branch: `main` (as of 2026-02-28)

**v0.2.0 released** — OrbStack validated (M4 + M2), Vault reboot unseal confirmed, Jenkins k8s agents working.
**v0.2.1 released** — docs-only: CHANGE.md versioned entries + README Releases table.

---

## Current Focus (as of 2026-02-28)

- Ubuntu k3s cluster redeploy pending (33-day-old cluster, Jenkins in Unknown state)
- Two-cluster refactor planned: branch `feature/two-cluster-infra` (plan: `docs/plans/two-cluster-infra.md`)
- shopping-cart CI/CD pipeline design in progress (see shopping-cart-infra memory-bank)

---

## Open Items

### Ubuntu Cluster Redeploy
- Current state: vault-0 Running (survived 2 restarts — reboot unseal confirmed working), jenkins-0 Unknown (pre-existing broken path)
- Plan: delete k3s cluster → redeploy clean → deploy_argocd → shopping-cart apps
- Gate: user approval required before cluster delete
- Self-hosted GitHub runner on Ubuntu needed for: Jenkins connectivity + e2e tests post-deploy

### Two-Cluster Refactor
- Branch: `feature/two-cluster-infra` (k3d-manager), `refactor/namespace-redesign` (shopping-cart-infra)
- Plan doc: `docs/plans/two-cluster-infra.md`
- infra cluster: OrbStack (m2-air) — Vault, ESO, Jenkins, ArgoCD, observability
- app cluster: k3s (Ubuntu/Parallels) — shopping-cart apps, data layer, app observability
- Prerequisites: Ubuntu cluster redeploy first

### Known Broken Paths (all pre-existing)
| Path | Root Cause |
|---|---|
| `deploy_jenkins` (no vault) | Policy creation always runs; jenkins-admin secret missing |
| `--enable-ldap` without `--enable-vault` | LDAP secrets require Vault |
| Basic LDAP deploys empty directory | No bootstrap LDIF; use `deploy_ad` as workaround |

### Cloud Architecture (planned — blocked on local two-cluster first)
- Plan: `docs/plans/cloud-architecture.md`
- Target: ACG sandbox (flat $200/year) — **three-track strategy** due to confirmed constraints
- **Track 0 (one-node EKS):** 1 cluster, 1× t3.medium, Vault+ESO+Istio only — proves `CLUSTER_PROVIDER=eks`; gate for Track B
- **Track A (k3s on EC2):** confirmed feasible — 2× t3.medium, existing k3s provider, nip.io DNS, ~23GB EBS. Start here.
- **Track B (EKS full stack):** conditional — blocked on Track 0 success + EKS/KMS/RDS verification; single cluster only (5-instance limit)
- Key ACG constraints: no Route53, max t3.medium, max 5 instances, max 30GB EBS, IAM restricted
- Vault unseal on cloud: SSM Parameter Store (new backend) or existing k8s secret fallback — KMS only if confirmed
- DNS on cloud: nip.io (Route53 unavailable on ACG)
- Blocked on: local two-cluster refactor + Ubuntu redeploy validated first

### Pending Work
- [ ] SMB CSI Phase 2 (NFS CSI swap) — `docs/plans/smb-csi-macos-workaround.md`
- [ ] SMB CSI Phase 3 (custom k3d node image, OrbStack only)
- [ ] AD end-to-end validation (`--enable-ad`, `--enable-ad-prod`) — requires external AD/VPN
- [ ] `docs/guides/certificate-rotation.md`
- [ ] `docs/guides/mac-ad-setup.md`
- [ ] `docs/guides/ad-connectivity-troubleshooting.md`
- [ ] CI Stage 3: destructive tests via `workflow_dispatch`
- [ ] AI-powered code review via GitHub Actions (see progress.md)
- [ ] OrbStack Phase 3: native Kubernetes provider (no k3d overhead)
- [ ] ArgoCD Phase 1 implementation (`docs/plans/argocd-implementation-plan.md`)
- [ ] LDAP rotator rename docs cleanup (code renamed 2026-02-23, docs pending)

---

## Release Strategy

| Version | Status | Notes |
|---|---|---|
| v0.1.0 | ✅ released 2026-02-27 | Initial release |
| v0.2.0 | ✅ released 2026-02-27 | OrbStack, Vault reboot unseal, Jenkins k8s agents |
| v0.2.1 | ✅ released 2026-02-28 | Docs-only: CHANGE.md + README Releases table |
| v0.3.0 | pending | Two-cluster refactor, ArgoCD, Ubuntu clean redeploy |
| v1.0.0 | future | Production-hardened, all known-broken paths resolved |

---

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **LDAP bind DN**: keep `LDAP_BASE_DN` in sync with LDIF bootstrap base DN
- **Jenkins admin password**: contains special chars — always quote `-u "user:$pass"`. See `docs/issues/2026-02-27-jenkins-admin-password-zsh-glob.md`
- **SMB CSI on macOS**: `cifs` kernel module unavailable in k3d/OrbStack — skip guard active
- **GitGuardian false positive resolved**: `LDAP_ROTATOR_IMAGE` (renamed from `LDAP_PASSWORD_ROTATOR_IMAGE` 2026-02-23)
- **Vault reboot unseal**: `_secret_store_data`/`_secret_load_data` are dual-path — macOS Keychain + Linux libsecret. k8s `vault-unseal` secret is the fallback for headless Ubuntu sessions

---

## Branch Protection

- 1 required PR approval, stale review dismissal, enforce admins disabled (admin can bypass)
- Required status checks: `lint` (Stage 1) and `stage2` (Stage 2)
- Tag: `@copilot` in PR body for automated review
