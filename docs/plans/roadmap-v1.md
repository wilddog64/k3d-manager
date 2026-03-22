# k3d-manager Strategic Roadmap

## Vision

k3d-manager is a **kops-for-k3s** — a cluster lifecycle manager for lightweight k3s/k3d
environments. Like kops, it owns its own clusters end-to-end: provision, configure, upgrade,
and destroy. Unlike cloud-managed Kubernetes (EKS, GKE, AKS), k3d-manager targets
environments where you want full control at zero managed-service cost:

- **Local** — k3d on OrbStack (M2/M4 Air, Mac Mini M5)
- **Remote sandbox** — k3s via k3sup on ACG EC2
- **Home lab** — k3s on Mac Mini M5 (planned October 2026)

The plugin layer (Vault, ESO, Istio, ArgoCD, Jenkins, OpenLDAP, Keycloak) deploys
identically against any k3s/k3d cluster. The provider abstraction controls only three
things: create, destroy, and get kubeconfig. Once those are done, plugins take over.

**k3d-manager does not wrap EKS, GKE, or AKS.** Those platforms have excellent dedicated
tooling (eksctl, gcloud, az aks). k3d-manager's value is depth on k3s, not breadth
across clouds.

---

## Currently Shipped

| Version | Highlights |
|---------|-----------|
| v0.9.5 | `deploy_app_cluster` — EC2 k3sup install + kubeconfig merge; replaces manual rebuild |
| v0.9.4 | autossh tunnel plugin, ArgoCD cluster registration, smoke-test gate, `_run_command` TTY fallback |
| v0.9.3 | TTY fix (`_DCRS_PROVIDER` global), lib-foundation v0.3.2 subtree, cluster rebuild smoke test |
| v0.9.2 | vCluster E2E composite actions, 11-finding Copilot hardening |
| v0.9.1 | vCluster plugin, two-tier `--help`, `function test()` refactor |

---

## v0.9.6 — ACG Plugin + Lab Accessibility
*Focus: ACG sandbox lifecycle as a first-class plugin; eliminate port-forward for UI services*

### ACG Plugin (`scripts/plugins/acg.sh`)

Migrate `bin/acg-sandbox.sh` into the dispatcher pattern. Expose ACG sandbox lifecycle
as proper k3d-manager functions:

```bash
./scripts/k3d-manager acg_provision   # launch EC2, configure VPC/SG/key, update SSH config
./scripts/k3d-manager acg_status      # show instance state, TTL, credentials validity
./scripts/k3d-manager acg_extend      # Antigravity TTL +4h (browser UI automation)
./scripts/k3d-manager acg_teardown    # terminate instance, clean kubeconfig entry
```

- `acg_provision` absorbs all logic from `bin/acg-sandbox.sh`
- `acg_extend` integrates Antigravity to automate the ACG web UI TTL extension
- `bin/acg-sandbox.sh` retired after migration
- BATS coverage: `scripts/tests/plugins/acg.bats` (`env -i` clean; mocks aws CLI and Antigravity calls)

### Lab Accessibility (LoadBalancer Services)

Eliminate port-forward for all UI services on the infra cluster:

- `argocd-server` — `server.service.type: LoadBalancer` in `scripts/etc/argocd/values.yaml.tmpl`
- `keycloak` — `service.type: LoadBalancer` in `scripts/etc/keycloak/values.yaml.tmpl`
- `jenkins` — `controller.serviceType: LoadBalancer` in `scripts/etc/jenkins/values-default.yaml.tmpl`
- LDAP and data-layer services excluded (protocol services, no browser UI)
- Frontend LoadBalancer deferred to v1.0.0 (pod not schedulable on single t3.medium)

### Code Quality
- [ ] **Upstream lib edits to lib-foundation** — `system.sh` (TTY fix + `_run_command_resolve_sudo`) + `agent_rigor.sh` (allowlist feature) → subtree pull back
- [ ] **`bin/` script consistency** — `bin/smoke-test-cluster-health.sh` needs `_kubectl`/`_run_command`
- [ ] **Relocate app-layer bug tracking** — file shopping-cart bugs as GitHub Issues in their repos

---

## v1.0.0 — Multi-Node k3s Cluster + Samba AD
*Focus: 3-node k3sup cluster on ACG — resolves single t3.medium resource exhaustion*

**Motivation:** Single t3.medium (4GB) at 95% capacity is a structural blocker for
all 5 shopping-cart pods. ACG allows up to 5 concurrent t3.medium instances. Three nodes
gives control-plane isolation, workload distribution, and a dedicated identity/data tier —
matching real k8s topology at zero cost.

### Node Layout (3 × t3.medium — ACG)

| Node | Role | Workloads |
|------|------|-----------|
| Node 1 | Control plane | k3s server, ArgoCD, Vault, ESO |
| Node 2 | App worker | basket, frontend, order, payment, product-catalog |
| Node 3 | Data + Identity | PostgreSQL, RabbitMQ, Redis, Samba AD DC |

