# Argo CD Setup Guide

This guide covers the deployment and configuration of Argo CD in the k3d-manager environment with LDAP authentication, Vault integration, and Istio ingress.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Deployment](#detailed-deployment)
- [Configuration](#configuration)
- [Accessing Argo CD](#accessing-argo-cd)
- [LDAP Authentication](#ldap-authentication)
- [Vault Integration](#vault-integration)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)

## Overview

Argo CD is deployed as a GitOps continuous delivery tool with the following integrations:

- **LDAP/Dex Authentication**: OpenLDAP integration for user authentication
- **Vault/ESO Integration**: Admin password stored in Vault, synced via External Secrets Operator
- **Istio Ingress**: Exposed via VirtualService at `argocd.dev.local.me`
- **RBAC**: Group-based access control (admin and developer groups)
- **TLS**: Vault PKI-issued certificates for CLI access

**Architecture:**
```
User → Istio IngressGateway → Argo CD Server
                                    ↓
                         Dex → OpenLDAP (authentication)
                                    ↓
                              Vault → ESO → Admin Password
```

## Prerequisites

### Required Components

1. **Kubernetes Cluster**: k3d or k3s cluster running
2. **Istio**: Service mesh deployed and configured
3. **Vault**: HashiCorp Vault with Kubernetes auth enabled
4. **External Secrets Operator**: ESO deployed and configured
5. **OpenLDAP** (optional): For LDAP authentication testing

### Environment Variables

```bash
# Optional: Customize ArgoCD configuration
export ARGOCD_NAMESPACE="argocd"                    # Default namespace
export ARGOCD_VIRTUALSERVICE_HOSTS="argocd.dev.local.me"  # Ingress hostname
export ARGOCD_ADMIN_PASSWORD="<custom-password>"   # Custom admin password (optional)
```

## Quick Start

### Default Deployment (No LDAP)

Deploy Argo CD with basic configuration:

```bash
./scripts/k3d-manager deploy_argocd
```

This installs Argo CD with:
- Admin password stored in Vault
- Istio VirtualService for ingress
- Default configuration

### Full Deployment (LDAP + Vault)

Deploy with LDAP authentication and Vault integration:

```bash
# Deploy OpenLDAP first (if not already deployed)
./scripts/k3d-manager deploy_ldap

# Deploy Argo CD with all integrations
./scripts/k3d-manager deploy_argocd --enable-ldap --enable-vault
```

### Minimal Non-Interactive Deployment

For automation or CI/CD:

```bash
K3DMGR_NONINTERACTIVE=1 ./scripts/k3d-manager deploy_argocd --enable-ldap --enable-vault
```

## Detailed Deployment

### Step 1: Prepare Environment

Ensure prerequisites are deployed:

```bash
# Check cluster is running
kubectl get nodes

# Verify Istio is deployed
kubectl get svc -n istio-system istio-ingressgateway

# Verify Vault is running and unsealed
kubectl get pods -n vault

# Verify ESO is deployed
kubectl get pods -n external-secrets-system
```

### Step 2: Deploy OpenLDAP (Optional)

If using LDAP authentication:

```bash
./scripts/k3d-manager deploy_ldap
```

Wait for OpenLDAP to be ready:

```bash
kubectl wait --for=condition=ready pod -l app=openldap -n directory --timeout=300s
```

### Step 3: Deploy Argo CD

Deploy with desired configuration:

```bash
# Basic deployment
./scripts/k3d-manager deploy_argocd

# Or with LDAP
./scripts/k3d-manager deploy_argocd --enable-ldap --enable-vault
```

The deployment will:
1. Create `argocd` namespace
2. Install Argo CD Helm chart
3. Configure Dex for LDAP (if enabled)
4. Create Vault secret for admin password
5. Create ESO ExternalSecret to sync password
6. Deploy Istio VirtualService for ingress
7. Configure RBAC policies

### Step 4: Verify Deployment

Check all pods are running:

```bash
kubectl get pods -n argocd

# Expected output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# argocd-application-controller-0       1/1     Running   0          2m
# argocd-applicationset-controller-..   1/1     Running   0          2m
# argocd-dex-server-...                 1/1     Running   0          2m
# argocd-notifications-controller-...   1/1     Running   0          2m
# argocd-redis-...                      1/1     Running   0          2m
# argocd-repo-server-...                1/1     Running   0          2m
# argocd-server-...                     1/1     Running   0          2m
```

Check Istio VirtualService:

```bash
kubectl get virtualservice -n argocd

# Expected output:
# NAME            GATEWAYS                  HOSTS                      AGE
# argocd-server   ["istio-system/shared"]   ["argocd.dev.local.me"]    2m
```

## Configuration

### Helm Values

Argo CD is configured via Helm values template: `scripts/etc/argocd/values.yaml.tmpl`

**Key configurations:**

```yaml
# Server configuration
server:
  ingress:
    enabled: false  # Using Istio VirtualService instead

# Dex LDAP configuration (when --enable-ldap is used)
dex:
  enabled: true
  env:
    - name: LDAP_BINDDN
      valueFrom:
        secretKeyRef:
          name: argocd-ldap-secret
          key: binddn
    - name: LDAP_BINDPW
      valueFrom:
        secretKeyRef:
          name: argocd-ldap-secret
          key: bindpw

# RBAC configuration
rbac:
  policy.csv: |
    g, admin, role:admin
    g, developers, role:readonly
```

### RBAC Policies

**Default RBAC configuration:**

| LDAP Group   | Argo CD Role | Permissions                          |
|--------------|--------------|--------------------------------------|
| `admin`      | `role:admin` | Full access (create, update, delete) |
| `developers` | `role:readonly` | Read-only access to applications  |

**Customizing RBAC:**

Edit `scripts/etc/argocd/values.yaml.tmpl`:

```yaml
rbac:
  policy.csv: |
    # Map LDAP groups to Argo CD roles
    g, <ldap-group>, <argocd-role>

    # Define custom permissions
    p, role:deployer, applications, *, */*, allow
    p, role:deployer, repositories, *, *, allow
```

### LDAP Configuration Variables

Set in `scripts/etc/ldap/vars.sh`:

```bash
LDAP_DOMAIN="dev.local.me"
LDAP_ADMIN_PASSWORD="<password>"
LDAP_ORGANIZATION="Development"
LDAP_BASE_DN="dc=dev,dc=local,dc=me"
```

## Accessing Argo CD

### Via Web UI

**Prerequisites:**
1. Add hostname to `/etc/hosts`:
   ```bash
   # Get Istio IngressGateway external IP or use localhost for k3d
   echo "127.0.0.1 argocd.dev.local.me" | sudo tee -a /etc/hosts
   ```

2. Access Argo CD UI:
   ```
   https://argocd.dev.local.me/
   ```

**Note for k3s users:** See [Ingress Port Forwarding](architecture/ingress-port-forwarding.md) for port 443 setup.

### Retrieve Admin Password

Get the admin password from Vault:

```bash
# Method 1: Using kubectl
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Method 2: From Vault directly
kubectl exec -n vault vault-0 -- \
  vault kv get -field=password secret/argocd/admin

# Method 3: Using k3d-manager helper (if available)
./bin/get-argocd-password.sh
```

**Default credentials:**
- Username: `admin`
- Password: Retrieved from above command

### Via CLI

**Install Argo CD CLI:**

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o argocd https://github.com/argoproj/argocd-cli/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

**Setup SSL Trust:**

Export and trust Vault CA certificate:

```bash
# Export Vault CA certificate
./bin/setup-argocd-cli-ssl.sh

# Follow the platform-specific instructions displayed
```

**Login to Argo CD:**

```bash
# Get admin password
ARGOCD_PASSWORD=$(kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

# Login
argocd login argocd.dev.local.me \
  --username admin \
  --password "$ARGOCD_PASSWORD"

# Or skip certificate verification (not recommended for production)
argocd login argocd.dev.local.me \
  --username admin \
  --password "$ARGOCD_PASSWORD" \
  --insecure
```

**Verify login:**

```bash
argocd cluster list
argocd app list
```

## LDAP Authentication

### LDAP User Structure

**Default LDAP schema:**

```
dc=dev,dc=local,dc=me
├── ou=users
│   ├── cn=alice
│   ├── cn=bob
│   └── cn=charlie
└── ou=groups
    ├── cn=admin (members: alice)
    └── cn=developers (members: bob, charlie)
```

### Test LDAP Users

**Pre-configured test users:**

| Username | Password | Groups      | Argo CD Access |
|----------|----------|-------------|----------------|
| alice    | alice123 | admin       | Full admin     |
| bob      | bob123   | developers  | Read-only      |
| charlie  | charlie123 | developers | Read-only      |

### Login with LDAP

**Via Web UI:**
1. Navigate to `https://argocd.dev.local.me/`
2. Click "LOG IN VIA DEX"
3. Select "Login with LDAP"
4. Enter LDAP credentials (e.g., username: `alice`, password: `alice123`)

**Via CLI:**

```bash
# Login with LDAP user
argocd login argocd.dev.local.me --sso

# Or use username/password directly
argocd login argocd.dev.local.me \
  --username alice \
  --password alice123 \
  --sso-port 8085
```

### Troubleshooting LDAP Authentication

**Check Dex logs:**

```bash
kubectl logs -n argocd deployment/argocd-dex-server
```

**Common issues:**

1. **"Invalid credentials"**
   - Verify LDAP user exists: `kubectl exec -n directory openldap-0 -- ldapsearch -x -b "dc=dev,dc=local,dc=me" "(cn=alice)"`
   - Check LDAP bind password in secret: `kubectl get secret -n argocd argocd-ldap-secret -o yaml`

2. **"LDAP server unreachable"**
   - Verify OpenLDAP is running: `kubectl get pods -n directory`
   - Check LDAP service: `kubectl get svc -n directory openldap`

3. **"User authenticated but no permissions"**
   - Check RBAC configuration: `kubectl get cm -n argocd argocd-rbac-cm -o yaml`
   - Verify group membership in LDAP

**Test LDAP connectivity from Dex:**

```bash
kubectl exec -n argocd deployment/argocd-dex-server -- \
  ldapsearch -x -H ldap://openldap.directory.svc.cluster.local:389 \
  -b "dc=dev,dc=local,dc=me" -D "cn=admin,dc=dev,dc=local,dc=me" \
  -w "admin" "(cn=alice)"
```

## Vault Integration

### Admin Password Storage

The Argo CD admin password is stored in Vault and synced to Kubernetes via ESO.

**Vault path:** `secret/argocd/admin`

**View password in Vault:**

```bash
kubectl exec -n vault vault-0 -- \
  vault kv get secret/argocd/admin

# Output:
# ====== Data ======
# Key         Value
# ---         -----
# password    <generated-password>
# username    admin
```

### Update Admin Password

**Option 1: Via Vault CLI**

```bash
kubectl exec -n vault vault-0 -- \
  vault kv put secret/argocd/admin \
  username=admin \
  password=<new-password>

# ESO will sync the new password automatically within ~1 minute
```

**Option 2: Via Argo CD CLI**

```bash
argocd account update-password
```

**Option 3: Via Web UI**

1. Login as admin
2. User Info → Update Password
3. ESO will sync changes back to Vault (if bidirectional sync is configured)

### ExternalSecret Configuration

Located in deployment: `scripts/plugins/argocd.sh`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-admin-password
  namespace: argocd
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: argocd-initial-admin-secret
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: secret/argocd/admin
        property: password
```

**Verify ESO sync:**

```bash
# Check ExternalSecret status
kubectl get externalsecret -n argocd

# Check synced secret
kubectl get secret -n argocd argocd-initial-admin-secret -o yaml
```

## Troubleshooting

### Common Issues

#### 1. Pods not starting

**Symptoms:**
```bash
kubectl get pods -n argocd
# NAME                                  READY   STATUS             RESTARTS   AGE
# argocd-server-...                     0/1     CrashLoopBackOff   5          5m
```

**Solutions:**

```bash
# Check pod logs
kubectl logs -n argocd deployment/argocd-server

# Common causes:
# - Missing ConfigMap: Check argocd-cm exists
# - RBAC issues: Check ServiceAccount permissions
# - Resource limits: Check cluster has enough resources
```

#### 2. Cannot access UI (404 or timeout)

**Check Istio VirtualService:**

```bash
kubectl get virtualservice -n argocd argocd-server -o yaml

# Verify:
# - hosts: ["argocd.dev.local.me"]
# - gateway: istio-system/shared
# - destination service matches argocd-server
```

**Check Istio Gateway:**

```bash
kubectl get gateway -n istio-system shared -o yaml

# Verify port 443 is configured
```

**Check /etc/hosts:**

```bash
cat /etc/hosts | grep argocd
# Should show: 127.0.0.1 argocd.dev.local.me (for k3d)
# Or: <node-ip> argocd.dev.local.me (for k3s)
```

#### 3. LDAP authentication not working

**Check Dex configuration:**

```bash
kubectl get cm -n argocd argocd-cm -o yaml | grep -A 20 "dex.config"

# Verify LDAP connector configuration
```

**Test LDAP connectivity:**

```bash
# From Dex pod
kubectl exec -n argocd deployment/argocd-dex-server -- \
  nc -zv openldap.directory.svc.cluster.local 389

# Should show: succeeded!
```

**Check LDAP secret:**

```bash
kubectl get secret -n argocd argocd-ldap-secret -o yaml

# Verify binddn and bindpw are present
```

#### 4. Vault integration not working

**Check ESO SecretStore:**

```bash
kubectl get secretstore -n argocd

# Should show: vault-backend   Valid   <age>
```

**Check ExternalSecret:**

```bash
kubectl describe externalsecret -n argocd argocd-admin-password

# Look for sync status and any errors
```

**Verify Vault access:**

```bash
# Check Vault is unsealed
kubectl exec -n vault vault-0 -- vault status

# Test secret read
kubectl exec -n vault vault-0 -- \
  vault kv get secret/argocd/admin
```

### Logs and Debugging

**View Argo CD server logs:**

```bash
kubectl logs -n argocd deployment/argocd-server -f
```

**View Dex logs:**

```bash
kubectl logs -n argocd deployment/argocd-dex-server -f
```

**View application controller logs:**

```bash
kubectl logs -n argocd statefulset/argocd-application-controller -f
```

**Enable debug logging:**

```bash
kubectl patch cm -n argocd argocd-cm --type merge -p '
{
  "data": {
    "server.log.level": "debug"
  }
}'

# Restart server to apply
kubectl rollout restart -n argocd deployment/argocd-server
```

### Health Checks

**Check all components:**

```bash
# Pods
kubectl get pods -n argocd

# Services
kubectl get svc -n argocd

# VirtualService
kubectl get virtualservice -n argocd

# ExternalSecrets
kubectl get externalsecret -n argocd

# ConfigMaps
kubectl get cm -n argocd
```

**Verify Argo CD API:**

```bash
curl -k https://argocd.dev.local.me/api/version

# Expected output:
# {"Version":"v2.x.x","BuildDate":"...","GitCommit":"..."}
```

## Next Steps

### Post-Deployment Tasks

1. **Change Admin Password**
   ```bash
   argocd account update-password
   ```

2. **Configure Repositories**
   ```bash
   argocd repo add https://github.com/your-org/your-repo.git \
     --username <username> \
     --password <password>
   ```

3. **Deploy First Application**
   ```bash
   argocd app create guestbook \
     --repo https://github.com/argoproj/argocd-example-apps.git \
     --path guestbook \
     --dest-server https://kubernetes.default.svc \
     --dest-namespace default

   argocd app sync guestbook
   ```

4. **Setup App of Apps Pattern**
   - Create a Git repository for application definitions
   - Deploy a root application that manages other applications
   - See [Argo CD Best Practices](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/)

### Recommended Next Steps

1. **Argo Rollouts** (Phase 2)
   - Install Argo Rollouts for progressive delivery
   - Implement blue/green and canary deployments
   - See `docs/plans/argocd-implementation-plan.md`

2. **ApplicationSets** (Phase 3)
   - Deploy ApplicationSet controller for multi-cluster management
   - Bootstrap core services from Git
   - Implement GitOps for infrastructure

3. **Production Hardening**
   - Configure TLS for all components
   - Implement network policies
   - Enable audit logging
   - Configure backup/restore procedures

4. **Monitoring & Alerts**
   - Integrate with Prometheus/Grafana
   - Configure notifications (Slack, email)
   - Set up health checks and SLOs

### Additional Resources

- **Argo CD Documentation**: https://argo-cd.readthedocs.io/
- **Argo CD Best Practices**: https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/
- **k3d-manager ArgoCD Plugin**: `scripts/plugins/argocd.sh`
- **ArgoCD Implementation Plan**: `docs/plans/argocd-implementation-plan.md`
- **Test Suite**: `scripts/tests/plugins/argocd.bats`
- **Ingress Port Forwarding**: `docs/architecture/ingress-port-forwarding.md`

### Support and Troubleshooting

For issues specific to this k3d-manager deployment:

1. Check test suite for expected behavior: `./scripts/k3d-manager test argocd`
2. Review plugin source code: `scripts/plugins/argocd.sh`
3. Check Helm values template: `scripts/etc/argocd/values.yaml.tmpl`
4. Review recent commits and changes in `CLAUDE.md`

For general Argo CD issues:
- GitHub Issues: https://github.com/argoproj/argo-cd/issues
- Slack Channel: https://argoproj.github.io/community/join-slack
