# Progress — k3d-manager

## Overall Status

**v0.9.3 SHIPPED** — squash-merged to main (8046c73), PR #36, 2026-03-16. Tagged + released.
**v0.9.4 ACTIVE** — branch cut from main 2026-03-16.

---

## What Is Complete

### v0.9.4 — active

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

- [ ] Force ArgoCD sync — order-service + product-catalog — Gemini: `argocd app sync order-service && argocd app sync product-catalog`
- [ ] Confirm all 5 pods `Running` on Ubuntu k3s — basket: CrashLoopBackOff (data layer Redis/RabbitMQ not deployed to Ubuntu k3s); payment: pending ArgoCD sync of secret
- [ ] Re-enable `shopping-cart-e2e-tests` scheduled run — after pods Running
- [ ] Playwright E2E green — milestone gate
- [ ] Re-enable `enforce_admins` on shopping-cart-payment main branch

### v0.9.5 — planned

- [ ] Service mesh — Istio full activation
- [ ] `PeerAuthentication` / `AuthorizationPolicy` / `Gateway`
- Spec: `docs/plans/v0.9.5-service-mesh.md`

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| basket-service CrashLoopBackOff | OPEN | Data layer (Redis `shopping-cart-data` ns, RabbitMQ) not deployed to Ubuntu k3s; separate issue from missing Secrets |
| SSH Tunnel timeouts | OPEN | Frequent connection resets during heavy ArgoCD sync; requires `ServerAliveInterval` or `screen` for stability |
| Vault Kubernetes auth over tunnel | KNOWN | CA cert validation fails over SSH tunnel; use static Vault token with `eso-reader` policy as fallback |
