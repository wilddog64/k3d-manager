# Bugfix: v1.17.0 — seed a dedicated smoke user so the Keycloak login check goes green

**Branch:** `k3d-manager-v1.17.0`
**Files:** `scripts/plugins/keycloak.sh`, `bin/k3dm-webhook`

---

## Problem

The login smoke test (`_smoke_test_logins` in `bin/k3dm-webhook`) leaves two checks at `⚪`:

```
⚪ Keycloak login: no credentials (set K3DM_SMOKE_KC_USER/PASS)
⚪ Frontend login: skipped (no Keycloak token)
```

Spec `2026-07-23-smoke-login-credential-autodiscovery.md` (commit `cdeebfa6`) closed
ArgoCD + Grafana by auto-discovering their admin Secrets, but deliberately left Keycloak +
Frontend out because no realm end-user password exists in plaintext anywhere.

**Live-verified blocker (2026-07-23):** the check does `grant_type=password` against
client **`frontend`**, but in the live `shopping-cart` realm the `frontend` client has
`directAccessGrantsEnabled=false` (it is a public SPA client — auth-code + PKCE only). So the
password-grant login can **never** succeed against `frontend`, seeded user or not. The only
clients with direct access grants are `admin-cli`, `order-service`, `product-catalog` — none is
the frontend user login the check exercises.

**Root cause:** there is no realm client that both (a) k3d-manager owns and (b) permits the
password grant the smoke test uses, and no realm end-user credential k3d-manager can discover.

**Decision (owner, Path 1):** k3d-manager seeds its **own** dedicated smoke client
(`k3dm-smoke`, public + direct-access-grants on) and a local user (`k3dm-smoke`) in the app
realm, stores the random password in a plain k8s Secret (`identity/k3dm-smoke-user`), and the
webhook discovers that Secret. This makes **Keycloak login** a real green (proves realm-user
auth works end to end) **without touching the app-owned `frontend` client**. The **Frontend**
line stays `⚪` on purpose — a token minted for `k3dm-smoke` is not scoped for the frontend
`/api/cart` audience, and a headless authed-API check against a public SPA is a separate,
larger problem out of scope here.

---

## Reproduction

```bash
make status CLUSTER_PROVIDER=k3s-hostinger   # Keycloak login shows ⚪ despite Keycloak being up
```

After this fix, running `./scripts/k3d-manager keycloak_seed_smoke_user` once (stack up) then
`make restart-webhook` flips **Keycloak login** to ✅; **Frontend login** stays `⚪`.

---

## Design notes / constraints honored

- **Idempotent + graceful.** `keycloak_seed_smoke_user` is a standalone public function run
  after the stack is up. If Keycloak is unreachable or the app realm does not exist yet, it
  **warns and returns 0** (never fails a caller) — the webhook then simply stays `⚪`.
- **No app-owned client is modified.** Only a new `k3dm-smoke` client + user are added.
- **No secret in argv / logs.** Admin username/password and the user password are passed to
  `curl` via `--data-urlencode name@file` / `--data-binary @file` (temp files under a
  `mktemp -d` cleaned on RETURN), never on the command line. The Secret is written via
  `--from-file` (not `--from-literal`).
- **Own namespace.** The Secret lives in `identity` (the Keycloak namespace), not `default`.
- **Stable password across re-runs.** If `identity/k3dm-smoke-user` already holds a password,
  it is reused (so a realm rebuild re-seeds the same credential); otherwise a fresh
  `openssl rand -hex 24` is generated.
- **Known limitation (documented, not blocking):** the `shopping-cart` realm is app-owned and
  reconciled by the app's `keycloak-realm-reconcile` job. If that job ever does a full managed
  import it could remove the `k3dm-smoke` client/user; the check then degrades to `⚪` and a
  re-run of `keycloak_seed_smoke_user` restores it. Acceptable by design.

---

## Fix

### Change 1 — `scripts/plugins/keycloak.sh`: add smoke-seed config defaults

**Exact old block (lines 53–54):**

```bash
: "${KEYCLOAK_REALM_NAME:=home}"
: "${KEYCLOAK_REALM_DISPLAY_NAME:=Home}"
```

