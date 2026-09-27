# Project Brief – k3d-manager

## What It Is

k3d-manager is a multi-cloud k3s cluster lifecycle framework built in Bash. It provisions,
configures, and tears down lightweight Kubernetes clusters on AWS EC2 (live), GCP, Azure, and
OCI (live), plus local runtimes (k3d, OrbStack) — all from a single entry point with a
consistent command interface.

It is **not** a general-purpose cluster tool and is **not** a local-only dev environment.
It is purpose-built to run the same opinionated service stack identically across cloud
providers at zero managed-service cost: no EKS, no GKE, no AKS — k3s everywhere.

## Core Mission

Provide a single-command experience for:
- Provisioning and destroying k3s clusters on any supported cloud or local runtime.
- Deploying Vault, ESO, Istio, ArgoCD, and OpenLDAP with correct wiring on first
  run, identical regardless of provider. (Jenkins is a **deprecated** demo feature —
  disabled by default via `ENABLE_JENKINS=0`, not deployed; code retained but unsupported.)
- Validating certificate rotation, directory-service integration, and secret management
  end-to-end before committing anything to production infrastructure.
- Running a GitOps app cluster (ubuntu-k3s on EC2) managed by ArgoCD on the infra cluster.

## Unique Design: Provider + Plugin System

### Provider System

The `CLUSTER_PROVIDER` environment variable selects the backend at runtime. Each provider
is an isolated shell module in `scripts/lib/providers/` that implements two lifecycle hooks:

```
_provider_<slug>_deploy_cluster   # provision infra + install k3s
_provider_<slug>_destroy_cluster  # tear down everything
```

The dispatcher (`scripts/lib/cluster_provider.sh`) translates `CLUSTER_PROVIDER` into the
slug (hyphens → underscores) and delegates. Adding a new cloud requires only one new file
and two functions — nothing else changes.

| `CLUSTER_PROVIDER` | Provider slug | Status |
|--------------------|---------------|--------|
| `k3s-aws`          | `k3s_aws`     | Active (AWS ACG sandbox via CloudFormation + k3sup) |
| `k3d`              | `k3d`         | Active (local Docker-based) |
| `k3s`              | `k3s`         | Active (Linux bare-metal, systemd-based) |
| `orbstack`         | `orbstack`    | Active (local OrbStack VM) |
| `k3s-oci`          | `k3s_oci`     | **DE-SCOPED** — code shipped v1.5.0 but no Always-Free instance was ever obtained; do not invest further effort |
| `k3s-gcp`          | `k3s_gcp`     | Active (GCP ACG sandbox via GCE + k3sup; shipped v1.1.0) |
| `k3s-az`           | `k3s_az`      | Active (Azure ACG sandbox via CloudFormation + k3sup; shipped v1.6.5) |
| `k3s-hostinger`    | `k3s_hostinger` | Active (permanent app cluster on Hostinger KVM2 VPS via SSH/k3sup; shipped v1.7.0) |

### Plugin System

Feature modules live in `scripts/plugins/` and are **lazy-loaded** — sourced only when
a matching function is invoked. Plugins are independent — each of the 28 lives in its own file:
ACG, ArgoCD, AWS, Azure, Cert-Manager, Copilot, E2E Tier 1 (`e2e.sh`), E2E Tier 2
(`e2e_remote.sh`), ESO, GCP, Gemini, Hello, Hub Recovery, Hub Snapshot, Istio Ambient, Jenkins
(**deprecated** — disabled by default, not deployed; code retained but unsupported), Keycloak,
LDAP, Loadtest, Observability, Shopping Cart, Signing, SMB-CSI, Smoke, SSM, Tunnel, Vault,
vCluster.

The two E2E tiers are separate plugins, not one: `e2e.sh` drives the local vCluster tier and
`e2e_remote.sh` the ACG/Stripe acceptance tier, and `smoke.sh` is a third file that probes both.

Public functions have no underscore prefix and are first-class CLI commands:
```
./scripts/k3d-manager vault_init
./scripts/k3d-manager acg_provision
./scripts/k3d-manager deploy_cluster
```

