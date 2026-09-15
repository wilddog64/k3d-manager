# Bug: `make status` login checks use different accounts and paths than the operator, so they false-green

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-15
**Status:** OPEN
**Files:** `bin/k3dm-webhook` (`_smoke_test_logins`), `scripts/tests/bin/test_smoke_logins.py` (new; pytest), `CHANGELOG.md`
**Related:** `docs/bugs/2026-07-23-smoke-login-credential-autodiscovery.md` (autodiscovery, done), `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`

## Evidence (2026-09-15)

- `make status CLUSTER_PROVIDER=k3s-hostinger` shows ✓ for the Keycloak, Frontend, ArgoCD, and Grafana logins.
- The operator reports they **cannot** log in to ArgoCD, Keycloak, Frontend SSO, Prometheus, or Alertmanager. Only Grafana works.

`_smoke_test_logins` vs. the accounts `make show-service-passwords` gives the operator:

| Check | What the check uses | What the operator uses |
|---|---|---|
| Keycloak | `k3dm-smoke-user` Secret, `k3dm-smoke` client, password grant | Keycloak admin console: master `admin` from `identity/keycloak-secrets` `KEYCLOAK_ADMIN_PASSWORD` |
| Frontend | smoke token sent straight to `GET /api/cart` | browser SSO via Keycloak as realm users `admin`/`developer`/`operator` (Vault `secret/keycloak/users/<user>` `password`) |
| ArgoCD | `admin` + Vault `argocd/admin`, **silent fallback** to `argocd-initial-admin-secret`; URL `localhost:8080` unless provider is hostinger | `admin` + Vault `argocd/admin` at `https://argocd.3ai-talk.org`, or the "Log in via Keycloak" SSO button |
| Grafana | `admin` + Vault `observability/grafana` | same ✅, the only one the operator can use |
| Prometheus | not login-checked | basic auth, Vault `k3d-manager/prometheus-basic-auth` |
| Alertmanager | not login-checked | basic auth, `~/.local/share/k3d-manager/alertmanager-basic-auth.env` |

A green check does not show that any operator account can log in.

## Fix

Rule: **every login line tests the operator's own account, from the same credential source `show-service-passwords` prints, against the public URL the operator opens.**
- Each detail names the account and source, e.g. `admin via Vault argocd/admin`, and never a value.
- A credential that can't be read is ⚪ skip with the source named. It never silently falls back to another account.

1. **Keycloak admin console** — `https://keycloak.3ai-talk.org/realms/master/protocol/openid-connect/token`, `client_id=admin-cli`, password grant. User from `identity/keycloak-secrets` `KEYCLOAK_ADMIN`, password `KEYCLOAK_ADMIN_PASSWORD`. Green only if `access_token` is returned.
2. **Frontend SSO (per realm user `admin`, `developer`, `operator`)** — do the browser authorization-code flow over plain HTTP with a cookie jar (`http.cookiejar` + `urllib`, no browser):
   - `GET /realms/<realm>/protocol/openid-connect/auth?client_id=<frontend client>&response_type=code&scope=openid&redirect_uri=<frontend redirect>&state=<rand>&code_challenge=<S256>&code_challenge_method=S256`;
   - parse `<form id="kc-form-login" … action="…">` (HTML-unescape the action);
   - POST `username`/`password`/`credentialId=` without following redirects;
   - **green** only for a 302/303 whose `Location` starts with the redirect URI and has `code=`.

   Red details:
   - `Invalid username or password` → `credentials rejected`
   - `Invalid parameter: redirect_uri` → `client redirect_uri rejected`
   - an `Update password`/`required action` form → `required action pending`
   - otherwise `HTTP <code>`.

   Read the realm, client id, and redirect URI from `shopping-cart-frontend` origin/main config (Keycloak init / env). Make them module constants with `K3DM_SMOKE_FE_REALM`/`_CLIENT`/`_REDIRECT` env overrides. Passwords come from Vault `secret/keycloak/users/<user>` field `password`, via the existing `_vault_secret`.

   Output: one line `Frontend SSO login` — ✓ when all 3 pass, else ✗ `developer: credentials rejected; operator: …`.
