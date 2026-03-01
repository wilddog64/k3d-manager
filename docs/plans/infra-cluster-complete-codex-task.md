# Codex Task — Infra Cluster Completion (v0.5.0)

**Branch:** `feature/infra-cluster-complete`
**Target:** v0.5.0
**Status:** Pending Codex implementation

---

## Context

v0.4.0 merged. ArgoCD has been deployed live to the infra cluster. The only remaining
component to complete the infra layer is **Keycloak** — no plugin exists yet.

This task covers:
1. `scripts/plugins/keycloak.sh` — `deploy_keycloak` command + helpers
2. `scripts/etc/keycloak/` — all config templates and variable defaults
3. `scripts/tests/plugins/keycloak.bats` — bats test suite (min 6 cases)

---

## New Files to Create

| File | Purpose |
|---|---|
| `scripts/plugins/keycloak.sh` | Main plugin — `deploy_keycloak` + helpers |
| `scripts/etc/keycloak/vars.sh` | All Keycloak config variables |
| `scripts/etc/keycloak/values.yaml.tmpl` | Bitnami Helm values |
| `scripts/etc/keycloak/secretstore.yaml.tmpl` | ESO SecretStore (same pattern as ArgoCD) |
| `scripts/etc/keycloak/externalsecret-admin.yaml.tmpl` | Admin password from Vault |
| `scripts/etc/keycloak/externalsecret-ldap.yaml.tmpl` | LDAP bind password from existing `ldap/openldap-admin` path |
| `scripts/etc/keycloak/realm-config.json.tmpl` | Keycloak realm JSON with LDAP UserFederationProvider |
| `scripts/etc/keycloak/virtualservice.yaml.tmpl` | Istio VirtualService |
| `scripts/tests/plugins/keycloak.bats` | Bats test suite (min 6 cases) |

---

## Known Issue — Istio + Job Sidecar (must fix in values template)

During the ArgoCD live deploy, the `argocd-redis-secret-init` pre-install hook Job
hung indefinitely because Istio injected a sidecar that outlived the main container.
The Bitnami Keycloak chart has the same risk via its `keycloak-config-cli` job.

**Required fix in `scripts/etc/keycloak/values.yaml.tmpl`:**

```yaml
keycloakConfigCli:
  enabled: true
  existingConfigmap: keycloak-realm-config
  podAnnotations:
    sidecar.istio.io/inject: "false"   # Prevents Istio sidecar blocking job completion
```

See `docs/issues/2026-03-01-istio-sidecar-blocks-helm-pre-install-jobs.md`.

---

## Verification (Codex must run)

```bash
shellcheck scripts/plugins/keycloak.sh
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/keycloak.bats
```

Both must pass before committing. Fix any shellcheck warnings or bats failures.

---

## deploy_keycloak Execution Order

```
1. Help text + CLUSTER_ROLE guard (skip if "app")
2. Flag parsing: --enable-ldap, --enable-vault, --skip-istio, -h/--help
3. kubectl create namespace $KEYCLOAK_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
4. helm repo add bitnami ... && helm repo update
5. if --enable-vault:
     _keycloak_seed_vault_admin_secret
     _keycloak_setup_vault_policies
     envsubst < secretstore.yaml.tmpl | kubectl apply -f -
     envsubst < externalsecret-admin.yaml.tmpl | kubectl apply -f -
     wait --for=condition=Ready externalsecret/$KEYCLOAK_ADMIN_SECRET_NAME (60s)
6. if --enable-ldap:
     envsubst < externalsecret-ldap.yaml.tmpl | kubectl apply -f -
     wait --for=condition=Ready externalsecret/$KEYCLOAK_LDAP_SECRET_NAME (60s)
     _keycloak_apply_realm_configmap
7. render values.yaml.tmpl → tmp file (envsubst), helm upgrade --install
8. kubectl -n $KEYCLOAK_NAMESPACE rollout status statefulset/keycloak --timeout=300s
9. if NOT --skip-istio:
     envsubst < virtualservice.yaml.tmpl | kubectl apply -f -
10. Print: "Keycloak UI: https://$KEYCLOAK_VIRTUALSERVICE_HOST"
    Print: "Admin credentials: kubectl -n $KEYCLOAK_NAMESPACE get secret $KEYCLOAK_ADMIN_SECRET_NAME ..."
```

---