Private helpers use `_` prefix and are internal to their plugin. The dispatcher never
references plugin internals directly — only public function names.

The `DIRECTORY_SERVICE_PROVIDER` variable (`openldap` / `activedirectory`) selects the
directory integration plugin, mirroring the same pattern as cluster providers.

## Scope

**In scope:**
- **Parallel multi-cloud provisioning (v1.28.0+):** multiple cloud providers (k3s-aws, k3s-hostinger) can be active concurrently; provider-scoped state prevents collision; concurrent teardown/refresh supported via explicit `CLUSTER_PROVIDER` or refuse-when-ambiguous gate.
- Local k3d (Docker-based) and k3s (systemd-based) clusters (`CLUSTER_PROVIDER=k3d`, `orbstack`).
- Remote 3-node k3s on AWS EC2 ACG sandbox via CloudFormation + k3sup (`CLUSTER_PROVIDER=k3s-aws`).
- Permanent app-cluster on Hostinger VPS via SSH/k3sup (`CLUSTER_PROVIDER=k3s-hostinger`).
- HashiCorp Vault with PKI, K8s auth, and ESO integration.
- Jenkins with Vault-issued TLS, cert rotation CronJob, and optional LDAP/AD auth
  **(deprecated — disabled by default, not deployed; code retained but unsupported)**.
- OpenLDAP (standard schema and AD-schema variant for testing AD code paths).
- External Secrets Operator (Vault backend; Azure backend partial).
- Active Directory integration (external-only; AD is never deployed by this tool).
- ACG sandbox lifecycle: provision, credential extraction via Playwright/Chrome CDP, TTL extension, teardown.
- SSH tunnel (autossh + launchd) with forward (k3s API) and reverse (Vault) port forwarding.
- ArgoCD GitOps hub on infra cluster managing shopping-cart apps on app cluster.
- Read-only remote and cloud-session access (v1.38.0+): a Slack `/k3dm` command surface and a
  pull-model cloud bridge (`bin/k3dm-cloud-bridge`) that serves a fixed reader-tier action
  allowlist from an untrusted git branch. No credential is ever placed in a cloud environment
  and no cluster endpoint is exposed; operator-tier and admin-tier actions stay off both paths.

**Out of scope:**
- Production cluster management.
- Cloud-managed Kubernetes (EKS, GKE, AKS) — k3d-manager is kops-for-k3s only.

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

Solo developer or small platform team who needs to:
- Run a realistic multi-service Kubernetes stack on cloud sandboxes (ACG AWS) or local
  runtimes without paying for managed Kubernetes.
