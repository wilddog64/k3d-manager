# Bugfix: v1.17.0 — argocd dead-path removal follow-up (orphaned `enable_vault` local + fn separator)

**Branch:** `k3d-manager-v1.17.0`
**Files:** `scripts/plugins/argocd.sh`

---

## Problem

Follow-up to `ac729e14` (removal of dead `_argocd_configure_post_deploy`). That deletion was
correct, but left two loose ends:

1. **Orphaned dead local.** `deploy_argocd()` declares `local enable_vault=1` at
   `scripts/plugins/argocd.sh:425` but never reads it — the option-parsing that was meant to
   consume it is already gone (only `enable_ldap` is passed, at line 430). It was invisible to
   shellcheck until now because the deleted function had a same-named `enable_vault` parameter
   that masked SC2034. With that function gone, `shellcheck -S warning` now reports
   `SC2034: enable_vault appears unused` at line 425. This local and the deleted function were
   two halves of the **same** abandoned code path.

2. **Missing function separator.** The removal collapsed the blank line between
   `_argocd_configure_vault_eso`'s closing `}` (line 574) and
   `function _argocd_seed_vault_admin_secret()` (line 575), leaving **zero** blank lines where
   the rest of the file uses exactly one between functions.

**Root cause:** collateral dead code from the pre-existing refactor that orphaned
`_argocd_configure_post_deploy`, plus an over-eager blank-line collapse in the deletion.

---

## Reproduction

```bash
shellcheck -S warning scripts/plugins/argocd.sh   # SC2034: enable_vault appears unused (line 425)
```

---

## Fix

### Change 1 — `scripts/plugins/argocd.sh`: remove the orphaned `enable_vault` local

**Exact old block (lines 424–426):**

```bash
   local enable_ldap=1  # Default to smart enabled
   local enable_vault=1 # Default to smart enabled
   # ... option parsing ...
```

**Exact new block:**

```bash
   local enable_ldap=1  # Default to smart enabled
   # ... option parsing ...
```

### Change 2 — `scripts/plugins/argocd.sh`: restore the single blank line between functions

**Exact old block (lines 573–575):**

```bash
   _info "[argocd] Vault/ESO integration configured"
}
function _argocd_seed_vault_admin_secret() {
```

**Exact new block:**

```bash
   _info "[argocd] Vault/ESO integration configured"
}

function _argocd_seed_vault_admin_secret() {
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/argocd.sh` | remove dead `enable_vault` local in `deploy_argocd`; restore one blank line before `_argocd_seed_vault_admin_secret` |

---

## Rules

- Do NOT touch `enable_ldap` (line 424) — it IS used (passed at line 430).
- Do NOT touch any other function, variable, or template.
- `shellcheck -S warning scripts/plugins/argocd.sh` — must report **zero** warnings (the SC2034
  must disappear; no new warnings introduced).
- `bash -n scripts/plugins/argocd.sh` — clean.
- `bats scripts/tests/plugins/argocd_servicemonitors_ensure.bats` — still 3/3.
- Run `_agent_audit` before reporting done.

---

## Definition of Done

- [ ] `grep -c 'enable_vault' scripts/plugins/argocd.sh` → **0** (disappearance gate)
- [ ] Exactly one blank line separates `_argocd_configure_vault_eso`'s `}` from `function _argocd_seed_vault_admin_secret()`
- [ ] `shellcheck -S warning scripts/plugins/argocd.sh` → zero warnings
- [ ] `bash -n scripts/plugins/argocd.sh` clean
- [ ] `bats scripts/tests/plugins/argocd_servicemonitors_ensure.bats` → 3/3
- [ ] `git show --stat` shows exactly one file changed
- [ ] Committed and pushed to `k3d-manager-v1.17.0`
- [ ] memory-bank updated with commit SHA and task status (separate commit from the code)

**Commit message (exact):**
```
refactor(argocd): remove orphaned enable_vault local + restore fn separator
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/plugins/argocd.sh`
- Do NOT remove or edit `enable_ldap` — it is still used
- Do NOT commit to `main` — work on `k3d-manager-v1.17.0`
