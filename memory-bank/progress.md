# Progress — k3d-manager

## Overall Status

**v0.9.3 SHIPPED** — squash-merged to main (8046c73), PR #36, 2026-03-16. Tagged + released.
**v0.9.4 ACTIVE** — branch cut from main 2026-03-16.

---

## What Is Complete

### v0.9.4 — active

- [ ] **Safety gate audit** — `deploy_*` functions (deploy_vault, deploy_jenkins, etc.) called with no args should print help/usage, NOT trigger actual deployment. Test all `deploy_*` entry points. Accidental invocation is a live risk.
- [ ] **`--dry-run` / `-n` mode** — all `deploy_*` functions should print every command that would run without executing. Easy cases: `kubectl apply --dry-run=client`, `helm install --dry-run`. Hard cases (Vault init, LDAP bootstrap): print commands only, no outcome validation. Do in same pass as safety gate audit.
- [ ] **`plan` mode (terraform plan equivalent)** — prototype with Vault first (easiest: `vault status` JSON, `helm status`, `kubectl get pods` all queryable without side effects). Output: per-component ✓/✗ with what will run vs already done. Extend to Jenkins, ESO, ArgoCD after Vault proven. copilot-cli scaffolds boilerplate; Codex implements state-query logic.
- [x] README releases table — v0.9.3 added — commit `1e3a930`
- [x] lib-foundation v0.3.3 subtree pull — commit `7684266`
- [x] Multi-arch workflow pin — ALL 5 app repos merged to main 2026-03-18
- [x] ArgoCD cluster registration fix — manual cluster secret `cluster-ubuntu-k3s` with `insecure: true`
- [x] Missing `frontend` manifest — `argocd/applications/frontend.yaml` in shopping-cart-infra (PR #17)
- [x] Verify `ghcr-pull-secret` — present in `apps`, `data`, `payment` namespaces
- [x] Tag refresh for ARM64 images — `newTag: latest` in all 5 repos
- [x] Codex: kubeconfig merge automation — commit `6699ce8`
- [x] payment-service missing Secrets — PR #14 merged (9d9de98); `payment-db-credentials` + `payment-encryption-secret` in `shopping-cart-payment/k8s/base/secret.yaml`

---

## What Is Pending

### v0.9.4 — active

- [x] **Gemini: rebuild Ubuntu k3s + E2E verification** — commit `7d614bc`
- [x] **Gemini: ArgoCD cluster registration + app sync** — commit `7d614bc`
- [x] Force ArgoCD sync — order-service + product-catalog — verified
- [x] **Codex: fix `instsudo` typo** — `scripts/lib/system.sh` line 850; commit `ef57b0f` (2026-03-20)
- [x] **autossh tunnel plugin** — Codex delivered autossh-backed tunnel plugin + BATS coverage per `docs/plans/v0.9.4-codex-autossh-tunnel-plugin.md`; commands exposed via `tunnel_start|stop|status`; commit msg: `feat(tunnel): add autossh tunnel plugin with launchd boot persistence`
- [x] **ArgoCD cluster registration automation** — Codex delivered `register_app_cluster`, cluster-secret template, and vars per `docs/plans/v0.9.4-codex-argocd-cluster-registration.md`; replaces manual secret creation; commit msg: `feat(argocd): add register_app_cluster to automate ubuntu-k3s cluster secret`
- [x] **Smoke tests** — Codex added `bin/smoke-test-cluster-health.sh` per `docs/plans/v0.9.4-codex-smoke-test-cluster-health.md`; command enforces ghcr secret, ArgoCD sync, and pod counts before sign-off
- [x] **Codex: reduce replicas to 1 + remove HPAs** — merged to main 2026-03-20; basket `f55effe` (#9), order `98b2f0b` (#13), payment `da0646f` (#15 → v0.1.1), product-catalog `41acad6` (#13), frontend `a9a1b70` (#8)
- [ ] Confirm all 5 pods `Running` on Ubuntu k3s — basket: CrashLoopBackOff (data layer Redis/RabbitMQ not deployed to Ubuntu k3s); payment: pending ArgoCD sync of secret
- [x] **Fix `_run_command` non-interactive sudo failure after VM restart** — Codex implemented `_run_command_has_tty`, interactive sudo fallbacks, and regression tests per `docs/plans/v0.9.4-codex-run-command-tty-sudo-fallback.md`; issue: `docs/issues/2026-03-19-run-command-non-interactive-sudo-failure.md`; commit msg: `fix(system): fall back to interactive sudo when sudo -n unavailable and TTY present`
- [ ] Re-enable `shopping-cart-e2e-tests` scheduled run — after pods Running
- [ ] Playwright E2E green — milestone gate
- [ ] Re-enable `enforce_admins` on shopping-cart-payment main branch

### tax-returns — pending (after quota reset 2026-03-21)

- [ ] Full pipeline script: pdf-to-text → populate 1040 template → run solver → generate PDF
  - Simple version first: solver + PDF generation only (manual template fill)
  - Full parser (W-2/1099 field mapping) as follow-up

### Roadmap (revised 2026-03-18)

- v1.1.0 — EKS (first cloud provider; AWS most mature)
  - **AD plugin: AWS Managed AD** — `DIRECTORY_SERVICE_PROVIDER=aws-managed-ad`; resolves `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` dev debt; proper CA trust + Vault LDAP secrets engine + Keycloak sync
  - **Longhorn storage plugin** — `deploy_longhorn`; replaces local-path storage for stateful workloads (PostgreSQL, Redis, RabbitMQ); replicates PVCs across nodes; enables pod rescheduling on node failure; critical for multi-node EKS/GKE/AKS HA
  - Enable Vault audit backend by default in k3d-manager Vault plugin (`vault audit enable file`) — every secret read/write/rotation logged; currently not explicitly enabled
  - Enforce GitOps-only ConfigMap/Secret changes — no direct `kubectl edit`; git history is the audit trail
  - Spring Boot config change flow: update ConfigMap in shopping-cart-infra git → PR → review → merge → ArgoCD syncs → spring-cloud-kubernetes detects file change → `@RefreshScope` reloads beans → no restart, full audit trail (who/when/what/why/approval all in git)
  - Test suite expansion (EKS phase):
    - BATS — k3d-manager plugin logic for volume mount + hot-reload setup
    - Playwright E2E — config change scenario: update ConfigMap in git → verify app behavior changes without pod restart
    - Gemini verification — ArgoCD sync completed, pod stayed Running throughout
    - Admission webhook or audit check — direct `kubectl edit configmap` attempt caught/blocked
  - Upgrade shopping-cart deployments: `secretKeyRef` env vars → volume mounts + file watching (zero-restart secret rotation)
  - Upgrade ConfigMap injection: `configMapKeyRef` env vars → volume mounts + `spring-cloud-kubernetes` library for `@RefreshScope` auto-reload (no pod restart on ConfigMap update)
  - IRSA for pod-level AWS credentials
  - Vault dynamic secrets + short TTL — meaningful only when rotation doesn't require restarts
- v1.2.0 — k3dm-mcp (gate: EKS delivered; k3d + EKS = two backends)
- v1.3.0 — GKE (ships into working MCP framework)
- v1.4.0 — AKS (known blocker: AADSTS130507)
- v1.1.0 — **GitHub Actions OIDC** for ghcr.io pulls — keyless auth, eliminates PAT entirely for CI; needs workflow changes in all 5 shopping-cart repos + IRSA already in scope for EKS
- v1.5.0 — vCluster

### v0.9.5 — planned

- [ ] Service mesh — Istio full activation
- [ ] `PeerAuthentication` / `AuthorizationPolicy` / `Gateway`
- Spec: `docs/plans/v0.9.5-service-mesh.md`
- [ ] **`deploy_app_cluster` via k3sup** — remote k3s install + kubeconfig merge from M4 in one command; eliminates manual SSH into EC2; issue: `docs/issues/2026-03-20-k3s-remote-deploy-via-k3sup.md`
- [ ] **sudo whitelist** — `scripts/etc/sudoers/k3d-manager` template installed during `deploy_cluster` bootstrap; `NOPASSWD` scoped to exact k3d-manager commands only (mkdir, cp, chmod, systemctl for k3s); eliminates need for warm sudo timestamp on fresh VM
- [ ] **Vault backup/restore** — `backup_vault` / `restore_vault` commands using `vault operator raft snapshot`; run before any destructive VM operation; eliminates manual PAT re-provisioning after cluster wipe
- [ ] **GitHub PAT rotation reminder** — current PAT expires 2026-04-12; rotate and re-store in Vault at `secret/github/pat-read-packages` before expiry

### k3dm-mcp tool surface (notes for when we get there)

- `k3dm.cluster.status()` — cluster health
- `k3dm.argocd.sync("app")` — trigger ArgoCD sync
- `k3dm.argocd.diff("app")` — plan before sync (wraps `argocd app diff`); supports `--all`
- `k3dm.vault.status()` — Vault health, initialized/sealed state
- Pattern: diff before sync — same discipline as terraform plan/apply

### v1.5.0 — planned

- [ ] vCluster support — multi-tenant topology on k3d
- [ ] ArgoCD targeting vClusters as registered clusters
- [ ] ESO + Vault across vCluster boundaries
- [ ] Istio mesh span/isolation across vClusters
- [ ] Re-engage Loft Labs contact when ready

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| frontend CrashLoopBackOff | OPEN | nginx permissions issue (`mkdir /var/cache/nginx/client_temp` failed) |
| order/product-catalog CrashLoopBackOff | OPEN | Data layer (PostgreSQL) missing on app cluster; pod logs show `UnknownHostException` |
| basket-service CrashLoopBackOff | OPEN | Data layer (Redis `shopping-cart-data` ns, RabbitMQ) not deployed to Ubuntu k3s |
| SSH Tunnel timeouts | OPEN | Frequent connection resets during heavy ArgoCD sync; requires `ServerAliveInterval` or `screen` for stability |
| Vault Kubernetes auth over tunnel | FIXED | Using reverse SSH tunnel to bridge connectivity from app cluster back to infra cluster |
