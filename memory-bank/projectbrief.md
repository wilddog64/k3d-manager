# Project Brief – k3d-manager

## What It Is

k3d-manager is a Bash utility for standing up opinionated local Kubernetes development
clusters with a full integrated service stack. It is **not** a general-purpose cluster
tool; it is purpose-built for a specific local dev + CI workflow.

## Core Mission

Provide a single-command developer experience for:
- Creating and tearing down Kubernetes clusters — local (k3d/OrbStack) and remote (ACG AWS EC2 via CloudFormation + k3sup).
- Deploying Vault, ESO, Istio, Jenkins, ArgoCD, and OpenLDAP with correct wiring on first run.
- Validating certificate rotation, directory-service integration, and secret management
  end-to-end **before** committing anything to production infrastructure.
- Running a GitOps app cluster (ubuntu-k3s on EC2) managed by ArgoCD on the infra cluster.

## Scope

**In scope:**
- Local k3d (Docker-based) and k3s (systemd-based) clusters (`CLUSTER_PROVIDER=k3d`, `orbstack`).
- Remote 3-node k3s on AWS EC2 ACG sandbox via CloudFormation + k3sup (`CLUSTER_PROVIDER=k3s-aws`).
- HashiCorp Vault with PKI, K8s auth, and ESO integration.
- Jenkins with Vault-issued TLS, cert rotation CronJob, and optional LDAP/AD auth.
- OpenLDAP (standard schema and AD-schema variant for testing AD code paths).
- External Secrets Operator (Vault backend; Azure backend partial).
- Active Directory integration (external-only; AD is never deployed by this tool).
- ACG sandbox lifecycle: provision, credential extraction via Playwright/Chrome CDP, TTL extension, teardown.
- SSH tunnel (autossh + launchd) with forward (k3s API) and reverse (Vault) port forwarding.
- ArgoCD GitOps hub on infra cluster managing shopping-cart apps on app cluster.

**Out of scope:**
- Production cluster management.
- Cloud-managed Kubernetes (EKS, GKE, AKS) — k3d-manager is kops-for-k3s only.
- Any cloud provisioning beyond ACG AWS sandbox (GCP/Azure planned for v1.0.5+).

## Why This Stack (Component Origin Story)

Each component exists because of a real gap, reasoned through sequentially — not from a design doc:

- **Jenkins** → needed a CI/CD target that mirrors enterprise reality
- **Credentials problem** → Jenkins needs passwords; where to store them safely?
  - Tried **BitWarden** first — `eso_config_bitwarden` was actually implemented
  - Landed on **Vault** — proper secret store for programmatic access
- **ESO** → Vault doesn't inject secrets into pods natively; ESO bridges Vault → Kubernetes secrets
- **Istio** → needed real service mesh to validate enterprise-like networking locally
- **LDAP/AD** → enterprises authenticate against directory services; needed local testing without a real AD
- **ACG plugin** → free AWS EC2 via Pluralsight ACG sandbox; needed automation to provision/teardown without manual AWS console clicks
- **Playwright/Chrome CDP** → ACG credential panel is browser-only; no API; Playwright extracts AWS keys from the UI automatically
- **CloudFormation** → replace sequential single-node EC2 with parallel 3-node stack; eliminates t3.medium resource exhaustion
- **ArgoCD** → GitOps hub on infra cluster; manages shopping-cart app deployments on EC2 k3s
- **Reverse tunnel** → Vault runs on Mac infra cluster; EC2 app pods need `localhost:8200`; reverse SSH tunnel bridges the gap without exposing Vault publicly

The `SECRET_BACKEND` abstraction exists because backends were *actually swapped* during development.

## Primary Users

Solo developer / small team validating Kubernetes service integration locally before
pushing to any cloud or on-prem environment.

## Repository Structure

```
k3d-manager/
├── scripts/
│   ├── k3d-manager          ← dispatcher / entry point
│   ├── lib/                 ← always-sourced core libraries
│   ├── plugins/             ← lazy-loaded feature modules
│   ├── etc/                 ← config templates & var files
│   └── tests/               ← Bats test suites
├── docs/
│   ├── plans/               ← design docs and task specs
│   ├── tests/               ← test plans and results
│   └── issues/              ← post-mortems and resolved bugs
├── bin/                     ← standalone helper scripts
├── memory-bank/             ← cross-agent documentation substrate
├── CLAUDE.md                ← authoritative dev guide
└── scratch/                 ← test logs and temp artifacts (gitignored)
```

## Branch Strategy

- `main` — stable, released state. Protected; owner merges via PR.
- `k3d-manager-v<X.Y.Z>` — feature branch per milestone; PR back to `main` on completion.
- Tags: `v<X.Y.Z>` annotated tag on the branch tip commit before merge.
