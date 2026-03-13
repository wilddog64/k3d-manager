# Jenkins Authentication Guide

Jenkins can be deployed with different authentication backends depending on your environment.

## Authentication Modes

### Default Mode (No Directory Service)

```bash
./scripts/k3d-manager deploy_jenkins --enable-vault
```

Uses Jenkins built-in authentication with credentials stored in Vault via External Secrets Operator.

### Active Directory Testing Mode

```bash
./scripts/k3d-manager deploy_jenkins --enable-ad --enable-vault
```

Deploys OpenLDAP with Active Directory schema for local development and testing. This mode:
- Uses the `ldap` plugin with AD-compatible schema
- Configures OpenLDAP with `msPerson` and `msOrganizationalUnit` object classes
- Stores LDAP credentials in Vault
- Ideal for testing AD integration before deploying to production

### Production Active Directory Integration

```bash
# Configure AD connection
export AD_DOMAIN="corp.example.com"
export AD_SERVER="dc1.corp.example.com,dc2.corp.example.com"  # optional

./scripts/k3d-manager deploy_jenkins --enable-ad-prod --enable-vault
```

Connects Jenkins to a production Active Directory server. This mode:
- Uses the `active-directory` plugin
- Validates AD connectivity (DNS resolution and LDAPS port 636) before deployment
- Stores AD service account credentials in Vault
- Requires network access to the AD domain controllers

Configuration file: `scripts/etc/jenkins/ad-vars.sh`

#### Skip Validation (for testing)

```bash
./scripts/k3d-manager deploy_jenkins --enable-ad-prod --enable-vault --skip-ad-validation
```

**Note:** The three directory service modes (`--enable-ldap`, `--enable-ad`, `--enable-ad-prod`) are mutually exclusive. Choose one based on your environment.

### Automated Job Creation with Job DSL

Jenkins deployments include an automatic seed job that pulls Job DSL scripts from a GitHub repository. The seed job:
- Automatically creates and updates Jenkins jobs from code
- Polls your repository every 15 minutes for changes
- Processes all `.groovy` files in the `jobs/` directory structure

For setup instructions and examples, see **[Jenkins Job DSL Setup Guide](../jenkins-job-dsl-setup.md)**.

---

## Vault Agent Sidecar for LDAP Credentials

Jenkins uses Vault agent sidecar injection to securely manage LDAP bind credentials at runtime, eliminating hardcoded passwords in ConfigMaps and enabling rotation without redeployment.

### How It Works

When Jenkins is deployed with `--enable-vault`, the Vault agent injector automatically:

1. **Injects an init container** (`vault-agent-init`) that authenticates to Vault using the Jenkins service account
2. **Fetches LDAP credentials** from Vault's KV store (`secret/data/ldap/openldap-admin`)
3. **Writes credentials as files** to `/vault/secrets/` in a shared memory volume
4. **Jenkins reads credentials** using JCasC's `${file:...}` syntax at startup

### Benefits

- **No passwords in ConfigMaps** — Credentials never baked into configuration at deployment time
- **Easier password rotation** — Update Vault, restart Jenkins pod (no redeployment needed)
- **Ephemeral storage** — Secrets stored in memory-backed volume, cleared on pod termination
- **Backup mechanism** — K8s secrets (managed by ESO) remain available as fallback

### Password Rotation Procedure

```bash
# 1. Update password in Vault
kubectl exec -n vault vault-0 -- vault kv put secret/ldap/openldap-admin \
  LDAP_BIND_DN="cn=ldap-admin,dc=home,dc=org" \
  LDAP_ADMIN_PASSWORD="new-password-here"

# 2. Update LDAP server (if applicable)
./scripts/k3d-manager deploy_ldap

# 3. Restart Jenkins pod to fetch new credentials
kubectl delete pod -n jenkins jenkins-0
```

The new Jenkins pod automatically fetches fresh credentials from Vault via the sidecar.

### Key Components

- Vault Kubernetes auth role: `jenkins-ldap-reader`
- Vault policy: Read access to `secret/data/ldap/openldap-admin`
- Pod annotations: `vault.hashicorp.com/agent-inject: "true"`
- JCasC configuration: `managerPasswordSecret: '${file:/vault/secrets/ldap-bind-password}'`

### Verification

```bash
# Check vault-agent-init was injected
kubectl get pod -n jenkins jenkins-0 -o jsonpath='{.spec.initContainers[*].name}'

# Verify secret files exist
kubectl exec -n jenkins jenkins-0 -- ls -la /vault/secrets/
```

**Full implementation details:** `docs/implementations/vault-sidecar-implementation.md`