**Exact new block:**

```bash
: "${KEYCLOAK_REALM_NAME:=home}"
: "${KEYCLOAK_REALM_DISPLAY_NAME:=Home}"
: "${KEYCLOAK_MASTER_ADMIN_SECRET_NAME:=keycloak-secrets}"
: "${KEYCLOAK_SMOKE_REALM:=shopping-cart}"
: "${KEYCLOAK_SMOKE_CLIENT_ID:=k3dm-smoke}"
: "${KEYCLOAK_SMOKE_USERNAME:=k3dm-smoke}"
: "${KEYCLOAK_SMOKE_SECRET_NAME:=k3dm-smoke-user}"
```

### Change 2 — `scripts/plugins/keycloak.sh`: add `keycloak_seed_smoke_user`, inserted directly above `function test_keycloak()`

**Exact old block (line 358):**

```bash
function test_keycloak() {
```

**Exact new block:**

```bash
function keycloak_seed_smoke_user() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      cat <<'HELP'
Usage: keycloak_seed_smoke_user

Idempotently seed a dedicated smoke client + local user in the app realm so the
login smoke test (make status) can prove real realm-user auth without touching the
app-owned 'frontend' client. Warns and returns 0 if Keycloak or the app realm is
not reachable.
HELP
      return 0
   fi

   local realm="${KEYCLOAK_SMOKE_REALM:-shopping-cart}"
   local client_id="${KEYCLOAK_SMOKE_CLIENT_ID:-k3dm-smoke}"
   local username="${KEYCLOAK_SMOKE_USERNAME:-k3dm-smoke}"
   local secret_name="${KEYCLOAK_SMOKE_SECRET_NAME:-k3dm-smoke-user}"
   local ns="${KEYCLOAK_NAMESPACE:-identity}"
   local admin_secret="${KEYCLOAK_MASTER_ADMIN_SECRET_NAME:-keycloak-secrets}"

   local base_url="${KEYCLOAK_BASE_URL:-}"
   if [[ -z "$base_url" ]]; then
      if [[ "${CLUSTER_PROVIDER:-}" == "k3s-hostinger" ]]; then
         base_url="https://keycloak.3ai-talk.org"
      else
         base_url="http://keycloak.shopping-cart.local"
      fi
   fi

   local admin_user admin_pass
   admin_user=$(_kubectl --no-exit -n "$ns" get secret "$admin_secret" -o jsonpath='{.data.KEYCLOAK_ADMIN}' 2>/dev/null | base64 -d 2>/dev/null || true)
   admin_pass=$(_kubectl --no-exit -n "$ns" get secret "$admin_secret" -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || true)
   if [[ -z "$admin_user" || -z "$admin_pass" ]]; then
      _warn "[keycloak] master admin creds not found in secret '$admin_secret'; skipping smoke seed"
      return 0
   fi

   local wd
   wd=$(mktemp -d -t kc-smoke.XXXXXX)
   trap 'rm -rf "$wd"' RETURN
   printf '%s' "$admin_user" > "$wd/u"
   printf '%s' "$admin_pass" > "$wd/p"

   local token
   token=$(_curl -sf \
      --data-urlencode grant_type=password \
      --data-urlencode client_id=admin-cli \
      --data-urlencode "username@$wd/u" \
      --data-urlencode "password@$wd/p" \
      "${base_url}/realms/master/protocol/openid-connect/token" \
      | jq -r '.access_token // empty' 2>/dev/null || true)
   if [[ -z "$token" ]]; then
      _warn "[keycloak] could not mint master admin token at ${base_url}; skipping smoke seed"
      return 0
   fi

   if ! _curl -sf -o /dev/null -H "Authorization: Bearer ${token}" \
        "${base_url}/admin/realms/${realm}"; then
      _warn "[keycloak] realm '${realm}' not present yet; skipping smoke seed"
      return 0
   fi

   local password
   password=$(_kubectl --no-exit -n "$ns" get secret "$secret_name" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
   if [[ -z "$password" ]]; then
      password=$(openssl rand -hex 24)
   fi

   local client_uuid
   client_uuid=$(_curl -sf -H "Authorization: Bearer ${token}" \
      "${base_url}/admin/realms/${realm}/clients?clientId=${client_id}" \
      | jq -r '.[0].id // empty' 2>/dev/null || true)
   if [[ -z "$client_uuid" ]]; then
      if ! _curl -sf -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            --data-binary "$(jq -n --arg cid "$client_id" '{clientId:$cid, enabled:true, protocol:"openid-connect", publicClient:true, directAccessGrantsEnabled:true, standardFlowEnabled:false, serviceAccountsEnabled:false}')" \
            "${base_url}/admin/realms/${realm}/clients" >/dev/null; then
         _warn "[keycloak] failed to create smoke client '${client_id}'"
         return 0
      fi
      _info "[keycloak] created smoke client '${client_id}' in realm '${realm}'"
   fi

   local user_uuid
   user_uuid=$(_curl -sf -H "Authorization: Bearer ${token}" \
      "${base_url}/admin/realms/${realm}/users?username=${username}&exact=true" \
      | jq -r '.[0].id // empty' 2>/dev/null || true)
   if [[ -z "$user_uuid" ]]; then
      if ! _curl -sf -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            --data-binary "$(jq -n --arg u "$username" '{username:$u, enabled:true}')" \
            "${base_url}/admin/realms/${realm}/users" >/dev/null; then
         _warn "[keycloak] failed to create smoke user '${username}'"
         return 0
      fi
      user_uuid=$(_curl -sf -H "Authorization: Bearer ${token}" \
         "${base_url}/admin/realms/${realm}/users?username=${username}&exact=true" \
         | jq -r '.[0].id // empty' 2>/dev/null || true)
   fi
   if [[ -z "$user_uuid" ]]; then
      _warn "[keycloak] smoke user '${username}' not resolvable after create; skipping"
      return 0
   fi

   jq -n --arg p "$password" '{type:"password", value:$p, temporary:false}' > "$wd/reset.json"
   if ! _curl -sf -X PUT \
         -H "Authorization: Bearer ${token}" \
         -H "Content-Type: application/json" \
         --data-binary "@$wd/reset.json" \
         "${base_url}/admin/realms/${realm}/users/${user_uuid}/reset-password" >/dev/null; then
      _warn "[keycloak] failed to set smoke user password"
      return 0
   fi

   printf '%s' "$username" > "$wd/uname"
   printf '%s' "$password" > "$wd/pword"
   _kubectl -n "$ns" create secret generic "$secret_name" \
      --from-file=username="$wd/uname" \
      --from-file=password="$wd/pword" \
      --dry-run=client -o yaml | _kubectl apply -f - >/dev/null

   _info "[keycloak] smoke user '${username}' seeded in realm '${realm}' (secret ${ns}/${secret_name})"
}

function test_keycloak() {
```

