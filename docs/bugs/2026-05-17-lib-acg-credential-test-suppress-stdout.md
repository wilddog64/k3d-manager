# Bug: lib-acg — `bin/acg-credential-test` prints AWS credentials to terminal via `tee`

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `bin/acg-credential-test` — replace `tee "$_tmpout"` with `> "$_tmpout"` to suppress credential stdout

---

## Before You Start

```
git -C ~/src/gitrepo/personal/lib-acg fetch origin
git -C ~/src/gitrepo/personal/lib-acg checkout fix/acg-credentials-extend-dialog
git -C ~/src/gitrepo/personal/lib-acg pull origin fix/acg-credentials-extend-dialog
```

Read this spec in full before touching any file.

---

## Problem

`bin/acg-credential-test` captures node script stdout via `tee "$_tmpout"`. `tee` writes to both the temp file AND the terminal, so `AWS_ACCESS_KEY_ID=...` and `AWS_SECRET_ACCESS_KEY=...` appear in plain text in the terminal output.

**Root cause:** Line 18 uses `tee` instead of a plain redirect:

```bash
node "$REPO_ROOT/playwright/acg_credentials.js" "$sandbox_url" "$@" | tee "$_tmpout"
```

`tee` is unnecessary here — the only consumer of the temp file is the `grep` on line 20. There is no need to echo credentials to the terminal.

---

## Fix

### Change 1 — `bin/acg-credential-test`: replace `tee` with plain redirect

**Exact old line (line 18):**

```bash
node "$REPO_ROOT/playwright/acg_credentials.js" "$sandbox_url" "$@" | tee "$_tmpout"
```

**Exact new line:**

```bash
node "$REPO_ROOT/playwright/acg_credentials.js" "$sandbox_url" "$@" > "$_tmpout"
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-credential-test` | `tee "$_tmpout"` → `> "$_tmpout"` — suppress credential stdout |

---

## Rules

- `shellcheck -S warning bin/acg-credential-test` — zero new warnings
- No other files modified

---

## Definition of Done

- [ ] Line 18: `| tee "$_tmpout"` replaced with `> "$_tmpout"`
- [ ] `shellcheck -S warning bin/acg-credential-test` passes with zero new warnings
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat` output

**Commit message (exact):**
```
fix(bin): suppress credential stdout — replace tee with plain redirect
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-credential-test`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT remove or redirect stderr — INFO/WARN/ERROR logs must still appear in the terminal
- Do NOT touch `playwright/acg_credentials.js` or `acg_extend.js`
