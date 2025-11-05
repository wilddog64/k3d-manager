# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

k3d-manager is a modular Bash-based utility for managing local Kubernetes development clusters with integrated service deployments (Istio, Vault, Jenkins, OpenLDAP, External Secrets Operator). The system uses a dispatcher pattern with lazy plugin loading for optimal performance.

**Main entry point:** `./scripts/k3d-manager <function> [args]`

## Development Commands

### Cluster Management
```bash
# Create and deploy a k3d cluster (default provider on macOS)
./scripts/k3d-manager create_cluster [cluster_name] [http_port] [https_port]
./scripts/k3d-manager deploy_cluster

# Deploy with k3s provider (Linux with systemd)
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster -f  # non-interactive

# Destroy cluster
./scripts/k3d-manager destroy_cluster
```

### Service Deployment
```bash
# Deploy External Secrets Operator
./scripts/k3d-manager deploy_eso

# Deploy Vault (includes automatic PKI setup and ESO integration)
./scripts/k3d-manager deploy_vault

# Deploy Jenkins (includes Vault PKI, ESO secrets, LDAP integration)
./scripts/k3d-manager deploy_jenkins

# Deploy OpenLDAP (ESO-integrated)
./scripts/k3d-manager deploy_ldap
```

### Testing
```bash
# Run all tests
./scripts/k3d-manager test all

# Run specific test suites
./scripts/k3d-manager test core      # core functionality tests
./scripts/k3d-manager test plugins   # plugin tests
./scripts/k3d-manager test lib       # library function tests

# Run specific test file or test case
./scripts/k3d-manager test install_k3d
./scripts/k3d-manager test install_k3d --case "_install_k3d exports INSTALL_DIR"
./scripts/k3d-manager test -v install_k3d --case "test case name"  # verbose

# Test logs stored in: scratch/test-logs/<suite>/<case-hash>/<timestamp>.log
```

## Architecture

### Core Components

**Dispatcher:** `scripts/k3d-manager` - Main entry point that sources libraries and loads plugins on demand.

**Libraries:** `scripts/lib/` - Core functionality:
- `system.sh` - System utilities, `_run_command` wrapper, package installation helpers
- `core.sh` - Cluster lifecycle operations (create/destroy/deploy)
- `test.sh` - Test framework integration (Bats)
- `cluster_provider.sh` - Provider abstraction layer
- `providers/k3d.sh`, `providers/k3s.sh` - Provider-specific implementations
- `vault_pki.sh` - Vault PKI certificate management helpers

**Plugins:** `scripts/plugins/` - Lazy-loaded feature modules:
- `vault.sh` - HashiCorp Vault deployment, initialization, PKI setup, ESO integration
- `jenkins.sh` - Jenkins deployment with Vault-issued TLS, cert rotation, LDAP auth
- `ldap.sh` - OpenLDAP deployment with Vault LDAP secrets engine integration
- `eso.sh` - External Secrets Operator deployment and SecretStore configuration
- `azure.sh` - Azure Key Vault ESO provider integration

**Configuration:** `scripts/etc/` - Templates and variables:
- `cluster_var.sh` - Cluster defaults (ports, paths)
- `vault/vars.sh` - Vault configuration (PKI settings, paths, TTLs)
- `jenkins/vars.sh` - Jenkins configuration (VirtualService hosts, TLS settings)
- `ldap/vars.sh` - LDAP connection parameters
- `*.yaml.tmpl` - Kubernetes manifest templates (processed with `envsubst`)

### Key Integration Patterns

**External Secrets Operator (ESO) Flow:**
1. Vault plugin enables K8s auth method and creates policies
2. ESO plugin deploys operator and creates SecretStore referencing Vault
3. Service plugins (Jenkins, LDAP) create ExternalSecret resources
4. ESO syncs secrets from Vault → Kubernetes secrets

**Jenkins Certificate Rotation:**
- Vault PKI issues initial TLS cert during deployment
- CronJob (`jenkins-cert-rotator`) runs periodically using `google/cloud-sdk:slim` image
- Job requests new cert from Vault, updates K8s secret, revokes old cert, restarts pods
- Controlled by `VAULT_PKI_*` variables in `scripts/etc/vault/vars.sh` and `scripts/etc/jenkins/vars.sh`

**Provider Abstraction:**
- `CLUSTER_PROVIDER` environment variable selects backend (k3d/k3s)
- `_cluster_provider()` returns active provider
- Provider-specific implementations in `scripts/lib/providers/`
- k3d: Docker-based, automatic credential management, port mapping via load balancer
- k3s: systemd-based, manual kubeconfig setup, direct host networking

## Plugin Development

Plugins are sourced only when their functions are invoked. Place new plugins in `scripts/plugins/`.

**Guidelines:**
- Public functions: no leading underscore
- Private functions: prefix with `_`
- Use helper wrappers: `_run_command`, `_kubectl`, `_helm`, `_curl`
- Keep functions idempotent
- Avoid side effects during source

