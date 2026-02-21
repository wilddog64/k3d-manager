# System Patterns – k3d-manager

## 1) Dispatcher + Lazy Plugin Loading

- `scripts/k3d-manager` is the sole entry point; it sources core libraries unconditionally
  and loads plugins **only when a function from that plugin is first invoked**.
- Benefit: fast startup; unused plugins never load.
- Convention: plugin files must not execute anything at source time (no side effects).

## 2) Configuration-Driven Strategy Pattern

Three environment variables select the active implementation at runtime:

| Variable | Selects | Default |
|---|---|---|
| `CLUSTER_PROVIDER` | Cluster backend | `k3d` (macOS) |
| `DIRECTORY_SERVICE_PROVIDER` | Auth backend | `openldap` |
| `SECRET_BACKEND` | Secret backend | `vault` |

Consumer code calls a generic interface function; the abstraction layer dispatches to the
provider-specific implementation. Adding a new provider requires a single new file — no
changes to consumers. This is the Bash equivalent of the Strategy OOP pattern.

## 3) Provider Interface Contracts

### Directory Service (`DIRECTORY_SERVICE_PROVIDER`)
All providers in `scripts/lib/dirservices/<provider>.sh` must implement:

| Function | Purpose |
|---|---|
| `_dirservice_<p>_init` | Deploy (OpenLDAP) or validate connectivity (AD) |
| `_dirservice_<p>_generate_jcasc` | Emit Jenkins JCasC `securityRealm` YAML |
| `_dirservice_<p>_validate_config` | Check reachability / credentials |
| `_dirservice_<p>_create_credentials` | Store service-account creds in Vault |
| `_dirservice_<p>_get_groups` | Query group membership for a user |
| `dirservice_smoke_test_login` | Validate end-user login works |

### Secret Backend (`SECRET_BACKEND`)
All backends in `scripts/lib/secret_backends/<backend>.sh` must implement:

| Function | Purpose |
|---|---|
| `<backend>_init` | Initialize / authenticate backend |
| `<backend>_create_secret` | Write a secret |
| `<backend>_create_secret_store` | Create ESO SecretStore resource |
| `<backend>_create_external_secret` | Create ESO ExternalSecret resource |
| `<backend>_wait_for_secret` | Block until K8s Secret is synced |

Supported: `vault` (complete). Planned: `azure`, `aws`, `gcp`.

### Cluster Provider (`CLUSTER_PROVIDER`)
Providers in `scripts/lib/providers/<provider>.sh`.
Supported: `k3d` (macOS/Docker), `k3s` (Linux/systemd).

## 4) ESO Secret Flow

```
Vault (K8s auth enabled)
  └─► ESO SecretStore (references Vault via K8s service account token)
       └─► ExternalSecret (per service, maps Vault path → K8s secret key)
            └─► Kubernetes Secret (auto-synced by ESO)
                 └─► Service Pod (mounts secret as env or volume)
```

Each service plugin is responsible for creating its own ExternalSecret resources.
Vault policies are created by the `deploy_vault` step and must allow each service's
service account to read its secrets path.

## 5) Jenkins Certificate Rotation Pattern

```
deploy_jenkins
  └─► Vault PKI issues leaf cert (jenkins.dev.local.me, default 30-day TTL)
       └─► Stored as K8s Secret in istio-system
            └─► jenkins-cert-rotator CronJob (runs every 12h by default)
                 ├─► Checks cert expiry vs. JENKINS_CERT_ROTATOR_RENEW_BEFORE threshold
                 ├─► If renewal needed: request new cert from Vault PKI
                 ├─► Update K8s secret in istio-system
                 ├─► Revoke old cert in Vault
                 └─► Rolling restart of Jenkins pods
```

Cert rotation has been validated via short-TTL/manual-job workflows (see
`docs/issues/2025-11-21-cert-rotation-fixes.md` and cert rotation test result docs).
The remaining gap is improving/validating dispatcher-driven cert-rotation test UX.