## Bats Test Cases (minimum 6)

1. `deploy_keycloak --help` exits 0 with usage text
2. `deploy_keycloak` skips when `CLUSTER_ROLE=app`
3. `KEYCLOAK_NAMESPACE` defaults to `identity`
4. `KEYCLOAK_HELM_RELEASE` defaults to `keycloak`
5. `deploy_keycloak` with unknown flag returns 1 with error message
6. `_keycloak_seed_vault_admin_secret` is defined as a function

---

## Pattern Reference

Mirror `scripts/plugins/argocd.sh` for all patterns:
- Source order at top of plugin
- `_info`, `_err`, `_warn` for logging
- `_kubectl`, `_helm` wrappers (not raw kubectl/helm)
- `_vault_login`, `_vault_policy_exists`, `_vault_exec_stream` for Vault operations
- `CLUSTER_ROLE` guard at top of public functions
- Exit code checking on Vault write operations (same as `_argocd_seed_vault_admin_secret`)
- `LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 24` for password generation

Mirror `scripts/tests/plugins/argocd.bats` for test patterns:
- `setup()` calls `init_test_env` then sources the plugin
- Tests use `run` for functions that should exit cleanly
- Stubs from `test_helpers.bash` handle kubectl/helm/vault calls

---

## Future: v0.6.0 — Keycloak Provider Interface

**Not part of this task.** Captured here so v0.6.0 has a clear spec.

### Motivation

The v0.5.0 Bitnami chart is suitable for the home lab. For production use the
**Keycloak Operator** (official, Red Hat/Keycloak project) is preferred — it manages
`Keycloak` and `KeycloakRealmImport` CRDs, handles rolling upgrades, and expects an
external database (e.g. CloudNativePG).

### Target Layout

```
scripts/lib/keycloak/
  bitnami.sh      ← extract from plugins/keycloak.sh (v0.5.0 logic moves here)
  operator.sh     ← new Keycloak Operator implementation

scripts/plugins/keycloak.sh   ← becomes a thin dispatcher
scripts/etc/keycloak/
  bitnami/        ← move existing values.yaml.tmpl here
  operator/       ← Keycloak CR + KeycloakRealmImport CR templates
```

### Interface Contract

Both `bitnami.sh` and `operator.sh` must implement:

| Function | Purpose |
|---|---|
| `_keycloak_provider_deploy` | Install Keycloak (helm install vs. operator CR apply) |
| `_keycloak_provider_wait_ready` | Wait for pods/CR Ready condition |
| `_keycloak_provider_configure_realm` | ConfigMap+configCli job vs. `KeycloakRealmImport` CR |

### Dispatch (vars.sh addition)

```bash
export KEYCLOAK_DEPLOY_MODE="${KEYCLOAK_DEPLOY_MODE:-bitnami}"  # bitnami | operator
```

`deploy_keycloak` sources the provider at runtime:
```bash
source "$SCRIPT_DIR/lib/keycloak/${KEYCLOAK_DEPLOY_MODE}.sh"
```

### Bitnami vs Operator Comparison

| | Bitnami (v0.5.0) | Operator (v0.6.0) |
|---|---|---|
| **Install** | `bitnami/keycloak` Helm chart | Keycloak Operator (OLM or Helm) |
| **Realm config** | ConfigMap → `keycloak-config-cli` job | `KeycloakRealmImport` CR |
| **Database** | Bundled PostgreSQL sub-chart | External (CloudNativePG recommended) |
| **HA / upgrades** | Manual replicas | Operator-managed |
| **Complexity** | Low | Higher — operator + CRDs + separate DB |

### Operator-specific Templates (v0.6.0)

```
scripts/etc/keycloak/operator/
  keycloak-cr.yaml.tmpl           ← Keycloak custom resource
  realm-import-cr.yaml.tmpl       ← KeycloakRealmImport custom resource
  clouodnativepg-cluster.yaml.tmpl ← External PostgreSQL cluster (optional)
```

### v0.6.0 Bats Additions

- `KEYCLOAK_DEPLOY_MODE` defaults to `bitnami`
- `deploy_keycloak` with `KEYCLOAK_DEPLOY_MODE=operator` calls `_keycloak_provider_deploy` from `operator.sh`
- `deploy_keycloak` with unknown `KEYCLOAK_DEPLOY_MODE` returns 1 with error message
