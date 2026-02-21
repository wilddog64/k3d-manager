# Technical Context – k3d-manager

## Runtime Prerequisites

| Tool | Notes |
|---|---|
| Docker | Required for k3d (macOS default) |
| k3d | Installed automatically if missing |
| k3s | Required on Linux; systemd-based |
| kubectl | Must be on PATH |
| helm | Used for ESO, Jenkins, Vault installs |
| jq | JSON parsing in scripts |
| Bats | Auto-installed by `_ensure_bats` for tests |
| vault CLI | For PKI / unseal operations |

## Platform Defaults

- **macOS**: `CLUSTER_PROVIDER=k3d` (Docker-based, no root required)
- **Linux**: `CLUSTER_PROVIDER=k3s` (systemd-based, requires root/sudo for install)

## Technology Stack

### Kubernetes Layer
- **k3d**: Runs k3s inside Docker containers; k3d load balancer handles port mapping.
- **k3s**: Lightweight Kubernetes; installs via curl script; kubeconfig at
  `/etc/rancher/k3s/k3s.yaml`.

### Service Mesh
- **Istio**: Installed during `deploy_cluster`. Required for Jenkins TLS routing via
  VirtualService and Gateway resources. Jenkins cert is issued for the Istio ingress,
  not for Jenkins itself.

### Secret Management
- **HashiCorp Vault**: Deployed via Helm; auto-initialized and unsealed; PKI enabled;
  K8s auth method enabled for ESO integration.
- **ESO (External Secrets Operator)**: Deployed via Helm; creates SecretStore pointing
  to Vault; service plugins create ExternalSecret resources.
- **Vault PKI**: Issues TLS certs for Jenkins; cert is stored as a K8s Secret in the
  `istio-system` namespace.

### CI/CD
- **Jenkins**: Deployed via Helm; Vault-issued TLS cert; optional LDAP/AD auth via
  JCasC; cert rotation CronJob (`jenkins-cert-rotator`).
- **CronJob image**: `docker.io/google/cloud-sdk:slim` (configurable via
  `JENKINS_CERT_ROTATOR_IMAGE`).

### Directory Services
- **OpenLDAP**: Deployed in-cluster; supports standard schema and AD-compatible schema
  (`bootstrap-ad-schema.ldif`).
- **Active Directory**: External only; connectivity validated via DNS + LDAP port probe.
  Never deployed by this tool.

## Key Variable Files

| File | Purpose |
|---|---|
| `scripts/etc/cluster_var.sh` | Cluster ports, k3d cluster name defaults |
| `scripts/etc/vault/vars.sh` | Vault PKI TTLs, paths, roles |
| `scripts/etc/jenkins/vars.sh` | Jenkins cert CN, VirtualService hosts, rotator settings |
| `scripts/etc/jenkins/ad-vars.sh` | AD prod config (domain, server, TLS mode) |
| `scripts/etc/jenkins/cert-rotator.sh` | CronJob schedule and renewal threshold |
| `scripts/etc/ldap/vars.sh` | LDAP base DN, admin DN, ports |
| `scripts/etc/ad/vars.sh` | AD-specific defaults |
| `scripts/etc/k3s/vars.sh` | k3s kubeconfig path, node IP |
| `scripts/etc/azure/azure-vars.sh` | Azure Key Vault ESO backend settings |

## Important Paths

| Path | Purpose |
|---|---|
| `scripts/k3d-manager` | Main dispatcher / entry point |
| `scripts/lib/system.sh` | `_run_command`, `_kubectl`, `_helm`, `_curl`, `_ensure_bats` |
| `scripts/lib/core.sh` | Cluster lifecycle: create/deploy/destroy |
| `scripts/lib/cluster_provider.sh` | Provider abstraction |
| `scripts/lib/providers/k3d.sh` | k3d implementation |
| `scripts/lib/providers/k3s.sh` | k3s implementation |
| `scripts/lib/vault_pki.sh` | Vault PKI cert helpers |
| `scripts/lib/directory_service.sh` | Directory service abstraction |
| `scripts/lib/dirservices/openldap.sh` | OpenLDAP provider |
| `scripts/lib/dirservices/activedirectory.sh` | AD provider (36 tests, 100% passing) |
| `scripts/lib/secret_backend.sh` | Secret backend abstraction |
| `scripts/lib/secret_backends/vault.sh` | Vault backend implementation |
| `scripts/plugins/vault.sh` | Vault deploy / init / PKI / ESO wiring |
| `scripts/plugins/jenkins.sh` | Jenkins deploy + cert rotation + auth config |
| `scripts/plugins/ldap.sh` | OpenLDAP deploy + Vault secrets engine |
| `scripts/plugins/eso.sh` | ESO deploy + SecretStore |
| `scripts/plugins/azure.sh` | Azure Key Vault ESO provider |
| `scripts/lib/test.sh` | Bats runner integration |
| `scripts/tests/` | Bats test suites (core, lib, plugins) |
| `bin/smoke-test-jenkins.sh` | Manual Jenkins smoke test (SSL + auth, Phases 1-3 done) |
| `scratch/test-logs/` | Test run artifacts (gitignored) |
| `scripts/etc/ldap/bootstrap-ad-schema.ldif` | Pre-seeded AD-schema LDIF (alice/bob/charlie) |

## Debugging

```bash
ENABLE_TRACE=1 ./scripts/k3d-manager <command>   # writes trace to /tmp/k3d.trace
DEBUG=1 ./scripts/k3d-manager <command>           # bash -x mode
```

`_args_have_sensitive_flag` auto-disables trace for commands with
`--password`, `--token`, or `--username` to avoid credential leaks.

## Testing (Current, Post-Overhaul)

- Unit testing now emphasizes pure-logic BATS coverage only.
- Mock-heavy orchestration suites were removed due to drift; integration confidence is
  driven by live-cluster smoke tests.

Current BATS files in repo:
- `scripts/tests/core/install_k3s.bats`
- `scripts/tests/lib/cleanup_on_success.bats`
- `scripts/tests/lib/dirservices_activedirectory.bats`
- `scripts/tests/lib/ensure_bats.bats`
- `scripts/tests/lib/install_kubernetes_cli.bats`
- `scripts/tests/lib/read_lines.bats`
- `scripts/tests/lib/run_command.bats`
- `scripts/tests/lib/sha256_12.bats`
- `scripts/tests/lib/test_auth_cleanup.bats`
- `scripts/tests/plugins/eso.bats`
- `scripts/tests/plugins/vault.bats`

Smoke test entrypoint:

```bash
./scripts/k3d-manager test smoke
./scripts/k3d-manager test smoke jenkins
```

## ESO Critical Fix (Known)

ESO SecretStore `mountPath` must be `kubernetes` (not `auth/kubernetes`).
Using the wrong path results in SecretStore NotReady. Source:
`docs/issues/2025-10-19-eso-secretstore-not-ready.md`.

## Vault Seal Behavior

Vault seals on every pod/node restart. The `reunseal_vault` command retrieves
unseal shards from macOS Keychain (or Linux `libsecret`) and unseals automatically.
All Vault-dependent services (ESO, Jenkins, LDAP auth) are unhealthy while sealed.
Always run `reunseal_vault` after any cluster node restart.
