# Active Context – k3d-manager

## Current Branch: `main` (as of 2026-02-28)

**v0.2.0 released** — OrbStack validated (M4 + M2), Vault reboot unseal confirmed, Jenkins k8s agents working.
**v0.2.1 released** — docs-only: CHANGE.md versioned entries + README Releases table.

---

## Current Focus (as of 2026-02-28)

- **Two-cluster is live** — infra on k3d (OrbStack), app on Ubuntu k3s (fresh redeploy ✅)
- Two-cluster refactor (k3d-manager code): `feature/two-cluster-infra` — Codex implements, Claude deploys
- shopping-cart CI/CD pipeline design in progress (see shopping-cart-infra memory-bank)

---

## Cluster State (as of 2026-02-28)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-test-orbstack-exists`)
| Component | Status | Age |
|---|---|---|
| Vault | ✅ Running | 3d21h |
| ESO | ✅ Running | 3d21h |
| Jenkins | ✅ Running | 34h |
| OpenLDAP | ✅ Running | 3d19h |
| Istio | ✅ Running | 3d22h |
| ArgoCD | ❌ Not deployed | — |

Context `k3d-automation` is dead (old cluster, port gone — ignore).

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`, host: 10.211.55.14)
| Component | Status | Notes |
|---|---|---|
| k3s node | ✅ Ready | Fresh redeploy 2026-02-28, v1.34.4+k3s1 |
| Istio | ✅ Running | IngressGateway + istiod |
| ESO | ❌ Not deployed | Needs remote Vault addr |
| shopping-cart-data | ❌ Not deployed | PostgreSQL, Redis, RabbitMQ |
| shopping-cart-apps | ❌ Not deployed | basket, order, payment, catalog, frontend |
| observability | ❌ Not deployed | — |

**SSH note:** `SSH_AUTH_SOCK` is forwarded (ForwardAgent yes in config).
If git auth fails: old ControlMaster may be stale — run `ssh -O exit ubuntu` then reconnect.

### Deployment Ownership
- **Claude** owns app cluster deployment
- Blocked on: Codex implementing app-cluster mode in k3d-manager (`feature/two-cluster-infra`)
- Remote Vault addr for Ubuntu ESO: `https://10.211.55.3:8200` (Mac OrbStack IP — verify before deploy)

## Open Items

### Two-Cluster Refactor — Codex Task (branch: `feature/two-cluster-infra`)

Full spec: `docs/plans/two-cluster-infra.md` — Codex reads this before starting.

**Summary of what Codex must implement:**

1. **Namespace renames** (change defaults, keep env var overrides working):
   - `vault` → `secrets` (vault.sh: `VAULT_NS_DEFAULT`, `eso_ns` defaults)
   - `external-secrets` → `secrets` (vault.sh eso_ns params)
   - `jenkins` → `cicd` (`scripts/etc/jenkins/vars.sh`)
   - `directory` → `identity` (`scripts/etc/ldap/vars.sh`, `ldap-password-rotator.sh`)
   - `argocd` → `cicd` (`scripts/etc/argocd/vars.sh`)

2. **Fix hardcoded namespace strings** in:
   - `scripts/lib/test.sh` — `-n jenkins`, `-n vault`
   - `scripts/ci/check_cluster_health.sh` — `namespace="${1:-vault}"`
   - `scripts/tests/run-cert-rotation-test.sh` — `-n jenkins`
   - `scripts/lib/dirservices/openldap.sh` — `namespace="${1:-directory}"`

3. **New `CLUSTER_ROLE` env var** (`infra` | `app`) in dispatcher:
   - `infra` (default): full stack — Vault, ESO, Jenkins, ArgoCD, LDAP, Istio
   - `app`: ESO only (remote Vault) + shopping-cart manifests; skip infra plugins

4. **Remote Vault ESO** (`REMOTE_VAULT_ADDR`):
   - New `_eso_configure_remote_vault` function in `scripts/plugins/eso.sh`
   - SecretStore template uses `REMOTE_VAULT_ADDR` + `kubernetes-app` auth mount
   - Vault auth mount setup script for infra cluster

**Must not break:** single-cluster mode, existing CLI flags, env var overrides, CI tests.

**Claude deploys** once Codex lands: destroy infra cluster → redeploy with new namespaces → deploy app layer on Ubuntu.

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
- **Ubuntu SSH agent forwarding**: `ForwardAgent yes` is set in `~/.ssh/config`. If `SSH_AUTH_SOCK` is empty on Ubuntu (git auth fails), kill stale ControlMaster: `ssh -O exit ubuntu` then reconnect. Root cause: ControlMaster reuses old socket without agent forwarding.

---

## Branch Protection

- 1 required PR approval, stale review dismissal, enforce admins disabled (admin can bypass)
- Required status checks: `lint` (Stage 1) and `stage2` (Stage 2)
- Tag: `@copilot` in PR body for automated review
