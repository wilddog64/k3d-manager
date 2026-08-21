# Bugfix: acg-up seed job delete blocks indefinitely on ArgoCD hook finalizer

**Branch:** `k3d-manager-v1.4.10`
**Files:** `bin/acg-up`

---

## Problem

`bin/acg-up` hangs at the product-catalog seed step for the full duration of the ACG session (~10 minutes observed). The script deletes the existing seed job before re-applying it, but `kubectl delete` without `--wait=false` blocks until the object is gone. The seed job carries an `argocd.argoproj.io/hook-finalizer`, which ArgoCD never clears during a plain delete — so the command blocks indefinitely.

**Root cause:** `kubectl delete job product-catalog-seed` at `bin/acg-up:1473` omits `--wait=false`, causing it to block until the hook finalizer is removed, which ArgoCD does not do synchronously on a direct delete.

---

## Reproduction

1. Deploy `product-catalog` via ArgoCD — the seed job gets the `hook-finalizer` annotation.
2. Run `bin/acg-up` with an empty products DB.
3. Script prints `Product DB is empty — running seed job...` then hangs.
4. `kubectl get job product-catalog-seed -n shopping-cart-apps` shows `Terminating` indefinitely.

---

## Fix

### Change 1 — `bin/acg-up:1474`: add `--wait=false` to seed job delete

**Exact old block (lines 1473–1474):**

```bash
    kubectl delete job product-catalog-seed \
      -n shopping-cart-apps --context ubuntu-k3s --ignore-not-found >/dev/null 2>&1
```

**Exact new block:**

```bash
    kubectl delete job product-catalog-seed \
      -n shopping-cart-apps --context ubuntu-k3s --ignore-not-found --wait=false >/dev/null 2>&1
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add `--wait=false` to seed job delete so ArgoCD hook finalizer does not block apply |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- Code change limited to `bin/acg-up`; docs/memory-bank updates may also be required

---

## Definition of Done

- [x] `--wait=false` added to `kubectl delete job product-catalog-seed` at line 1474
- [x] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.10`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-up): add --wait=false to seed job delete — hook-finalizer blocks indefinitely
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.10`
