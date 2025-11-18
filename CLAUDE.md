# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

k3d-manager is a modular Bash-based utility for managing local Kubernetes development clusters with integrated service deployments (Istio, Vault, Jenkins, OpenLDAP, External Secrets Operator). The system uses a dispatcher pattern with lazy plugin loading for optimal performance.

**Main entry point:** `./scripts/k3d-manager <function> [args]`

## Current Work in Progress (2025-11-17)

**Status:** Testing certificate rotation functionality (Priority 1 task)

**Branch:** `ldap-develop`

**What's Complete:**
- ✅ Active Directory provider implementation (all functions)
- ✅ Automated tests for AD provider (36 tests, 100% passing)
- ✅ Documentation updates (CLAUDE.md, testing guides)
- ✅ Certificate rotation test plan created

**Current Task:** Certificate Rotation Validation
- **Location:** `docs/tests/certificate-rotation-validation.md`
- **Status:** Ready to execute on Ubuntu/k3s
- **Effort:** ~15 minutes active testing

**Test Configuration Created:**
```bash
# File: /tmp/cert-rotation-test.env
export VAULT_PKI_ROLE_TTL="10m"                    # 10-min cert lifetime for testing
export JENKINS_CERT_ROTATOR_RENEW_BEFORE="300"     # Renew at 5 min remaining
export JENKINS_CERT_ROTATOR_SCHEDULE="*/2 * * * *" # Check every 2 minutes
export JENKINS_CERT_ROTATOR_ENABLED="1"
```

**Next Steps (on Ubuntu with k3s):**
1. Deploy k3s cluster: `CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster -f`
2. Load test config: `source /tmp/cert-rotation-test.env`
3. Deploy Jenkins: `./scripts/k3d-manager deploy_jenkins --enable-vault`
4. Follow test plan: `docs/tests/certificate-rotation-validation.md`
5. Document results

**Why This Matters:**
- Certificate rotation code EXISTS but has NEVER been tested
- Unknown if auto-rotation actually works in production
- High impact if broken (service outages from expired certs)
- Must validate before considering AD work "complete"

**Remaining After This:**
- End-to-end AD integration test
- Documentation completion (cert rotation guide, Mac AD setup)
- Optional: monitoring recommendations, additional tests

**Reference Documents:**
- Test plan: `docs/tests/certificate-rotation-validation.md`
- Prioritized tasks: `docs/plans/remaining-tasks-priority.md`
- Recent commits: `cf89579`, `6ab4af1`, `850fa9c`

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

# Deploy Jenkins (includes Vault PKI, ESO secrets, directory service integration)
./scripts/k3d-manager deploy_jenkins

# Deploy Jenkins with standard LDAP integration
./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault

# Deploy Jenkins with AD schema testing (OpenLDAP with AD-compatible schema)
./scripts/k3d-manager deploy_jenkins --enable-ad --enable-vault

# Deploy Jenkins with production Active Directory integration
AD_DOMAIN=corp.example.com \
  ./scripts/k3d-manager deploy_jenkins --enable-ad-prod --enable-vault

# Deploy OpenLDAP (ESO-integrated, standard schema)
./scripts/k3d-manager deploy_ldap

# Deploy OpenLDAP with AD-compatible schema (for testing AD integration)
./scripts/k3d-manager deploy_ad --enable-vault
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
- `dirservices/openldap.sh`, `dirservices/activedirectory.sh` - Directory service provider implementations

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
- `jenkins/ad-vars.sh` - Active Directory configuration for production AD integration
- `ldap/vars.sh` - LDAP connection parameters
- `ldap/bootstrap-ad-schema.ldif` - AD-compatible LDAP schema for testing
- `ad/vars.sh` - Active Directory provider configuration
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

**Directory Service Abstraction:**
- `DIRECTORY_SERVICE_PROVIDER` environment variable selects authentication backend (openldap/activedirectory)
- Provider-specific implementations in `scripts/lib/dirservices/`
- OpenLDAP: In-cluster deployment, standard LDAP schema, simple bind authentication
- Active Directory: External/remote connection, AD-specific schema, supports TOKENGROUPS optimization
- Common interface: `_dirservice_*_init()`, `_dirservice_*_generate_jcasc()`, `_dirservice_*_validate_config()`
- Jenkins deployment modes:
  - `--enable-ldap`: Standard LDAP (OpenLDAP with simple schema)
  - `--enable-ad`: AD testing mode (OpenLDAP with AD-compatible schema)
  - `--enable-ad-prod`: Production AD (connects to external Active Directory)

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

**Active Directory (Production):**
- `AD_DOMAIN` - AD domain name (e.g., corp.example.com)
- `AD_SERVER` - Comma-separated AD server list (optional, auto-discovered if empty)
- `AD_SITE` - AD site name (optional)
- `AD_REQUIRE_TLS` - Require TLS connection (default: true)
- `AD_TLS_CONFIG` - TLS configuration mode (default: TRUST_ALL_CERTIFICATES)
- `AD_ADMIN_GROUP` - AD group for Jenkins admin access (default: Domain Admins)
- `AD_GROUP_LOOKUP_STRATEGY` - Group lookup strategy: RECURSIVE, TOKENGROUPS, or CHAIN (default: RECURSIVE)
- `AD_VAULT_PATH` - Vault path for AD credentials (default: secret/data/jenkins/ad-credentials)
- `AD_TEST_MODE` - Bypass connectivity checks for testing (default: 0)

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

**Active Directory connectivity issues:**
- Verify AD_DOMAIN is set: `echo $AD_DOMAIN`
- Test DNS resolution: `nslookup $AD_DOMAIN` or `host $AD_DOMAIN`
- Test LDAP port connectivity: `nc -zv $AD_DOMAIN 636` (LDAPS) or `nc -zv $AD_DOMAIN 389` (LDAP)
- Check VPN connection if using corporate AD
- Use `--skip-ad-validation` flag for testing without AD connectivity
- Enable test mode: `export AD_TEST_MODE=1` to bypass validation

**AD schema testing (OpenLDAP):**
- Verify LDIF loaded: `kubectl exec -n directory <pod> -- ldapsearch -x -b "DC=corp,DC=example,DC=com" -LLL dn`
- Check AD-style structure: DNs should use uppercase OU, CN, DC components
- Test authentication: Users should authenticate with sAMAccountName (e.g., "alice")
- See `docs/tests/active-directory-testing-instructions.md` for comprehensive testing guide
