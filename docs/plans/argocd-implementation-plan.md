# Argo CD Implementation Plan for k3d-manager

**Created:** 2025-11-27
**Status:** Planning
**Priority:** Future Enhancement
**Dependencies:** Vault, ESO, Istio (all deployed)

## Overview

This plan outlines the implementation of Argo CD as a GitOps orchestration layer for k3d-manager, following patterns from enterprise Argo CD ApplicationSets architecture. The implementation will leverage existing infrastructure (Vault, ESO, Istio, LDAP) and follow established k3d-manager plugin patterns.

## Goals

1. **GitOps Automation** - Manage k3d-manager services declaratively via Git
2. **Progressive Delivery** - Add Argo Rollouts for canary/blue-green deployments
3. **Multi-Cluster Ready** - Design for future multi-cluster expansion
4. **Existing Integration** - Leverage Vault, ESO, Istio, and LDAP/AD authentication
5. **Developer Experience** - Maintain bash deployment scripts alongside GitOps workflow

## Reference Architecture

Based on `argo-implement.md`, the enterprise pattern includes:

**Core Components:**
- Argo CD Server (GitOps controller)
- Argo Rollouts (progressive delivery)
- ApplicationSets (multi-cluster orchestration)
- AppProjects (RBAC and resource scoping)

**Key Patterns:**
- Cluster labels for targeting (e.g., `cluster_name`, `env=dev`)
- ApplicationSets generate Applications per cluster/environment
- Helm charts stored in external repos, manifests in ApplicationSet repo
- External Secrets for credential management (already implemented!)

## Current k3d-manager Architecture

**Existing Services:**
- **Vault** - PKI, secrets management
- **External Secrets Operator** - Vault→K8s secret syncing
- **Istio** - Service mesh with ingress gateway
- **Jenkins** - CI/CD with LDAP/AD authentication, Job DSL automation
- **OpenLDAP** - Directory service (standard + AD-compatible schemas)

**Deployment Pattern:**
```bash
./scripts/k3d-manager deploy_<service> [--flags]
```

**Plugin Architecture:**
```
scripts/
├── k3d-manager           # Main dispatcher
├── lib/                  # Core libraries
├── plugins/              # Service deployment plugins
│   ├── vault.sh
│   ├── jenkins.sh
│   ├── ldap.sh
│   └── eso.sh
└── etc/                  # Configuration templates
    ├── vault/
    ├── jenkins/
    └── ldap/
```

---

## Implementation Phases

### Phase 1: Core Argo CD Deployment (Foundation)

**Goal:** Deploy Argo CD server with Istio ingress, Vault integration, and LDAP authentication.

**Effort:** ~4-6 hours
**Branch:** `feature/argocd-phase1`

#### Tasks

1. **Create Argo CD Plugin** (`scripts/plugins/argocd.sh`)
   - Follow existing plugin patterns (vault.sh, jenkins.sh)
   - Implement `deploy_argocd()` function
   - Support `--enable-ldap` and `--enable-ad` flags (reuse auth providers)
   - Add smoke test function

2. **Configuration Templates** (`scripts/etc/argocd/`)
   ```
   argocd/
   ├── vars.sh                      # Environment variables
   ├── values.yaml.tmpl             # Helm values template
   ├── argocd-cm.yaml.tmpl          # ConfigMap for OIDC/LDAP
   ├── argocd-rbac-cm.yaml.tmpl    # RBAC policy
   └── gateway.yaml.tmpl            # Istio VirtualService/Gateway
   ```

3. **Helm Deployment**
   - Chart: `argo/argo-cd` (official Helm chart)
   - Namespace: `argocd`
   - Version: Latest stable (v2.x)
   - HA mode: Single replica (for dev/test)

4. **Integrations**
   - **Vault:** Store admin password in `secret/argocd/admin`
   - **ESO:** Create ExternalSecret to sync admin credentials
   - **Istio:** Deploy VirtualService for `argocd.dev.local.me`
   - **LDAP:** Configure dex connector to existing OpenLDAP
   - **TLS:** Reuse Vault PKI for certificate issuance

