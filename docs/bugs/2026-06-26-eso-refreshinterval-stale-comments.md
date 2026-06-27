# Bugfix: ESO ExternalSecret stale cadence comments (Copilot PR #86 follow-up)

**Repo (work):** `shopping-cart-infra`
**Branch (all work repos):** `fix/eso-refresh-interval-self-heal` (the SAME branch as open PR #86 — the fix lands on that PR)
**Spec repo:** k3d-manager (this file) — read here, implement in shopping-cart-infra.

---

## Problem

PR #86 lowered `refreshInterval: 24h → 15m` across all ExternalSecret manifests so a
transient Vault-bridge flap self-heals within ~15m. But the inline **comments** above several
`refreshInterval` lines still describe the old cadence (`24h is sufficient`, `daily`), so they
now contradict the manifest. Copilot flagged 7 of these on PR #86.

**Root cause:** the Tier 1 change touched only the `refreshInterval:` value, not the adjacent
explanatory comments.

---

## Fix

Replace each stale cadence comment with one consistent line that matches the new intent.

**Exact new comment line (identical everywhere, two-space indent):**
```yaml
  # 15m refresh: a transient Vault-bridge flap self-heals within ~15m (static KV, negligible read cost)
```

### Change 1 — `data-layer/secrets/payment-encryption-externalsecret.yaml`
Old:
```yaml
  # Check for key rotation daily
```
New:
```yaml
  # 15m refresh: a transient Vault-bridge flap self-heals within ~15m (static KV, negligible read cost)
```

### Change 2 — `data-layer/secrets/payment-gateway-externalsecret.yaml`
Old:
```yaml
  # Check for updates daily
```
New:
```yaml
  # 15m refresh: a transient Vault-bridge flap self-heals within ~15m (static KV, negligible read cost)
```

### Change 3 — `data-layer/secrets/postgres-orders-externalsecret.yaml`
Old:
```yaml
  # Static KV credentials do not expire; 24h is sufficient
```
New:
```yaml
  # 15m refresh: a transient Vault-bridge flap self-heals within ~15m (static KV, negligible read cost)
```

### Change 4 — `data-layer/secrets/postgres-payment-externalsecret.yaml`
Old:
```yaml
  # Static KV credentials do not expire; 24h is sufficient
```
New:
```yaml
  # 15m refresh: a transient Vault-bridge flap self-heals within ~15m (static KV, negligible read cost)
```

### Change 5 — `data-layer/secrets/postgres-products-externalsecret.yaml` (TWO occurrences)
This is a two-document YAML. **Both** occurrences of the line below must be replaced.
Old (×2):
```yaml
  # Static KV credentials do not expire; 24h is sufficient
```
New (×2):
```yaml
  # 15m refresh: a transient Vault-bridge flap self-heals within ~15m (static KV, negligible read cost)
```

### Change 6 — `data-layer/secrets/redis-cart-externalsecret.yaml`
Old:
```yaml
  # Refresh password daily (static secret)
```
New:
```yaml
  # 15m refresh: a transient Vault-bridge flap self-heals within ~15m (static KV, negligible read cost)
```

---

## Files Changed

| File | Change |
|------|--------|
| `data-layer/secrets/payment-encryption-externalsecret.yaml` | 1 comment line |
| `data-layer/secrets/payment-gateway-externalsecret.yaml` | 1 comment line |
| `data-layer/secrets/postgres-orders-externalsecret.yaml` | 1 comment line |
| `data-layer/secrets/postgres-payment-externalsecret.yaml` | 1 comment line |
| `data-layer/secrets/postgres-products-externalsecret.yaml` | 2 comment lines |
| `data-layer/secrets/redis-cart-externalsecret.yaml` | 1 comment line |

Total: 7 comment lines across 6 files. **Comments only — do NOT change any `refreshInterval`
value, secret data, auth, path, or any other field.**

---

## Verification

```bash
# 0 stale cadence comments remain
git grep -n -iE '#.*(24 ?h|daily|do not expire|is sufficient)' -- '*.yaml' ':(exclude)docs/**'   # → no output
# 7 new comment lines present
git grep -c 'self-heals within ~15m' -- '*.yaml' | awk -F: '{s+=$2} END{print s}'   # → 7
```

YAML must stay valid (yamllint via `validate.yml` must pass).

---

## Rules

- Only the 6 listed files change — comments only.
- Preserve exact indentation (`  #` — two spaces).
- No `refreshInterval` value changes, no data/auth/path changes.
- Work on `fix/eso-refresh-interval-self-heal` (the open PR #86 branch), never `main`.

---

## Definition of Done

- [ ] All 7 stale comment lines replaced (one each, two in postgres-products)
- [ ] `git grep` for stale cadence comments returns nothing
- [ ] `git grep -c 'self-heals within ~15m'` sums to 7
- [ ] yamllint clean
- [ ] Committed and pushed to `origin/fix/eso-refresh-interval-self-heal`
- [ ] k3d-manager `memory-bank/activeContext.md` + `progress.md` updated with the commit SHA

**Commit message (exact):**
```
docs(eso): align ExternalSecret refreshInterval comments with 15m self-heal interval
```

---

## What NOT to Do

- Do NOT create a PR (the fix lands on existing PR #86)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the 6 listed manifests
- Do NOT change any `refreshInterval` value or any non-comment field
- Do NOT commit to `main` — work on `fix/eso-refresh-interval-self-heal`
