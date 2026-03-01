# Codex Task: ArgoCD Phase 1 Fixes

**Branch:** `feature/argocd-phase1`
**Created:** 2026-03-01
**Author:** Claude (reviewed before Codex hand-off)

---

## Context

`scripts/plugins/argocd.sh` and `scripts/etc/argocd/vars.sh` are complete and correct for v0.3.0.
All templates exist. The issues are in static manifests (projects + applicationsets) which were
live-exported from the old cluster and contain:
1. Stale Kubernetes server metadata (`resourceVersion`, `uid`, `creationTimestamp`, etc.)
2. Old v0.2.x namespace names (`vault`, `jenkins`, `directory`, `argocd`, `external-secrets-system`)
3. Placeholder GitHub org (`your-org` instead of `wilddog64`)

Additionally, `argocd.sh` needs:
- `_argocd_deploy_appproject` to apply the manifest into the correct namespace (`$ARGOCD_NAMESPACE`,
  default `cicd`), not the hardcoded `argocd` in the static YAML
- A `_argocd_seed_vault_admin_secret` helper to write the initial `secret/argocd/admin` password
  into Vault so the ESO ExternalSecret can sync it

---

## Change 1 — `scripts/etc/argocd/projects/platform.yaml`

Rewrite as a clean declarative manifest (no server metadata). Fix:
- `namespace: argocd` → `namespace: ${ARGOCD_NAMESPACE}` (rename file to `platform.yaml.tmpl`)
- Fix all destination namespace values to v0.3.0 names

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    managed-by: k3d-manager
    project-type: platform
