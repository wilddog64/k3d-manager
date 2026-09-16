# Bug: the Keycloak reconcile hook re-breaks the browser flow, blocking all shopping-cart SSO

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-15
**Status:** OPEN
**Severity:** high — no one can log in to the `shopping-cart` realm through a browser: the frontend and ArgoCD SSO both fail.
**Fix lands in:** `shopping-cart-infra` — `identity/keycloak/keycloak-reconcile-hook-job.yaml`
**Regression of:** `docs/bugs/archive/2026-08-20-pre-v1.26/v1.4.11-bugfix-keycloak-browser-flow-mixed-requirements.md` — diagnosed 2026-08, fixed **only by hand on the live cluster**, and its "Permanent fix needed" was never done.

## Evidence (2026-09-15, live, read-only)

`make status CLUSTER_PROVIDER=k3s-hostinger` reported:

```
✗ Frontend SSO login: admin … credentials rejected; developer … credentials rejected; operator … credentials rejected
✗ ArgoCD SSO login: admin via Vault keycloak/users/admin: credentials rejected
```

The credentials are **not** the problem:

- Vault `secret/keycloak/users/<user>` binds successfully against `openldap-0` for admin, developer and operator (`ldapwhoami`, verified in-pod; MATCH for all three).
- Keycloak itself issues a token for those same passwords: a direct grant on realm `shopping-cart` via `admin-cli` returns **200** for developer and operator.
- Keycloak federates openldap-0 as intended (`connectionUrl=ldap://openldap.identity.svc.cluster.local:389`, `usersDn=ou=users,dc=home,dc=org`), so shopping-cart-infra PRs #96/#97 (2026-09-12) did land. The 2026-09-04 osixia-vs-openldap issue doc is **stale**.

The browser flow is what fails. Any valid authorization request returns **HTTP 400** with a
generic "We are sorry… Invalid username or password." page **before a login form is ever
rendered** — for every redirect_uri, with correct PKCE. Keycloak's log names the cause:

```
WARN REQUIRED and ALTERNATIVE elements at same level! Those alternative executions
     will be ignored: [auth-cookie, identity-provider-redirector, null]
WARN KC-SERVICES0013: Failed authentication: AuthenticationFlowException
WARN type="LOGIN_ERROR" clientId="frontend" userId="null" error="invalid_user_credentials"
```

Live flow `browser-with-conditional-otp` (the realm's `browserFlow`):

```
level=0 Cookie                                      ALTERNATIVE
level=0 Kerberos                                    DISABLED
level=0 Identity Provider Redirector                ALTERNATIVE
level=0 browser-with-conditional-otp forms          ALTERNATIVE
level=1   Username Password Form                    REQUIRED
level=1   … Browser - Conditional OTP               CONDITIONAL
level=2     Condition - user configured             REQUIRED
level=2     OTP Form                                REQUIRED
level=0 otp-conditional-subflow                     CONDITIONAL   ← the defect
level=1   Condition - user role                     DISABLED
```

## Root cause

`identity/keycloak/keycloak-reconcile-hook-job.yaml` creates `otp-conditional-subflow` as a
**top-level** execution of `browser-with-conditional-otp` and sets it `CONDITIONAL`. Keycloak's
rule is that when REQUIRED/CONDITIONAL and ALTERNATIVE executions share a level, the ALTERNATIVE
ones are ignored — so the `forms` subflow holding **Username Password Form** is skipped, the flow
has nothing left to execute, and it throws. The misleading page text is why the login check
labelled it "credentials rejected".

The top-level subflow is also **redundant**: `browser-with-conditional-otp` is copied from the
stock `browser` flow, which already contains a conditional OTP subflow at level 1 inside `forms`.
Its one child here (`Condition - user role`) is `DISABLED`, so it contributes nothing.

The v1.4.11 hand-fix (set `forms` REQUIRED, delete the orphan execution) was wiped when the flow
was recreated — Keycloak restarted 2026-09-12, the PostSync reconcile hook ran, and the creation
branch is guarded only by "does the flow already exist".

## Fix (in `shopping-cart-infra`, on a feature branch)

1. **Stop creating the top-level `otp-conditional-subflow`.** Remove that creation block and the
   execution-id lookup / `CONDITIONAL` update that follow it.
2. **Configure the inherited subflow instead.** Attach the `Condition - user role` config and the
   OTP Form requirement to the level-1 conditional OTP subflow that the flow copy already provides,
   so MFA intent is preserved without a second subflow.
3. **Make the hook self-healing, not create-once.** The existing-flow branch must also assert the
   invariant, so a drifted realm is repaired rather than skipped:
   - no execution other than `Cookie`, `Kerberos`, `Identity Provider Redirector` and `<flow> forms`
     at level 0;
   - `<flow> forms` is `ALTERNATIVE` with `Username Password Form` `REQUIRED` beneath it;
   - delete any stray top-level `otp-conditional-subflow` execution it finds.
4. **Fail loudly.** If the invariant cannot be restored, the hook exits non-zero — a broken
   browser flow must not look like a successful sync.

## Acceptance

1. Re-run the reconcile hook (or let ArgoCD PostSync run it) and re-read the flow: level 0 holds
   only Cookie / Kerberos / IdP Redirector / forms.
2. `GET https://keycloak.3ai-talk.org/realms/shopping-cart/protocol/openid-connect/auth?…` with a
   valid S256 PKCE challenge returns **200 with a login form**, not 400.
3. A browser login to the frontend and to ArgoCD "Log in via Keycloak" succeeds as `developer`.
4. `make status CLUSTER_PROVIDER=k3s-hostinger` → `✓ Frontend SSO login`, `✓ ArgoCD SSO login`.
5. Restart Keycloak once and repeat step 2 — the flow must still be correct.

## Follow-up (separate, do not fix here)

The realm user `admin` resolves to LDAP entry `cn=jenkins-admin,ou=users,dc=home,dc=org`, while
`developer` and `operator` map to `uid=<user>,…` as expected. Worth its own investigation once
SSO logins work again.

## What NOT to do

- Do not hand-patch the live realm with `kcadm`/admin API: the reconcile hook re-applies on each
  sync, which is exactly how this regressed.
- Do not edit the `shopping-cart-infra` repo directly or from `main` — spec + Codex on a feature branch.
- Do not disable MFA wholesale to make the flow "work".
- Do not touch the LDAP federation config; it is correct.
- Do not print, log, or commit any credential.
- No PR, no merge, no `main` commit, no force-push, no `--no-verify`.
