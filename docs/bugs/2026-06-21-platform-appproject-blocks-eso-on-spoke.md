# Bugfix: ESO Phase 2 — platform AppProject blocks ESO (and all platform apps) on every non-`ubuntu-k3s` spoke

**Branch:** `feat/eso-phase2-clustersecretstore` (PR #98)
**Files:** `scripts/etc/argocd/projects/platform.yaml.tmpl`, `scripts/etc/argocd/applicationsets/eso.yaml`, `scripts/tests/etc/argocd_platform_project.bats` (new)

---

## Problem

ESO Phase 2 ships the `eso` ApplicationSet, which fans ESO out to every cluster labeled
`k3d-manager/role: app-cluster`. But on the live hub the generated Application
`ubuntu-hostinger-eso` is **rejected by ArgoCD and never syncs**:

```
InvalidSpecError: application destination server 'https://2.25.146.252:6443' and
namespace 'secrets' do not match any of the allowed destinations in project 'platform'
```

Because ESO never installs on the Hostinger spoke, no `ClusterSecretStore` /
`ExternalSecret` resources can be created there, so `order-service-secrets` and
`payment-service-secrets` are never synced from Vault → `order-service` and
`payment-service` pods sit in `CreateContainerConfigError`. **This is the "nothing
works" outage** — and it means PR #98 (ESO Phase 2) does not actually deliver working
ESO on any spoke other than `ubuntu-k3s` until this is fixed.

**Root cause (two compounding defects):**

1. **`platform.yaml.tmpl` hardwires every app-cluster destination to `name: ubuntu-k3s`.**
   The platform AppProject is the security allow-list for platform apps (ESO, monitoring,
   trivy). Each spoke destination entry is pinned to the literal cluster name `ubuntu-k3s`,
   so the project rejects the identical workload on `ubuntu-hostinger` (or any future
   `ubuntu-gcp` / `ubuntu-azure` spoke). This is the same defect class that
   `v1.5.0-bugfix-platform-project-missing-cicd-ubuntu-k3s.md` and
   `2026-04-26-platform-appproject-missing-staging-destination.md` patched by *adding more
   hardcoded rows* — the list keeps accreting per-cluster literals instead of being
   provider-generic.

2. **`eso.yaml` addresses its destination by raw `server` URL, not by cluster `name`.**
   It uses `destination.server: '{{.server}}'` (`https://2.25.146.252:6443`) while the
   working data ApplicationSets (`data-git.yaml`, `services-git.yaml`) use
   `destination.name: '{{.name}}'`. The `name` form is what the project allow-list and the
   rest of the codebase match on.

---

## Why NOT the `APP_CLUSTER_NAME` retarget approach (abandoned)

Two earlier branches attacked this; **do not use either as-is** — this spec supersedes both:

- `fix/platform-appproject-retarget-hostinger` (`252b871e`): swapped `name: ubuntu-k3s` →
  `name: ${APP_CLUSTER_NAME}` and added `APP_CLUSTER_NAME="${APP_CLUSTER_NAME:-ubuntu-hostinger}"`
  to `_argocd_deploy_appproject` in `scripts/plugins/argocd.sh`. **This is the major flaw the
  PR must not ship:** it only moves the hardwire from one literal (`ubuntu-k3s`) to another
  (`ubuntu-hostinger`) baked at template-render time. The whole point of the `eso`/`data-git`
  **cluster generators** is to fan out to *all* registered spokes simultaneously
  (`matchLabels: k3d-manager/role: app-cluster`). A single render-time name supports exactly
  one spoke; it regresses `ubuntu-k3s` and breaks the moment a second spoke is registered. It
  also reintroduces a provider-specific literal (`ubuntu-hostinger`) into shared library code,
  the exact anti-pattern `project_app_cluster_vault_auth_portability` warns against.
- `fix/platform-appproject-provider-generic` (`10dd49f8`): the correct provider-generic
  approach (`name: '*'` + eso `.name`). This spec ratifies that approach and consolidates it
  into the Phase 2 branch so PR #98 ships working ESO; `10dd49f8` and `252b871e` are then
  abandoned (their standalone branches will be closed/deleted by Claude — not Codex's task).

The fix below allows the project's **cluster generator** to remain the single gate over
*which* clusters receive platform apps; the AppProject becomes namespace-scoped but
provider-agnostic by cluster name. It is still least-privilege: the `name: '*'` glob is
scoped to specific platform namespaces (`secrets`, `cicd`, `monitoring`, `trivy-system`,
`shopping-cart-*`) — never `namespace: '*'`.

---

## Reproduction

```
# Hub = local k3d cluster; Hostinger registered as a spoke (role=app-cluster)
kubectl --context k3d-k3d-cluster -n cicd get application ubuntu-hostinger-eso \
  -o jsonpath='{.status.conditions}'
# => InvalidSpecError: ... do not match any of the allowed destinations in project 'platform'

kubectl --context ubuntu-hostinger get crd | grep external-secrets   # (empty — ESO absent)
kubectl --context ubuntu-hostinger -n shopping-cart-apps get pod      # order-service CreateContainerConfigError
```

Expected after fix (operator re-applies the project + appset on the hub): the
`ubuntu-hostinger-eso` Application becomes `Synced`, ESO installs into `secrets` on the
spoke, ESO CRDs appear, and ExternalSecrets can populate the app secrets.

---

## Fix

### Change 1 — `scripts/etc/argocd/projects/platform.yaml.tmpl`: make app-cluster destinations provider-generic

Replace the entire `destinations:` block (lines 13–43).

**Exact old block:**

```yaml
  destinations:
    - namespace: secrets
      server: https://kubernetes.default.svc
    - namespace: secrets
      name: ubuntu-k3s
    - namespace: cicd
      server: https://kubernetes.default.svc
    - namespace: identity
      server: https://kubernetes.default.svc
    - namespace: istio-system
      server: https://kubernetes.default.svc
    - namespace: default
      server: https://kubernetes.default.svc
    - namespace: staging
      server: https://kubernetes.default.svc
    - namespace: shopping-cart-apps
      name: ubuntu-k3s
    - namespace: shopping-cart-payment
      name: ubuntu-k3s
    - namespace: shopping-cart-data
      name: ubuntu-k3s
    - namespace: cicd
      name: ubuntu-k3s
    - namespace: monitoring
      server: https://kubernetes.default.svc
    - namespace: trivy-system
      server: https://kubernetes.default.svc
    - namespace: monitoring
      name: ubuntu-k3s
    - namespace: trivy-system
      name: ubuntu-k3s
```

**Exact new block:**

```yaml
  destinations:
    - namespace: secrets
      server: https://kubernetes.default.svc
    - namespace: secrets
      name: '*'
    - namespace: cicd
      server: https://kubernetes.default.svc
    - namespace: identity
      server: https://kubernetes.default.svc
    - namespace: istio-system
      server: https://kubernetes.default.svc
    - namespace: default
      server: https://kubernetes.default.svc
    - namespace: staging
      server: https://kubernetes.default.svc
    - namespace: shopping-cart-apps
      name: '*'
    - namespace: shopping-cart-payment
      name: '*'
    - namespace: shopping-cart-data
      name: '*'
    - namespace: cicd
      name: '*'
    - namespace: monitoring
      server: https://kubernetes.default.svc
    - namespace: trivy-system
      server: https://kubernetes.default.svc
    - namespace: monitoring
      name: '*'
    - namespace: trivy-system
      name: '*'
```

### Change 2 — `scripts/etc/argocd/applicationsets/eso.yaml`: address the spoke by cluster name

In the `template.spec.destination` block, change the `server` form to the `name` form so it
matches `data-git.yaml` / `services-git.yaml` and the platform project allow-list.

**Exact old block:**

```yaml
      destination:
        server: '{{.server}}'
        namespace: secrets
```

**Exact new block:**

```yaml
      destination:
        name: '{{.name}}'
        namespace: secrets
```

### Change 3 — `scripts/tests/etc/argocd_platform_project.bats` (new file): lock the fix in

Create the file with exactly this content:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  PLATFORM_TMPL="${REPO_ROOT}/scripts/etc/argocd/projects/platform.yaml.tmpl"
  ESO_APPSET="${REPO_ROOT}/scripts/etc/argocd/applicationsets/eso.yaml"
}

@test "platform AppProject does not hardwire app-cluster to a single provider name" {
  run grep -nE 'name:[[:space:]]*ubuntu-k3s' "$PLATFORM_TMPL"
  [ "$status" -ne 0 ]
}

@test "platform AppProject does not bake a render-time provider name" {
  run grep -nE 'name:[[:space:]]*\$\{APP_CLUSTER_NAME\}' "$PLATFORM_TMPL"
  [ "$status" -ne 0 ]
}

@test "platform AppProject uses provider-generic app-cluster destinations" {
  run grep -cE "name:[[:space:]]*'\\*'" "$PLATFORM_TMPL"
  [ "$status" -eq 0 ]
  [ "$output" -ge 7 ]
}

@test "eso ApplicationSet uses cluster-name destination form (matches data-git)" {
  run grep -nE "name:[[:space:]]*'\\{\\{.name\\}\\}'" "$ESO_APPSET"
  [ "$status" -eq 0 ]
  run grep -nE "server:[[:space:]]*'\\{\\{.server\\}\\}'" "$ESO_APPSET"
  [ "$status" -ne 0 ]
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/projects/platform.yaml.tmpl` | 7× app-cluster destination `name: ubuntu-k3s` → `name: '*'` (provider-generic) |
| `scripts/etc/argocd/applicationsets/eso.yaml` | destination `server: '{{.server}}'` → `name: '{{.name}}'` |
| `scripts/tests/etc/argocd_platform_project.bats` | new — asserts no `ubuntu-k3s`/`${APP_CLUSTER_NAME}` literal, `name: '*'` ≥7, eso uses `.name` |

---

## Rules

- Minimal patch — only the three files above. Do **NOT** touch `scripts/plugins/argocd.sh`
  (no `APP_CLUSTER_NAME` envsubst/default — that is the abandoned retarget approach).
- `_argocd_deploy_appproject` must keep `envsubst '$ARGOCD_NAMESPACE'` exactly as-is — the
  template now contains the literal `'*'`, so no new variable substitution is introduced.
- Preserve existing indentation (2-space YAML), quoting (`'*'` and `'{{.name}}'` must stay
  single-quoted so YAML/goTemplate parse correctly), and LF line endings.
- `./scripts/k3d-manager test all` — full suite green, including the new
  `scripts/tests/etc/argocd_platform_project.bats`.
- `./scripts/k3d-manager _agent_audit` — must exit 0.
- Do NOT apply anything to a live cluster. Re-applying the platform AppProject + `eso`
  ApplicationSet on the hub is a **separate operator step Claude runs after merge** (see Out
  of scope).

---

## Definition of Done

- [ ] Changes 1, 2, 3 applied exactly as written.
- [ ] `scripts/plugins/argocd.sh` unchanged (verify `git diff --stat` lists only the three files above).
- [ ] `./scripts/k3d-manager test all` green, including `scripts/tests/etc/argocd_platform_project.bats` (4 tests `ok`).
- [ ] `./scripts/k3d-manager _agent_audit` exits 0.
- [ ] Commit with message **exactly**:
      `fix(argocd): provider-generic platform AppProject + eso name destination`
- [ ] `git push origin feat/eso-phase2-clustersecretstore` — do NOT report done until the push succeeds.
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with the commit SHA and status.
- [ ] Report back: commit SHA + `git diff --stat` of the commit + the memory-bank lines you updated.

---

## What NOT to Do

- Do NOT create a PR (PR #98 already exists for this branch).
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than the three listed targets — specifically NOT `scripts/plugins/argocd.sh`.
- Do NOT commit to `main` — work on `feat/eso-phase2-clustersecretstore`.
- Do NOT use `name: ${APP_CLUSTER_NAME}` or any single literal cluster name — the fix is `name: '*'`.
- Do NOT widen any destination to `namespace: '*'` — keep namespaces explicit.

---

## Out of scope (separate follow-ups — do NOT touch here)

1. **Live re-apply** — after merge, Claude re-renders the platform AppProject and the `eso`
   ApplicationSet onto the hub so the rejected `ubuntu-hostinger-eso` Application re-evaluates
   and syncs. Not a Codex task; no live process touched in this bugfix.
2. **`data-layer` SyncError** — `data-git` Application on `ubuntu-hostinger` fails with
   `one or more synchronization tasks are not valid` (a shopping-cart-infra manifest issue),
   distinct from this AppProject rejection. Track separately if it persists after ESO is healthy.
3. **`observability-acg.yaml`** uses a render-time `name: ${APP_CLUSTER_NAME}` (ACG preflight
   list generator, not a cluster generator). It is allowed by the new `name: '*'` rows, so it
   is not part of this outage; revisit its hardwire only if it later misroutes.
