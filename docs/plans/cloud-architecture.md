# Cloud Architecture Plan — k3d-manager Cloud Provider

_Established: 2026-02-28 | Updated: 2026-02-28 (ACG constraints)_

---

## ACG Sandbox Constraints (Verified)

Before committing to any cloud architecture, these confirmed ACG sandbox limitations
must shape the design:

| Constraint | Detail | Impact |
|---|---|---|
| **IAM restricted** | No OIDC provider creation, service-linked roles may fail | Blocks EKS IRSA — pod-level IAM unavailable |
| **Route 53 unavailable** | Authorization error on all Route 53 calls | No managed DNS — use `nip.io` / `sslip.io` instead |
| **Max instance: t3.medium** | t3.large and above not allowed | Infra node must fit in t3.medium (2 vCPU / 4GB) |
| **Max 5 EC2 instances** | Hard limit across all instances | Two-cluster design = 4-5 nodes — very tight |
| **Max 30GB EBS total** | Across all volumes in the sandbox | Careful storage allocation required |
| **EKS availability: unconfirmed** | IAM restrictions may block cluster creation | Verify before building Track B |
| **KMS availability: unconfirmed** | Needed for Vault auto-unseal | Verify before planning KMS path |
| **RDS / ElastiCache / MQ: unconfirmed** | No documentation confirming availability | Verify before planning managed data layer |
| **Session: up to 8h** | Must extend manually | Design for teardown/rebuild — use Terraform |
| **Regions: us-east-1, us-west-2 only** | No other regions | Use us-east-1 |

---

## Three-Track Strategy

```
Track 0: One-node EKS (develop EKS provider)
──────────────────────────────────────────────
1 EKS cluster, 1× t3.medium node
Minimal deployment: Vault + ESO + Istio only
Goal: prove CLUSTER_PROVIDER=eks works end-to-end
Answers: does EKS work on ACG? does IRSA work? does EBS CSI work?
Time: one sandbox session

Track A: k3s on EC2 (full stack on cloud)
──────────────────────────────────────────
2× t3.medium, existing k3s provider
Full shopping-cart stack
nip.io DNS, SSM/k8s-secret unseal
Unblocked — start after local two-cluster done

Track B: EKS full stack (after Track 0 proves EKS feasible)
────────────────────────────────────────────────────────────
Single EKS cluster, t3.medium nodes
Full shopping-cart stack
nip.io DNS, KMS unseal (if confirmed)
Managed services (RDS/ElastiCache if confirmed)
Blocked on: Track 0 success
```

---

## Track A: k3s on EC2 (Primary Path)

### What Changes vs Local

| Component | Local | Track A (k3s on EC2) |
|---|---|---|
| Cluster provisioning | k3d / k3s binary | k3s on EC2 (existing k3s provider) |
| Vault unseal | Keychain / libsecret | k8s `vault-unseal` secret (existing fallback) |
| DNS | `/etc/hosts` | `nip.io` — `<service>.<node-ip>.nip.io` |
| TLS (public) | Vault PKI | Vault PKI (same — self-signed acceptable for sandbox) |
| Storage | hostPath / local-path | EBS gp2 PVC (local-path provisioner works on k3s) |
| Node provisioning | local machine | Terraform: VPC + EC2 + SG + EBS |

**Nothing changes in plugin code.** All of Vault, ESO, Jenkins, ArgoCD, Istio run
identically — it is the same k3s provider already used on Ubuntu/Parallels.

### Node Layout (within ACG limits)

```
Node 1 — t3.medium (k3s server — control plane + infra workloads)
  vault/          ~2GB EBS
  external-secrets/
  jenkins/        ~8GB EBS
  argocd/
  identity/       ~2GB EBS (Keycloak + OpenLDAP)
  istio-system/
  Subtotal: ~12GB

Node 2 — t3.medium (k3s agent — app workloads + data)
  shopping-cart-apps/
  shopping-cart-data/
    postgresql × 2   ~4GB EBS
    redis × 2        ~1GB EBS
    rabbitmq         ~2GB EBS
  observability/    ~4GB EBS (Prometheus TSDB)
  Subtotal: ~11GB

Total EBS: ~23GB  ← within 30GB limit
Total instances: 2  ← within 5-instance limit
```

