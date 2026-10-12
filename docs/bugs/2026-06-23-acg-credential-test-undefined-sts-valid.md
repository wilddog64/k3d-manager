# Bugfix: v0.4.1 — `acg-credential-test` calls undefined `_sts_valid`

**Branch:** `feat/v0.4.1`
**Files:** `scripts/lib/acg/bin/acg-credential-test`

---

## Problem

`scripts/lib/acg/bin/acg-credential-test:277` calls `_sts_valid`, a function that is **never defined** anywhere in the script. Under `set -e`/strict invocation the unknown command exits 127; the `! _sts_valid` test therefore evaluates **always-true**, so the Step-2 branch fires on every happy-path run — triggering an unnecessary sandbox delete/restart + credential re-extraction even when the freshly-extracted AWS credentials are already valid.

**Root cause:** Imported verbatim from lib-acg (`7708ae31`); the helper was referenced but never carried over (or never existed). Pre-existing — NOT a PR #32 regression.

The real validation already exists inline as the final gate at line 292:
`AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity >/dev/null 2>&1`.

---

## Reproduction

`make credential-test PROVIDER=aws` with a valid, freshly-extracted sandbox: observe `WARN: sts:GetCallerIdentity failed — restarting sandbox...` followed by a spurious restart, despite the final gate then reporting `INFO: AWS credentials validated (sts:GetCallerIdentity OK)`.

---

## Fix

### Change 1 — `scripts/lib/acg/bin/acg-credential-test`: replace the undefined call with the canonical inline sts probe (matches line 292)

**Exact old block (line 277):**

```bash
  if ! _sts_valid; then
```

**Exact new block:**

```bash
  if ! AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity >/dev/null 2>&1; then
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/bin/acg-credential-test` | Replace undefined `_sts_valid` with inline `aws sts get-caller-identity` probe |

---

## Rules

- `shellcheck -S warning scripts/lib/acg/bin/acg-credential-test` — zero new warnings
- `bash -n scripts/lib/acg/bin/acg-credential-test` — parses
- No other files touched

---

## Definition of Done

- [ ] Single line replaced exactly as above
- [ ] `shellcheck` + `bash -n` pass
- [ ] CHANGE.md `[Unreleased]` notes the fix
- [ ] Committed and pushed to `feat/v0.4.1`

**Commit message (exact):**
```
fix(acg): replace undefined _sts_valid with inline aws sts probe in acg-credential-test
```
