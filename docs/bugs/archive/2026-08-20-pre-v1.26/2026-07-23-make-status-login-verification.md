# Bugfix: v1.17.0 — `make status` verifies real logins, not just health pages

**Branch:** `k3d-manager-v1.17.0`
**Files:** `bin/k3dm-webhook`

---

## Problem

`make status` (and the Slack `/cluster-status`, same source) reports every service green
while frontend logins are actually broken. Both consume the `services` array produced by
`_smoke_test_services` (`bin/k3dm-webhook:1513`), which only polls health/liveness or
unauthenticated root pages:

- ArgoCD `localhost:8080/healthz` — 200 even when OIDC login is dead
- Frontend `frontend.3ai-talk.org/` (root) — **the Keycloak stale-session error page renders as HTTP 200** (the exact false-green)
- Keycloak `/health/live` — liveness ≠ can-mint-a-token
- Grafana `/api/health` — 200 even when OIDC login is broken

**Root cause:** the smoke test never performs an authenticated login, so a broken IdP /
stale session / misconfigured OIDC client all read as green. Directly tied to the recurring
frontend "We are sorry… please login again" symptom.

**Chosen approach (decided 2026-07-23):** credentialed **token/credential POST, no browser** —
a check is green only when a real login succeeds. Rejected full Playwright E2E (too heavy) and
redirect-assert-only (doesn't prove token minting).

---

## Reproduction

```bash
make status          # every service ✅ even when the frontend login page is broken
```

The Keycloak stale-session error page served at the frontend root returns HTTP 200, so the
current Frontend check passes.

---

## Design

Add one new helper, `_smoke_test_logins(provider, app_context)`, and call it at the end of
`_smoke_test_services`. Each check performs a **real credentialed login** and is green only on
success. **Credentials come from environment variables read by the webhook process.** When a
service's credentials are absent, that check is **skipped** (`ok=None` → renders ⚪), so a
credential-less environment (CI, a fresh clone) never false-reds — consistent with the existing
`None` results (Pushgateway / ESO / Data layer).

Credential env vars (operator supplies; see "Open decision" below):

| Service | User var | Password var | Extra |
|---------|----------|--------------|-------|
| Keycloak | `K3DM_SMOKE_KC_USER` | `K3DM_SMOKE_KC_PASS` | `K3DM_SMOKE_KC_REALM` (default `shopping-cart`), `K3DM_SMOKE_KC_CLIENT` (default `frontend`) |
| Frontend | *(reuses Keycloak token)* | — | `K3DM_SMOKE_FRONTEND_AUTHED_PATH` (default `/api/cart`) |
| ArgoCD | `K3DM_SMOKE_ARGOCD_USER` (default `admin`) | `K3DM_SMOKE_ARGOCD_PASS` | — |
| Grafana | `K3DM_SMOKE_GRAFANA_USER` (default `admin`) | `K3DM_SMOKE_GRAFANA_PASS` | — |

---

## Fix

### Change 1 — `bin/k3dm-webhook`: add `_smoke_test_logins` immediately before `def _smoke_test_services(...)` (line 1513)

**Insert this new function (new block, placed directly above the `_smoke_test_services` definition):**

```python
def _smoke_test_logins(provider, app_context):
    """Credentialed login checks — green only when a real login succeeds.

    Each check is skipped (ok=None) when its credentials are not configured, so the
    absence of credentials never reports red. Returns list of (name, ok, detail)."""
    import ssl
    import os
    import urllib.parse
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    results = []

    if provider == "k3s-hostinger":
        keycloak_base = "https://keycloak.3ai-talk.org"
        frontend_base = "https://frontend.3ai-talk.org"
    else:
        keycloak_base = "http://keycloak.shopping-cart.local"
        frontend_base = "http://frontend.shopping-cart.local"
    grafana_base = "https://grafana.3ai-talk.org"
    argocd_base = "http://localhost:8080"

    def _post(url, data, headers=None):
        body = urllib.parse.urlencode(data).encode() if isinstance(data, dict) else data
        h = {"User-Agent": "k3dm-smoketest/1"}
        if headers:
            h.update(headers)
        req = urllib.request.Request(url, data=body, headers=h, method="POST")
        with urllib.request.urlopen(req, timeout=8, context=ctx) as resp:
            return resp.status, resp.read()

    kc_user = os.environ.get("K3DM_SMOKE_KC_USER")
    kc_pass = os.environ.get("K3DM_SMOKE_KC_PASS")
    kc_realm = os.environ.get("K3DM_SMOKE_KC_REALM", "shopping-cart")
    kc_client = os.environ.get("K3DM_SMOKE_KC_CLIENT", "frontend")
    kc_token = None
    if not (kc_user and kc_pass):
        results.append(("Keycloak login", None, "no credentials (set K3DM_SMOKE_KC_USER/PASS)"))
    else:
        try:
            url = f"{keycloak_base}/realms/{kc_realm}/protocol/openid-connect/token"
            code, raw = _post(url, {
                "grant_type": "password",
                "client_id": kc_client,
                "username": kc_user,
                "password": kc_pass,
            })
            kc_token = json.loads(raw).get("access_token") if code == 200 else None
            if kc_token:
                results.append(("Keycloak login", True, f"token minted (realm={kc_realm})"))
            else:
                results.append(("Keycloak login", False, f"HTTP {code}, no access_token"))
        except Exception as exc:
            results.append(("Keycloak login", False, str(exc)[:200]))

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
            results.append(("Frontend login", False, f"HTTP {exc.code} on {fe_path}"))
        except Exception as exc:
            results.append(("Frontend login", False, str(exc)[:200]))

    argo_user = os.environ.get("K3DM_SMOKE_ARGOCD_USER", "admin")
    argo_pass = os.environ.get("K3DM_SMOKE_ARGOCD_PASS")
    if not argo_pass:
        results.append(("ArgoCD login", None, "no credentials (set K3DM_SMOKE_ARGOCD_PASS)"))
    else:
        try:
            code, raw = _post(
                f"{argocd_base}/api/v1/session",
                json.dumps({"username": argo_user, "password": argo_pass}).encode(),
                headers={"Content-Type": "application/json"},
            )
            tok = json.loads(raw).get("token") if code == 200 else None
            results.append(("ArgoCD login", bool(tok), f"HTTP {code}" + ("" if tok else ", no token")))
        except urllib.error.HTTPError as exc:
            results.append(("ArgoCD login", False, f"HTTP {exc.code}"))
        except Exception as exc:
            results.append(("ArgoCD login", False, str(exc)[:200]))

    graf_user = os.environ.get("K3DM_SMOKE_GRAFANA_USER", "admin")
    graf_pass = os.environ.get("K3DM_SMOKE_GRAFANA_PASS")
    if not graf_pass:
        results.append(("Grafana login", None, "no credentials (set K3DM_SMOKE_GRAFANA_PASS)"))
    else:
        try:
            code, raw = _post(
                f"{grafana_base}/login",
                json.dumps({"user": graf_user, "password": graf_pass}).encode(),
                headers={"Content-Type": "application/json"},
            )
            results.append(("Grafana login", code == 200, f"HTTP {code}"))
        except urllib.error.HTTPError as exc:
            results.append(("Grafana login", False, f"HTTP {exc.code}"))
        except Exception as exc:
            results.append(("Grafana login", False, str(exc)[:200]))

    return results
```

### Change 2 — `bin/k3dm-webhook`: call the helper at the end of `_smoke_test_services`

**Exact old block (lines 1681–1683):**

```python
        results.append(("Data layer", _dl_ok, _dl_detail))

    return results
```

**Exact new block:**

```python
        results.append(("Data layer", _dl_ok, _dl_detail))

    results.extend(_smoke_test_logins(provider, app_context))

    return results
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | new `_smoke_test_logins` helper + one call at end of `_smoke_test_services` |

---

## Rules

- Do NOT alter any existing check in `_smoke_test_services` — only append the new call.
- The new checks MUST return `ok=None` (skip) when credentials are absent — never red.
  Confirm the `all_ok` aggregation (`/api/v1/health`, ~line 3061) already treats `None` as
  pass-through (the existing Pushgateway/ESO/Data-layer `None` results prove it does). If it
  does NOT, do NOT change `all_ok` — file that as a separate finding.
- No hardcoded credentials — env vars only (`${PLACEHOLDER}` discipline).
- `python3 -m py_compile bin/k3dm-webhook` — clean.
- Run `_agent_audit` before reporting done.

---

## Definition of Done

- [ ] `_smoke_test_logins` added; four checks (Keycloak / Frontend / ArgoCD / Grafana)
- [ ] Each check skips (⚪) when its creds are unset — verified by running `make status` with no
      `K3DM_SMOKE_*` vars set (no new ❌ appears)
- [ ] `results.extend(_smoke_test_logins(...))` wired in before `return results`
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] `make restart-webhook` run after the change (webhook code changed)
- [ ] Committed and pushed to `k3d-manager-v1.17.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(webhook): verify real logins in smoke test, not just health pages
```

---

## Open decision (operator — NOT code scope)

Where the webhook process gets `K3DM_SMOKE_*` credentials in the running deployment:
- Keycloak dev realm — `alice/password` (dev-only; never a production path)
- ArgoCD / Grafana admin — via Vault/ESO/Keychain, injected into the webhook's environment

Pick the source and wire it into the webhook's launch environment (systemd unit / launch
wrapper) separately. The code degrades gracefully (⚪) until those vars exist, so this can land
first and light up once creds are provided.

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/k3dm-webhook`
- Do NOT add a Playwright/browser dependency
- Do NOT commit to `main` — work on `k3d-manager-v1.17.0`