5. **Authentication Configuration**
   - LDAP via Dex connector (similar to Jenkins LDAP setup)
   - AD support for production environments
   - Admin group: `argocd-admins` (maps to LDAP group)

6. **Testing**
   - Unit tests: `scripts/tests/plugins/argocd.bats`
   - Smoke test: Verify Argo CD UI accessible
   - LDAP login test
   - CLI login test

#### Deliverables

- [ ] `scripts/plugins/argocd.sh` - Deployment plugin
- [ ] `scripts/etc/argocd/` - Configuration templates
- [ ] `scripts/tests/plugins/argocd.bats` - Unit tests
- [ ] Documentation: `docs/argocd-setup.md`
- [ ] Command: `./scripts/k3d-manager deploy_argocd --enable-ldap --enable-vault`

#### Success Criteria

- Argo CD UI accessible at `https://argocd.dev.local.me`
- LDAP authentication working (reuse existing OpenLDAP users)
- Admin password stored in Vault, synced via ESO
- Istio ingress configured with Vault-issued TLS certificate
- CLI tool (`argocd`) can authenticate

---

### Phase 2: Argo Rollouts Installation

**Goal:** Deploy Argo Rollouts controller for progressive delivery capabilities.

**Effort:** ~2-3 hours
**Dependencies:** Phase 1 complete

#### Tasks

1. **Extend Argo CD Plugin**
   - Add `--enable-rollouts` flag to `deploy_argocd()`
   - Deploy Argo Rollouts via Helm subchart or separate Application

2. **Rollouts Configuration**
   - Namespace: `argocd` (co-located with Argo CD)
   - Chart: `argo/argo-rollouts`
   - Dashboard: Optional Rollouts UI

3. **Testing**
   - Deploy sample Rollout with canary strategy
   - Validate progressive delivery workflow

#### Deliverables

- [ ] Argo Rollouts deployment integrated into plugin
- [ ] Example Rollout manifest for testing
- [ ] Documentation update

---

### Phase 3: ApplicationSet Bootstrap (GitOps Foundation)

**Goal:** Create ApplicationSet structure to manage existing k3d-manager services.

**Effort:** ~6-8 hours
**Dependencies:** Phase 1 complete

#### Tasks

1. **Repository Structure Decision**
   - **Option A:** Single repo (k3d-manager for both scripts and GitOps)
   - **Option B:** Separate GitOps repo (k3d-manager-apps)
   - **Recommendation:** Start with Option A, migrate to B if needed

2. **Create ApplicationSet Manifests** (`scripts/etc/argocd/applicationsets/`)
   ```
   applicationsets/
   ├── platform-services.yaml   # Vault, ESO, Istio
   ├── jenkins.yaml              # Jenkins with LDAP/AD variants
   └── directory-services.yaml   # OpenLDAP/AD
   ```

