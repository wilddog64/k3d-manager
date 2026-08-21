# Bugfix: re-apply frontend SSO changes after accidental revert on main

**Branch:** `shopping-cart-frontend-v0.5.1`
**Repo:** `shopping-cart-frontend` (`~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend`)

---

## Before You Start

1. `git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend fetch origin`
2. `git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend checkout shopping-cart-frontend-v0.5.1`
3. Read this spec in full before touching any file
4. Confirm `origin/main` has the revert at its tip:
   ```bash
   git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend log origin/main --oneline -3
   ```
   Expected: top commit is `2872a4cd Revert "fix(frontend): wire Keycloak SSO build args and CSP host"`
5. Confirm the branch's current `nginx.conf` has `keycloak.shopping-cart.local` in `connect-src`:
   ```bash
   grep "connect-src" ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend/nginx.conf
   ```

---

## Problem

The functional fix for frontend SSO (`6120783`) was accidentally pushed to `main` and then
reverted (`2872a4cd`). The PR branch (`v0.5.1`) shares `6120783` as a common ancestor with
`main`, so GitHub's 3-way merge sees no diff for `ci.yml` or `nginx.conf`. If the PR is
merged as-is, the revert wins and main ends up without the fix.

The branch needs a new explicit commit that changes the files **from main's current (reverted)
state** to the correct state, so the PR diff shows the changes and the merge delivers them.

---

## Fix — two steps

### Step 1: Merge origin/main into the branch

This brings the revert into the branch, giving you a working tree with the OLD (broken) file
contents to work from:

```bash
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend merge origin/main \
  --no-edit -m "chore: merge main to pick up revert before re-applying SSO fix"
```

After this merge, confirm the files are in the REVERTED (broken) state:
- `nginx.conf` connect-src should contain `keycloak.identity.svc.cluster.local:8080`
- `.github/workflows/ci.yml` should NOT have `build-args` and should use SHA `3e3a7957`

### Step 2: Re-apply the two file changes

**`.github/workflows/ci.yml`** — find the "Build, Scan & Push" job:

**Old:**
```yaml
    uses: wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@3e3a7957cab3fb102946d6eaab10cd106ce7b1f2
    with:
      service-name: shopping-cart-frontend
      image-name: ghcr.io/wilddog64/shopping-cart-frontend
```

**New:**
```yaml
    uses: wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@8c581840b904f21459fa225c80ddfe54f93ed9aa
    with:
      service-name: shopping-cart-frontend
      image-name: ghcr.io/wilddog64/shopping-cart-frontend
      build-args: VITE_KEYCLOAK_URL=http://keycloak.shopping-cart.local
```

**`nginx.conf`** — find the `connect-src` directive in the `Content-Security-Policy` header:

**Old `connect-src` value:**
```
connect-src 'self' http://keycloak.identity.svc.cluster.local:8080 https://*.keycloak.local;
```

**New:**
```
connect-src 'self' http://keycloak.shopping-cart.local https://*.keycloak.local;
```

---

## Files Changed

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | Update SHA pin to `8c581840`; add `build-args: VITE_KEYCLOAK_URL=http://keycloak.shopping-cart.local` |
| `nginx.conf` | Replace in-cluster Keycloak service URL with public hostname in CSP `connect-src` |

---

## What NOT to Do

- Do NOT create a PR — PR #15 is already open; just push the branch
- Do NOT skip pre-commit hooks — run hooks normally (frontend repo has pre-commit config)
- Do NOT modify any file other than those listed above
- Do NOT commit to `main`
- Do NOT close or recreate PR #15 — the new commits will update it automatically

---

## Rules

- Work on `shopping-cart-frontend-v0.5.1`
- Push to `origin/shopping-cart-frontend-v0.5.1`

**Commit messages (exact):**
```
chore: merge main to pick up revert before re-applying SSO fix
```
```
fix(ci): re-apply VITE_KEYCLOAK_URL build arg and nginx CSP after revert
```

---

## Definition of Done

- [ ] `git log origin/shopping-cart-frontend-v0.5.1 --oneline -5` shows both new commits
- [ ] PR #15 diff (`gh pr view 15 --repo wilddog64/shopping-cart-frontend`) shows `.github/workflows/ci.yml` and `nginx.conf` as changed files
- [ ] `nginx.conf` has `http://keycloak.shopping-cart.local` in `connect-src`
- [ ] `ci.yml` has `build-args: VITE_KEYCLOAK_URL=http://keycloak.shopping-cart.local` and SHA `8c581840`
- [ ] Pushed to `origin/shopping-cart-frontend-v0.5.1`
- [ ] Commit SHA reported back
