# k3d-manager Strategic Roadmap: Towards v1.0.0

## Vision
Transform `k3d-manager` from a collection of Bash utility scripts into an
AI-assistable local Kubernetes platform — operable from any MCP-compatible
desktop client (Claude Desktop, OpenAI Codex, ChatGPT Atlas, Perplexity Comet).

---

## v0.6.x — The Tooling Baseline (Current)
*Focus: Stabilization & AI Plumbing*

- **v0.6.1 (Merged):** Standardize infra cluster structure (`secrets`, `identity`, `cicd` namespaces) and fix Istio sidecar Job hangs.
- **v0.6.2 (Active):** Copilot CLI Integration & Security Hardening.
  - Implement `_ensure_node` and `_ensure_copilot_cli` system helpers (auto-install pattern).
  - Implement `_k3d_manager_copilot` scoped passthrough wrapper with deny-tool guardrails.
  - Implicit `K3DM_ENABLE_AI` gating — all AI features opt-in, graceful auth failure.
  - Security: stdin-based secret injection for Vault KV, `_safe_path` helper, instruction integrity checks.
  - Plan: `docs/plans/v0.6.2-ensure-copilot-cli.md`
- **v0.6.3 (Planned):** The Great Refactor & Digital Auditor.
  - Refactor `core.sh` and `system.sh` to eliminate "Defensive Bloat" (redundant logic).
  - Reduce cyclomatic complexity and standardize OS-specific "footprints."
  - Implement `_agent_lint` (copilot-cli-powered architectural auditor) and `_agent_audit` (test-weakening detection).
  - Plan: `docs/plans/v0.6.3-refactor-and-audit.md`
- **v0.6.4 (Planned):** Shared Library Foundation.
  - Extract `core.sh` and `system.sh` into a discrete `lib-foundation` repository.
  - Implement **git subtree** integration across `k3d-manager`, `rigor-cli`, and `shopping-carts`.

## v0.7.0 — The Agent-Assisted Phase
*Focus: AI as a Code Generator + App Cluster Deployment*

- **Key Features:**
  - Implement Keycloak Provider Interface (Bitnami + Operator support).
  - Use `copilot-cli` to autonomously scaffold new plugins and BATS test suites.
  - Standardize "Template Specs" that can be fed directly to AI for consistent code generation.
  - Deploy ESO on Ubuntu app cluster and shopping-cart stack (PostgreSQL, Redis, RabbitMQ, apps).

## v0.8.0 — Security Hardening + lib-foundation Backlog
*Focus: Close open security gaps in k3d-manager before MCP integration*

### Vault-Managed ArgoCD Deploy Keys
Empty-passphrase SSH deploy keys stored on disk are insecure and hard to rotate.
Move all ArgoCD GitHub repo credentials into Vault — ESO syncs them to Kubernetes secrets,
ArgoCD reads from those secrets. No key files on disk.

- One Vault KV entry per repo: `secret/argocd/deploy-keys/<repo-name>`
- ESO `ExternalSecret` per repo → syncs to `argocd-repo-<name>` secret in `cicd` ns
- New Vault policy: `argocd-deploy-key-reader` (read-only on `secret/argocd/deploy-keys/*`)
- New function: `configure_vault_argocd_repos` in a plugin
- **Rotation mechanism:** `vault kv put secret/argocd/deploy-keys/<repo> private_key=@<new-key>` →
  ESO syncs → ArgoCD picks up automatically → update GitHub deploy key. One operation.
- **Rotation policy (two-tier):**
  - Scheduled — every 24h: rotate all 5 deploy keys (cron in `shopping-cart-infra` CI or k3d-manager scheduled task)
  - On `shopping-cart-infra` main merge: rotate all 5 deploy keys (infra changes are highest-risk event)
  - On demand: `k3d-manager argocd_rotate_deploy_keys` — manual escape hatch for suspected compromise
  - Skip: per-PR rotation on app repos (basket, order, etc.) — no infra change, low value
- **Rationale:** Deploy keys are repo-scoped read-only SSH keys — blast radius is low.
  24h rotation covers lab hygiene. Infra-merge trigger covers the highest-risk event.
  Per-PR rotation on app repos would create high Vault churn with negligible security gain.
