# Jenkins Authentication Flow Analysis - Three Deployment Scenarios

## Executive Summary

This document analyzes how Jenkins authentication works across three deployment scenarios in k3d-manager. The key findings reveal:

1. **jenkins-admin password is DYNAMICALLY GENERATED** per deployment (via Vault password policy)
2. **LDAP JCasC config is conditionally included** only when `--enable-ldap` is used
3. **ESO always creates the jenkins-admin secret**, regardless of Vault/LDAP flags
4. **The awk filtering script correctly removes LDAP config** when LDAP is disabled

---

## Scenario 1: `deploy_jenkins --enable-vault --enable-ldap`

### What Happens

```bash
deploy_jenkins --enable-vault --enable-ldap [namespace] [vault-ns] [vault-release]
```

### Authentication Flow

#### Step 1: Vault Bootstrap
- `deploy_eso` deploys External Secrets Operator
- `deploy_vault` deploys Vault (unseals, initializes)
- Vault enables KV v2 and Kubernetes auth methods

#### Step 2: Jenkins Admin Password Generation
**File:** `scripts/plugins/jenkins.sh:1354-1393` (`_create_jenkins_admin_vault_policy`)

```bash
# Create password generation policy in Vault
vault write sys/policies/password/jenkins-admin policy=@jenkins-admin.hcl
```

Policy generates a **24-character random password** using:
```
length = 24
charset = abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 !@#$%^&*()-_=+[]{};:,.?
```

Then generates and stores the secret:
```bash
jenkins_admin_pass=$(vault read -field=password sys/policies/password/jenkins-admin/generate)
vault kv put secret/eso/jenkins-admin username=jenkins-admin password="$jenkins_admin_pass"
```

**Result:** Secret is stored at `secret/eso/jenkins-admin` with random password

#### Step 3: Jenkins Admin Vault Policy
Creates read access for Jenkins ESO service account:
- Policy: `eso-jenkins-admin`
- Service Account: Jenkins
- Permissions: Read `secret/eso/jenkins-admin` and `ldap/openldap-admin` (if LDAP enabled)

#### Step 4: ESO Secret Creation
**File:** `scripts/etc/jenkins/eso.yaml`

Creates two Kubernetes secrets:

**Secret 1: jenkins-admin**
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: jenkins-admin
  namespace: jenkins
spec:
  refreshInterval: 1h
  data:
    - secretKey: jenkins-admin-user
      remoteRef:
        key: eso/jenkins-admin
        property: username          # Maps to "jenkins-admin"
    - secretKey: jenkins-admin-password
      remoteRef:
        key: eso/jenkins-admin
        property: password          # Maps to random 24-char password
```

**Secret 2: jenkins-ldap-config**
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: jenkins-ldap-config
  namespace: jenkins
spec:
  data:
    - secretKey: LDAP_BIND_DN
      remoteRef:
        key: ldap/openldap-admin
        property: LDAP_BINDDN
    - secretKey: LDAP_BIND_PASSWORD
      remoteRef:
        key: ldap/openldap-admin
        property: LDAP_ADMIN_PASSWORD
    - secretKey: LDAP_BASE_DN
      remoteRef:
        key: ldap/openldap-admin
        property: LDAP_BASE_DN
```

#### Step 5: LDAP Deployment
`_deploy_jenkins_ldap` calls `deploy_ldap` and seeds LDAP service accounts in Vault

#### Step 6: Jenkins Helm Deployment
**File:** `scripts/etc/jenkins/values.yaml` (used as-is, no filtering)

Jenkins JCasC config includes **BOTH**:

1. **Admin user from ESO secret:**
```yaml
containerEnv:
  - name: JENKINS_ADMIN_USER
    value: "jenkins-admin"
  - name: JENKINS_ADMIN_PASS
    valueFrom:
      secretKeyRef:
        name: jenkins-admin
        key: jenkins-admin-password
```

2. **LDAP security realm from values.yaml:**
```yaml
JCasC:
  configScripts:
    01-security: |
      jenkins:
        securityRealm:
          ldap:
            configurations:
              - server: "${LDAP_URL}"
                rootDN: "${LDAP_BASE_DN}"
                managerDN: "${LDAP_BIND_DN}"
                managerPasswordSecret: "${LDAP_BIND_PASSWORD}"
                ...
        authorizationStrategy:
          projectMatrix:
            entries:
              - group:
                  name: "jenkins-admins"
                  permissions:
                    - "Overall/Administer"
```

### Result

**Authentication Method:** LDAP (primary) with local jenkins-admin fallback