### DNS: nip.io (no Route53 needed)

`nip.io` resolves any subdomain to the embedded IP:
```
# Node 2 public IP: 54.210.1.50
basket.54-210-1-50.nip.io   → 54.210.1.50
jenkins.54-210-1-50.nip.io  → 54.210.1.50
```

VirtualService host templates use `${SERVICE}.${NODE_IP//./-}.nip.io`
when `CLUSTER_PROVIDER=k3s` and `K3S_DNS_MODE=nip.io`.

New env var: `K3S_DNS_MODE` — `hosts` (local default) or `nip.io` (EC2 default).

### Vault Unseal on EC2

No KMS, no Keychain. The existing `vault-unseal` k8s secret fallback already
handles this — `_vault_replay_cached_unseal` falls back to the k8s secret when
libsecret is unavailable (line 419–428 of vault.sh). No code change needed.

For added durability, shards can be stored in **AWS SSM Parameter Store**
(SecureString, free tier) — add as a third backend in `_secret_store_data`:

```
Priority order:
1. macOS Keychain (if security command available)
2. Linux libsecret (if secret-tool available)
3. AWS SSM Parameter Store (if aws CLI available + VAULT_UNSEAL_SSM_PATH set)
4. k8s vault-unseal secret (always available — existing fallback)
```

### Terraform Module (Track A)

```
terraform/aws/track-a/
├── main.tf          VPC + subnets + IGW + NAT GW + route tables
├── sg.tf            Security groups (k3s API 6443, HTTP 80, HTTPS 443, WinRM 5985)
├── ec2.tf           2× t3.medium + EBS volumes + user_data bootstrap
├── k3s.tf           k3s server install + agent join token output
├── outputs.tf       node IPs, k3s join token, kubeconfig path
└── variables.tf     region, cluster name, key pair name
```

---

## Track B: EKS (Conditional — Verify First)

**Do not implement until all three are confirmed on a live ACG sandbox:**

```bash
# Verification checklist — run in a throwaway ACG session
aws eks create-cluster --name test-verify --kubernetes-version 1.29 \
  --role-arn ... --resources-vpc-config ...
# → If IAM error: EKS unavailable on ACG sandbox

aws kms create-key --description "vault-unseal-test"
# → If IAM error: KMS unavailable

aws rds create-db-instance --db-instance-identifier test \
  --db-instance-class db.t3.micro --engine postgres ...
# → If error: RDS unavailable
```

### If EKS Confirmed Available

Revise from two EKS clusters to **single EKS cluster** (instance limit):

```yaml
# scripts/etc/eks/cluster.yaml.tmpl (revised for ACG constraints)
managedNodeGroups:
  - name: general
    instanceType: t3.medium   # max allowed on ACG
    desiredCapacity: 2        # 2 nodes — within 5-instance limit
    minSize: 1
    maxSize: 2

iam:
  withOIDC: true   # only if IAM permits OIDC provider creation
```

### If KMS Confirmed Available

Replace k8s secret fallback with KMS auto-unseal:

```yaml
# vault helm values addition
seal "awskms" {
  region     = "${AWS_REGION}"
  kms_key_id = "${VAULT_KMS_KEY_ID}"
}
```

KMS auto-unseal is the production-correct pattern — no shard management at all.

### DNS on Track 0 and Track B (EKS)

Route53 is **unavailable** regardless of EKS availability.
EKS IngressGateway gets an NLB with a **DNS hostname**, not a static IP.
`nip.io` requires an IP in the subdomain — resolve the NLB hostname first:

```bash
NLB_HOST=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
NLB_IP=$(dig +short "$NLB_HOST" | head -1)
# VirtualService host: ${SERVICE}.${NLB_IP//./-}.nip.io
```

Add `_eks_get_ingress_ip` to `eks.sh` to encapsulate this.
NLB IPs can change on restart — re-run the above after each sandbox session.