### Change 3 — `bin/k3dm-webhook`: Keycloak block falls back to the seeded Secret

**Exact old block (lines 1565–1571):**

```python
    kc_user = os.environ.get("K3DM_SMOKE_KC_USER")
    kc_pass = os.environ.get("K3DM_SMOKE_KC_PASS")
    kc_realm = os.environ.get("K3DM_SMOKE_KC_REALM", "shopping-cart")
    kc_client = os.environ.get("K3DM_SMOKE_KC_CLIENT", "frontend")
    kc_token = None
    if not (kc_user and kc_pass):
        results.append(("Keycloak login", None, "no credentials (set K3DM_SMOKE_KC_USER/PASS)"))
```

**Exact new block:**

```python
    kc_user = os.environ.get("K3DM_SMOKE_KC_USER")
    kc_pass = os.environ.get("K3DM_SMOKE_KC_PASS")
    kc_realm = os.environ.get("K3DM_SMOKE_KC_REALM", "shopping-cart")
    kc_client = os.environ.get("K3DM_SMOKE_KC_CLIENT", "frontend")
    kc_via_smoke_client = False
    if not (kc_user and kc_pass):
        seeded_user = _smoke_secret("identity", "username", "k3dm-smoke-user")
        seeded_pass = _smoke_secret("identity", "password", "k3dm-smoke-user")
        if seeded_user and seeded_pass:
            kc_user, kc_pass = seeded_user, seeded_pass
            if "K3DM_SMOKE_KC_CLIENT" not in os.environ:
                kc_client = "k3dm-smoke"
            kc_via_smoke_client = True
    kc_token = None
    if not (kc_user and kc_pass):
        results.append(("Keycloak login", None, "no credentials (k3dm-smoke-user Secret absent; set K3DM_SMOKE_KC_USER/PASS)"))
```