- **LDAP login:** Users in LDAP `jenkins-admins` group can authenticate
- **Fallback:** `jenkins-admin` / `<random-24-char-password>` works if LDAP unavailable
- **Credentials source:** Vault (random, regenerated each deployment)
- **LDAP config:** Fully configured via JCasC
- **Secret sync:** ESO refreshes secrets hourly

---

## Scenario 2: `deploy_jenkins --enable-vault` (no LDAP)

### What Happens

```bash
deploy_jenkins --enable-vault [namespace] [vault-ns] [vault-release]
# OR equivalently:
JENKINS_LDAP_ENABLED=0 deploy_jenkins --enable-vault
```

### Authentication Flow

#### Steps 1-4: IDENTICAL to Scenario 1
- Vault bootstrap
- jenkins-admin password generated (same random 24-char password)
- ESO creates jenkins-admin secret
- **DIFFERENCE:** LDAP vault policy NOT created (no LDAP deployment)

#### Step 5: LDAP Deployment SKIPPED
`_deploy_jenkins_ldap` is NOT called

#### Step 6: Jenkins Helm Deployment with AWK Filtering
**File:** `scripts/plugins/jenkins.sh:1043-1123` (Helm deployment section)

Before deploying, the plugin detects `JENKINS_LDAP_ENABLED=0` and creates a filtered copy of values.yaml:

```bash
if (( ! JENKINS_LDAP_ENABLED )); then
   # Create temporary values file WITHOUT LDAP config
   awk '...' "$values_file" > "$temp_values"
   values_file="$temp_values"
fi
```

**The AWK filter removes:**

1. **Container environment variables starting with LDAP_:**
   - LDAP_URL
   - LDAP_GROUP_SEARCH_BASE
   - LDAP_USER_SEARCH_BASE
   - LDAP_BASE_DN
   - LDAP_BIND_DN
   - LDAP_BIND_PASSWORD

2. **Entire JCasC securityRealm block from 01-security config:**
   ```yaml
   securityRealm:
     ldap:
       configurations:
         ...
   ```

**How the AWK script works:**
- Tracks indentation level when entering securityRealm block
- Skips all lines until next sibling key at same or lesser indent
- Removes entire LDAP block and its nested ldap config
- Preserves authorizationStrategy section (not part of securityRealm)

### Result

**Authentication Method:** Local jenkins-admin only

- **Login:** Only `jenkins-admin` / `<random-24-char-password>` works
- **LDAP:** Completely absent (no JCasC config, no env vars, no plugin activation)
- **Credentials source:** Vault (random, regenerated each deployment)
- **Password:** Same dynamically generated password as Scenario 1
- **JCasC:** Does not include securityRealm ldap block

**Container will have:**
```yaml
containerEnv:
  - name: JENKINS_ADMIN_USER
    value: "jenkins-admin"
  - name: JENKINS_ADMIN_PASS
    valueFrom:
      secretKeyRef:
        name: jenkins-admin
        key: jenkins-admin-password
  - name: JAVA_OPTS
    value: "-Djenkins.install.runSetupWizard=false"
  # LDAP_* env vars are REMOVED
```

---

## Scenario 3: `deploy_jenkins` (no flags, minimal)

### What Happens

```bash
deploy_jenkins
# Equivalent to:
deploy_jenkins --disable-vault --disable-ldap
```

### Authentication Flow

#### Key Difference: No Vault/ESO
This scenario assumes Vault and ESO are already deployed separately

#### Steps 1-3: VAULT SKIPPED
- `deploy_eso` IS called (line 865: `if (( enable_vault )); then deploy_eso`)
- `deploy_vault` IS called (line 869-871)
- Vault bootstrap proceeds

**Wait - this means `--enable-vault` DEFAULTS to 1 if not specified?**

Actually, looking at line 727:
```bash
local enable_vault="${JENKINS_VAULT_ENABLED:-1}"
```

**Default is ENABLED (1)**. To disable, you must explicitly pass `--disable-vault`.

### CORRECTION: Actual Minimal Deployment

To truly deploy minimal Jenkins (no Vault):
```bash
deploy_jenkins --disable-vault --disable-ldap
```

This will:
- Skip `deploy_eso` (line 865)
- Skip `deploy_vault` (line 869)
- Skip `_deploy_jenkins_ldap` (line 877)
- Try to wait for existing jenkins-admin secret (line 945)
- Deploy Jenkins with existing credentials from Kubernetes

### Expected Behavior

1. **ESO NOT deployed:** Must have secrets pre-created manually
2. **Vault NOT deployed:** Credentials must exist in K8s cluster already
3. **LDAP NOT deployed:** Same as Scenario 2 (no LDAP config)
4. **Secret creation:** Jenkins-admin secret must already exist in namespace
5. **Error if secret missing:** `_jenkins_wait_for_secret` times out after 60s

### Result

**Authentication Method:** Local jenkins-admin (pre-created)