- Validate Vault PKI, LDAP/AD auth, Istio mTLS, and ESO secret sync before production.
- Operate identically across providers — same commands, same plugin stack, different backend.
- Troubleshoot infrastructure failures via multi-agent `/ask` (Claude, Gemini, Codex) from Slack threads.
- Resume interrupted cluster provisioning via `/cluster-resume` checkpoint-based re-entry.

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
│   ├── plans/               ← design docs and task specs (max 5 per milestone)
│   ├── bugs/                ← unplanned bug-fix specs (exempt from the 5-plan cap)
│   ├── issues/              ← Copilot findings and post-incident notes
│   ├── guides/              ← one guide per major technology
│   ├── retro/               ← per-milestone retrospectives
│   ├── api/                 ← public function reference
│   └── tests/               ← test plans and results
├── bin/                     ← standalone helper scripts
├── memory-bank/             ← cross-agent documentation substrate
├── CLAUDE.md                ← authoritative dev guide
└── scratch/                 ← test logs and temp artifacts (gitignored)
```

## Branch Strategy

- `main` — stable, released state. Protected (`enforce_admins` ON); owner merges via PR only.
- `k3d-manager-v<X.Y.Z>` — one feature branch per milestone (sprint story). PR back to `main` on completion; squash-merge preferred for clean history.
- Tags: `v<X.Y.Z>` annotated tag created on the merge SHA before the branch is deleted.
- `enforce_admins` is disabled only to merge a green PR, then immediately re-enabled.
- **Release scope gate:** max 5 spec files per milestone. A 6th spec signals the release is too large — split before writing another.
- Branch cleanup every 5 releases: keep `main` + current branch; delete all merged version branches (local + remote).

---

## Project Character

### Spec-Driven, Multi-Agent Development

Every code change starts as a written spec in `docs/plans/` before any agent touches a
file. The spec defines exact old/new code blocks, shellcheck gates, commit message, and
Definition of Done. No spec → no implementation task.

Three AI agents divide the work by capability:

| Agent | Role | Constraint |
|-------|------|------------|
| **Claude** | Architect — writes specs, verifies output, manages memory-bank | Never pushes to remote without user confirmation |
| **Codex** | Implementer — pure code changes, no live cluster | Must push before reporting done; fabricated SHAs caught by `git log` |
| **Gemini** | Operator — live cluster tasks, e2e smoke tests | Read-only tool scoping for verify tasks; no `--yolo` |
| **Copilot** | Reviewer — automated PR review after CI green | Findings documented in `docs/issues/`; threads resolved via GraphQL |

### Memory-Bank as Cross-Agent Substrate

`memory-bank/` is the shared context layer that survives context resets and agent
switches. Every agent reads it before starting; every agent updates it after completing.
It is the single source of truth for current branch, task status, decisions, and blockers.

- `activeContext.md` — current milestone, shipped versions, operational notes
- `progress.md` — task checklist: what's done, what's pending, what's blocked
- `projectbrief.md` — this file; stable project identity
- `systemPatterns.md` — architectural patterns, conventions, anti-patterns

### Bash Core, Stdlib-Only Satellites

The **cluster-lifecycle runtime** is plain Bash — no Go, no framework — so the provider
and plugin path installs and runs on any Linux or macOS machine with only standard POSIX
tools + kubectl + helm. Two satellites sit outside that core and are **Python
stdlib-only, no pip dependency at runtime**: the webhook server (`bin/k3dm-webhook`) and
the Hermes monitoring agent (`scripts/lib/hermes/`, `bin/k3dm-hermes`). Both are optional
— a cluster comes up without either. Playwright (Node.js) is used only for browser
automation: ACG sandbox TTL extend (`scripts/plugins/acg.sh`) and the Antigravity Copilot
agent trigger (`scripts/plugins/antigravity.sh`).

Consequence for testing: the repo has **two** test roots and two languages, so there is no
single green. See Enforcement at Commit Time below.

### Enforcement at Commit Time

Pre-commit hooks enforce code quality before any commit lands:
- `shellcheck -S warning` on all modified `.sh` files
- BATS test suite (`scripts/tests/`) runs on every commit
- Hooks cannot be bypassed (`--no-verify` is prohibited in all agent specs)

Violations are bugs. Agents fix their own hook failures and recommit — they do not skip.

**There is no single green (v1.35.0+).** The entrypoints are not interchangeable:

| Target | Runs | Root |
|---|---|---|
| `make test` | `scripts/tests/{lib,core,plugins,etc}` by directory discovery | dispatcher |
| `make test-bin` | `scripts/tests/bin` | `bats` directly |
| `make test-python-unit` | `scripts/tests/bin/*.py` (stdlib `unittest`) | python |
| `make test-pytest` | `scripts/tests/hermes` + `scripts/tests/bin/test_smoke_logins.py` | pytest |
| `make test-all` | all of the above | — |

`make test` deliberately does **not** include `scripts/tests/bin` — a different runner
root. So "`make test` passed" is a narrower claim than "the suite passed"; only
`make test-all` is the whole suite, and CI gates the four leaf targets individually.
Discovery is by **directory**, never a hand-maintained file list: a hand-maintained list
is how one plugin suite stayed dark in CI for a full release while `make test` was red
locally.

### Subtree-Managed Core Library

`scripts/lib/system.sh` and `scripts/lib/agent_rigor.sh` are managed as a `git subtree`
from `lib-foundation`. Changes to these files must go upstream first (lib-foundation PR),
then be pulled back via `git subtree pull`. Direct edits to the subtree files in
k3d-manager are tracked as debt and resolved in the next lib-foundation release.
