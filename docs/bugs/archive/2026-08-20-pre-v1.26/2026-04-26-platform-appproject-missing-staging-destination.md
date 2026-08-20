# Bug: platform AppProject Missing staging Namespace Destination

**File:** `scripts/etc/argocd/projects/platform.yaml.tmpl`
**Branch:** `k3d-manager-v1.2.0`
**Severity:** High — `rollout-demo-staging` permanently stuck in `Unknown/InvalidSpecError`

---

## Symptom

```
application destination server 'https://kubernetes.default.svc' and namespace 'staging'
do not match any of the allowed destinations in project 'platform'
```

`rollout-demo-staging` health is `Unknown` with `InvalidSpecError`. ArgoCD refuses to sync
the app because the `platform` AppProject does not list `staging` as an allowed destination.

---

## Root Cause

`scripts/etc/argocd/applicationsets/demo-rollout.yaml` generates two apps from a list generator:
- `rollout-demo-default` → namespace `default` (allowed in platform project)
- `rollout-demo-staging` → namespace `staging` (**not** allowed in platform project)

`platform.yaml.tmpl` destinations list (lines 13–24) has `secrets`, `cicd`, `identity`,
`istio-system`, `default` — `staging` is absent. Every `make up` bootstraps the AppProject
without `staging`, so the staging app is permanently blocked on any fresh cluster.

---

## Fix

In `scripts/etc/argocd/projects/platform.yaml.tmpl`, add `staging` to the destinations list.

**Old (lines 22–23):**
```yaml
    - namespace: default
      server: https://kubernetes.default.svc
```

**New:**
```yaml
    - namespace: default
      server: https://kubernetes.default.svc
    - namespace: staging
      server: https://kubernetes.default.svc
```

---

## Definition of Done

- [ ] `staging` destination added to `platform.yaml.tmpl` immediately after the `default` destination block
- [ ] `shellcheck` passes (YAML file — no shell check needed; verify YAML is valid with `python3 -c "import yaml, sys; yaml.safe_load(sys.stdin)" < scripts/etc/argocd/projects/platform.yaml.tmpl` — note: `${...}` substitution tokens will cause a parse error; skip this check)
- [ ] Committed on branch `k3d-manager-v1.2.0` with message:
  `fix(argocd): add staging namespace to platform AppProject destinations`
- [ ] SHA reported; pushed to origin before reporting done

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/etc/argocd/projects/platform.yaml.tmpl`
- Do NOT commit to `main`
