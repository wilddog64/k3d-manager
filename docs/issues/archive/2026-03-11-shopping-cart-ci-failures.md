# Issue: Shopping Cart CI Publish Job Failures

**Discovered:** 2026-03-11
**First failure date:** 2026-03-09
**Status:** OPEN — all 5 service repos affected
**Milestone:** v0.8.0 — Shopping Cart CI Stabilization

---

## Summary

All 5 shopping cart service repos have failing CI Publish jobs since March 9, 2026.
The pattern is consistent: **Test/Build job passes, Publish job fails.**
This blocks image delivery to ghcr.io → blocks ArgoCD GitOps sync → causes `ImagePullBackOff`
on the Ubuntu app cluster.

Root causes are **different per repo** — not a single shared failure.

---

## Root Cause per Repo

### 1. shopping-cart-basket (Go) — Trivy install failure
**Failing step:** `Publish / build-push` → Trivy scanner installation
**Error:**
```
aquasecurity/trivy info found version: 0.60.0 for v0.60.0/Linux/64bit
##[error]Process completed with exit code 1.
```
**Root cause:** Custom Trivy install script (`bash ./trivy/contrib/install.sh`) in the reusable
workflow fails silently. The install script is failing during binary download.
**Fix:** Replace custom install script with `aquasecurity/trivy-action@0.30.0` in
`shopping-cart-infra/.github/workflows/build-push-deploy.yml`.
**Affects:** basket + product-catalog (both use same reusable workflow at same pinned commit)

---

### 2. shopping-cart-order (Java) — Missing Maven dependency
**Failing step:** `Build & Test` → `Build with Maven`
**Error:**
```
[ERROR] Could not resolve dependencies for project com.shoppingcart:shopping-cart-order
[ERROR] dependency: com.shoppingcart:rabbitmq-client:jar:1.0.0-SNAPSHOT
[ERROR] Could not find artifact com.shoppingcart:rabbitmq-client:jar:1.0.0-SNAPSHOT
```
**Root cause:** `rabbitmq-client-java` library is declared as a Maven dependency but never
published to any accessible Maven repository (local `mvn install` doesn't help in CI).
**Fix:** Publish `rabbitmq-client-java` to GitHub Packages, or restructure as a multi-module
Maven project, or add a CI step to build + install the library before building order service.
**Affects:** shopping-cart-order only

---

### 3. shopping-cart-payment (Java) — Maven wrapper init failure
**Failing step:** `Build and Test` → `Build with Maven`
**Error:**
```
Downloading Maven Wrapper...
-Dmaven.multiModuleProjectDirectory system property is not set.
##[error]Process completed with exit code 1.
```
**Root cause:** Maven wrapper (`mvnw`) fails to initialize — either the wrapper binary is
missing from the repo or the system property needs to be set explicitly.
**Fix:** Verify `mvnw` and `.mvn/wrapper/maven-wrapper.properties` are committed. If present,
add `-Dmaven.multiModuleProjectDirectory=.` to the Maven command in the CI workflow.
**Affects:** shopping-cart-payment only

---

### 4. shopping-cart-product-catalog (Python) — Trivy install failure
**Failing step:** `Publish / build-push` → Trivy scanner installation
**Error:** Same as basket (identical reusable workflow, same pinned commit)
**Fix:** Same as basket — fix reusable workflow in shopping-cart-infra.
**Affects:** basket + product-catalog (shared fix)

---

### 5. shopping-cart-frontend (React/TS) — ESLint + TypeScript errors
**Failing steps:** `Lint → Run ESLint` + `Type Check → Run TypeScript compiler`
**Errors:**
```
ESLint:
- src/components/layout/Header.tsx: 'Package' is defined but never used
- src/components/layout/ProtectedRoute.tsx: 'Navigate' is defined but never used
- src/stores/cartStore.ts: 'CartItem' is defined but never used

TypeScript:
- src/config/api.ts: Property 'env' does not exist on type 'ImportMeta'
- src/config/auth.ts: Property 'env' does not exist on type 'ImportMeta'
  (missing vite/client type definitions in tsconfig.json)
```
**Fix:**
1. Remove unused imports in Header.tsx, ProtectedRoute.tsx, cartStore.ts
2. Add `"types": ["vite/client"]` to `tsconfig.json` compilerOptions
**Affects:** shopping-cart-frontend only

---

## Dependency Chain

Fixing CI unblocks the full delivery pipeline:

```
CI Publish passes
  → Docker images pushed to ghcr.io
    → ArgoCD detects new image tag (kustomize update)
      → ArgoCD syncs to Ubuntu k3s app cluster
        → ImagePullBackOff resolved
          → Shopping cart services running end-to-end
```

---

## Fix Priority

| Repo | Fix effort | Shared fix | Priority |
|---|---|---|---|
| basket + product-catalog | Low — one workflow change | Yes (fix once in infra repo) | P1 |
| frontend | Low — remove unused imports + tsconfig | No | P1 |
| payment | Low-Medium — verify/fix mvnw | No | P2 |
| order | Medium — publish rabbitmq-client-java | No | P2 |

P1 fixes unblock 3 of 5 services immediately (basket, product-catalog, frontend).
P2 fixes complete the pipeline for order and payment.

---

## Reusable Workflow Note

All service repos reference the reusable workflow at a pinned commit:
```
wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@981008c46c2fd1462c32a4ae51c561c60ee13042
```
The Trivy fix must be applied in `shopping-cart-infra` and the caller workflows
in basket and product-catalog updated to the new commit hash.

---

## Agent Assignment (when ready to fix)

| Fix | Suggested agent | Notes |
|---|---|---|
| Trivy install (infra workflow) | Codex | Single file edit in shopping-cart-infra |
| Frontend unused imports + tsconfig | Codex | Isolated, no cluster dependency |
| Payment mvnw fix | Codex | Verify file presence, fix workflow |
| Order rabbitmq-client dependency | Codex | May require GitHub Packages setup |