3. **ArgoCD** — always `https://argocd.3ai-talk.org/api/v1/session`, regardless of provider. Password **only** from Vault `argocd/admin` (keep the `K3DM_SMOKE_ARGOCD_PASS` override, labelled `env`). Remove the `argocd-initial-admin-secret` fallback; it made a stale Vault password look green.
4. **ArgoCD SSO** — new line `ArgoCD SSO login`. `GET https://argocd.3ai-talk.org/auth/login` without redirects must 302/303 to the Keycloak realm auth endpoint. Then run the same code-flow as item 2 as realm user `admin`, following that `Location` and expecting a redirect to `https://argocd.3ai-talk.org/auth/callback` with `code=`. Same red details.
5. **Prometheus** — `GET https://prometheus.3ai-talk.org/api/v1/status/buildinfo` with basic auth from Vault `k3d-manager/prometheus-basic-auth` (`user` default `admin`, `password`) → green on 200. Also send one unauthenticated request; a 200 there is ✗ `auth not enforced`.
6. **Alertmanager** — `GET https://alertmanager.3ai-talk.org/api/v2/status` with basic auth from `~/.local/share/k3d-manager/alertmanager-basic-auth.env` (parse `ALERTMANAGER_BASIC_AUTH_USER`/`_PASSWORD` lines; never source) → green on 200.
7. **Rename, don't delete, the synthetic checks:**
   - `Keycloak login` → `Keycloak smoke token (k3dm-smoke-user)`;
   - `Frontend login` → `Frontend API (smoke token)`.

   They stay useful for service health, but no longer read as "you can log in".
8. **Every request** sends `User-Agent: k3dm-smoketest/1` (Cloudflare 1010) and uses the existing timeouts/retries. Register every credential with `_register_secret`, and never put a credential in a detail string, log, or exception text.

## Tests (`scripts/tests/bin/test_smoke_logins.py`, loads `bin/k3dm-webhook` via `SourceFileLoader`, all HTTP faked)

- **Code-flow parser:**
  - a fixture login page with an HTML-escaped action gets the right POST target;
  - a 302 with `code=` → green;
  - the invalid-credentials page → `credentials rejected`;
  - the redirect_uri error page → `client redirect_uri rejected`;
  - a required-action form → `required action pending`.
- **ArgoCD:**
  - Vault unreadable → ⚪ skip naming `Vault argocd/admin`;
  - `argocd-initial-admin-secret` is never read (fake `_smoke_secret` asserts);
  - the URL is `https://argocd.3ai-talk.org` for both `k3d` and `k3s-hostinger`.
- **Prometheus:** unauthenticated 200 → ✗ `auth not enforced`.
- **Alertmanager:** env file parsed without sourcing; missing file → ⚪ skip.
- **Every detail string** names the account and source and contains no fake password value (use sentinel `PW-SENTINEL-DO-NOT-PRINT`).
- **Source parity:** the Vault paths and secret names used here (`argocd/admin`, `observability/grafana`, `k3d-manager/prometheus-basic-auth`, `keycloak/users`, `keycloak-secrets`, `KEYCLOAK_ADMIN_PASSWORD`, `alertmanager-basic-auth.env`) each appear in the Makefile `show-service-passwords` block or in `bin/get-keycloak-password`. Assert tokens, not whole lines.

## Acceptance

1. `make restart-webhook`, then `make status CLUSTER_PROVIDER=k3s-hostinger`.
2. Each login line must match what the operator sees in a browser. Expect red lines now for the services they cannot use, each with a specific reason.
3. Fixing those underlying logins is follow-up work driven by these reasons.

## What NOT to do

- Do not print, log, or embed any credential. No base64 comparisons.
- Do not reset any password or run `grafana cli admin reset-admin-password`.
- Do not hand-patch cluster Secrets.
- Do not use a browser/Playwright.
- Do not edit `scripts/lib/foundation/` or `scripts/lib/acg/`.
- No PR, no merge, no `main` commit, no force-push, no `--no-verify`. No `git add -A`, no `git stash`.
