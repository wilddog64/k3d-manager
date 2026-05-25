# Bug: keycloak-realm-reconcile PostSync job missing LDAP_BIND_CREDENTIAL env var

**Date:** 2026-05-24
**File:** `shopping-cart-infra/identity/keycloak/keycloak-reconcile-hook-job.yaml`
**Repo:** `shopping-cart-infra`
**Branch (work):** `fix/keycloak-ldap-bind-credential` (create from origin/main)

---

## Problem

The ArgoCD PostSync hook job `keycloak-realm-reconcile` renders the realm JSON with
`render_realm()` which substitutes `${LDAP_BIND_CREDENTIAL}` (line 53 of the job script).
The substituted value is the OpenLDAP admin bind password used by Keycloak's LDAP
federation provider.

`LDAP_BIND_CREDENTIAL` is never set in the container's env. On every PostSync run:
- `render_realm()` substitutes an empty string for `${LDAP_BIND_CREDENTIAL}`
- `kcadm.sh create partialImport` imports the realm with an empty LDAP bind password
- Keycloak LDAP federation connects with a blank credential → authentication fails
- User logins via Keycloak (admin, developer, operator) fail

The job exits 1 and both pods show `Error`:
```
keycloak-realm-reconcile-xxxxx   0/1   Error   0   50m
```

The cluster continues to function only because `acg-up` step 10d performs the initial
realm import directly (with correct substitution) before the PostSync job runs.

**This bug exists since the job was introduced (2026-05-14, commit `d0dd8ec`). It is not
caused by any recent fix.**

---

## Root Cause

`identity/keycloak/keycloak-reconcile-hook-job.yaml` env section (lines 159–179) lists
only the 4 client secrets. `LDAP_BIND_CREDENTIAL` is referenced in the script but has no
corresponding env entry sourced from a secret.

The `ldap-secrets` Secret in the `identity` namespace (provisioned by ESO from Vault
`ldap/admin`) has key `LDAP_ADMIN_PASSWORD` which is exactly the value needed.

---

## Fix

### Change 1 — `identity/keycloak/keycloak-reconcile-hook-job.yaml`: add LDAP_BIND_CREDENTIAL env entry

**Exact old block (lines 175–183 — after grafana-client-secret, before volumeMounts):**

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

**Exact new block:**

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

---

## Files Changed

| File | Change |
|------|--------|
| `identity/keycloak/keycloak-reconcile-hook-job.yaml` | Add `LDAP_BIND_CREDENTIAL` env entry sourced from `ldap-secrets.LDAP_ADMIN_PASSWORD` |

---

## Before You Start

1. `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra fetch origin`
2. Create and checkout branch: `git checkout -b fix/keycloak-ldap-bind-credential origin/main`
3. Read this spec in full before touching any files
4. Read `identity/keycloak/keycloak-reconcile-hook-job.yaml` — locate the env section ending with `grafana-client-secret`
5. Confirm you are on branch `fix/keycloak-ldap-bind-credential` — never commit to `main`

---

## Rules

- `kubectl apply --dry-run=client -f identity/keycloak/keycloak-reconcile-hook-job.yaml` — must pass
- No other files touched

---

## Definition of Done

- [ ] `LDAP_BIND_CREDENTIAL` env entry added after `GRAFANA_CLIENT_SECRET` block, before `volumeMounts`
- [ ] `secretKeyRef.name` is `ldap-secrets`, `secretKeyRef.key` is `LDAP_ADMIN_PASSWORD`
- [ ] `kubectl apply --dry-run=client -f identity/keycloak/keycloak-reconcile-hook-job.yaml` passes
- [ ] Committed on branch `fix/keycloak-ldap-bind-credential`
- [ ] Pushed to `origin/fix/keycloak-ldap-bind-credential`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(keycloak): add LDAP_BIND_CREDENTIAL env to reconcile hook job — sourced from ldap-secrets
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `identity/keycloak/keycloak-reconcile-hook-job.yaml`
- Do NOT commit to `main`
- Do NOT change the script body of the reconcile job — only the env section
