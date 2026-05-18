# Bug: ArgoCD SSO login fails — invalid_scope: groups not defined as Keycloak client scope

**Branch:** `k3d-manager-v1.4.7`
**Work repo:** `shopping-cart-infra` — branch `fix/argocd-groups-scope`
**File:** `argocd/config/argocd-cm.yaml`

---

## Before You Start

```
git checkout -b fix/argocd-groups-scope origin/main
```

Read this spec in full before touching any file.

---

## Problem

ArgoCD SSO login via Keycloak fails with:

```
invalid_scope: Invalid scopes: openid profile email groups
```

`argocd-cm.yaml` lists `groups` in `requestedScopes`. Keycloak rejects this because
`groups` is not defined as a client scope in the realm — the ArgoCD Keycloak client has
a `groups` **protocol mapper** (adds the `groups` claim to the token) but a mapper is
not a scope. Keycloak's `clientScopes` list in `realm-shopping-cart.json` is empty.

The `groups` claim is still delivered in the ID token via the client-level mapper
without needing a scope. Removing `groups` from `requestedScopes` fixes the login error
while preserving group-based RBAC.

---

## Fix

### Change 1 — `argocd/config/argocd-cm.yaml`: remove `groups` from requestedScopes

**Exact old block:**
```yaml
    requestedScopes:
      - openid
      - profile
      - email
      - groups
```

**Exact new block:**
```yaml
    requestedScopes:
      - openid
      - profile
      - email
```

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| `shopping-cart-infra` | `argocd/config/argocd-cm.yaml` | Remove `groups` from requestedScopes |

---

## Rules

- No other files modified
- Do NOT modify `realm-shopping-cart.json` — the protocol mapper on the ArgoCD client is correct

---

## Definition of Done

- [ ] `argocd/config/argocd-cm.yaml` requestedScopes has only `openid`, `profile`, `email`
- [ ] Committed to branch `fix/argocd-groups-scope` with message:
      `fix(argocd): remove groups from requestedScopes — not a Keycloak client scope`
- [ ] `git push origin fix/argocd-groups-scope` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `argocd/config/argocd-cm.yaml`
- Do NOT commit to `main` — work on `fix/argocd-groups-scope`
- Do NOT add a `groups` client scope to `realm-shopping-cart.json` — the protocol mapper approach is correct
