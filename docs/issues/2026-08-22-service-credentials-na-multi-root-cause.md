# `make show-service-passwords` returns N/A + no service login (2026-08-22)

**Symptom:** `make show-service-passwords` showed `password: N/A` for ArgoCD,
Grafana, Prometheus, and Keycloak; user reported being unable to log in to any
service. Hub = `k3d-k3d-cluster` on the laptop; public domains `*.3ai-talk.org`.

## Root causes (three independent faults)

### 1. Vault port-forward down (FIXED)
`show-service-passwords` reads credentials from Vault at `http://127.0.0.1:18200`.
Nothing was listening on 18200 — the `com.k3d-manager.vault-port-forward`
LaunchAgent plist was **absent** from `~/Library/LaunchAgents/` (only the
unrelated `com.k3d-manager.vault-failover` Tier-3 profile-flip watchdog remained,
and it does **not** own the 18200 forward). Vault itself was unsealed and healthy
in-pod (`vault-0` in `secrets`, raft, `Sealed=false`).

**Fix:** `make install-vault-port-forward` → regenerates the plist
(`kubectl port-forward vault-0 18200:8200 -n secrets --context k3d-k3d-cluster`,
`RunAtLoad`+`KeepAlive`) and bootstraps the agent. Grafana + Alertmanager
passwords resolved immediately after.

### 2. Vault KV lost its display-mirror paths (services unaffected)
After the port-forward came back, Vault KV under `secret/` held only `ldap/` and
`observability/`. The `argocd/admin`, `k3d-manager/prometheus-basic-auth`,
`k3d-manager/alertmanager`, `k3d-manager/cloudflared`, and `keycloak/*` paths are
gone. **Key insight:** only `identity/openldap-admin` and
`monitoring/grafana-admin-credentials` are actually ESO-managed (both
`SecretSynced`, store `vault-backend` `Valid`). ArgoCD/Prometheus/Alertmanager
are **not** ESO-managed — their Vault paths are display/bootstrap mirrors only.
So the missing paths break `show-service-passwords` output, **not** the services:

- **ArgoCD** admin password still lives in `argocd-initial-admin-secret` (cicd ns).
  Retrieve with `argocd admin initial-password -n cicd`. Login works today.
- **Prometheus** basic-auth htpasswd is bcrypt inside
  `prometheus-kube-prometheus-stack-prometheus-web-config` — the plaintext only
  existed in the now-empty Vault path → not recoverable, needs rotation.
- **Alertmanager** display reads a local file
  (`~/.local/share/k3d-manager/alertmanager-basic-auth.env`), not Vault — worked
  throughout.

### 3. Keycloak not deployed on the hub (genuine login blocker)
`identity` ns has only `openldap-0`; no keycloak pod anywhere, no Keycloak app in
the ArgoCD set, no `keycloak/*` Vault paths. `deploy_keycloak`
(`scripts/plugins/keycloak.sh`) is not wired into the `make up` bootstrap for this
provider (only invoked in tests / fuller provisioning). Consequences: Keycloak
admin login and the **frontend SSO** (shopping-cart frontend on the hostinger app
cluster, currently `Degraded`) cannot work. Full recovery needs
`deploy_keycloak` + realm/OIDC-client reconcile + `secret/keycloak/users/*`
seeding + frontend client wiring — milestone-sized, not an incident quick-fix.

## Display bug noted in passing
`show-service-passwords` (Makefile) reads the Keycloak admin secret as
`keycloak-secrets` in `identity`, but `deploy_keycloak` creates
`keycloak-admin-secret` (`KEYCLOAK_ADMIN_SECRET_NAME`). Even once Keycloak is
deployed the display would read the wrong name → fix the Makefile.

## Remediation tracks (user chose all three)
1. **Re-seed** `argocd/admin` into Vault from the live `argocd-initial-admin-secret`
   (display-only; preserves the working password; needs a secret decode).
2. **Rotate** the unrecoverable creds (Prometheus basic-auth; cloudflared if used)
   — generate new, write to Vault, update the in-cluster credential, restart.
3. **Investigate/plan Keycloak** deployment on the hub incl. frontend SSO wiring.
