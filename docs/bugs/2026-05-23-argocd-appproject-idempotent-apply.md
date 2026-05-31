# Bug: ArgoCD AppProject apply fails on re-run — resourceVersion must be specified for update

**Branch:** `k3d-manager-v1.4.9`
**File:** `scripts/plugins/argocd.sh`

---

## Problem

`make up` fails with:

```
The appprojects "platform" is invalid: metadata.resourceVersion: Invalid value: 0x0: must be specified for an update
kubectl command failed (1): kubectl apply -f /tmp/argocd-appproject.*.yaml
ERROR: failed to execute kubectl apply -f ...: 1
```

ArgoCD CRDs require `resourceVersion` for updates when using client-side `kubectl apply`.
On a re-run (AppProject already exists), client-side apply cannot supply `resourceVersion`
and the API server rejects the update. Fix: use `--server-side` flag, which lets the server
manage field ownership and `resourceVersion` without client-side tracking.

---

## Fix

### Change — `scripts/plugins/argocd.sh` line 1065: add `--server-side` to AppProject apply

**Exact old line:**

```bash
   _kubectl apply -f "$rendered" >/dev/null
```

**Exact new line:**

```bash
   _kubectl apply --server-side -f "$rendered" >/dev/null
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/argocd.sh` | Add `--server-side` flag to `_kubectl apply` in `_argocd_deploy_appproject` (line 1065) |

---

## Rules

- `shellcheck -S warning scripts/plugins/argocd.sh` — zero new warnings
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] Line 1065: `_kubectl apply --server-side -f "$rendered"` (flag added)
- [ ] No other functions or files modified
- [ ] `shellcheck` passes
- [ ] `make up` completes without AppProject error on a cluster where AppProject already exists
- [ ] Committed and pushed to `k3d-manager-v1.4.9`

**Commit message (exact):**
```
fix(argocd): use server-side apply for AppProject — client-side apply fails when resource already exists
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any other function in the file
- Do NOT commit to `main`
