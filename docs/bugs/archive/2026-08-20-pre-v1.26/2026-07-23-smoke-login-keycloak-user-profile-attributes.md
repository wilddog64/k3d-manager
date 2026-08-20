# Bugfix: v1.17.0 — smoke user seed fails direct-grant login ("Account is not fully set up")

**Branch:** `k3d-manager-v1.17.0`
**Files:** `scripts/plugins/keycloak.sh`

---

## Before You Start

1. `git pull origin k3d-manager-v1.17.0` — get the latest branch state (this spec + prior spec-5 work).
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — the live-smoke findings that produced this bug.
3. Read `scripts/plugins/keycloak.sh` around `_keycloak_smoke_ensure_user` (currently lines 413–432) so the old block matches exactly before you edit.

---

## Problem

The spec-5 smoke user seed (`647b4181`) creates the `k3dm-smoke` user with only
`{username, enabled:true}`. On a fresh cluster the subsequent direct-access-grant
token mint against the `k3dm-smoke` client fails with:

```
HTTP 400  {"error":"invalid_grant","error_description":"Account is not fully set up"}
```

so the webhook smoke reports **Keycloak login ❌** even though the client, the
password credential, and the user are all otherwise correct.

**Root cause:** Keycloak 24+ enables the declarative **User Profile** by default,
where `email`, `firstName`, and `lastName` are **required** attributes. A user
created without them has an incomplete profile, and the direct-grant flow evaluates
the profile as not fully set up and refuses to mint a token. `_keycloak_smoke_ensure_user`
never populates those attributes.

Live-verified 2026-07-23: patching the existing user with
`{email, firstName, lastName, emailVerified:true}` via `PUT /users/{uuid}` made the
same token mint return **HTTP 200 with an access_token**, and the webhook smoke then
reported `Keycloak login: token minted (realm=shopping-cart)`.

---

## Reproduction

On a cluster whose `shopping-cart` realm has no `k3dm-smoke` user yet:

```bash
./scripts/k3d-manager keycloak_seed_smoke_user
# then (what the webhook smoke does):
curl -s -d grant_type=password -d client_id=k3dm-smoke \
  --data-urlencode username=k3dm-smoke --data-urlencode "password=$(kubectl -n identity get secret k3dm-smoke-user -o jsonpath='{.data.password}' | base64 -d)" \
  http://keycloak.shopping-cart.local/realms/shopping-cart/protocol/openid-connect/token
```

- **Expected:** HTTP 200, response contains `access_token`.
- **Actual:** HTTP 400, `invalid_grant` / `Account is not fully set up`, no token.

---

## Fix

### Change 1 — `scripts/plugins/keycloak.sh`: populate required profile attributes on the smoke user

Create the user WITH `email`/`firstName`/`lastName`/`emailVerified`, and also PUT
those attributes idempotently so a user left incomplete by a prior seed is repaired
on the next run (the create path is skipped when the user already exists).

**Exact old block (lines 413–432):**

```bash
function _keycloak_smoke_ensure_user() {
   local base_url="$1" token="$2" realm="$3" username="$4"
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
         return 1
      fi
      user_uuid=$(_curl -sf -H "Authorization: Bearer ${token}" \
         "${base_url}/admin/realms/${realm}/users?username=${username}&exact=true" \
         | jq -r '.[0].id // empty' 2>/dev/null || true)
   fi
   printf '%s' "$user_uuid"
}
```

**Exact new block:**

```bash
function _keycloak_smoke_ensure_user() {
   local base_url="$1" token="$2" realm="$3" username="$4"
   local user_uuid
   user_uuid=$(_curl -sf -H "Authorization: Bearer ${token}" \
      "${base_url}/admin/realms/${realm}/users?username=${username}&exact=true" \
      | jq -r '.[0].id // empty' 2>/dev/null || true)
   if [[ -z "$user_uuid" ]]; then
      if ! _curl -sf -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            --data-binary "$(jq -n --arg u "$username" '{username:$u, enabled:true, emailVerified:true, email:($u + "@k3dm.local"), firstName:$u, lastName:"smoke", requiredActions:[]}')" \
            "${base_url}/admin/realms/${realm}/users" >/dev/null; then
         return 1
      fi
      user_uuid=$(_curl -sf -H "Authorization: Bearer ${token}" \
         "${base_url}/admin/realms/${realm}/users?username=${username}&exact=true" \
         | jq -r '.[0].id // empty' 2>/dev/null || true)
   fi
   if [[ -n "$user_uuid" ]]; then
      if ! _curl -sf -X PUT \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            --data-binary "$(jq -n --arg u "$username" '{enabled:true, emailVerified:true, email:($u + "@k3dm.local"), firstName:$u, lastName:"smoke", requiredActions:[]}')" \
            "${base_url}/admin/realms/${realm}/users/${user_uuid}" >/dev/null; then
         return 1
      fi
   fi
   printf '%s' "$user_uuid"
}
```

**Notes for the implementer:**
- Do NOT touch any other function. `_keycloak_smoke_set_password` and the rest stay as-is.
- The email uses the username as the local part with a fixed `@k3dm.local` domain — a
  dev-only smoke user; `loginWithEmailAllowed` does not change username-based login.
- if-count of the edited function is **4** (`[[ -z ]]`, `! POST`, `[[ -n ]]`, `! PUT`) —
  well under `AGENT_AUDIT_MAX_IF=8`. Do NOT add an allowlist entry and do NOT raise the threshold.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/keycloak.sh` | `_keycloak_smoke_ensure_user` sets required User Profile attributes (email/firstName/lastName/emailVerified) on create and repairs them idempotently via PUT |

---

## Rules

- `shellcheck -S warning scripts/plugins/keycloak.sh` — zero new warnings
- `bash -n scripts/plugins/keycloak.sh` — parses clean
- `./scripts/k3d-manager _agent_audit` — passes (no if-count/bare-sudo/inline-cred regressions)
- No other files touched (this is a single-file code change; memory-bank is a SEPARATE commit)

---

## Definition of Done

- [ ] `_keycloak_smoke_ensure_user` matches the new block exactly
- [ ] `shellcheck -S warning scripts/plugins/keycloak.sh` clean
- [ ] `bash -n scripts/plugins/keycloak.sh` clean
- [ ] `./scripts/k3d-manager _agent_audit` passes
- [ ] Committed and pushed to `k3d-manager-v1.17.0`
- [ ] memory-bank updated (SEPARATE commit) with the commit SHA and task status

**Commit message (exact):**
```
fix(keycloak): set required User Profile attrs on smoke user so direct-grant login succeeds
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/plugins/keycloak.sh` (memory-bank is a separate commit)
- Do NOT commit to `main` — work on `k3d-manager-v1.17.0`
- Do NOT add an `if-count-allowlist` entry or raise `AGENT_AUDIT_MAX_IF`
