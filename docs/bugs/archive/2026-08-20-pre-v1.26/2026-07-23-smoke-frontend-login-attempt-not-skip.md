# Bugfix: v1.17.0 — frontend login smoke skips a check that actually passes

**Branch:** `k3d-manager-v1.17.0`
**Files:** `bin/k3dm-webhook`

---

## Before You Start

1. `git pull origin k3d-manager-v1.17.0` — get the latest branch state (spec-5 seed + User-Profile fix `950998aa`).
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — the live-smoke findings that produced this change.
3. Read `bin/k3dm-webhook` around the frontend-login block (currently lines 1598–1616) so the old block matches exactly before you edit.

---

## Problem

The webhook health smoke **unconditionally skips** the Frontend login check whenever the
Keycloak token was minted through the `k3dm-smoke` fallback client (`kc_via_smoke_client`
is `True`). The stated reason — "smoke-client token not scoped for frontend audience" — is
an assumption, and it is **false on the live cluster**: the frontend authenticates the
bearer token but does not enforce the `aud` claim, so the smoke token logs in successfully.

The skip throws away real end-to-end login coverage: Keycloak issues a token → the frontend
validates it → returns the user's cart.

**Root cause:** the `elif kc_via_smoke_client:` branch replaces the actual HTTP request with
an unconditional `ok=None` skip, instead of attempting the request and grading it by result.

Live-verified 2026-07-23 (`shopping-cart` realm, hub `k3d-k3d-cluster`):

| Test | Result |
|------|--------|
| smoke token claims | `aud=account`, `azp=k3dm-smoke`, scope `profile email` |
| `GET /api/cart` **with** smoke token | **HTTP 200** — real cart JSON |
| `GET /api/cart` **without** token | **HTTP 401** |
| `frontend` Keycloak client | `directAccessGrantsEnabled=False` (auth-code only — that is why the smoke uses the `k3dm-smoke` fallback) |

---

## Reproduction

On a cluster with the `k3dm-smoke` user seeded (`./scripts/k3d-manager keycloak_seed_smoke_user`):

```bash
# mint a smoke-client token
PW=$(kubectl -n identity get secret k3dm-smoke-user -o jsonpath='{.data.password}' | base64 -d)
TOK=$(curl -s -d grant_type=password -d client_id=k3dm-smoke \
  --data-urlencode username=k3dm-smoke --data-urlencode "password=${PW}" \
  http://keycloak.shopping-cart.local/realms/shopping-cart/protocol/openid-connect/token \
  | jq -r .access_token)
# the frontend accepts it:
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer ${TOK}" \
  http://frontend.shopping-cart.local/api/cart
```

- **Expected (current webhook behavior):** Frontend login reported ⚪ `skipped (...)`.
- **Actual endpoint behavior:** HTTP 200 — the login works; the smoke should report ✅.

---

## Fix

### Change 1 — `bin/k3dm-webhook`: attempt the frontend request instead of skipping, grade by result

Remove the unconditional `elif kc_via_smoke_client:` skip. Always attempt the authed request
when a token exists. Grade by outcome:

- **HTTP 2xx → ✅** (real login proof) — for any client.
- **HTTP 401/403 via the smoke client → ⚪** (`ok=None`) — an audience-strict deployment
  correctly rejects the smoke token; skip rather than false-red.
- **HTTP 401/403 via the real `frontend` client, or any other 4xx/5xx → ❌** (`ok=False`).
- **Other exceptions → ❌** (unchanged).

**Exact old block (lines 1598–1616):**

```python
    fe_path = os.environ.get("K3DM_SMOKE_FRONTEND_AUTHED_PATH", "/api/cart")
    if kc_token is None:
        results.append(("Frontend login", None, "skipped (no Keycloak token)"))
    elif kc_via_smoke_client:
        results.append(("Frontend login", None, "skipped (smoke-client token not scoped for frontend audience)"))
    else:
        try:
            req = urllib.request.Request(
                f"{frontend_base.rstrip('/')}{fe_path}",
                headers={"User-Agent": "k3dm-smoketest/1",
                         "Authorization": f"Bearer {kc_token}"},
            )
            with urllib.request.urlopen(req, timeout=8, context=ctx) as resp:
                ok = 200 <= resp.status < 300
                results.append(("Frontend login", ok, f"HTTP {resp.status} on {fe_path}"))
        except urllib.error.HTTPError as exc:
            results.append(("Frontend login", False, f"HTTP {exc.code} on {fe_path}"))
        except Exception as exc:
            results.append(("Frontend login", False, str(exc)[:200]))
```

**Exact new block:**

```python
    fe_path = os.environ.get("K3DM_SMOKE_FRONTEND_AUTHED_PATH", "/api/cart")
    if kc_token is None:
        results.append(("Frontend login", None, "skipped (no Keycloak token)"))
    else:
        try:
            req = urllib.request.Request(
                f"{frontend_base.rstrip('/')}{fe_path}",
                headers={"User-Agent": "k3dm-smoketest/1",
                         "Authorization": f"Bearer {kc_token}"},
            )
            with urllib.request.urlopen(req, timeout=8, context=ctx) as resp:
                ok = 200 <= resp.status < 300
                results.append(("Frontend login", ok, f"HTTP {resp.status} on {fe_path}"))
        except urllib.error.HTTPError as exc:
            if kc_via_smoke_client and exc.code in (401, 403):
                results.append(("Frontend login", None, f"skipped (smoke-client token rejected: HTTP {exc.code} on {fe_path})"))
            else:
                results.append(("Frontend login", False, f"HTTP {exc.code} on {fe_path}"))
        except Exception as exc:
            results.append(("Frontend login", False, str(exc)[:200]))
```

**Notes for the implementer:**
- Do NOT touch any other function or the Keycloak/ArgoCD/Grafana login blocks around it.
- `kc_via_smoke_client` is already in scope (set earlier in the same function) — do not redefine it.
- Preserve the existing 4-space indentation of the surrounding Python block exactly.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | Frontend login smoke attempts the authed request even when using the `k3dm-smoke` fallback client; grades 2xx→✅, smoke-client 401/403→⚪, everything else→❌ |

---

## Rules

- `python3 -m py_compile bin/k3dm-webhook` — compiles clean
- `./scripts/k3d-manager _agent_audit` — passes
- No other files touched (this is a single-file code change; memory-bank is a SEPARATE commit)
- Do NOT run `make restart-webhook` or any live smoke — Claude restarts the webhook and re-verifies against the live cluster after your push

---

## Definition of Done

- [ ] The frontend-login block matches the new block exactly
- [ ] `python3 -m py_compile bin/k3dm-webhook` clean
- [ ] `./scripts/k3d-manager _agent_audit` passes
- [ ] Committed and pushed to `k3d-manager-v1.17.0`
- [ ] memory-bank updated (SEPARATE commit) with the commit SHA and task status

**Commit message (exact):**
```
fix(webhook): attempt frontend login smoke on smoke-client token instead of skipping
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/k3dm-webhook` (memory-bank is a separate commit)
- Do NOT commit to `main` — work on `k3d-manager-v1.17.0`
- Do NOT run `make restart-webhook` or any live cluster / smoke command — that is Claude's step
