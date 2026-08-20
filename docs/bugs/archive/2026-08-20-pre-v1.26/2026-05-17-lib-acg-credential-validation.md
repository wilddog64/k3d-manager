# Bug: lib-acg — `bin/acg-credential-test` does not validate extracted AWS credentials

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `bin/acg-credential-test` — add `aws sts get-caller-identity` validation after extraction

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

`bin/acg-credential-test` uses `exec node ...` so the shell exits when Node exits. There is
no post-extraction check. Callers only discover invalid credentials later (e.g. `aws s3 ls`
→ `InvalidAccessKeyId`). The test harness should fail loudly at extraction time, not
silently succeed and leave the caller with broken credentials.

**Root cause:** `exec node` replaces the shell process — no code can run after Node exits.
The fix removes `exec` so the shell regains control, then validates the extracted AWS
credentials with `aws sts get-caller-identity` before exiting 0.

---

## Fix

### Change 1 — `bin/acg-credential-test`: validate AWS credentials after extraction

**Exact old block (entire file):**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi

sandbox_url="${1:?Usage: $0 <sandbox-url> [--provider aws|gcp]}"
shift

exec node "$REPO_ROOT/playwright/acg_credentials.js" "$sandbox_url" "$@"
```

**Exact new block (entire file):**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi

sandbox_url="${1:?Usage: $0 <sandbox-url> [--provider aws|gcp]}"
shift

_tmpout=$(mktemp)
trap 'rm -f "$_tmpout"' EXIT

node "$REPO_ROOT/playwright/acg_credentials.js" "$sandbox_url" "$@" | tee "$_tmpout"

if grep -q '^AWS_ACCESS_KEY_ID=' "$_tmpout"; then
  _key_id=$(grep '^AWS_ACCESS_KEY_ID=' "$_tmpout" | cut -d= -f2-)
  _secret=$(grep '^AWS_SECRET_ACCESS_KEY=' "$_tmpout" | cut -d= -f2-)
  _token=$(grep '^AWS_SESSION_TOKEN=' "$_tmpout" | cut -d= -f2- || true)

  _validate_aws() {
    local -a _env=(
      AWS_ACCESS_KEY_ID="$1"
      AWS_SECRET_ACCESS_KEY="$2"
    )
    [[ -n "${3:-}" ]] && _env+=(AWS_SESSION_TOKEN="$3")
    env "${_env[@]}" aws sts get-caller-identity >/dev/null 2>&1
  }

  if _validate_aws "$_key_id" "$_secret" "$_token"; then
    printf 'INFO: AWS credentials validated (sts:GetCallerIdentity OK)\n' >&2
  else
    printf 'ERROR: AWS credentials are invalid — sts:GetCallerIdentity failed\n' >&2
    exit 1
  fi
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-credential-test` | Remove `exec`; pipe node output through `tee`; validate AWS creds with `sts:GetCallerIdentity` |

---

## Rules

- `shellcheck -S warning bin/acg-credential-test` — zero warnings
- GCP flow (no `AWS_ACCESS_KEY_ID` in output) must pass through without calling `aws`
- No other files modified

---

## Definition of Done

- [ ] `exec node` replaced with `node ... | tee "$_tmpout"`
- [ ] `mktemp` + `trap rm` pattern used for temp file cleanup
- [ ] `_validate_aws` function uses `env` array — no `eval`, no bare variable expansion
- [ ] AWS session token included in validation env when present, omitted when absent
- [ ] GCP-only output (no `AWS_ACCESS_KEY_ID`) skips validation entirely
- [ ] `shellcheck -S warning bin/acg-credential-test` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(bin): validate AWS credentials with sts:GetCallerIdentity after extraction
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-credential-test`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT use `eval` to expand credential variables
- Do NOT touch `bin/acg-extend-test` — no validation needed there
