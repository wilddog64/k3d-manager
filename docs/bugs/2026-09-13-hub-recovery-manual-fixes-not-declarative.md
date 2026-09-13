# Bug: hub recovery depends on three manual fixes that no code path reproduces

**Filed:** 2026-09-13
**Branch:** `k3d-manager-v1.33.0`
**Incident:** `docs/issues/2026-09-11-hub-recovery-public-origin-and-eso.md`
**Status:** spec draft — design decisions below must be answered before a Codex handoff

---

## Summary

The 2026-09-11 controlled hub rebuild only reached a working state after three
hand-applied fixes. None of them is reproduced by bootstrap, refresh, or
`hub_recovery_*`, so the next server-container rebuild will regress the same
three ways: zero shopping-cart Applications, `SecretSyncedError` on every app
ExternalSecret, and a Cloudflare 502 on `frontend.3ai-talk.org`.

## Defect 1 — Hub-as-app-cluster registration is not recreated by recovery

**Live (correct) state, 2026-09-13:**

```text
secret cicd/ubuntu-k3s-app-cluster
  labels: argocd.argoproj.io/secret-type=cluster, k3d-manager/provider=k3d, k3d-manager/role=app-cluster
  stringData: name=ubuntu-k3s, server=https://kubernetes.default.svc, config={}
```

`services-git` selects on `k3d-manager/role=app-cluster`; without this Secret it
generates zero service Applications.

**Code today:** `register_app_cluster` (`scripts/plugins/argocd.sh:1322`) already
supports the in-cluster server (`:1353` switches environment to `infra`) but
**requires `ARGOCD_APP_CLUSTER_TOKEN`**, which is meaningless for
`https://kubernetes.default.svc`. Callers (`Makefile:208`, `bin/cluster-up:758`,
`bin/cluster-preflight:590`, `_hostinger_register_cluster`) all target a remote
app cluster. Nothing registers the hub itself, and `hub_recovery_restore`
(`scripts/plugins/hub_recovery.sh:187`) stops at PV data.

**Required behaviour:** an idempotent function that applies the in-cluster
registration Secret above (no token, `config={}`), invoked from the hub recovery
path. It must not relabel other cluster Secrets unless
`K3DM_EXCLUSIVE_APP_CLUSTER=true` (reuse `_argocd_set_active_app_cluster`).

## Defect 2 — Application secret prefixes are absent from every Vault ESO policy

**Evidence:** after restore, the only ESO Kubernetes role (`eso-ldap-directory`,
written by `ldap.sh:1136` via `_vault_configure_secret_reader_role`) covered LDAP,
Keycloak, observability, and platform-ops. Every `vault-backend` ExternalSecret
in the app namespaces failed with `could not get secret data from provider`
until a hand-written `eso-apps` policy was attached.

Secret paths the hub ExternalSecrets read today (`kubectl get externalsecret -A`,
2026-09-13), excluding identity/monitoring/platform-ops:

```text
secret/data/github/pat
secret/data/minio/credentials
secret/data/payment/{encryption,stripe,paypal}
secret/data/postgres/{orders,products,payment}
secret/data/rabbitmq/default
secret/data/redis/{cart,orders-cache}
```

**Required behaviour:** a declared, read-only `eso-apps` policy for exactly
those prefixes (`github/pat`, `minio`, `payment`, `postgres`, `rabbitmq`,
`redis`), attached to the ESO role, applied by the bootstrap/recovery path via
`_vault_build_policy_hcl` — never broadened to `secret/data/*`. Least privilege
per CLAUDE.md: `read` only.

## Defect 3 — The repo's static Cloudflare config carries a stale frontend origin

`bin/cluster-up:1689` seeds `~/.cloudflared/config.yml` from
`scripts/etc/cloudflared/config.yml`, which still says:

```yaml
  - hostname: frontend.3ai-talk.org
    service: http://127.0.0.2:80
```

The working live config is `http://127.0.0.1:8000` — the k3d serverlb host port
(published by OrbStack) that fronts the Istio ingress NodePort. Recovery restored
the stale `127.0.0.2:80` origin and produced a public 502. The `127.0.0.2:80`
listener belongs to the hostinger `frontend-browser-http` path
(`scripts/lib/providers/k3s-hostinger.sh:399`), so the correct origin depends on
which provider currently serves the frontend.

**Required behaviour:** the ingress origin for each hostname is derived from the
active provider (or one documented table keyed by provider), not a single static
file, and `bin/public-endpoint-probe` reads the same source.

## Design decisions needed before handoff

1. Defect 1 entry point: new `register_hub_app_cluster`, or teach
   `register_app_cluster` to skip the token requirement when
   `ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc`?
2. Defect 2: separate `eso-apps` role + policy, or a second policy on the
   existing ESO role? (The live fix attached a second policy to the role.)
3. Defect 3: provider-keyed origin table in `scripts/etc/cloudflared/`, or
   generate `config.yml` at refresh time? Which providers must be supported now
   (hub-only k3d, k3s-hostinger)?
4. Should `hub_recovery_restore --confirm` call all three, or should a separate
   `hub_recovery_reconcile` run after PV restore?

## Targets (expected)

- `scripts/plugins/argocd.sh`
- `scripts/plugins/vault.sh` and/or `scripts/plugins/eso.sh`
- `scripts/plugins/hub_recovery.sh`
- `scripts/etc/cloudflared/config.yml` (+ any new provider-keyed file)
- `bin/cluster-up`, `bin/public-endpoint-probe`
- BATS: `scripts/tests/plugins/hub_recovery.bats`, plus a new/extended suite for
  registration rendering and policy HCL (pure logic, no cluster mocks)

## Definition of Done (to be finalised with exact code blocks after decisions)

- [ ] Rendering the in-cluster registration Secret produces the labels/stringData above with no token
- [ ] `eso-apps` policy HCL contains exactly the six prefixes, `read` only
- [ ] Frontend origin for the hub provider is `http://127.0.0.1:8000`; no `127.0.0.2:80` remains in the hub path
- [ ] `shellcheck` clean on touched files; BATS green
- [ ] Commit on `k3d-manager-v1.33.0`, pushed; SHA reported

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the listed targets
- Do NOT commit to `main`
- Do NOT edit `scripts/lib/foundation/` (subtree)
- Do NOT grant `secret/data/*` or any write capability to ESO
- Do NOT run anything against a live cluster, Vault, or Cloudflare