### Change 4 — `bin/k3dm-webhook`: Frontend block stays `⚪` when the smoke client was used

**Exact old block (lines 1589–1591):**

```python
    fe_path = os.environ.get("K3DM_SMOKE_FRONTEND_AUTHED_PATH", "/api/cart")
    if kc_token is None:
        results.append(("Frontend login", None, "skipped (no Keycloak token)"))
```

**Exact new block:**

```python
    fe_path = os.environ.get("K3DM_SMOKE_FRONTEND_AUTHED_PATH", "/api/cart")
    if kc_token is None:
        results.append(("Frontend login", None, "skipped (no Keycloak token)"))
    elif kc_via_smoke_client:
        results.append(("Frontend login", None, "skipped (smoke-client token not scoped for frontend audience)"))
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/keycloak.sh` | add smoke-seed config defaults; add `keycloak_seed_smoke_user` (idempotent, graceful, secret-safe) |
| `bin/k3dm-webhook` | Keycloak check falls back to seeded `identity/k3dm-smoke-user` Secret (client `k3dm-smoke`); Frontend check stays `⚪` when the smoke client token was used |

---

## Rules

- `shellcheck -S warning scripts/plugins/keycloak.sh` — zero **new** warnings.
- `python3 -m py_compile bin/k3dm-webhook` — clean.
- All secret-bearing values go to `curl`/`kubectl` via files (`--data-urlencode name@file`,
  `--data-binary @file`, `--from-file`) — **never** on the command line. Do not switch any of
  these to `--from-literal`, `-d value`, or inline `--data-urlencode name=value`.
- Do NOT add `-k` / `--insecure` to any `_curl` call.
- Do NOT modify the `frontend` client, the app realm import, `_smoke_test_services`, or the
  ArgoCD/Grafana blocks.
- Env vars still win — the webhook only falls back to the Secret when `K3DM_SMOKE_KC_USER/PASS`
  are unset; `_smoke_secret` returning `None` degrades to `⚪`, never a false red.
- Run `make restart-webhook` after the change (webhook code changed).
- Run `_agent_audit` before reporting done.

---

## Definition of Done

- [ ] `keycloak_seed_smoke_user` present directly above `test_keycloak`; uses `mktemp -d` +
      `trap 'rm -rf "$wd"' RETURN`; reads admin creds from `identity/keycloak-secrets`
      (`KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD`)
- [ ] 4 smoke-seed config defaults added after `KEYCLOAK_REALM_DISPLAY_NAME`
- [ ] Webhook Keycloak block sets `kc_via_smoke_client` and falls back via `_smoke_secret`
- [ ] Webhook Frontend block has the `elif kc_via_smoke_client:` `⚪` branch
- [ ] `shellcheck -S warning scripts/plugins/keycloak.sh` — no new warnings
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] `grep -c 'kc_via_smoke_client' bin/k3dm-webhook` → **3** (1 init + 1 set + 1 elif test)
- [ ] `make restart-webhook` exits 0
- [ ] `git show --stat` shows exactly two files changed (`scripts/plugins/keycloak.sh`, `bin/k3dm-webhook`)
- [ ] Committed and pushed to `k3d-manager-v1.17.0`
- [ ] memory-bank updated with commit SHA and task status (separate commit from the code)

**Commit message (exact):**
```
feat(keycloak): seed dedicated smoke user for real Keycloak login check
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/plugins/keycloak.sh` and `bin/k3dm-webhook`
- Do NOT touch the app-owned `frontend` client or the app realm import
- Do NOT put any secret on a command line (no `--from-literal`, no `-d password=...`)
- Do NOT commit to `main` — work on `k3d-manager-v1.17.0`
```
