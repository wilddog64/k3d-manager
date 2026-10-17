# e2e-sandbox Tier 2 cannot mint a Keycloak token (doubled realm path, no e2e client on the hub realm)

**Status:** OPEN — fix spec written 2026-10-17 (Option A, below); implementation pending
**Priority:** P1
**Approval:** operator, 2026-10-17 — "go with your recommendation (A)"
**Severity:** High — every Tier 2 Stripe test fails 401 before reaching payment-service
**Found by:** Claude, live run `1792198836-11122` (2026-10-17T01:03Z), the first a′ run to reach Playwright
**Introduced by:** `945018ee` (v1.36.0 Tier 2 manifest); exposed since shopping-cart-e2e-tests #9/#10
(2026-10-02), when the payment flow started minting a real bearer token

## Symptom

4/4 `flows/stripe-checkout-orchestrator.spec.ts` tests got `401` (expected 400/400/200/402). Test stderr:

```
Error getting auth token: Error: Keycloak token request failed: 404 {"error":"HTTP 404 Not Found"...}
```

Everything before Playwright worked: hub-apps gate (15 Synced/Healthy), Stripe profile label, order and
payment restarts, Job created; cleanup reset the label to `none` and `payment.gateway.default` to `mock`.

## Cause — two defects

1. **Doubled realm path.** `_e2e_sandbox_job_manifest` (`scripts/plugins/e2e.sh`) sets
   `KEYCLOAK_URL=https://keycloak.3ai-talk.org/realms/shopping-cart`, but `tests/helpers/auth.ts`
   builds `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token`. The request goes to
   `/realms/shopping-cart/realms/shopping-cart/...` → 404 (probed: realm discovery 200, doubled path 404).
   Tier 1 sets the base URL (`http://keycloak:8080`) and is unaffected.
2. **No e2e identity on the hub realm.** The helper uses a password grant with client `e2e-tests`,
   a client secret, and user `e2e-user`. Those exist only in the Tier 1 throwaway Keycloak
   (`scripts/etc/e2e/keycloak.yaml`). The Tier 2 Job passes no `KEYCLOAK_CLIENT_ID`,
   `KEYCLOAK_CLIENT_SECRET`, username or password, and the hub `shopping-cart` realm has no such
   client. Fixing (1) alone turns the 404 into `invalid_client`.

## Options (operator decision)

- **A — e2e client + user in the hub realm.** Confidential client `e2e-tests` (direct-access grants on,
  no browser flows, scoped roles only) and a non-admin `e2e-user`; client secret and password in Vault,
  synced to the sandbox by ESO into a run-scoped Secret the Job reads. Cost: a password-grant client on
  the public Keycloak — mitigate with a long random secret and no admin roles.
- **B — client-credentials grant.** Service-account client, no user. Needs the e2e helper to support
  `client_credentials` and the services to accept a service-account token. Smaller attack surface; more
  cross-repo work.
- **C — Tier 2 skips auth.** Run with `OAUTH2_ENABLED=false` against the sandbox services. Loses the
  real-token coverage that PR #9 added; not recommended.

Whichever option: set `KEYCLOAK_URL=https://keycloak.3ai-talk.org` and `KEYCLOAK_REALM=shopping-cart`.

## Fix (spec, 2026-10-17) — Option A

Branch: `k3d-manager-v1.43.4`. Single repo (k3d-manager); no change to shopping-cart-infra's realm JSON
or to shopping-cart-e2e-tests.

### Facts the design rests on (verified 2026-10-17)

- The e2e helper (`shopping-cart-e2e-tests/tests/helpers/auth.ts`) does a **password grant**:
  `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token` with `KEYCLOAK_CLIENT_ID`,
  `KEYCLOAK_CLIENT_SECRET`, `TEST_USERNAME`, `TEST_PASSWORD`.
- payment-service authorizes on realm roles (`realm_access.roles` → `ROLE_<NAME>`); checkout needs
  `PAYMENT_USER` or `PAYMENT_WRITE`. Tier 1 grants `e2e-user` exactly `PAYMENT_USER` and `PAYMENT_WRITE`
  and passes; basket/order extract roles but the Tier 1 run proves those two suffice.
