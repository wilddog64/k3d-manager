# Codex Task: Update Reusable Workflow SHA to Enable Multi-Arch Builds (v0.9.4)

## Context

All 5 shopping-cart app repos pin their `publish` job to a stale SHA of
`shopping-cart-infra/.github/workflows/build-push-deploy.yml`. The pinned SHA
(`8363caf`) predates the multi-arch fix. As a result, CI builds only `linux/amd64`
images, which fail to run on the Ubuntu k3s node (arm64).

The current infra HEAD (`999f8d70277b92d928412ff694852b05044dbb75`) contains the fix:
```yaml
platforms: linux/amd64,linux/arm64
```

**Fix:** Update the pinned SHA in all 5 app repos. Re-running CI will push
`linux/amd64,linux/arm64` images to ghcr.io. ArgoCD will then sync successfully.

---

## Exact Change Required

In each file listed below, replace:
```
wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@8363caf109617e66f2a65be08d66a7e51b8a0e96
```
With:
```
wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@999f8d70277b92d928412ff694852b05044dbb75
```

---

## Files to Change

| Repo | File |
|------|------|
| `shopping-cart-basket` | `.github/workflows/go-ci.yml` |
| `shopping-cart-order` | `.github/workflows/ci.yml` |
| `shopping-cart-payment` | `.github/workflows/ci.yaml` |
| `shopping-cart-product-catalog` | `.github/workflows/ci.yml` |
| `shopping-cart-frontend` | `.github/workflows/ci.yml` |

Local paths (all under `~/src/gitrepo/personal/shopping-carts/`):
- `shopping-cart-basket/.github/workflows/go-ci.yml`
- `shopping-cart-order/.github/workflows/ci.yml`
- `shopping-cart-payment/.github/workflows/ci.yaml`
- `shopping-cart-product-catalog/.github/workflows/ci.yml`
- `shopping-cart-frontend/.github/workflows/ci.yml`

---

## Steps

### 1. Verify starting state

```bash
grep -rn "8363caf" \
  ~/src/gitrepo/personal/shopping-carts/shopping-cart-basket/.github/ \
  ~/src/gitrepo/personal/shopping-carts/shopping-cart-order/.github/ \
  ~/src/gitrepo/personal/shopping-carts/shopping-cart-payment/.github/ \
  ~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog/.github/ \
  ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend/.github/
```

Expected: 5 matches — one per repo.

### 2. Create branch and apply fix in each repo

For each repo:
```bash
cd ~/src/gitrepo/personal/shopping-carts/<repo>
git checkout main && git pull origin main
git checkout -b fix/multiarch-workflow-pin
# Edit the workflow file — replace the SHA
git add .github/
git commit -m "ci: pin build-push-deploy to multi-arch SHA (999f8d7)

Updates reusable workflow pin from 8363caf (amd64-only) to 999f8d7
which includes platforms: linux/amd64,linux/arm64.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push origin fix/multiarch-workflow-pin
```

### 3. Open PRs — one per repo

```bash
gh pr create --repo wilddog64/<repo> \
  --title "ci: pin build-push-deploy to multi-arch SHA (999f8d7)" \
  --body "Updates reusable workflow pin from \`8363caf\` (amd64-only) to \`999f8d7\` which includes \`platforms: linux/amd64,linux/arm64\`. Fixes ImagePullBackOff on arm64 k3s node." \
  --base main --head fix/multiarch-workflow-pin
```

### 4. Wait for CI green on each PR branch

```bash
gh run list --repo wilddog64/<repo> --limit 3
```

All jobs must pass before merging.

### 5. Report completion

For each repo provide:
- PR URL
- CI run ID and status
- Commit SHA of the fix

---

## Definition of Done

- [ ] SHA updated in all 5 workflow files — verified with grep (0 matches for `8363caf`)
- [ ] PRs open on all 5 repos — `fix/multiarch-workflow-pin` branch
- [ ] CI green on all 5 PR branches
- [ ] Report PR URLs + commit SHAs

**Do NOT merge the PRs** — Claude will merge after verifying CI.

---

## What NOT to Do

- Do NOT change anything other than the SHA string in the workflow files
- Do NOT modify Dockerfiles, k8s manifests, or any other files
- Do NOT merge the PRs
- Do NOT rebase / reset --hard / push --force
- Do NOT fabricate SHAs — verify with `git log` before reporting