spec:
  description: Platform services managed by k3d-manager
  sourceRepos:
    - '*'
  destinations:
    - namespace: secrets
      server: https://kubernetes.default.svc
    - namespace: cicd
      server: https://kubernetes.default.svc
    - namespace: identity
      server: https://kubernetes.default.svc
    - namespace: istio-system
      server: https://kubernetes.default.svc
    - namespace: default
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: ''
      kind: PersistentVolume
    - group: rbac.authorization.k8s.io
      kind: ClusterRole
    - group: rbac.authorization.k8s.io
      kind: ClusterRoleBinding
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
    - group: networking.istio.io
      kind: Gateway
    - group: argoproj.io
      kind: Rollout
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
  orphanedResources:
    warn: true
  roles:
    - name: admin
      description: Full admin access to platform project
      groups:
        - platform-admins
      policies:
        - p, proj:platform:admin, applications, *, platform/*, allow
    - name: developer
      description: Developer access - sync and refresh only
      groups:
        - platform-developers
      policies:
        - p, proj:platform:developer, applications, get, platform/*, allow
        - p, proj:platform:developer, applications, sync, platform/*, allow
```

**File action:** Delete `projects/platform.yaml`, create `projects/platform.yaml.tmpl` with the above content.

---

## Change 2 — `scripts/plugins/argocd.sh` — `_argocd_deploy_appproject`

Update the function to use `envsubst` since the file is now a template:

```bash
# Before:
function _argocd_deploy_appproject() {
   _info "[argocd] Deploying platform AppProject"

   local appproject_file="$ARGOCD_CONFIG_DIR/projects/platform.yaml"

   if [[ ! -f "$appproject_file" ]]; then
      _err "[argocd] AppProject file not found: $appproject_file"
      return 1
   fi

   _kubectl apply -f "$appproject_file" >/dev/null

   _info "[argocd] AppProject deployed: platform"
   return 0
}

# After:
function _argocd_deploy_appproject() {
   _info "[argocd] Deploying platform AppProject"

   local appproject_tmpl="$ARGOCD_CONFIG_DIR/projects/platform.yaml.tmpl"

   if [[ ! -f "$appproject_tmpl" ]]; then
      _err "[argocd] AppProject template not found: $appproject_tmpl"
      return 1
   fi

   envsubst '$ARGOCD_NAMESPACE' < "$appproject_tmpl" | _kubectl apply -f - >/dev/null

   _info "[argocd] AppProject deployed: platform"
   return 0
}
```

---

## Change 3 — `scripts/etc/argocd/applicationsets/platform-helm.yaml`

Rewrite as a clean declarative manifest. Fix `namespace: argocd` → `cicd`.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-helm
  namespace: cicd
  labels:
    managed-by: k3d-manager
    app-type: platform
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: dev
        values:
          revision: HEAD
  goTemplate: true
  goTemplateOptions:
    - missingkey=error
  template:
    metadata:
      name: '{{.name}}-platform'
      labels:
        cluster: '{{.name}}'
        environment: '{{.metadata.labels.environment}}'
    spec:
      project: platform
      source:
        repoURL: https://argoproj.github.io/argo-helm
        chart: argo-cd
        targetRevision: '{{.values.revision}}'
        helm:
          releaseName: 'argocd-{{.name}}'
          parameters:
            - name: server.replicas
              value: "2"
            - name: repoServer.replicas
              value: "2"
      destination:
        server: '{{.server}}'
        namespace: cicd
      syncPolicy:
        automated:
          prune: false
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
      ignoreDifferences:
        - group: apps
          kind: Deployment
          jsonPointers:
            - /spec/replicas
```

---

## Change 4 — `scripts/etc/argocd/applicationsets/services-git.yaml`

Rewrite as a clean declarative manifest. Fix `your-org` → `wilddog64` and `namespace: argocd` → `cicd`.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: services-git
  namespace: cicd
  labels:
    managed-by: k3d-manager
    app-type: services
spec:
  generators:
    - git:
        repoURL: https://github.com/wilddog64/k3d-manager
        revision: HEAD
        directories:
          - path: services/*
  goTemplate: true
  goTemplateOptions:
    - missingkey=error
  template:
    metadata:
      name: '{{.path.basename}}'
      labels:
        app-type: service
        discovered-from: git
    spec:
      project: platform
      source:
        repoURL: https://github.com/wilddog64/k3d-manager
        targetRevision: HEAD
        path: '{{.path.path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

---

## Change 5 — `scripts/etc/argocd/applicationsets/demo-rollout.yaml`

Rewrite as a clean declarative manifest. Fix `your-org` → `wilddog64` and `namespace: argocd` → `cicd`.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: demo-rollout
  namespace: cicd
  labels:
    managed-by: k3d-manager
    app-type: demo
spec:
  generators:
    - list:
        elements:
          - environment: dev
            namespace: default
          - environment: staging
            namespace: staging
  goTemplate: true
  goTemplateOptions:
    - missingkey=error
  template:
    metadata:
      name: 'rollout-demo-{{.namespace}}'
      labels:
        environment: '{{.environment}}'
    spec:
      project: platform
      source:
        repoURL: https://github.com/wilddog64/k3d-manager
        targetRevision: HEAD
        path: scripts/etc/argocd
        directory:
          include: sample-rollout.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

---

## Change 6 — Add `_argocd_seed_vault_admin_secret` to `scripts/plugins/argocd.sh`

ArgoCD needs a password stored at `secret/argocd/admin` in Vault before the ESO ExternalSecret can
sync it. Add a helper that writes a random password if the path does not exist, and call it from
`deploy_argocd` when `enable_vault=1`.

Add before `_argocd_setup_vault_policies`:

```bash
function _argocd_seed_vault_admin_secret() {
   local ns="${VAULT_NS_DEFAULT:-secrets}"
   local release="${VAULT_RELEASE_DEFAULT:-vault}"

   # Check if secret already exists
   if _vault_exec_stream --no-exit --pod "${release}-0" "$ns" "$release" -- \
         vault kv get -format=json "${ARGOCD_VAULT_KV_MOUNT}/${ARGOCD_ADMIN_VAULT_PATH}" \
         > /dev/null 2>&1; then
      _info "[argocd] Vault admin secret already exists at ${ARGOCD_VAULT_KV_MOUNT}/${ARGOCD_ADMIN_VAULT_PATH}, skipping"
      return 0
   fi

   _info "[argocd] Seeding ArgoCD admin password in Vault"
   local password
   password=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' < /dev/urandom | head -c 24)

   _vault_login "$ns" "$release"
   _vault_exec_stream --no-exit --pod "${release}-0" "$ns" "$release" -- \
      vault kv put "${ARGOCD_VAULT_KV_MOUNT}/${ARGOCD_ADMIN_VAULT_PATH}" \
         "${ARGOCD_ADMIN_PASSWORD_KEY}=${password}"

   _info "[argocd] ArgoCD admin password seeded. Retrieve with:"
   _info "[argocd]   kubectl -n ${ARGOCD_NAMESPACE} get secret ${ARGOCD_ADMIN_SECRET_NAME} -o jsonpath='{.data.password}' | base64 -d"
}
```

In `deploy_argocd`, after `_argocd_setup_vault_policies`, add:

```bash
      # Seed admin secret in Vault if not already present
      _argocd_seed_vault_admin_secret
```

---

## Change 7 — `shellcheck scripts/plugins/argocd.sh`

Run `shellcheck scripts/plugins/argocd.sh` and fix any warnings. Pay special attention to:
- SC2016 (already suppressed at top — verify still needed)
- The `cat <<'HCL' | _vault_exec_stream ...` pipe pattern
- Any unquoted variables

---

## Change 8 — `scripts/tests/plugins/argocd.bats`

Create `scripts/tests/plugins/argocd.bats` with the following tests (follow patterns from
`scripts/tests/plugins/eso.bats` for reference):

```bash
# Tests to write:
# 1. deploy_argocd --help shows usage without error
# 2. deploy_argocd skips when CLUSTER_ROLE=app
# 3. deploy_argocd_bootstrap --help shows usage without error
# 4. deploy_argocd_bootstrap --skip-applicationsets --skip-appproject returns 0 (no-op)
# 5. _argocd_deploy_appproject fails when template is missing
# 6. ARGOCD_NAMESPACE defaults to 'cicd' (not 'argocd')
```

Use stubs for `_kubectl`, `_helm`, `_vault_login`, `_vault_exec_stream`.
Set `AD_TEST_MODE=1` or equivalent to disable live cluster calls.

---

## Verification Steps (Codex must run before committing)

```bash
# 1. Shellcheck
shellcheck scripts/plugins/argocd.sh

# 2. Bats tests
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/argocd.bats

# 3. Confirm namespace default
grep 'ARGOCD_NAMESPACE' scripts/etc/argocd/vars.sh | head -3
```

All three must pass/be clean before committing.

---

## Out of Scope for This Branch

- ArgoCD Rollouts (Phase 2)
- ApplicationSet bootstrap with real GitOps apps (Phase 3+)
- Keycloak OIDC integration
- Live deployment (Gemini handles that after PR merge)