- The hub realm has neither role, no `e2e-tests` client and no local users. Its LDAP federation is
  `READ_ONLY` with `syncRegistrations=false`, so a user created through the admin API stays a **local
  Keycloak user** — nothing is written to OpenLDAP.
- `bin/cluster-up` Step 10d imports the realm JSON only on a fresh realm (201); on 409 it reconciles the
  `argocd` client alone, and `_keycloak_reconcile_realm_client` errors if the client does not exist.
  So the e2e identity must be **created-or-updated through the admin API**, not added to the realm JSON.
- The sandbox ClusterSecretStore `vault-backend` uses the `app-cluster-reader` Vault policy, which already
  reads `secret/data/keycloak/*`. A new `keycloak/e2e` path needs **no policy change**.
- `services/shopping-cart-namespace` deploys to **both** `ubuntu-k3s` and `ubuntu-hostinger`, so the
  credentials must not go there as a GitOps ExternalSecret — that would put test credentials in prod.
- Tier 2 must stay Vault-free on the laptop side (BATS `sandbox verification uses hub profile flow
  without vault, ...`). The harness therefore never reads Vault: it applies a **run-scoped
  ExternalSecret on the sandbox** and the sandbox's ESO reads Vault.

### F1 — Vault `secret/keycloak/e2e` (seeded once, reused forever)

`scripts/plugins/shopping_cart.sh`, `shopping_cart_seed_sandbox_vault_kv`, directly after the
`keycloak/clients` block (before the final `_info "[acg-up] Vault KV seeded ..."`):

```bash
  if _vault_kv_exists "keycloak/e2e"; then
    _info "[acg-up] Reusing existing Vault secret keycloak/e2e"
    _e2e_kc_client_secret=$(_vault_kv_get_field "keycloak/e2e" "client_secret")
    _e2e_kc_user_password=$(_vault_kv_get_field "keycloak/e2e" "user_password")
  else
    _src_json=$(_seed_source_data "keycloak/e2e")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying keycloak/e2e from canonical source Vault"
      _vault_kv_put "${_src_json}" keycloak/e2e
      _e2e_kc_client_secret=$(printf '%s' "${_src_json}" | jq -r '.client_secret // empty')
      _e2e_kc_user_password=$(printf '%s' "${_src_json}" | jq -r '.user_password // empty')
    else
      _e2e_kc_client_secret=$(openssl rand -base64 36 | tr -d '=+/')
      _e2e_kc_user_password=$(openssl rand -base64 36 | tr -d '=+/')
      _vault_kv_put "{\"client_secret\":\"${_e2e_kc_client_secret}\",\"user_password\":\"${_e2e_kc_user_password}\"}" keycloak/e2e
    fi
  fi
```

`bin/cluster-up`, with the other `: "${...:=}"` defaults (after `: "${_grafana_client_secret:=}"`):

```bash
: "${_e2e_kc_client_secret:=}"
: "${_e2e_kc_user_password:=}"
```

### F2 — `_keycloak_ensure_e2e_identity` (create-or-update, idempotent)

New private function in `scripts/plugins/keycloak.sh`, after `_keycloak_reconcile_realm_client`.
Signature: `_keycloak_ensure_e2e_identity <base_url> <admin_token> <realm>`; secrets come from the
environment variables `E2E_KC_CLIENT_SECRET` and `E2E_KC_USER_PASSWORD`, never from argv. Every request
body that carries a secret is built with `jq -n --arg` and sent with `--data-binary @-` on stdin.
Use the file's existing `_curl` and `Authorization: Bearer` header style. Returns 1 (with `_err`) on
any failed call; returns 1 if either env var is empty.

1. **Roles.** For `PAYMENT_USER` and `PAYMENT_WRITE`: `POST /admin/realms/<realm>/roles` with
   `{"name": "<ROLE>"}`; HTTP 201 or 409 is success.
