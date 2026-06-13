# Bugfix: v1.7.0 — `make up CLUSTER_PROVIDER=k3s-hostinger` trips the deploy safety gate

**Branch:** `k3d-manager-v1.7.0`
**Files:** `Makefile`

---

## Problem

`make up CLUSTER_PROVIDER=k3s-hostinger` fails immediately with:

```
Usage: deploy_cluster [options] [cluster_name]
...
Safety gate: rerun with explicit options or pass --confirm to apply defaults.
make: *** [up] Error 1
```

The provider never runs — no SSH, no k3sup. The failure is the dispatcher's deploy
guard, not the provider.

**Root cause:** the `Makefile` `up` target's `k3s-hostinger` arm calls
`deploy_cluster` with **no arguments**. The dispatcher gate
`__k3dm_deploy_guard_args` (`scripts/k3d-manager:530`) exits 1 when none of
`--confirm` / `--dry-run` / a positional arg is present. The sibling `k3s-oci`
arm (line 20) passes `--confirm`; the `k3s-hostinger` arm (line 22) omits it.
The `down` target's `k3s-hostinger` arm already passes `--confirm` correctly —
only `up` was missed.

---

## Reproduction

```bash
make up CLUSTER_PROVIDER=k3s-hostinger
# actual:   Safety gate ... make: *** [up] Error 1
# expected: provider runs (SSH wait → k3sup install → merge kubeconfig)
```

---

## Fix

### Change 1 — `Makefile`: pass `--confirm` to the `k3s-hostinger` up arm (mirror `k3s-oci`)

**Exact old block (line 22):**

```makefile
	  k3s-hostinger) CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager deploy_cluster ;; \
```

**Exact new block:**

```makefile
	  k3s-hostinger) CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager deploy_cluster --confirm ;; \
```

(Leading whitespace is a TAB followed by two spaces — do not convert the tab.)

---

## Files Changed

| File | Change |
|------|--------|
| `Makefile` | `k3s-hostinger` `up` arm passes `--confirm` so the deploy gate accepts it |

---

## Rules

- `make -n up CLUSTER_PROVIDER=k3s-hostinger` — expands to `... deploy_cluster --confirm`
- `git diff --check` — clean (no whitespace errors, tab preserved)
- No other files touched (do NOT change the `observability` line or any other arm)

---

## Definition of Done

- [ ] `k3s-hostinger` up arm passes `--confirm`
- [ ] `make -n up CLUSTER_PROVIDER=k3s-hostinger` shows `deploy_cluster --confirm`
- [ ] Tab indentation preserved (`git diff --check` clean)
- [ ] Committed and pushed to `k3d-manager-v1.7.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(make): pass --confirm to k3s-hostinger up arm so deploy gate accepts it
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `Makefile`
- Do NOT touch the `observability` line or the `down`/`status` arms
- Do NOT commit to `main` — work on `k3d-manager-v1.7.0`
