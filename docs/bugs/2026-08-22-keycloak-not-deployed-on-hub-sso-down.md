# Keycloak not deployed on the hub → SSO + admin login down (2026-08-22)

**Severity:** high (frontend SSO + Keycloak admin unusable).
**Parent incident:** `docs/issues/2026-08-22-service-credentials-na-multi-root-cause.md`.
**Cluster:** hub `k3d-k3d-cluster`; frontend on hostinger app cluster.

## Observed state

- `identity` ns holds only `openldap-0`; **no keycloak pod anywhere**.
- No Keycloak app in the ArgoCD set; no `keycloak/*` Vault KV paths; no
  `keycloak-admin-secret` in `identity`.
- `keycloak.3ai-talk.org` is wired end-to-end but dead: cloudflared routes it to
  `http://localhost:8880`, and `com.k3d-manager.keycloak-port-forward` is running
  as a **zombie** (forwards to a Service with no backing pod).
- `bin/get-keycloak-password` reads `secret/keycloak/users/<user>` (absent) → the
  dev-user passwords show `N/A`.

So the deployment intent is clearly "Keycloak on the hub" (port-forward :8880 +
cloudflared + LDAP federation against the live `openldap-0`), but it was never
run on this hub (or was lost on a rebuild without re-seed —
cf. `docs/bugs/2026-05-11-keycloak-admin-password-reseed-on-rebuild.md`).

## Remediation

Use the existing, idempotent `deploy_keycloak` (`scripts/plugins/keycloak.sh`) —
do **not** hand-roll manifests.

1. **Pre-req:** hub Vault reachable (port-forward on 18200 — restored in the
   parent incident), `openldap-0` Running, `htpasswd`/`jq`/`envsubst` present.
2. **Set the public host** so the VirtualService/route matches the live domain
   (`vars.sh` default is `keycloak.dev.local.me`):
   `export KEYCLOAK_VIRTUALSERVICE_HOST=keycloak.3ai-talk.org`
3. **Deploy with LDAP federation + Vault-seeded admin:**
   `./scripts/k3d-manager deploy_keycloak --enable-ldap --enable-vault`
   - seeds `secret/keycloak/admin` in Vault + ESO-syncs `keycloak-admin-secret`,
   - applies the realm ConfigMap and reconciles the OIDC client(s),
   - waits on `statefulset/keycloak`, applies the Istio VirtualService.
4. **Seed the SSO user passwords** the frontend/tests expect at
   `secret/keycloak/users/{admin,developer,operator}` (the path
   `bin/get-keycloak-password` reads). Confirm the `make up` / `acg-up` step that
   normally writes these ran; if not, seed via the same mechanism.
5. **Refresh the :8880 port-forward** so it stops being a zombie:
   `launchctl kickstart -k gui/$(id -u)/com.k3d-manager.keycloak-port-forward`
   (or the managed install target).
6. **Wire the hostinger frontend SSO** — verify the frontend's OIDC client
   (redirect URIs, issuer) matches this Keycloak; see the prior art
   `docs/bugs/2026-05-17-keycloak-jwt-issuer-mismatch-app-cluster.md` and
   `docs/bugs/2026-06-25-hostinger-refresh-keycloak-public-sso-gap.md`.

## Verification

- `kubectl --context k3d-k3d-cluster -n identity get pod -l app.kubernetes.io/name=keycloak` → Running.
- `curl -sI https://keycloak.3ai-talk.org/realms/master` → 200.
- `bin/get-keycloak-password admin` → a real password.
- Frontend login at `https://frontend.3ai-talk.org` completes the SSO round-trip.

## Related display bug (fix alongside)

`make show-service-passwords` reads the Keycloak admin secret as
`keycloak-secrets` in `identity`, but `deploy_keycloak` creates
`keycloak-admin-secret` (`KEYCLOAK_ADMIN_SECRET_NAME`). Update the Makefile to
read `keycloak-admin-secret` / `KEYCLOAK_ADMIN_PASSWORD_KEY` so the admin row
resolves once Keycloak is up.

## Caution

`deploy_keycloak` runs a Helm install + realm/client reconcile against the live
hub and touches the frontend's auth path — an outward-facing, hard-to-reverse
change. Run it deliberately (not as part of an unrelated batch), and confirm the
frontend client wiring before declaring SSO restored.