2. **Client `e2e-tests`.** Payload (secret injected with `--arg`):
   ```json
   {"clientId":"e2e-tests","name":"e2e-tests","enabled":true,"protocol":"openid-connect",
    "publicClient":false,"clientAuthenticatorType":"client-secret","secret":"<E2E_KC_CLIENT_SECRET>",
    "directAccessGrantsEnabled":true,"standardFlowEnabled":false,"implicitFlowEnabled":false,
    "serviceAccountsEnabled":false,"redirectUris":[],"webOrigins":[]}
   ```
   `GET /clients?clientId=e2e-tests` → if empty `POST /clients`, else `PUT /clients/<id>` with `.id` set
   (same pattern as `_keycloak_reconcile_realm_client`). The PUT rotates nothing: it rewrites the same
   secret from Vault, so a restore and a rebuild converge.
3. **User `e2e-user`.** `GET /users?username=e2e-user&exact=true` → if empty `POST /users` with
   `{"username":"e2e-user","enabled":true,"emailVerified":true,"email":"e2e-user@example.invalid",
   "firstName":"E2E","lastName":"User","requiredActions":[]}`, then re-GET for the id. Then always
   `PUT /users/<id>/reset-password` with `{"type":"password","value":"<E2E_KC_USER_PASSWORD>","temporary":false}`.
4. **Role mapping.** `GET /roles/PAYMENT_USER` and `GET /roles/PAYMENT_WRITE`, then
   `POST /users/<id>/role-mappings/realm` with the two role representations (idempotent in Keycloak).
   Grant nothing else: no `platform-*`, no client roles.
5. `_info "[keycloak] e2e identity ensured in realm '<realm>' (client e2e-tests, user e2e-user)"` — no values.

### F3 — call it from `bin/cluster-up` Step 10d

Immediately after the `argocd` PKCE removal succeeds (inside the same `if` chain, before the realm
temp file is removed):

```bash
      if E2E_KC_CLIENT_SECRET="${_e2e_kc_client_secret}" E2E_KC_USER_PASSWORD="${_e2e_kc_user_password}" \
          _keycloak_ensure_e2e_identity "http://localhost:${_kc_pf_port}" "${_kc_token}" "shopping-cart"; then
        _info "[acg-up] Keycloak e2e identity ensured"
      else
        kill "${_kc_pf_pid}" 2>/dev/null || true
        rm -f "${_realm_json_file}"
        _acg_fail "[acg-up] Failed to ensure the Keycloak e2e identity"
      fi
```

Fail-closed is deliberate: a hub without the identity makes every Tier 2 run 401, which is this bug.

### F4 — run-scoped ExternalSecret and the Job env (`scripts/plugins/e2e.sh`)

New `_e2e_sandbox_provision_keycloak_credentials`: pipe this manifest on **stdin** to
`_e2e_sandbox_kc apply -f -` (stdin keeps `vault` out of `_run_command` argv — the existing no-vault
BATS test must pass unchanged), then
`_e2e_sandbox_kc -n "$E2E_NAMESPACE" wait --for=condition=Ready externalsecret/e2e-keycloak-credentials --timeout="${E2E_ESO_TIMEOUT:-90}s"`;
on timeout `_err "[e2e] ExternalSecret e2e-keycloak-credentials did not become Ready — check Vault secret/keycloak/e2e and the sandbox ESO log"`.

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: e2e-keycloak-credentials
  namespace: shopping-cart-apps
  labels:
    app.kubernetes.io/part-of: k3dm-e2e
spec:
  refreshInterval: 0s
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: e2e-keycloak-credentials
    creationPolicy: Owner
  data:
    - secretKey: client-secret
      remoteRef:
        key: secret/data/keycloak/e2e
        property: client_secret
    - secretKey: user-password
      remoteRef:
        key: secret/data/keycloak/e2e
        property: user_password
```

`e2e_verify_sandbox`: new phase right after `provisioning-secrets`:

```bash
  _E2E_ACTIVE_PHASE="provisioning-keycloak-credentials"
  _e2e_sandbox_provision_keycloak_credentials
