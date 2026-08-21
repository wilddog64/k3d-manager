# Bug: keycloak-reconcile-hook-job has duplicate LDAP_BIND_CREDENTIAL env entry

**Date:** 2026-05-24
**File:** `shopping-cart-infra/identity/keycloak/keycloak-reconcile-hook-job.yaml`
**Repo:** `shopping-cart-infra`
**Branch (work):** `fix/keycloak-ldap-bind-credential` (already exists — do NOT recreate)

---

## Problem

Commit `4643caa` added an explicit `secretKeyRef` entry for `LDAP_BIND_CREDENTIAL`
sourced from `ldap-secrets.LDAP_ADMIN_PASSWORD`.

However, `keycloak-secrets-externalsecret.yaml` already syncs `LDAP_BIND_CREDENTIAL`
from Vault `secret/data/ldap/admin` into the `keycloak-secrets` Secret. The reconcile
job already has `envFrom: secretRef: keycloak-secrets` (line 157-158) which injects
all keys from `keycloak-secrets` — including `LDAP_BIND_CREDENTIAL`.

The explicit `secretKeyRef` creates two sources of truth for the same credential,
sourced through two different Secret objects (`ldap-secrets` vs `keycloak-secrets`),
both ultimately reading the same Vault path.

**Flagged by Copilot on PR #67 (comment ID 3295605999, line 184).**

---

## Root Cause

The original bug spec assumed `LDAP_BIND_CREDENTIAL` was missing from the container
environment entirely. In fact it was already provided via `envFrom: secretRef: keycloak-secrets`.
The root cause of the original job failure requires separate investigation.

---

## Fix

### Change 1 — `identity/keycloak/keycloak-reconcile-hook-job.yaml`: remove duplicate env entry

**Exact old block (lines 175–184 — GRAFANA_CLIENT_SECRET through volumeMounts):**

```yaml
        - name: GRAFANA_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: keycloak-client-secrets
              key: grafana-client-secret
        - name: LDAP_BIND_CREDENTIAL
          valueFrom:
            secretKeyRef:
              name: ldap-secrets
              key: LDAP_ADMIN_PASSWORD
        volumeMounts:
        - name: keycloak-realm-import
          mountPath: /realm
          readOnly: true
```

**Exact new block:**

```yaml
        - name: GRAFANA_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: keycloak-client-secrets
              key: grafana-client-secret
        volumeMounts:
        - name: keycloak-realm-import
          mountPath: /realm
          readOnly: true
```

---

## Files Changed

| File | Change |
|------|--------|
| `identity/keycloak/keycloak-reconcile-hook-job.yaml` | Remove 5-line `LDAP_BIND_CREDENTIAL` env entry added in `4643caa` |

---

## Before You Start

1. `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra fetch origin`
2. `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra checkout fix/keycloak-ldap-bind-credential`
3. `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra pull origin fix/keycloak-ldap-bind-credential`
4. Read `identity/keycloak/keycloak-reconcile-hook-job.yaml` lines 175–190 to locate the block
5. Confirm you are on branch `fix/keycloak-ldap-bind-credential` — never commit to `main`

**Branch (work repo):** `fix/keycloak-ldap-bind-credential` in `shopping-cart-infra`

---

## Rules

- `kubectl apply --dry-run=client -f identity/keycloak/keycloak-reconcile-hook-job.yaml` — must pass
- No other files touched

---

## Definition of Done

- [ ] Lines 180–184 (`LDAP_BIND_CREDENTIAL` secretKeyRef block) removed from `identity/keycloak/keycloak-reconcile-hook-job.yaml`
- [ ] `kubectl apply --dry-run=client -f identity/keycloak/keycloak-reconcile-hook-job.yaml` passes
- [ ] No other files modified
- [ ] Committed on branch `fix/keycloak-ldap-bind-credential`
- [ ] Pushed to `origin/fix/keycloak-ldap-bind-credential`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(keycloak): remove duplicate LDAP_BIND_CREDENTIAL env entry — already provided via envFrom keycloak-secrets
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `identity/keycloak/keycloak-reconcile-hook-job.yaml`
- Do NOT commit to `main`
- Do NOT remove or change the `envFrom: secretRef: keycloak-secrets` block — only remove the explicit `LDAP_BIND_CREDENTIAL` env entry