## 6) Jenkins Deployment Modes

| Command | Status | Notes |
|---|---|---|
| `deploy_jenkins` | **BROKEN** | Policy creation always runs; `jenkins-admin` Vault secret absent |
| `deploy_jenkins --enable-vault` | WORKING | Baseline with Vault PKI TLS |
| `deploy_jenkins --enable-vault --enable-ldap` | WORKING | + OpenLDAP standard schema |
| `deploy_jenkins --enable-vault --enable-ad` | WORKING | + OpenLDAP with AD schema |
| `deploy_jenkins --enable-vault --enable-ad-prod` | WORKING* | + real AD (requires `AD_DOMAIN`) |
| `deploy_jenkins --enable-ldap` (no vault) | **BROKEN** | LDAP requires Vault for secrets |

## 7) JCasC Authorization Format

Always use the **flat `permissions:` list** format for the Jenkins matrix-auth plugin:

```yaml
authorizationStrategy:
  projectMatrix:
    permissions:
      - "Overall/Read:authenticated"
      - "Overall/Administer:user:admin"
      - "Overall/Administer:group:Jenkins Admins"
```

Do NOT use the nested `entries:` format — it causes silent parsing failures with
the matrix-auth plugin.

## 8) Active Directory Integration Pattern

- AD is always an **external service** (never deployed in-cluster).
- `_dirservice_activedirectory_init` validates connectivity (DNS + LDAP port probe);
  it does not deploy anything.
- **Local testing path**: use `deploy_ad` to stand up OpenLDAP with
  `bootstrap-ad-schema.ldif` (AD-compatible DNs, sAMAccountName attrs). Test users:
  `alice` (admin), `bob` (developer), `charlie` (read-only). All password: `password`.
- **Production path**: set `AD_DOMAIN`, use `--enable-ad-prod`. `TOKENGROUPS`
  strategy is faster for real AD nested group resolution.
- `AD_TEST_MODE=1` bypasses connectivity checks for unit testing.

## 9) `_run_command` Privilege Escalation Pattern

Never call `sudo` directly. Always route through `_run_command`:

```bash
_run_command --prefer-sudo -- apt-get install -y jq   # sudo if available
_run_command --require-sudo -- mkdir /etc/myapp        # fail if no sudo
_run_command --probe 'config current-context' -- kubectl get nodes
_run_command --quiet -- might-fail                     # suppress stderr
```

`_args_have_sensitive_flag` detects `--password`, `--token`, `--username` and
automatically disables `ENABLE_TRACE` for that command.

## 10) Idempotency Mandate

Every public function must be safe to run more than once. Implement checks like:
- "resource already exists" → skip, not error.
- "helm release already deployed" → upgrade, not re-install.
- "Vault already initialized" → skip init, read existing unseal keys.

## 11) Cross-Agent Documentation Pattern

`memory-bank/` is the collaboration substrate across AI agent sessions.
- `projectbrief.md` – immutable project scope and goals.
- `techContext.md` – technologies, paths, key files.
- `systemPatterns.md` – architecture and design decisions.
- `activeContext.md` – current work, open blockers, decisions in flight.
- `progress.md` – done / pending tracker; must be updated at session end.

`activeContext.md` must capture **what changed AND why decisions were made**.
`progress.md` must maintain pending TODOs to prevent session-handoff loss.

## 12) Test Strategy Pattern (Post-Overhaul)

- Avoid mock-heavy orchestration tests that assert internal call sequences.
- Keep BATS for pure logic (deterministic, offline checks).
- Use live-cluster E2E smoke tests for integration confidence.

Smoke entrypoint:

```bash
./scripts/k3d-manager test smoke
./scripts/k3d-manager test smoke jenkins
```

Implemented in `scripts/lib/help/utils.sh`; runs available scripts in `bin/` and skips
missing/non-executable ones.