3. **AppProject Definition** (`scripts/etc/argocd/projects/`)
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: AppProject
   metadata:
     name: platform
     namespace: argocd
   spec:
     description: Platform services managed by k3d-manager
     destinations:
       - namespace: 'vault'
         server: 'https://kubernetes.default.svc'
       - namespace: 'jenkins'
         server: 'https://kubernetes.default.svc'
       - namespace: 'directory'
         server: 'https://kubernetes.default.svc'
       - namespace: 'istio-system'
         server: 'https://kubernetes.default.svc'
     sourceRepos:
       - '*'  # Allow all repos (restrict in production)
     clusterResourceWhitelist:
       - group: '*'
         kind: '*'
   ```

4. **Helm Chart References**
   - Store Helm values in Git (not just templates)
   - Reference existing charts:
     - Vault: `hashicorp/vault`
     - Jenkins: `jenkins/jenkins`
     - ESO: `external-secrets/external-secrets`

5. **Cluster Labels** (future multi-cluster support)
   ```yaml
   # Example cluster secret with labels
   metadata:
     labels:
       environment: dev
       provider: k3d
       cluster_name: local
   ```

#### Deliverables

- [ ] ApplicationSet manifests for existing services
- [ ] AppProject definition
- [ ] Git repository structure for Helm values
- [ ] Documentation: ApplicationSet usage guide

---

### Phase 4: Service Migration to GitOps

**Goal:** Migrate one service (Vault) from bash deployment to Argo CD management.

**Effort:** ~4-6 hours
**Dependencies:** Phase 3 complete

#### Tasks

1. **Choose Pilot Service: Vault**
   - Simplest service (no stateful dependencies on others)
   - Already has well-defined Helm values
   - Good candidate for GitOps

2. **Create Application Manifest**
   ```yaml
   # scripts/etc/argocd/applications/vault.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: vault
     namespace: argocd
   spec:
     project: platform
     source:
       repoURL: https://helm.releases.hashicorp.com
       chart: vault
       targetRevision: 0.27.0
       helm:
         valuesFiles:
           - values-dev.yaml  # Stored in Git
     destination:
       server: https://kubernetes.default.svc
       namespace: vault
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
   ```

3. **Extract Helm Values to Git**
   - Convert `scripts/etc/vault/values.yaml.tmpl` to static values
   - Store in Git repository
   - Remove envsubst variables (use Argo CD templating instead)

4. **Deployment Workflow**
   - **Manual (Existing):** `./scripts/k3d-manager deploy_vault`
   - **GitOps (New):** Git commit → Argo CD auto-sync
   - **Hybrid:** Keep bash script for initial bootstrap, Argo CD for ongoing management

5. **Testing**
   - Deploy Vault via Argo CD Application
   - Verify auto-sync, self-heal, and prune behavior
   - Test secret access (ensure ESO still works)

#### Deliverables

- [ ] Vault Application manifest
- [ ] Vault Helm values in Git
- [ ] Migration guide: bash → GitOps
- [ ] Updated deployment script with GitOps option

---

### Phase 5: Multi-Service ApplicationSets

**Goal:** Use ApplicationSets to manage all platform services with cluster labels.

**Effort:** ~8-10 hours
**Dependencies:** Phase 4 complete

#### Tasks

1. **ApplicationSet for Platform Services**
   ```yaml
   # scripts/etc/argocd/applicationsets/platform-services.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: ApplicationSet
   metadata:
     name: platform-services
     namespace: argocd
   spec:
     generators:
       - matrix:
           generators:
             - list:
                 elements:
                   - service: vault
                     namespace: vault
                     chart: vault
                     repoURL: https://helm.releases.hashicorp.com
                   - service: external-secrets
                     namespace: external-secrets
                     chart: external-secrets
                     repoURL: https://charts.external-secrets.io
                   - service: jenkins
                     namespace: jenkins
                     chart: jenkins
                     repoURL: https://charts.jenkins.io
             - clusters:
                 selector:
                   matchLabels:
                     environment: dev
     template:
       metadata:
         name: '{{service}}-{{cluster.name}}'
       spec:
         project: platform
         source:
           repoURL: '{{repoURL}}'
           chart: '{{chart}}'
           targetRevision: HEAD
           helm:
             valuesFiles:
               - '{{cluster.name}}/{{service}}/values.yaml'
         destination:
           server: '{{cluster.server}}'
           namespace: '{{namespace}}'
         syncPolicy:
           automated:
             prune: true
             selfHeal: true
   ```

2. **Directory Service ApplicationSet** (LDAP/AD variants)
   - Use generators to create different Applications for:
     - Standard LDAP (`--enable-ldap`)
     - AD testing (`--enable-ad`)
     - Production AD (`--enable-ad-prod`)

3. **Jenkins ApplicationSet** (with directory service integration)
   - Matrix generator: Jenkins × Directory Service
   - Conditional values based on auth provider

#### Deliverables

- [ ] Platform services ApplicationSet
- [ ] Directory services ApplicationSet
- [ ] Jenkins ApplicationSet with auth variants
- [ ] Cluster label documentation

---

### Phase 6: Advanced Features

**Goal:** Add monitoring, notifications, and progressive delivery workflows.

**Effort:** ~6-8 hours
**Dependencies:** Phase 5 complete

#### Tasks

1. **Notifications Configuration**
   - Slack/Email notifications for sync failures
   - Integration with existing monitoring (if any)

2. **Progressive Delivery with Argo Rollouts**
   - Create sample canary deployment for Jenkins
   - Define analysis templates (success rate, latency)
   - Automated rollback on failure

3. **App of Apps Pattern**
   - Root Application that manages all ApplicationSets
   - Bootstrap from single manifest

4. **Backup and Disaster Recovery**
   - Export Argo CD configuration
   - Document restore procedure

#### Deliverables

- [ ] Notifications configuration
- [ ] Sample Rollout with analysis
- [ ] App of Apps manifest
- [ ] Backup/restore documentation

---

## Repository Structure (Proposed)

### Option A: Single Repository (Recommended for Start)

```
k3d-manager/
├── scripts/
│   ├── k3d-manager
│   ├── plugins/
│   │   └── argocd.sh          # New plugin
│   └── etc/
│       └── argocd/
│           ├── vars.sh
│           ├── values.yaml.tmpl
│           ├── applicationsets/
│           ├── applications/
│           └── projects/
├── gitops/                      # New directory for GitOps manifests
│   ├── clusters/
│   │   └── local/              # k3d/k3s cluster
│   │       ├── vault/
│   │       │   └── values.yaml
│   │       ├── jenkins/
│   │       │   └── values.yaml
│   │       └── eso/
│   │           └── values.yaml
│   └── bootstrap/
│       └── root-app.yaml       # App of Apps
└── docs/
    └── argocd-setup.md
