# Bug: acg-up — `return 1` outside function fails with "can only return from function"

**Branch:** `k3d-manager-v1.4.6`
**Files:** `bin/acg-up`

---

## Problem

`bin/acg-up` line 111 uses `|| return 1` as an error guard after `acg_get_credentials`.
`bin/acg-up` is a standalone script — it is executed directly, not sourced. `return` is
only valid inside a function or a sourced script. Using it at the top level of an executed
script emits:

```
bin/acg-up: line 111: return: can only `return' from a function or sourced script
make: *** [up] Error 2
```

**Root cause:** The fix in `b1da7ef4` correctly removed the `aws sts` shortcut and added
the error guard, but used `return 1` instead of `exit 1`. `bin/acg-up` is invoked via
`bin/acg-up ...` (executed), not `source bin/acg-up`.

---

## Reproduction

1. Run `make up` with `CLUSTER_PROVIDER=k3s-aws`
2. `acg_get_credentials` fails (any reason)
3. `|| return 1` executes at the top level of `bin/acg-up`
4. Shell prints "can only return from a function or sourced script"
5. `make` reports `Error 2`

---

## Fix

### Change 1 — `bin/acg-up` line 111: `return 1` → `exit 1`

**Exact old line:**
```bash
    acg_get_credentials ${sandbox_url:+"$sandbox_url"} || return 1
```

**Exact new line:**
```bash
    acg_get_credentials ${sandbox_url:+"$sandbox_url"} || exit 1
```

---

## Files Changed

| File | Changes |
|------|---------|
| `bin/acg-up` | Change 1 — `return 1` → `exit 1` on line 111 |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched
- Exactly one line changes

---

## Definition of Done

- [ ] Line 111: `|| return 1` → `|| exit 1`
- [ ] All surrounding lines unchanged
- [ ] `shellcheck -S warning bin/acg-up` passes
- [ ] No other files modified
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg-up): use exit 1 instead of return — bin/acg-up is executed not sourced
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change anything else on line 111 — only `return` → `exit`
