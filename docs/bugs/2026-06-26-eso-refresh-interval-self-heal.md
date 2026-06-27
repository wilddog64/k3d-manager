# Bugfix: ESO ExternalSecret refreshInterval 24h → 15m (self-heal after tunnel flap)

**Repo (work):** `shopping-cart-infra`
**Branch (all work repos):** `fix/eso-refresh-interval-self-heal` (from `origin/main`)
**Spec repo:** k3d-manager (this file) — read here, implement in shopping-cart-infra.

---

## Problem

The Hostinger app cluster reads secrets from the hub Vault (on the Mac) through a
multi-hop reverse-SSH/socat bridge. Any network blip flaps the tunnel; ESO marks the
ClusterSecretStore `vault-backend` `Ready=False` and every dependent ExternalSecret goes
`SecretSyncedError`.

The tunnel self-reconnects within ~minutes, **but the ExternalSecrets do not recover** —
every ESO ExternalSecret in `shopping-cart-infra` hardcodes:

```yaml
  refreshInterval: 24h
```

So after a transient failure ESO will not retry the fetch for **24 hours**. The secrets
stay broken until an operator manually runs a `force-sync` annotation. This caused two live
outages on 2026-06-26 (recovery required manual `kubectl annotate ... force-sync` on the
store **and** each stuck ExternalSecret).

**Root cause:** `refreshInterval: 24h` turns every transient Vault-reachability blip into a
24-hour outage, because ESO's retry cadence == the refresh interval.

> Related prior art: `docs/bugs/v1.5.0-bugfix-services-git-externalsecret-refreshinterval-drift.md`,
> `docs/bugs/v1.5.0-bugfix-eso-stale-secrets-force-refresh.md`. This spec is the broader,
> data-layer-wide fix.

---

## Fix

Lower `refreshInterval` from `24h` to `15m` in **every** ExternalSecret manifest below.
15m means any tunnel flap self-heals within ≤15 minutes with **zero** manual intervention;
the extra Vault KV reads are negligible (a handful of small reads per secret per hour).

The change is identical in every file:

**Exact old line:**
```yaml
  refreshInterval: 24h
```

**Exact new line:**
```yaml
  refreshInterval: 15m
```

### Files to change (19)

```
argocd/config/argocd-secret.yaml
data-layer/minio/secret.yaml
data-layer/postgresql/orders/secret.yaml
data-layer/postgresql/payment/secret.yaml
data-layer/postgresql/products/secret.yaml
data-layer/secrets/payment-encryption-externalsecret.yaml
data-layer/secrets/payment-gateway-externalsecret.yaml
data-layer/secrets/postgres-orders-apps-externalsecret.yaml
data-layer/secrets/postgres-orders-externalsecret.yaml
data-layer/secrets/postgres-payment-externalsecret.yaml
data-layer/secrets/postgres-products-externalsecret.yaml
data-layer/secrets/rabbitmq-externalsecret.yaml
data-layer/secrets/redis-cart-apps-externalsecret.yaml
data-layer/secrets/redis-cart-externalsecret.yaml
data-layer/secrets/redis-orders-cache-apps-externalsecret.yaml
data-layer/secrets/redis-orders-cache-externalsecret.yaml
identity/keycloak/keycloak-client-secrets-externalsecret.yaml
identity/keycloak/keycloak-secrets-externalsecret.yaml
identity/ldap/ldap-secrets-externalsecret.yaml
```

> Each file has exactly one `refreshInterval:` line. Do NOT touch `*.md`, `.clinerules`, or
> any file under `docs/archive/`. Do NOT change any other field (path, role, auth, data keys).

---

## Verification

```bash
# 0 occurrences of 24h remain in real manifests
grep -rn 'refreshInterval: 24h' . | grep -vE '\.(md)$|/archive/|\.clinerules'   # → no output
# 19 manifests now at 15m
grep -rln 'refreshInterval: 15m' . | grep -vE '\.(md)$|/archive/|\.clinerules' | wc -l   # → 19
```

YAML must stay valid (indentation unchanged — `refreshInterval` stays a child of `spec`).

---

## Rules

- Only the 19 listed YAML files change — one line each.
- Preserve exact indentation (`  refreshInterval:` — two spaces).
- No changes to secret data, auth, paths, or any other manifest field.
- No PR. No `--no-verify`. Work on `fix/eso-refresh-interval-self-heal`, never `main`.

---

## Definition of Done

- [ ] All 19 manifests changed `24h` → `15m` (one line each)
- [ ] `grep -rn 'refreshInterval: 24h'` over real manifests returns nothing
- [ ] `grep -rln 'refreshInterval: 15m'` over real manifests counts 19
- [ ] Committed and pushed to `origin/fix/eso-refresh-interval-self-heal`
- [ ] k3d-manager `memory-bank/activeContext.md` + `progress.md` updated with the commit SHA

**Commit message (exact):**
```
fix(eso): lower ExternalSecret refreshInterval 24h to 15m for self-heal after vault bridge flap
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the 19 listed manifests
- Do NOT commit to `main` — work on `fix/eso-refresh-interval-self-heal`
- Do NOT change the bridge/socat/tunnel topology — that is the separate Tier 3 plan
  (`docs/plans/hub-vault-relocation-fallback.md`)