```

### Option B: Separate GitOps Repository (Future)

```
k3d-manager-apps/
├── clusters/
│   ├── dev/
│   ├── staging/
│   └── prod/
├── applicationsets/
├── projects/
└── bootstrap/
```

---

## Integration with Existing Components

### Vault Integration

**Secrets to Store:**
- Argo CD admin password: `secret/argocd/admin`
- Git repository credentials (if private repos): `secret/argocd/repo-creds`
- Notification tokens: `secret/argocd/notifications`

**ESO Configuration:**
```yaml
# ExternalSecret for Argo CD admin password
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-secret
  namespace: argocd
spec:
  secretStoreRef:
    name: vault-kv-store
    kind: SecretStore
  target:
    name: argocd-secret
  data:
    - secretKey: admin.password
      remoteRef:
        key: secret/argocd/admin
        property: password
```

### LDAP/AD Authentication

**Dex Configuration for LDAP:**
```yaml
# scripts/etc/argocd/argocd-cm.yaml.tmpl
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  dex.config: |
    connectors:
      - type: ldap
        id: ldap
        name: OpenLDAP
        config:
          host: openldap-openldap-bitnami.directory.svc.cluster.local:389
          insecureNoSSL: true
          bindDN: ${LDAP_BIND_DN}
          bindPW: ${LDAP_BIND_PASSWORD}
          userSearch:
            baseDN: ou=users,dc=home,dc=org
            filter: "(cn=%s)"
            username: cn
            idAttr: cn
            emailAttr: mail
            nameAttr: cn
          groupSearch:
            baseDN: ou=groups,dc=home,dc=org
            filter: "(member=%s)"
            nameAttr: cn
```

**RBAC Policy:**
```yaml
# scripts/etc/argocd/argocd-rbac-cm.yaml.tmpl
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    g, argocd-admins, role:admin
    g, jenkins-admins, role:admin