- **Assumption:** `jenkins-admin` secret already exists in Jenkins namespace
- **Expected keys:** Must have `jenkins-admin-user` and `jenkins-admin-password`
- **Source:** Manual creation or previous deployment
- **LDAP:** Same as Scenario 2 (disabled, no JCasC config)
- **Risk:** Deployment fails if credentials don't pre-exist

---

## Key Implementation Details

### Password Generation Policy

**File:** `scripts/plugins/jenkins.sh:1365-1371`

```hcl
length = 24
rule "charset" { charset = "abcdefghijklmnopqrstuvwxyz" }
rule "charset" { charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
rule "charset" { charset = "0123456789" }
rule "charset" { charset = "!@#$%^&*()-_=+[]{};:,.?" }
```

**Result:** Unique 24-character password on every `vault read -field=password sys/policies/password/jenkins-admin/generate`

### ESO ExternalSecret Specification

**File:** `scripts/etc/jenkins/eso.yaml:25-48`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: jenkins-admin
  namespace: jenkins
spec:
  refreshInterval: 1h
  target:
    name: jenkins-admin
    creationPolicy: Owner
    template:
      type: Opaque
  data:
    - secretKey: jenkins-admin-user
      remoteRef:
        key: eso/jenkins-admin
        property: username
    - secretKey: jenkins-admin-password
      remoteRef:
        key: eso/jenkins-admin
        property: password
```

**Key points:**
- `refreshInterval: 1h` - ESO syncs hourly, can pick up password changes
- `creationPolicy: Owner` - ESO creates/manages the K8s secret
- Maps `username` field from Vault to `jenkins-admin-user` K8s secret key
- Maps `password` field from Vault to `jenkins-admin-password` K8s secret key

### AWK Filtering Script Logic

**File:** `scripts/plugins/jenkins.sh:1052-1120`

The AWK script processes values.yaml line-by-line when LDAP is disabled:

```awk
BEGIN {
  skip_depth = 0                    # Tracking LDAP env var removal
  in_jcasc_security = 0             # In 01-security JCasC section?
  skip_security_realm = 0           # Skip securityRealm block?
}

# Track JCasC 01-security section entry
/^[[:space:]]*01-security:/ {
  in_jcasc_security = 1
}

# Detect securityRealm: and skip entire block
in_jcasc_security && /^[[:space:]]*securityRealm:/ {
  security_realm_indent = RLENGTH   # Remember indent level
  skip_security_realm = 1
  next
}

# Skip lines while in securityRealm block (until same/lesser indent sibling)
skip_security_realm {
  current_indent = RLENGTH
  if (current_indent <= security_realm_indent && $0 ~ /^[[:space:]]*[a-zA-Z]+:/) {
    skip_security_realm = 0          # Found sibling at same level
  }
  if (skip_security_realm) next
}

# Skip LDAP env var blocks (- name: LDAP_*)
/^[[:space:]]*- name: LDAP_/ {
  ldap_indent = RLENGTH
  skip_depth = 1
  next
}

# Skip continuation of LDAP env var
skip_depth > 0 {
  current_indent = RLENGTH
  if ($0 ~ /^[[:space:]]*- name:/ && current_indent == ldap_indent) {
    skip_depth = 0
  }
  if (skip_depth > 0) next
}

