# 2026-06-19 — Copilot PR #96 findings: /cluster-resume provider parsing, rg test dependency, preflight RBAC justification

**Filed:** 2026-06-19 (Claude)
**Type:** bugfix / hardening — addresses Copilot review on PR #96
**Branch:** `k3d-manager-v1.7.1` (existing — do NOT branch off main)
**Files (exactly three):**
- `workers/slack-relay/index.js`
- `scripts/tests/plugins/argocd_app_cluster_generator.bats`
- `scripts/etc/vcluster/argocd-manager-rbac.yaml`

## Why

Copilot left three comments on PR #96. All three are valid:

1. **`/cluster-resume` duplicates `resolveProvider()` and silently defaults to `aws`** — risk of an
   accidental AWS sandbox resume when the provider is omitted or mistyped.
2. **The generator BATS test hard-depends on `rg` (ripgrep)**, which `install.sh` does not install —
   fresh environments fail. A plain recursive `grep` is sufficient (search is already dir-scoped).
3. **Preflight RBAC grants effective cluster-admin** (`*` everything). CLAUDE.md requires new
   ClusterRoles to be **justified**. This mirrors ArgoCD's standard `argocd-manager` role and is
   installed only inside an ephemeral throwaway vCluster — so the fix is to document that
   justification explicitly (blast radius is bounded operationally, not by RBAC).

## Before You Start

- `git pull origin k3d-manager-v1.7.1`
- Read all three target files in full before editing.

## Change 1 — `workers/slack-relay/index.js`: use `resolveProvider`, require an explicit sandbox provider

**Exact old block:**
```js
  if (command === '/cluster-resume') {
    const _t = text.toLowerCase()
    const _p = PROVIDER_ALIASES[_t] || _t
    const provider = VALID_PROVIDERS.has(_p) ? _p : 'aws'
    const { ok, conflict } = await relay('/api/v1/cluster-resume', { provider, response_url: responseUrl })
```

**Exact new block:**
```js
  if (command === '/cluster-resume') {
    const provider = resolveProvider(text, '')
    if (!VALID_PROVIDERS.has(provider)) {
      return jsonReply('Usage: /cluster-resume <aws|gcp|az> — resumes a lab sandbox provision from its last checkpoint', threadTs)
    }
    const { ok, conflict } = await relay('/api/v1/cluster-resume', { provider, response_url: responseUrl })
```

Rationale: dedups the parsing onto `resolveProvider`, removes the silent `aws` fallback, and
rejects both typos and `hostinger` (the permanent cluster is not "resumed from checkpoint").
`VALID_PROVIDERS` (`aws`/`gcp`/`az`) is the correct set for a resumable lab sandbox.

## Change 2 — `scripts/tests/plugins/argocd_app_cluster_generator.bats`: drop the `rg` dependency

**Exact old block:**
```bash
@test "argocd app cluster generator: no static ubuntu-k3s ApplicationSet destination remains" {
  run rg -n -U "destination:\\n\\s+name: ubuntu-k3s" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets"
  [ "$status" -eq 1 ]
}
```

**Exact new block:**
```bash
@test "argocd app cluster generator: no static ubuntu-k3s ApplicationSet destination remains" {
  run grep -rF -- "ubuntu-k3s" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets"
  [ "$status" -eq 1 ]
}
```

Rationale: `grep -rF` needs no extra tooling and returns exit 1 when there is no match. Verified
there are currently **zero** `ubuntu-k3s` references in that directory, so the assertion (no static
ubuntu-k3s destination remains after the cutover) still holds and is slightly stronger.

## Change 3 — `scripts/etc/vcluster/argocd-manager-rbac.yaml`: expand the justification annotation

Keep the rules exactly as-is (this is ArgoCD's standard cluster-manager role; the application
controller must reconcile arbitrary GitOps manifests — Istio/Vault/ESO/cert-manager CRDs — that
cannot be enumerated ahead of time). Replace ONLY the annotation comment with a fuller justification.

**Exact old block:**
```yaml
  annotations:
    # ArgoCD needs broad cluster access to reconcile the shopping-cart stack and its CRDs.
    # This RBAC manifest is installed inside the throwaway vCluster for Phase 1 preflight.
```

**Exact new block:**
```yaml
  annotations:
    # JUSTIFICATION (CLAUDE.md: "new ClusterRoles must be justified"):
    # Mirrors ArgoCD's standard `argocd-manager` cluster role (the same wildcard role that
    # `argocd cluster add` installs). The application-controller must reconcile arbitrary GitOps
    # manifests — Istio, Vault, ESO, cert-manager CRDs, etc. — that cannot be enumerated ahead of
    # time, so a scoped role would silently break reconciliation. Blast radius is bounded
    # operationally, not by RBAC: installed ONLY inside an ephemeral throwaway vCluster created for
    # Phase 1 preflight and destroyed when the run ends. Never applied to the host or any production path.
```

## Rules

- `node --check workers/slack-relay/index.js` — zero errors (syntax).
- `bash -n scripts/tests/plugins/argocd_app_cluster_generator.bats` — clean; run the suite:
  `bats scripts/tests/plugins/argocd_app_cluster_generator.bats` — all tests pass.
- YAML stays valid; do NOT change the ClusterRole `rules`, the ServiceAccount, or the ClusterRoleBinding.
- `./scripts/k3d-manager _agent_audit` — clean.
- LF line endings only. No `--no-verify`. Only the three files above may change.
- Never commit on `main` — work on `k3d-manager-v1.7.1`.

## Definition of Done

- [ ] All three exact edits applied.
- [ ] `node --check` passes; `bats` suite passes; `_agent_audit` clean.
- [ ] Committed + pushed to `k3d-manager-v1.7.1`; SHA confirmed on `origin/k3d-manager-v1.7.1`.
- [ ] memory-bank `activeContext.md` + `progress.md` updated with the SHA and status.

**Commit message (exact):**
```
fix(slack,vcluster): cluster-resume uses resolveProvider, drop rg test dep, justify preflight RBAC (Copilot PR#96)
```

## What NOT to do

- Do NOT create a PR (PR #96 already exists — pushing the branch updates it).
- Do NOT merge any PR.
- Do NOT change the ClusterRole `rules` blocks (only the annotation comment).
- Do NOT modify any file other than the three listed.
- Do NOT skip pre-commit hooks.