```

### Istio Ingress

**VirtualService:**
```yaml
# scripts/etc/argocd/gateway.yaml.tmpl
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: argocd-gateway
  namespace: argocd
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: argocd-tls  # Vault PKI-issued cert
      hosts:
        - argocd.dev.local.me
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: argocd
  namespace: argocd
spec:
  hosts:
    - argocd.dev.local.me
  gateways:
    - argocd-gateway
  http:
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: argocd-server
            port:
              number: 80
```

---

## Deployment Commands

### Phase 1: Deploy Argo CD
```bash
# Deploy Argo CD with LDAP authentication
./scripts/k3d-manager deploy_argocd --enable-ldap --enable-vault

# Deploy with AD authentication (production)
export AD_DOMAIN="corp.example.com"
./scripts/k3d-manager deploy_argocd --enable-ad-prod --enable-vault

# Deploy with Argo Rollouts
./scripts/k3d-manager deploy_argocd --enable-ldap --enable-vault --enable-rollouts
```

### Phase 3: Bootstrap ApplicationSets
```bash
# Apply ApplicationSets manually
kubectl apply -f scripts/etc/argocd/applicationsets/

# Or via Argo CD CLI
argocd app create platform-services \
  --repo https://github.com/your-org/k3d-manager \
  --path scripts/etc/argocd/applicationsets \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace argocd
```

### Phase 6: App of Apps
```bash
# Bootstrap everything from single Application
kubectl apply -f gitops/bootstrap/root-app.yaml
```

---

## Testing Strategy

### Unit Tests (`scripts/tests/plugins/argocd.bats`)

```bash
@test "deploy_argocd creates argocd namespace" {
  run deploy_argocd
  kubectl get namespace argocd
}

@test "deploy_argocd deploys argocd-server" {
  run deploy_argocd
  kubectl get deployment argocd-server -n argocd
}

@test "deploy_argocd configures LDAP via dex" {
  run deploy_argocd --enable-ldap
  kubectl get configmap argocd-cm -n argocd -o yaml | grep "type: ldap"
}
```

### Integration Tests

1. **Argo CD UI Access** - Verify HTTPS ingress works
2. **LDAP Login** - Authenticate with existing OpenLDAP users
3. **Application Sync** - Deploy sample app via Application manifest
4. **Auto-Sync** - Verify Git changes trigger automatic deployment
5. **Rollback** - Test rollback to previous revision

### End-to-End Workflow

```bash
# 1. Deploy cluster
./scripts/k3d-manager deploy_cluster

# 2. Deploy prerequisites
./scripts/k3d-manager deploy_vault
./scripts/k3d-manager deploy_eso
./scripts/k3d-manager deploy_ldap

# 3. Deploy Argo CD
./scripts/k3d-manager deploy_argocd --enable-ldap --enable-vault

# 4. Access UI
open https://argocd.dev.local.me

# 5. Login with LDAP user (e.g., alice)