### New File: `scripts/lib/providers/eks.sh`

```
Function                    Purpose
─────────────────────────────────────────────────────
_eks_create_cluster         eksctl create cluster (from config template)
_eks_destroy_cluster        eksctl delete cluster
_eks_get_kubeconfig         aws eks update-kubeconfig
_eks_cluster_exists         aws eks describe-cluster (check)
_eks_wait_for_nodes         kubectl wait --for=condition=Ready nodes
_eks_install_prerequisites  install eksctl, aws-iam-authenticator
_eks_install_storage_driver aws eks create-addon aws-ebs-csi-driver
_eks_get_ingress_ip         resolve NLB hostname → IP for nip.io DNS
```

Activated by: `CLUSTER_PROVIDER=eks ./scripts/k3d-manager deploy_cluster`

---

## Environment Variables

| Variable | Default | Track A | Track 0 / Track B |
|---|---|---|---|
| `AWS_REGION` | `us-east-1` | ✓ | ✓ |
| `K3S_DNS_MODE` | `hosts` | `nip.io` | `nip.io` (after NLB IP resolution) |
| `VAULT_UNSEAL_MODE` | `keyring` | `ssm` or `k8s-secret` | `k8s-secret` (T0) / `kms` (TB if available) |
| `VAULT_KMS_KEY_ID` | (unset) | N/A | KMS key ARN (Track B only) |
| `VAULT_UNSEAL_SSM_PATH` | (unset) | `/k3d-manager/vault/shards` | N/A |
| `DOMAIN` | `dev.local.me` | `<node-ip>.nip.io` | `<nlb-ip>.nip.io` (resolved via `_eks_get_ingress_ip`) |

---

## Implementation Order

### Track 0 (EKS provider development — run in any ACG session)
1. `scripts/lib/providers/eks.sh` — implement all functions in the table above
2. `scripts/etc/eks/cluster.yaml.tmpl` — 1-node t3.medium, OIDC conditional on IAM
3. One ACG sandbox session: `CLUSTER_PROVIDER=eks ./scripts/k3d-manager deploy_cluster`
4. Validate: Vault unseals (k8s secret fallback), ESO SecretStore ready, Istio Gateway up
5. Validate: `_eks_get_ingress_ip` resolves NLB → nip.io hostname reachable
6. **Decision:** success → Track B unlocked; IAM/EKS error → document, Track A is the cloud path

### Track A (k3s on EC2 — start after local two-cluster done)
1. Terraform module `terraform/aws/track-a/` — VPC, EC2, SGs
2. `nip.io` DNS mode in VirtualService templates (`K3S_DNS_MODE`)
3. SSM shard backend in `_secret_store_data` / `_secret_load_data`
4. Validate: `CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster` on EC2
5. Validate: full stack (vault → eso → ldap → jenkins → argocd)

### Track B (after Track 0 proves EKS feasible)
1. Verify KMS / RDS / ElastiCache availability on ACG sandbox
2. Extend `scripts/etc/eks/cluster.yaml.tmpl` for 2-node full cluster
3. KMS auto-unseal (`VAULT_UNSEAL_MODE=kms`) — only if KMS confirmed
4. Validate: `CLUSTER_PROVIDER=eks ./scripts/k3d-manager deploy_cluster` (full stack)

---

## Sequencing with Local Work

All tracks are **blocked on**:
1. Local two-cluster refactor complete (`feature/two-cluster-infra`)
2. Ubuntu k3s clean redeploy validated

Track 0: one ACG sandbox session — can run independently of Track A
Track A: requires Terraform module written + ACG sandbox provisioned
Track B: requires Track 0 success + KMS/RDS verification

---

## References

- Shopping-cart-infra cloud architecture: `shopping-cart-infra/docs/plans/cloud-architecture.md`
- Two-cluster local plan: `docs/plans/two-cluster-infra.md`
- k3s provider (reference implementation): `scripts/lib/providers/k3s.sh`
- ACG sandbox help: https://help.pluralsight.com/hc/en-us/articles/24425443133076