### New CLUSTER_PROVIDER value: `k3s-remote`

```bash
CLUSTER_PROVIDER=k3s-remote ./scripts/k3d-manager deploy_cluster
```

- `deploy_cluster` calls `acg_provision` three times → 3 EC2 instances
- `k3sup install` on Node 1 (control plane)
- `k3sup join` on Node 2 + Node 3 (workers)
- Node taints + labels applied
- Tunnel started automatically (`tunnel_start` — Node 1)
- Kubeconfig merged as `ubuntu-k3s`

```bash
CLUSTER_PROVIDER=k3s-remote ./scripts/k3d-manager destroy_cluster
# terminates all 3 EC2 instances, stops tunnel, removes kubeconfig context
```

### Samba AD DC Plugin

```bash
DIRECTORY_SERVICE_PROVIDER=activedirectory ./scripts/k3d-manager deploy_directory
```

- Deploys `samba-ad-dc` container on Node 3
- Replaces OpenLDAP simulation with real AD protocol behavior
- Resolves `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` dev-only debt
- `DIRECTORY_SERVICE_PROVIDER=openldap` remains the default for local k3d

### Milestone Gate

All 5 shopping-cart pods Running + Playwright E2E green = v1.0.0 done.

---

## v1.1.0 — Full Stack Provisioning (Single Command)
*Focus: One command brings up k3s cluster + complete plugin stack*

```bash
CLUSTER_PROVIDER=k3s-remote ./scripts/k3d-manager provision_full_stack
# acg_provision × N → deploy_cluster → deploy_vault → deploy_eso → deploy_istio
# → deploy_argocd → register_app_cluster → shopping-cart apps synced
```

- `provision_full_stack` orchestrates the complete lifecycle in sequence
- Idempotent — safe to re-run after partial failure
- `teardown_full_stack` — inverse: destroy apps → deregister → destroy cluster → acg_teardown × N

---

## v1.2.0 — k3dm-mcp
*Focus: MCP server wrapping k3d-manager CLI — AI-driven cluster operations*

**Gate:** v1.0.0 multi-node proven. k3d (local) + k3s-remote (ACG) = two backends,
enough surface for a useful provider-agnostic MCP API.

**Discrete repo:** `wilddog64/k3dm-mcp`

**MCP tools (initial set):**
- `deploy_cluster` / `destroy_cluster` — k3d + k3s-remote
- `deploy_vault`, `deploy_eso`, `deploy_argocd`
- `acg_provision`, `acg_extend`, `acg_teardown`
- `sync_state` — cluster health snapshot

**Transport:** HTTP (default), stdio (optional). `K3DM_MCP_TRANSPORT=http|stdio`.

**Key design invariants:**
- One AI Layer Rule: `K3DM_ENABLE_AI=0` in all subprocess envs
- No raw kubectl output to LLM — SQLite state cache only
- Blast radius classification on every mutating tool
- Dry-run gate before any destructive operation

---

## v1.3.0 — Home Lab (Mac Mini M5)
*Focus: k3s on Mac Mini M5 as always-on home cluster*

**Target hardware:** Mac Mini M5 (October 2026)

**New `CLUSTER_PROVIDER` value:** `k3s-local-arm64`

- k3s installed natively on Mac Mini via k3sup (loopback — `k3sup install --host localhost`)
- Always-on: launchd service, starts on boot
- WireGuard peer — M4 Air connects remotely from anywhere
- Home automation plugins: Home Assistant, Mosquitto MQTT, Node-RED, InfluxDB, Grafana, Zigbee2MQTT
- Managed by k3d-manager the same way as ACG EC2 — same plugin interface

**`homehub-mcp`** (separate repo) — home automation operations via MCP.
Not merged into `k3dm-mcp` — separate concern, separate lifecycle.

---

## Architectural Boundary

**k3d-manager owns k3s/k3d clusters end-to-end.** It does not wrap EKS, GKE, or AKS.
For cloud-managed Kubernetes, use eksctl, gcloud, or az aks — they are better tools
for that job. k3d-manager's lane is lightweight k3s at zero managed-service cost,
with an opinionated plugin stack that runs identically in every environment it supports.

`CLUSTER_PROVIDER` controls only: create, destroy, get kubeconfig.
Once those are done — plugins take over. Plugins speak only Kubernetes primitives
(`kubectl`, `helm`) and have no opinion on what is underneath.

---

## Engineering Standards

1. **Spec-first** — no milestone implemented without a plan doc in `docs/plans/`
2. **Rollback-safe** — repository must be deployable at every commit on main
3. **Bash-native** — no heavy frameworks; all orchestration in shell or lean MCP servers
4. **No ADKs** — reject LangChain, CrewAI, and similar. Sovereign, auditable tooling only
5. **Max 5 plan docs per release** — if a milestone exceeds 5 specs, split before writing a 6th
6. **BATS coverage required** — every new plugin function needs `env -i` clean BATS tests
