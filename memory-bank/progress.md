# Progress — k3d-manager

## Overall Status

**v0.9.3 SHIPPED** — squash-merged to main (8046c73), PR #36, 2026-03-16. Tagged + released.
**v0.9.4 ACTIVE** — branch cut from main 2026-03-16.

---

## v0.9.4 — Completed

- [x] README releases table — v0.9.3 added — `1e3a930`
- [x] lib-foundation v0.3.3 subtree pull — `7684266`
- [x] Multi-arch workflow pin — all 5 app repos merged to main 2026-03-18
- [x] ArgoCD cluster registration fix — manual cluster secret `cluster-ubuntu-k3s` with `insecure: true`
- [x] Missing `frontend` manifest — `argocd/applications/frontend.yaml` in shopping-cart-infra (PR #17)
- [x] Verify `ghcr-pull-secret` — present in `apps`, `data`, `payment` namespaces
- [x] Tag refresh for ARM64 images — `newTag: latest` in all 5 repos
- [x] Codex: kubeconfig merge automation — `6699ce8`
- [x] payment-service missing Secrets — PR #14 merged (9d9de98)
- [x] Fix `_run_command` non-interactive sudo failure — `fix(system): fall back to interactive sudo when sudo -n unavailable and TTY present`; issue: `docs/issues/2026-03-19-run-command-non-interactive-sudo-failure.md`
- [x] autossh tunnel plugin — `feat(tunnel): add autossh tunnel plugin with launchd boot persistence`; spec: `docs/plans/v0.9.4-codex-autossh-tunnel-plugin.md`
- [x] ArgoCD cluster registration automation — `register_app_cluster` + cluster-secret template; spec: `docs/plans/v0.9.4-codex-argocd-cluster-registration.md`
- [x] Smoke tests — `bin/smoke-test-cluster-health.sh`; spec: `docs/plans/v0.9.4-codex-smoke-test-cluster-health.md`
- [x] Reduce replicas to 1 + remove HPAs — merged 2026-03-20: basket `f55effe` (#9), order `98b2f0b` (#13), payment `da0646f` (#15), product-catalog `41acad6` (#13), frontend `a9a1b70` (#8)
- [x] Fix frontend nginx CrashLoopBackOff — `65b354f` merged to main 2026-03-21; tagged v0.1.1
- [x] Gemini: rebuild Ubuntu k3s + E2E verification — `7d614bc`
- [x] Gemini: ArgoCD cluster registration + app sync — `7d614bc`
- [x] Force ArgoCD sync — order-service + product-catalog — verified
- [x] Codex: fix `instsudo` typo — `scripts/lib/system.sh` line 850; `ef57b0f` (2026-03-20)

---

## v0.9.4 — Pending

- [ ] **Safety gate audit** — `deploy_*` functions called with no args should print help, NOT trigger deployment. Test all `deploy_*` entry points.
- [ ] **`--dry-run` / `-n` mode** — all `deploy_*` print every command without executing. Easy: `kubectl apply --dry-run=client`, `helm install --dry-run`. Hard (Vault init, LDAP bootstrap): print commands only.
- [ ] **`plan` mode** — prototype with Vault first (`vault status`, `helm status`, `kubectl get pods`). Output: per-component ✓/✗. Extend to Jenkins, ESO, ArgoCD after Vault proven.
- [ ] Confirm all 5 pods `Running` on Ubuntu k3s — basket/order/product-catalog: CrashLoopBackOff (data layer not deployed)
- [x] **Gemini: verify frontend pod Running** — Pod `frontend-85969b4bf-zq9st` is `Running` on ubuntu-k3s; manually patched with `emptyDir` volumes
- [ ] Re-enable `shopping-cart-e2e-tests` scheduled run — after pods Running
- [ ] Playwright E2E green — milestone gate
- [ ] Re-enable `enforce_admins` on shopping-cart-payment main branch

---

## v0.9.5 — Planned

- [ ] Service mesh — Istio full activation; `PeerAuthentication` / `AuthorizationPolicy` / `Gateway`; spec: `docs/plans/v0.9.5-service-mesh.md`
- [ ] **`deploy_app_cluster` via k3sup** — remote k3s install + kubeconfig merge from M4 in one command; issue: `docs/issues/2026-03-20-k3s-remote-deploy-via-k3sup.md`
- [ ] **sudo whitelist** — `scripts/etc/sudoers/k3d-manager` template installed during `deploy_cluster` bootstrap; `NOPASSWD` scoped to exact k3d-manager commands only; eliminates warm sudo timestamp requirement
- [ ] **Vault backup/restore** — `backup_vault` / `restore_vault` via `vault operator raft snapshot`; run before destructive VM operations
- [ ] **GitHub PAT rotation** — expires 2026-04-12; rotate and re-store in Vault at `secret/github/pat-read-packages`

---

## Roadmap

- **v1.1.0** — EKS provider + ACG lifecycle
  - AD plugin: AWS Managed AD (`DIRECTORY_SERVICE_PROVIDER=aws-managed-ad`; resolves `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` dev debt)
  - Longhorn storage plugin (`deploy_longhorn`; replaces local-path; PVC replication; HA)
  - Vault audit backend enabled by default (`vault audit enable file`)
  - GitOps-only ConfigMap/Secret changes; Spring Boot `@RefreshScope` hot-reload via spring-cloud-kubernetes
  - Upgrade deployments: `secretKeyRef` env vars → volume mounts + file watching (zero-restart secret rotation)
  - IRSA for pod-level AWS credentials; Vault dynamic secrets + short TTL
  - GitHub Actions OIDC for ghcr.io pulls — keyless auth, eliminates PAT
  - BATS + Playwright E2E + Gemini verification + admission webhook for config change scenario
- **v1.2.0** — k3dm-mcp (gate: EKS delivered; k3d + EKS = two backends)
- **v1.3.0** — GKE + AD plugin: Google Cloud Identity
- **v1.4.0** — AKS (known blocker: AADSTS130507)
- **v1.5.0** — vCluster: multi-tenant topology, ArgoCD targeting vClusters, ESO+Vault across boundaries, Istio isolation; re-engage Loft Labs when ready

### k3dm-mcp tool surface (notes for when we get there)

- `k3dm.cluster.status()`, `k3dm.argocd.sync("app")`, `k3dm.argocd.diff("app")`, `k3dm.vault.status()`
- Pattern: diff before sync — same discipline as terraform plan/apply

---

## tax-returns — Pending

- [ ] Full pipeline: pdf-to-text → populate 1040 template → run solver → generate PDF
  - Simple version first: solver + PDF generation only (manual template fill)
  - Full parser (W-2/1099 field mapping) as follow-up

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| frontend CrashLoopBackOff | FIXED | Manually patched with `emptyDir` volumes; permanent fix needed in repo |
| order/product-catalog CrashLoopBackOff | OPEN | PostgreSQL missing on app cluster; `UnknownHostException` in pod logs |
| basket-service CrashLoopBackOff | OPEN | Redis (`shopping-cart-data` ns) + RabbitMQ not deployed to Ubuntu k3s |
| SSH Tunnel timeouts | OPEN | Connection resets during heavy ArgoCD sync; needs `ServerAliveInterval` or `screen` |