```

`_e2e_sandbox_exit_trap`: after `_e2e_sandbox_clear_profile`, add
`_run_command --soft -- kubectl --context ubuntu-k3s -n shopping-cart-apps delete externalsecret e2e-keycloak-credentials --ignore-not-found || true`
(`creationPolicy: Owner` garbage-collects the Secret).

`_e2e_sandbox_job_manifest`: replace the single `KEYCLOAK_URL` entry with:

```yaml
            - name: KEYCLOAK_URL
              value: https://keycloak.3ai-talk.org
            - name: KEYCLOAK_REALM
              value: shopping-cart
            - name: KEYCLOAK_CLIENT_ID
              value: e2e-tests
            - name: TEST_USERNAME
              value: e2e-user
            - name: KEYCLOAK_CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: e2e-keycloak-credentials
                  key: client-secret
            - name: TEST_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: e2e-keycloak-credentials
                  key: user-password
```

### Tests

- `scripts/tests/plugins/e2e.bats`:
  - Job manifest: `KEYCLOAK_URL` value is exactly `https://keycloak.3ai-talk.org` (assert the value has
    no `/realms`), and `KEYCLOAK_CLIENT_SECRET`/`TEST_PASSWORD` come from `secretKeyRef` `e2e-keycloak-credentials`.
  - Phase order: `provisioning-secrets` → `provisioning-keycloak-credentials` → `enabling-stripe`.
  - Exit trap deletes `externalsecret e2e-keycloak-credentials`, also when the run fails.
  - The existing no-vault test passes unchanged.
- `scripts/tests/plugins/keycloak.bats` (stub `_curl`, record argv and stdin to separate files):
  - client missing → POST; present → PUT with `.id`; user missing → POST then reset-password; present →
    reset-password only; role-mapping POST carries only `PAYMENT_USER` and `PAYMENT_WRITE`.
  - **Secret hygiene:** with sentinel values in the two env vars, the argv log contains neither sentinel;
    the stdin log does.
  - Empty env var → returns 1 before any `_curl` call.
- Each new test must fail against the pre-fix source (mutation check on a temp copy).

### Docs

`docs/guides/vcluster-e2e-harness.md` § Tier 2: how the run authenticates (hub realm client `e2e-tests`,
local user `e2e-user`, roles, Vault `secret/keycloak/e2e`, run-scoped ExternalSecret, why not GitOps).

### Security notes

- A password-grant client on the public Keycloak. Mitigations: 48-char random secret and password in
  Vault only; client has no browser flows, no redirect URIs, no service account; user holds only the two
  payment roles; the payment path stays in Stripe **test** mode on the sandbox.
- Hostinger runs the same realm; the identity exists there too but grants nothing beyond payment roles,
  and no credential is deployed to Hostinger.

## Files

- `scripts/plugins/shopping_cart.sh`
- `scripts/plugins/keycloak.sh`
- `bin/cluster-up`
- `scripts/plugins/e2e.sh`
- `scripts/tests/plugins/e2e.bats`
- `scripts/tests/plugins/keycloak.bats`
- `docs/guides/vcluster-e2e-harness.md`

## Rules

- Implement F1–F4 exactly; touch only the files above. No PR, no merge, no `--no-verify`, never `main`.
- Never print, echo or log a secret value; no secret in argv (stdin / env only).
- Do not run anything against a live cluster, Vault, Keycloak or the ACG sandbox — BATS stubs only.
- Gates (paste the output): `shellcheck scripts/plugins/keycloak.sh scripts/plugins/e2e.sh scripts/plugins/shopping_cart.sh bin/cluster-up`
  (zero new warnings); `bats scripts/tests/plugins/e2e.bats scripts/tests/plugins/keycloak.bats` (all pass).
- Commit message: `fix(e2e): give Tier 2 a hub Keycloak e2e identity and fix the doubled realm path`

## Live proof

On the next `make up` (or on the running hub via a one-off Step 10d rerun), then `make e2e-sandbox`:
the Playwright `stripe` project passes 4/4, the summary shows `result=pass`, and after the run
`kubectl --context ubuntu-k3s -n shopping-cart-apps get externalsecret,secret e2e-keycloak-credentials`
returns NotFound.
