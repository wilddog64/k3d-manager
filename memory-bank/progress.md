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
- [x] ArgoCD cluster registration fix — **COMPLETE**
  - Manual cluster secret `cluster-ubuntu-k3s` in `cicd` ns.
  - Configured with `insecure: true` for `host.k3d.internal` support.
  - Successfully registered `ubuntu-k3s` cluster in ArgoCD.
- [x] Missing `frontend` manifest — **COMPLETE**
  - Created `argocd/applications/frontend.yaml` in `shopping-cart-infra`.
  - Opened PR #17; applied manually to cluster.
- [x] Verify `ghcr-pull-secret` — **COMPLETE**
  - Verified presence in `shopping-cart-apps`, `shopping-cart-data`, `shopping-cart-payment`.
- [x] Tag refresh for ARM64 images — **COMPLETE**
  - Verified `newTag: latest` in all 5 app repositories.
  - Created PR #9 for `shopping-cart-basket` to align tags.
- [x] Codex: kubeconfig merge automation — commit `6699ce8`

---

## What Is Pending

### v0.9.4 — active

- [x] Fix payment-service missing Secrets — Codex COMPLETE (66c9eac); `payment-db-credentials` + `payment-encryption-secret` added to `shopping-cart-payment/k8s/base/secret.yaml`; branch: `fix/payment-missing-secrets` — pending PR + ArgoCD sync
- [ ] Force ArgoCD sync for order-service + product-catalog — **HIGH PRIORITY** — resources exist in git but sync Unknown due to tunnel; Gemini to run `argocd app sync`
- [ ] Wait for all apps to reach `Synced` + `Healthy` — blocked by missing Secrets/ConfigMaps above
- [ ] Confirm all 5 pods `Running` on Ubuntu k3s — currently: basket CrashLoopBackOff (163 restarts), order 1/2 Running+Error, product-catalog CrashLoopBackOff, payment ImagePullBackOff
- [ ] Re-enable `shopping-cart-e2e-tests` scheduled run — after pods Running
- [ ] Playwright E2E green in CI — milestone gate

### v0.9.5 — planned

- [ ] Service mesh — Istio full activation
- [ ] `PeerAuthentication` / `AuthorizationPolicy` / `Gateway`
- Spec: `docs/plans/v0.9.5-service-mesh.md`

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| Missing Secrets/ConfigMaps on Ubuntu k3s | OPEN | `CreateContainerConfigError` + `CrashLoopBackOff` on all 5 services; ESO not configured for app namespaces; see `docs/issues/2026-03-18-shopping-cart-missing-secrets-configmaps.md` |
| SSH Tunnel timeouts | OPEN | Frequent connection resets during heavy ArgoCD sync; requires `ServerAliveInterval` or `screen` for stability |
| ArgoCD cluster registration over tunnel | FIXED | Using manual cluster secret pointing to `https://host.k3d.internal:6443` with `insecure: true` |
| Vault Kubernetes auth over tunnel | KNOWN | CA cert validation fails over SSH tunnel; use static Vault token with `eso-reader` policy as fallback |