{ print }  # Print all non-skipped lines
```

### Vault Kubernetes Auth Setup

**File:** `scripts/plugins/vault.sh:1206-1261` (`_enable_kv2_k8s_auth`)

Sets up policies for ESO to read Jenkins secrets:
- Policy: `eso-reader` (read-only)
- Kubernetes role: `eso-reader`
- Bound to: ESO service account in external-secrets namespace

Jenkins then uses a different role:
- Policy: `eso-jenkins-admin` (created at line 883 in jenkins.sh)
- Kubernetes role: `eso-jenkins-admin` (or `${JENKINS_ESO_ROLE}`)
- Bound to: Jenkins ESO service account
- Allows reading: `eso/jenkins-admin`, `ldap/openldap-admin`

---

## Gaps and Potential Issues

### Issue 1: Default Behavior Ambiguity

**Problem:** Default values in `deploy_jenkins` function (line 726-727):
```bash
local enable_ldap="${JENKINS_LDAP_ENABLED:-1}"
local enable_vault="${JENKINS_VAULT_ENABLED:-1}"
```

Both default to ENABLED (1). This means:
- `deploy_jenkins` without args enables BOTH Vault AND LDAP
- User must explicitly `--disable-*` to disable
- **Confusing:** CLAUDE.md says "LDAP disabled by default" but code shows opposite

### Issue 2: LDAP JCasC Configuration Missing When LDAP Enabled but Vault Disabled

**Problem:** If user runs:
```bash
deploy_jenkins --enable-ldap --disable-vault
```

Then:
1. LDAP is deployed (`_deploy_jenkins_ldap` called)
2. But Vault is not, so `_create_jenkins_admin_vault_policy` fails (needs Vault)
3. Result: LDAP config in JCasC but no credentials to bind

**Root cause:** LDAP is treated as optional Vault integration, not standalone.

### Issue 3: Password Regeneration on Every Deploy

**Problem:** `_create_jenkins_admin_vault_policy` generates a new password each time:
```bash
jenkins_admin_pass=$(vault read -field=password sys/policies/password/jenkins-admin/generate)
```

This creates issues:
1. ESO refreshes secret hourly → Jenkins restarts
2. Every `deploy_jenkins` call changes the password
3. No way to use predictable password for integrations (CI/CD tools, etc.)
4. Previous password is lost (unless cached)

**Impact on Vault secret caching:** When ESO syncs the new password hourly, it overwrites the Kubernetes secret, potentially causing pod restarts if using `refreshInterval: 1h`.

### Issue 4: LDAP Admin Credentials Assumed Seeded

**Problem:** `_create_jenkins_vault_ad_policy` (lines 1411-1443) creates policies for LDAP credentials, but assumes:
```bash
path "secret/data/jenkins/ad-ldap"     { capabilities = ["read"] }
path "secret/data/jenkins/ad-adreader" { capabilities = ["read"] }
```

But where are these secrets seeded? The code doesn't create them - it assumes they pre-exist in Vault.

**Gap:** No corresponding `_vault_seed_ldap_admin_secrets` or similar. This path mismatch is mentioned in the policy but never populated.

### Issue 5: JCasC LDAP Config Uses Hardcoded Template Variables

**Problem:** `values.yaml` line 147-152 uses template variables:
```yaml
configurations:
  - server: "${LDAP_URL}"
    rootDN: "${LDAP_BASE_DN}"
    managerDN: "${LDAP_BIND_DN}"
    managerPasswordSecret: "${LDAP_BIND_PASSWORD}"
```

But when deploying without Vault (`--disable-vault`):
1. These env vars are removed by AWK filter
2. But if JCasC still references them, it will use empty values
3. Jenkins might fail to configure or use default values

**Actually, this is handled correctly:** The AWK filter removes the ENTIRE securityRealm block, not just the bindings, so this isn't an issue.

### Issue 6: AWK Filtering Only in Helm Deployment

**Problem:** The AWK filtering (lines 1043-1123) happens ONLY when deploying Jenkins Helm chart.

If user manually applies values.yaml or uses custom Helm override, they must handle LDAP filtering themselves. No automated safeguard for:
- `helm upgrade` with values.yaml containing LDAP
- GitOps workflows using values.yaml directly
- Custom Helm deployments

---

## Summary Table

| Aspect | Scenario 1: Vault+LDAP | Scenario 2: Vault Only | Scenario 3: Minimal |
|--------|----------------------|----------------------|---------------------|
| **Vault Deployed** | Yes | Yes | No |
| **ESO Deployed** | Yes | Yes | No |
| **LDAP Deployed** | Yes | No | No |
| **jenkins-admin Password** | Random (Vault) | Random (Vault) | Pre-existing |
| **Password Static** | No - regenerated on every deploy | No - regenerated on every deploy | Yes - must pre-exist |
| **LDAP JCasC Config** | Included (full securityRealm) | Removed (AWK filtered) | Removed (AWK filtered) |
| **Primary Auth Method** | LDAP + local fallback | Local jenkins-admin only | Local jenkins-admin only |
| **LDAP Env Vars** | Present (LDAP_*) | Removed (by AWK) | Removed (by AWK) |
| **Secret Sync** | Hourly (ESO) | Hourly (ESO) | None (static) |
| **Risk of Pod Restart** | High (hourly sync) | High (hourly sync) | None |
| **Prerequisite Secrets** | None (all created) | None (all created) | jenkins-admin must exist |

---

## Recommendations

1. **Fix Default Behavior Documentation:** Update CLAUDE.md to clarify that LDAP and Vault default to ENABLED, not disabled
2. **Add Password Generation Override:** Allow users to provide `JENKINS_ADMIN_PASSWORD` environment variable to skip dynamic generation
3. **Implement Safer ESO Refresh:** Use `syncPolicy: apply` with smart update detection instead of hourly full refresh
4. **Add LDAP-Only Deployment Option:** Support `--enable-ldap --disable-vault` with bundled secret storage
5. **Document Secret Caching:** Clarify which passwords are regenerated, when, and how to persist them
6. **Add Pre-flight Validation:** Check that required secrets exist before deployment in Scenario 3