**Plugin skeleton:**
```bash
#!/usr/bin/env bash
# scripts/plugins/mytool.sh

function mytool_do_something() {
  _kubectl apply -f my.yaml
}

function _mytool_helper() {
  # Private helper function
  :
}
```

**`_run_command` wrapper usage:**
```bash
# Prefer sudo but fall back to current user
_run_command --prefer-sudo -- apt-get install -y jq

# Require sudo, fail if unavailable
_run_command --require-sudo -- mkdir /etc/myapp

# Probe subcommand to decide sudo necessity
_run_command --probe 'config current-context' -- kubectl get nodes

# Suppress error messages (still returns exit code)
_run_command --quiet -- command_that_might_fail
```

## Important Configuration Variables

**Cluster Provider:**
- `CLUSTER_PROVIDER` / `K3D_MANAGER_PROVIDER` / `K3DMGR_PROVIDER` - Select backend (k3d/k3s)

**Vault PKI:**
- `VAULT_ENABLE_PKI` - Enable PKI bootstrap (default: 1)
- `VAULT_PKI_PATH` - Mount path (default: pki)
- `VAULT_PKI_CN` - Root CA common name (default: dev.local.me)
- `VAULT_PKI_ROLE` - Role name for issuing certs (default: jenkins-tls)
- `VAULT_PKI_MAX_TTL` - Root CA lifetime (default: 87600h = 10 years)
- `VAULT_PKI_ROLE_TTL` - Leaf cert lifetime (default: 720h = 30 days)

**Jenkins:**
- `VAULT_PKI_LEAF_HOST` - Common name for Jenkins cert (default: jenkins.dev.local.me)
- `JENKINS_VIRTUALSERVICE_HOSTS` - Comma-separated Istio VirtualService hosts
- `JENKINS_CERT_ROTATOR_IMAGE` - CronJob image (default: docker.io/google/cloud-sdk:slim)
- `JENKINS_HOME_PATH` - Host path for Jenkins storage (default: `${SCRIPT_DIR}/storage/jenkins_home`)

**k3s-specific:**
- `K3S_KUBECONFIG_PATH` - Path to k3s kubeconfig (default: /etc/rancher/k3s/k3s.yaml)
- `K3S_NODE_IP` / `NODE_IP` - Override detected node IP
- `K3S_CONFIG_DIR` - k3s configuration directory (default: /etc/rancher/k3s)

**Air-gapped deployments:**
- `ESO_HELM_CHART_REF` - Local ESO chart path
- `JENKINS_HELM_CHART_REF` - Local Jenkins chart path
- Set `*_HELM_REPO_URL` to empty string to skip repo operations

## Tracing and Debugging

```bash
# Enable trace output to /tmp/k3d.trace
ENABLE_TRACE=1 ./scripts/k3d-manager <command>

# Enable bash debug mode
DEBUG=1 ./scripts/k3d-manager <command>
```

## Testing Infrastructure

- Tests use [Bats](https://github.com/bats-core/bats-core) - automatically installed via `_ensure_bats` in `scripts/lib/system.sh`
- Test files: `scripts/tests/{core,lib,plugins}/*.bats`
- Test helpers: `scripts/tests/test_helpers.bash`
- Failed test logs include artifacts in `scratch/test-logs/` hierarchy

## Code Style Principles (from AGENTS.md)

When making changes to this codebase:
- **Minimal patches:** Prefer small, targeted changes over refactoring
- **Style consistency:** Maintain existing indentation, quoting, and naming conventions
- **LF line endings:** No CRLF
- **Shell blocks:** No inline comments unless explicitly requested
- **Secrets:** Use `${PLACEHOLDER}` variables, never hardcode secrets
- **Exact line ranges:** When editing, specify precise file:line-range targets

## Security Notes

- `_run_command` handles sudo probing and permission escalation safely
- `_args_have_sensitive_flag` detects sensitive CLI arguments to disable trace
- Trace output auto-disables for commands with `--password`, `--token`, `--username` flags
- PKI certificates auto-rotate; old certs are revoked in Vault after rotation
- External Secrets Operator syncs credentials from Vault without exposing them in git

## Common Troubleshooting

**Jenkins cert rotator image pull failures:**
- Set `JENKINS_CERT_ROTATOR_IMAGE` to accessible registry
- Update `scripts/etc/jenkins/vars.sh` for persistent configuration

**k3s auto-install requirements:**
- Linux with systemd
- Root/passwordless sudo access
- Open ports: 6443 (API), 10250 (kubelet), 8472/udp (flannel), 30000-32767 (NodePort)

**hostPath mount validation:**
- k3d clusters require volume mounts for Jenkins storage
- Missing mounts detected during deployment
- Recreate cluster with proper volume configuration if needed

**ESO secret sync issues:**
- Verify Vault is unsealed: `./scripts/k3d-manager deploy_vault`
- Check SecretStore status: `kubectl get secretstore -A`
- Validate Vault policies allow secret reads