- Motivated by: shopping cart deploy keys with empty passphrases discovered during v0.7.3

### Certificate Management (SC-081 Readiness)
CA/Browser Forum Ballot SC-081 compresses public TLS cert lifetimes to 47 days by 2029.
Manual renewal at that cadence is not viable. k3d-manager already handles cluster-internal
certs via Vault PKI — this adds ACME-based auto-renewal for external-facing services.

**Two-issuer architecture:**
- **Vault PKI** — unchanged, handles internal service mesh certs. CA owned by us.
- **cert-manager + ACME** — new, handles external-facing ingress certs (Let's Encrypt).

**New plugin: `deploy_cert_manager`**
```bash
./scripts/k3d-manager deploy_cert_manager                          # Let's Encrypt staging
./scripts/k3d-manager deploy_cert_manager --production             # Let's Encrypt production
ACME_EMAIL=user@example.com ./scripts/k3d-manager deploy_cert_manager
```

- Installs cert-manager via Helm (pinned chart version)
- Configures `ClusterIssuer` for Let's Encrypt ACME (HTTP-01 via Istio ingress)
- Annotates existing ingress resources to use cert-manager issuer
- Provider-aware extension in v1.0.0: ACM (EKS), GCP Certificate Manager (GKE), Key Vault (AKS)

### lib-foundation Backlog
- `_run_command` if-count refactor (v0.3.0) — `docs/issues/2026-03-08-run-command-if-count-refactor.md`
- Sync `deploy_cluster` fixes upstream (CLUSTER_NAME, provider helpers)
- Route bare sudo in `_install_debian_helm` / `_install_debian_docker` through `_run_command`
- Add `.github/copilot-instructions.md` to lib-foundation

### Shopping Cart CI Stabilization + Code Quality Gates

Execution order is fixed — each step unblocks the next:

1. **Fix CI failures (P1 first, P2 second):**
   - basket + product-catalog: replace custom Trivy install with `aquasecurity/trivy-action@0.30.0` in infra workflow
   - frontend: remove unused imports + add `"types": ["vite/client"]` to tsconfig
   - payment: fix `mvnw` init failure
   - order: publish `rabbitmq-client-java` to GitHub Packages or add CI pre-install step

2. **Add missing linters (after CI is green):**
   - basket: `golangci-lint` + `go vet`
   - order: Checkstyle + OWASP dependency check
   - product-catalog: `ruff check` + `mypy` + `black --check`
   - payment: Checkstyle/SpotBugs (OWASP already present)
   - frontend: already enforces ESLint + Prettier + `tsc --noEmit`

3. **Branch protection (after linters pass):**
   - All 5 repos: require PR, required status checks, no force push, dismiss stale reviews
   - Automated via `configure_shopping_cart_branch_protection` in `scripts/plugins/shopping_cart.sh`

### Shopping Cart E2E — Playwright MCP (deferred to v0.8.1)

`@playwright/mcp` runs **outside the cluster** on the dev machine. The AI client (Claude,
Copilot, or Gemini CLI) drives browser automation via MCP tool calls. No Chrome-in-cluster
needed — simpler, no resource pressure on Ubuntu k3s node.

**Prerequisite chain:** CI green → images in ghcr.io → ArgoCD syncs → services running →
branch protection enforced → then Playwright MCP can test against live services.

**Design:**
- `@playwright/mcp` runs as a local process on dev machine
- Browser connects to shopping-cart-frontend via `port-forward.sh` or Istio ingress
- Tests live in `shopping-cart-e2e-tests/` repo (already has Playwright structure + flow specs)
- Copilot already has Playwright MCP built in — zero extra setup for test generation
- Trigger: manual via Claude/Copilot MCP session, or CI job that installs + runs Playwright

**Hardware note:** M5 Mac mini (Oct 2026) — revisit parallel test execution when hardware upgrades.

**Tool boundary:**
- Playwright MCP → tests apps you own and control
- Google Antigravity → interacts with third-party UIs you cannot control (ACG sandbox — v1.0.0)

---

## k3dm-mcp — Separate Repository (v1.4.0 — after all cloud providers ship)
*Discrete repo: [github.com/wilddog64/k3dm-mcp](https://github.com/wilddog64/k3dm-mcp)*

Lean MCP server wrapping the k3d-manager CLI. Exposes cluster operations as structured MCP
tools callable from any MCP-compatible AI client. Owns its own memory-bank and roadmap.
Ships after v1.1.0–v1.3.0 so the full provider surface (local + all three clouds) is
available from day one.

**Full scope:** see `k3dm-mcp/docs/plans/roadmap.md`

**Key design decisions carried forward from k3d-manager planning:**
- One AI Layer Rule: `K3DM_ENABLE_AI=0` always set in subprocess env
- Explicit subprocess env — no ambient shell state
- SQLite state cache — never dump raw kubectl output to LLM
- Blast radius classification, dry-run gate, pre-destroy snapshot
- Loop detection + session call limit + credential scan on tool args
- BATS-based MCP test harness (env -i, record-replay fixtures)

## v0.8.1 — Trace UI (Optional, k3dm-mcp)
*Focus: Visual observability for local dev — no hard dependencies*

- **Key Feature:** Jaeger trace UI as an opt-in sidecar. Environments without Docker
  continue to use v0.8.0 span file output unchanged.
- **Gating:** `ENABLE_JAEGER=1` — consistent with `ENABLE_OTEL=1` and `ENABLE_TRACE=1`.
  Off by default. Never required. Never assumed.
- **Implementation:**
  - `ENABLE_JAEGER=1 k3dm-mcp start` spins up a single `jaegertracing/all-in-one` container
  - v0.8.0 OTLP span output exported to Jaeger — no instrumentation changes required
  - UI available at `localhost:16686` while MCP server is running
  - Container tears down with the MCP server
- **Capability matrix:**

  | Environment | `ENABLE_OTEL` | `ENABLE_JAEGER` |
  |---|---|---|
  | Bare metal k3s, no Docker | spans to file | not available |
  | Local dev with Docker | spans to file | Jaeger UI |
  | CI pipeline | spans to stdout | not available |
  | Air-gapped | spans to file | not available |
  | External OTLP backend (Tempo, Datadog) | configure OTLP endpoint | not needed |

- **No Grafana:** Jaeger's built-in UI is sufficient for local dev. Grafana/Tempo is
  a shared-team concern, not a local dev tool concern.
- **Dependency:** Docker — optional. k3s/bare metal environments use span file output only.

## v0.9.1 — vCluster Plugin + Playwright E2E in CI
*Focus: Ephemeral tenant clusters for isolated testing*

**Motivation:** Shopping-cart has no real traffic — the value is fast lifecycle, not scale.
Spin up a clean vCluster tenant, deploy the full stack, run Playwright E2E tests, tear it down.
Clean slate every PR run, no shared cluster state pollution.

**Track 1a — vCluster plugin (`scripts/plugins/vcluster.sh`):**
```bash
./scripts/k3d-manager vcluster_create  <name>   # spin up tenant cluster inside host
./scripts/k3d-manager vcluster_destroy <name>   # tear it down
./scripts/k3d-manager vcluster_use     <name>   # switch kubeconfig to tenant
./scripts/k3d-manager vcluster_list            # list active tenant clusters
```
- `VCLUSTER_NAMESPACE` env var — target namespace in host (default: `vclusters`)
- `VCLUSTER_VERSION` env var — pin chart version, no floating `latest`
- Prerequisite check: verify host cluster context is active before any operation
- dry-run gate inherited from `_run_command`
- BATS coverage: `scripts/tests/plugins/vcluster.bats` (`env -i` clean)

**Track 1b — Playwright E2E in CI (`shopping-cart-infra`):**
```
PR opened on any shopping-cart repo
→ CI: vcluster_create shopping-cart-e2e
→ deploy full stack (ESO + shopping-cart-data + apps) into tenant
→ Playwright runs E2E against tenant services
→ pass/fail reported to PR
→ vcluster_destroy shopping-cart-e2e
```
- Playwright runs outside the cluster on the CI runner (no Chrome-in-cluster)
- Tests live in `shopping-cart-e2e-tests/` repo
- Prerequisite: images in ghcr.io (CI stabilization complete ✅)

**Spec:** `docs/plans/v0.9.1-vcluster-plugin.md`

---

## v0.9.0 — Messaging Gateway
*Focus: Natural language interface for cluster operations*

**Motivation:** k3dm-mcp (v0.8.0) exposes cluster ops as MCP tools. v0.9.0 adds a
messaging layer so those tools can be triggered from chat — Slack, Telegram, or any
channel the team already uses. Builds on OpenClaw's architecture concept but with
security-first design: Vault for credentials, blast radius classification enforced,
no raw token storage in config files.

**Key features:**
- Slack-first channel adapter (webhook receiver → intent parser → k3dm-mcp tool call)
- Natural language → deterministic MCP tool mapping (no free-form LLM execution)
- Async notification back to channel: "Deploy complete. Vault unsealed. 7/7 pods healthy."
- Multi-user awareness — team sees operations in shared channel
- Security model inherited from v0.8.0: dry-run gate, blast radius, independent confirmation

**What it is NOT:**
- Not a general-purpose chatbot
- Not a replacement for the CLI — CLI stays the primary interface
- Not a multi-tenant platform — personal/team use only

**Implementation:** Thin TypeScript gateway (Node.js). Shells out to k3dm-mcp via
JSON-RPC stdio. No direct k3d-manager calls — always through the MCP security layer.

---

## v0.9.5 — Service Mesh: Istio Full Activation
*Focus: Activate the dormant Istio mesh — prerequisite for observability and cloud providers*

- STRICT mTLS mesh-wide via `PeerAuthentication`
- `AuthorizationPolicy` replacing payment service `NetworkPolicy` (L7 identity-based, not L4 IP-based)
- Frontend ingress via Istio `Gateway` + `VirtualService`
- `DestinationRule` load balancing per service (LEAST_CONN for order/payment, ROUND_ROBIN for basket/catalog/frontend)
- `ServiceEntry` for external payment gateways (Stripe, PayPal)
- Namespace label fix: `shopping-cart-product-catalog` missing `istio-injection: enabled`
- **Manifests only** — no k3d-manager shell code changes
- **Spec:** `docs/plans/v0.9.5-service-mesh.md`

---

## v0.9.6 — Lab Accessibility: LoadBalancer Services
*Focus: Eliminate port-forward — all UI services reachable via OrbStack LoadBalancer IP*

- `argocd-server` — `server.service.type: LoadBalancer` in `scripts/etc/argocd/values.yaml.tmpl`
- `keycloak` — `service.type: LoadBalancer` in `scripts/etc/keycloak/values.yaml.tmpl`
- `jenkins` — `controller.serviceType: LoadBalancer` in `scripts/etc/jenkins/values-default.yaml.tmpl`
- `shopping-cart-frontend` — `spec.type: LoadBalancer` in `k8s/base/service.yaml`
- LDAP and data-layer services excluded (protocol services, no browser UI)
- **Spec:** `docs/plans/v0.9.6-lab-accessibility.md`

---

## v0.9.7 — Vault Hardening
*Focus: Close the 3 remaining gaps from HashiCorp's 12 capabilities for modern secrets management*

### Gap #7 — Backup / Restore

New plugin functions in `scripts/plugins/vault.sh`:

```bash
./scripts/k3d-manager backup_vault           # snapshot Vault to local file (default: ~/.k3d-manager/vault-snapshots/)
./scripts/k3d-manager backup_vault --s3      # upload snapshot to S3 (requires AWS_S3_BACKUP_BUCKET env var)
./scripts/k3d-manager restore_vault <file>   # restore from snapshot file
```

- Uses `vault operator raft snapshot save` (Raft integrated storage)
- Snapshot file: `vault-snapshot-<YYYYMMDD-HHMMSS>.snap`
- Restore requires Vault to be sealed — `restore_vault` checks and refuses if unsealed
- `--s3` path: `aws s3 cp <snapshot> s3://${AWS_S3_BACKUP_BUCKET}/vault-snapshots/` — credentials via Vault, not env file

### Gap #12 — Audit Logging

Vault audit device enabled during `deploy_vault`:

```bash
vault audit enable file path=/var/log/vault/audit.log
```

- Audit log volume mounted in Vault pod via `extraVolumes` in Helm values template
- Log rotation via `logrotate` config deployed alongside Vault
- `audit_vault_status` function: `vault audit list` — reports enabled devices and file path
- Dev-only exception: audit disabled when `VAULT_DEV_MODE=1`

### Gap #3 — Secrets Scanning

Two layers:

**Pre-commit (local):**
- `gitleaks` added to `.pre-commit-config.yaml` in k3d-manager and all shopping-cart repos (references `github.com/gitleaks/gitleaks` directly — no shared dependency)
- Each repo owns its own `.gitleaks.toml` at repo root (allowlists for test credentials like `alice/password`)
- Blocks commit if secrets pattern detected — no bypass without explicit `SKIP=gitleaks`

**CI gate (`shopping-cart-infra`):**
- `gitleaks/gitleaks-action@v2` step added to `build-push-deploy.yml` — runs before build
- Pinned version — no `@latest`

---

## v0.9.8 — Vault-Managed ArgoCD Deploy Key Rotation
*Focus: Eliminate empty-passphrase SSH deploy keys on disk — move all ArgoCD GitHub repo credentials into Vault*

**Motivation:** Deploy keys with empty passphrases stored on disk are insecure and hard to rotate.
ESO syncs them to Kubernetes secrets; ArgoCD reads from those secrets. No key files on disk.

### Vault Storage

One KV entry per repo:
```
secret/argocd/deploy-keys/shopping-cart-basket
secret/argocd/deploy-keys/shopping-cart-order
secret/argocd/deploy-keys/shopping-cart-payment
secret/argocd/deploy-keys/shopping-cart-product-catalog
secret/argocd/deploy-keys/shopping-cart-frontend
```

New Vault policy: `argocd-deploy-key-reader` — `read` only on `secret/argocd/deploy-keys/*`.

### ESO + ArgoCD Wiring

- One `ExternalSecret` per repo → syncs to `argocd-repo-<name>` secret in `cicd` ns
- ArgoCD reads repo credentials from the Kubernetes secret — no key files on disk

### Plugin Function

New function `configure_vault_argocd_repos` in `scripts/plugins/argocd.sh` (or `vault.sh`):
- Generates fresh ED25519 key pair per repo
- Writes private key to Vault KV
- Uploads public key as GitHub deploy key via `gh api`
- Applies ESO `ExternalSecret` manifest

### Rotation Policy (two-tier)

- **Scheduled — every 24h:** rotate all 5 deploy keys (cron in `shopping-cart-infra` CI or k3d-manager launchd)
- **On `shopping-cart-infra` main merge:** rotate all 5 deploy keys — infra changes are highest-risk event
- **On demand:** `./scripts/k3d-manager argocd_rotate_deploy_keys` — manual escape hatch for suspected compromise
- **Skip:** per-PR rotation on app repos — no infra change, low value, high Vault churn

### Rotation Mechanism

```bash
vault kv put secret/argocd/deploy-keys/<repo> private_key=@<new-key>
# ESO syncs automatically → ArgoCD picks up → update GitHub deploy key
```
One operation. No ArgoCD restart required.

---

## v0.9.9 — Copilot CLI Integration
*Focus: AI-assisted cluster operations via GitHub Copilot CLI — opt-in, zero ambient state*

**Spec:** `docs/plans/v0.6.2-ensure-copilot-cli.md` (written under v0.6.2, re-slotted here)

### New helpers in `scripts/lib/system.sh`

- **`_ensure_node`** — lazy-install Node.js if not present (required by Copilot CLI)
- **`_ensure_copilot_cli`** — lazy-install `@githubnext/github-copilot-cli` via npm; graceful auth failure if `GITHUB_TOKEN` absent
- **`_k3d_manager_copilot`** — scoped passthrough wrapper with deny-tool guardrails; sets `K3DM_ENABLE_AI=0` in subprocess env (One AI Layer Rule)

### Gating

- All Copilot features behind `K3DM_ENABLE_AI=1` — off by default
- Graceful degradation: if Copilot CLI unavailable or unauthenticated, functions return non-fatal warning

### BATS coverage

- `scripts/tests/lib/copilot.bats` — `env -i` clean; tests lazy-install logic, deny-tool enforcement, auth failure path

---

## v1.0.0 — Remote k3s via k3sup (3-node) + AD Plugin (on-prem)
*Focus: Multi-node k3s cluster on ACG + Samba AD DC — production-grade topology at zero cost*

**Motivation:** Single t3.medium at 95% memory capacity is a recurring blocker. ACG allows up to
5 concurrent t3.medium instances. Three nodes gives control-plane isolation, workload distribution,
and a dedicated identity/data tier — matching real k8s topology without managed cloud cost.
Samba AD DC replaces OpenLDAP simulation with real AD behavior, resolving `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES`
dev-only debt and enabling proper Jenkins AD authentication testing.

### Node Layout (3 × t3.medium — ACG)

| Node | Role | Workloads | EBS |
|---|---|---|---|
| Node 1 | Control plane | k3s server, ArgoCD, Vault, ESO | ~10GB |
| Node 2 | App worker | basket, frontend, order, payment, product-catalog | ~10GB |
| Node 3 | Data + Identity | PostgreSQL, RabbitMQ, Redis, **Samba AD DC** | ~10GB |

Total: ~30GB EBS — at ACG limit. Size volumes carefully.

### New CLUSTER_PROVIDER value: `k3s-remote`

```bash
CLUSTER_PROVIDER=k3s-remote ./scripts/k3d-manager deploy_cluster
```

- `_ensure_k3sup` — lazy-install k3sup binary if not present
- `deploy_cluster` for `k3s-remote`:
  1. Calls `bin/acg-sandbox.sh` three times — 3 EC2 instances provisioned, IPs resolved
  2. `k3sup install` on Node 1 — control plane
  3. `k3sup join` on Node 2 + Node 3 — workers join cluster
  4. Renames kubeconfig context to `ubuntu-k3s`
  5. Points server to `https://localhost:6443` (tunnel endpoint — Node 1)
  6. Merges into `~/.kube/config`
- Node taints + labels applied: `node-role=control-plane`, `node-role=app`, `node-role=data`
- `destroy_cluster` — terminates all 3 EC2 instances via `aws ec2 terminate-instances`

### AD Plugin — on-prem (Samba AD DC)

New plugin: `scripts/plugins/activedirectory.sh`

```bash
DIRECTORY_SERVICE_PROVIDER=activedirectory ./scripts/k3d-manager deploy_directory
```

- Deploys `samba-ad-dc` container on Node 3 (identity tier)
- Replaces OpenLDAP simulation with real AD protocol behavior
- Resolves `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` dev-only debt — proper TLS cert from Vault PKI
- Jenkins LDAP plugin points to Samba AD DC — real group membership, nested groups, Kerberos
- Test accounts provisioned via idempotent `samba-tool user create` calls
- `DIRECTORY_SERVICE_PROVIDER=activedirectory` selects this path; `openldap` remains default for local k3d

### SSH Tunnel integration

- `deploy_cluster` starts tunnel automatically after k3s install (`tunnel_start` — Node 1)
- `destroy_cluster` stops tunnel before terminating instances (`tunnel_stop`)

### BATS coverage

- `scripts/tests/plugins/k3s_remote.bats` — `env -i` clean; mocks k3sup and aws CLI calls
- `scripts/tests/plugins/activedirectory.bats` — mocks samba-tool calls, validates idempotency

---

## v1.1.0 — AWS EKS Provider + ACG Sandbox Lifecycle + AD Plugin (AWS Managed AD)
*Focus: First cloud provider — AWS is the most common ACG sandbox*

**Motivation:** The architectural boundary already supports this — `CLUSTER_PROVIDER`
abstracts create/destroy/kubeconfig, and plugins speak only Kubernetes primitives.
Adding EKS means k3d-manager deploys the same Vault + ESO + Istio + ArgoCD stack to
AWS without modification to any plugin.

**New CLUSTER_PROVIDER value:**
- `eks` — AWS EKS via `eksctl` (lazy-loaded on first use)
  - kubeconfig via `aws eks update-kubeconfig`
  - Single t3.medium node — sufficient for full stack on ACG sandbox
  - `AWS_SESSION_TOKEN` support for ACG STS credentials

Cloud credentials handled through Vault — never in config files or CLI args.

**Key use case — ACG AWS sandbox lifecycle:**
```
"Spin up my standard stack on this AWS sandbox"
→ CLUSTER_PROVIDER=eks + STS credentials from ACG
→ deploy_cluster: Vault, ESO, Istio, ArgoCD, OpenLDAP
→ SQLite state: records expiry time from ACG session
→ Slack: "Stack ready on EKS. Sandbox expires in 4h. Auto-teardown reminder set."
→ 30min before expiry: "Sandbox expiring soon. Run destroy_cluster to clean up."
```

**ACG login automation — Google Antigravity:**
ACG has no public API — everything goes through the web UI.
Antigravity automates login and STS credential extraction.
Clean handoff: Antigravity outputs credentials → k3dm-mcp injects into Vault → k3d-manager reads.

**Sandbox lifecycle extensions to SQLite state cache:**
- `sandbox_expiry` column — populated from Antigravity output
- `stale: true` flag extended to cover expired sandboxes
- `sync_state` tool warns when sandbox has < 30min remaining

**AD Plugin — cloud variant (AWS Managed AD):**
- `DIRECTORY_SERVICE_PROVIDER=activedirectory CLOUD_AD_PROVIDER=aws` — targets AWS Managed AD
- Complements v1.0.0 on-prem Samba AD DC; same plugin interface, cloud backend
- Resolves remaining cloud AD TLS debt when running on EKS

**Design spec:** `docs/plans/v1.1.0-multi-cloud-design.md` (EKS + ACG sections)

---

## v1.2.0 — Google GKE Provider
*Focus: Second cloud provider — GCP ACG sandbox support*

**New CLUSTER_PROVIDER value:**
- `gke` — Google GKE via `gcloud container clusters` (lazy-loaded on first use)
  - kubeconfig via `gcloud container clusters get-credentials`
  - Single e2-standard-2 node — sufficient for full stack
  - `GOOGLE_CREDENTIALS_JSON` via process substitution — never written to disk

**ACG GCP sandbox:**
- Service account JSON extracted by Antigravity, injected into Vault
- `gcloud auth activate-service-account --key-file <(echo $GOOGLE_CREDENTIALS_JSON)`

**Design spec:** `docs/plans/v1.1.0-multi-cloud-design.md` (GKE section — implementation phase 2)

---

## v1.3.0 — Azure AKS Provider
*Focus: Third cloud provider — Azure ACG sandbox support*

**New CLUSTER_PROVIDER value:**
- `aks` — Azure AKS via `az aks` (lazy-loaded on first use)
  - kubeconfig via `az aks get-credentials`
  - Single Standard_B2s node (Standard_B2ms preferred if quota allows)
  - Resource group lifecycle: create on deploy, delete on destroy
  - Service principal auth: `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET`, `AZ_TENANT_ID` from Vault

**ACG Azure sandbox:**
- Service principal credentials extracted by Antigravity, injected into Vault

**Design spec:** `docs/plans/v1.1.0-multi-cloud-design.md` (AKS section — implementation phase 3)

**API stability:** v1.3.0 declares the full multi-cloud provider surface stable. Breaking
changes require a major version bump. Bash CLI compatibility maintained for all existing scripts.

**Engineering standards inherited:** spec-first, no ADKs, bash-native plugins,
Zero-Dependency philosophy, `env -i` BATS suites for all new providers.

---

## v1.4.0 — k3dm-mcp
*Focus: MCP server wrapping k3d-manager CLI — AI-driven cluster operations*

**Prerequisite:** All three cloud providers (v1.1.0–v1.3.0) must ship first.
k3dm-mcp wraps the complete provider surface — EKS/GKE/AKS operations exposed as
structured MCP tools alongside local k3d/k3s operations.

**Motivation:** With all providers in place, k3dm-mcp can expose a unified interface
across every cluster target (local → cloud) from any MCP-compatible AI client
(Claude Desktop, Copilot, Gemini CLI).

**Discrete repo:** [`wilddog64/k3dm-mcp`](https://github.com/wilddog64/k3dm-mcp)

**Key design decisions:**
- One AI Layer Rule: `K3DM_ENABLE_AI=0` always set in subprocess env
- Explicit subprocess env — no ambient shell state
- SQLite state cache — never dump raw kubectl output to LLM
- Blast radius classification, dry-run gate, pre-destroy snapshot
- Loop detection + session call limit + credential scan on tool args
- BATS-based MCP test harness (`env -i`, record-replay fixtures)

**MCP tools exposed (initial set):**
- `deploy_cluster` / `destroy_cluster` — works for k3d, k3s, eks, gke, aks
- `deploy_vault`, `deploy_eso`, `deploy_argocd`
- `vcluster_create` / `vcluster_destroy` / `vcluster_use` / `vcluster_list`
- `sync_state` — cluster health snapshot into SQLite

**Full scope:** see `k3dm-mcp/docs/plans/roadmap.md`

---

## Architectural Boundary

**k3d-manager does not compete with Terraform, Pulumi, or any cloud provisioner.**

Those tools own infrastructure provisioning — VPCs, node groups, IAM, networking.
k3d-manager owns what runs *on top of* the cluster — Vault, ESO, Istio, Jenkins, OpenLDAP, ArgoCD.

The handoff point is a kubeconfig:
```
Terraform/Pulumi provisions EKS/GKE/AKS  →  outputs kubeconfig
k3d-manager points at that kubeconfig    →  deploys and configures the service stack
```

**The plugin layer speaks only Kubernetes primitives** (`kubectl`, `helm`) and has no opinion
on what is underneath. A plugin works identically against:
- k3d on a laptop
- k3s on a Ubuntu VM
- EKS, GKE, AKS, Rancher, Talos — any cluster with a valid kubeconfig

`CLUSTER_PROVIDER` controls only three things: create, destroy, and get kubeconfig.
Once those are done — by k3d-manager or by an external provisioner — the provider
abstraction is finished and the plugins take over.

This boundary is intentional and permanent. k3d-manager's value is **dev/staging environment
parity**: the same stack definition runs locally, in staging, and can target production-grade
clusters without modification. That problem is unsolved by Terraform and Pulumi — it is
k3d-manager's lane.

---

## Homelab (Unscheduled — v0.9.x or v1.0.x depending on workload)
*Focus: Remote access to always-on infra cluster — prerequisite for portable development*

**Current state:** Infra cluster runs on M2 Air (no remote access). M4 Air is the dev workstation.
**Target:** M4 Air connects to infra cluster remotely from anywhere — coffee shop, travel, etc.

### WireGuard Setup

- **Phase 1 (now):** M2 Air as WireGuard server — always-on, zero cost
  - M4 Air as client — connects to M2 Air when away from home
  - EC2 optionally added as a peer — all three nodes on same private network
- **Phase 2 (October 2026):** Mac Mini M5 takes over as WireGuard server
  - Copy server config from M2 Air to Mini
  - Update peer configs to point to Mini's IP
  - M2 Air retired from server role

### What this unlocks

- Full k3d-manager development from anywhere with internet
- Infra cluster always reachable — no OrbStack tunnel management when traveling
- Same workflow on M4 Air whether at home or remote

**No timeline committed** — slot into a v0.9.x if workload is light, otherwise v1.0.x.

---

## Engineering Standards
1. **Spec-First:** No new roadmap milestones are implemented without a confirmed investigation and plan.
2. **Checkpointing:** The repository must remain rollback-safe at every stage.
3. **Bash-Native:** AI orchestration must respect the "Zero-Dependency" (or auto-installing dependency) philosophy of the project.
4. **Native Agency (No ADKs):** Explicitly reject heavy Agent Development Kits (e.g., LangChain, CrewAI) to keep the tool lightweight, manageable, and sovereign. All orchestration logic must live in the shell or via lean MCP servers.