# 6. Deploy sample application via UI or CLI
```

---

## Migration Strategy: Bash Scripts → GitOps

### Hybrid Approach (Recommended)

**Keep bash scripts for:**
- Initial cluster bootstrap
- Local development/testing
- Emergency manual interventions
- Services not yet in GitOps

**Use Argo CD for:**
- Production deployments
- Configuration drift detection
- Automated rollbacks
- Multi-environment promotions

### Coexistence Pattern

```bash
# scripts/plugins/argocd.sh
function deploy_vault() {
  local use_gitops="${ARGOCD_MANAGED:-0}"

  if [[ "$use_gitops" == "1" ]]; then
    _info "[vault] deploying via Argo CD Application"
    _deploy_vault_via_argocd
  else
    _info "[vault] deploying via Helm (traditional method)"
    _deploy_vault_via_helm
  fi
}
```

---

## Rollback Plan

If Argo CD deployment fails or causes issues:

1. **Remove Argo CD:**
   ```bash
   kubectl delete namespace argocd
   kubectl delete crd applications.argoproj.io
   kubectl delete crd applicationsets.argoproj.io
   kubectl delete crd appprojects.argoproj.io
   ```

2. **Revert to bash deployments:**
   ```bash
   ./scripts/k3d-manager deploy_vault
   ./scripts/k3d-manager deploy_jenkins --enable-ldap
   ```

3. **No data loss:**
   - All service data persists (Vault storage, Jenkins home, etc.)
   - Only GitOps orchestration layer is removed

---

## Success Metrics

### Phase 1 Success
- [ ] Argo CD UI accessible via Istio ingress
- [ ] LDAP authentication working
- [ ] Admin password synced from Vault via ESO
- [ ] Argo CD CLI functional

### Phase 3 Success
- [ ] At least one ApplicationSet deployed
- [ ] ApplicationSet generates Applications successfully
- [ ] Applications sync without errors

### Phase 4 Success
- [ ] Vault deployed and managed by Argo CD Application
- [ ] Git commit triggers automatic sync
- [ ] Self-heal recovers from manual kubectl changes
- [ ] ESO still functions correctly

### Overall Success
- [ ] All k3d-manager services manageable via GitOps
- [ ] Deployment time reduced by 50% (after initial setup)
- [ ] Configuration drift detection enabled
- [ ] Documentation complete for all workflows

---

## Open Questions

1. **Repository Strategy:**
   - Start with single repo or create separate GitOps repo immediately?
   - **Decision:** Start with single repo, evaluate after Phase 3

2. **Service Migration Priority:**
   - Which services migrate first? Vault → ESO → Jenkins → LDAP?
   - **Decision:** Vault (Phase 4), then ESO, Jenkins last (most complex)

3. **Cluster Labels:**
   - Design for single cluster or multi-cluster from day one?
   - **Decision:** Single cluster labels (`environment: dev`), expand labels in Phase 5

4. **Bash Script Deprecation:**
   - Keep bash scripts indefinitely or sunset after GitOps proven?
   - **Decision:** Keep bash scripts for bootstrap and emergency use

5. **Argo Rollouts Adoption:**
   - Which services benefit from progressive delivery?
   - **Decision:** Jenkins (non-critical), then evaluate for Vault (requires care)

---

## Timeline Estimates

| Phase | Tasks | Effort | Dependencies |
|-------|-------|--------|--------------|
| Phase 1 | Core Argo CD deployment | 4-6 hours | Vault, ESO, Istio |
| Phase 2 | Argo Rollouts | 2-3 hours | Phase 1 |
| Phase 3 | ApplicationSets | 6-8 hours | Phase 1 |
| Phase 4 | Vault migration | 4-6 hours | Phase 3 |
| Phase 5 | Multi-service ApplicationSets | 8-10 hours | Phase 4 |
| Phase 6 | Advanced features | 6-8 hours | Phase 5 |
| **Total** | | **30-41 hours** | |

**Realistic Delivery:**
- Working in 2-hour sessions: ~15-20 sessions
- Calendar time: 3-4 weeks (part-time work)
- MVP (Phases 1-3): 1-2 weeks

---

## References

- `argo-implement.md` - Enterprise ApplicationSets architecture reference
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Argo Rollouts Documentation](https://argo-rollouts.readthedocs.io/)
- [ApplicationSet Spec](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- k3d-manager existing patterns: `scripts/plugins/{vault,jenkins,ldap}.sh`

---

## Next Steps

**To begin Phase 1:**

1. Create feature branch: `git checkout -b feature/argocd-phase1`
2. Create plugin scaffold: `scripts/plugins/argocd.sh`
3. Add Argo CD Helm repo: `helm repo add argo https://argoproj.github.io/argo-helm`
4. Create configuration directory: `scripts/etc/argocd/`
5. Implement basic deployment function
6. Test deployment: `./scripts/k3d-manager deploy_argocd`

**Decision Required:**
- Confirm Phase 1 approach and priority
- Review and approve repository structure
- Set timeline for completion
